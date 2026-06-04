// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// SPDX-FileCopyrightText: 2026 Jonathan Jewell (hyperpolymath)
//
// llm-grace — pure pressure-signal classifier.
//
// Maps a snapshot of cheap /proc-derived counters to a pressure STATE.
// Pure: no I/O, no allocation, no clock. The scenario table in the
// tests below is the executable spec (ADR-0003). Read it first.

const std = @import("std");

/// What kind of trouble the box is in — interpreted signatures, not a
/// single threshold (ADR-0003).
pub const State = enum {
    /// Normal headroom. Do nothing.
    friendly,
    /// MemAvailable collapsing fast even before swap moves. Shed gently/proactively.
    memory_cliff,
    /// Pre-OOM "disk-thrash + low CPU" signature. Shed hard and fast.
    swap_death,
    /// High CPU, load ~= cores, low iowait, memory flat. Busy, NOT dangerous — do not shed.
    compute_saturated,
    /// VRAM/util pinned, RAM fine. Training by design — informational only, never a shed trigger.
    gpu_saturated,
    /// Near-zero CPU + near-zero I/O. Parked/waiting — safest possible pause target.
    idle_tell,
};

/// A snapshot of signals derived over one sample interval. All counter
/// fields are already reduced to deltas/percentages by the sampler.
pub const Snapshot = struct {
    mem_total_kb: u64,
    mem_available_kb: u64,
    /// kB/s; negative = MemAvailable falling.
    mem_available_slope_kbps: i64,
    swap_total_kb: u64,
    swap_free_kb: u64,
    /// Pages swapped OUT during the interval (vmstat pswpout delta). >0 = active eviction.
    pswpout_delta: u64,
    /// % of interval the CPU spent in iowait.
    iowait_pct: u8,
    /// % of interval the disk was busy (diskstats io_ticks).
    io_ticks_pct: u8,
    /// 1-minute load average.
    load1: f32,
    nproc: u32,
    /// Userspace CPU %.
    cpu_user_pct: u8,
    /// GPU utilisation %, or null if unknown/unsampled.
    gpu_util_pct: ?u8,
};

/// Session-local attention/motion signals from ADR-0003/ADR-0004.
/// This is separate from machine pressure: it decides whether the
/// persisted attention target is still eligible to be the protected drum.
pub const SessionSignals = struct {
    /// True when this session is the last UserPromptSubmit target. ADR-0004
    /// says this attention marker persists; it does not decay by timer.
    attention_persisted: bool,
    /// True when RSS/working set puts this session in the "heavy" row.
    heavy_rss: bool,
    /// True when passive transcript observation shows progress.
    transcript_advanced: bool,
    /// CPU-active override from ADR-0003: a hot child still counts as moving
    /// even if the transcript is briefly quiet.
    cpu_active: bool = false,
};

pub const SessionClass = enum {
    /// Last-attention target is heavy and moving: protect it last.
    protected_drum,
    /// Heavy but not moving: pause/checkpoint first; never protected by size.
    heat_no_motion,
    /// Heavy and moving, but not the persisted attention target.
    heavy_moving_unfocused,
    /// Light work that is still making progress.
    light_moving,
    /// Light and stalled/quiet: cheapest pause target.
    idle_waiting,
};

pub fn sessionMoving(s: SessionSignals) bool {
    return s.transcript_advanced or s.cpu_active;
}

pub fn classifySession(s: SessionSignals) SessionClass {
    const moving = sessionMoving(s);
    if (s.heavy_rss) {
        if (!moving) return .heat_no_motion;
        if (s.attention_persisted) return .protected_drum;
        return .heavy_moving_unfocused;
    }
    if (moving) return .light_moving;
    return .idle_waiting;
}

pub fn protectsPersistedDrum(s: SessionSignals) bool {
    return classifySession(s) == .protected_drum;
}

