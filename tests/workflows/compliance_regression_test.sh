#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Exercise failure paths without modifying the checkout or invoking real compilers.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
expect_failure() {
    if "$@" >"$tmp/output" 2>&1; then
        echo "FAIL: expected failure: $*" >&2
        exit 1
    fi
}
bash "$root/scripts/check-state.sh" "$root/.machine_readable/STATE.a2ml"
expect_failure bash "$root/scripts/check-state.sh" "$tmp/missing"
printf '(state (metadata (project "wrong")))\n' > "$tmp/state"
expect_failure bash "$root/scripts/check-state.sh" "$tmp/state"
cp -R "$root/.github/workflows" "$tmp/workflows"
rm "$tmp/workflows/governance.yml"
expect_failure bash "$root/tests/workflows/validate_workflows_test.sh" "$tmp/workflows"
mkdir "$tmp/repo"
# Copy only validator inputs; no credentials, .git, or generated build trees.
for path in scripts .machine_readable .github src/interface docs LICENSES README.adoc EXPLAINME.adoc LICENSE Justfile AUDIT.adoc TOPOLOGY.adoc; do
    mkdir -p "$tmp/repo/$(dirname "$path")"
    cp -R "$root/$path" "$tmp/repo/$path"
done
mkdir "$tmp/bin"
# Failing silently must still fail the gate: never grep compiler diagnostics.
printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/zig"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/idris2"
chmod +x "$tmp/bin/zig" "$tmp/bin/idris2"
expect_failure env PATH="$tmp/bin:$PATH" bash "$root/scripts/validate-template.sh" "$tmp/repo"
grep -q 'Zig build failed' "$tmp/output"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/zig"
printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/idris2"
expect_failure env PATH="$tmp/bin:$PATH" bash "$root/scripts/validate-template.sh" "$tmp/repo"
grep -q 'Idris2 syntax issue' "$tmp/output"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/idris2"
bash_output=$(PATH="$tmp/bin:$PATH" bash "$root/scripts/validate-template.sh" "$tmp/repo" 2>&1)
[[ "$bash_output" == *'Validation PASSED'* ]]
rm "$tmp/repo/LICENSE" "$tmp/repo/README.adoc"
expect_failure env PATH="$tmp/bin:$PATH" bash "$root/scripts/validate-template.sh" "$tmp/repo"
grep -q 'Required file missing: LICENSE' "$tmp/output"
grep -q 'Required file missing: README.adoc' "$tmp/output"
grep -q 'VALIDATION SUMMARY' "$tmp/output"
echo 'PASS: compliance regression tests (missing state/workflow/files, silent compiler failures)'
