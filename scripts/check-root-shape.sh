#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# check-root-shape.sh — fail when the repository root contains entries that
# are not on the canonical allowlist (.machine_readable/root-allow.txt).
#
# Companion to scripts/validate-template.sh: that script enforces required
# files; this one enforces that nothing else has crept in.
#
# Exit codes:
#   0 — root matches allowlist
#   1 — extras found at root (drift)
#   2 — usage / setup error

set -euo pipefail

REPO_ROOT="${1:-.}"
ALLOW_FILE="${REPO_ROOT}/.machine_readable/root-allow.txt"

if [ ! -f "$ALLOW_FILE" ]; then
    echo "ERROR: allowlist not found at $ALLOW_FILE" >&2
    exit 2
fi

# Build the allow set: strip comments, trailing slashes, and blank lines.
mapfile -t ALLOW < <(
    sed -E 's/[[:space:]]*#.*$//' "$ALLOW_FILE" \
        | sed -E 's|/$||' \
        | awk 'NF'
)

declare -A ALLOW_SET=()
for entry in "${ALLOW[@]}"; do
    ALLOW_SET["$entry"]=1
done

# Enumerate everything tracked or present at the repository root.
mapfile -t ACTUAL < <(
    cd "$REPO_ROOT" && \
    find . -mindepth 1 -maxdepth 1 \
        ! -name '.' \
        -printf '%f\n' \
    | sort
)

EXTRAS=()
for entry in "${ACTUAL[@]}"; do
    if [ -z "${ALLOW_SET[$entry]+x}" ]; then
        EXTRAS+=("$entry")
    fi
done

if [ ${#EXTRAS[@]} -eq 0 ]; then
    echo "PASS: root matches allowlist (${#ACTUAL[@]} entries, ${#ALLOW[@]} permitted)"
    exit 0
fi

echo "FAIL: ${#EXTRAS[@]} root entries are not on the allowlist:" >&2
for e in "${EXTRAS[@]}"; do
    if [ -d "$REPO_ROOT/$e" ]; then
        echo "  - $e/  (directory)" >&2
    else
        echo "  - $e" >&2
    fi
done
echo "" >&2
echo "Either move them into the appropriate subdirectory, or add a justified" >&2
echo "entry to .machine_readable/root-allow.txt." >&2
exit 1
