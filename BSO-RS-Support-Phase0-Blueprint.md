# BSO-RS-Support — Phase 0 Migration Blueprint

**Status:** Draft for design review (18 October 2026)  
**Goal:** Replace ATSugg long-term with a Microsoft Power Platform application.  
**Legacy reference:** ATSugg (React, FastAPI, PostgreSQL); preserve as rollback/reference until cutover acceptance.  
**Target platform:** Power Apps Premium, Dataverse, Power Automate, SharePoint, Outlook/Teams, optionally AI Builder and Power BI.  
**Assumption confirmed by sponsor:** Power Apps Premium and Dataverse permitted for production. Specific connector permissions, capacity, and runtime identities remain to be validated.

## A. Product boundaries

- Main interactive user: BSO. Assigned TA is an interviewer/contact directory entry; not automatically a separate interactive role or approval stage.
- Workflow: Need Call Candidate → Candidate Answered → Waiting Manual Scheduling → Round 1 Scheduled → Offer Extended (Pass) or Candidate Failed (Fail). Reschedule from Round 1 Scheduled → Need Call Candidate (with cancellation attempt and audit).
- No Draft Created / BSO Reviewing / Sent to TA / TA Approval revival without an explicit new product decision.
- BSO is coordinator. TA is required interviewer; candidate required attendee; room a resource attendee for offline events.
- Online availability: TA. Offline: TA and room. Never treat failed or unknown availability as free.
- CV URL is the canonical current booking prerequisite; future binary CV storage in SharePoint is a separate feature requiring access controls and migration decision.
- LEGO Careers: Vietnam-only visible postings, exact job-title matching (one match = auto-selection; none or multiple = manual selection); booking requires valid linked career and CV URL.
- Preserve email subject/body snapshot, logical recipients and sender identity in audit; avoid duplicate sends.

## B. Target component map

| ATSugg | BSO-RS-Support | Decision |
|---|---|---|
| React UI | Model-driven App; Custom Pages for scheduling/complex detail | Replace |
| FastAPI domain services | Dataverse Custom APIs + synchronous plug-ins for critical transitions | Replace |
| PostgreSQL | Dataverse | Replace at cutover |
| Email adapter (Graph/PAD) | Outlook connector via appropriately user-scoped Power Apps/Flow execution | Validate identity before rollout |
| Calendar adapter | Outlook Calendar / Teams connectors + availability verification | Validate attendee/calendar permissions |
| CV canonical link | Dataverse field plus optional SharePoint documents | Migrate links and access controls |
| OCR local | AI Builder or alternative approved OCR | Conditional on budget/accuracy/privacy |
| LEGO Careers client | Scheduled cloud flow/custom connector to official careers proxy | Validate HTTP/DLP/response parsing |
| Metrics | Dataverse charts/Power BI | Replace |
| Audit | Immutable custom audit entities plus Dataverse Audit where useful | Implement |

## C. Proposed Dataverse data model (initial names, not deployed)

The required project namespace is `os_sr` wherever Power Platform supports it. The table labels below are business names; proposed abbreviated technical names are mapped in [Data Model](docs/DATA_MODEL.md). The exact `os_sr` Dataverse Publisher Prefix remains unverified: the documented eight-character maximum is met, but underscore acceptance is not stated in the published reference. Do not silently substitute another prefix; names remain proposals until schema review and publisher validation.

| Table | Business fields and relationships | Notes |
|---|---|---|
| Candidate | unique Candidate Number; name; email; phone; job title; source; current stage/status; owner BSO; assigned TA; CV URL; linked LEGO Career; timestamps | Main record |
| Call Log | Candidate lookup; outcome; contacted at; contacted by; notes | Append-only business log |
| Candidate Status History | Candidate; previous/new status; actor; timestamp; reason; correlation ID | Every business transition |
| Interview Round | Candidate; TA; mode; room; start/end; organizer; event ID; status | One candidate can have several rounds/attempts |
| Interview Result | Candidate + Round; Pass/Fail; feedback; salary; recorded by/at | Gate by workflow |
| TA Directory | email; display name; active | TA is NOT automatically an interactive role |
| Location | name; room email; details; active | Offline room resource |
| Position | title; active | Reference list |
| Candidate Source | name; active | Reference list |
| Email Template | code; subject; body; To/CC defaults; active | Template variables allowlisted |
| Email Dispatch | Candidate; idempotency key; intended sender; To/CC; subject/body snapshot; state; provider correlation; timestamps/errors | States: Queued, Sending, Sent, Failed, Indeterminate; do not retry uncertain sends blindly |
| Visitor Registration | Candidate; interview; location; visit time; status | Onsite |
| LEGO Career | external ID; position; location/country; URL; status; last synced | Sync upsert via stable external key |
| Integration Run | kind; correlation; start/end; state; sanitized error | Avoid tokens/PII logging |
| App Configuration | logical key; approved value | Prefer environment variables for secrets/endpoint URLs |

**Keys/integrity:** Unique candidate number; unique LEGO external ID; unique outbound idempotency key; event IDs and action correlation stored for cancellation/reconciliation. Relationships, row ownership and retention policies must be specified before schema deployment. No live schema is claimed here.

## D. App pages

1. Operations Dashboard — open queues, SLA/KPI, recent actions.
2. Candidates — list, search, filters, create/edit.
3. Candidate Detail — information, CV URL, assigned TA, calls, rounds, interview results, visitor records, audit.
4. Call & Schedule — combined coordinator queue and scheduling custom page.
5. Email Center — template management and dispatch audit.
6. Visitor Queue — onsite arrivals and notifications.
7. LEGO Careers — sync, state, Vietnam-only matching.
8. Settings — TA, positions, sources, locations, templates.

