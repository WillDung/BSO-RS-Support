# BSO-RS-Support — VS Code–first Power Platform development

## Technical decision

Use GitHub Copilot Agent inside the BSO-RS-Support VS Code workspace as the development orchestrator. Preferred integration: **Microsoft Dataverse Skills** (`microsoft/Dataverse-skills`) plus the **existing** Dataverse MCP, PAC CLI MCP, Power Platform Tools, Dataverse SDK/Web API when needed. This is not a new backend or a custom MCP server. Tool selection must be based on verified capability, version and authorization.

References:
- Official skills: https://github.com/microsoft/Dataverse-skills
- Skill metadata authoring: https://github.com/microsoft/Dataverse-skills/blob/main/.github/plugins/dataverse/skills/dv-metadata/SKILL.md
- PAC model-driven app creation: https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/model
- Dataverse MCP: https://learn.microsoft.com/en-us/power-apps/maker/data-platform/data-platform-mcp

## Stack / responsibility

| Responsibility | Preferred authoring path | Required verification |
| --- | --- | --- |
| Tables, columns, relationships, keys | Dataverse Skills `dv-metadata` using supported SDK/MetadataService/Web API; existing provenance-aware provisioning scripts | exact `os_sr_*` names, Organization/User ownership, primary name, attributes, solution membership, no duplicate objects |
| Dataverse forms and views | `dv-metadata`, SDK metadata and approved supported tools | opened/published UI metadata and solution inclusion |
| Model-driven app | PAC `model create` for an unpublished shell in the target Solution; AppModule SDK/Web API when exact technical-name control is required; `AddAppComponents`, sitemap/app designer, `ValidateApp` | Exact app unique name, Publisher/Solution linkage, table/form/view selection, sitemap, role dependencies, and unpublished state; follow [Phase 2A manifest](MODEL_DRIVEN_APP_MANIFEST.md) and [runbook](MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md) |
| Custom Pages and UI | Power Apps-supported tooling and component build workflow; interactive designer only when unavoidable | deployed pages, navigation, device/BSO UAT |
| Custom APIs / plug-ins | supported SDK/PAC plug-in tooling with tests | server-side workflow state guard, idempotency, trace/recovery |
| Cloud Flows | solution-aware Power Automate tools/definitions and connection references | owner/connection, DLP, no live sends/bookings without tests and authorization |
| Security and audit | reviewed role/field security deployment, IT/Compliance audit decision | least-privilege testing, approved retention, no PII leakage |
| ALM and release | PAC export/unpack/version and approved deployment pipeline | release artifacts and rollback plan |

## Build slices

1. **Bootstrap:** audit existing repo/tool skill installation; read-only verify current state and source-of-truth docs.
2. **Reference tables:** current issue `os_sr_pos` HTTP 401 incident; do not automatically retry. Verify recovery under **new** approval; then other table batches after approval.
3. **Candidate core schema:** `os_sr_cand`, `os_sr_call`, `os_sr_csh`; decide Candidate Number, role ownership, status choices, keys, history integrity before creation.
4. **Usable model-driven MVP:** app and navigation, Candidate/Create/Call/History forms and views, BSO/Admin access policies, synthetic UAT only.
5. **Domain automation:** server-side transitions and audit; call outcome, scheduling, result recording.
6. **Scheduling and communications:** user-scoped organizer/sender identities, fail-closed TA/room availability, visitor notifications, safe dispatch/audit, no unsafe retry.
7. **LEGO Careers, SharePoint and optional AI Builder:** Vietnam scope, CV gate, secured links/permissions, DLP and retention.
8. **ALM/acceptance:** export/unpack to Git, independent verification, security and user UAT, staged production acceptance. Keep ATSugg until cutover signoff.

## Development contract

- The end-goal is an operable **Power Apps Model-driven + Custom Pages** application using Dataverse as the sole authority, not a parallel React/FastAPI/PostgreSQL product.
- Project technical names follow `os_sr_*`. Dataverse publisher prefix is `os`, with project namespace `sr`. Display labels remain human-readable.
- Onboarding skills does **not** change the tenant's API authorization. Official SDK/CLI/MCP calls can also receive HTTP 401; no bypasses.
- Do not overwrite existing `.vscode/mcp.json`, `.github/copilot-instructions.md`, `AGENTS.md`, project rules, or functioning scripts just to install skills.
- Production-class VN LMV IT is internal development by user decision; safety gates for data/security are still required.
- Auditing is off and retention is governed by IT/Compliance; no real candidate or staff data until controls are approved.
- User retains responsibility for Git commit/push/sync. Agent maintains a truthful state log.
- For flows that send messages/book appointments, require explicit sandbox recipients and real mailbox evidence before production.

## 401 incident policy

At last verified report, a one-time EntityDefinitions POST for `os_sr_pos` returned HTTP 401. GET reconciliation found no Position table. `os_sr_ta` exists and remains valid. Root cause remains UNKNOWN; defensive token refresh and logging are not confirmed fixes. Do not call MCP/SDK writes as an unauthorized workaround. Separate recovery authorization, one-write limit, independent read-back and diagnostics are required.

## Known limitation

No complete all-in-one tool was verified for automatically generating and deploying every app feature. Copilot can automate most supported authoring, packaging and checking, but custom pages, flows and security may require tenant permissions, approved connectors, external identities, or interactive UI operations. A task must report those blockers rather than claiming a completed application.

PAC CLI 2.13.1 `pac model create` has no unique-name option. The owner approved caller suffix `srapp`, expected final `os_srapp`, as an app-only exception to `os_sr_*`. Read-only checks found no app-name conflict, but Phase 2C did not send a write because the Solution contains two unexplained root component types `80` and `10091`. Reconcile those before creation. `pac model genpage` manages generated pages only; it is not a substitute for configuring ordinary entity navigation. Standard forms/views use supported Dataverse records and app-component APIs. Keep the app unpublished; publication requires separate approval.
