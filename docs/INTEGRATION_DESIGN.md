# Integration Design

**Status:** Contracts below are proposed. Connector permissions, APIs, identities, and environment configuration are unverified. External side effects must have explicit correlation and uncertain-outcome handling.

## Email

Use approved templates and capture the logical To/CC lists, intended sender, subject, rendered body snapshot, dispatch idempotency key, timestamps, and provider correlation. Confirm the current BSO's allowed Microsoft 365 identity before send; never silently use a fixed owner connection as the BSO. Treat provider-confirmed send as Sent, confirmed error as Failed, and timeout/ambiguous response as Indeterminate. Never blindly retry Indeterminate; reconcile first. A successful Flow run is not delivery proof. Test with synthetic recipients and verify actual From/recipients/message evidence before rollout.

## Calendar and Teams

Before booking, validate candidate status, active TA, valid linked LEGO Career, CV URL, interval, mode, and location if offline. BSO coordinates; candidate and TA are required attendees; offline room is a resource attendee. Online requires verified TA availability; offline requires verified TA and room availability. Unknown, failed, stale, or conflicting availability blocks booking. Recheck immediately before creation where supported. Store idempotency/correlation and provider event ID, and model confirmed, failed, and uncertain outcomes. Design cancellation, reschedule, reconciliation, time zones, organizer identity, and Teams link behavior explicitly. External calendars are not transactionally coupled to Dataverse.

