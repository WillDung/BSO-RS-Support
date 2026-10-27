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
- Use existing Candidate Write execution privilege plus calling-user table/row permissions. The factory explicitly selects the initiating caller; contexts with a different execution user or nested invocation are rejected. No SYSTEM/service-account elevation.
- Organization-level auditing remains an external governance/release prerequisite, but it is not a Candidate Core runtime rejection. Required table-audit metadata and the append-only Status History/Operation Receipt business evidence remain mandatory. This does not enable or change organization auditing or waive governance gates for production rollout.
- Candidate creation/profile updates, approved calls, and scheduling-queue transition use the server contract. Future scheduled/result/reschedule actions reject until their evidence boundaries exist; a semantic transition test does not enable them in the API.
- Present profile fields replace, omitted fields preserve, and explicit null clears optional phone/lookups only. Name/email cannot be blank/null. UTC contact timestamps cannot be in the future.
- Versioned canonical request fingerprints include caller, correlation identity, action, target, expected status, and all supplied validated fields. Omission/null/type boundaries are distinct. Digests remain sensitive evidence, not anonymization.
- Receipt insert and applicable Candidate/Call/History effects share the caller's synchronous Dataverse transaction. Unique canonical-string correlation key prevents racing duplicate effects; transaction faults propagate without internal retry. An exact later replay returns persisted original effect IDs/status even after subsequent Candidate edits.
- `ProtectCandidateCore` rejects direct mutation entrypoints. It classifies table-bound writes from the current context's server-owned `OwningExtension`: the active processing step must resolve read-only to the exact package-backed guard type, assembly/package, SDK message, and matching message filter. Only exact supported message/entity pairs map to canonical WriteCodes; unsupported registrations fail closed. Populated runtime message/entity values are consistency checks only. An independently verified bounded `ApplyCandidateAction` ancestor, calling-user execution predicates, and the exact ActionType/write allowlist are still required to authorize a protected write. The bounded positive registration cache is process-local; negative results are not cached. Association guards retain their relationship-specific behavior.
- A supported caller needs an approved role with operation-specific Candidate and child/receipt privileges, including Append/AppendTo where applicable. This phase does **not** create/grant such a role or prove a non-admin user's effective rights.
- No API is invoked during metadata deployment verification. The separately authorized Phase 3D runtime slice may exercise supported Candidate Core actions against at most one unmistakably synthetic Candidate; scheduler/result/reschedule actions must continue to fail closed until trusted evidence exists. Live uniqueness races, forced rollback, AutoNumber behavior, and non-admin authorization remain separate acceptance evidence.

See the [API contract](../../docs/PHASE_3C_API_CONTRACT.json), [receipt contract](../../docs/PHASE_3C_OPERATION_RECEIPT_PLAN.json), [deployment runner](../../scripts/Deploy-BsoRsCandidateOperations.ps1), and [Phase 3C report](../../docs/PHASE_3C_CANDIDATE_CORE_API_PLUGIN_REPORT.md).
