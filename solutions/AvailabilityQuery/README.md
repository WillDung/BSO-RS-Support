# Availability Query source (offline)

This is source and a reference contract for P0 Slice 2A in the existing `os_sr_bso_rs_support` Solution. The completed offline vertical slice is not deployed or runtime accepted and does not change the frozen managed solution. The retained [stop report](../../docs/P0_SLICE_2A_DEV_PROVISIONING_REPORT.md) describes partial provider-independent provisioning, not freshly verified tenant state. This build performed no tenant operations.

- [OutlookMeetingTimesAdapter.cs](OutlookMeetingTimesAdapter.cs) defines the `Find meeting times (V2)` request and validates the expected response shape before filtering suggestions.
- [AvailabilityRules.cs](AvailabilityRules.cs) validates request and slot policy and defines canonical result JSON and safe error categories.
- [AvailabilityQueryPlugin.cs](AvailabilityQueryPlugin.cs) contains the separate `os_sr_avqg.ProtectAvailabilityQuery` Create/Update guard.
- [ReferenceDriftPolicy.cs](ReferenceDriftPolicy.cs) defines the Flow's memory-only pre-terminal reference comparison.
- [AvailabilityConfigurationRenderer.cs](AvailabilityConfigurationRenderer.cs) renders guard configuration offline from environment-specific values.
- [AvailabilityQuery.schema.json](../Entities/os_sr_avq/AvailabilityQuery.schema.json) is the unchanged offline table contract: no Candidate or Interview Schedule lookup and no provider-payload field.
- [availability-flow.contract.json](availability-flow.contract.json), environment-variable, role-delta, and retention files are design contracts, not actual Power Platform components. The C# adapter is an offline reference implementation; it is not an invocable Power Automate action.

## Outlook provider

The approved DEV provider is Office 365 Outlook **Find meeting times (V2)**. Online sends the TA as `RequiredAttendees` and an empty `ResourceAttendees`; Onsite also sends the room as `ResourceAttendees`. The action receives the requested duration and UTC window, a configured `MaxCandidates` from 1 to 200, string `"100"` for `MinimumAttendeePercentage`, `IsOrganizerOptional = true`, and `ActivityDomain = Work`. It receives no Candidate, Interview Schedule, or timezone input.

The adapter requires the top-level reason and suggestion array, time-slot start/end, and an attendee array with address, type, and availability. Each expected attendee must appear exactly once with the expected type and availability exactly `free`. Organizer availability is ignored. Every accepted slot is UTC, in the requested window, exactly the requested duration, aligned to 15 minutes, past the lead-time threshold, and wholly within one local business day and business hours in `SE Asia Standard Time`. Slots are sorted, deduplicated and serialized only as `startUtc`/`endUtc`. Unknown or malformed shapes fail closed; a valid response with no valid slots returns `NoSlots` / `NO_COMMON_SLOT`. No provider body, reason, mailbox snapshot, attendee status, location, confidence, or organizer identity is persisted or displayed.

The action has no timezone input. The adapter recognizes only `timeZone` exactly `UTC` with its explicitly supported timestamp formats. If the first synthetic live execution returns a different valid timezone representation: **STOP; do not retry or broaden conversion.** Capture only sanitized field names, types and timezone representation, then make a separately reviewed bounded correction. Offline tests do not establish the live response shape.

## Reference drift and identities

The Flow retains only reference IDs, active states and normalized mailbox addresses in memory before the call. Before every terminal write, it re-reads required TA/Location and applies `ReferenceDriftPolicy.BeforeTerminalWrite`. A changed ID/state/address or unreadable reference overrides the result with Failed / `REFERENCE_CHANGED` / `[]`; display-name-only changes are ignored. Online ignores Location. Secure Flow inputs/outputs must protect reference reads, the Outlook action and comparisons. The re-read is not a distributed lock or booking guarantee.

Neither the guard's domain check nor the Flow's comparison to submitted IDs enforces the privately approved reference IDs and mailbox addresses before Outlook. Offline synthetic probes confirmed that another same-domain address or reference ID can reach the local Outlook callback. Keep the Flow OFF and Availability disabled until an approved server-enforced exact-target check, or an independently verified equivalent restriction, covers both IDs and addresses before provider access; a later drift check cannot undo a provider call.

The documented DEV arrangement separates the BSO requester from the current DEV owner acting as Dataverse result writer, and specifies the owner's Outlook connection rather than the BSO's. The actual connector principal, mailbox access and consistency with the requested BSO session remain unverified and must be resolved before activation. The guard checks caller and initiating identity and does not permit the writer to create requests or the requester to write results. **`DEV_FUNCTIONAL_IDENTITY_ELEVATED_NOT_SECURITY_ACCEPTANCE`**: the owner is elevated, and this DEV arrangement is not least-privilege security acceptance. Production identity is a later decision.

## Canonical configuration binding

Environment configuration -> `AvailabilityConfigurationRenderer.Render` -> identical `ProtectAvailabilityQuery` unsecure configuration on both steps.

Pass exactly one resolved value for each definition in [availability-environment-variables.json](availability-environment-variables.json), including the proposed maximum-candidates definition, plus a separate environment-specific nonsecret result-writer user GUID. No actual environment values, identity GUID, mailbox address, credential, or rendered environment output is committed. Never maintain or hand-edit duplicate step configuration.

