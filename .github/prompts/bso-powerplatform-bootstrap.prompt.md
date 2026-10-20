---
description: Prepare GitHub Copilot and Dataverse Skills to build BSO-RS-Support from VS Code (read-only).
---
# BSO-RS-Support — Bootstrap Power Platform Auto-build

You are the Power Platform Solution Architect and GitHub Copilot Agent working inside the **BSO-RS-Support** repository, NOT the legacy ATSugg repository.

**Goal:** make VS Code the primary environment for implementing and verifying the **full Power Platform app**, not only Dataverse tables. Use supported official tools and accurate repository state.

## Mandatory repository-first discovery

1. Read `AGENTS.md`, `MASTER_PRODUCTION_RULES.md`, `PROJECT_RULES.md`, `WORKFLOW.md`, existing `.github/copilot-instructions.md`, and the current `CURRENT_STATE.md`, `PRODUCT_DECISIONS.md`, `DATAVERSE_SCHEMA_SPECIFICATION.md`, `SECURITY_MODEL.md`, and `ALM_DEPLOYMENT.md`. Find actual paths; do not assume all docs reside at root.
2. Inspect `.vscode/mcp.json` and existing provisioning scripts before editing anything. Do not overwrite custom configured servers, custom prompts or audited scripts.
3. Detect whether Microsoft's `microsoft/Dataverse-skills` is actually installed, and whether GitHub Copilot can discover `dv-overview`, `dv-connect`, `dv-metadata`, `dv-solution`, and `dv-security`. If not installed, propose and (only with user approval for installation) use the official documented installer. Do not treat a GitHub URL as installed code.
4. Prefer the official Microsoft-maintained skills over third-party MCP servers. Do not automatically install `ryanmichaeljames/dataverse-mcp` or `mwhesse/dataverse-mcp` into a production-class environment. Third-party code requires code/security review and an explicit install decision.
5. Verify actual `pac` capabilities using installed CLI help, including `pac model help` and `pac solution help`. Do not assume `pac table` exists. Inspect MCP tool schemas rather than guessing their capabilities.
6. Use `scripts/Test-BsoVsCodeReadiness.ps1` to check CLI, target and Solution, without dumping tokens or user email.

## Confirmed project facts (reverify read-only)

- Authorized environment display name: `VN LMV IT` (Production-class, used internally by IT).
- Publisher unique name `os_bso_rs_support`, customization prefix `os`.
- Unmanaged Solution unique name `os_sr_bso_rs_support` (initial version `1.0.0.0`).
- Names: table `os_sr_cand`, `os_sr_call`, etc. Avoid double prefixing. Use `sr_...` stems only when the tool inserts `os_` automatically.
- `os_sr_ta` was created and independently verified; current reported project inventory is one table.
- `os_sr_pos` write attempt failed with HTTP 401; reconciled absent. Root cause **UNKNOWN**. Previous batch approval does **NOT** authorize recovery retry. `os_sr_csrc` and `os_sr_loc` remain absent by last report.
- Dataverse environment auditing OFF; current technical retention 30 days is NOT approved IT/Compliance policy.

## VS Code full-app workstream plan

Prepare exact tool-by-tool paths for these deliverables without performing writes:

A. Dataverse schema: tables, primary IDs/names, relationships, keys, ownership, status Choice, required columns, solution membership, audit readiness.
B. Model-driven BSO app: app shell, sitemap/navigation, default forms, Quick Create, views, search, dashboards, security testing. Check `pac model create` on this installed version and/or SDK. Do not create app yet.
C. Custom Pages: complex scheduling and candidate operations, where supported by Power Apps tooling; document any remaining Maker-only step instead of inventing an API.
D. Server-side domain logic: Dataverse Custom APIs/plug-ins, transaction guards, permitted status transitions and append-only history.
E. Cloud Flows: Outlook calendar/Teams availability, mail, SharePoint, LEGO Careers integration, audit/reconciliation; verify DLP/connection references/identity, no live sends or bookings.
F. ALM: Solution export/unpack, source control artifacts, automated validation, staged deployment, UAT/rollback. User owns git commit/sync.

## Non-negotiables

- BSO coordinator and TA interviewer; no deprecated TA approval stage.
- Candidate must have eligible Vietnam LEGO Career link and CV before booking.
- Online: TA availability must be verified; offline: TA AND room must be verified. Unknown is not free.
- Mailbox sender identity must match authorized BSO; preserve logical recipients and snapshots; no unsafe resend/fan-out.
- Never generate/use real candidate or employee data for fixtures. No default open access.
- Audit/retention, role grants, flows sending mail, booking and production writes require separate gates.
- Do not retry unknown writes automatically, or treat GET-only DryRun as POST authorization evidence.
- Do not change environments; do not commit/push/sync Git.
- This **bootstrap is READ-ONLY**: no create/update/delete/publish/import/export/app installation without separate user authorization. Do not interact with candidate/business records.

## Deliverable

Return (1) installed tool/skill inventory with evidence; (2) read-only target verification; (3) an accurate capability matrix for full-app development; (4) existing 401 incident status; (5) concrete prioritized build slices, with required approvals and blockers; (6) local files changed, if any; (7) one next action. Stop.
