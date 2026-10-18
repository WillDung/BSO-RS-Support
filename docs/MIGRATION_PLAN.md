# Migration Plan

**Status:** Proposed approach only. ATSugg schema, live data, record counts, and access were not inspected; no production dataset or migration capability is assumed. Keep ATSugg intact as business reference and rollback option through acceptance.

## Source mapping (initial proposal)

| ATSugg source concept (to inventory) | Proposed destination | Mapping work required |
|---|---|---|
| Candidate/person | Candidate | Candidate number/key, contact normalization, duplicates, owner, status |
| Calls/contact events | Call Log | Actor/time/time zone, outcome, notes, references |
| Current stage/status changes | Candidate + Candidate Status History | Canonical state mapping, unmapped/invalid values, historical transition order |
| Interviews/rounds/events | Interview Round | TA, mode, room, time zone, provider event ID and current external state |
| Interview outcomes/feedback | Interview Result | Pass/Fail and field/privacy/retention mapping |
| TA/interviewer directory | TA Directory | Stable identity/email mapping; do not infer app role |
| Locations/rooms | Location | Room/resource mailbox identity verification |
| Positions/jobs | Position and LEGO Career | Distinguish internal position from external career posting |
| Candidate source values | Candidate Source | Normalize while retaining historical meaning |
| Email templates and send history | Email Template / Email Dispatch | Template version, logical recipients, sender evidence, snapshot and outcome availability |
| Visitor records | Visitor Registration | Candidate/interview/location linkage and retention |
| CV URLs/files | Candidate CV URL; optional SharePoint documents | Access validation, URL durability, physical file decision and migration controls |

Mapping is provisional. Inventory actual tables, constraints, record counts, active features, reference data, data quality, time zones, and audit availability before freezing it.

## Transformation and validation

Define stable source-to-target keys and duplicate policy; normalize phone/email/Unicode/time zones without losing source values; map statuses only through approved rules; resolve orphan references; validate URL and relationship semantics. Preserve source identifiers for reconciliation where permitted. Use synthetic fixtures during development. Establish per-entity counts, required-field/null rules, uniqueness, relationship integrity, status distribution, and exception thresholds before trial load.

## Identity and historical audit

Map BSO/TA identities using an approved directory strategy; do not assume legacy usernames map to Entra identities or grant app roles. Preserve historical actors as source identity plus resolved identity where feasible, with provenance for unresolved actors. Preserve transition history and timestamps/order. Do not fabricate historical email delivery or calendar state where source evidence is absent.

## Reconciliation, rehearsal, cutover

Run trial migration in Test. Reconcile counts, keys, critical fields, relationships, statuses, historical audit, CV link accessibility, email/calendar evidence, and documented exceptions. Obtain business sign-off on mapping and exceptions. Define freeze window, incremental/delta strategy, retry/idempotency, write ownership during cutover, monitoring, user communications, and rollback trigger. Rehearse cutover and rollback before production migration.

Production cutover requires approved access, security/privacy/retention review, verified integrations, signed UAT, agreed reconciliation, and formal change approval. Keep ATSugg intact and available for rollback until acceptance and retirement criteria are explicitly met. Retirement requires business sign-off, reconciliation closure, retention/legal approval, recoverability evidence, and confirmed archive/access plan.
