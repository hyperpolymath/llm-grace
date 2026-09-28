# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# RSR Standard Justfile Template
# https://just.systems/man/en/
#
# Copy this file to new projects and customize the placeholder values.
#
# Run `just` to see all available recipes
# Run `just cookbook` to generate docs/just-cookbook.adoc
# Run `just combinations` to see matrix recipe options

set shell := ["bash", "-uc"]
set dotenv-load := true
set positional-arguments := true

# Import auto-generated contractile recipes (must-check, trust-verify, etc.)
# Re-generate with: contractile gen-just
import? "build/contractile.just"

# Project metadata — customize these
project := "llm-grace"
OWNER := "hyperpolymath"
REPO := "llm-grace"
version := "0.1.0"
tier := "infrastructure"  # 1 | 2 | infrastructure

# ═══════════════════════════════════════════════════════════════════════════════
# DEFAULT & HELP
# ═══════════════════════════════════════════════════════════════════════════════

# Show all available recipes with descriptions
default:
    @just --list --unsorted

# Show detailed help for a specific recipe
help recipe="":
    #!/usr/bin/env bash
    if [ -z "{{recipe}}" ]; then
        just --list --unsorted
        echo ""
        echo "Usage: just help <recipe>"
        echo "       just cookbook     # Generate full documentation"
        echo "       just combinations # Show matrix recipes"
    else
        just --show "{{recipe}}" 2>/dev/null || echo "Recipe '{{recipe}}' not found"
    fi

# Show this project's info
info:
    @echo "Project: llm_grace"
    @echo "Version: {{version}}"
    @echo "RSR Tier: {{tier}}"
    @echo "Recipes: $(just --summary | wc -w)"
    @[ -f ".machine_readable/STATE.a2ml" ] && grep -oP 'phase\s*=\s*"\K[^"]+' .machine_readable/STATE.a2ml | head -1 | xargs -I{} echo "Phase: {}" || true

# Run Invariant Path overlay tools for this repository
invariant-path *ARGS:
    ./scripts/invariant-path.sh {{ARGS}}

# ═══════════════════════════════════════════════════════════════════════════════
# INIT — see build/just/init.just
# ═══════════════════════════════════════════════════════════════════════════════

import? "build/just/init.just"

# ═══════════════════════════════════════════════════════════════════════════════
# GROOVE PROTOCOL — see build/just/groove.just
# ═══════════════════════════════════════════════════════════════════════════════

import? "build/just/groove.just"

# ═══════════════════════════════════════════════════════════════════════════════
# PROJECT SELF-ASSESSMENT + OPENSSF COMPLIANCE — see build/just/assess.just
# ═══════════════════════════════════════════════════════════════════════════════

import? "build/just/assess.just"

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD & COMPILE
# ═══════════════════════════════════════════════════════════════════════════════

# No root application target exists yet; fail clearly instead of printing fake success.
build *args:
    @bash scripts/dev.sh build {{args}}

build-release *args:
    @bash scripts/dev.sh build-release {{args}}

build-watch:
    @echo "ERROR: no application build/watch target exists yet" >&2
    @exit 1

# Remove only known generated Zig outputs; never remove the tracked build/ source tree.
clean:
    @rm -rf -- .zig-cache zig-out

clean-all: clean

# Run real core tests (LMDB headers/library required; optional LMDB_PREFIX).
test mode="Debug":
    bash scripts/dev.sh test {{mode}}

# Explicitly build and run the read-only observer; use `-- --once` for one epoch.
monitor *args:
    bash scripts/dev.sh monitor {{args}}

# Zig's test runner already reports each named test and its outcome.
test-verbose:
    just test

# Pure signal smoke test (no LMDB required).
test-smoke:
    zig test src/signal/sampler.zig

# End-to-end monitor/hook tests are not implemented; never report fake success.
e2e:
    @echo "ERROR: live monitor/hook acceptance suite is not implemented (issue #4)" >&2
    @exit 1

# Run the repository's implemented cross-cutting checks.
aspect:
    bash tests/aspect_tests.sh

