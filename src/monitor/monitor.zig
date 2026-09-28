// SPDX-License-Identifier: MPL-2.0
// Read-only monitor primitives. This module never signals or writes to observed processes.
const std = @import("std");
const sampler = @import("sampler");
const c = @cImport({
    @cInclude("sys/file.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
});

pub const proc_read_limit: usize = 64 * 1024;
pub const default_period_ns: u64 = 10 * std.time.ns_per_s;
pub const session_stale_after_ns: u64 = 5 * 60 * std.time.ns_per_s;

pub const InvalidReason = enum { missing, oversized, malformed, contradictory, pid_reused, counter_reset, device_changed, io_error };
pub const StaleReason = enum { age_limit, no_motion };
pub fn Observation(comptime T: type) type {
    return union(enum) { valid: T, invalid: InvalidReason, stale: StaleReason };
}

/// Monotonic scheduling state. Wall time is intentionally not accepted here.
pub const Schedule = struct {
    period_ns: u64 = default_period_ns,
    last_sample_ns: ?u64 = null,

    pub fn due(self: *const Schedule, now_ns: u64) !bool {
        const last = self.last_sample_ns orelse return true;
        if (now_ns < last) return error.ClockRegressed;
        return now_ns - last >= self.period_ns;
    }

    pub fn sampled(self: *Schedule, now_ns: u64) !void {
        if (self.last_sample_ns) |last| if (now_ns < last) return error.ClockRegressed;
        self.last_sample_ns = now_ns;
    }
};

/// Acquire a non-blocking, kernel-released exclusive ownership lock. `path` must
/// be inside a trusted private directory. Keep the descriptor alive for the
/// monitor lifetime; do not unlink or replace the lock file.
pub const Ownership = struct {
    fd: c_int,

    pub fn acquire(path: [*:0]const u8) !Ownership {
        const fd = c.open(path, c.O_CREAT | c.O_RDWR | c.O_CLOEXEC, @as(c_uint, 0o600));
        if (fd < 0) return error.LockOpenFailed;
        if (c.flock(fd, c.LOCK_EX | c.LOCK_NB) != 0) {
            _ = c.close(fd);
            return error.AlreadyOwned;
        }
        return .{ .fd = fd };
    }

    pub fn release(self: *Ownership) void {
        _ = c.flock(self.fd, c.LOCK_UN);
        _ = c.close(self.fd);
        self.* = undefined;
    }
};

/// Read at most `limit` bytes (plus one probe byte), never an unbounded /proc
/// allocation. A file of exactly limit bytes is accepted; larger files fail.
pub fn readBounded(allocator: std.mem.Allocator, path: []const u8, limit: usize) ![]u8 {
    if (limit > proc_read_limit) return error.InvalidLimit;
    const zpath = try allocator.dupeZ(u8, path);
    defer allocator.free(zpath);
    var file = try std.fs.openFileAbsolute(zpath, .{});
    defer file.close();
    const buf = try allocator.alloc(u8, limit + 1);
    errdefer allocator.free(buf);
    const n = try file.readAll(buf);
    if (n > limit) return error.ReadLimitExceeded;
    return allocator.realloc(buf, n);
}

fn readFailure(err: anyerror) InvalidReason {
    return if (err == error.ReadLimitExceeded or err == error.InvalidLimit or err == error.TooManyDevices) .oversized else .io_error;
}

pub const Device = struct { name: []const u8, major_minor: []const u8 };
pub const DeviceCandidate = struct { name: []const u8, major_minor: []const u8, whole_device: bool };

/// Select only whole devices, in deterministic lexical order. Device identity
/// includes major:minor so a reused device name is not treated as the same disk.
pub fn selectDevices(allocator: std.mem.Allocator, candidates: []const DeviceCandidate) ![]Device {
    var selected: std.ArrayList(Device) = .empty;
    errdefer {
        for (selected.items) |device| {
            allocator.free(device.name);
            allocator.free(device.major_minor);
        }
        selected.deinit(allocator);
    }
    for (candidates) |candidate| {
        if (!candidate.whole_device or excludedDevice(candidate.name)) continue;
        if (candidate.name.len == 0 or candidate.major_minor.len == 0) return error.InvalidDevice;
        for (selected.items) |prior| {
            if (std.mem.eql(u8, prior.name, candidate.name) or std.mem.eql(u8, prior.major_minor, candidate.major_minor)) return error.DuplicateDevice;
        }
        const name = try allocator.dupe(u8, candidate.name);
        errdefer allocator.free(name);
        const identity = try allocator.dupe(u8, candidate.major_minor);
        errdefer allocator.free(identity);
        try selected.append(allocator, .{ .name = name, .major_minor = identity });
    }
    // Small device sets: insertion sort keeps ordering and allocation semantics simple.
    for (1..selected.items.len) |i| {
        var j = i;
        while (j > 0 and std.mem.order(u8, selected.items[j - 1].name, selected.items[j].name) == .gt) : (j -= 1) {
            std.mem.swap(Device, &selected.items[j - 1], &selected.items[j]);
        }
    }
    return try selected.toOwnedSlice(allocator);
}

pub fn freeDevices(allocator: std.mem.Allocator, devices: []Device) void {
    for (devices) |device| {
        allocator.free(device.name);
        allocator.free(device.major_minor);
    }
    allocator.free(devices);
}

/// Discover top-level /sys/block entries, read their kernel major:minor identity,
/// and retain only whole devices with a sysfs `device` link (physical/virtual
/// hardware endpoints, excluding stacked dm/md/loop devices). Entries exposing
/// a `partition` marker are also excluded. Re-read each epoch; identity changes
/// invalidate the interval. This is a conservative heuristic, not proof that
/// arbitrary storage topologies have no hidden overlap.
pub fn discoverBlockDevices(allocator: std.mem.Allocator) ![]Device {
    return discoverBlockDevicesAt(allocator, "/sys/block");
}

pub fn discoverBlockDevicesAt(allocator: std.mem.Allocator, sys_block_path: []const u8) ![]Device {
    const zpath = try allocator.dupeZ(u8, sys_block_path);
    defer allocator.free(zpath);
    var dir = try std.fs.openDirAbsolute(zpath, .{ .iterate = true });
    defer dir.close();
    var it = dir.iterate();
    var visited: usize = 0;
    var candidates: std.ArrayList(DeviceCandidate) = .empty;
    defer {
        for (candidates.items) |candidate| {
            allocator.free(candidate.name);
            allocator.free(candidate.major_minor);
        }
        candidates.deinit(allocator);
    }
    while (try it.next()) |entry| {
        visited += 1;
        if (visited > 512) return error.TooManyDevices;
        if (entry.kind != .directory and entry.kind != .sym_link) continue;
        if (candidates.items.len == 128) return error.TooManyDevices;
        const partition_path = try std.fmt.allocPrintSentinel(allocator, "{s}/{s}/partition", .{ sys_block_path, entry.name }, 0);
        defer allocator.free(partition_path);
        var whole = true;
        if (std.fs.openFileAbsolute(partition_path, .{})) |partition| {
            partition.close();
            whole = false;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
        if (!whole) continue;
        const hardware_path = try std.fmt.allocPrintSentinel(allocator, "{s}/{s}/device", .{ sys_block_path, entry.name }, 0);
        defer allocator.free(hardware_path);
        var hardware = std.fs.openDirAbsolute(hardware_path, .{}) catch |err| switch (err) {
            error.FileNotFound, error.NotDir => continue,
            else => return err,
        };
        hardware.close();
        const dev_path = try std.fmt.allocPrint(allocator, "{s}/{s}/dev", .{ sys_block_path, entry.name });
        defer allocator.free(dev_path);
        const dev_text = try readBounded(allocator, dev_path, 128);
        defer allocator.free(dev_text);
        const name = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(name);
        const identity = try allocator.dupe(u8, std.mem.trim(u8, dev_text, " \t\r\n"));
        errdefer allocator.free(identity);
        try candidates.append(allocator, .{ .name = name, .major_minor = identity, .whole_device = whole });
    }
    return selectDevices(allocator, candidates.items);
}

pub fn sameDevices(a: []const Device, b: []const Device) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (!std.mem.eql(u8, left.name, right.name) or !std.mem.eql(u8, left.major_minor, right.major_minor)) return false;
    }
    return true;
}