## E. Critical flow contracts (proposals)

**Book interview**
- Input: Candidate ID, TA reference, online/offline, location if offline, start/end, idempotency key.
- Validate Candidate status, TA active, linked LEGO job URL and valid CV URL.
- Verify TA free/busy; offline verify room too. Any unavailable/error/unknown = block.
- Revalidate immediately before booking to reduce race risk; even then external calendars do not provide absolute transactionality.
- Create organizer event with candidate and TA as required attendees and room as resource attendee when applicable.
- Capture provider event ID, state/history and dispatch details; do not mark scheduled based solely on starting the flow.
- On uncertain outcome, reconcile by correlation/provider ID before retry.

**Send email**
- Input: validated sender/BSO identity, logical To/CC, template and rendered snapshot, unique dispatch key.
- Each BSO must send as their own allowed Microsoft 365 identity. Verify Power Apps-invoked flow connection mode or equivalent before implementation; fixed owner connection is not sufficient.
- Single logical dispatch, no per-recipient fan-out for multi-To; store outcome and correlation. Indeterminate send is not auto-retried.
- Prove mailbox From, recipients, received message and audit with synthetic recipients.

**Reschedule**
- Record request, try cancel previous event, persist cancellation result and history, return to Need Call Candidate only via approved business action; flag unresolved external calendar state for reconciliation.

**LEGO synchronization**
- Outbound scheduled sync; official LEGO careers proxy, paginated if applicable, Vietnam-only visibility; stable external IDs and idempotent upsert. Do not deactivate all careers on a partial/error response.

## F. Security, ALM and operations

- Entra ID for authentication; Dataverse Security Roles control access. Start with BSO and Admin roles. TA stays directory-only unless new interactive TA functionality is authorized.
- Least privilege by table/operation and environment. Field security where needed for salary/contact details.
- Separate Dev, Test, Production; solution-aware components and connection references; managed deployments to production.
- Check tenant DLP rules for Outlook, HTTP/custom connector, SharePoint, AI Builder and Power BI; permissions for TA/room calendars; capacity/licensing for AI Builder and data storage.
- No real candidate data in development fixtures; use synthetic test data. Agree on production retention, privacy, backup/recovery, and ownership.
- Maintain monitoring for failed/indeterminate mail/calendar actions, failed synchronization, cloud-flow runs, rate limiting and retry rules.

## G. Migration strategy

1. Inventory ATSugg PostgreSQL schema, record counts, actual active features and data quality. Current repository docs are a reference, not a guaranteed snapshot of live production.
2. Approve Dataverse schema and candidate status translation; freeze data mapping and key strategy.
3. Implement core app and migration scripts with synthetic fixtures; test relationships, timezone, Unicode, duplicate handling, audit and URL accessibility.
4. Prove identity and scheduling/email acceptance in real tenant with safe test accounts before any candidate-facing action.
5. Trial migration into Test; reconcile record counts, key fields, relationships, statuses, email history and file links.
6. Rehearse cutover and rollback; define freeze window and data delta plan.
7. Production migration; business sign-off; activate new UI; retain ATSugg read-only/archive and backups under company policy.

## H. Acceptance gates

- Identity: BSO A and B can act only within permissions; mailbox From and organizer exactly match approved rules; negative identity tests block sending.
- Workflow: every permitted transition creates exactly one history entry; invalid transitions refused. No legacy TA approval introduced.
- Scheduling: fail-closed for TA and room; booking revalidation; online/offline required attendees; cancellation/reconciliation verified.
- Email: multi-To and CC preserve logical recipients; template snapshots correct; exactly one dispatch audit per key; uncertain sends not blindly retried.
- Integrations: LEGO partial sync does not wipe valid records; sync idempotent; errors observable.
- Security: DLP, role testing, access to CV/salary, data protection and audit verified.
- Migration: agreed 100% reconciliation for required records and relationships, with documented exceptions; user acceptance sign-off before cutover.
- ALM: solution promoted Dev → Test → Production using controlled pipeline, environment connections and rollback plan.

## I. First build slice (after blueprint sign-off)

1. Create solution `BSO-RS-Support` in Dev, confirm publisher prefix and security boundary.
2. Create Candidate, TA Directory, Position, Candidate Source, Call Log and Candidate Status History tables.
3. Create BSO/Admin roles and minimal model-driven navigation.
4. Implement Candidate Create → Call Log → status change with a server-enforced action and audit.
5. Add tests for permissions, allowed/blocked transitions and duplicate submit.

## J. Explicit open items

- Which production environment and Dataverse region the organization approves.
- Whether BSO mailbox sending through user-provided connections and Outlook connector is permitted under tenant policy.
- Room mailbox permissions and scheduling test accounts.
- Approved publisher prefix; data migration volume/retention rules; AI Builder and Power BI capacity.
- Whether CV files must be migrated physically or URLs are sufficient for launch.

**Source basis:** Project materials: `PROJECT_CONTEXT.md`, `PRODUCT_DECISIONS.md`, `CURRENT_IMPLEMENTATION_TASK.md`, `README.md`, `MASTER_PRODUCTION_RULES.md`, `DATA_MODEL.md`, `CLAUDE.md`. These have some differing historical snapshots; active feature scope is reconciled to explicit product decisions, with behavior requiring live tenant verification marked as such. Microsoft official docs for custom pages, Power Platform pipelines and run-only connections inform platform choices.
