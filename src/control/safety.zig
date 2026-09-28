// SPDX-License-Identifier: MPL-2.0
// Filesystem-only bypass: must be checked BEFORE any IPC or ledger operation.
const std = @import("std");

/// Any OFF directory entry (even a dangling symlink), or inability to inspect
/// the trusted control directory, disables enforcement. No LMDB dependency.
/// OFF does not authorize clearing a checkpoint latch or relaunching a session.
pub fn enforcementAllowed(control_dir: std.fs.Dir) bool {
    _ = std.posix.fstatat(control_dir.fd, "OFF", std.posix.AT.SYMLINK_NOFOLLOW) catch |err| {
        return err == error.FileNotFound;
    };
    return false;
}

test "plain OFF file bypass is independent of missing or broken ledger" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.expect(enforcementAllowed(tmp.dir));
    const off = try tmp.dir.createFile("OFF", .{});
    off.close();
    try std.testing.expect(!enforcementAllowed(tmp.dir));
    try tmp.dir.deleteFile("OFF");
    try std.testing.expect(enforcementAllowed(tmp.dir));
}

test "dangling OFF symlink disables enforcement" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.symLink("nonexistent", "OFF", .{});
    try std.testing.expect(!enforcementAllowed(tmp.dir));
}