fn excludedDevice(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "loop") or std.mem.startsWith(u8, name, "ram") or
        std.mem.startsWith(u8, name, "zram") or std.mem.startsWith(u8, name, "fd");
}

pub const ProcessIdentity = struct { pid: u32, start_ticks: u64 };
pub const Motion = enum { moving, quiet, stale, unknown };
pub const SessionObservation = struct {
    identity: ProcessIdentity,
    rss_kb: u64,
    transcript_bytes: u64,
    motion: Motion,
    sampled_at_ns: u64,
};
pub const PreviousSession = struct { identity: ProcessIdentity, transcript_bytes: u64, changed_at_ns: u64 };

/// Parse Linux /proc/PID/stat. The comm field can contain spaces and ')' so
/// parsing starts after its final closing parenthesis. starttime is field 22.
pub fn parseProcessIdentity(text: []const u8) !ProcessIdentity {
    const open = std.mem.indexOfScalar(u8, text, '(') orelse return error.MalformedProcStat;
    const close = std.mem.lastIndexOfScalar(u8, text, ')') orelse return error.MalformedProcStat;
    if (close <= open or close + 2 >= text.len) return error.MalformedProcStat;
    const pid = try std.fmt.parseInt(u32, std.mem.trim(u8, text[0..open], " \t"), 10);
    var fields = std.mem.tokenizeAny(u8, text[close + 1 ..], " \t\n");
    _ = fields.next() orelse return error.MalformedProcStat; // state: field 3
    for (0..18) |_| _ = fields.next() orelse return error.MalformedProcStat; // fields 4..21
    const start = try std.fmt.parseInt(u64, fields.next() orelse return error.MalformedProcStat, 10);
    return .{ .pid = pid, .start_ticks = start };
}

