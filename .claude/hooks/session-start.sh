#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Read-only SessionStart preflight. Never installs tools, changes repo state,
# or blocks the assistant from starting; missing requirements are reported.
set -u

note() { printf '[session-start] %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

note "llm-grace is development scaffolding; no monitor daemon or enforcement hooks are installed."
for tool in git bash; do
    if have "$tool"; then
        note "available: $tool ($(command -v "$tool"))"
    else
        note "missing optional/preflight tool: $tool"
    fi
done
if have zig; then
    version="$(zig version 2>/dev/null || true)"
    if [[ "$version" == 0.15.2 ]]; then
        note "available: Zig $version"
    else
        note "Zig version mismatch: expected 0.15.2, found ${version:-unavailable}"
    fi
else
    note "Zig 0.15.2 is required to run core tests; no installation attempted."
fi
if have just; then
    note "available: $(just --version)"
else
    note "just is optional; scripts/run.sh provides the shell entrypoint."
fi
note "Read CLAUDE.md and docs/practice/AI-CONVENTIONS.adoc before editing."
exit 0
