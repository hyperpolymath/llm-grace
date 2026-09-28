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
        var it = std.mem.tokenizeAny(u8, ln, " \t");
        if (std.mem.eql(u8, it.next() orelse continue, "pswpout")) {
            if (it.next()) |v| return std.fmt.parseInt(u64, v, 10) catch 0;
        }
    }
    return 0;
}

pub fn parseStat(text: []const u8, r: *Raw) void {
    r.nproc = 0;
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
                if (i < 8) total +|= n; // user nice system idle iowait irq softirq steal
                if (i == 0 or i == 1) user +|= n; // user + nice
                if (i == 4) iowait = n;
            }
            r.cpu_total = total;
            r.cpu_user = user;
            r.cpu_iowait = iowait;
        } else if (ln.len > 3 and std.mem.startsWith(u8, ln, "cpu") and
            (ln[3] >= '0' and ln[3] <= '9'))
        {
            r.nproc +|= 1;
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
        sum +|= std.fmt.parseInt(u64, fields[12], 10) catch 0;
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

/// Checked entry point for monitor use. Missing data is never a healthy or
/// dangerous observation. The caller must retain/report an unknown state.
/// diskstats must contain only caller-selected, non-overlapping whole devices.
/// An empty selection (e.g. no block devices) is valid and yields zero activity.
pub fn sampleChecked(meminfo: []const u8, vmstat: []const u8, stat: []const u8, loadavg: []const u8, diskstats: []const u8) !Raw {
    const keys = [_][]const u8{ "MemTotal:", "MemAvailable:", "SwapTotal:", "SwapFree:" };
    for (keys) |key| {
        var seen: usize = 0;
        var lines = std.mem.tokenizeScalar(u8, meminfo, '\n');
        while (lines.next()) |line| {
            if (!std.mem.startsWith(u8, line, key)) continue;
            seen += 1;
            var fields = std.mem.tokenizeAny(u8, line[key.len..], " \t");
            _ = try std.fmt.parseInt(u64, fields.next() orelse return error.InvalidSample, 10);
            if (!std.mem.eql(u8, fields.next() orelse return error.InvalidSample, "kB")) return error.InvalidSample;
        }
        if (seen != 1) return error.InvalidSample;
    }
    var vm_lines = std.mem.tokenizeScalar(u8, vmstat, '\n');
    var swaps: usize = 0;
    while (vm_lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        if (!std.mem.eql(u8, fields.next() orelse continue, "pswpout")) continue;
        swaps += 1;
        _ = try std.fmt.parseInt(u64, fields.next() orelse return error.InvalidSample, 10);
    }
    if (swaps != 1) return error.InvalidSample;
    var cpu_lines = std.mem.tokenizeScalar(u8, stat, '\n');
    var cpus: usize = 0;
    while (cpu_lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        if (!std.mem.eql(u8, fields.next() orelse continue, "cpu")) continue;
        cpus += 1;
        var count: usize = 0;
        var total: u64 = 0;
        while (fields.next()) |field| : (count += 1) {
            const n = try std.fmt.parseInt(u64, field, 10);
            if (count < 8) total = try std.math.add(u64, total, n);
        }
        if (count < 5) return error.InvalidSample;
    }
    if (cpus != 1) return error.InvalidSample;
    var load_fields = std.mem.tokenizeAny(u8, loadavg, " \t\n");
    const load = try std.fmt.parseFloat(f32, load_fields.next() orelse return error.InvalidSample);
    if (!std.math.isFinite(load) or load < 0) return error.InvalidSample;
    const raw = sample(meminfo, vmstat, stat, loadavg, diskstats);
    if (raw.mem_total_kb == 0 or raw.mem_available_kb > raw.mem_total_kb or
        raw.swap_free_kb > raw.swap_total_kb or raw.nproc == 0 or raw.cpu_total == 0) return error.InvalidSample;
    return raw;
}

fn pct(part: u64, whole: u64) u8 {
    if (whole == 0) return 0;
    const v = @as(u128, part) * 100 / whole;
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
        const delta = @as(i128, cur.mem_available_kb) - @as(i128, prev.mem_available_kb);
        const rate = @divTrunc(delta * 1000, @as(i128, interval_ms));
        break :blk @intCast(std.math.clamp(rate, std.math.minInt(i64), std.math.maxInt(i64)));
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
        .mem_total_kb = 16_000_000,
        .mem_available_kb = 600_000,
        .swap_total_kb = 8_000_000,
        .swap_free_kb = 400_000,
        .pswpout = 100_000,
        .cpu_total = 100_000,
        .cpu_user = 5_000,
        .cpu_iowait = 1_000,
        .io_ticks = 50_000,
        .load1 = 40,
        .nproc = 20,
    };
    const cur = Raw{
        .mem_total_kb = 16_000_000,
        .mem_available_kb = 300_000,
        .swap_total_kb = 8_000_000,
        .swap_free_kb = 200_000,
        .pswpout = 145_000,
        .cpu_total = 101_000,
        .cpu_user = 5_080,
        .cpu_iowait = 1_600,
        .io_ticks = 59_800,
        .load1 = 42,
        .nproc = 20,
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
        .mem_total_kb = 16_000_000,
        .mem_available_kb = 11_000_000,
        .swap_total_kb = 8_000_000,
        .swap_free_kb = 8_000_000,
        .pswpout = 7,
        .cpu_total = 100_000,
        .cpu_user = 30_000,
        .cpu_iowait = 2_000,
        .io_ticks = 10_000,
        .load1 = 6,
        .nproc = 20,
    };
    const cur = Raw{
        .mem_total_kb = 16_000_000,
        .mem_available_kb = 10_990_000,
        .swap_total_kb = 8_000_000,
        .swap_free_kb = 8_000_000,
        .pswpout = 7,
        .cpu_total = 101_000,
        .cpu_user = 30_450,
        .cpu_iowait = 2_040,
        .io_ticks = 10_250,
        .load1 = 6,
        .nproc = 20,
    };
    const snap = reduce(prev, cur, 10_000, 20);
    try std.testing.expectEqual(cls.State.friendly, cls.classify(snap));
}