pub fn parseRssKb(status: []const u8) !u64 {
    var found: ?u64 = null;
    var lines = std.mem.tokenizeScalar(u8, status, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "VmRSS:")) continue;
        if (found != null) return error.MalformedStatus;
        var fields = std.mem.tokenizeAny(u8, line[6..], " \t");
        const value = try std.fmt.parseInt(u64, fields.next() orelse return error.MalformedStatus, 10);
        if (!std.mem.eql(u8, fields.next() orelse return error.MalformedStatus, "kB")) return error.MalformedStatus;
        found = value;
    }
    return found orelse error.MissingRss;
}

/// Join two bounded stat reads around status/transcript metadata. A changed
/// starttime (or mismatch with the prior sample) explicitly rejects PID reuse.
pub fn observeSession(
    expected_identity: ProcessIdentity,
    stat_before: []const u8,
    status: []const u8,
    stat_after: []const u8,
    transcript_bytes: u64,
    now_ns: u64,
    previous: ?PreviousSession,
    stale_after_ns: u64,
) Observation(SessionObservation) {
    const before = parseProcessIdentity(stat_before) catch return .{ .invalid = .malformed };
    const after = parseProcessIdentity(stat_after) catch return .{ .invalid = .malformed };
    if (before.pid != expected_identity.pid or after.pid != expected_identity.pid) return .{ .invalid = .contradictory };
    if (before.start_ticks != after.start_ticks or before.start_ticks != expected_identity.start_ticks) return .{ .invalid = .pid_reused };
    if (previous) |prior| {
        if (prior.identity.pid != before.pid or prior.identity.start_ticks != before.start_ticks) return .{ .invalid = .pid_reused };
        if (now_ns < prior.changed_at_ns) return .{ .invalid = .counter_reset };
    }
    const rss = parseRssKb(status) catch |err| return .{ .invalid = if (err == error.MissingRss) .missing else .malformed };
    var motion: Motion = .unknown;
    if (previous) |prior| {
        if (transcript_bytes < prior.transcript_bytes) return .{ .invalid = .counter_reset };
        if (transcript_bytes > prior.transcript_bytes) {
            motion = .moving;
        } else if (now_ns - prior.changed_at_ns >= stale_after_ns) {
            motion = .stale;
        } else {
            motion = .quiet;
        }
    }
    return .{ .valid = .{ .identity = before, .rss_kb = rss, .transcript_bytes = transcript_bytes, .motion = motion, .sampled_at_ns = now_ns } };
}

