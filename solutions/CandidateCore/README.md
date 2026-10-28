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
- The production BSO role must not receive direct Create/Write on protected business tables. Phase 5A readback in VN LMV IT confirms live `os_sr_cact` uses `prvReados_sr_cand`, present on the unassigned BSO role. Protected-table Create/Write grants are absent; effective non-admin security acceptance remains Phase 5B.
- Organization-level auditing remains an external governance/release prerequisite, but it is not a Candidate Core runtime rejection. Required table-audit metadata and the append-only Status History/Operation Receipt business evidence remain mandatory. This does not enable or change organization auditing or waive governance gates for production rollout.
- Candidate creation/profile updates, the three call outcomes, Waiting Manual Scheduling, Round 1 scheduling, Pass/Fail, reschedule, and cancellation are implemented and offline-tested. Phase 5A runtime and browser lifecycle acceptance in VN LMV IT passed the scope recorded in the [acceptance report](../../docs/PHASE_5A_CANDIDATE_CORE_ACCEPTANCE_REPORT.md); this does not add browser acceptance for profile updates. The existing `os_sr_intv` Round 1 schedule is authoritative durable evidence for the manual Candidate Core workflow; active caller-readable TA and Location references and a valid future same-day UTC interval are required. Schedule persistence is read back before Candidate, Status History, and Receipt changes. Pass/Fail requires exactly one active Round 1 schedule without a terminal result. Reschedule/Cancel require that schedule plus a reason, preserve schedule history, and return Candidate to Need Call Candidate.
- The manual `os_sr_intv` record is workflow evidence, not proof of an external calendar booking or live calendar availability. This does not bypass the separate identity and fail-closed rules for any future Microsoft 365 calendar or email integration.
- Present profile fields replace, omitted fields preserve, and explicit null clears optional phone/lookups only. Name/email cannot be blank/null. UTC contact timestamps cannot be in the future.
- Versioned canonical request fingerprints include caller, correlation identity, action, target, expected status, and all supplied validated fields. Omission/null/type boundaries are distinct. Digests remain sensitive evidence, not anonymization.
- Receipt insert and applicable Candidate/Call/History effects share the caller's synchronous Dataverse transaction. Unique canonical-string correlation key prevents racing duplicate effects; transaction faults propagate without internal retry. An exact later replay returns persisted original effect IDs/status even after subsequent Candidate edits.
- `ProtectCandidateCore` source is retained for historical compatibility, but is superseded as the intended production security mechanism. The 50 registrations are documented inactive and were not changed by this local source update. Production direct-write denial is intended to come from Dataverse role privileges; SYSTEM writes are scoped to the approved API and its explicit mutation matrix rather than guard-specific `0x80040265` rejection.
- The `BSO-RS Support - BSO` role remains unassigned, with zero user/team assignments. The observed live role uses Candidate Read for API execution and has no protected-table Create/Write grants. No effective non-admin access claim is made.
- The Phase 5A target is VN LMV IT only. The existing unsigned package was updated in place earlier in Phase 5A; the Candidate Console defaults to Candidate Core and retains explicit DEV rollback. Authenticated browser lifecycle and separate 27-dispatch replay/concurrency acceptance passed. No package update was required by the browser correction.
- `PHASE_5B_BSO_ROLE_ASSIGNMENT_APPROVAL_REQUIRED`. Production acceptance, effective non-admin authorization/app access, concurrent uniqueness races, and forced live rollback remain separate gates. Browser creation verified generated Candidate Numbers, not every AutoNumber concurrency behavior.

See the [API contract](../../docs/PHASE_3C_API_CONTRACT.json), [receipt contract](../../docs/PHASE_3C_OPERATION_RECEIPT_PLAN.json), [deployment runner](../../scripts/Deploy-BsoRsCandidateOperations.ps1), and [Phase 3C report](../../docs/PHASE_3C_CANDIDATE_CORE_API_PLUGIN_REPORT.md).
