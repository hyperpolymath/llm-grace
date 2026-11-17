#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Layering controls for the proof-profiles proposal.
# Two files must be accepted and two must be refused. Each exit status is read
# directly, never through a pipe. Exit 0 only when all four behave as stated.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")"
command -v agda >/dev/null || { echo "REFUSED: agda is not installed; this check did not run"; exit 2; }
echo "checker: $(agda --version)"
fail=0
expect() { # expect <accept|refuse> <file>
  LC_ALL=C.UTF-8 agda "$2" >/dev/null 2>&1; rc=$?
  if { [ "$1" = accept ] && [ $rc -eq 0 ]; } || { [ "$1" = refuse ] && [ $rc -ne 0 ]; }; then
    echo "ok    $1 $2 (exit $rc)"
  else
    echo "WRONG $1 $2 (exit $rc)"; fail=1
  fi
}
find . -name '*.agdai' -delete
expect accept Core.agda                         # canonical profile
expect accept CubicalLayer.agda                 # cubical layer imports the canonical core
expect refuse CubicalImportsPlainWithoutK.agda  # --without-K alone cannot be imported by --cubical
expect refuse UsesK.agda                        # K is refused under the canonical profile
find . -name '*.agdai' -delete
exit $fail
