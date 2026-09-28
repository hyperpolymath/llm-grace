<!--
SPDX-License-Identifier: MPL-2.0
SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

# Claude Code instructions for llm-grace

Read these repository sources before acting:

1. `0-AI-MANIFEST.a2ml` and `.machine_readable/STATE.a2ml`.
2. `docs/practice/AI-CONVENTIONS.adoc` and `.machine_readable/6a2/AGENTIC.a2ml`.
3. For issue #4, ADR-0003, ADR-0004, ADR-0006, and
   `docs/governance/COMPLIANCE-REVIEW.adoc`.

## Safety and evidence

- Issue #2 is owner-only. Do not edit existing SPDX/license declarations or
  claim legal clearance.
- The monitor is observe-only. Do not install global hooks, signal user
  processes, create memory pressure, or connect this work to enforcement.
- Treat fixture tests, a live one-epoch read, and production acceptance as
  different evidence. Never call issue #4 closed or claim the repository is
  security/quality issue-free without the remaining ADR-0006 criteria.
- Do not silently skip a missing tool or turn an unsupported operation into a
  green result. State which checks ran and which did not.

## Local entrypoints

- `scripts/run.sh help` is the stable shell entrypoint.
- `scripts/dev.sh check` runs implemented local structural, syntax, and format
  checks; `scripts/dev.sh test [Debug|ReleaseSafe]` runs core tests.
- `just --list` shows the task interface. Just recipes must delegate to real
  commands or fail explicitly; no placeholder success messages.

This checkout has no runnable monitor daemon or installable application yet.
Do not represent the developer entrypoint as a desktop/service launcher or
install it into user/system locations.