/// Checked pairwise host sample: every counter/device set must be valid for
/// this epoch. The first sample has no delta and is explicitly invalid.
pub fn checkedSystemSample(
    previous_raw: ?sampler.Raw,
    previous_diskstats: []const u8,
    current_diskstats: []const u8,
    previous_devices: []const Device,
    current_devices: []const Device,
    meminfo: []const u8,
    vmstat: []const u8,
    stat: []const u8,
    loadavg: []const u8,
    interval_ns: u64,
    gpu_util_pct: ?u8,
) Observation(sampler.Snapshot) {
    if (previous_raw == null) return .{ .invalid = .missing };
    if (!sameDevices(previous_devices, current_devices)) return .{ .invalid = .device_changed };
    if (interval_ns == 0 or interval_ns % std.time.ns_per_ms != 0) return .{ .invalid = .malformed };
    const current = sampler.sampleChecked(meminfo, vmstat, stat, loadavg, current_diskstats) catch return .{ .invalid = .malformed };
    var names: [128][]const u8 = undefined;
    if (current_devices.len > names.len) return .{ .invalid = .oversized };
    for (current_devices, 0..) |device, i| names[i] = device.name;
    const busy = sampler.diskBusyPercent(previous_diskstats, current_diskstats, names[0..current_devices.len], interval_ns / std.time.ns_per_ms) catch |err| {
        return .{ .invalid = if (err == error.CounterReset) .counter_reset else if (err == error.MissingDevice or err == error.DuplicateDevice) .device_changed else .malformed };
    };
    const result = sampler.reduceChecked(previous_raw.?, current, interval_ns / std.time.ns_per_ms, busy, gpu_util_pct) catch |err| {
        return .{ .invalid = if (err == error.CounterReset) .counter_reset else .malformed };
    };
    return .{ .valid = result };
}

/// Read a session's proc facts around transcript metadata. Every proc read is
/// bounded; stat-before/stat-after brackets all other observations to reject
/// PID exit/reuse races. Transcript contents are never opened or modified.
pub fn observeSessionFromProc(
    allocator: std.mem.Allocator,
    expected_identity: ProcessIdentity,
    transcript_path: []const u8,
    now_ns: u64,
    previous: ?PreviousSession,
) Observation(SessionObservation) {
    const before_path = std.fmt.allocPrint(allocator, "/proc/{d}/stat", .{expected_identity.pid}) catch return .{ .invalid = .io_error };
    defer allocator.free(before_path);
    const status_path = std.fmt.allocPrint(allocator, "/proc/{d}/status", .{expected_identity.pid}) catch return .{ .invalid = .io_error };
    defer allocator.free(status_path);
    const before = readBounded(allocator, before_path, proc_read_limit) catch |err| return .{ .invalid = readFailure(err) };
    defer allocator.free(before);
    const status = readBounded(allocator, status_path, proc_read_limit) catch |err| return .{ .invalid = readFailure(err) };
    defer allocator.free(status);
    const ztranscript = allocator.dupeZ(u8, transcript_path) catch return .{ .invalid = .io_error };
    defer allocator.free(ztranscript);
    const transcript = std.fs.openFileAbsolute(ztranscript, .{}) catch return .{ .invalid = .io_error };
    const metadata = transcript.stat() catch {
        transcript.close();
        return .{ .invalid = .io_error };
    };
    transcript.close();
    const after = readBounded(allocator, before_path, proc_read_limit) catch |err| return .{ .invalid = readFailure(err) };
    defer allocator.free(after);
    return observeSession(expected_identity, before, status, after, metadata.size, now_ns, previous, session_stale_after_ns);
}