test "checked samples reject missing, contradictory and non-finite evidence" {
    const mem = "MemTotal: 1000 kB\nMemAvailable: 500 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n";
    const cpu = "cpu 1 2 3 4 5 6 7 8\ncpu0 1 2\n";
    const valid = try sampleChecked(mem, "pswpout\t42", cpu, "0.5", "");
    try std.testing.expectEqual(@as(u64, 42), valid.pswpout);
    try std.testing.expectError(error.InvalidSample, sampleChecked("", "pswpout 0", cpu, "0", ""));
    try std.testing.expectError(error.InvalidSample, sampleChecked(mem, "", cpu, "0", ""));
    try std.testing.expectError(error.InvalidSample, sampleChecked(mem, "pswpout 0", "cpu 1 2", "0", ""));
    try std.testing.expectError(error.InvalidSample, sampleChecked(mem, "pswpout 0", cpu, "nan", ""));
    try std.testing.expectError(error.InvalidSample, sampleChecked(mem, "pswpout 0", cpu, "-1", ""));
}

test "wide arithmetic is bounded for extreme observations" {
    const max = std.math.maxInt(u64);
    try std.testing.expectEqual(@as(u8, 100), pct(max, max));
    try std.testing.expectEqual(@as(u8, 100), pct(max, 1));
    const snap = reduce(.{}, .{ .mem_available_kb = max }, 1, null);
    try std.testing.expectEqual(std.math.maxInt(i64), snap.mem_available_slope_kbps);
    const falling = reduce(.{ .mem_available_kb = max }, .{}, 1, null);
    try std.testing.expectEqual(std.math.minInt(i64), falling.mem_available_slope_kbps);
    _ = reduce(.{}, .{ .mem_available_kb = max }, max, null);
}

test "CPU count does not accumulate when parser target is reused" {
    var raw = Raw{};
    parseStat("cpu 1 2 3 4 5\ncpu0 1 2", &raw);
    parseStat("cpu 1 2 3 4 5\ncpu0 1 2", &raw);
    try std.testing.expectEqual(@as(u32, 1), raw.nproc);
}