// Named, visible thresholds (legibility > magic numbers).
const MEM_CLIFF_FRAC_NUM = 1; // MemAvailable < 10% of total => cliff
const MEM_CLIFF_FRAC_DEN = 10;
const MEM_CLIFF_SLOPE_KBPS: i64 = -50_000; // falling faster than ~50 MB/s
const SWAP_IOWAIT_HI: u8 = 20;
const SWAP_IOTICKS_HI: u8 = 80;
const SWAP_LOAD_MULT: f32 = 1.5; // load1 > nproc * 1.5
const SWAP_CPU_LO: u8 = 25; // userspace CPU low while thrashing
const GPU_HI: u8 = 90;
const COMPUTE_CPU_HI: u8 = 85;
const COMPUTE_IOWAIT_LO: u8 = 10;
const IDLE_CPU: u8 = 3;
const IDLE_IO: u8 = 3;

fn memHealthy(s: Snapshot) bool {
    // Available is comfortably above the cliff fraction.
    return s.mem_available_kb * MEM_CLIFF_FRAC_DEN > s.mem_total_kb * MEM_CLIFF_FRAC_NUM;
}

pub fn classify(s: Snapshot) State {
    // Priority order matters: most dangerous signature first.

    // 1. Swap-death pre-OOM signature: actively evicting to disk AND
    //    disk-bound AND run-queue piled up AND userspace CPU is LOW
    //    (the "thrash, not work" tell). All clauses required.
    if (s.pswpout_delta > 0 and
        s.iowait_pct >= SWAP_IOWAIT_HI and
        s.io_ticks_pct >= SWAP_IOTICKS_HI and
        s.load1 > @as(f32, @floatFromInt(s.nproc)) * SWAP_LOAD_MULT and
        s.cpu_user_pct <= SWAP_CPU_LO)
    {
        return .swap_death;
    }

    // 2. Memory cliff: available collapsing fast, or already below the
    //    cliff fraction — even before swap moves. Proactive.
    if (!memHealthy(s) or s.mem_available_slope_kbps <= MEM_CLIFF_SLOPE_KBPS) {
        return .memory_cliff;
    }

    // 3. GPU saturated: pinned VRAM/util with RAM fine. Informational
    //    only — never a shed trigger (training by design).
    if (s.gpu_util_pct) |g| {
        if (g >= GPU_HI and memHealthy(s)) return .gpu_saturated;
    }

    // 4. Compute saturated: honest heavy work — high CPU, low iowait,
    //    memory fine. Busy, NOT dangerous. Must not be shed.
    if (s.cpu_user_pct >= COMPUTE_CPU_HI and
        s.iowait_pct < COMPUTE_IOWAIT_LO and
        memHealthy(s))
    {
        return .compute_saturated;
    }

    // 5. Idle tell: parked/waiting — the cheapest, safest pause target.
    if (s.cpu_user_pct <= IDLE_CPU and s.io_ticks_pct <= IDLE_IO) {
        return .idle_tell;
    }

    // 6. Default: healthy.
    return .friendly;
}

// ---------------------------------------------------------------------
// Scenario table = executable spec. Each row is a named, realistic
// snapshot and the state it MUST classify as.
// ---------------------------------------------------------------------

const Case = struct { name: []const u8, s: Snapshot, want: State };

