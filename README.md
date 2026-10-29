# BSO-RS-Support

Internal BSO Recruitment Support and Candidate Operations. The target is a Power Platform application that will eventually replace ATSugg; ATSugg remains intact as the business reference and rollback option until migration and acceptance are complete.

## Phase and implementation status

**Current phase: Production Readiness / ALM remediation.** Candidate Core and Candidate Console are implemented in source; Phase 5B BSO security acceptance and Candidate Console DEV verification are recorded as passed in DEV only. The canonical Solution source has an offline unmanaged pack/unpack round-trip. Production readiness remains `PRODUCTION_READINESS_BLOCKED_TECHNICAL_AND_EXTERNAL`: the existing-package release updater is not implemented, the managed artifact requires an approved Test rehearsal, and organizational Test/Production gates remain open. See [Current State](docs/CURRENT_STATE.md) and the [Readiness Blocker Ledger](docs/READINESS_BLOCKER_LEDGER.md).

## Target architecture and technology

- Power Apps Model-driven App for primary operations; Custom Pages only for justified complex interactions.
- Microsoft Dataverse as the authoritative production store and enforcement boundary for business state.
- Dataverse Custom APIs and plug-ins for critical transactions; Power Automate for integrations and asynchronous work.
- Microsoft 365 Outlook and Teams for email and scheduling, subject to identity, permission, and tenant-policy validation.
- SharePoint for approved document storage, not candidate workflow data.
- LEGO's official careers proxy API as the intended posting source; AI Builder/OCR and Power BI remain conditional options.
- Microsoft Entra ID authentication and Power Platform Solutions for ALM.

Premium and Dataverse production use are approved in principle. Tenant access, connectors, permissions, capacities, identities, DLP, and environments are not confirmed.

## Business modules

Candidate operations and call logging; status and history; interview scheduling and results; email templates and dispatch audit; visitor registration; TA, location, position, and source directories; LEGO Careers synchronization; integration monitoring and reporting. Details and status labels are in [Product Requirements](docs/PRODUCT_REQUIREMENTS.md).

## Repository map

- [docs/](docs/PROJECT_CONTEXT.md): authoritative project context, requirements, designs, decisions, plans, and acceptance criteria.
- [MASTER_PRODUCTION_RULES.md](MASTER_PRODUCTION_RULES.md): non-negotiable business, security, audit, and release invariants.
- [AGENTS.md](AGENTS.md) and [WORKFLOW.md](WORKFLOW.md): agent and collaboration process.
- `.github/instructions/` and `.github/prompts/`: scoped Copilot guidance.
- [solutions/](solutions/), [scripts/](scripts/), and [tests/](tests/): canonical PAC Solution source, offline release/configuration gates, and executable Candidate Core/console/source validation suites. These local artifacts do not imply that integrations are deployed or Test/Production resources exist.
- [BSO-RS-Support-Phase0-Blueprint.md](BSO-RS-Support-Phase0-Blueprint.md): supplied design blueprint, draft for review.

## Prerequisites and blockers

Before any Test or Production operation, obtain the exact approved target, identity and release evidence; resolve audit/privacy/DLP, migration, integration, backup/recovery, support ownership, and change-approval gates. The canonical source count and required-component map are in [SOLUTION_COMPONENT_INVENTORY.json](docs/SOLUTION_COMPONENT_INVENTORY.json); release inputs are pinned in [RELEASE_INPUT_MANIFEST.json](docs/RELEASE_INPUT_MANIFEST.json). Do not use production candidate data or credentials in this repository.

## Development workflow

Select one authorized phase, read the context and production rules, inspect only relevant files, submit a preflight report, obtain approval for material architecture changes, implement bounded scope, validate, review, and update documentation. Never provision resources or claim tests/deployments without evidence. See [WORKFLOW.md](WORKFLOW.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation navigation

Start with [Project Context](docs/PROJECT_CONTEXT.md), [Current State](docs/CURRENT_STATE.md), [Architecture](docs/ARCHITECTURE.md), and [Implementation Plan](docs/IMPLEMENTATION_PLAN.md). Product rules are in [Master Production Rules](MASTER_PRODUCTION_RULES.md); unresolved choices are tracked in [Product Decisions](docs/PRODUCT_DECISIONS.md).