# No benchmark suite is implemented; do not claim benchmark success.
bench:
    @echo "ERROR: no reproducible benchmark suite is implemented" >&2
    @exit 1

# Run the structural template validator; this is not a release certification.
readiness:
    bash scripts/validate-template.sh .

# Print the current CRG grade (reads from READINESS.md '**Current Grade:** X' line)
crg-grade:
    @grade=$$(grep -oP '(?<=\*\*Current Grade:\*\* )[A-FX]' READINESS.md 2>/dev/null | head -1); \
    [ -z "$$grade" ] && grade="X"; \
    echo "$$grade"

# Print a shields.io CRG badge for embedding in README files
# Looks for '**Current Grade:** X' in READINESS.md; falls back to X
crg-badge:
    @grade=$$(grep -oP '(?<=\*\*Current Grade:\*\* )[A-FX]' READINESS.md 2>/dev/null | head -1); \
    [ -z "$$grade" ] && grade="X"; \
    case "$$grade" in \
      A) color="brightgreen" ;; \
      B) color="green" ;; \
      C) color="yellow" ;; \
      D) color="orange" ;; \
      E) color="red" ;; \
      F) color="critical" ;; \
      *) color="lightgrey" ;; \
    esac; \
    echo "[![CRG $$grade](https://img.shields.io/badge/CRG-$$grade-$$color?style=flat-square)](https://github.com/hyperpolymath/standards/tree/main/component-readiness-grades)"

# Run currently implemented local suites. E2E/pressure acceptance remains a separate open gate.
test-all: test aspect lint validate-state

# Run implemented fast structural, syntax, workflow, and formatting checks.
check:
    bash scripts/dev.sh check

# Run all implemented quality checks (core tests require LMDB).
quality: fmt-check lint aspect test
    @echo "Configured local quality checks passed; consult compliance review for remaining release/security gates."

# Fix all auto-fixable issues [reversible: git checkout]
fix: fmt
    @echo "Fixed all auto-fixable issues"

# ═══════════════════════════════════════════════════════════════════════════════
# LINT & FORMAT
# ═══════════════════════════════════════════════════════════════════════════════

# Format Zig source files only.
fmt:
    zig fmt src/signal src/control src/ledger src/monitor

# Check formatting without changing files.
fmt-check:
    zig fmt --check src/signal src/control src/ledger src/monitor

# Shell syntax plus workflow/compliance regression checks (not a full static analysis suite).
lint:
    bash scripts/dev.sh lint

# ═══════════════════════════════════════════════════════════════════════════════
# RUN & EXECUTE
# ═══════════════════════════════════════════════════════════════════════════════

# There is no app or daemon binary to launch or install yet.
run *args:
    @bash scripts/dev.sh run {{args}}

run-verbose *args:
    @bash scripts/dev.sh run-verbose {{args}}

install:
    @bash scripts/dev.sh install

# ═══════════════════════════════════════════════════════════════════════════════
# DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════════

# Check required tools without installing anything.
deps:
    bash scripts/dev.sh doctor

# Audit dependencies for vulnerabilities
deps-audit:
    @command -v trivy >/dev/null || { echo "ERROR: trivy is required" >&2; exit 1; }
    trivy fs --severity HIGH,CRITICAL --exit-code 1 .


# ═══════════════════════════════════════════════════════════════════════════════
# DOCUMENTATION
# ═══════════════════════════════════════════════════════════════════════════════

# Generate all documentation
docs:
    @mkdir -p docs/generated docs/man
    just cookbook
    just man
    @echo "Documentation generated in docs/"

# Generate justfile cookbook documentation
cookbook:
    #!/usr/bin/env bash
    mkdir -p docs
    OUTPUT="docs/just-cookbook.adoc"
    echo "= llm_grace Justfile Cookbook" > "$OUTPUT"
    echo ":toc: left" >> "$OUTPUT"
    echo ":toclevels: 3" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    echo "Generated: $(date -Iseconds)" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    echo "== Recipes" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    just --list --unsorted | while read -r line; do
        if [[ "$line" =~ ^[[:space:]]+([a-z_-]+) ]]; then
            recipe="${BASH_REMATCH[1]}"
            echo "=== $recipe" >> "$OUTPUT"
            echo "" >> "$OUTPUT"
            echo "[source,bash]" >> "$OUTPUT"
            echo "----" >> "$OUTPUT"
            echo "just $recipe" >> "$OUTPUT"
            echo "----" >> "$OUTPUT"
            echo "" >> "$OUTPUT"
        fi
    done
    echo "Generated: $OUTPUT"

