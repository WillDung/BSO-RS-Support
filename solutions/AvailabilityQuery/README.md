# Availability Query source (offline)

This is an isolated source proposal for P0 Slice 2A in the existing `os_sr_bso_rs_support` Solution. It is not in the live or frozen managed solution, is not registered, and has not been deployed.

- `AvailabilityRules.cs` contains a deterministic, Graph-independent calculation and strict result JSON contract.
- `AvailabilityQueryPlugin.cs` contains the separate `os_sr_avqg.ProtectAvailabilityQuery` Create/Update guard.
- [ReferenceDriftPolicy.cs](ReferenceDriftPolicy.cs) defines the Flow's memory-only pre-terminal reference comparison.
- [AvailabilityConfigurationRenderer.cs](AvailabilityConfigurationRenderer.cs) renders canonical unsecure configuration offline from approved environment-specific values.
- `..\Entities\os_sr_avq\AvailabilityQuery.schema.json` is the canonical offline schema contract; it deliberately contains no Candidate or Interview Schedule lookup and no raw provider data field.
- `graph-scheduling.openapi.json` exposes exactly one operation, `getSchedule`; OAuth client values are not present.
- The flow, environment-variable, role-delta, and retention files are design contracts, not actual Power Platform components.
- The package identity is `os_sr_avqg_pkg`; its assembly and namespace are `os_sr_avqg`. No package has been built for deployment or pushed.

## Reference drift

The [Flow contract](availability-flow.contract.json) reads the query and active TA and, for Onsite only, Location before Graph. It retains only reference IDs, active states and normalized mailbox addresses in memory; Graph uses those same trimmed/lowercase addresses. Immediately before **any** terminal write (Available, NoSlots or Failed), it re-reads the required references and applies `ReferenceDriftPolicy.BeforeTerminalWrite`. A changed ID/state/address or an unreadable required reference overrides the result with Failed, `[]` slots and `REFERENCE_CHANGED`. Display-name changes are ignored. Online ignores Location. No snapshot, mailbox address or raw Graph payload is persisted or logged; sensitive Flow actions require secure inputs/outputs. Drift does not automatically retry, invoke Candidate Core or change business rows. This is a read-before-write check, not a distributed lock or booking guarantee.

## Canonical configuration binding

Environment configuration -> `AvailabilityConfigurationRenderer.Render` -> `ProtectAvailabilityQuery` unsecure configuration.

Pass exactly one resolved value for each of the six definitions in [availability-environment-variables.json](availability-environment-variables.json), plus the separate environment-specific **nonsecret** Dataverse integration application-user GUID. The GUID is not a Graph credential. No actual environment values, identity GUID or rendered environment output is committed. Never maintain a second hand-written copy or hand-edit either step's output.

The renderer rejects missing/duplicate/unknown settings, credential keys, invalid business-hour JSON (including duplicate/unknown properties), horizon above 61, and durations not divisible by 15. Domains must be canonical lowercase DNS names, without trailing dots; separator whitespace is ignored. Domain/duration list order is preserved. Output uses fixed scalar-key order, weekday order, LF separators and no trailing newline. Both steps must use identical bytes. The renderer calls the **real** `PluginConfiguration.Parse` and verifies exact equality of parsed identity, scalar values, lists and business-hour boundaries against source semantics. The parser now rejects unknown keys and case-insensitive duplicate keys. Policy changes start in approved environment values and require regeneration, not manual synchronization. No authentication or tenant read is performed by rendering.

## First-runtime DateTime gate

Strict UTC validation remains unchanged. If the first synthetic availability create sends explicit UTC (`...Z`) but the plug-in rejects **only** because the bound `DateTime.Kind` is not UTC: **STOP. Do not retry. Do not normalize automatically. Localize the actual Dataverse transport representation first.** No transport behavior is claimed by offline tests.

The project is separate from the Candidate Core assembly and has no Candidate Core project reference. Slice 2A must not call `os_sr_cact`.