/// Maximum device utilisation, not a sum across disks/partitions. Caller selects
/// non-overlapping whole devices (for example from sysfs) once per sample pair.
/// Missing/replaced devices and counter resets invalidate the interval.
pub fn diskBusyPercent(previous: []const u8, current: []const u8, devices: []const []const u8, interval_ms: u64) !u8 {
    if (interval_ms == 0) return error.InvalidInterval;
    var busy: u8 = 0;
    for (devices, 0..) |device, i| {
        for (devices[0..i]) |other| {
            if (std.mem.eql(u8, device, other)) return error.DuplicateDevice;
        }
        const before = try deviceTicks(previous, device);
        const after = try deviceTicks(current, device);
        if (after < before) return error.CounterReset;
        busy = @max(busy, pct(after - before, interval_ms));
    }
    return busy;
}

fn deviceTicks(text: []const u8, device: []const u8) !u64 {
    var result: ?u64 = null;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        _ = fields.next() orelse continue;
        _ = fields.next() orelse return error.InvalidSample;
        const name = fields.next() orelse return error.InvalidSample;
        if (!std.mem.eql(u8, name, device)) continue;
        if (result != null) return error.DuplicateDevice;
        for (0..9) |_| _ = fields.next() orelse return error.InvalidSample;
        result = try std.fmt.parseInt(u64, fields.next() orelse return error.InvalidSample, 10);
    }
    return result orelse error.MissingDevice;
}

/// Use with sampleChecked and diskBusyPercent. Unknown/reset intervals must not
/// be used to resume a checkpoint or to manufacture a pressure classification.
pub fn reduceChecked(prev: Raw, cur: Raw, interval_ms: u64, disk_busy_pct: u8, gpu_util_pct: ?u8) !cls.Snapshot {
    if (interval_ms == 0) return error.InvalidInterval;
    if (disk_busy_pct > 100) return error.InvalidSample;
    if (gpu_util_pct) |g| if (g > 100) return error.InvalidSample;
    if (cur.nproc != prev.nproc or cur.cpu_total <= prev.cpu_total or
        cur.cpu_user < prev.cpu_user or cur.cpu_iowait < prev.cpu_iowait or
        cur.pswpout < prev.pswpout) return error.CounterReset;
    var snap = reduce(prev, cur, interval_ms, gpu_util_pct);
    snap.io_ticks_pct = disk_busy_pct;
    return snap;
}

test "disk saturation is per selected device, not a sum or partition double count" {
    const prev = "8 0 sda 0 0 0 0 0 0 0 0 0 0 0\n8 1 sda1 0 0 0 0 0 0 0 0 0 0 0\n8 16 sdb 0 0 0 0 0 0 0 0 0 0 0\n";
    const cur = "8 0 sda 0 0 0 0 0 0 0 0 0 500 0\n8 1 sda1 0 0 0 0 0 0 0 0 0 500 0\n8 16 sdb 0 0 0 0 0 0 0 0 0 500 0\n";
    try std.testing.expectEqual(@as(u8, 50), try diskBusyPercent(prev, cur, &.{ "sda", "sdb" }, 1000));
    try std.testing.expectError(error.DuplicateDevice, diskBusyPercent(prev, cur, &.{ "sda", "sda" }, 1000));
    try std.testing.expectError(error.MissingDevice, diskBusyPercent(prev, cur, &.{"nvme0n1"}, 1000));
    try std.testing.expectError(error.CounterReset, diskBusyPercent(cur, prev, &.{"sda"}, 1000));
    try std.testing.expectError(error.InvalidInterval, diskBusyPercent(prev, cur, &.{"sda"}, 0));
}

test "checked reduction rejects zero intervals, resets and CPU topology changes" {
    const before = Raw{ .cpu_total = 100, .cpu_user = 50, .nproc = 1 };
    const after = Raw{ .cpu_total = 200, .cpu_user = 60, .nproc = 1 };
    try std.testing.expectError(error.InvalidInterval, reduceChecked(before, after, 0, 0, null));
    try std.testing.expectError(error.CounterReset, reduceChecked(after, before, 1000, 0, null));
    var hotplug = after;
    hotplug.nproc = 2;
    try std.testing.expectError(error.CounterReset, reduceChecked(before, hotplug, 1000, 0, null));
    try std.testing.expectEqual(@as(u8, 55), (try reduceChecked(before, after, 1000, 55, null)).io_ticks_pct);
}
