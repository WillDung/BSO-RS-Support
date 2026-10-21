# Architecture

**Status:** Proposed target architecture, based on the draft blueprint. The project Publisher, unmanaged Solution, and TA Directory table are verified. The project owner officially adopted existing BSO-RS-Support AppModule `srapp` (ID `3709bb7c-28cd-f111-a05c-70a8a581cbfa`) on 21 October 2026. This app-only name exception supersedes the prior `os_srapp` proposal; normal Dataverse table naming remains `os_sr_*`. The AppModule Publisher lookup is unknown. App composition/navigation, security changes, and publication are not authorized; current app state remains Active but Unpublished.

## Logical components

| Concern | Target component | Boundary / status |
|---|---|---|
| Interactive operations | Power Apps Model-driven App | Officially adopted existing AppModule `srapp`; currently Active but Unpublished and not composed. `os_srapp` was a superseded naming proposal. R2 found no app components and only a placeholder Site Map. Type 80 is the AppModule, type 62 the Site Map, and type 10091 remains unidentified and is not the Site Map object. See [Model-driven App Manifest](MODEL_DRIVEN_APP_MANIFEST.md) and [Automation Runbook](MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md). |
| Complex interaction | Power Apps Custom Pages | Use only when justified; proposed |
| Authoritative data | Microsoft Dataverse | Sole production source for candidate workflow/business state; production use approved in principle, no schema provisioned |
| Critical business operations | Dataverse Custom APIs and synchronous plug-ins | Proposed enforcement for critical transitions |
| Orchestration | Power Automate Cloud Flows | Integrations and asynchronous work; must call approved business operations |
| Mail and calendar | Microsoft 365 Outlook/Teams | Identity and permission model requires verification |
| Documents | SharePoint | Approved document storage, not candidate database; CV binary storage unresolved |
| Careers data | LEGO official careers proxy API | Intended source; contract/access unverified |
| Identity | Microsoft Entra ID | Authentication target; exact roles and tenant config unverified |
| ALM | Power Platform Solutions | Managed downstream deployment target; environments/pipeline unverified |
| Optional capabilities | AI Builder OCR, Power BI | Conditional on approval, privacy, capacity, and need |

## Proposed Dataverse schema boundary

The proposed table inventory is grouped into reference, candidate/history, interview/communication, and integration areas in [Data Model](DATA_MODEL.md). Complete proposed columns, ownership, keys, relationships, cascade rules, audit, security, and migration mappings are in [Dataverse Schema Specification](DATAVERSE_SCHEMA_SPECIFICATION.md). Reference tables are proposed OrgOwned; candidate and activity-bearing records are proposed UserOwned, with child ownership assigned by an approved server-side operation. These choices are not deployed or approved. The publisher and empty solution do not imply that any table, role, API, plug-in, app, or flow exists.

## Interaction and data flow

The UI requests a business action. Dataverse validates and commits critical candidate state and history through an approved server-side operation. Flows may orchestrate external side effects such as email/calendar calls, but do not bypass transition rules. External operations require correlation, idempotency where possible, explicit outcome states, and reconciliation for uncertain results. Dataverse remains business authority; SharePoint holds approved document binaries only.

## Model-driven App composition (proposed)

The adopted app is prepared for a Phase 2D composition proposal using `os_sr_ta`, Main `Information` form `e076f089-e35b-46f3-b123-9cf0463759e5`, and public `Active TA Directories` view `2cb98672-8176-4337-af5e-d6aabcac8f2d`, under Recruitment Support > Administration > TA Directory. The Main form and view are in the exported project Solution under the TA table root; they are not yet selected in the app. The existing Site Map is `srapp` and currently placeholder-only. No composition, role change, or publication is authorized by adoption. See the app manifest, runbook, and [Product Decisions](PRODUCT_DECISIONS.md).

## Trust boundaries

Entra authentication, Dataverse role/row/field authorization, and Microsoft 365 connector identity are distinct. A BSO's app authorization does not prove their connector sends as the same identity. Verify sender and organizer identity before rollout. External calendars and email providers cannot be assumed to participate in Dataverse transactions.

## Architecture decisions still open

Schema review/approval, table ownership/security roles, field-level controls, keys, audit/retention, synchronous API contracts, user-scoped connector pattern, calendar reconciliation, LEGO sync transport, CV file strategy, and optional services remain open. The selected naming strategy uses Publisher Prefix `os` plus namespace segment `sr_`; final technical names begin `os_sr_`. See [Security Model](SECURITY_MODEL.md), [Integration Design](INTEGRATION_DESIGN.md), [ALM Deployment](ALM_DEPLOYMENT.md), and [Product Decisions](PRODUCT_DECISIONS.md).
