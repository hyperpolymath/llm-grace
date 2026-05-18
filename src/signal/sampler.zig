// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan Jewell (hyperpolymath)
//
// llm-grace — /proc sampler.
//
// Pure parsing + reduction: text in, `classifier.Snapshot` out. No file
// I/O here (a thin caller reads /proc and passes the text), so every
// path is fixture-testable without root, a balloon, or a real box.

const std = @import("std");
const cls = @import("classifier.zig");

/// Raw cumulative counters from one read of /proc.
pub const Raw = struct {
    mem_total_kb: u64 = 0,
    mem_available_kb: u64 = 0,
    swap_total_kb: u64 = 0,
    swap_free_kb: u64 = 0,
    pswpout: u64 = 0, // cumulative pages swapped out
    cpu_total: u64 = 0, // sum of cpu jiffies
    cpu_user: u64 = 0, // user + nice
    cpu_iowait: u64 = 0,
    io_ticks: u64 = 0, // ms spent doing I/O, summed over real disks
    load1: f32 = 0,
    nproc: u32 = 0,
};

fn kvKb(line: []const u8, key: []const u8) ?u64 {
    if (!std.mem.startsWith(u8, line, key)) return null;
    var it = std.mem.tokenizeAny(u8, line[key.len..], " \t");
    const v = it.next() orelse return null;
    return std.fmt.parseInt(u64, v, 10) catch null;
}

pub fn parseMeminfo(text: []const u8, r: *Raw) void {
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |ln| {
        if (kvKb(ln, "MemTotal:")) |v| r.mem_total_kb = v;
        if (kvKb(ln, "MemAvailable:")) |v| r.mem_available_kb = v;
        if (kvKb(ln, "SwapTotal:")) |v| r.swap_total_kb = v;
        if (kvKb(ln, "SwapFree:")) |v| r.swap_free_kb = v;
    }
}

pub fn parseVmstatPswpout(text: []const u8) u64 {
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |ln| {
        if (std.mem.startsWith(u8, ln, "pswpout ")) {
            var it = std.mem.tokenizeAny(u8, ln["pswpout ".len..], " \t");
            if (it.next()) |v| return std.fmt.parseInt(u64, v, 10) catch 0;
        }
    }
    return 0;
}

pub fn parseStat(text: []const u8, r: *Raw) void {
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |ln| {
        if (std.mem.startsWith(u8, ln, "cpu ")) {
            var it = std.mem.tokenizeAny(u8, ln[4..], " \t");
            var i: usize = 0;
            var total: u64 = 0;
            var user: u64 = 0;
            var iowait: u64 = 0;
            while (it.next()) |tok| : (i += 1) {
                const n = std.fmt.parseInt(u64, tok, 10) catch break;
                if (i < 8) total += n; // user nice system idle iowait irq softirq steal
                if (i == 0 or i == 1) user += n; // user + nice
                if (i == 4) iowait = n;
            }
            r.cpu_total = total;
            r.cpu_user = user;
            r.cpu_iowait = iowait;
        } else if (ln.len > 3 and std.mem.startsWith(u8, ln, "cpu") and
            (ln[3] >= '0' and ln[3] <= '9'))
        {
            r.nproc += 1;
        }
    }
}

pub fn parseLoadavg(text: []const u8) f32 {
    var it = std.mem.tokenizeAny(u8, text, " \t\n");
    const v = it.next() orelse return 0;
    return std.fmt.parseFloat(f32, v) catch 0;
}

pub fn parseDiskstats(text: []const u8) u64 {
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    var sum: u64 = 0;
    while (lines.next()) |ln| {
        var it = std.mem.tokenizeAny(u8, ln, " \t");
        var fields: [20][]const u8 = undefined;
        var n: usize = 0;
        while (it.next()) |tok| {
            if (n >= fields.len) break;
            fields[n] = tok;
            n += 1;
        }
        if (n < 13) continue;
        const name = fields[2];
        if (std.mem.startsWith(u8, name, "loop") or
            std.mem.startsWith(u8, name, "ram")) continue;
        // /proc/diskstats: after major minor name, field 10 (1-based)
        // = ms doing I/O => token index 2 + 10 = 12.
        sum += std.fmt.parseInt(u64, fields[12], 10) catch 0;
    }
    return sum;
}

pub fn sample(meminfo: []const u8, vmstat: []const u8, stat: []const u8, loadavg: []const u8, diskstats: []const u8) Raw {
    var r = Raw{};
    parseMeminfo(meminfo, &r);
    r.pswpout = parseVmstatPswpout(vmstat);
    parseStat(stat, &r);
    r.load1 = parseLoadavg(loadavg);
    r.io_ticks = parseDiskstats(diskstats);
    return r;
}

fn pct(part: u64, whole: u64) u8 {
    if (whole == 0) return 0;
    const v = part * 100 / whole;
    return @intCast(@min(v, 100));
}

