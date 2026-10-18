# Acceptance Criteria

These are verifiable gates for a future implementation, not evidence of completed tests. Execute only in approved environments using synthetic or authorized data.

## Candidate and workflow

- Candidate has a unique approved key and required relationships; duplicate handling is deterministic.
- BSO can find/filter assigned operational queues within approved authorization.
- Every allowed transition records previous/new status, actor, timestamp, reason when applicable, and correlation when applicable exactly once, including duplicate-submit behavior.
- Invalid transitions and unauthorized actions are rejected server-side. No Submit-to-TA Approval stage exists.
- Pass records Offer Extended; Fail records Candidate Failed; reschedule returns to Need Call Candidate only through an approved operation and records cancellation outcome/history.

## Email

- Approved template version, logical To and CC, intended sender, subject, and rendered body snapshot are auditable.
- A test proves actual From and recipients match the approved BSO identity and logical recipient list; negative identity/permission cases block send.
- Repeating a dispatch key creates no duplicate logical email. Confirmed send is Sent; confirmed failure is Failed; ambiguous result is Indeterminate.
- Indeterminate email is reconciled and never blindly retried. Flow invocation success alone cannot mark Sent.

## Scheduling and calendar

- Online booking requires verified TA availability; offline requires verified TA and room availability. Unknown/error/stale results block booking.
- Availability is rechecked immediately before booking where supported. Conflicts, races, and provider errors are surfaced without false success.
- Candidate and TA are required attendees; offline room is a resource attendee; intended organizer identity is verified.
- Booking/cancellation uncertainty is reconciled before retry; provider event ID, correlation, and state history are auditable.

## CV, Careers, and privacy

- Booking is blocked without valid CV URL and valid linked LEGO Career according to product rules.
- Only Vietnam careers are visible; exactly one title match auto-selects and zero/multiple require manual resolution.
- Duplicate sync is idempotent; partial/error sync preserves previously valid postings.
- Authorized users can access only approved CV/salary/contact data; no real candidate data or CV appears in development artifacts/logs.
- OCR (if separately approved) provides confidence/failure/manual correction and does not autonomously change critical state.

## Visitor, security, and operations

- Visitor record is correctly linked and only visible to authorized roles; business-specific visitor notifications/retention are approved before testing.
- Role/row/field negative tests prove least-privilege behavior; TA has no app access absent explicit decision.
- Monitoring identifies failed/indeterminate email, calendar, and sync operations with sanitized diagnostics and accountable ownership.

## Migration and release

- Agreed required source records, keys, relationships, statuses, identities, and historical audit reconcile at the approved threshold (blueprint proposes 100% for required records/relationships); exceptions are documented and signed off.
- Trial, cutover, and rollback are rehearsed; ATSugg remains intact until acceptance and retirement approval.
- Managed Solution promotion, environment configuration, approvals, backup/recovery, smoke checks, and rollback plan are evidenced before production release.
