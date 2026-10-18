# Integration Design

**Status:** Contracts below are proposed. Connector permissions, APIs, identities, and environment configuration are unverified. External side effects must have explicit correlation and uncertain-outcome handling.

## Email

Use approved templates and capture the logical To/CC lists, intended sender, subject, rendered body snapshot, dispatch idempotency key, timestamps, and provider correlation. Confirm the current BSO's allowed Microsoft 365 identity before send; never silently use a fixed owner connection as the BSO. Treat provider-confirmed send as Sent, confirmed error as Failed, and timeout/ambiguous response as Indeterminate. Never blindly retry Indeterminate; reconcile first. A successful Flow run is not delivery proof. Test with synthetic recipients and verify actual From/recipients/message evidence before rollout.

## Calendar and Teams

Before booking, validate candidate status, active TA, valid linked LEGO Career, CV URL, interval, mode, and location if offline. BSO coordinates; candidate and TA are required attendees; offline room is a resource attendee. Online requires verified TA availability; offline requires verified TA and room availability. Unknown, failed, stale, or conflicting availability blocks booking. Recheck immediately before creation where supported. Store idempotency/correlation and provider event ID, and model confirmed, failed, and uncertain outcomes. Design cancellation, reschedule, reconciliation, time zones, organizer identity, and Teams link behavior explicitly. External calendars are not transactionally coupled to Dataverse.

## SharePoint

SharePoint is approved document storage, not candidate workflow authority. Canonical initial booking prerequisite is a valid candidate CV URL. Whether to store binary CVs, folder/library structure, permissions, retention, malware scanning, migration, and link validation remain open. Do not copy real CVs into development or this repository.

## LEGO Careers

Intended source: LEGO's official careers proxy API. Define authentication, endpoint, schema, pagination, rate limits, schedule, timeouts, country/location interpretation, and change/deactivation semantics with the API owner. Only Vietnam postings are visible for this workflow. Use stable external IDs and idempotent upsert. Exactly one title match may auto-select; zero/multiple require manual resolution. On partial/error responses, preserve previously valid records. No endpoint or credentials are recorded here.

## OCR / AI Builder

Optional and conditional on organizational approval, privacy review, accuracy/quality evaluation, licensing/capacity, and human correction. Define document scope, extraction schema, confidence thresholds, retention, and failure/manual fallback. OCR does not authorize automatic candidate state changes.

## Shared contract requirements

Use a correlation identifier across Dataverse action, Flow, and provider where supported. Keep error details sanitized; do not log credentials or unnecessary payload/PII. Use bounded retries only when outcome semantics and idempotency permit. For uncertain non-idempotent actions, reconcile against provider state before retry. Define monitoring, alert ownership, retention, and operational runbooks before production. See [Master Production Rules](../MASTER_PRODUCTION_RULES.md).
