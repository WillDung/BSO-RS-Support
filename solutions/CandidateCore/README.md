# Candidate Core server operations

Source for the signed `os_sr_cact` Dataverse assembly, version `1.0.0.0`. This is authored .NET plug-in source, **not an exported/unpacked Solution**. The supported target is .NET Framework 4.6.2 with `Microsoft.CrmSdk.CoreAssemblies` pinned to 9.0.2.60; the SDK assembly is supplied by the Dataverse sandbox. No runtime dependency is merged/uploaded with this assembly.

## Build and offline validation

From repository root, using a protected local strong-name key:

```powershell
dotnet build .\solutions\CandidateCore\CandidateCore.csproj -c Release "-p:CandidateSigningKey=C:\protected-local-path\candidate-signing.snk"
dotnet run --project .\tests\CandidateCore\CandidateCore.Tests.csproj -c Release
dotnet run --project .\tests\CandidateCoreSdk\CandidateCoreSdk.Tests.csproj -c Release
& .\tests\CandidateCoreSdk\bin\Release\net48\CandidateCoreSdk.Tests.exe
& .\tests\Phase3COperationReceipt.Tests.ps1
& .\tests\Phase3CDeployment.Tests.ps1
```

The legacy assembly build requires the protected local key and must not be used to build or validate the unsigned package. The SDK adapter harness references the unsigned package project directly, so it does not require that key. Do not commit private signing material. `bin`/`obj` are ignored. Preserve the same signing identity for compatible legacy assembly updates; assembly hash also depends on the signing key. No signing key, tenant identifiers, secrets, or real Candidate values are compiled into source.

## Runtime boundaries

- `ApplyCandidateAction` is the synchronous main-operation handler for the unbound private Action `os_sr_cact`. Private affects discovery, not authorization.
- The plug-in context remains the initiating caller and rejects mismatched or nested execution. Candidate reads use a caller-context organization service. The handler creates the SYSTEM organization service with `CreateOrganizationService(null)` only after the API context and request inputs are validated.
- SYSTEM access is confined to `ApplyCandidateAction` and its operation store. The API uses it to read the idempotency receipt and to persist only the exact action-specific Candidate, Call Log, Status History, Interview Schedule, and Receipt mutations listed by `CandidateOperation.MutationMatrix`. The store exposes no caller-provided table or entity names. Candidate, schedule, and reference reads remain caller-context; optional Position, Candidate Source, TA, and Location references are checked for caller visibility before SYSTEM service creation.
- The BSO role must not receive direct Create/Write on protected business tables. The current API contract still names `prvWriteos_sr_cand` as its execution privilege; that conflicts with the requested no-Candidate-Write role and remains unresolved. Do not assign that privilege or substitute another privilege until the supported API-only execution gate is verified.
- Organization-level auditing remains an external governance/release prerequisite, but it is not a Candidate Core runtime rejection. Required table-audit metadata and the append-only Status History/Operation Receipt business evidence remain mandatory. This does not enable or change organization auditing or waive governance gates for production rollout.
- Candidate creation/profile updates, approved calls, scheduling-queue transition, and Pass/Fail result persistence are implemented in local source and offline tests only. Pass/Fail requires exactly one caller-readable active Round 1 schedule with no prior result; the schedule result, Candidate transition, Status History, and Receipt share the synchronous Dataverse transaction.
- `MarkRound1Scheduled` remains fail-closed because no trusted TA/room availability evidence boundary exists; unknown or stale availability is not free. `RequestReschedule` and `CancelRound1` remain fail-closed because trusted calendar-event cancellation evidence is not implemented. Their DEV direct-write behavior is not promoted to production authority.
- Present profile fields replace, omitted fields preserve, and explicit null clears optional phone/lookups only. Name/email cannot be blank/null. UTC contact timestamps cannot be in the future.
- Versioned canonical request fingerprints include caller, correlation identity, action, target, expected status, and all supplied validated fields. Omission/null/type boundaries are distinct. Digests remain sensitive evidence, not anonymization.
- Receipt insert and applicable Candidate/Call/History effects share the caller's synchronous Dataverse transaction. Unique canonical-string correlation key prevents racing duplicate effects; transaction faults propagate without internal retry. An exact later replay returns persisted original effect IDs/status even after subsequent Candidate edits.
- `ProtectCandidateCore` source is retained for historical compatibility, but is superseded as the intended production security mechanism. The 50 registrations are documented inactive and were not changed by this local source update. Production direct-write denial is intended to come from Dataverse role privileges; SYSTEM writes are scoped to the approved API and its explicit mutation matrix rather than guard-specific `0x80040265` rejection.
- The `BSO-RS Support - BSO` role remains unassigned and was not changed. Its production privileges and the API execution privilege remain pending verified, non-production security acceptance. `prvWriteos_sr_cand` still conflicts with the required no-direct-Candidate-Write role. No effective non-admin access claim is made.
- These are local source changes only. They do not prove that the existing unsigned package, API metadata, deployed UI, or role has been updated. The currently documented VN LMV IT environment is Production; no environment was queried or changed for this work.
- The Custom API contract, package, Candidate Console, and role have not been updated from this local source. No deployment, runtime operation, browser acceptance, or effective non-admin authorization was performed. Live uniqueness races, forced rollback, AutoNumber behavior, and non-admin authorization remain separate acceptance evidence.

See the [API contract](../../docs/PHASE_3C_API_CONTRACT.json), [receipt contract](../../docs/PHASE_3C_OPERATION_RECEIPT_PLAN.json), [deployment runner](../../scripts/Deploy-BsoRsCandidateOperations.ps1), and [Phase 3C report](../../docs/PHASE_3C_CANDIDATE_CORE_API_PLUGIN_REPORT.md).