# Generate man page
man:
    #!/usr/bin/env bash
    mkdir -p docs/man
    cat > docs/man/llm_grace.1 << EOF
    .TH llm_grace 1 "$(date +%Y-%m-%d)" "{{version}}" "llm_grace Manual"
    .SH NAME
    llm_grace \- RSR-compliant project
    .SH SYNOPSIS
    .B just
    [recipe] [args...]
    .SH DESCRIPTION
    RSR (Rhodium Standard Repository) project managed with just.
    .SH AUTHOR
    $(git config user.name 2>/dev/null || echo "Author") <$(git config user.email 2>/dev/null || echo "email")>
    EOF
    echo "Generated: docs/man/llm_grace.1"

# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINERS (stapeln ecosystem — Podman + Chainguard Wolfi)
# ═══════════════════════════════════════════════════════════════════════════════

# Initialise container templates — substitute placeholders with project values
container-init:
    #!/usr/bin/env bash
    set -euo pipefail

    if [ ! -d "container" ]; then
        echo "Error: container/ directory not found."
        echo "This repo may not have been created from rsr-template-repo."
        exit 1
    fi

    echo "=== Container Template Initialisation ==="
    echo ""

    # Load RSR defaults if available
    DEFAULTS="${XDG_CONFIG_HOME:-$HOME/.config}/rsr/defaults"
    if [ -f "$DEFAULTS" ]; then
        echo "Loading defaults from $DEFAULTS"
        # shellcheck source=/dev/null
        source "$DEFAULTS"
        echo ""
    fi

    # Prompt for container-specific values
    read -rp "Service name (e.g. my-api) [llm_grace]: " _SERVICE_NAME
    SERVICE_NAME="${_SERVICE_NAME:-llm_grace}"

    read -rp "Primary port [8080]: " _PORT
    PORT="${_PORT:-8080}"

    read -rp "Container registry [ghcr.io/${OWNER:-hyperpolymath}]: " _REGISTRY
    REGISTRY="${_REGISTRY:-ghcr.io/${OWNER:-hyperpolymath}}"

    echo ""
    echo "  Service: $SERVICE_NAME"
    echo "  Port:    $PORT"
    echo "  Registry: $REGISTRY"
    echo ""
    read -rp "Proceed? [Y/n] " CONFIRM
    [[ "${CONFIRM:-Y}" =~ ^[Nn] ]] && echo "Aborted." && exit 0

    echo ""
    echo "Replacing container placeholders..."

    # Brace tokens as variables (hex escapes avoid just interpolation)
    LB=$(printf '\x7b\x7b')
    RB=$(printf '\x7d\x7d')

    SED_ARGS=(
        -e "s|${LB}SERVICE_NAME${RB}|${SERVICE_NAME}|g"
        -e "s|${LB}PORT${RB}|${PORT}|g"
        -e "s|${LB}REGISTRY${RB}|${REGISTRY}|g"
    )

    find container/ -type f | while read -r file; do
        if file --brief "$file" | grep -qi 'text\|ascii\|utf'; then
            sed -i "${SED_ARGS[@]}" "$file"
        fi
    done

    echo "Container templates initialised."
    echo ""
    echo "Next steps:"
    echo "  1. Edit container/Containerfile — add your build commands"
    echo "  2. Edit container/entrypoint.sh — set your application binary"
    echo "  3. Review container/compose.toml — adjust services and volumes"
    echo "  4. Build: just container-build"