The renderer rejects missing, duplicate, unknown and credential settings, invalid business-hour JSON, horizon above the existing 61-day safety limit, durations not divisible by 15, and maximum candidates outside 1-200. Domains must be canonical lowercase DNS names. Output uses fixed scalar-key order, weekday order, LF separators and no trailing newline. The renderer calls the real `PluginConfiguration.Parse` and verifies exact equality to source semantics. The 61-day cap remains a conservative existing policy, not a claim about an Outlook connector limit.

## First-runtime Dataverse DateTime gate

Strict UTC validation remains unchanged. If the first synthetic availability create sends explicit UTC (`...Z`) but the plug-in rejects **only** because the bound `DateTime.Kind` is not UTC: **STOP. Do not retry. Do not normalize automatically. Localize the actual Dataverse transport representation first.**

The project has no Candidate Core project reference and Slice 2A must not call `os_sr_cact`. The external blocker remains `SLICE_2A_SYNTHETIC_MAILBOX_PREREQUISITE_MISSING`.

## Connected Check Calendar build

The existing Console submits request fields only. The Create guard establishes requester ownership and Pending; the existing Flow reads the request, validates settings and reference shapes, calls Outlook, filters slots, rechecks references, and submits only the six terminal-result fields. The Update guard validates the terminal result and immutable request/ownership fields. Its registration contract now covers **all Updates**, not just result-field updates. Available results also revalidate current references.

The seven added validators check business hours, configuration lists, request shape, TA response, Location response, provider response and UTC timestamps. Expression and dependency changes consume these checks, validate and normalize inputs/results, and keep a failed initial query read from attempting a terminal write. Malformed mailbox/control characters are rejected before provider access. These are offline source corrections, not evidence of a deployed Flow.

The Flow retains the original 26-location privacy hardening and all 33 originally protected actions, and protects six additional sensitive actions: **39 actions plus trigger output**. Seven connector policies request no automatic retries inside `inputs`; Microsoft's [Logic Apps retry reference](https://learn.microsoft.com/en-us/azure/logic-apps/error-exception-handling#retry-policies) documents that placement for actions that support retry policies, but does not certify this Power Automate deployment. The earlier bounded Retry-After proposal remains an owner/Technical Lead decision, not an implemented or newly approved requirement.

The Console validates selected references, dates, duration and canonical results; it shows Pending, slots, NoSlots and safe failures, and suppresses duplicate submissions while waiting. Refresh is a read, not a replacement request. No Candidate, Interview Schedule, event, Call Log or History mutation is introduced; manual scheduling remains unchanged.

[Full-path tests](../../tests/CheckCalendar.Integration.test.cjs) execute Console source through the real compiled Create guard, the actual Flow action tree with local connector fixtures, the real Update guard and Console rendering. They explicitly simulate the unresolved synthetic-isolation prerequisite; a separate test verifies that the real policy blocks synthetic requests. Online and Onsite slots, room-busy/empty results, throttling, drift and unsupported timezone are covered conditionally. This bounded WDL evaluator is not Microsoft runtime certification, Dataverse transport proof or effective privacy verification. See [test commands and limitations](../../tests/README.md#p0-slice-2a-offline-availability).

## Minimal gated DEV delta

The current source comparison covers the existing resources; it does not establish how the unresolved exact-target authorization gate will be satisfied. Do not create a second Flow, table, connection reference or Candidate Core change for this delta:

1. Verify the installed guard package against the source and a recoverable rollback artifact; update the existing package only if needed and separately authorized. Establish its two synchronous PreOperation registrations using identical canonically rendered configuration. Approve explicit execution order first; the contract does not invent one. The Update registration must invoke the guard for every update.
2. Conditionally update the **existing OFF** `os_sr_avchk` definition using a fresh exact ETag and the reviewed functional delta. Preserve identity, owner, OFF state, membership, bindings and unchanged source outside that delta; read back the complete definition and all required privacy settings. The historical 26-only preservation plan is not authorization for this functional delta.
3. Reconcile all six Console resources against a fresh baseline. The captured historical comparison found changes to HTML, policy, main and Availability scripts, with unchanged CSS; its bound environment script must not be replaced by the unconfigured source template. The generator's explicit `-AvailabilityEnabled` opt-in is restricted to bound synthetic DEV with Candidate Core enabled and no release profile. The default and checked-in configuration remain disabled, and the real policy independently blocks synthetic requests while isolation is unresolved. Generation does not authorize update or publication.

**Blocked writes:** require fresh exact-target/caller evidence and scope authorization; approval of all seven effective settings and guard execution order; separate requester/writer identities; verified intended Outlook connection, consent and TA/room free-busy access; and scoped update/readback controls. The owner's intended authorized BSO session is not proof of the Dataverse result-writer identity. If requester and writer resolve to one principal, stop rather than weakening the guard.

The unpublished-WebResource ETag race and publication exclusivity remain unresolved; do not overwrite or publish a draft around those gates. OFF Flow service preservation and activation/privacy approval remain separate gates. Only after these pass may the operator enable the feature and run one controlled request under an explicit stop/OFF-restoration plan. See the [existing runtime plan](../../docs/P0_SLICE_2A_BUSINESS_RUNTIME_CRITICAL_PATH.md#10-connected-build-and-first-runtime-handoff). No runtime smoke, deployment, registration or publication occurred in this build. `REAL_DATA_STILL_PROHIBITED`.
