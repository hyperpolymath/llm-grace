#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# No system load injection: fork/SIGKILL tests target only their own child.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v zig >/dev/null || { echo 'ERROR: Zig 0.15.2 is required' >&2; exit 1; }
[[ $(zig version) == 0.15.2 ]] || { echo 'ERROR: this suite is pinned to Zig 0.15.2' >&2; exit 1; }
command -v timeout >/dev/null || { echo 'ERROR: GNU timeout is required' >&2; exit 1; }
lmdb=(-llmdb)
if [[ -n ${LMDB_PREFIX:-} ]]; then
    [[ -f "$LMDB_PREFIX/include/lmdb.h" && -f "$LMDB_PREFIX/lib/liblmdb.a" ]] || {
        echo 'ERROR: LMDB_PREFIX must contain include/lmdb.h and lib/liblmdb.a' >&2
        exit 1
    }
    lmdb=(-I "$LMDB_PREFIX/include" "$LMDB_PREFIX/lib/liblmdb.a")
fi
# An independent timeout prevents a writer-lock regression from hanging CI.
timeout --kill-after=5s 60s zig test src/signal/sampler.zig "$@"
timeout --kill-after=5s 60s zig test src/control/ladder.zig "$@"
timeout --kill-after=5s 60s zig test src/control/safety.zig "$@"
timeout --kill-after=5s 60s zig test src/ledger/lmdb.zig "${lmdb[@]}" -lc "$@"
