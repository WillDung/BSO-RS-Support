# Integration Design

**Status:** Contracts below are proposed. Connector permissions, APIs, identities, and environment configuration are unverified. External side effects must have explicit correlation and uncertain-outcome handling.

## Email

Use approved templates and capture the logical To/CC lists, intended sender, subject, rendered body snapshot, dispatch idempotency key, timestamps, and provider correlation. Confirm the current BSO's allowed Microsoft 365 identity before send; never silently use a fixed owner connection as the BSO. Treat provider-confirmed send as Sent, confirmed error as Failed, and timeout/ambiguous response as Indeterminate. Never blindly retry Indeterminate; reconcile first. A successful Flow run is not delivery proof. Test with synthetic recipients and verify actual From/recipients/message evidence before rollout.

## Calendar and Teams

Before booking, validate candidate status, active TA, valid linked LEGO Career, CV URL, interval, mode, and location if offline. BSO coordinates; candidate and TA are required attendees; offline room is a resource attendee. Online requires verified TA availability; offline requires verified TA and room availability. Unknown, failed, stale, or conflicting availability blocks booking. Recheck immediately before creation where supported. Store idempotency/correlation and provider event ID, and model confirmed, failed, and uncertain outcomes. Design cancellation, reschedule, reconciliation, time zones, organizer identity, and Teams link behavior explicitly. External calendars are not transactionally coupled to Dataverse.

