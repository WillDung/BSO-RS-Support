# Architecture

**Status:** Proposed target architecture, based on the draft blueprint. The project Publisher, unmanaged Solution, and TA Directory table are verified. No BSO-RS-Support Model-driven App is deployed. Phase 2A/2B documented the app; Phase 2C authorization is blocked before Create by two unexplained Solution-component roots. The approved `os_srapp` exception remains unimplemented. Sitemap composition, app security, and publication remain gated. Material design decisions require review and appropriate organizational approval.

## Logical components

| Concern | Target component | Boundary / status |
|---|---|---|
| Interactive operations | Power Apps Model-driven App | Default UI; proposed. The owner approved `BSO-RS-Support` / caller suffix `srapp` / expected final `os_srapp` as an app-only naming exception. Phase 2C preflight is blocked by unexplained Solution-component root types `80` and `10091`; no app or navigation is deployed. See [Model-driven App Manifest](MODEL_DRIVEN_APP_MANIFEST.md) and [Automation Runbook](MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md). |
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

The initial app proposal contains only the existing `os_sr_ta` table, its Main `Information` form, and default public `Active TA Directories` view, under Recruitment Support > Administration > TA Directory. The owner approved the `os_srapp` app-only exception. Read-only name checks found no conflict. Phase 2C remains blocked by unexplained Solution-component roots of types `80` and `10091`; no app shell was created. Component selection, sitemap creation, validation, role associations, and publication remain separate steps. See the app manifest, runbook, and [Product Decisions](PRODUCT_DECISIONS.md).

## Trust boundaries

Entra authentication, Dataverse role/row/field authorization, and Microsoft 365 connector identity are distinct. A BSO's app authorization does not prove their connector sends as the same identity. Verify sender and organizer identity before rollout. External calendars and email providers cannot be assumed to participate in Dataverse transactions.

## Architecture decisions still open

Schema review/approval, table ownership/security roles, field-level controls, keys, audit/retention, synchronous API contracts, user-scoped connector pattern, calendar reconciliation, LEGO sync transport, CV file strategy, and optional services remain open. The selected naming strategy uses Publisher Prefix `os` plus namespace segment `sr_`; final technical names begin `os_sr_`. See [Security Model](SECURITY_MODEL.md), [Integration Design](INTEGRATION_DESIGN.md), [ALM Deployment](ALM_DEPLOYMENT.md), and [Product Decisions](PRODUCT_DECISIONS.md).
