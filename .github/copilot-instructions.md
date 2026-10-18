# Repository Instructions for GitHub Copilot

Read [AGENTS.md](../AGENTS.md) and the required authoritative documents it names before making changes. Use [docs/PROJECT_CONTEXT.md](../docs/PROJECT_CONTEXT.md), [docs/CURRENT_STATE.md](../docs/CURRENT_STATE.md), and [MASTER_PRODUCTION_RULES.md](../MASTER_PRODUCTION_RULES.md) as the project baseline; consult specialized files for the task.

Provide a bounded preflight before implementation. Preserve the canonical workflow, identity separation, fail-closed scheduling, email idempotency, audit, privacy, and ALM rules. Distinguish implementation from requirements, proposals, dependencies, and open decisions. Use synthetic data only; do not invent tenant configuration or claim resources/tests exist. Do not connect, provision, commit, or push without explicit authorization. Update relevant documentation and validate the resulting scope.