/// Single-owner host observer. It owns no ledger connection, emits no action,
/// and only reads procfs/sysfs. A caller must retain the instance to retain the
/// kernel lock; dropping it releases ownership automatically only at process exit.
pub const ReadOnlyMonitor = struct {
    allocator: std.mem.Allocator,
    ownership: Ownership,
    schedule: Schedule,
    previous_raw: ?sampler.Raw = null,
    previous_diskstats: ?[]u8 = null,
    previous_devices: ?[]Device = null,
    previous_at_ns: ?u64 = null,

    pub fn init(allocator: std.mem.Allocator, lock_path: [*:0]const u8, period_ns: u64) !ReadOnlyMonitor {
        if (period_ns == 0) return error.InvalidPeriod;
        return .{ .allocator = allocator, .ownership = try Ownership.acquire(lock_path), .schedule = .{ .period_ns = period_ns } };
    }

    pub fn deinit(self: *ReadOnlyMonitor) void {
        if (self.previous_diskstats) |bytes| self.allocator.free(bytes);
        if (self.previous_devices) |devices| freeDevices(self.allocator, devices);
        self.ownership.release();
        self.* = undefined;
    }

    /// Fixture-friendly epoch ingress used by the live collector too.
    pub fn observeHostTexts(
        self: *ReadOnlyMonitor,
        now_ns: u64,
        meminfo: []const u8,
        vmstat: []const u8,
        stat: []const u8,
        loadavg: []const u8,
        diskstats: []const u8,
        devices: []const Device,
    ) !Observation(sampler.Snapshot) {
        if (!try self.schedule.due(now_ns)) return error.NotDue;
        try self.schedule.sampled(now_ns);
        return self.processHostTexts(now_ns, meminfo, vmstat, stat, loadavg, diskstats, devices);
    }

    fn processHostTexts(
        self: *ReadOnlyMonitor,
        now_ns: u64,
        meminfo: []const u8,
        vmstat: []const u8,
        stat: []const u8,
        loadavg: []const u8,
        diskstats: []const u8,
        devices: []const Device,
    ) !Observation(sampler.Snapshot) {
        const current = sampler.sampleChecked(meminfo, vmstat, stat, loadavg, diskstats) catch return .{ .invalid = .malformed };
        if (self.previous_raw == null or self.previous_diskstats == null or self.previous_devices == null or self.previous_at_ns == null) {
            try self.setBaseline(current, diskstats, devices, now_ns);
            return .{ .invalid = .missing };
        }
        const elapsed = now_ns - self.previous_at_ns.?;
        if (elapsed > self.schedule.period_ns *| 2) {
            try self.setBaseline(current, diskstats, devices, now_ns);
            return .{ .stale = .age_limit };
        }
        if (!sameDevices(self.previous_devices.?, devices)) {
            try self.setBaseline(current, diskstats, devices, now_ns);
            return .{ .invalid = .device_changed };
        }
        const observation = checkedSystemSample(self.previous_raw, self.previous_diskstats.?, diskstats, self.previous_devices.?, devices, meminfo, vmstat, stat, loadavg, elapsed, null);
        // A valid raw sample becomes the next baseline even if deltas reset. This
        // bounds recovery to one unknown interval rather than poisoning forever.
        try self.setBaseline(current, diskstats, devices, now_ns);
        return observation;
    }

    /// One due host epoch from bounded Linux procfs and freshly discovered sysfs.
    pub fn sampleHost(self: *ReadOnlyMonitor, now_ns: u64) !Observation(sampler.Snapshot) {
        if (!try self.schedule.due(now_ns)) return error.NotDue;
        try self.schedule.sampled(now_ns);
        const devices = discoverBlockDevices(self.allocator) catch |err| return .{ .invalid = readFailure(err) };
        defer freeDevices(self.allocator, devices);
        const mem = readBounded(self.allocator, "/proc/meminfo", proc_read_limit) catch |err| return .{ .invalid = readFailure(err) };
        defer self.allocator.free(mem);
        const vm = readBounded(self.allocator, "/proc/vmstat", proc_read_limit) catch |err| return .{ .invalid = readFailure(err) };
        defer self.allocator.free(vm);
        const stat = readBounded(self.allocator, "/proc/stat", proc_read_limit) catch |err| return .{ .invalid = readFailure(err) };
        defer self.allocator.free(stat);
        const load = readBounded(self.allocator, "/proc/loadavg", 4096) catch |err| return .{ .invalid = readFailure(err) };
        defer self.allocator.free(load);
        const disk = readBounded(self.allocator, "/proc/diskstats", proc_read_limit) catch |err| return .{ .invalid = readFailure(err) };
        defer self.allocator.free(disk);
        return self.processHostTexts(now_ns, mem, vm, stat, load, disk, devices);
    }

    fn setBaseline(self: *ReadOnlyMonitor, raw: sampler.Raw, diskstats: []const u8, devices: []const Device, now_ns: u64) !void {
        const disk_copy = try self.allocator.dupe(u8, diskstats);
        errdefer self.allocator.free(disk_copy);
        const device_copy = try cloneDevices(self.allocator, devices);
        errdefer freeDevices(self.allocator, device_copy);
        if (self.previous_diskstats) |old| self.allocator.free(old);
        if (self.previous_devices) |old| freeDevices(self.allocator, old);
        self.previous_raw = raw;
        self.previous_diskstats = disk_copy;
        self.previous_devices = device_copy;
        self.previous_at_ns = now_ns;
    }
};

fn cloneDevices(allocator: std.mem.Allocator, devices: []const Device) ![]Device {
    const copy = try allocator.alloc(Device, devices.len);
    var count: usize = 0;
    errdefer {
        for (copy[0..count]) |device| {
            allocator.free(device.name);
            allocator.free(device.major_minor);
        }
        allocator.free(copy);
    }
    for (devices, 0..) |device, i| {
        const name = try allocator.dupe(u8, device.name);
        errdefer allocator.free(name);
        const identity = try allocator.dupe(u8, device.major_minor);
        errdefer allocator.free(identity);
        copy[i] = .{ .name = name, .major_minor = identity };
        count += 1;
    }
    return copy;
}

