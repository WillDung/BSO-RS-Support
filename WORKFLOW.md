# Collaboration Workflow

1. Select one authorized implementation phase from [Implementation Plan](docs/IMPLEMENTATION_PLAN.md).
2. Read [Project Context](docs/PROJECT_CONTEXT.md), [Current State](docs/CURRENT_STATE.md), [Master Production Rules](MASTER_PRODUCTION_RULES.md), and this workflow.
3. Inspect only the relevant files and confirm current repository state.
4. Produce a preflight report: goal, factual state, scope, files, dependencies, risks, and validation.
5. Obtain approval for material architecture/product changes. Trivial documentation edits do not need agent approval unless they alter business decisions.
6. Implement only the approved scope. Preserve existing content and avoid secrets or real personal data.
7. Execute relevant validation and report exact commands/results. Never claim a check that was not run.
8. Review the diff for correctness, security, scope, and truthful status.
9. Update documentation and [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md) when status changes.
10. When the human owner directs a commit, use a descriptive Conventional Commit message. Do not commit or push automatically.

External operations, tenant access, credentials, resource provisioning, and production changes require separate explicit authorization and applicable organizational approval.
