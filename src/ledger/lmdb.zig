// SPDX-License-Identifier: MPL-2.0
// Bounded ledger primitive. No process control, automatic map growth, or relaxed sync.
const std = @import("std");
const c = @cImport({
    @cInclude("lmdb.h");
    @cInclude("unistd.h");
    @cInclude("sys/wait.h");
    @cInclude("signal.h");
    @cInclude("errno.h");
});

pub const max_record_bytes = 4096;
pub const max_session_bytes = 128;
pub const default_map_bytes = 16 * 1024 * 1024;

fn check(rc: c_int) !void {
    switch (rc) {
        0 => {},
        c.MDB_NOTFOUND => return error.NotFound,
        c.MDB_MAP_FULL => return error.MapFull,
        c.MDB_MAP_RESIZED => return error.MapResized,
        c.MDB_READERS_FULL => return error.ReadersFull,
        c.ENOSPC => return error.DiskFull,
        c.ENOMEM => return error.OutOfMemory,
        c.EACCES => return error.AccessDenied,
        c.EIO => return error.StorageFailure,
        c.MDB_CORRUPTED, c.MDB_INVALID, c.MDB_VERSION_MISMATCH => return error.InvalidDatabase,
        else => return error.LmdbFailure,
    }
}

fn value(bytes: []const u8) c.MDB_val {
    return .{ .mv_size = bytes.len, .mv_data = @ptrCast(@constCast(bytes.ptr)) };
}

fn slice(v: c.MDB_val) []const u8 {
    return @as([*]const u8, @ptrCast(v.mv_data))[0..v.mv_size];
}

/// One environment handle per process/path. Do not copy or use after close/fork.
/// Caller owns a private, trusted directory on a local filesystem and must
/// serialize open/close against its other users. LMDB serializes write txns;
/// acquiring its writer lock is NOT a bounded-time operation. Hook callers must
/// use a bounded IPC boundary, never invoke this API on their blocking path.
pub const Ledger = struct {
    env: *c.MDB_env,
    sessions: c.MDB_dbi,
    events: c.MDB_dbi,
    meta: c.MDB_dbi,

    pub fn open(path: [:0]const u8, map_bytes: usize) !Ledger {
        if (map_bytes < 64 * 1024) return error.MapTooSmall;
        var maybe_env: ?*c.MDB_env = null;
        try check(c.mdb_env_create(&maybe_env));
        const env = maybe_env.?;
        errdefer c.mdb_env_close(env);
        try check(c.mdb_env_set_maxdbs(env, 3));
        try check(c.mdb_env_set_mapsize(env, map_bytes));
        // flags=0: no NOSYNC, NOMETASYNC, WRITEMAP, MAPASYNC, or NOLOCK.
        try check(c.mdb_env_open(env, path.ptr, 0, 0o600));
        var maybe_txn: ?*c.MDB_txn = null;
        try check(c.mdb_txn_begin(env, null, 0, &maybe_txn));
        const txn = maybe_txn.?;
        var owned = true;
        defer if (owned) c.mdb_txn_abort(txn);
        var self = Ledger{ .env = env, .sessions = 0, .events = 0, .meta = 0 };
        try check(c.mdb_dbi_open(txn, "sessions", c.MDB_CREATE, &self.sessions));
        try check(c.mdb_dbi_open(txn, "events", c.MDB_CREATE, &self.events));
        try check(c.mdb_dbi_open(txn, "meta", c.MDB_CREATE, &self.meta));
        var key = value("schema");
        var existing: c.MDB_val = undefined;
        const rc = c.mdb_get(txn, self.meta, &key, &existing);
        if (rc == c.MDB_NOTFOUND) {
            var version = value("1");
            try check(c.mdb_put(txn, self.meta, &key, &version, 0));
        } else {
            try check(rc);
            if (!std.mem.eql(u8, slice(existing), "1")) return error.UnsupportedSchema;
        }
        owned = false; // commit consumes the transaction even on failure
        try check(c.mdb_txn_commit(txn));
        return self;
    }

    pub fn close(self: *Ledger) void {
        c.mdb_env_close(self.env);
        self.* = undefined;
    }

    /// Atomically persist latest session record, ordered event, and sequence.
    /// Records are opaque versioned bytes supplied by the caller. Events encode
    /// [8-byte wall_ms][2-byte session length][session][record]. All integers BE.
    /// Ordering is the transaction sequence, not the potentially jumping clock.
    /// Success means default-sync commit succeeded, NOT that hardware is infallible.
    pub fn append(self: *Ledger, session: []const u8, record: []const u8, wall_ms: u64) !u64 {
        try validate(session, record);
        var maybe_txn: ?*c.MDB_txn = null;
        try check(c.mdb_txn_begin(self.env, null, 0, &maybe_txn));
        const txn = maybe_txn.?;
        var owned = true;
        defer if (owned) c.mdb_txn_abort(txn);
        const seq = try self.stage(txn, session, record, wall_ms);
        owned = false;
        try check(c.mdb_txn_commit(txn));
        return seq;
    }

    fn validate(session: []const u8, record: []const u8) !void {
        if (session.len == 0 or session.len > max_session_bytes) return error.InvalidSession;
        if (record.len > max_record_bytes) return error.RecordTooLarge;
    }

    fn stage(self: *Ledger, txn: *c.MDB_txn, session: []const u8, record: []const u8, wall_ms: u64) !u64 {
        var seq_key = value("sequence");
        var old: c.MDB_val = undefined;
        const rc = c.mdb_get(txn, self.meta, &seq_key, &old);
        var seq: u64 = 0;
        if (rc != c.MDB_NOTFOUND) {
            try check(rc);
            if (old.mv_size != 8) return error.InvalidDatabase;
            seq = std.mem.readInt(u64, slice(old)[0..8], .big);
        }
        seq = try std.math.add(u64, seq, 1);
        var encoded: [8]u8 = undefined;
        std.mem.writeInt(u64, &encoded, seq, .big);
        var sequence = value(&encoded);
        var session_key = value(session);
        var data = value(record);
        try check(c.mdb_put(txn, self.sessions, &session_key, &data, 0));
        var event: [10 + max_session_bytes + max_record_bytes]u8 = undefined;
        std.mem.writeInt(u64, event[0..8], wall_ms, .big);
        std.mem.writeInt(u16, event[8..10], @intCast(session.len), .big);
        @memcpy(event[10..][0..session.len], session);
        @memcpy(event[10 + session.len ..][0..record.len], record);
        var event_value = value(event[0 .. 10 + session.len + record.len]);
        try check(c.mdb_put(txn, self.events, &sequence, &event_value, c.MDB_NOOVERWRITE));
        try check(c.mdb_put(txn, self.meta, &seq_key, &sequence, 0));
        return seq;
    }

    /// Copy out while the read txn is alive. Never leak mmap pointers to callers.
    pub fn read(self: *Ledger, allocator: std.mem.Allocator, session: []const u8) ![]u8 {
        return self.readDb(allocator, self.sessions, session);
    }

    pub fn readEvent(self: *Ledger, allocator: std.mem.Allocator, seq: u64) ![]u8 {
        var encoded: [8]u8 = undefined;
        std.mem.writeInt(u64, &encoded, seq, .big);
        return self.readDb(allocator, self.events, &encoded);
    }

    fn readDb(self: *Ledger, allocator: std.mem.Allocator, db: c.MDB_dbi, bytes: []const u8) ![]u8 {
        var maybe_txn: ?*c.MDB_txn = null;
        try check(c.mdb_txn_begin(self.env, null, c.MDB_RDONLY, &maybe_txn));
        const txn = maybe_txn.?;
        defer c.mdb_txn_abort(txn);
        var key = value(bytes);
        var result: c.MDB_val = undefined;
        try check(c.mdb_get(txn, db, &key, &result));
        return allocator.dupe(u8, slice(result));
    }
};