# Build container image via cerro-torre pipeline
container-build *args:
    #!/usr/bin/env bash
    if [ -f "container/ct-build.sh" ]; then
        cd container && ./ct-build.sh {{args}}
    elif [ -f "container/Containerfile" ]; then
        podman build -t llm_grace:latest -f container/Containerfile .
    elif [ -f "build/Containerfile" ]; then
        podman build -t llm_grace:latest -f build/Containerfile .
    elif [ -f "Containerfile" ]; then
        podman build -t llm_grace:latest -f Containerfile .
    else
        echo "No Containerfile found in container/, build/, or project root"
        exit 1
    fi

# Verify compose configuration
container-verify:
    #!/usr/bin/env bash
    if [ ! -f "container/compose.toml" ]; then
        echo "No container/compose.toml found"
        exit 1
    fi
    cd container
    if command -v selur-compose &>/dev/null; then
        selur-compose verify
    else
        echo "selur-compose not found, falling back to podman compose"
        podman compose --file compose.toml config
    fi

# Start container stack
container-up *args:
    #!/usr/bin/env bash
    if [ ! -f "container/compose.toml" ]; then
        echo "No container/compose.toml found"
        exit 1
    fi
    cd container
    if command -v selur-compose &>/dev/null; then
        selur-compose up {{args}}
    else
        podman compose --file compose.toml up {{args}}
    fi

# Stop container stack
container-down:
    #!/usr/bin/env bash
    cd container 2>/dev/null || { echo "No container/ directory"; exit 1; }
    if command -v selur-compose &>/dev/null; then
        selur-compose down
    else
        podman compose --file compose.toml down
    fi

# Sign and verify container bundle (build + pack + sign + verify)
container-sign:
    #!/usr/bin/env bash
    if [ -f "container/ct-build.sh" ]; then
        cd container && ./ct-build.sh
    else
        echo "No container/ct-build.sh found"
        exit 1
    fi

# Push signed bundle to registry
container-push:
    #!/usr/bin/env bash
    if [ -f "container/ct-build.sh" ]; then
        cd container && ./ct-build.sh --push
    else
        echo "No container/ct-build.sh found — falling back to podman push"
        podman push llm_grace:latest
    fi

# Run container interactively (for debugging)
container-run *args:
    podman run --rm -it llm_grace:latest {{args}}

# ═══════════════════════════════════════════════════════════════════════════════
# CI & AUTOMATION
# ═══════════════════════════════════════════════════════════════════════════════

# Run full CI pipeline locally
ci: deps quality

# Install git hooks
install-hooks:
    @mkdir -p .git/hooks
    @cat > .git/hooks/pre-commit << 'HOOKEOF'
    #!/bin/bash
    just fmt-check || exit 1
    just lint || exit 1
    just assail || exit 1
    HOOKEOF
    @chmod +x .git/hooks/pre-commit
    @echo "Git hooks installed"

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY
# ═══════════════════════════════════════════════════════════════════════════════

# Run security audit
security: deps-audit
    @command -v gitleaks >/dev/null || { echo "ERROR: gitleaks is required" >&2; exit 1; }
    gitleaks detect --source . --redact

# Generate SBOM
sbom:
    @command -v syft >/dev/null || { echo "ERROR: syft is required to generate an SBOM" >&2; exit 1; }
    @mkdir -p docs/security
    syft . -o spdx-json > docs/security/sbom.spdx.json

# ═══════════════════════════════════════════════════════════════════════════════
# VALIDATION & COMPLIANCE — see build/just/validate.just
# ═══════════════════════════════════════════════════════════════════════════════

import? "build/just/validate.just"

# ═══════════════════════════════════════════════════════════════════════════════
# STATE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

# Update STATE.a2ml timestamp
state-touch:
    @if [ -f ".machine_readable/STATE.a2ml" ]; then \
        sed -i 's/last-updated = "[^"]*"/last-updated = "'"$(date +%Y-%m-%d)"'"/' .machine_readable/STATE.a2ml && \
        echo "STATE.a2ml timestamp updated"; \
    fi

# Show current phase from STATE.a2ml
state-phase:
    @grep -oP 'phase\s*=\s*"\K[^"]+' .machine_readable/STATE.a2ml 2>/dev/null | head -1 || echo "unknown"

# ═══════════════════════════════════════════════════════════════════════════════
# GUIX & NIX
# ═══════════════════════════════════════════════════════════════════════════════