The detailed P0 Slice 2 proposal is in [P0 Slice 2 calendar availability and booking](#p0-slice-2-calendar-availability-and-booking-proposed--architecture-approved).

## P0 Slice 2 calendar availability and booking (PROPOSED / ARCHITECTURE APPROVED)

**Latest owner direction and concurrent DEV report (2026-11-05):** the Outlook connector DEV path is feasible, DEV identity Option A is approved for later functional testing using the existing owner connection, synthetic mailbox prerequisites are missing, and the custom Graph path is abandoned. The concurrently appearing [provisioning stop report](P0_SLICE_2A_DEV_PROVISIONING_REPORT.md) states that bounded provider-independent provisioning stopped at `P0_SLICE_2A_RECONCILIATION_FAILED:MEMBERSHIP:10` after partial table/TA-relationship creation, before roles, configuration definitions, publication or provider components. Its tenant observations are **unverified in this offline session**. Do not infer total absence or continue provisioning without separate verification and approval.

**Status (2026-11-05):** The owner supplied `SLICE_2A_OUTLOOK_CONNECTOR_PREFLIGHT_ACCEPTED`, `SLICE_2A_OUTLOOK_CONNECTOR_DEV_PATH_FEASIBLE`, `SLICE_2A_DEV_IDENTITY_OPTION_A_APPROVED`, `SLICE_2A_CUSTOM_GRAPH_PATH_ABANDONED`, and `SLICE_2A_SYNTHETIC_MAILBOX_PREREQUISITE_MISSING`. These supersede the former Slice 2A Graph path. Offline Slice 2A source and tests are in [AvailabilityQuery](../solutions/AvailabilityQuery/), its [schema contract](../solutions/Entities/os_sr_avq/AvailabilityQuery.schema.json), and the [Console panel](../solutions/CandidateConsole/WebResources/os_/bso/candidate-console-availability.js). The Outlook refactor is **not deployed or runtime accepted**; the concurrent partial-schema report and supplied preflight are not independently verified by this offline task. No tenant operation is authorized here.

The owner approved the Slice 2A architecture on 2026-11-05 with these invariants: `P0_SLICE_2A_DISPLAY_ONLY_AVAILABILITY_ARCHITECTURE_APPROVED`, `P0_SLICE_2A_CANDIDATE_STATE_INDEPENDENT`, `P0_SLICE_2A_NO_CANDIDATE_CORE_MUTATION`, `P0_SLICE_2A_NO_INTERVIEW_SCHEDULE_MUTATION`, `P0_SLICE_2A_PROPOSAL_DOCUMENTATION_AUTHORIZED`. Slices 2B–2D remain proposals beyond architecture level.

`P0_SLICE_1_LIVE_FUNCTIONALLY_ACCEPTED` is unchanged. The Slice 1 manual workflow (Waiting Manual Scheduling → `MarkRound1Scheduled` → Round 1 Scheduled, with `os_sr_intv` as the authoritative internal record) is not connected to Slice 2A. No manual/external scheduling switch exists or is proposed for 2A; that decision belongs to Slice 2B.

### Trusted integration boundary

Approved DEV option A is a solution-aware Cloud Flow using the standard Office 365 Outlook **Find meeting times (V2)** action and a Dataverse connection in the existing `os_sr_bso_rs_support` Solution. The request creator is a separate BSO test identity; the result writer is the current DEV owner identity used by the Dataverse Flow connection. The Outlook connection belongs to that owner, not to or impersonating the BSO. The guard checks both calling and initiating identity. `DEV_FUNCTIONAL_IDENTITY_ELEVATED_NOT_SECURITY_ACCEPTANCE`: the owner is elevated, so this is functional DEV wiring, not a least-privilege security acceptance. Production identity remains a later decision.

```text
Candidate Console (browser JS; no tokens, no secrets)
   │ Dataverse Web API only, as the signed-in BSO
   ▼
Dataverse
   └─ os_sr_avq availability-query row (no Candidate or Interview Schedule link)
   │ row trigger
   ▼
Solution Cloud Flow (I/O only, concurrency 1)
   ├─ Office 365 Outlook → Find meeting times (V2), current DEV owner connection
   └─ Dataverse → current DEV owner result-writer connection
```

- The browser calls Dataverse only. No credentials, tokens, mailbox snapshots, or provider payloads belong in Console configuration, business rows, or logs.
- The former custom connector, project Entra app, delegated permission, consent, and dedicated Dataverse application-user DEV prerequisites are **`SUPERSEDED_BY_OUTLOOK_CONNECTOR_ARCHITECTURE`**. Do not recreate them for 2A.
- Connection references remain governed ALM inputs; no connection, role, Flow, or environment configuration is created by this source. Production licensing, DLP, identities, and least privilege remain subject to separate governance, not established by DEV functional feasibility.

### Capability basis (Microsoft documentation, read 2026-11-05)

| Capability | Proposed use |
|---|---|
| [Office 365 Outlook: Find meeting times (V2)](https://learn.microsoft.com/en-us/connectors/office365/#find-meeting-times-%28v2%29) | Approved Slice 2A action. Its documented input includes required and resource attendees, duration, window, maximum candidates, attendee percentage, organizer optionality, and activity domain; its V2 response documents attendee address/type/availability. Live response shape remains unverified. |
| Room as `resource` attendee ([create event](https://learn.microsoft.com/en-us/graph/api/user-post-events)) | Room accepts/declines asynchronously; onsite booking is confirmed only after `accepted` (2B). |
| Event `transactionId`, extended properties ([event](https://learn.microsoft.com/en-us/graph/api/resources/event)) | Booking GUID as `transactionId` (best effort) and as an extended property for authoritative lookup during reconciliation (2B). |
| [ImmutableId](https://learn.microsoft.com/en-us/graph/outlook-immutable-id), `iCalUId`, `changeKey` | Stable event identity, cross-copy correlation, and manual-edit detection (2B). No reliance on an undocumented `If-Match` for events. |
| [Update](https://learn.microsoft.com/en-us/graph/api/event-update) / [cancel](https://learn.microsoft.com/en-us/graph/api/event-cancel) | Attendees-only PATCH to add the candidate; organizer `cancel` (202) for cancellation and reschedule (2B). |
| [Online meetings on events](https://learn.microsoft.com/en-us/graph/outlook-calendar-online-meetings) | `isOnlineMeeting` + `onlineMeetingProvider=teamsForBusiness` at creation; irreversible once set (2C). |
| Provider throttling | Flow concurrency is 1; the source contract allows at most two bounded `429` retries honoring `Retry-After`. No retry is allowed after an unsupported first-live timezone or response shape. |
| [Connection references](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/create-connection-reference) | Solution flows bind to references; connections are supplied at import. |

The event/Teams capabilities in this table are later-slice proposals, not part of the 2A Outlook read. Their runtime behavior, booking identity, permissions and implementation remain open.

### Business modes

| Mode | Required availability | Booking (2B+) |
|---|---|---|
| ONSITE | TA free **and** room free | One Outlook event: TA, room (resource), candidate |
| ONLINE | TA free | Outlook event with Teams join details (requires 2C) |
| HYBRID | Not modeled (D8) | — |

Unknown or error availability for any required source is **NOT AVAILABLE**. Fail closed.

### Slice 2A availability algorithm

1. Trigger on a new Pending `os_sr_avq`, read the request and TA, and read Location only for ONSITE. Validate active references, email syntax and allowed domains, future UTC window and allowed duration. Keep only the reference IDs, active states and normalized emails in Flow memory.
2. Call Office 365 Outlook `Find meeting times (V2)`: `RequiredAttendees` is the TA; `ResourceAttendees` is empty ONLINE and the room ONSITE; `MeetingDuration`, `Start`, and `End` are the request values; `MaxCandidates` is the configured 1–200 bound; `MinimumAttendeePercentage` is string `"100"`; `IsOrganizerOptional` is `true`; `ActivityDomain` is `Work`. There is no Candidate, Interview Schedule or timezone input.
3. Validate the entire response: required top-level `emptySuggestionsReason` and `meetingTimeSuggestions[]`; each suggestion's `meetingTimeSlot.start/end` each contain `dateTime` and `timeZone`, and `attendeeAvailability[]` entries each contain `attendee.emailAddress.address`, `attendee.type` and `availability`. Optional confidence, organizer availability, reason and locations are shape-checked but never used as availability evidence. Unknown/missing/changed shapes fail with a safe category and no slots.
4. The adapter recognizes only `timeZone` exactly `UTC` and explicitly supported UTC timestamp formats. Each expected address must appear exactly once as the required TA or resource room and its availability must be exactly `free`. Tentative, busy, oof, workingElsewhere, unknown, missing, duplicate, or malformed attendee data never establishes free time. The organizer calendar does not decide acceptance.
5. Capture current UTC after the provider call; use that same instant for queried-at and lead-time filtering, never a backdated request or call-start time. Accept only suggestions wholly inside the requested window, of exactly the requested duration, aligned to 15 minutes, meeting lead time, and within business hours on the same local day in `SE Asia Standard Time`. Sort ascending, remove identical duplicates, and enforce slot-count and JSON-length limits. Conflicting duplicate availability observations fail closed.
6. A valid response with no valid suggestions → `NoSlots` / `NO_COMMON_SLOT`; at least one valid slot → `Available`; provider error, malformed shape or unsupported timezone → `Failed` with a safe category. Never expose or persist `emptySuggestionsReason`, suggestion reason, connector error body, diagnostics, raw payload, addresses, attendee status, locations, confidence, or organizer identity. `os_sr_avq_slts` contains only UTC `startUtc` and `endUtc`.
7. Immediately before **any** terminal write, re-read TA and, for ONSITE only, Location. Apply [ReferenceDriftPolicy.BeforeTerminalWrite](../solutions/AvailabilityQuery/ReferenceDriftPolicy.cs): changed reference ID, active state or normalized mailbox address (or an unreadable required reference) overrides Available, NoSlots or Failed with **Failed**, slots `[]`, error `REFERENCE_CHANGED`, no reason. Display-name-only changes do not invalidate. Do not retry automatically or mutate Candidate/Core. This is not a distributed lock; 2A never guarantees a booking.
8. Write exactly one terminal result and expiry. In 2A the result is advisory display only. Secure inputs/outputs on reference reads, Outlook and snapshot/comparison actions so memory-only values do not become retained run-history payloads. The [Flow contract](../solutions/AvailabilityQuery/availability-flow.contract.json) is a source contract, not a deployed Flow; the C# adapter is a tested reference, not a directly invocable Power Automate action.

### Slice 2A write boundary

| Category | Slice 2A rule |
|---|---|
| **A. Business-data writes** — Candidate, Call Log, Candidate Status History, Operation Receipt, `os_sr_intv`, TA Directory, Location; any `os_sr_cact` invocation | **Prohibited.** The availability panel must not call `os_sr_cact`, update Candidate or `os_sr_intv`, create Status History or Operation Receipt, pre-fill or invoke `MarkRound1Scheduled`, or advance Candidate state. |
| **B. Integration infrastructure/configuration writes** — `os_sr_avq` table and protection plug-in step, Cloud Flow, Outlook/Dataverse connection references, environment variable definitions/values, Console/app web resources and publication | **Potentially required later; each needs separate explicit authorization.** None is performed by this offline task. A custom connector, project Entra app, consent and dedicated application user are not DEV prerequisites. |
| **C. Runtime availability-query rows** — `os_sr_avq` request/result rows created by the BSO and completed by the integration identity | Required by the approved 2A design once B is authorized. Not Candidate business data: no Candidate or `os_sr_intv` lookup, no Candidate Core path. Synthetic-only in DEV; 30-day retention is approved, while cleanup remains unimplemented and separately gated. |

### Slice 2A acceptance contract

Slice 2A acceptance must prove all of the following, using synthetic TA/room test mailboxes only:

1. An availability query can be initiated from the panel.
2. The `Pending` state is visible.
3. An `Available` result displays slots.
4. A `NoSlots` result displays a deterministic reason.
5. An availability failure displays a safe, deterministic category (no raw provider payload, token, or exception text).
6. Candidate rows remain unchanged.
7. Interview Schedule (`os_sr_intv`) rows remain unchanged.
8. Candidate Status History remains unchanged.
9. Operation Receipt remains unchanged.
10. No `os_sr_cact` call originates from the availability panel (plug-in trace and Receipt count baseline).

No Candidate state transition is part of Slice 2A acceptance. Additional technical checks: every unknown/error path yields zero slots; the organizer calendar receives no event; no token or secret appears in the browser, Dataverse rows, or flow run history inputs/outputs shown to makers.

### Offline source status and preflight gates

The offline source defines the unchanged schema contract, isolated guard and Outlook response adapter, logical Flow contract, environment-variable definitions without values, role delta, and 30-day cleanup design. The Console panel is separately gated and follows the shared `[DEV]` reference policy. These artifacts are not included in the frozen managed 1.0.0.1 artifact and must not be described as tenant resources.

The owner-supplied preflight states Outlook DEV feasibility but `SLICE_2A_SYNTHETIC_MAILBOX_PREREQUISITE_MISSING` remains the external blocker. Existing `[DEV]` references use `.invalid` addresses and cannot be used for live calendar checks. No mailbox, connection, Flow, schema, role or publication is authorized by the offline refactor.

Canonical binding is **approved environment configuration -> [AvailabilityConfigurationRenderer.Render](../solutions/AvailabilityQuery/AvailabilityConfigurationRenderer.cs) -> plug-in unsecure configuration**. The existing six business settings plus a proposed `os_sr_avq_maxc` definition provide source values; the result-writer GUID is a separate environment-specific nonsecret input. The new technical name remains pending approval. Do not maintain hand-written duplicate values. The renderer validates all seven values, parses its deterministic output through the real `PluginConfiguration.Parse`, and verifies equality to source semantics. Both guard steps receive identical bytes. The existing 61-day safety cap is retained as policy, not an Outlook connector limitation. No credentials, identity GUID, mailbox values or rendered environment output are committed.

**First-runtime provider timezone gate:** the action has no timezone input. If the first synthetic execution returns a different valid timezone representation from the adapter's explicit UTC contract: **STOP. Do not retry or broaden conversion.** Capture sanitized field names, types and timezone representation only, without raw provider output or mailbox values, and make a separately reviewed bounded correction.

**First-runtime DateTime gate:** retain strict UTC validation. If the first synthetic availability create sends explicit UTC (`...Z`) but the plug-in rejects **only** because the bound `DateTime.Kind` is not UTC: **STOP. Do not retry. Do not normalize automatically. Localize the actual Dataverse transport representation first.** Offline tests do not establish Dataverse transport Kind; changing UTC interpretation requires separate approval.

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
| Outlook availability timeout | Availability unknown | `os_sr_avq` Failed | No blind repeat | — | No |
| Create timeout / lost response | Booking pending verification | Indeterminate | **None blind** | Extended-property lookup | If lookup fails |
| 401 / 403 | Calendar integration unavailable | Failed `PROVIDER_AUTH` / `PROVIDER_PERMISSION` | No | — | Yes; alert |
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
