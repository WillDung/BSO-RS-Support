# Candidate Core server operations

Source for the signed `os_sr_cact` Dataverse assembly, version `1.0.0.0`. This is authored .NET plug-in source, **not an exported/unpacked Solution**. The supported target is .NET Framework 4.6.2 with `Microsoft.CrmSdk.CoreAssemblies` pinned to 9.0.2.60; the SDK assembly is supplied by the Dataverse sandbox. No runtime dependency is merged/uploaded with this assembly.

## Phase 5B storage-boundary correction (29 October 2026)

The source audit proved that Candidate Core's protected Candidate and Interview Schedule reads used the initiating-user service even though the corresponding writes and Receipt operations used SYSTEM. The local source now routes all protected Candidate, Call Log, Status History, Interview Schedule, and Operation Receipt storage through the bounded SYSTEM service. Before Candidate data or full Interview Schedule data is retrieved, SYSTEM checks the initiating user's effective `ReadAccess` with `RetrievePrincipalAccess`; schedule discovery queries return IDs only until that check succeeds. Reference-table validation remains caller-context. Candidate owner and actor fields remain the initiating user, and Candidate Number remains server-generated.

CreateCandidate failures now have a constrained stage diagnostic (`RECEIPT_READ`, `CANDIDATE_CREATE`, `CANDIDATE_READBACK`, `RECEIPT_CREATE`, or `RESPONSE`) containing only the stage and sanitized code/category. The Candidate Console displays/logs only that allowlisted diagnostic, never the raw server error message.

**Deployment status:** local SDK and package validation do not establish that the edited source is deployed. The live VN LMV IT assembly is signed; no compatible signing key was available in this session. The unsigned package build is not compatible with that live assembly identity, so no package update or browser retry was performed. Phase 5B remains pending.

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
- The plug-in context remains the initiating caller and rejects mismatched or nested execution. The handler validates request inputs and caller-visible references with the initiating-user service, then creates the SYSTEM organization service with `CreateOrganizationService(null)`.
- SYSTEM access is confined to `ApplyCandidateAction` and its fixed operation store. All protected Candidate, Call Log, Status History, Interview Schedule, and Operation Receipt reads/writes use SYSTEM; Candidate and full Schedule reads verify the initiating user's effective `ReadAccess` through `RetrievePrincipalAccess` first. Schedule discovery queries return IDs only before the access check. Reference-table reads remain caller-context. The store exposes no caller-provided table, entity, message, or attribute names, and mutations remain constrained by `CandidateOperation.MutationMatrix`.
- The production BSO role must not receive direct Create/Write on protected business tables. Phase 5A readback in VN LMV IT confirmed live `os_sr_cact` uses `prvReados_sr_cand`; at that time the BSO role was unassigned. Phase 5B later assigned the role directly to the approved test identity. Protected-table Create/Write grants remain absent, but effective non-admin security acceptance is still pending.
- Organization-level auditing remains an external governance/release prerequisite, but it is not a Candidate Core runtime rejection. Required table-audit metadata and the append-only Status History/Operation Receipt business evidence remain mandatory. This does not enable or change organization auditing or waive governance gates for production rollout.
- Candidate creation/profile updates, the three call outcomes, Waiting Manual Scheduling, Round 1 scheduling, Pass/Fail, reschedule, and cancellation are implemented and offline-tested. Phase 5A runtime and browser lifecycle acceptance in VN LMV IT passed the scope recorded in the [acceptance report](../../docs/PHASE_5A_CANDIDATE_CORE_ACCEPTANCE_REPORT.md); this does not add browser acceptance for profile updates. The existing `os_sr_intv` Round 1 schedule is authoritative durable evidence for the manual Candidate Core workflow; active caller-readable TA and Location references and a valid future same-day UTC interval are required. Schedule persistence is read back before Candidate, Status History, and Receipt changes. Pass/Fail requires exactly one active Round 1 schedule without a terminal result. Reschedule/Cancel require that schedule plus a reason, preserve schedule history, and return Candidate to Need Call Candidate.
- The manual `os_sr_intv` record is workflow evidence, not proof of an external calendar booking or live calendar availability. This does not bypass the separate identity and fail-closed rules for any future Microsoft 365 calendar or email integration.
- Present profile fields replace, omitted fields preserve, and explicit null clears optional phone/lookups only. Name/email cannot be blank/null. UTC contact timestamps cannot be in the future.
- Versioned canonical request fingerprints include caller, correlation identity, action, target, expected status, and all supplied validated fields. Omission/null/type boundaries are distinct. Digests remain sensitive evidence, not anonymization.
- Receipt insert and applicable Candidate/Call/History effects share the caller's synchronous Dataverse transaction. Unique canonical-string correlation key prevents racing duplicate effects; transaction faults propagate without internal retry. An exact later replay returns persisted original effect IDs/status even after subsequent Candidate edits.
- `ProtectCandidateCore` source is retained for historical compatibility, but is superseded as the intended production security mechanism. The 50 registrations are documented inactive and were not changed by this local source update. Production direct-write denial is intended to come from Dataverse role privileges; SYSTEM writes are scoped to the approved API and its explicit mutation matrix rather than guard-specific `0x80040265` rejection.
- The `BSO-RS Support - BSO` role was directly assigned to the approved Phase 5B test identity; no additional role or team assignment was made. The observed live role uses Candidate Read for API execution and has no protected-table Create/Write grants. Effective non-admin acceptance is not established.
- The Phase 5A target is VN LMV IT only. The existing unsigned package was updated in place earlier in Phase 5A; the Candidate Console defaults to Candidate Core and retains explicit DEV rollback. Authenticated browser lifecycle and separate 27-dispatch replay/concurrency acceptance passed. No package update was required by the browser correction.
- `PHASE_5B_SECURITY_ACCEPTANCE_PENDING`. The approved test identity and app access are established, but the live Candidate Core retry and direct-write denial tests remain incomplete. Production acceptance, concurrent uniqueness races, and forced live rollback remain separate gates. Browser creation verified generated Candidate Numbers, not every AutoNumber concurrency behavior.

See the [API contract](../../docs/PHASE_3C_API_CONTRACT.json), [receipt contract](../../docs/PHASE_3C_OPERATION_RECEIPT_PLAN.json), [deployment runner](../../scripts/Deploy-BsoRsCandidateOperations.ps1), and [Phase 3C report](../../docs/PHASE_3C_CANDIDATE_CORE_API_PLUGIN_REPORT.md).
