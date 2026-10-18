# Instructions for AI Agents

This repository governs BSO-RS-Support, a planned Power Platform replacement for ATSugg. Do not infer that a design is deployed or that tenant prerequisites have been met.

## Required reading

Before any task, read these in order:

1. [docs/PROJECT_CONTEXT.md](docs/PROJECT_CONTEXT.md)
2. [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md)
3. [MASTER_PRODUCTION_RULES.md](MASTER_PRODUCTION_RULES.md)
4. [WORKFLOW.md](WORKFLOW.md)

Then inspect only the relevant specialized design, requirement, security, integration, ALM, migration, or test documents.

## Required preflight

Before implementation, report the requested outcome, current factual state, relevant files, bounded proposed changes, dependencies and risks, and a focused validation plan. Do not implement until the requested phase and scope are clear. Obtain explicit approval before material architecture or product-decision changes. Trivial documentation corrections do not require approval unless they alter a business decision.

## Guardrails

- Treat Dataverse as production authority for candidate business state. Critical transitions must use an approved Dataverse business operation.
- Preserve the canonical workflow and fail-closed scheduling/email rules in [MASTER_PRODUCTION_RULES.md](MASTER_PRODUCTION_RULES.md).
- Separate application authorization from Microsoft 365 connector identity; never silently impersonate a BSO through a fixed Flow owner connection.
- Use synthetic data only. Never add secrets, real tenant identifiers, candidate PII, CVs, or production connector URLs.
- Do not create fake exports, flows, tables, test results, environment configuration, or deployment claims.
- Keep ATSugg intact until migration acceptance and cutover approval.
- Update the appropriate documentation when an approved design or status changes. Use relative Markdown links and distinguish current implementation, approved requirement, proposal, dependency, and open decision.
- Do not commit, push, connect to a tenant, or provision resources unless explicitly authorized.
