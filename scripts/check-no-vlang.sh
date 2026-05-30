#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# check-no-vlang.sh — enforce "the V language (vlang.io) is banned in the estate".
#
# Estate rule: the V language (vlang.io) is banned. The connector layer is
# `v-unified-api-adapter` (16 endpoints + transaction-firewall gating).
# Treat any V reference as drift and remove it.
#
# Searches for V-specific patterns in tracked files. The .v file
# extension is intentionally NOT used as a marker because Coq theorem files
# share that extension; this check looks at content patterns instead.
#
# NOTE: this check must NEVER match the substring "zig". Zig (ziglang.org)
# is a permitted, first-class estate language and is in fact this repo's
# core language (see docs/decisions/0003-graceful-degradation-architecture.adoc).
# An earlier revision was corrupted by a find/replace that turned the V
# markers into the literal "zig", which wrongly flagged all legitimate Zig
# source; that corruption is removed here.
#
# Excludes:
#   .git/ (vcs internals)
#   node_modules/ (vendored dependencies)
#
# Exit codes:
#   0 — no V references found
#   1 — V references found (treat as drift)
#   2 — usage / setup error

set -euo pipefail

REPO_ROOT="${1:-.}"

# Patterns that uniquely indicate V code, scaffolding, or naming.
# Coq's `.v` extension is not used as a marker (see header).
PATTERNS=(
    'gen-v-connector'
    'V-TRIPLE'
    'v-triple'
    'vlang'
    'connectors/v-'
)

PATTERN_OR=$(IFS='|'; echo "${PATTERNS[*]}")

# Files that document the V ban itself (the rule's own description
# legitimately names "V", "V-TRIPLE", etc.). Excluded by name.
DOC_EXCLUSIONS=(
    "estate-rules.yml"             # the workflow that calls this script
    "check-no-vlang.sh"            # this script itself
    "PLAYBOOK.a2ml"                # documents the [rsr-repo-skeleton] rules
    "feedback_v_lang_banned.md"    # memory entry documenting the ban
    "project_zig_unified_api.md"   # memory entry documenting the replacement
)

EXCLUDE_ARGS=()
for f in "${DOC_EXCLUSIONS[@]}"; do
    EXCLUDE_ARGS+=(--exclude="$f")
done

# Architecture Decision Records under docs/decisions/ legitimately NAME
# the banned tech to *record the decision about it* (e.g. "remove all
# V sources"). They are meta-policy prose, not template body that
# clones into a downstream project, so they are exempt from the content
# scan. Nothing executable lives in an ADR, so this cannot mask real
# V code. Tracked under hyperpolymath/standards#84.
ADR_EXEMPT_RE='(^|/)docs/decisions/'

# Build grep arguments. Use -r to recurse, -n for line numbers, -i for
# case-insensitive matching. Exclude .git, node_modules, files that
# legitimately document the ban, then drop ADR hits post-filter.
HITS=$(grep -rni -E "$PATTERN_OR" "$REPO_ROOT" \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    "${EXCLUDE_ARGS[@]}" \
    2>/dev/null \
    | grep -vE "$ADR_EXEMPT_RE" \
    || true)

if [ -z "$HITS" ]; then
    echo "PASS: no V-language references"
    exit 0
fi

# Count matches
LINES=$(echo "$HITS" | wc -l | tr -d ' ')

echo "FAIL: $LINES V-language reference(s) found (estate rule: the V language is banned):" >&2
echo "$HITS" | sed 's|^|  |' >&2
echo "" >&2
echo "The V language has been replaced by v-unified-api-adapter. Remove these references." >&2
exit 1
