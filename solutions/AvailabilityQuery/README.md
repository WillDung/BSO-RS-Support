# Availability Query source (offline)

This is an isolated source proposal for P0 Slice 2A in the existing `os_sr_bso_rs_support` Solution. It is not in the live or frozen managed solution, is not registered, and has not been deployed.

- `AvailabilityRules.cs` contains a deterministic, Graph-independent calculation and strict result JSON contract.
- `AvailabilityQueryPlugin.cs` contains the separate `os_sr_avqg.ProtectAvailabilityQuery` Create/Update guard.
- `..\Entities\os_sr_avq\AvailabilityQuery.schema.json` is the canonical offline schema contract; it deliberately contains no Candidate or Interview Schedule lookup and no raw provider data field.
- `graph-scheduling.openapi.json` exposes exactly one operation, `getSchedule`; OAuth client values are not present.
- The flow, environment-variable, role-delta, and retention files are design contracts, not actual Power Platform components.
- The package identity is `os_sr_avqg_pkg`; its assembly and namespace are `os_sr_avqg`. No package has been built for deployment or pushed.

The plug-in step uses nonsecret, environment-specific unsecure configuration. It must contain only the selected Dataverse integration application-user GUID and the environment's policy values. No GUID or environment values are committed. The same values must be aligned with the solution environment variables at deployment.

The project is separate from the Candidate Core assembly and has no Candidate Core project reference. Slice 2A must not call `os_sr_cact`.
