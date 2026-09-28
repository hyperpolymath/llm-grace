# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# VALIDATION & COMPLIANCE
#
# Imported by ../../Justfile via `import? "build/just/validate.just"`.
# Recipes here check that this repo conforms to the RSR (Rhodium Standard
# Repository) skeleton: required files, METAdata, AI install guide
# completeness, etc. Run via `just validate`.

# Validate RSR compliance
validate-rsr:
    bash scripts/validate-template.sh .
    bash scripts/check-root-shape.sh .
    bash scripts/check-no-md-in-docs.sh .
    bash tests/workflows/validate_workflows_test.sh

# Structural check for the repository's S-expression STATE format, not TOML.
# This is a required-field check, not a full A2ML parser or readiness proof.
validate-state:
    bash scripts/check-state.sh .machine_readable/STATE.a2ml

# Validate AI installation guide completeness (finishbot pre-release check)
validate-ai-install:
    #!/usr/bin/env bash
    echo "=== AI Installation Guide Check ==="
    GUIDE="docs/AI_INSTALLATION_GUIDE.adoc"
    README="README.adoc"
    ERRORS=0

    # Check guide exists
    if [ ! -f "$GUIDE" ]; then
        echo "MISSING: $GUIDE (create from template: docs/AI_INSTALLATION_GUIDE.adoc)"
        ERRORS=$((ERRORS + 1))
    else
        # Check for unfilled TODO markers
        TODOS=$(grep -c '\[TODO-AI-INSTALL' "$GUIDE" 2>/dev/null || true)
        if [ "$TODOS" -gt 0 ]; then
            echo "INCOMPLETE: $GUIDE has $TODOS unfilled [TODO-AI-INSTALL] markers:"
            grep -n '\[TODO-AI-INSTALL' "$GUIDE" | head -10
            ERRORS=$((ERRORS + 1))
        else
            echo "$GUIDE: complete (no TODO markers)"
        fi

        # Check AI implementation section exists
        if ! grep -q 'ai-implementation' "$GUIDE" 2>/dev/null; then
            echo "MISSING: [[ai-implementation]] anchor in $GUIDE"
            ERRORS=$((ERRORS + 1))
        fi

        # Check privacy notice exists
        if ! grep -qi 'privacy' "$GUIDE" 2>/dev/null; then
            echo "MISSING: Privacy notice in $GUIDE"
            ERRORS=$((ERRORS + 1))
        fi

        # Check install commands exist (not just placeholders)
        if ! grep -q 'git clone' "$GUIDE" 2>/dev/null; then
            echo "WARNING: No git clone command found in $GUIDE -- install commands may be incomplete"
        fi
    fi

    # Check README has AI install section
    if [ -f "$README" ]; then
        if ! grep -qi 'AI-Assisted Installation' "$README" 2>/dev/null; then
            echo "MISSING: AI-Assisted Installation section in $README"
            echo "  Copy from docs/AI-INSTALL-README-SECTION.adoc"
            ERRORS=$((ERRORS + 1))
        fi

        # Check README for unfilled TODO markers
        README_TODOS=$(grep -c '\[TODO-AI-INSTALL' "$README" 2>/dev/null || true)
        if [ "$README_TODOS" -gt 0 ]; then
            echo "INCOMPLETE: $README has $README_TODOS unfilled [TODO-AI-INSTALL] markers"
            ERRORS=$((ERRORS + 1))
        fi
    fi

    if [ "$ERRORS" -gt 0 ]; then
        echo ""
        echo "AI install guide: FAIL ($ERRORS issues)"
        exit 1
    fi
    echo "AI install guide: PASS"

# Full validation suite
validate: validate-rsr validate-state validate-ai-install
    @echo "All validations passed!"
