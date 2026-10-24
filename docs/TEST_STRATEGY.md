# Test Strategy

**Status:** Test approach plus partial implementation evidence. Candidate Core metadata and the server operation API/plugin are deployed; offline synthetic suites exist and have passed. No live business-operation acceptance is claimed. The owner-authorized Phase 3D run stopped before fixture creation because organization auditing is disabled, the approved API intentionally defers scheduler/result/reschedule transitions, and a safe exact-ID cleanup mechanism was not established. See the [Phase 3D report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).

## Test layers

- **Unit/component:** Business operation validation, allowed transitions, idempotency keys, template rendering, mapping/parsing, status/history creation, error classification.
- **Integration/contract:** Dataverse APIs, Outlook mail/calendar, Teams, SharePoint, LEGO proxy, and approved OCR; use isolated nonproduction identities and synthetic records/documents.
- **Authorization:** Positive and negative BSO/Admin (if approved) data/operation access; TA is not granted app access by default; verify field and CV access.
- **Concurrency:** Duplicate submit, concurrent transition, availability race, simultaneous dispatch, upsert duplication, cancellation/booking race.
- **Failure recovery:** Timeouts before/after provider action, throttling, partial sync, connector credential/policy error, provider unavailable, uncertain send/book/cancel, reconciliation and safe retry.
- **UAT:** BSO workflows across queues, calls, scheduling, email, results, visitor operations, and exception handling with synthetic data.
- **Production smoke:** Only after approved deployment; verify solution/configuration, identity, least-privilege access, key workflows and monitoring without sending unintended external messages.

## Critical assertions

- Every valid status transition has exactly one appropriate history record; invalid transitions fail server-side.
- TA availability is verified online; TA and room availability are verified offline. Unknown/error/stale is not free; recheck occurs immediately before booking where supported.
- Correct sender/organizer and logical To/CC are observed. One idempotency key produces no duplicate email. Indeterminate send is not blindly retried.
- Calendar uncertainty is reconciled before retry; confirmed event IDs and cancellation state are auditable.
- CV and salary/contact access obey authorization. No real candidate data leaks to logs, test artifacts, or repository.
- LEGO sync is idempotent and partial/error responses do not wipe valid postings; only Vietnam postings are visible and ambiguous title matches need manual resolution.
- Migration reconciliation covers approved counts, keys, relationships, status mapping, identity, and historical audit, with exceptions signed off.

## Evidence and exit

Record test environment/type, revision, prerequisites, case/results, and defects with sensitive data sanitized. Never report a test as passed if unrun. Production cutover requires relevant regression, authorization/security, integration failure, migration reconciliation, UAT sign-off, and smoke-test evidence. See [Acceptance Criteria](ACCEPTANCE_CRITERIA.md).
