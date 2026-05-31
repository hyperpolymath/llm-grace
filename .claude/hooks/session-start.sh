#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# SessionStart hook for Claude Code on the web. Best-effort and idempotent:
# ensures the lint/compliance tools this repo's checks rely on are present so
# a fresh session can run scripts/check-*.sh and `reuse lint` without manual
# setup.
#
# Installs ONLY via standard package managers (pip / apt / gem) — there is
# deliberately no piped remote script (no `curl ... | bash`). Never blocks a
# session: each step is guarded by a `command -v` probe and trails `|| true`.
set -u

note() { printf '[session-start] %s\n' "$*"; }

command -v reuse       >/dev/null 2>&1 || { note "installing reuse (pip)";       pip install --quiet reuse        >/dev/null 2>&1 || true; }
command -v shellcheck  >/dev/null 2>&1 || { note "installing shellcheck (apt)";  apt-get install -y shellcheck    >/dev/null 2>&1 || true; }
command -v asciidoctor >/dev/null 2>&1 || { note "installing asciidoctor (gem)"; gem install --silent asciidoctor >/dev/null 2>&1 || true; }

have() { command -v "$1" >/dev/null 2>&1 && echo y || echo n; }
note "tooling present: reuse=$(have reuse) shellcheck=$(have shellcheck) asciidoctor=$(have asciidoctor)"
note "(the 'just' task runner is not auto-installed here; add it manually if you want recipe shortcuts)"
exit 0