const a = std.testing.allocator;
fn tempPath(dir: std.fs.Dir) ![:0]u8 {
    const path = try dir.realpathAlloc(a, ".");
    defer a.free(path);
    return a.dupeZ(u8, path);
}
fn expectRecord(db: *Ledger, session: []const u8, expected: []const u8) !void {
    const found = try db.read(a, session);
    defer a.free(found);
    try std.testing.expectEqualStrings(expected, found);
}

test "state and event survive reopen; sequence survives clock regression" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tempPath(tmp.dir);
    defer a.free(path);
    {
        var db = try Ledger.open(path, default_map_bytes);
        defer db.close();
        try std.testing.expectEqual(@as(u64, 1), try db.append("s1", "active", 100));
        try std.testing.expectEqual(@as(u64, 2), try db.append("s1", "checkpoint", 90));
        try std.testing.expectError(error.InvalidSession, db.append("", "", 0));
        try std.testing.expectError(error.RecordTooLarge, db.append("s1", &([_]u8{0} ** 4097), 0));
    }
    var db = try Ledger.open(path, default_map_bytes);
    defer db.close();
    try expectRecord(&db, "s1", "checkpoint");
    const event = try db.readEvent(a, 2);
    defer a.free(event);
    try std.testing.expectEqual(@as(u64, 90), std.mem.readInt(u64, event[0..8], .big));
    try std.testing.expectEqualStrings("s1checkpoint", event[10..]);
    try std.testing.expectEqual(@as(u64, 3), try db.append("s2", "active", 80));
}