The detailed P0 Slice 2 proposal is in [P0 Slice 2 calendar availability and booking](#p0-slice-2-calendar-availability-and-booking-proposed--architecture-approved).

## P0 Slice 2 calendar availability and booking (PROPOSED / ARCHITECTURE APPROVED)

**Status (2026-11-05):** `PROPOSED / ARCHITECTURE APPROVED`. Nothing in this section is implemented, deployed, provisioned, or runtime accepted. No flow, custom connector, connection reference, environment variable, app registration, schema change, or Console change exists for Slice 2. No tenant operation is authorized. Decisions D1–D8 in [Product Decisions](PRODUCT_DECISIONS.md#p0-slice-2-calendar-integration-proposed--architecture-approved) are `PENDING OWNER/TECHNICAL LEAD`.

The owner approved the Slice 2A architecture on 2026-11-05 with these invariants: `P0_SLICE_2A_DISPLAY_ONLY_AVAILABILITY_ARCHITECTURE_APPROVED`, `P0_SLICE_2A_CANDIDATE_STATE_INDEPENDENT`, `P0_SLICE_2A_NO_CANDIDATE_CORE_MUTATION`, `P0_SLICE_2A_NO_INTERVIEW_SCHEDULE_MUTATION`, `P0_SLICE_2A_PROPOSAL_DOCUMENTATION_AUTHORIZED`. Slices 2B–2D remain proposals beyond architecture level.

`P0_SLICE_1_LIVE_FUNCTIONALLY_ACCEPTED` is unchanged. The Slice 1 manual workflow (Waiting Manual Scheduling → `MarkRound1Scheduled` → Round 1 Scheduled, with `os_sr_intv` as the authoritative internal record) is not connected to Slice 2A. No manual/external scheduling switch exists or is proposed for 2A; that decision belongs to Slice 2B.

### Trusted integration boundary

Recommended option A: solution-aware Cloud Flows using governed connection references, calling Microsoft Graph through a solution custom connector. Decisions and state transitions stay in tested C# under Dataverse; flows only perform external I/O and write results back.

```text
Candidate Console (browser JS; no tokens, no secrets)
   │ Dataverse Web API only, as the signed-in BSO
   ▼
Dataverse
   ├─ os_sr_cact (Candidate Core) — sole authority for Candidate and schedule state (2B+ only)
   └─ Slice 2A: os_sr_avq availability-query row (no Candidate link)
   │ row trigger
   ▼
Solution Cloud Flow (I/O only, concurrency 1)
   ├─ connection reference → custom connector "Graph Scheduling" (OAuth, delegated; D1/D2)
   └─ connection reference → Dataverse (integration identity)
```

- **Rejected:** any browser call to Graph, and any Graph secret, token, certificate, or connection credential in Candidate Console JavaScript, web-resource configuration, or Dataverse business rows.
- Credentials live only in the Power Platform connection bound to the connection reference (and, for the custom connector, in the Entra app registration it uses). Dataverse stores identifiers and sanitized outcome codes only.
- The standard Office 365 Outlook connector is acceptable for reads but is not proposed for writes: its event actions do not expose Graph `transactionId` or extended properties, and its documented V4 update resets omitted fields.
- Option B (server-side service behind a custom connector) is a fallback if a delegated service account is rejected. Option C (secure backend with application permissions, Exchange RBAC for Applications scoping) is an escalation path: it requires Azure resources, and reading TA calendars would need `Calendars.Read` (event details) rather than free/busy-only access.

### Capability basis (Microsoft documentation, read 2026-11-05)

| Capability | Proposed use |
|---|---|
| [`calendar: getSchedule`](https://learn.microsoft.com/en-us/graph/api/calendar-getschedule) | Free/busy for TA and room; least privilege `Calendars.ReadBasic`. Each [`scheduleInformation`](https://learn.microsoft.com/en-us/graph/api/resources/scheduleinformation) entry can carry its own `error`. Only `availabilityView` code `0` is free. |
| Room as `resource` attendee ([create event](https://learn.microsoft.com/en-us/graph/api/user-post-events)) | Room accepts/declines asynchronously; onsite booking is confirmed only after `accepted` (2B). |
| Event `transactionId`, extended properties ([event](https://learn.microsoft.com/en-us/graph/api/resources/event)) | Booking GUID as `transactionId` (best effort) and as an extended property for authoritative lookup during reconciliation (2B). |
| [ImmutableId](https://learn.microsoft.com/en-us/graph/outlook-immutable-id), `iCalUId`, `changeKey` | Stable event identity, cross-copy correlation, and manual-edit detection (2B). No reliance on an undocumented `If-Match` for events. |
| [Update](https://learn.microsoft.com/en-us/graph/api/event-update) / [cancel](https://learn.microsoft.com/en-us/graph/api/event-cancel) | Attendees-only PATCH to add the candidate; organizer `cancel` (202) for cancellation and reschedule (2B). |
| [Online meetings on events](https://learn.microsoft.com/en-us/graph/outlook-calendar-online-meetings) | `isOnlineMeeting` + `onlineMeetingProvider=teamsForBusiness` at creation; irreversible once set (2C). |
| [Throttling](https://learn.microsoft.com/en-us/graph/throttling-limits) | Honour `Retry-After`; at most 4 concurrent requests per app per mailbox, so flow concurrency is 1. |
| [Connection references](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/create-connection-reference) | Solution flows bind to references; connections are supplied at import. |

Items still to verify in a spike: Dataverse-triggered flow start latency, `transactionId` deduplication window, event `If-Match` support, maximum `getSchedule` window, room response latency, Teams lobby behaviour, and `Place.Read.All` consent requirement.

### Business modes

| Mode | Required availability | Booking (2B+) |
|---|---|---|
| ONSITE | TA free **and** room free | One Outlook event: TA, room (resource), candidate |
| ONLINE | TA free | Outlook event with Teams join details (requires 2C) |
| HYBRID | Not modeled (D8) | — |

Unknown or error availability for any required source is **NOT AVAILABLE**. Fail closed.

### Slice 2A availability algorithm

1. Validate inputs in a Dataverse plug-in: TA active, `os_sr_ta_eml` syntactically valid and in the allowed-domain list; for ONSITE, Location active with a valid `os_sr_loc_rmeml`; window in the future and within the maximum length; duration allowed. Validation failure → `Failed` with a deterministic category; Graph is not called.
2. The flow calls `getSchedule` once for the TA and, if ONSITE, the room, with a 15-minute interval and UTC times.
3. A required source is Known only if its entry exists, has no `error`, and its `availabilityView` has exactly the expected length with characters `0`–`3`. Any unknown required source → `Failed`, zero slots.
4. A candidate slot is valid only if every 15-minute block is `0` for every required source (tentative counts as busy pending D5), it lies within business hours in `SE Asia Standard Time`, starts and ends on the same local day, and meets lead-time rules (D6). From 2B, active Dataverse bookings for the same TA/room are also excluded.
5. Known sources with no valid slot → `NoSlots` with a deterministic reason. At least one slot → `Available`.
6. Results carry an expiry. In 2A they are advisory display only.

### Slice 2A write boundary

| Category | Slice 2A rule |
|---|---|
| **A. Business-data writes** — Candidate, Call Log, Candidate Status History, Operation Receipt, `os_sr_intv`, TA Directory, Location; any `os_sr_cact` invocation | **Prohibited.** The availability panel must not call `os_sr_cact`, update Candidate or `os_sr_intv`, create Status History or Operation Receipt, pre-fill or invoke `MarkRound1Scheduled`, or advance Candidate state. |
| **B. Integration infrastructure/configuration writes** — `os_sr_avq` table and protection plug-in step, custom connector, Cloud Flow, connection references, environment variable definitions/values, Entra app registration and consent, Console/app web resources and their publication | **Potentially required later; each needs separate explicit authorization.** None is performed by this proposal. |
| **C. Runtime availability-query rows** — `os_sr_avq` request/result rows created by the BSO and completed by the integration identity | Required by the approved 2A design once B is authorized. Not Candidate business data: no Candidate or `os_sr_intv` lookup, no Candidate Core path. Synthetic-only in DEV; retention/purge is an open item. |

### Slice 2A acceptance contract

Slice 2A acceptance must prove all of the following, using synthetic TA/room test mailboxes only:

1. An availability query can be initiated from the panel.
2. The `Pending` state is visible.
3. An `Available` result displays slots.
4. A `NoSlots` result displays a deterministic reason.
5. An availability failure displays a safe, deterministic category (no raw Graph payload, token, or exception text).
6. Candidate rows remain unchanged.
7. Interview Schedule (`os_sr_intv`) rows remain unchanged.
8. Candidate Status History remains unchanged.
9. Operation Receipt remains unchanged.
10. No `os_sr_cact` call originates from the availability panel (plug-in trace and Receipt count baseline).

No Candidate state transition is part of Slice 2A acceptance. Additional technical checks: every unknown/error path yields zero slots; the organizer calendar receives no event; no token or secret appears in the browser, Dataverse rows, or flow run history inputs/outputs shown to makers.

### Candidate-state effects by phase

| Phase | Candidate-state effect |
|---|---|
| 2A Calendar Availability | **Candidate state unchanged.** No Candidate Core operation is invoked. |
| 2B Booking + Dataverse evidence (onsite), cancel, reschedule | Candidate state changes **only after** external booking succeeds **and** the state-changing booking outcome (proposed `RecordBookingOutcome`) is durably recorded through Candidate Core. A pending, failed, indeterminate, or compensating booking never advances Candidate. |
| 2C Teams | Teams integration must **not** independently advance Candidate state. A Teams link is a precondition of an ONLINE booking outcome, not a transition. |
| 2D Email / invitation hardening | Email or invitation outcome must **not** independently advance Candidate state unless a separately approved business rule explicitly requires it. |

### Slice 2B+ proposal summary

These are proposals for later approval, not 2A scope:

- **Transaction boundary:** (1) `RequestRound1Booking` atomically records booking intent, booking GUID, and Receipt in Dataverse, leaving Candidate unchanged; (2) the flow performs external calls and writes external identifiers back immediately; (3) `RecordBookingOutcome` atomically promotes the schedule to Scheduled, moves Candidate to Round 1 Scheduled, and writes Status History and Receipt. `RecordBookingOutcome` and `RecordCancellationOutcome` are callable only by the integration principal; Status History keeps the requesting BSO as actor.
- **Booking states:** Requested → InProgress → ExternalCreated → Confirmed; Failed; Indeterminate; Compensating; ReconciliationRequired; CancelRequested → CancelConfirmed; CancelIndeterminate. An event is created with internal attendees first; the candidate is added only after room acceptance (and Teams link in 2C), so a compensating cancel never reaches the candidate.
- **Idempotency:** one booking GUID per operation, used as `transactionId` and extended property; lookup before any create; re-POST only after absence is confirmed. No blind retry after an ambiguous outcome. A Dataverse failure after event creation never triggers automatic external cancel; it goes to retry then ReconciliationRequired.
- **Reschedule:** cancel the existing event and create a replacement after the Candidate is re-contacted (current rule: Round 1 Scheduled → Need Call Candidate). The prior row becomes Superseded and keeps its external identifiers.
- **Cancel:** organizer cancel releases the room and the Teams meeting; Candidate returns to Need Call Candidate only after cancellation is confirmed; identifiers and cancellation evidence are preserved.
- **Email:** the calendar invitation is the event and Exchange sends it; no separate recruitment email by default. Any separate email (2D) follows the [Email](#email) rules.
- **Open 2B dependencies:** the existing rule that booking requires a valid linked LEGO Career and CV URL; the manual/external scheduling switch; `os_sr_intv_loc` requiredness (D7).

| Failure | User-visible | Dataverse state | Retry | Reconciliation | Operator |
|---|---|---|---|---|---|
| TA/room busy at recheck | Slot no longer available | Failed; schedule Withdrawn | New query | — | No |
| `getSchedule` timeout | Availability unknown | `os_sr_avq` Failed | User re-runs (read-only) | — | No |
| Create timeout / lost response | Booking pending verification | Indeterminate | **None blind** | Extended-property lookup | If lookup fails |
| 401 / 403 | Calendar integration unavailable | Failed `GRAPH_AUTH` | No | — | Yes; alert |
| 404 mailbox/resource | Calendar not found | Failed / `os_sr_avq` Failed | No | — | Yes; fix reference data |
| 409 / concurrency | Conflict, refresh | Unchanged or Failed | Re-read first | Compare `changeKey` | If persistent |
| 429 | Busy, retrying | Unchanged | Bounded, honour `Retry-After` | — | No |
| Dataverse write fails after create | Pending | ExternalCreated / InProgress | Bounded idempotent Dataverse retry | Extended-property lookup | If retries exhausted |
| Room declines / no response | Room not confirmed | Compensating → Failed | No | Verify cancel | If cancel unclear |
| Teams link missing (2C) | Online meeting not provisioned | Compensating → Failed | Bounded re-GET | — | If cancel unclear |
| Invitation/email indeterminate (2D) | Send unverified | Dispatch Indeterminate | **Never blind** | Sent Items via immutable draft id | Yes |
| Reschedule / cancel partial failure | Cancellation pending | CancelRequested / CancelIndeterminate; Candidate unchanged | No | GET event / `isCancelled`; 404 = gone | If unresolved |

## SharePoint

SharePoint is approved document storage, not candidate workflow authority. Canonical initial booking prerequisite is a valid candidate CV URL. Whether to store binary CVs, folder/library structure, permissions, retention, malware scanning, migration, and link validation remain open. Do not copy real CVs into development or this repository.

## LEGO Careers

Intended source: LEGO's official careers proxy API. Define authentication, endpoint, schema, pagination, rate limits, schedule, timeouts, country/location interpretation, and change/deactivation semantics with the API owner. Only Vietnam postings are visible for this workflow. Use stable external IDs and idempotent upsert. Exactly one title match may auto-select; zero/multiple require manual resolution. On partial/error responses, preserve previously valid records. No endpoint or credentials are recorded here.

## OCR / AI Builder

Optional and conditional on organizational approval, privacy review, accuracy/quality evaluation, licensing/capacity, and human correction. Define document scope, extraction schema, confidence thresholds, retention, and failure/manual fallback. OCR does not authorize automatic candidate state changes.

## Shared contract requirements

Use a correlation identifier across Dataverse action, Flow, and provider where supported. Keep error details sanitized; do not log credentials or unnecessary payload/PII. Use bounded retries only when outcome semantics and idempotency permit. For uncertain non-idempotent actions, reconcile against provider state before retry. Define monitoring, alert ownership, retention, and operational runbooks before production. See [Master Production Rules](../MASTER_PRODUCTION_RULES.md).