# Enter Guix development shell (primary)
guix-shell:
    guix shell -D -f guix.scm

# Build with Guix
guix-build:
    guix build -f guix.scm

# Enter Nix development shell (fallback)
nix-shell:
    @if [ -f "flake.nix" ]; then nix develop; else echo "No flake.nix"; fi

# ═══════════════════════════════════════════════════════════════════════════════
# HYBRID AUTOMATION
# ═══════════════════════════════════════════════════════════════════════════════

# Run local automation tasks
automate task="all":
    #!/usr/bin/env bash
    case "{{task}}" in
        all) just fmt && just lint && just test && just docs && just state-touch ;;
        cleanup) just clean && find . -name "*.orig" -delete && find . -name "*~" -delete ;;
        update) just deps && just validate ;;
        *) echo "Unknown: {{task}}. Use: all, cleanup, update" && exit 1 ;;
    esac

# ═══════════════════════════════════════════════════════════════════════════════
# COMBINATORIC MATRIX RECIPES
# ═══════════════════════════════════════════════════════════════════════════════

# Build matrix: [debug|release] x [target] x [features]
build-matrix mode="debug" target="" features="":
    @echo "Build matrix: mode={{mode}} target={{target}} features={{features}}"

# Test matrix: [unit|integration|e2e|all] x [verbosity] x [parallel]
test-matrix suite="unit" verbosity="normal" parallel="true":
    @echo "Test matrix: suite={{suite}} verbosity={{verbosity}} parallel={{parallel}}"

# Container matrix: [build|run|push|shell|scan] x [registry] x [tag]
container-matrix action="build" registry="ghcr.io/hyperpolymath" tag="latest":
    @echo "Container matrix: action={{action}} registry={{registry}} tag={{tag}}"

# CI matrix: [lint|test|build|security|all] x [quick|full]
ci-matrix stage="all" depth="quick":
    @echo "CI matrix: stage={{stage}} depth={{depth}}"

# Show all matrix combinations
combinations:
    @echo "=== Combinatoric Matrix Recipes ==="
    @echo ""
    @echo "Build Matrix: just build-matrix [debug|release] [target] [features]"
    @echo "Test Matrix:  just test-matrix [unit|integration|e2e|all] [verbosity] [parallel]"
    @echo "Container:    just container-matrix [build|run|push|shell|scan] [registry] [tag]"
    @echo "CI Matrix:    just ci-matrix [lint|test|build|security|all] [quick|full]"

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION CONTROL
# ═══════════════════════════════════════════════════════════════════════════════

# Show git status
status:
    @git status --short

# Show recent commits
log count="20":
    @git log --oneline -{{count}}

# Generate CHANGELOG.md with git-cliff
changelog:
    @command -v git-cliff >/dev/null || { echo "git-cliff not found — install: cargo install git-cliff"; exit 1; }
    git cliff --config .machine_readable/configs/git-cliff/cliff.toml --output CHANGELOG.md
    @echo "Generated CHANGELOG.md"

# Preview changelog for unreleased commits (does not write)
changelog-preview:
    @command -v git-cliff >/dev/null || { echo "git-cliff not found — install: cargo install git-cliff"; exit 1; }
    git cliff --config .machine_readable/configs/git-cliff/cliff.toml --unreleased --strip header

# Tag a new release (usage: just release-tag 1.2.3)
release-tag version:
    #!/usr/bin/env bash
    TAG="v{{version}}"
    if git rev-parse "$TAG" >/dev/null 2>&1; then
        echo "Tag $TAG already exists"
        exit 1
    fi
    just changelog
    git add CHANGELOG.md
    git commit -m "chore(release): prepare $TAG"
    git tag -a "$TAG" -m "Release $TAG"
    echo "Created tag $TAG — push with: git push origin main --tags"

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

# Count lines of code
loc:
    @find . \( -name "*.rs" -o -name "*.ex" -o -name "*.exs" -o -name "*.res" -o -name "*.gleam" -o -name "*.zig" -o -name "*.idr" -o -name "*.hs" -o -name "*.ncl" -o -name "*.scm" -o -name "*.adb" -o -name "*.ads" \) -not -path './target/*' -not -path './_build/*' 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 || echo "0"

