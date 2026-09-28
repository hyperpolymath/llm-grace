#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Local, non-installing development entrypoint for llm-grace.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
    cat <<'USAGE'
llm-grace development commands

  scripts/dev.sh help
  scripts/dev.sh doctor       Report required local tools; missing tools fail.
  scripts/dev.sh lint         Check shell syntax and workflow/compliance regressions.
  scripts/dev.sh check        Run lint, Zig formatting, and repository checks.
  scripts/dev.sh test [MODE]  Run the core tests (Debug or ReleaseSafe; default Debug).
  scripts/dev.sh just [ARGS]  Forward arguments to the Just task runner.
  scripts/dev.sh monitor [ARGS] Build and explicitly invoke the read-only monitor.
  scripts/dev.sh status       Report that no service runtime is configured.
  scripts/dev.sh run          Explain why there is no runnable service yet (fails).

This checkout is development scaffolding plus tested primitives. It does not
start a monitor daemon, install hooks, modify global configuration, or deploy.
USAGE
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

doctor() {
    local missing=0 zig_version
    for tool in git zig timeout; do
        if command -v "$tool" >/dev/null 2>&1; then
            printf 'OK   %s: %s\n' "$tool" "$(command -v "$tool")"
        else
            printf 'MISS %s\n' "$tool" >&2
            missing=1
        fi
    done
    if command -v zig >/dev/null 2>&1; then
        zig_version="$(zig version)"
        if [[ "$zig_version" == 0.15.2 ]]; then
            printf 'OK   Zig version: %s\n' "$zig_version"
        else
            printf 'MISS Zig version: expected 0.15.2, found %s\n' "$zig_version" >&2
            missing=1
        fi
    fi
    if command -v just >/dev/null 2>&1; then
        printf 'OK   just: %s\n' "$(just --version)"
    else
        printf 'INFO just is optional; scripts/dev.sh works without it\n'
    fi
    if [[ -n "${LMDB_PREFIX:-}" ]]; then
        if [[ -f "$LMDB_PREFIX/include/lmdb.h" && -f "$LMDB_PREFIX/lib/liblmdb.a" ]]; then
            printf 'OK   LMDB_PREFIX: %s\n' "$LMDB_PREFIX"
        else
            printf 'MISS LMDB_PREFIX must contain include/lmdb.h and lib/liblmdb.a\n' >&2
            missing=1
        fi
    elif [[ -f /usr/include/lmdb.h ]] && (ldconfig -p 2>/dev/null | grep -q 'liblmdb\.so' || [[ -f /usr/lib/liblmdb.a || -f /usr/lib/x86_64-linux-gnu/liblmdb.a ]]); then
        printf 'OK   LMDB: system headers and library found\n'
    else
        printf 'MISS LMDB development headers/library (set LMDB_PREFIX if non-system)\n' >&2
        missing=1
    fi
    (( missing == 0 )) || return 1
}

check_shell_syntax() {
    local checked=0 path
    while IFS= read -r -d '' path; do
        bash -n "$path"
        checked=$((checked + 1))
    done < <(find scripts tests .claude container session -type f -name '*.sh' -print0 2>/dev/null)
    printf 'Shell syntax: %d scripts checked\n' "$checked"
}

run_lint() {
    check_shell_syntax
    bash tests/workflows/validate_workflows_test.sh
    bash tests/workflows/compliance_regression_test.sh
    bash tests/workflows/dev_entrypoints_test.sh
}

run_check() {
    need zig
    [[ "$(zig version)" == 0.15.2 ]] || fail "Zig 0.15.2 required (found $(zig version))"
    zig fmt --check src/signal src/control src/ledger src/monitor
    run_lint
    bash scripts/check-root-shape.sh .
    bash scripts/check-state.sh
    printf 'Implemented local checks passed. This is not a release or security certification.\n'
}

command_name="${1:-help}"
if (($# > 0)); then shift; fi
case "$command_name" in
    help|-h|--help)
        usage
        ;;
    version|--version|-V)
        sha="$(git rev-parse --short HEAD 2>/dev/null || printf unknown)"
        platform="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
        printf 'llm-grace-dev 0.1.0 (%s) [%s]\n' "$sha" "$platform"
        ;;
    status|--status)
        printf 'No application or monitor service is configured; no process was queried.\n'
        ;;
    stop|--stop)
        printf 'No application or monitor service is configured; nothing was stopped.\n'
        ;;
    doctor)
        doctor
        ;;
    lint)
        (($# == 0)) || fail "lint takes no arguments"
        run_lint
        ;;
    check)
        (($# == 0)) || fail "check takes no arguments"
        run_check
        ;;
    test)
        mode="${1:-Debug}"
        (($# <= 1)) || fail "test accepts at most one mode: Debug or ReleaseSafe"
        case "$mode" in Debug|ReleaseSafe) ;; *) fail "unsupported test mode '$mode' (use Debug or ReleaseSafe)" ;; esac
        exec bash scripts/test-core.sh -O "$mode"
        ;;
    just)
        need just
        exec just "$@"
        ;;
    monitor|observe)
        [[ "${1:-}" != -- ]] || shift
        need zig
        [[ "$(zig version)" == 0.15.2 ]] || fail "Zig 0.15.2 required (found $(zig version))"
        mkdir -p zig-out/bin
        zig build-exe --dep monitor --dep sampler -Mroot=src/monitor/main.zig -lc --dep sampler -Mmonitor=src/monitor/monitor.zig -Msampler=src/signal/sampler.zig -O Debug -femit-bin=zig-out/bin/llm-grace-monitor
        exec zig-out/bin/llm-grace-monitor "$@"
        ;;
    build|build-release|install)
        fail "there is no root application build/install target; use 'scripts/dev.sh monitor --once' for the explicit read-only observer"
        ;;
    run|run-verbose|start|--start|--auto|--browser|--web|--integ|--disinteg)
        fail "there is no application or managed service to launch or integrate; use 'scripts/dev.sh monitor --once' for explicit read-only observation"
        ;;
    *)
        fail "unknown command '$command_name' (run scripts/dev.sh help)"
        ;;
esac
