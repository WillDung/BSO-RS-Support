---
mode: agent
description: Review changed files for business, architecture, security, ALM, audit, and testing problems.
---
# Review Changes

Read the required project context and production rules in `AGENTS.md`. Review the changed files and diff only; do not modify files unless explicitly asked.

Prioritize actionable findings by severity. Check workflow invariants, Dataverse authority, identity boundaries, scheduling fail-closed behavior, email idempotency and uncertain outcomes, audit/history, privacy/least privilege, integration recovery, ALM/rollback, migration reconciliation, documentation truthfulness, and missing tests. Cite file paths and precise lines where possible.

Report findings first, then open questions/assumptions, then a concise summary. If there are no findings, say so and identify meaningful verification gaps. Never report an unrun test as passed.