# Show TODO comments
todos:
    @grep -rn "TODO\|FIXME\|HACK\|XXX" --include="*.rs" --include="*.ex" --include="*.res" --include="*.gleam" --include="*.zig" --include="*.idr" --include="*.hs" . 2>/dev/null || echo "No TODOs"

# Open in editor
edit:
    ${EDITOR:-code} .

# Run high-rigor security assault using panic-attacker
maint-assault:
    @./.machine_readable/scripts/maintenance/maint-assault.sh

# Run panic-attacker pre-commit scan (foundational floor-raise requirement)
assail:
    @command -v panic-attack >/dev/null 2>&1 || { echo "ERROR: panic-attack is required" >&2; exit 1; }
    panic-attack assail .


# Report toolchain readiness without installing packages.
doctor:
    bash scripts/dev.sh doctor

# Guided tour of key features
tour:
    @echo "=== {{project}} Tour ==="
    @echo ""
    @echo "1. Project structure:"
    @ls -la
    @echo ""
    @echo "2. Available commands: just --list"
    @echo ""
    @echo "3. Read README.adoc for full overview"
    @echo "4. Read EXPLAINME.adoc for architecture decisions"
    @echo "5. Run 'just doctor' to check your setup"
    @echo ""
    @echo "Tour complete! Try 'just --list' to see all available commands."

# Open feedback channel with diagnostic context
help-me:
    @echo "=== {{project}} Help ==="
    @echo "Platform: $(uname -s) $(uname -m)"
    @echo "Shell: $SHELL"
    @echo ""
    @echo "To report an issue:"
    @echo "  https://github.com/{{OWNER}}/{{REPO}}/issues/new"
    @echo ""
    @echo "Include the output of 'just doctor' in your report."

# ═══════════════════════════════════════════════════════════════════════════════
# FORMAL VERIFICATION (PROOFS) — see build/just/proofs.just
# ═══════════════════════════════════════════════════════════════════════════════

import? "build/just/proofs.just"

# ═══════════════════════════════════════════════════════════════════════════════
# SESSION MANAGEMENT (THIN BINDINGS TO CENTRAL STANDARDS)
# ═══════════════════════════════════════════════════════════════════════════════

# Show canonical session-management command model
session-help:
    @echo "Canonical command model:"
    @echo "  intake repo <path>"
    @echo "  checkpoint change <path>"
    @echo "  verify maintenance <path>"
    @echo "  verify substantial <path>"
    @echo "  verify release <path>"
    @echo "  close planned <path>"
    @echo "  close urgent <path>"
    @echo "  recover repo <path>"
    @echo "  handover full <path>"
    @echo "  handover split <path>"
    @echo "  handover model <path>"
    @echo "  handover human <path>"
    @echo ""
    @echo "Use Just aliases below (thin wrappers around ./session/dispatch.sh)."

# Canonical aliases (friendly recipe names that map to canonical commands)
intake-repo path=".":
    @./session/dispatch.sh intake repo "{{path}}"

checkpoint-change path=".":
    @./session/dispatch.sh checkpoint change "{{path}}"

verify-maintenance path=".":
    @./session/dispatch.sh verify maintenance "{{path}}"

verify-substantial path=".":
    @./session/dispatch.sh verify substantial "{{path}}"

verify-release path=".":
    @./session/dispatch.sh verify release "{{path}}"

close-planned path=".":
    @./session/dispatch.sh close planned "{{path}}"

close-urgent path=".":
    @./session/dispatch.sh close urgent "{{path}}"

recover-repo path=".":
    @./session/dispatch.sh recover repo "{{path}}"

handover-full path=".":
    @./session/dispatch.sh handover full "{{path}}"

handover-split path=".":
    @./session/dispatch.sh handover split "{{path}}"

handover-model path=".":
    @./session/dispatch.sh handover model "{{path}}"

handover-human path=".":
    @./session/dispatch.sh handover human "{{path}}"
