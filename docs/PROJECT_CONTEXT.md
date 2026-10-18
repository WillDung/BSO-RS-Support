# Project Context

**Status:** Current repository baseline, 18 October 2026. Source basis: supplied [Phase 0 Blueprint](../BSO-RS-Support-Phase0-Blueprint.md) (draft for design review) and the accompanying product rules. Historical references named by the blueprint are not present in this repository.

## Purpose and legacy

BSO-RS-Support is an internal recruitment support and candidate operations application intended to replace ATSugg over time. ATSugg is described by the blueprint as React, FastAPI, and PostgreSQL. It must remain intact as business reference and rollback option until migration and acceptance are completed. No source code or live production state has been inspected here.

## Current implementation

Documentation and repository foundation only. No Dataverse schema, Power Apps app, Cloud Flow, custom API, connector, environment, solution export, or production integration is claimed implemented. Premium and Dataverse production usage are approved in principle; specific environments, capabilities, identities, capacity, and permissions remain unverified.

## Target architecture (proposed)

Model-driven Power App as primary UI, Custom Pages for justified complex screens, Dataverse for authoritative business data and critical server-enforced operations, Power Automate for integration/asynchronous orchestration, Outlook/Teams for messaging and scheduling, SharePoint for approved documents, Entra ID authentication, and Solutions for ALM. LEGO's official careers proxy is the intended job source. AI Builder/OCR and Power BI are conditional options.

## Active business workflow

Need Call Candidate → Candidate Answered → Waiting Manual Scheduling → Round 1 Scheduled → Offer Extended (Pass) or Candidate Failed (Fail). Reschedule from Round 1 Scheduled returns to Need Call Candidate with cancellation attempt and audit. TA is a directory/interviewer contact, not automatically an app user or approver. See [Business Workflows](BUSINESS_WORKFLOWS.md) and [Master Production Rules](../MASTER_PRODUCTION_RULES.md).

## Product decisions and constraints

Dataverse is production source of truth; critical state changes use an approved Dataverse operation. Online scheduling requires verified TA availability; offline also requires verified room availability. Unknown availability fails closed. Email must have verified intended sender, idempotency, immutable-enough content/recipient audit, and explicit Indeterminate outcomes. Candidate CV URL remains canonical booking prerequisite; physical SharePoint CV storage is unresolved. Vietnam-only LEGO postings; exactly one title match can auto-select. See [Product Decisions](PRODUCT_DECISIONS.md) and the [Master Production Rules](../MASTER_PRODUCTION_RULES.md).

## Source confidence and open decisions

The supplied blueprint is explicitly a draft and cites unavailable historical documents (`PROJECT_CONTEXT.md`, `PRODUCT_DECISIONS.md`, `CURRENT_IMPLEMENTATION_TASK.md`, `README.md`, `MASTER_PRODUCTION_RULES.md`, `DATA_MODEL.md`, `CLAUDE.md`). This foundation uses the prompt's mandatory rules and blueprint as its source basis; no missing document content is inferred. Business details needing validation and platform dependencies are tracked in [Product Decisions](PRODUCT_DECISIONS.md).
