#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# check-no-project-identifiers.sh — keep the RSR template a NEUTRAL skeleton.
#
# Regression guard for hyperpolymath/rsr-template-repo#45: the template had
# been overwritten with a snapshot of the PseudoScript/AffineScript project
# (project-named README/manifests + an embedded `affinescript/` subtree), so
# every downstream repo was born as a project clone.
#
# Three independent checks, any of which fails the build:
#
#   A. Placeholder integrity — the identity/manifest files MUST still carry
#      their `{{PLACEHOLDER}}` markers. This catches *any* project snapshot,
#      not just known names: you cannot commit a real project's name/purpose
#      here without first destroying the placeholder.
#
#   B. No embedded project subtree — no tracked directory may be named after
#      a known estate language/project (the `affinescript/` vector).
#
#   C. No slug leakage — known estate project/language slugs must not appear
#      in tracked files, except occurrences allowlisted in
#      .machine_readable/identifier-allow.txt (the estate TS->AffineScript
#      policy is the only legitimate one).
#
# Exit codes: 0 ok | 1 drift found | 2 usage/setup error

set -euo pipefail

REPO_ROOT="${1:-.}"
ALLOW_FILE=".machine_readable/identifier-allow.txt"
SELF="scripts/check-no-project-identifiers.sh"

if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: $REPO_ROOT is not a git work tree" >&2
    exit 2
fi

# Known estate project / language slugs that must never identify this repo.
BLOCK='pseudoscript|affinescript|rattlescript|ephapax|katagoria|typell|nextgen-typing|the-nash-equilibrium'

# Directory basenames that indicate an embedded project clone.
CLONE_DIRS='pseudoscript affinescript rattlescript ephapax katagoria typell'

fail=0

# ── Check A: placeholder integrity in identity files ─────────────────────────
# file<TAB>required-placeholder (repeat file for multiple requirements)
check_placeholder() {
    local f="$1" needle="$2"
    local path="$REPO_ROOT/$f"
    [ -f "$path" ] || return 0   # absent file is Check-B/own concern, not here
    if ! grep -qF "$needle" "$path"; then
        echo "FAIL[A]: $f no longer contains required placeholder '$needle'" >&2
        echo "         (a real project value was substituted into a template file)" >&2
        fail=1
    fi
}
check_placeholder "README.adoc"                        "{{PROJECT_NAME}}"
check_placeholder "0-AI-MANIFEST.a2ml"                 "{{PROJECT_NAME}}"
check_placeholder "0-AI-MANIFEST.a2ml"                 "{{PROJECT_PURPOSE}}"
check_placeholder ".machine_readable/6a2/ECOSYSTEM.a2ml" "{{PROJECT_NAME}}"
check_placeholder ".machine_readable/ECOSYSTEM.a2ml"   "{{REPO}}"

# ── Check B: no embedded project-clone subtree ───────────────────────────────
while IFS= read -r tracked; do
    IFS='/' read -ra parts <<< "$tracked"
    # Inspect only directory components (drop the basename).
    for ((i=0; i<${#parts[@]}-1; i++)); do
        for slug in $CLONE_DIRS; do
            if [ "${parts[$i]}" = "$slug" ]; then
                echo "FAIL[B]: embedded project subtree detected: $tracked" >&2
                echo "         (directory component '$slug/' is a project clone)" >&2
                fail=1
            fi
        done
    done
done < <(git -C "$REPO_ROOT" ls-files)

# ── Check C: slug leakage outside the allowlist ──────────────────────────────
# Load allowlist: path -> list of needles ('*' = whole file exempt).
declare -A ALLOW
if [ -f "$REPO_ROOT/$ALLOW_FILE" ]; then
    while IFS= read -r row; do
        row="${row%%#*}"
        [ -z "${row// }" ] && continue
        p="${row%%$'\t'*}"; n="${row#*$'\t'}"
        p="$(echo "$p" | sed 's/[[:space:]]*$//')"
        n="$(echo "$n" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        ALLOW["$p"]+="${ALLOW[$p]:+|}$n"
    done < "$REPO_ROOT/$ALLOW_FILE"
fi

is_exempt() {  # path, content -> 0 if exempt
    local path="$1" content="$2" needles="${ALLOW[$1]:-}"
    [ -z "$needles" ] && return 1
    local IFS='|' nlist=() x
    read -ra nlist <<< "$needles"
    for x in "${nlist[@]}"; do
        [ "$x" = "*" ] && return 0
        # strip every case-insensitive occurrence of the allowed needle
        content="$(printf '%s' "$content" | sed "s/$(printf '%s' "$x" | sed 's/[.[\*^$()+?{|/]/\\&/g')//Ig")"
    done
    # exempt only if nothing blocklisted survives
    printf '%s' "$content" | grep -qiE "$BLOCK" && return 1
    return 0
}

while IFS= read -r line; do
    [ -z "$line" ] && continue
    path="${line%%:*}"; rest="${line#*:}"
    lineno="${rest%%:*}"; content="${rest#*:}"
    [ "$path" = "$ALLOW_FILE" ] && continue
    [ "$path" = "$SELF" ] && continue
    [ "$path" = ".machine_readable/ai/PLACEHOLDERS.adoc" ] && continue
    # Architecture Decision Records legitimately name estate projects to
    # *record decisions about them* (e.g. "AffineScript, not ReScript").
    # They are meta-policy prose, not the template identity that clones
    # downstream — Checks A & B still guard identity/subtree separately.
    # Tracked under hyperpolymath/standards#84.
    case "$path" in docs/decisions/*) continue ;; esac
    if ! is_exempt "$path" "$content"; then
        echo "FAIL[C]: project identifier leaked at $path:$lineno" >&2
        echo "         > $(printf '%s' "$content" | sed 's/^[[:space:]]*//' | cut -c1-100)" >&2
        echo "         (remove the project reference, or add a justified row to $ALLOW_FILE)" >&2
        fail=1
    fi
done < <(git -C "$REPO_ROOT" grep -nI -iE "$BLOCK" -- . 2>/dev/null || true)

if [ "$fail" -eq 0 ]; then
    echo "PASS: template is a neutral RSR skeleton (no project identifiers)"
    exit 0
fi
echo "" >&2
echo "Template hygiene failed — origin: hyperpolymath/rsr-template-repo#45;" >&2
echo "scanner-scope/ADR-exemption tracked at hyperpolymath/standards#84." >&2
exit 1
