# BSO-RS-Support

Internal BSO Recruitment Support and Candidate Operations. The target is a Power Platform application that will eventually replace ATSugg; ATSugg remains intact as the business reference and rollback option until migration and acceptance are complete.

## Phase and implementation status

**Phase 0: repository foundation and blueprint.** This repository currently contains documentation only. No Power Platform implementation, environment, integration, test execution, or deployment is claimed complete. See [Current State](docs/CURRENT_STATE.md).

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
- `solutions/`, `automation/`, `scripts/`, `tests/`: intended homes for future artifacts; currently documentation only.
- [BSO-RS-Support-Phase0-Blueprint.md](BSO-RS-Support-Phase0-Blueprint.md): supplied design blueprint, draft for review.

## Prerequisites and blockers

Before implementation, confirm the approved Dev/Test/Production environments and Dataverse region, publisher prefix, security boundary, DLP and connector permissions, service/user connection model, calendar permissions, storage and retention, migration scope, and any optional capacities. See [Product Decisions](docs/PRODUCT_DECISIONS.md) and [Current State](docs/CURRENT_STATE.md). Do not use production candidate data or credentials in this repository.

## Development workflow

Select one authorized phase, read the context and production rules, inspect only relevant files, submit a preflight report, obtain approval for material architecture changes, implement bounded scope, validate, review, and update documentation. Never provision resources or claim tests/deployments without evidence. See [WORKFLOW.md](WORKFLOW.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation navigation

Start with [Project Context](docs/PROJECT_CONTEXT.md), [Current State](docs/CURRENT_STATE.md), [Architecture](docs/ARCHITECTURE.md), and [Implementation Plan](docs/IMPLEMENTATION_PLAN.md). Product rules are in [Master Production Rules](MASTER_PRODUCTION_RULES.md); unresolved choices are tracked in [Product Decisions](docs/PRODUCT_DECISIONS.md).
