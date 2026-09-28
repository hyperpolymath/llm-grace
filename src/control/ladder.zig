// SPDX-License-Identifier: MPL-2.0
// Finite policy kernel, not a process controller or a formal proof.
const std = @import("std");
pub const State = enum { active, paused, checkpointed, terminated };
pub const Event = enum {
    pressure,
    recovery,
    checkpoint_committed,
    terminate,
    human_resume,
    unknown_sample,
};

/// A checkpoint_committed event is permitted ONLY after the caller receives a
/// successful ledger commit for that session. This model does not verify that
/// external fact. OFF bypasses enforcement without erasing the stored latch.
pub fn step(state: State, event: Event, off: bool) State {
    if (off or state == .terminated) return state;
    return switch (event) {
        .unknown_sample => state,
        .pressure => if (state == .active) .paused else state,
        .recovery => if (state == .paused) .active else state,
        .checkpoint_committed => if (state == .paused) .checkpointed else state,
        .terminate => if (state == .checkpointed) .terminated else state,
        .human_resume => if (state == .checkpointed) .active else state,
    };
}

test "exhaustive finite ladder: latch, terminal, checkpoint-before-terminate, OFF" {
    const states = std.enums.values(State);
    const events = std.enums.values(Event);
    for (states) |state| {
        for (events) |event| {
            try std.testing.expectEqual(state, step(state, event, true));
            const next = step(state, event, false);
            if (state == .terminated) try std.testing.expectEqual(State.terminated, next);
            if (state == .checkpointed and event != .human_resume and event != .terminate)
                try std.testing.expectEqual(State.checkpointed, next);
            if (next == .terminated and state != .terminated)
                try std.testing.expect(state == .checkpointed and event == .terminate);
            if (event == .unknown_sample) try std.testing.expectEqual(state, next);
        }
    }
}

test "pause recovers automatically; checkpoint requires explicit human release" {
    var state: State = .active;
    state = step(state, .pressure, false);
    try std.testing.expectEqual(State.paused, state);
    state = step(state, .recovery, false);
    try std.testing.expectEqual(State.active, state);
    state = step(state, .pressure, false);
    state = step(state, .checkpoint_committed, false);
    try std.testing.expectEqual(State.checkpointed, step(state, .recovery, false));
    try std.testing.expectEqual(State.active, step(state, .human_resume, false));
    try std.testing.expectEqual(State.terminated, step(state, .terminate, false));
}