test "aborted writer exposes neither latest state nor event" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tempPath(tmp.dir);
    defer a.free(path);
    var db = try Ledger.open(path, default_map_bytes);
    defer db.close();
    _ = try db.append("s", "before", 0);
    var txn: ?*c.MDB_txn = null;
    try check(c.mdb_txn_begin(db.env, null, 0, &txn));
    _ = db.stage(txn.?, "s", "after", 1) catch |err| {
        c.mdb_txn_abort(txn.?);
        return err;
    };
    c.mdb_txn_abort(txn.?);
    try expectRecord(&db, "s", "before");
    try std.testing.expectError(error.NotFound, db.readEvent(a, 2));
    try std.testing.expectEqual(@as(u64, 2), try db.append("s", "retry", 2));
}

// These are process-crash tests, NOT host-power-loss tests. No memory balloon.
// Child opens its own environment after fork; no inherited environment is used.
fn crashChild(path: [:0]const u8, commit: bool) noreturn {
    var db = Ledger.open(path, default_map_bytes) catch c._exit(10);
    if (commit) {
        _ = db.append("s", "committed", 2) catch c._exit(11);
    } else {
        var txn: ?*c.MDB_txn = null;
        check(c.mdb_txn_begin(db.env, null, 0, &txn)) catch c._exit(12);
        _ = db.stage(txn.?, "s", "uncommitted", 1) catch c._exit(13);
    }
    _ = c.kill(c.getpid(), c.SIGKILL);
    c._exit(14);
}

test "SIGKILL before and after commit preserves atomicity and releases writer lock" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tempPath(tmp.dir);
    defer a.free(path);
    {
        var db = try Ledger.open(path, default_map_bytes);
        defer db.close();
        _ = try db.append("s", "before", 0);
    }
    for ([_]bool{ false, true }) |commit| {
        const pid = c.fork();
        if (pid < 0) return error.ForkFailed;
        if (pid == 0) crashChild(path, commit);
        var status: c_int = 0;
        if (c.waitpid(pid, &status, 0) != pid) return error.WaitFailed;
        try std.testing.expectEqual(@as(c_int, c.SIGKILL), status & 0x7f);
        var db = try Ledger.open(path, default_map_bytes);
        defer db.close();
        try expectRecord(&db, "s", if (commit) "committed" else "before");
        if (!commit) {
            try std.testing.expectError(error.NotFound, db.readEvent(a, 2));
        } else {
            const event = try db.readEvent(a, 2);
            defer a.free(event);
            try std.testing.expectEqualStrings("scommitted", event[10..]);
        }
    }
}

test "bounded map fills cleanly without losing last successful commit" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tempPath(tmp.dir);
    defer a.free(path);
    var db = try Ledger.open(path, 64 * 1024);
    defer db.close();
    var record = [_]u8{42} ** max_record_bytes;
    var last: ?u8 = null;
    for (0..100) |i| {
        record[0] = @intCast(i);
        _ = db.append("s", &record, @intCast(i)) catch |err| {
            try std.testing.expectEqual(error.MapFull, err);
            try std.testing.expect(last != null);
            const found = try db.read(a, "s");
            defer a.free(found);
            try std.testing.expectEqual(last.?, found[0]);
            try std.testing.expectError(error.NotFound, db.readEvent(a, @intCast(i + 1)));
            return;
        };
        last = record[0];
    }
    return error.ExpectedMapFull;
}

fn writerChild(path: [:0]const u8, session: []const u8) noreturn {
    var db = Ledger.open(path, default_map_bytes) catch c._exit(20);
    for (0..10) |i| {
        _ = db.append(session, "heartbeat", @intCast(i)) catch c._exit(21);
    }
    db.close();
    c._exit(0);
}

test "independent processes share serialized event sequence without lost updates" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tempPath(tmp.dir);
    defer a.free(path);
    var pids: [2]c.pid_t = undefined;
    var started: usize = 0;
    // Reap even if a later fork fails or an assertion fails.
    defer for (pids[0..started]) |pid| {
        var status: c_int = 0;
        _ = c.waitpid(pid, &status, 0);
    };
    for ([_][]const u8{ "one", "two" }, 0..) |session, i| {
        pids[i] = c.fork();
        if (pids[i] < 0) return error.ForkFailed;
        if (pids[i] == 0) writerChild(path, session);
        started += 1;
    }
    for (pids) |pid| {
        var status: c_int = 0;
        if (c.waitpid(pid, &status, 0) != pid) return error.WaitFailed;
        try std.testing.expectEqual(@as(c_int, 0), status);
    }
    var db = try Ledger.open(path, default_map_bytes);
    defer db.close();
    try expectRecord(&db, "one", "heartbeat");
    try expectRecord(&db, "two", "heartbeat");
    for (1..21) |seq| {
        const event = try db.readEvent(a, @intCast(seq));
        a.free(event);
    }
    try std.testing.expectError(error.NotFound, db.readEvent(a, 21));
}