/// Staleness is never converted into a current value. Callers can retain the
/// last sample separately for display, but must not feed it into classification.
pub fn freshness(comptime T: type, sampled_at_ns: u64, now_ns: u64, max_age_ns: u64, value: T) Observation(T) {
    if (now_ns < sampled_at_ns) return .{ .invalid = .counter_reset };
    if (now_ns - sampled_at_ns > max_age_ns) return .{ .stale = .age_limit };
    return .{ .valid = value };
}

test "monotonic schedule rejects backward time and does not sample early" {
    var schedule = Schedule{ .period_ns = 10 };
    try std.testing.expect(try schedule.due(100));
    try schedule.sampled(100);
    try std.testing.expect(!try schedule.due(109));
    try std.testing.expect(try schedule.due(110));
    try std.testing.expectError(error.ClockRegressed, schedule.due(99));
    try std.testing.expectError(error.ClockRegressed, schedule.sampled(99));
}

test "bounded reader accepts limit and rejects the probe byte" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "proc", .data = "1234" });
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, "proc");
    defer std.testing.allocator.free(path);
    const bytes = try readBounded(std.testing.allocator, path, 4);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("1234", bytes);
    try tmp.dir.writeFile(.{ .sub_path = "proc", .data = "12345" });
    try std.testing.expectError(error.ReadLimitExceeded, readBounded(std.testing.allocator, path, 4));
    try std.testing.expectError(error.InvalidLimit, readBounded(std.testing.allocator, path, proc_read_limit + 1));
}

test "single-instance lock excludes another owner and releases on close" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);
    const lock_path = try std.fmt.allocPrintSentinel(std.testing.allocator, "{s}/monitor.lock", .{path}, 0);
    defer std.testing.allocator.free(lock_path);
    var first = try Ownership.acquire(lock_path.ptr);
    defer first.release();
    try std.testing.expectError(error.AlreadyOwned, Ownership.acquire(lock_path.ptr));
    first.release();
    var second = try Ownership.acquire(lock_path.ptr);
    second.release();
}

test "stable selection excludes partitions and virtual devices, catches identity changes" {
    const a = std.testing.allocator;
    const first = try selectDevices(a, &.{
        .{ .name = "sdb", .major_minor = "8:16", .whole_device = true },
        .{ .name = "sda1", .major_minor = "8:1", .whole_device = false },
        .{ .name = "loop0", .major_minor = "7:0", .whole_device = true },
        .{ .name = "sda", .major_minor = "8:0", .whole_device = true },
    });
    defer freeDevices(a, first);
    try std.testing.expectEqualStrings("sda", first[0].name);
    try std.testing.expectEqualStrings("sdb", first[1].name);
    const same = try selectDevices(a, &.{ .{ .name = "sda", .major_minor = "8:0", .whole_device = true }, .{ .name = "sdb", .major_minor = "8:16", .whole_device = true } });
    defer freeDevices(a, same);
    try std.testing.expect(sameDevices(first, same));
    const replaced = try selectDevices(a, &.{ .{ .name = "sda", .major_minor = "259:0", .whole_device = true }, .{ .name = "sdb", .major_minor = "8:16", .whole_device = true } });
    defer freeDevices(a, replaced);
    try std.testing.expect(!sameDevices(first, replaced));
}

fn statFixture(pid: u32, start: u64) ![]u8 {
    return std.fmt.allocPrint(std.testing.allocator, "{d} (a tricky ) name) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 {d} 21 22\n", .{ pid, start });
}

test "sysfs fixture discovery selects sorted whole-device identities" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("sys/block/sda/device");
    try tmp.dir.makePath("sys/block/sda1");
    try tmp.dir.makePath("sys/block/sdb/device");
    try tmp.dir.makePath("sys/block/loop0");
    try tmp.dir.writeFile(.{ .sub_path = "sys/block/sda/dev", .data = "8:0\n" });
    try tmp.dir.writeFile(.{ .sub_path = "sys/block/sda1/dev", .data = "8:1\n" });
    try tmp.dir.writeFile(.{ .sub_path = "sys/block/sda1/partition", .data = "1\n" });
    try tmp.dir.writeFile(.{ .sub_path = "sys/block/sdb/dev", .data = "8:16\n" });
    try tmp.dir.writeFile(.{ .sub_path = "sys/block/loop0/dev", .data = "7:0\n" });
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, "sys/block");
    defer std.testing.allocator.free(path);
    const devices = try discoverBlockDevicesAt(std.testing.allocator, path);
    defer freeDevices(std.testing.allocator, devices);
    try std.testing.expectEqual(@as(usize, 2), devices.len);
    try std.testing.expectEqualStrings("sda", devices[0].name);
    try std.testing.expectEqualStrings("8:0", devices[0].major_minor);
    try std.testing.expectEqualStrings("sdb", devices[1].name);
}

