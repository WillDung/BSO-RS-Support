# Availability Query source (offline)

This is source and a reference contract for P0 Slice 2A in the existing `os_sr_bso_rs_support` Solution. The Outlook refactor is not in the live or frozen managed solution, registered, deployed, or runtime accepted. A concurrent [stop report](../../docs/P0_SLICE_2A_DEV_PROVISIONING_REPORT.md) describes partial provider-independent schema creation, unverified in this offline session. No tenant operation is authorized.

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

The approved DEV requester is a separate BSO test identity; the result writer is the current DEV owner identity used by the Dataverse Flow connection. The Outlook connection also belongs to that owner, not the BSO. The guard checks caller and initiating identity and does not permit the writer to create requests or the requester to write results. **`DEV_FUNCTIONAL_IDENTITY_ELEVATED_NOT_SECURITY_ACCEPTANCE`**: the owner is elevated, and this DEV arrangement is not least-privilege security acceptance. Production identity is a later decision.

## Canonical configuration binding

Environment configuration -> `AvailabilityConfigurationRenderer.Render` -> identical `ProtectAvailabilityQuery` unsecure configuration on both steps.

Pass exactly one resolved value for each definition in [availability-environment-variables.json](availability-environment-variables.json), including the proposed maximum-candidates definition, plus a separate environment-specific nonsecret result-writer user GUID. No actual environment values, identity GUID, mailbox address, credential, or rendered environment output is committed. Never maintain or hand-edit duplicate step configuration.

The renderer rejects missing, duplicate, unknown and credential settings, invalid business-hour JSON, horizon above the existing 61-day safety limit, durations not divisible by 15, and maximum candidates outside 1-200. Domains must be canonical lowercase DNS names. Output uses fixed scalar-key order, weekday order, LF separators and no trailing newline. The renderer calls the real `PluginConfiguration.Parse` and verifies exact equality to source semantics. The 61-day cap remains a conservative existing policy, not a claim about an Outlook connector limit.

## First-runtime Dataverse DateTime gate

Strict UTC validation remains unchanged. If the first synthetic availability create sends explicit UTC (`...Z`) but the plug-in rejects **only** because the bound `DateTime.Kind` is not UTC: **STOP. Do not retry. Do not normalize automatically. Localize the actual Dataverse transport representation first.**

The project has no Candidate Core project reference and Slice 2A must not call `os_sr_cact`. The external blocker remains `SLICE_2A_SYNTHETIC_MAILBOX_PREREQUISITE_MISSING`.
