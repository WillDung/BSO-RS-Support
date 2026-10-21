# Architecture

**Status:** Proposed target architecture, based on the draft blueprint. The project Publisher, unmanaged Solution, and TA Directory table are verified. A BSO-RS-Support Model-driven App exists in the environment with actual unique name `srapp`, Saved - Not Published; it is not the approved expected `os_srapp`. Phase 2C authorization to create one app shell was not executed because it would create a second same-display-name app. Reconcile the existing app before further work. Sitemap composition, app security, and publication remain gated. Material design decisions require review and appropriate organizational approval.

## Logical components

| Concern | Target component | Boundary / status |
|---|---|---|
| Interactive operations | Power Apps Model-driven App | Default UI; proposed. An existing BSO-RS-Support app has unique name `srapp` (Saved - Not Published), conflicting with the owner-approved target `os_srapp`. Phase 2C did not create a second app. Type 80 is identified as the existing AppModule; type 10091 is linked to its sitemap context but lacks an authoritative direct type mapping. See [Model-driven App Manifest](MODEL_DRIVEN_APP_MANIFEST.md) and [Automation Runbook](MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md). |
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

The initial app design targets the existing `os_sr_ta` table, its Main `Information` form, and default public `Active TA Directories` view, under Recruitment Support > Administration > TA Directory. The owner approved `os_srapp`, but a same-display-name AppModule already exists as `srapp`; Phase 2C did not create a duplicate. Type 10091 is dependency-linked to the existing app; its exact component identity is unresolved. Component selection, sitemap changes, validation, role associations, and publication remain separate steps. See the app manifest, runbook, and [Product Decisions](PRODUCT_DECISIONS.md).

## Trust boundaries

Entra authentication, Dataverse role/row/field authorization, and Microsoft 365 connector identity are distinct. A BSO's app authorization does not prove their connector sends as the same identity. Verify sender and organizer identity before rollout. External calendars and email providers cannot be assumed to participate in Dataverse transactions.

## Architecture decisions still open

Schema review/approval, table ownership/security roles, field-level controls, keys, audit/retention, synchronous API contracts, user-scoped connector pattern, calendar reconciliation, LEGO sync transport, CV file strategy, and optional services remain open. The selected naming strategy uses Publisher Prefix `os` plus namespace segment `sr_`; final technical names begin `os_sr_`. See [Security Model](SECURITY_MODEL.md), [Integration Design](INTEGRATION_DESIGN.md), [ALM Deployment](ALM_DEPLOYMENT.md), and [Product Decisions](PRODUCT_DECISIONS.md).