test "session fixture observes identity RSS and motion; rejects PID reuse" {
    const a = std.testing.allocator;
    const before = try statFixture(42, 900);
    defer a.free(before);
    const after = try statFixture(42, 900);
    defer a.free(after);
    const rss = "Name:\tmodel\nVmRSS:\t12345 kB\n";
    const first = observeSession(.{ .pid = 42, .start_ticks = 900 }, before, rss, after, 100, 1_000, null, 500);
    const initial = switch (first) {
        .valid => |v| v,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(Motion.unknown, initial.motion);
    const prior = PreviousSession{ .identity = initial.identity, .transcript_bytes = 100, .changed_at_ns = 1_000 };
    const moving = observeSession(.{ .pid = 42, .start_ticks = 900 }, before, rss, after, 120, 1_100, prior, 500);
    try std.testing.expectEqual(Motion.moving, (switch (moving) {
        .valid => |v| v,
        else => return error.TestUnexpectedResult,
    }).motion);
    const moved_prior = PreviousSession{ .identity = initial.identity, .transcript_bytes = 120, .changed_at_ns = 1_100 };
    const quiet = observeSession(.{ .pid = 42, .start_ticks = 900 }, before, rss, after, 120, 1_200, moved_prior, 500);
    try std.testing.expectEqual(Motion.quiet, (switch (quiet) {
        .valid => |v| v,
        else => return error.TestUnexpectedResult,
    }).motion);
    const stale = observeSession(.{ .pid = 42, .start_ticks = 900 }, before, rss, after, 120, 1_600, moved_prior, 500);
    try std.testing.expectEqual(Motion.stale, (switch (stale) {
        .valid => |v| v,
        else => return error.TestUnexpectedResult,
    }).motion);
    const reused = try statFixture(42, 901);
    defer a.free(reused);
    const pid_reused = observeSession(.{ .pid = 42, .start_ticks = 900 }, before, rss, reused, 100, 1_100, prior, 500);
    try std.testing.expectEqual(InvalidReason.pid_reused, pid_reused.invalid);
    try std.testing.expectEqual(InvalidReason.pid_reused, (observeSession(.{ .pid = 42, .start_ticks = 900 }, reused, rss, reused, 100, 1_100, prior, 500)).invalid);
    try std.testing.expectEqual(InvalidReason.pid_reused, (observeSession(.{ .pid = 42, .start_ticks = 900 }, reused, rss, reused, 100, 1_100, null, 500)).invalid);
}

test "missing or malformed session facts remain explicit invalid observations" {
    const stat = try statFixture(7, 1);
    defer std.testing.allocator.free(stat);
    try std.testing.expectEqual(InvalidReason.missing, (observeSession(.{ .pid = 7, .start_ticks = 1 }, stat, "VmSize: 3 kB", stat, 0, 0, null, 2)).invalid);
    try std.testing.expectEqual(InvalidReason.malformed, (observeSession(.{ .pid = 7, .start_ticks = 1 }, "bad", "VmRSS: 1 kB", stat, 0, 0, null, 2)).invalid);
}

test "checked host fixture requires a baseline and stable whole-device epoch" {
    const devices = [_]Device{.{ .name = "sda", .major_minor = "8:0" }};
    const mem_before = "MemTotal: 1000 kB\nMemAvailable: 500 kB\nSwapTotal: 100 kB\nSwapFree: 90 kB\n";
    const mem_after = "MemTotal: 1000 kB\nMemAvailable: 400 kB\nSwapTotal: 100 kB\nSwapFree: 80 kB\n";
    const vm_before = "pswpout 10\n";
    const vm_after = "pswpout 12\n";
    const cpu_before = "cpu 100 0 50 700 50 0 0 0\ncpu0 1 2\n";
    const cpu_after = "cpu 110 0 55 720 55 0 0 0\ncpu0 1 2\n";
    const load = "0.5 0.4 0.3 1/10 123\n";
    const disk_before = "8 0 sda 0 0 0 0 0 0 0 0 0 0 0\n";
    const disk_after = "8 0 sda 0 0 0 0 0 0 0 0 0 500 0\n";
    try std.testing.expectEqual(InvalidReason.missing, (checkedSystemSample(null, disk_before, disk_after, &devices, &devices, mem_after, vm_after, cpu_after, load, std.time.ns_per_s, null)).invalid);
    const baseline = try sampler.sampleChecked(mem_before, vm_before, cpu_before, load, disk_before);
    const observed = checkedSystemSample(baseline, disk_before, disk_after, &devices, &devices, mem_after, vm_after, cpu_after, load, std.time.ns_per_s, null);
    const snapshot = switch (observed) {
        .valid => |v| v,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u8, 50), snapshot.io_ticks_pct);
    try std.testing.expectEqual(@as(u64, 2), snapshot.pswpout_delta);
    const replaced = [_]Device{.{ .name = "sda", .major_minor = "259:0" }};
    try std.testing.expectEqual(InvalidReason.device_changed, (checkedSystemSample(baseline, disk_before, disk_after, &devices, &replaced, mem_after, vm_after, cpu_after, load, std.time.ns_per_s, null)).invalid);
    try std.testing.expectEqual(InvalidReason.malformed, (checkedSystemSample(baseline, disk_before, disk_after, &devices, &devices, mem_after, vm_after, cpu_after, load, 0, null)).invalid);
}