const TABLE = [_]Case{
    .{
        .name = "swap-death pre-OOM signature (disk thrash + low CPU)",
        .s = .{
            .mem_total_kb = 16_000_000, .mem_available_kb = 300_000,
            .mem_available_slope_kbps = -120_000,
            .swap_total_kb = 8_000_000, .swap_free_kb = 200_000,
            .pswpout_delta = 45_000, .iowait_pct = 55, .io_ticks_pct = 98,
            .load1 = 42.0, .nproc = 20, .cpu_user_pct = 8, .gpu_util_pct = null,
        },
        .want = .swap_death,
    },
    .{
        .name = "memory cliff: available collapsing, swap not yet moving",
        .s = .{
            .mem_total_kb = 16_000_000, .mem_available_kb = 1_200_000,
            .mem_available_slope_kbps = -90_000,
            .swap_total_kb = 8_000_000, .swap_free_kb = 8_000_000,
            .pswpout_delta = 0, .iowait_pct = 5, .io_ticks_pct = 20,
            .load1 = 6.0, .nproc = 20, .cpu_user_pct = 40, .gpu_util_pct = null,
        },
        .want = .memory_cliff,
    },
    .{
        .name = "compute saturated: honest heavy build, NOT swap-death",
        .s = .{
            .mem_total_kb = 16_000_000, .mem_available_kb = 9_000_000,
            .mem_available_slope_kbps = -1_000,
            .swap_total_kb = 8_000_000, .swap_free_kb = 8_000_000,
            .pswpout_delta = 0, .iowait_pct = 6, .io_ticks_pct = 30,
            .load1 = 21.0, .nproc = 20, .cpu_user_pct = 96, .gpu_util_pct = null,
        },
        .want = .compute_saturated,
    },
    .{
        .name = "gpu saturated: training pins VRAM, RAM fine",
        .s = .{
            .mem_total_kb = 16_000_000, .mem_available_kb = 10_000_000,
            .mem_available_slope_kbps = 0,
            .swap_total_kb = 8_000_000, .swap_free_kb = 8_000_000,
            .pswpout_delta = 0, .iowait_pct = 2, .io_ticks_pct = 5,
            .load1 = 4.0, .nproc = 20, .cpu_user_pct = 30, .gpu_util_pct = 99,
        },
        .want = .gpu_saturated,
    },
    .{
        .name = "idle tell: parked, near-zero cpu and io",
        .s = .{
            .mem_total_kb = 16_000_000, .mem_available_kb = 12_000_000,
            .mem_available_slope_kbps = 0,
            .swap_total_kb = 8_000_000, .swap_free_kb = 8_000_000,
            .pswpout_delta = 0, .iowait_pct = 0, .io_ticks_pct = 1,
            .load1 = 0.2, .nproc = 20, .cpu_user_pct = 1, .gpu_util_pct = null,
        },
        .want = .idle_tell,
    },
    .{
        .name = "friendly: healthy normal operation",
        .s = .{
            .mem_total_kb = 16_000_000, .mem_available_kb = 11_000_000,
            .mem_available_slope_kbps = -2_000,
            .swap_total_kb = 8_000_000, .swap_free_kb = 8_000_000,
            .pswpout_delta = 0, .iowait_pct = 4, .io_ticks_pct = 25,
            .load1 = 6.0, .nproc = 20, .cpu_user_pct = 45, .gpu_util_pct = 20,
        },
        .want = .friendly,
    },
    .{
        .name = "heavy disk IO but mem fine + no swap-out: NOT swap-death",
        .s = .{
            .mem_total_kb = 16_000_000, .mem_available_kb = 8_000_000,
            .mem_available_slope_kbps = -3_000,
            .swap_total_kb = 8_000_000, .swap_free_kb = 8_000_000,
            .pswpout_delta = 0, .iowait_pct = 40, .io_ticks_pct = 95,
            .load1 = 18.0, .nproc = 20, .cpu_user_pct = 30, .gpu_util_pct = null,
        },
        .want = .friendly,
    },
};

test "scenario table: classifier matches the spec" {
    for (TABLE) |c| {
        const got = classify(c.s);
        std.testing.expectEqual(c.want, got) catch |e| {
            std.debug.print("FAIL [{s}]: want {any}, got {any}\n", .{ c.name, c.want, got });
            return e;
        };
    }
}

test "ADR-0004: persisted attention does not protect a heavy stalled drum" {
    const abandoned = SessionSignals{
        .attention_persisted = true,
        .heavy_rss = true,
        .transcript_advanced = false,
        .cpu_active = false,
    };

    try std.testing.expect(!sessionMoving(abandoned));
    try std.testing.expectEqual(SessionClass.heat_no_motion, classifySession(abandoned));
    try std.testing.expect(!protectsPersistedDrum(abandoned));

    const still_working = SessionSignals{
        .attention_persisted = true,
        .heavy_rss = true,
        .transcript_advanced = true,
    };
    try std.testing.expectEqual(SessionClass.protected_drum, classifySession(still_working));
    try std.testing.expect(protectsPersistedDrum(still_working));
}
