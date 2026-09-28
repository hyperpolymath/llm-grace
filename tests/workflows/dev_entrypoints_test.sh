#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Verify developer entrypoints are explicit and do not masquerade as a service.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

help_output="$(scripts/run.sh help)"
grep -q 'scripts/dev.sh check' <<<"$help_output"
version_output="$(scripts/run.sh --version)"
grep -q '^llm-grace-dev 0.1.0 (' <<<"$version_output"
stop_output="$(scripts/run.sh --stop)"
grep -q 'nothing was stopped' <<<"$stop_output"
grep -q 'scripts/dev.sh test' <<<"$help_output"

if output="$(scripts/run.sh run 2>&1)"; then
    echo "ERROR: run unexpectedly succeeded without an application" >&2
    exit 1
fi
grep -q 'there is no application' <<<"$output"

if output="$(scripts/run.sh --integ 2>&1)"; then
    echo "ERROR: integration unexpectedly succeeded without an application" >&2
    exit 1
fi
grep -q 'there is no application' <<<"$output"

if output="$(scripts/dev.sh test Unsupported 2>&1)"; then
    echo "ERROR: unsupported test mode unexpectedly succeeded" >&2
    exit 1
fi
grep -q 'unsupported test mode' <<<"$output"

if grep -Eq 'apt-get install|pip install|gem install' .claude/hooks/session-start.sh; then
    echo "ERROR: AI session startup must not install packages" >&2
    exit 1
fi

if command -v just >/dev/null 2>&1; then
    if output="$(just run 2>&1)"; then
        echo "ERROR: just run unexpectedly succeeded without an application" >&2
        exit 1
    fi
    grep -q 'there is no application' <<<"$output"
    if grep -Eq 'safe to merge|All test categories passed' Justfile; then
        echo "ERROR: Justfile makes an unsupported all-tests/merge claim" >&2
        exit 1
    fi
fi

echo "PASS: developer entrypoints fail closed and session startup is read-only"