test "read-only monitor owns one instance and samples only on its monotonic cadence" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);
    const lock_path = try std.fmt.allocPrintSentinel(std.testing.allocator, "{s}/host.lock", .{root}, 0);
    defer std.testing.allocator.free(lock_path);
    var monitor = try ReadOnlyMonitor.init(std.testing.allocator, lock_path.ptr, std.time.ns_per_s);
    defer monitor.deinit();
    try std.testing.expectError(error.AlreadyOwned, Ownership.acquire(lock_path.ptr));
    const devices = [_]Device{.{ .name = "sda", .major_minor = "8:0" }};
    const mem0 = "MemTotal: 1000 kB\nMemAvailable: 500 kB\nSwapTotal: 100 kB\nSwapFree: 90 kB\n";
    const mem1 = "MemTotal: 1000 kB\nMemAvailable: 400 kB\nSwapTotal: 100 kB\nSwapFree: 80 kB\n";
    const vm0 = "pswpout 10\n";
    const vm1 = "pswpout 12\n";
    const cpu0 = "cpu 100 0 50 700 50 0 0 0\ncpu0 1 2\n";
    const cpu1 = "cpu 110 0 55 720 55 0 0 0\ncpu0 1 2\n";
    const disk0 = "8 0 sda 0 0 0 0 0 0 0 0 0 0 0\n";
    const disk1 = "8 0 sda 0 0 0 0 0 0 0 0 0 500 0\n";
    try std.testing.expectEqual(InvalidReason.missing, (try monitor.observeHostTexts(0, mem0, vm0, cpu0, "0.5", disk0, &devices)).invalid);
    try std.testing.expectError(error.NotDue, monitor.observeHostTexts(std.time.ns_per_s / 2, mem1, vm1, cpu1, "0.5", disk1, &devices));
    const second = try monitor.observeHostTexts(std.time.ns_per_s, mem1, vm1, cpu1, "0.5", disk1, &devices);
    try std.testing.expectEqual(@as(u8, 50), (switch (second) {
        .valid => |v| v,
        else => return error.TestUnexpectedResult,
    }).io_ticks_pct);
    const replacement = [_]Device{.{ .name = "sda", .major_minor = "259:0" }};
    try std.testing.expectEqual(InvalidReason.device_changed, (try monitor.observeHostTexts(2 * std.time.ns_per_s, mem1, vm1, cpu1, "0.5", disk1, &replacement)).invalid);
}

test "stale samples are not relabelled with current time" {
    const obs = freshness(u64, 10, 30, 5, 99);
    try std.testing.expectEqual(StaleReason.age_limit, obs.stale);
    try std.testing.expectEqual(InvalidReason.counter_reset, (freshness(u64, 31, 30, 5, 99)).invalid);
    try std.testing.expectEqual(@as(u64, 99), (freshness(u64, 30, 30, 5, 99)).valid);
}
