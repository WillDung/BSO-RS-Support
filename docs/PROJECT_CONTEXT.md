# Project Context

**Status:** Current repository baseline, updated 21 October 2026. Source basis: supplied [Phase 0 Blueprint](../BSO-RS-Support-Phase0-Blueprint.md) (draft for design review), accompanying product rules, and read-only verified environment metadata. Historical references named by the blueprint are not present in this repository.

## Purpose and legacy

BSO-RS-Support is an internal recruitment support and candidate operations application intended to replace ATSugg over time. ATSugg is described by the blueprint as React, FastAPI, and PostgreSQL. It must remain intact as business reference and rollback option until migration and acceptance are completed. No source code or live production state has been inspected here.

## Current implementation

Documentation and repository foundation, the verified Phase 1B Publisher/unmanaged Solution, and the Phase 1D-C TA Directory table `os_sr_ta` in VN LMV IT Production, explicitly selected for internal IT development. On 20 October 2026 the first Phase 1D-D Position Apply returned HTTP 401; its root cause is unknown and no retry is authorized. Read-only reconciliation on 21 October confirms TA remains the sole project table and all three Phase 1D-D targets are absent. The environment has four Model-driven Apps, but no BSO-RS-Support app. Phase 2A adds a proposed app manifest and automation runbook only; `os_sr_app` is not yet verified. Apps, flows, custom APIs, connectors, and integrations are not implemented for this project. Evidence and recovery gates are recorded in [Current State](CURRENT_STATE.md), [Model-driven App Manifest](MODEL_DRIVEN_APP_MANIFEST.md), and [Automation Runbook](MODEL_DRIVEN_APP_AUTOMATION_RUNBOOK.md). Premium and Dataverse production usage are approved in principle; wider capabilities, identities, capacity, and permissions remain unverified.

## Target architecture (proposed)

Model-driven Power App as primary UI, Custom Pages for justified complex screens, Dataverse for authoritative business data and critical server-enforced operations, Power Automate for integration/asynchronous orchestration, Outlook/Teams for messaging and scheduling, SharePoint for approved documents, Entra ID authentication, and Solutions for ALM. LEGO's official careers proxy is the intended job source. AI Builder/OCR and Power BI are conditional options.

## Active business workflow

Need Call Candidate → Candidate Answered → Waiting Manual Scheduling → Round 1 Scheduled → Offer Extended (Pass) or Candidate Failed (Fail). Reschedule from Round 1 Scheduled returns to Need Call Candidate with cancellation attempt and audit. TA is a directory/interviewer contact, not automatically an app user or approver. See [Business Workflows](BUSINESS_WORKFLOWS.md) and [Master Production Rules](../MASTER_PRODUCTION_RULES.md).

## Product decisions and constraints

Dataverse is production source of truth; critical state changes use an approved Dataverse operation. Online scheduling requires verified TA availability; offline also requires verified room availability. Unknown availability fails closed. Email must have verified intended sender, idempotency, immutable-enough content/recipient audit, and explicit Indeterminate outcomes. Candidate CV URL remains canonical booking prerequisite; physical SharePoint CV storage is unresolved. Vietnam-only LEGO postings; exactly one title match can auto-select. See [Product Decisions](PRODUCT_DECISIONS.md) and the [Master Production Rules](../MASTER_PRODUCTION_RULES.md).

## Naming requirement and status

The selected naming strategy is Dataverse Publisher Prefix `os` plus project namespace segment `sr_`, producing final technical names beginning `os_sr_`. The Publisher prefix and approved TA table/column names are verified; other components should follow [Data Model](DATA_MODEL.md). Where Power Apps prepends `os_`, enter only the `sr_<abbreviation>` stem; otherwise use the full final name exactly once. Do not use `os_sr` as the actual Publisher Prefix or allow double-prefixing.

## Source confidence and open decisions

The supplied blueprint is explicitly a draft and cites unavailable historical documents (`PROJECT_CONTEXT.md`, `PRODUCT_DECISIONS.md`, `CURRENT_IMPLEMENTATION_TASK.md`, `README.md`, `MASTER_PRODUCTION_RULES.md`, `DATA_MODEL.md`, `CLAUDE.md`). This foundation uses the prompt's mandatory rules and blueprint as its source basis; no missing document content is inferred. Business details needing validation and platform dependencies are tracked in [Product Decisions](PRODUCT_DECISIONS.md).
