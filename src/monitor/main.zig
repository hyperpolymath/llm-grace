// SPDX-License-Identifier: MPL-2.0
// Explicitly invoked read-only host observer; no auto-start or enforcement.
const std = @import("std");
const sampler = @import("sampler");
const monitor = @import("monitor");
const c = @cImport({
    @cInclude("time.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

const default_interval_seconds: u64 = 10;
const maximum_interval_seconds: u64 = 3600;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);
    var interval_seconds = default_interval_seconds;
    var sample_count: u64 = 0; // zero means continue until interrupted
    var lock_override: ?[]const u8 = null;
    var once = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try writeLine(allocator,
                \\llm-grace-monitor 0.1.0
                \\Read-only host observer. No signals, hooks, process writes, or auto-start.
                \\Usage: llm-grace-monitor [--once] [--count N] [--interval-seconds N] [--lock-file PATH]
                \\Requires XDG_RUNTIME_DIR to refer to a user-private (0700) directory unless --lock-file is provided.
                \\An initial sample has no delta baseline and is reported as invalid:missing.
            , .{});
            return;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-V")) {
            try writeLine(allocator, "llm-grace-monitor 0.1.0\n", .{});
            return;
        } else if (std.mem.eql(u8, arg, "--once")) {
            once = true;
            sample_count = 1;
        } else if (std.mem.eql(u8, arg, "--count")) {
            i += 1;
            if (i >= args.len) return error.MissingCount;
            sample_count = try std.fmt.parseInt(u64, args[i], 10);
            if (sample_count == 0) return error.InvalidCount;
        } else if (std.mem.eql(u8, arg, "--interval-seconds")) {
            i += 1;
            if (i >= args.len) return error.MissingInterval;
            interval_seconds = try std.fmt.parseInt(u64, args[i], 10);
            if (interval_seconds == 0 or interval_seconds > maximum_interval_seconds) return error.InvalidInterval;
        } else if (std.mem.eql(u8, arg, "--lock-file")) {
            i += 1;
            if (i >= args.len) return error.MissingLockPath;
            lock_override = args[i];
        } else {
            try writeLine(allocator, "ERROR: unknown option: {s}\n", .{arg});
            return error.InvalidArgument;
        }
    }
    if (once) sample_count = 1;

    const lock_path = if (lock_override) |path|
        try allocator.dupeZ(u8, path)
    else blk: {
        const runtime_dir = try std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR");
        try verifyPrivateRuntimeDir(allocator, runtime_dir);
        break :blk try std.fmt.allocPrintSentinel(allocator, "{s}/llm-grace-monitor.lock", .{runtime_dir}, 0);
    };

    const interval_ns = interval_seconds * std.time.ns_per_s;
    var observer = try monitor.ReadOnlyMonitor.init(allocator, lock_path.ptr, interval_ns);
    defer observer.deinit();

    var sequence: u64 = 0;
    while (sample_count == 0 or sequence < sample_count) {
        const now_ns = try monotonicNowNs();
        const observation = try observer.sampleHost(now_ns);
        sequence += 1;
        switch (observation) {
            .valid => |snapshot| {
                const load_centi = @as(u64, @intFromFloat(snapshot.load1 * 100));
                try writeLine(
                    allocator,
                    "{{\"sequence\":{d},\"monotonic_ns\":{d},\"status\":\"valid\",\"classification\":\"{s}\",\"mem_available_kb\":{d},\"mem_slope_kbps\":{d},\"swap_free_kb\":{d},\"pswpout_delta\":{d},\"iowait_pct\":{d},\"disk_busy_pct\":{d},\"load1_centi\":{d},\"nproc\":{d},\"cpu_user_pct\":{d}}}\n",
                    .{ sequence, now_ns, @tagName(sampler.classify(snapshot)), snapshot.mem_available_kb, snapshot.mem_available_slope_kbps, snapshot.swap_free_kb, snapshot.pswpout_delta, snapshot.iowait_pct, snapshot.io_ticks_pct, load_centi, snapshot.nproc, snapshot.cpu_user_pct },
                );
            },
            .invalid => |reason| try writeLine(allocator, "{{\"sequence\":{d},\"monotonic_ns\":{d},\"status\":\"invalid\",\"reason\":\"{s}\"}}\n", .{ sequence, now_ns, @tagName(reason) }),
            .stale => |reason| try writeLine(allocator, "{{\"sequence\":{d},\"monotonic_ns\":{d},\"status\":\"stale\",\"reason\":\"{s}\"}}\n", .{ sequence, now_ns, @tagName(reason) }),
        }
        if (sample_count == 0 or sequence < sample_count) std.Thread.sleep(interval_ns);
    }
}

fn verifyPrivateRuntimeDir(allocator: std.mem.Allocator, path: []const u8) !void {
    const zpath = try allocator.dupeZ(u8, path);
    var metadata: c.struct_stat = undefined;
    if (c.lstat(zpath, &metadata) != 0) return error.RuntimeDirectoryUnavailable;
    if ((metadata.st_mode & c.S_IFMT) != c.S_IFDIR or
        (metadata.st_mode & @as(c_uint, 0o077)) != 0 or
        metadata.st_uid != c.geteuid()) return error.UntrustedRuntimeDirectory;
}

fn monotonicNowNs() !u64 {
    var value: c.struct_timespec = undefined;
    if (c.clock_gettime(c.CLOCK_MONOTONIC, &value) != 0) return error.MonotonicClockUnavailable;
    const seconds: u64 = @intCast(value.tv_sec);
    const nanoseconds: u64 = @intCast(value.tv_nsec);
    return seconds * std.time.ns_per_s + nanoseconds;
}

fn writeLine(allocator: std.mem.Allocator, comptime format: []const u8, values: anytype) !void {
    const bytes = try std.fmt.allocPrint(allocator, format, values);
    var written: usize = 0;
    while (written < bytes.len) {
        const result = c.write(1, bytes[written..].ptr, bytes.len - written);
        if (result <= 0) return error.OutputFailure;
        written += @intCast(result);
    }
}
