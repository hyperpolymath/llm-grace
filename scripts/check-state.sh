#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Required-field check only; full A2ML validation remains an external gate.
set -euo pipefail
state=${1:-.machine_readable/STATE.a2ml}
if [[ ! -f "$state" ]]; then
    echo "ERROR: missing state: $state" >&2
    exit 1
fi
for pattern in '^\(state' '\(metadata' '\(project "llm-grace"\)' '\(last-updated "[0-9]{4}-[0-9]{2}-[0-9]{2}"\)' '\(phase "[^"]+"\)'; do
    if ! grep -Eq "$pattern" "$state"; then
        echo "ERROR: $state missing required field matching $pattern" >&2
        exit 1
    fi
done
echo "PASS: STATE required fields (not full syntax or readiness validation)"
