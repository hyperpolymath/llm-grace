#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Stable developer entrypoint; this repository does not yet ship a service.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT/scripts/dev.sh" "$@"