/// Reduce two raw samples + the wall interval into a classifier Snapshot.
pub fn reduce(prev: Raw, cur: Raw, interval_ms: u64, gpu_util_pct: ?u8) cls.Snapshot {
    const d_total = if (cur.cpu_total > prev.cpu_total) cur.cpu_total - prev.cpu_total else 0;
    const d_user = if (cur.cpu_user > prev.cpu_user) cur.cpu_user - prev.cpu_user else 0;
    const d_iow = if (cur.cpu_iowait > prev.cpu_iowait) cur.cpu_iowait - prev.cpu_iowait else 0;
    const d_io_ms = if (cur.io_ticks > prev.io_ticks) cur.io_ticks - prev.io_ticks else 0;
    const d_pswp = if (cur.pswpout > prev.pswpout) cur.pswpout - prev.pswpout else 0;

    const slope: i64 = blk: {
        if (interval_ms == 0) break :blk 0;
        const cur_a: i64 = @intCast(cur.mem_available_kb);
        const prev_a: i64 = @intCast(prev.mem_available_kb);
        break :blk @divTrunc((cur_a - prev_a) * 1000, @as(i64, @intCast(interval_ms)));
    };

    return .{
        .mem_total_kb = cur.mem_total_kb,
        .mem_available_kb = cur.mem_available_kb,
        .mem_available_slope_kbps = slope,
        .swap_total_kb = cur.swap_total_kb,
        .swap_free_kb = cur.swap_free_kb,
        .pswpout_delta = d_pswp,
        .iowait_pct = pct(d_iow, d_total),
        .io_ticks_pct = if (interval_ms == 0) 0 else pct(d_io_ms, interval_ms),
        .load1 = cur.load1,
        .nproc = if (cur.nproc == 0) 1 else cur.nproc,
        .cpu_user_pct = pct(d_user, d_total),
        .gpu_util_pct = gpu_util_pct,
    };
}

// ---------------------------------------------------------------------
// Fixture tests: real-shaped /proc text -> Raw -> Snapshot -> State.
// ---------------------------------------------------------------------

test "parsers extract expected fields" {
    var r = Raw{};
    parseMeminfo(
        \\MemTotal:       16000000 kB
        \\MemFree:          100000 kB
        \\MemAvailable:     300000 kB
        \\SwapTotal:       8000000 kB
        \\SwapFree:         200000 kB
    , &r);
    try std.testing.expectEqual(@as(u64, 16000000), r.mem_total_kb);
    try std.testing.expectEqual(@as(u64, 300000), r.mem_available_kb);
    try std.testing.expectEqual(@as(u64, 200000), r.swap_free_kb);
    try std.testing.expectEqual(@as(u64, 51234), parseVmstatPswpout("nr_free_pages 12\npswpout 51234\npgfault 9\n"));
    try std.testing.expectApproxEqAbs(@as(f32, 42.0), parseLoadavg("42.00 30.10 10.05 9/1234 5678"), 0.001);

    var rs = Raw{};
    parseStat("cpu  100 0 50 700 50 0 0 0 0 0\ncpu0 1 2\ncpu1 3 4\nintr 9\n", &rs);
    try std.testing.expectEqual(@as(u32, 2), rs.nproc);
    try std.testing.expectEqual(@as(u64, 900), rs.cpu_total); // 100+0+50+700+50
    try std.testing.expectEqual(@as(u64, 100), rs.cpu_user);
    try std.testing.expectEqual(@as(u64, 50), rs.cpu_iowait);
    // diskstats: io_ticks is the 10th field after the device name.
    try std.testing.expectEqual(@as(u64, 5000), parseDiskstats("   8 0 sda 1 2 3 4 5 6 7 8 9 5000 11\n  7 0 loop0 1 2 3 4 5 6 7 8 9 9999 1\n"));
}

test "reduce + classify: swap-death signature end-to-end" {
    const prev = Raw{
        .mem_total_kb = 16_000_000, .mem_available_kb = 600_000,
        .swap_total_kb = 8_000_000, .swap_free_kb = 400_000,
        .pswpout = 100_000, .cpu_total = 100_000, .cpu_user = 5_000,
        .cpu_iowait = 1_000, .io_ticks = 50_000, .load1 = 40, .nproc = 20,
    };
    const cur = Raw{
        .mem_total_kb = 16_000_000, .mem_available_kb = 300_000,
        .swap_total_kb = 8_000_000, .swap_free_kb = 200_000,
        .pswpout = 145_000, .cpu_total = 101_000, .cpu_user = 5_080,
        .cpu_iowait = 1_600, .io_ticks = 59_800, .load1 = 42, .nproc = 20,
    };
    const snap = reduce(prev, cur, 10_000, null); // 10s interval
    try std.testing.expectEqual(@as(u64, 45_000), snap.pswpout_delta);
    try std.testing.expect(snap.iowait_pct >= 20);
    try std.testing.expect(snap.io_ticks_pct >= 80);
    try std.testing.expect(snap.cpu_user_pct <= 25);
    try std.testing.expect(snap.mem_available_slope_kbps < 0);
    try std.testing.expectEqual(cls.State.swap_death, cls.classify(snap));
}

test "reduce + classify: quiet box is friendly" {
    const prev = Raw{
        .mem_total_kb = 16_000_000, .mem_available_kb = 11_000_000,
        .swap_total_kb = 8_000_000, .swap_free_kb = 8_000_000,
        .pswpout = 7, .cpu_total = 100_000, .cpu_user = 30_000,
        .cpu_iowait = 2_000, .io_ticks = 10_000, .load1 = 6, .nproc = 20,
    };
    const cur = Raw{
        .mem_total_kb = 16_000_000, .mem_available_kb = 10_990_000,
        .swap_total_kb = 8_000_000, .swap_free_kb = 8_000_000,
        .pswpout = 7, .cpu_total = 101_000, .cpu_user = 30_450,
        .cpu_iowait = 2_040, .io_ticks = 10_250, .load1 = 6, .nproc = 20,
    };
    const snap = reduce(prev, cur, 10_000, 20);
    try std.testing.expectEqual(cls.State.friendly, cls.classify(snap));
}
