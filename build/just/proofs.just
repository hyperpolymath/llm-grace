# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# FORMAL VERIFICATION (PROOFS)
#
# Imported by ../../Justfile via `import? "build/just/proofs.just"`.
# Recipes here check formal proofs across Idris2, Lean4, Agda, and Coq, plus
# scan for dangerous/unsafe constructs and report status. Run via
# `just proof-check-all` for the full sweep.

# Check all formal proofs (Idris2 + Lean4 + Agda + Coq)
proof-check-all: proof-check-idris2 proof-check-lean4 proof-check-agda proof-check-coq proof-scan-dangerous
    @echo "=== All proof checks complete ==="

# Check Idris2 proofs (ABI, types, dependent type proofs)
proof-check-idris2:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Checking Idris2 proofs ==="
    if ! command -v idris2 &>/dev/null; then
        echo "SKIP: idris2 not installed"
        exit 0
    fi
    ERRORS=0
    for f in $(find verification/proofs/idris2 -name '*.idr' 2>/dev/null); do
        echo -n "  Checking $f ... "
        if idris2 --check "$f" 2>/dev/null; then
            echo "OK"
        else
            echo "FAIL"
            ERRORS=$((ERRORS + 1))
        fi
    done
    if [ "$ERRORS" -gt 0 ]; then
        echo "FAIL: $ERRORS Idris2 proof(s) failed"
        exit 1
    fi
    echo "PASS: All Idris2 proofs verified"

# Check Lean4 proofs
proof-check-lean4:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Checking Lean4 proofs ==="
    if ! command -v lean &>/dev/null; then
        echo "SKIP: lean not installed"
        exit 0
    fi
    ERRORS=0
    for f in $(find verification/proofs/lean4 -name '*.lean' 2>/dev/null); do
        echo -n "  Checking $f ... "
        if lean "$f" 2>/dev/null; then
            echo "OK"
        else
            echo "FAIL"
            ERRORS=$((ERRORS + 1))
        fi
    done
    if [ "$ERRORS" -gt 0 ]; then
        echo "FAIL: $ERRORS Lean4 proof(s) failed"
        exit 1
    fi
    echo "PASS: All Lean4 proofs verified"

# Check Agda proofs
proof-check-agda:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Checking Agda proofs ==="
    if ! command -v agda &>/dev/null; then
        echo "SKIP: agda not installed"
        exit 0
    fi
    ERRORS=0
    for f in $(find verification/proofs/agda -name '*.agda' 2>/dev/null); do
        echo -n "  Checking $f ... "
        if agda --safe "$f" 2>/dev/null; then
            echo "OK"
        else
            echo "FAIL"
            ERRORS=$((ERRORS + 1))
        fi
    done
    if [ "$ERRORS" -gt 0 ]; then
        echo "FAIL: $ERRORS Agda proof(s) failed"
        exit 1
    fi
    echo "PASS: All Agda proofs verified"

# Check Coq proofs
proof-check-coq:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Checking Coq proofs ==="
    if ! command -v coqc &>/dev/null; then
        echo "SKIP: coqc not installed"
        exit 0
    fi
    ERRORS=0
    for f in $(find verification/proofs/coq -name '*.v' 2>/dev/null); do
        echo -n "  Checking $f ... "
        if coqc "$f" 2>/dev/null; then
            echo "OK"
        else
            echo "FAIL"
            ERRORS=$((ERRORS + 1))
        fi
    done
    if [ "$ERRORS" -gt 0 ]; then
        echo "FAIL: $ERRORS Coq proof(s) failed"
        exit 1
    fi
    echo "PASS: All Coq proofs verified"

# Scan for dangerous patterns in proof files (believe_me, sorry, Admitted, etc.)
proof-scan-dangerous:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Scanning for dangerous patterns in proofs ==="
    DANGEROUS=0
    PATTERNS="believe_me|assert_total|postulate|sorry|Admitted|unsafeCoerce|Obj\.magic"
    for f in $(find verification/proofs -name '*.idr' -o -name '*.lean' -o -name '*.agda' -o -name '*.v' 2>/dev/null); do
        MATCHES=$(grep -nE "$PATTERNS" "$f" 2>/dev/null || true)
        if [ -n "$MATCHES" ]; then
            echo "  DANGEROUS: $f"
            echo "$MATCHES" | sed 's/^/    /'
            DANGEROUS=$((DANGEROUS + 1))
        fi
    done
    if [ "$DANGEROUS" -gt 0 ]; then
        echo "FAIL: $DANGEROUS file(s) contain dangerous patterns"
        exit 1
    fi
    echo "PASS: No dangerous patterns found in proofs"

# Show proof status summary
proof-status:
    #!/usr/bin/env bash
    echo "=== Proof Status ==="
    echo ""
    echo "Idris2: $(find verification/proofs/idris2 -name '*.idr' 2>/dev/null | wc -l) files"
    echo "Lean4:  $(find verification/proofs/lean4 -name '*.lean' 2>/dev/null | wc -l) files"
    echo "Agda:   $(find verification/proofs/agda -name '*.agda' 2>/dev/null | wc -l) files"
    echo "Coq:    $(find verification/proofs/coq -name '*.v' 2>/dev/null | wc -l) files"
    echo "TLA+:   $(find verification/proofs/tlaplus -name '*.tla' 2>/dev/null | wc -l) files"
    echo ""
    # PROOF-STATUS may live at root, docs/status/ (post-#20), .md or .adoc (post-#23)
    for candidate in docs/status/PROOF-STATUS.adoc docs/status/PROOF-STATUS.md PROOF-STATUS.adoc PROOF-STATUS.md; do
        if [ -f "$candidate" ]; then
            grep -E "^\| \*\*Total\*\*|^\| \*Total\*" "$candidate" 2>/dev/null || echo "(No summary row in $candidate)"
            exit 0
        fi
    done
    echo "(No PROOF-STATUS file found at root or docs/status/)"
