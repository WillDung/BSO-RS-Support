# Phase 3D - Candidate Core Synthetic Runtime Acceptance

Date: 26 October 2026. This report records the R4O server-registration classifier implementation, one existing-package update, and the resulting CreateCandidate rejection; earlier runtime failures remain historical evidence. Source: owner authorization, current repository contract/source, guarded live reconciliation, local offline validation, and the supported Dataverse plug-in package model.

## Fast Track MVP: Package Update and CreateCandidate Runtime Stop

**Result:** `CREATECANDIDATE_RUNTIME_FAILURE`; exact safe rejection `DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_PROTECTED_WRITE:CC_CREATE_CANDIDATE:0x80040265`. This run stops Candidate Core hardening as directed. The earlier marker and server-registration metadata mechanisms are superseded for MVP authorization. `ProtectCandidateCore` uses the source-known child message/entity mapping and a bounded trusted `os_sr_cact` ParentContext ancestor; direct writes without that ancestor remain rejected. The exact ActionType/write matrix was not broadened.

### Package update and preflight

The local unsigned `os_sr_cact_pkg` 1.0.0 artifact was pushed once to the already-existing package in VN LMV IT. No new package, registration PATCH, handler PATCH, API/schema change, trace/profiler change, security change, or signing-key access occurred. Immediate GET-only reconciliation confirmed the existing package ID/unique name, package-backed `os_sr_cact.ApplyCandidateAction`, 50 package-backed `os_sr_cact.ProtectCandidateCore` guard steps, unchanged API/schema contract, trace setting Off, and no active Candidate Core Profiler wrappers.

Fresh pre-dispatch inventory resolved 50/50 registrations: six exact canonical message/entity pairs, 42 fail-closed unsupported pairs, and two relationship guards; zero unresolved and zero contradictory mappings. This is a registration-topology inventory and is **not** used by the MVP runtime classifier. Normalized inventory SHA-256: `070a6be1d49d3d0d831df757d470024a37283312749e8b19a1a5615b7ecc7480`.

Local artifact hashes:

| Artifact | SHA-256 |
|---|---|
| Unsigned `os_sr_cact.dll` | `62d8b4426a3060b3cd473a440ae9df70ff6543c74064a6b0c610815882f41425` |
| Unsigned `os_sr_cact_pkg.1.0.0.nupkg` | `277f02e13a2e223698eb1899aa5703231447062d45d7a93c0476148577b10f4b` |

These are local build-artifact hashes. Dataverse did not expose package bytes for independent byte-for-byte server reconciliation; package identity/topology, not uploaded-byte equality, was verified.

### One-shot runtime result

Exactly one synthetic CreateCandidate was dispatched with the minimal request, one fresh correlation ID, and a reserved `.invalid` email. The runner made one Custom API invocation, performed no automatic retry, and stopped immediately at `CC_CREATE_CANDIDATE` with the exact guard rejection above. The subsequent GET-only reconciliation confirmed Candidate / Call Log / Status History / Operation Receipt counts of **0 / 0 / 0 / 0**. The one-shot lock and sanitized local evidence journal are retained.

No RecordCall, replay, Answered transition, Waiting Manual Scheduling transition, direct-write canary, second CreateCandidate, or further package update was attempted. The MVP backend workflow therefore remains unaccepted; no result should be inferred for call/history behavior from offline tests.

### UI fallback disposition

The owner-requested DEV-flow fallback was not created or deployed. A flow's direct Candidate/Call/History writes would still enter `ProtectCandidateCore` without the required trusted `os_sr_cact` ancestor, while invoking `os_sr_cact` is blocked by the same runtime failure. No guard exception or direct-write bypass was introduced. Read-only inspection listed 34 cloud flows; no name or description matched Candidate, Record Call, Status History, DEV/TEMP, BSO-RS, or `os_sr`. This does not rule out a relevant flow under another name. The available Power Platform tooling exposed flow listing but no supported flow-creation operation. No `srapp` navigation, page, form, command, or publication change was made; no generated custom pages were found for `srapp`. The first-visible vertical-slice criterion is unmet; see [Candidate UI implementation note](CANDIDATE_UI_IMPLEMENTATION_NOTE.md).

### Local validation

| Gate | Result |
|---|---|
| Candidate Core engine harness | PASS, 141 assertions |
| SDK adapter/guard harness | PASS, 303 assertions |
| PowerShell suites | PASS, all 12 suites |
| PowerShell script parsing | PASS, all 11 scripts |
| Unsigned package build | PASS, 0 warnings and 0 errors |
| Unsigned package validation | PASS, 12 assertions |
| `git diff --check` | PASS |

No browser/app acceptance, published UI, DEV flow, or visible Candidate workflow is claimed.

## Historical R4O Server-Registration Classifier: Deployment and Runtime Rejection

**Final result for this bounded R4O run:** the registration-backed package was updated once and reconciled, but the single CreateCandidate was rejected with `DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_GUARD_REGISTRATION:CC_CREATE_CANDIDATE:0x80040265`. Runtime acceptance and the matrix were not reached. The prior `OTHER_PROTECTED_WRITE` CreateCandidate result proved the runtime-shape classifier inadequate. Static source reconciliation already showed that Candidate Create and Receipt Create were in the exact ActionType/write allowlist; that allowlist was not broadened. The new safe category does not identify which internal registration metadata check failed; the stop rule was applied without further repair, deployment, or invocation.

`ProtectCandidateCore` now derives a table-bound protected write from the current guard execution context's server-owned `OwningExtension`, which must reference an active `sdkmessageprocessingstep`. The read-only metadata chain must resolve the exact `os_sr_cact.ProtectCandidateCore` PlugInType, assembly `os_sr_cact` v1.0.0.0, existing package `os_sr_cact_pkg` v1.0.0, SDK message, and matching SDK message filter. Only the six exact pairs listed below receive canonical WriteCodes. Associate/Disassociate registrations are handled by the existing relationship guard. Other exact but unsupported message/entity pairs fail closed as `UNSUPPORTED_GUARD_REGISTRATION`. Where runtime `MessageName` or `PrimaryEntityName` is populated, it is only a consistency check; disagreement fails closed as `GUARD_REGISTRATION_CONTEXT_MISMATCH`. No registration ID, payload shape, Target, or request CLR type selects a protected write. The verified API ancestor/action trust model remains a separate required authorization check and was not weakened.

The positive guard-registration cache is process-local, capped at 128 entries, expires after one minute, and is keyed by organization, calling user, and current OwningExtension ID. Negative results are not cached; each uncached or expired decision revalidates the metadata chain. Cache persistence is not required for correctness.

### Live 50-step registration inventory

Fresh GET-only preflight resolved 50/50 package-backed `ProtectCandidateCore` registrations: six canonical protected-write mappings, 42 exact unsupported registrations (fail-closed), two relationship guards, zero unresolved rows, and zero contradictory mappings. The two relationship registrations have no table filter. Empty WriteCode cells below are intentionally unsupported/relationship entries, not missing inventory data.

| Step name | SDK message | `primaryobjecttypecode` | Canonical WriteCode |
|---|---|---|---|
| `os_sr_cact.guard.os_sr_call.Assign` | Assign | `os_sr_call` | — |
| `os_sr_cact.guard.os_sr_call.Create` | Create | `os_sr_call` | `CALL_LOG_CREATE` |
| `os_sr_cact.guard.os_sr_call.CreateMultiple` | CreateMultiple | `os_sr_call` | — |
| `os_sr_cact.guard.os_sr_call.Delete` | Delete | `os_sr_call` | — |
| `os_sr_cact.guard.os_sr_call.DeleteMultiple` | DeleteMultiple | `os_sr_call` | — |
| `os_sr_cact.guard.os_sr_call.GrantAccess` | GrantAccess | `os_sr_call` | — |
| `os_sr_cact.guard.os_sr_call.ModifyAccess` | ModifyAccess | `os_sr_call` | — |
| `os_sr_cact.guard.os_sr_call.RevokeAccess` | RevokeAccess | `os_sr_call` | — |
| `os_sr_cact.guard.os_sr_call.SetState` | SetState | `os_sr_call` | — |
| `os_sr_cact.guard.os_sr_call.SetStateDynamicEntity` | SetStateDynamicEntity | `os_sr_call` | — |
| `os_sr_cact.guard.os_sr_call.Update` | Update | `os_sr_call` | — |
| `os_sr_cact.guard.os_sr_call.UpdateMultiple` | UpdateMultiple | `os_sr_call` | — |
| `os_sr_cact.guard.os_sr_cand.Assign` | Assign | `os_sr_cand` | — |
| `os_sr_cact.guard.os_sr_cand.Create` | Create | `os_sr_cand` | `CANDIDATE_CREATE` |
| `os_sr_cact.guard.os_sr_cand.CreateMultiple` | CreateMultiple | `os_sr_cand` | — |
| `os_sr_cact.guard.os_sr_cand.Delete` | Delete | `os_sr_cand` | — |
| `os_sr_cact.guard.os_sr_cand.DeleteMultiple` | DeleteMultiple | `os_sr_cand` | — |
| `os_sr_cact.guard.os_sr_cand.GrantAccess` | GrantAccess | `os_sr_cand` | — |
| `os_sr_cact.guard.os_sr_cand.ModifyAccess` | ModifyAccess | `os_sr_cand` | — |
| `os_sr_cact.guard.os_sr_cand.RevokeAccess` | RevokeAccess | `os_sr_cand` | — |
| `os_sr_cact.guard.os_sr_cand.SetState` | SetState | `os_sr_cand` | — |
| `os_sr_cact.guard.os_sr_cand.SetStateDynamicEntity` | SetStateDynamicEntity | `os_sr_cand` | — |
| `os_sr_cact.guard.os_sr_cand.Update` | Update | `os_sr_cand` | `CANDIDATE_UPDATE` |
| `os_sr_cact.guard.os_sr_cand.UpdateMultiple` | UpdateMultiple | `os_sr_cand` | — |
| `os_sr_cact.guard.os_sr_csh.Assign` | Assign | `os_sr_csh` | — |
| `os_sr_cact.guard.os_sr_csh.Create` | Create | `os_sr_csh` | `STATUS_HISTORY_CREATE` |
| `os_sr_cact.guard.os_sr_csh.CreateMultiple` | CreateMultiple | `os_sr_csh` | — |
| `os_sr_cact.guard.os_sr_csh.Delete` | Delete | `os_sr_csh` | — |
| `os_sr_cact.guard.os_sr_csh.DeleteMultiple` | DeleteMultiple | `os_sr_csh` | — |
| `os_sr_cact.guard.os_sr_csh.GrantAccess` | GrantAccess | `os_sr_csh` | — |
| `os_sr_cact.guard.os_sr_csh.ModifyAccess` | ModifyAccess | `os_sr_csh` | — |
| `os_sr_cact.guard.os_sr_csh.RevokeAccess` | RevokeAccess | `os_sr_csh` | — |
| `os_sr_cact.guard.os_sr_csh.SetState` | SetState | `os_sr_csh` | — |
| `os_sr_cact.guard.os_sr_csh.SetStateDynamicEntity` | SetStateDynamicEntity | `os_sr_csh` | — |
| `os_sr_cact.guard.os_sr_csh.Update` | Update | `os_sr_csh` | — |
| `os_sr_cact.guard.os_sr_csh.UpdateMultiple` | UpdateMultiple | `os_sr_csh` | — |
| `os_sr_cact.guard.os_sr_oprc.Assign` | Assign | `os_sr_oprc` | — |
| `os_sr_cact.guard.os_sr_oprc.Create` | Create | `os_sr_oprc` | `RECEIPT_CREATE` |
| `os_sr_cact.guard.os_sr_oprc.CreateMultiple` | CreateMultiple | `os_sr_oprc` | — |
| `os_sr_cact.guard.os_sr_oprc.Delete` | Delete | `os_sr_oprc` | — |
| `os_sr_cact.guard.os_sr_oprc.DeleteMultiple` | DeleteMultiple | `os_sr_oprc` | — |
| `os_sr_cact.guard.os_sr_oprc.GrantAccess` | GrantAccess | `os_sr_oprc` | — |
| `os_sr_cact.guard.os_sr_oprc.ModifyAccess` | ModifyAccess | `os_sr_oprc` | — |
| `os_sr_cact.guard.os_sr_oprc.RevokeAccess` | RevokeAccess | `os_sr_oprc` | — |
| `os_sr_cact.guard.os_sr_oprc.SetState` | SetState | `os_sr_oprc` | — |
| `os_sr_cact.guard.os_sr_oprc.SetStateDynamicEntity` | SetStateDynamicEntity | `os_sr_oprc` | — |
| `os_sr_cact.guard.os_sr_oprc.Update` | Update | `os_sr_oprc` | `RECEIPT_UPDATE` |
| `os_sr_cact.guard.os_sr_oprc.UpdateMultiple` | UpdateMultiple | `os_sr_oprc` | — |
| `os_sr_cact.guard.relationships.Associate` | Associate | — | — |
| `os_sr_cact.guard.relationships.Disassociate` | Disassociate | — | — |

Pre-deployment normalized inventory SHA-256: `070a6be1d49d3d0d831df757d470024a37283312749e8b19a1a5615b7ecc7480` (UTF-8 lines sorted by step name as `step|message|entity|writecode`, blank cells preserved, terminal LF).

### Local gates and artifact before deployment

| Gate | Result |
|---|---|
| Candidate Core engine harness | PASS, 141 assertions |
| SDK adapter/guard harness | PASS, 335 assertions; includes registration-backed canonical-pair tests, fail-closed registration cases, context cross-checks, marker-independent trusted Candidate/Receipt creates, and direct-write negatives |
| PowerShell suites | PASS, all 12 suites / 1,143 assertions |
| PowerShell parsing | PASS, all 11 scripts under `scripts/` |
| Unsigned package | Rebuilt and validated; `os_sr_cact_pkg` 1.0.0 / `os_sr_cact` 1.0.0.0; no signing key |
| DLL SHA-256 | `cda68cd70897d0353650f4f0e0cf34387bbe6b5b0d79892a49a70692dd1740ef` |
| Package SHA-256 | `8c98e022caf19eda2d7709803c4b0f4dafdfb78a05985223c5eac0bf51cd6c2c` |

The fresh GET-only pre-deployment preflight returned `PHASE_3D_RUNTIME_PREFLIGHT_READY`: VN LMV IT / PAC-WhoAmI agreement; one existing package-backed API handler and guard; unchanged API contract and Candidate Core schema; Active Receipt key; trace setting 0 (Off); zero active Candidate Core Profiler wrappers; 50 package-backed guard registrations and the inventory above; and Candidate / Call / History / Receipt counts 0/0/0/0. It dispatched zero Custom API calls and performed zero writes.

### Existing-package update and one CreateCandidate result

| Gate or operation | Verified result |
|---|---|
| Local package submitted | `os_sr_cact_pkg` 1.0.0, unsigned; DLL SHA-256 `cda68cd70897d0353650f4f0e0cf34387bbe6b5b0d79892a49a70692dd1740ef`; `.nupkg` SHA-256 `8c98e022caf19eda2d7709803c4b0f4dafdfb78a05985223c5eac0bf51cd6c2c` |
| Package update | Exactly one PAC CLI `pac plugin push` targeting the existing package; command exit code 0; retries 0; no package creation |
| Immediate read-only reconciliation | Same existing package identity/version, package `modifiedon` advanced, package-backed handler/guard and 50-step topology intact; all 50 registration classifications resolved; API contract/schema/Receipt key unchanged; trace Off; no active Candidate Core Profiler wrappers |
| Package content bytes | Dataverse GET did not expose a content hash; local hashes identify the submitted artifact, not independently verified deployed bytes |
| CreateCandidate | Exactly one dispatch, synthetic `[SYNTHETIC-E2E]` name and `.invalid` email, no optional inputs; HTTP 400 / `0x80040265` |
| Exact safe result | `DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_GUARD_REGISTRATION:CC_CREATE_CANDIDATE:0x80040265` |
| Runtime evidence | `CREATECANDIDATE_RUNTIME_FAILURE`; dispatch state `REJECTED`; candidate ID not captured; automatic retries 0 |
| Post-call counts | Not re-queried after the failure stop. The last verified counts were the fresh pre-deployment 0/0/0/0; do not infer post-call counts from that earlier read |
| Runtime matrix / live direct-write canary | Not run. No safe existing live direct-write canary was available; no canary was improvised |
| Final classification | `CREATECANDIDATE_RUNTIME_FAILURE` / `UNSUPPORTED_GUARD_REGISTRATION`; no runtime acceptance or Phase 3D completion claim |

No second package update, second CreateCandidate, matrix call, trace-setting change, Profiler action, registration/handler PATCH, schema/API/security/app/publication/audit-setting change, legacy signed assembly update, signing-key access, commit, or push occurred. No further backend diagnostic is authorized by this result in the current run.

## Prior R4O Static Write-Context Reconciliation (2026-10-26; superseded by classifier result above)

**Historical classification: `CANDIDATE_CORE_WRITE_CONTEXT_FAILURE_UNRESOLVED`.** The single diagnostic CreateCandidate returned `UNSUPPORTED_CORE_WRITE_CONTEXT:CREATE_CANDIDATE:OTHER_PROTECTED_WRITE` during `CC_CREATE_CANDIDATE`. This did not identify an exact supported table/message pair or prove an allowlist correction. The later R4O implementation and runtime result are reported above.

**Pre-deployment finding: no unique failing CreateCandidate pair is statically proven.** The earlier R4O `UNSUPPORTED_CORE_WRITE_CONTEXT` is the baseline. This continuation uses safe action/write localization, not a new readiness phase and not a return to marker diagnosis. The attachment both describes a possible second diagnostic-branch package update and states a maximum of one; the stricter one-update ceiling is applied. No second speculative repair is authorized by this interpretation.

### Canonical source-derived contract

All allowed cells below still require the full verified package-backed API ancestor/OwningExtension, synchronous transaction, depth and caller contract. `RecordCall` cells describe its supported outcome-dependent union, not unconditional execution of every write.

| ActionType | Candidate Create | Candidate Update | Call Log Create | History Create | Receipt Create | Receipt Update / Upsert / other protected mutation |
|---|---|---|---|---|---|---|
| CreateCandidate | Allow | Deny | Deny | Deny | Allow | Deny |
| UpdateCandidate | Deny | Allow | Deny | Deny | Allow | Deny |
| RecordCall | Deny | Allow when Answered changes status | Allow | Allow when Answered changes status | Allow | Deny |
| ProceedToScheduling | Deny | Allow | Deny | Allow | Allow | Deny |
| MarkRound1Scheduled | Deny | Deny | Deny | Deny | Deny | Deny |
| RecordPass | Deny | Deny | Deny | Deny | Deny | Deny |
| RecordFail | Deny | Deny | Deny | Deny | Deny | Deny |
| RequestReschedule | Deny | Deny | Deny | Deny | Deny | Deny |

Source locations: [CandidateOperation.Execute and Transition](../solutions/CandidateCore/Operation.cs) determine reachability; [DataverseStore](../solutions/CandidateCore/DataversePlugin.cs) maps business effects to SDK calls, `ProtectCandidateCore.RegisteredWriteCode` maps only the exact server-owned registration pairs, and the action/write authorization remains a separate exact check.

| Action / branch | Exact successful first-execution sequence after transaction validation |
|---|---|
| CreateCandidate | Receipt lookup (read) -> Candidate Create -> Receipt Create |
| UpdateCandidate | Receipt lookup -> Candidate read/version/status checks -> Candidate Update -> Receipt Create |
| RecordCall: No Answer / Call Back Requested | Receipt lookup -> Candidate read/version/status checks -> Call Log Create -> Receipt Create |
| RecordCall: Answered | Receipt lookup -> Candidate read/version/status checks -> Candidate Update -> Call Log Create -> History Create -> Receipt Create |
| ProceedToScheduling | Receipt lookup -> Candidate read/version/status checks -> Candidate Update -> History Create -> Receipt Create |
| MarkRound1Scheduled | Receipt lookup -> Candidate read/checks -> fail closed before any write: missing scheduler evidence |
| RecordPass / RecordFail / RequestReschedule | Receipt lookup -> Candidate read/checks -> fail closed before any write: missing result/cancellation evidence (or invalid current status) |

`Transition` has a future-evidence test parameter, but production `Execute` does not supply true; future transitions are not reachable production writes. Candidate updates use `IOrganizationService.Execute(UpdateRequest)` with `IfRowVersionMatches`; the protected message is Update. All four table creates use `IOrganizationService.Create`. There is no receipt Update, Upsert, Execute persistence or other receipt write path. Reads are not business-write allowlist entries.

Receipt semantics: first successful execution creates one receipt after its business effects; identical replay finds the receipt, verifies actor/action/fingerprint/version/target, reads Candidate and returns stored evidence without writes. Conflicting replay rejects before mutation. Operation failure does not persist a successful receipt; failed-transaction rollback is separately simulated offline and is not inferred as live acceptance.

### Static comparison and bounded changes

| CreateCandidate reachable protected write | Existing R4O guard compatibility | Source |
|---|---|---|
| `CANDIDATE_CREATE` | Already allowed | `SafeOperation(Create, os_sr_cand)`; `IsActionForOperation` CreateCandidate branch |
| `RECEIPT_CREATE` | Already allowed | `SafeOperation(Create, os_sr_oprc)`; existing receipt branch |

`UNSUPPORTED_CORE_WRITE_CONTEXT` is emitted before ancestor trust checks when SafeOperation/message/table classification is unsupported. Neither required CreateCandidate pair is absent or misclassified in static source. Therefore **`STATIC_GUARD_WRITE_CONTEXT_DEFECT_PROVEN` is not claimed for the live CreateCandidate failure**.

The full eight-action comparison did expose one overbroad cell group: Receipt Create previously accepted any supported action, including all four fail-closed future actions. That branch is narrowed to the four current write-capable actions. It does not explain or fix the CreateCandidate failure, and does not broaden any allowlist.

The diagnostic build adds only closed action/write codes to unsupported-write rejection: `UNSUPPORTED_CORE_WRITE_CONTEXT:<ACTION_CODE>:<WRITE_CODE>`. The action is a bounded ancestor label for diagnosis, not proof of trusted registration; unknown values map to `UNKNOWN_ACTION`. Only the five current protected write codes, `RECEIPT_UPDATE` and `OTHER_PROTECTED_WRITE` are exposed. No arbitrary message/table strings, values, record IDs, actors, markers or payloads are returned. Safe diagnostic propagation is wired through service-stage wrapping and runtime reporting.

The canonical SDK matrix tests every supported ActionType against all five valid mutation categories, both allowing exact reachable pairs and rejecting all other pairs; it also rejects direct writes, Receipt Update/Upsert, Candidate Delete and Call/History Update. The engine harness separately verifies actual read/write order, every replay/conflict path and all four fail-closed operations. Existing direct-write/registration/R4J/idempotency/service-stage tests remain.

### Bounded live diagnostic result

| Gate or operation | Verified result for this R4O continuation |
|---|---|
| Identity | VN LMV IT; fresh PAC and WhoAmI agreement |
| Storage/API | Exact Candidate Core schema/Choices/relationships; Active Receipt key; unchanged 13 inputs/five outputs |
| Existing package | One `os_sr_cact_pkg` v1.0.0; unchanged package/assembly/type identities; package-backed handler and guard |
| Guard registration | 50/50 package-backed; retained protected-property fingerprints/configuration/message/filter/impersonation/secure-reference properties exact before and after update |
| Trace setting / active Candidate Core Profiler wrappers | 0 (Off) / 0; no setting change or Profiler activity |
| Diagnostic package updates | 1, HTTP 204; immediate topology reconciliation passed |
| Package disposition | `PACKAGE_UPDATE_ACCEPTED_CONTENT_NOT_BYTE_RECONCILABLE`; ordinary GET is not deployed-byte evidence |
| Diagnostic CreateCandidate / total API dispatches | 1 / 1, minimal four-input synthetic request, no optional inputs |
| Runtime response | HTTP 400 / `0x80040265` |
| Exact safe diagnostic | `DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_CORE_WRITE_CONTEXT:CREATE_CANDIDATE:OTHER_PROTECTED_WRITE:CC_CREATE_CANDIDATE:0x80040265` |
| Automatic retries | 0 |
| Pre/post/final Candidate / Call Log / History / Receipt | 0/0/0/0 -> 0/0/0/0 -> 0/0/0/0 |
| Corrected acceptance / runtime matrix | Not reached; diagnostic did not prove a deterministic failing pair |
| Direct-write live canary | Not executed; no existing safe runner and no successful matrix; SDK negatives retained |
| Final read-only reconciliation | Same package-backed handler/types, unchanged API, 50 package-backed guards, trace Off, no active Candidate Core Profiler wrappers, zero counts |

The action label is derived from a bounded ancestor for diagnosis, not registration trust. `OTHER_PROTECTED_WRITE` means the rejected context's message/primary-entity combination was not one of the five currently supported protected write categories or Receipt Update. It does not expose which message/entity it was. The diagnostic is thrown before ancestor verification, so this result does not prove that OwningExtension checks passed or failed. It does not support changing marker, ParentContext, identities or the exact business-write allowlist. No such change followed the diagnostic.

### R4O artifact and validation evidence

Local SHA-256 of the uploaded diagnostic input:

- DLL: `45c15f8b825e167fc8a1e7031b34708af3ac34a3fef689dc5853cf35cd7abcdf`
- Package: `8617f313091ba6e51398b4b0abd19566f6486023595144bb7438f9ada1db996e`
- Inventory (`Sort-Object FullName`, `name|length|compressed-length` joined by LF): `5e19f514443bf7c03e7a67c70e3128b275ebeb263fd192db26856b74ab21532c`

Local gates passed: engine 141 assertions; SDK 326 assertions; all 12 PowerShell suites / 1,140 assertions; unsigned Rebuild and package validation; all 11 repository scripts and bounded R4O runner parsed; privacy/relative-link checks and `git diff --check`. Existing R4J input projection, verified ancestor registration/direct-write negatives, idempotency/receipt rollback and service-stage regressions remain in the suites. A new durable R4O continuation journal/runtime lock enforced the single dispatch; no consumed earlier authorization was reused.

No successful CreateCandidate, runtime matrix/write-context acceptance, Phase 3D completion or transition to Candidate UI/BSO Security is claimed. No second build/deployment/call, trace-setting write, Profiler activity, new package, schema/Choice/API/security/app/audit/publication change, handler/guard-step PATCH, legacy signed assembly update, signing-key access, commit or push occurred in this continuation.

## Earlier Verified Server-Owned Ancestor Acceptance Attempt (2026-10-26)

**`CANDIDATE_CORE_TRUST_MODEL_FAILURE:UNSUPPORTED_CORE_WRITE_CONTEXT`.** The owner explicitly approved replacing required SharedVariables marker authorization with the verified server-owned API ancestor model. The preceding R4M diagnostic proved `MARKER_MISSING`; it did not prove the transport mechanism. The owner-approved architecture decision supersedes the old marker requirement without claiming that mechanism was diagnosed.

### Implemented trust contract

[ProtectCandidateCore](../solutions/CandidateCore/DataversePlugin.cs) retains the bounded eight-ancestor search, expected `os_sr_cact` message/stage 30/synchronous transaction, positive lower depth, matching calling/initiating users, supported ActionType and operation-specific table/message compatibility. It now requires server-owned `OwningExtension` of logical type `sdkmessageprocessingstep`. Calling-user read-only resolution follows `eventhandler` -> exact `os_sr_cact.ApplyCandidateAction` PlugInType -> `os_sr_cact` assembly v1.0.0.0 -> existing `os_sr_cact_pkg` package v1.0.0. The live assembly-to-package attribute was separately verified as `packageid`. No registration IDs are hard-coded.

Closed failure categories cover missing/wrong extension, handler type, assembly/package mismatch and unreadable registration. A registration service fault stops traversal immediately, without another service call in a potentially failed transaction. Positive validation is cached for at most one minute by organization/calling user/server-owned extension ID, locked and capped at 128 entries; negative decisions are not cached. Cache expiry or process restart requires a fresh chain read. No service-user elevation or privilege grant is used.

The private marker is retained solely as non-authoritative, nonpersisted evidence. Its absence, type or fingerprint does not authorize or reject writes. Caller tags, input parameters and entity attributes cannot substitute for the server-owned registration. Removal of exact child-payload fingerprint authorization is intentional under the new approved boundary; API engine validation/idempotency and operation-specific ancestry remain required. Receipts remain append-only: operations create receipts and replay reads them; no receipt-update path was introduced.

**Legacy handler rollback also requires matching guard rollback.** The signed legacy assembly was not changed and is not accepted merely for matching a type/name. ParentContext remains subject to [Microsoft's platform-fragility caveat](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/understand-the-data-context#parentcontext); tests and live reconciliation must be repeated after relevant platform/package changes. The model is detailed in the [Security Model](SECURITY_MODEL.md) and [Architecture](ARCHITECTURE.md).

### Live execution evidence

| Gate or operation | Verified result for this authorization |
|---|---|
| Identity | VN LMV IT; fresh PAC/WhoAmI agreement |
| Schema/API | Exact Candidate Core storage/Choice/relationship reconciliation; Receipt alternate key Active; unchanged 13 inputs/five outputs |
| Package and types | One existing unsigned `os_sr_cact_pkg` v1.0.0; unchanged assembly/type identities; package-backed ApplyCandidateAction and ProtectCandidateCore |
| Guard topology | All 50 package-backed; protected registration fingerprints/configuration/message/filter/impersonation/secure-reference checks exact before and after update |
| Trace setting / active Candidate Core Profiler wrappers | 0 (Off) / 0; unchanged, no Profiler activity |
| Existing-package updates | Exactly 1, HTTP 204; immediate package/type/API/guard topology reconciliation passed |
| Package disposition | `PACKAGE_UPDATE_ACCEPTED_CONTENT_NOT_BYTE_RECONCILABLE`; no deployed-byte equivalence claim |
| CreateCandidate / all Custom API dispatches | 1 / 1; minimal four-input synthetic request, no optional fields |
| Runtime result | HTTP 400 / `0x80040265` |
| Exact safe returned guard category | `DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_CORE_WRITE_CONTEXT:CC_CREATE_CANDIDATE:0x80040265` |
| Automatic retries | 0 |
| Pre/post/final Candidate / Call Log / History / Receipt | 0/0/0/0 -> 0/0/0/0 -> 0/0/0/0 |
| Matrix | Not entered; CreateCandidate failed |
| Live direct-write canary | Not executed; no existing safe negative runner found, and success prerequisite was not met |
| Final read-only reconciliation | Package-backed handler/types and all 50 guards exact; API unchanged; trace Off; no active Candidate Core Profiler wrappers |

The returned category does not identify which nested execution produced an unsupported protected-write context. It does not establish that OwningExtension verification succeeded or failed. No trace content was captured, no additional business call was issued, and no speculative cause is claimed. Per the stop rule, no second source/package repair or backend diagnostic was opened.

The runtime journal retained the sanitized HTTP/guard error, but the dispatch's parsed ResultCode was null because the older parser did not recognize the generic unsupported-core-write category. The local reporting parser was then extended and regression-tested to preserve that closed category. This was a reporting-only correction: no package rebuild/update or runtime replay followed. A local GET-only final-reconciliation adapter initially failed from PowerShell dynamic variable shadowing; that local adapter was corrected and the read-only reconciliation completed. Neither issue caused an additional tenant write or business dispatch.

### Artifact and validation evidence

Local SHA-256 hashes of the uploaded input:

- DLL: `dcae627458b081e162ec49bc20632a7a185d08f563dca887954bb69aedf944df`
- NuGet package: `d0c328c0b69d586e9952a0a2a1483a45ad345b3c0c4e0989285639194858e655`
- Inventory (`Sort-Object FullName`, `name|length|compressed-length` lines joined by LF): `bd0a8a423494cb1efe9e0c46399ece92346615636a6025df2e3cae8b8fd5d990`

Local gates passed: Candidate engine 109 assertions; SDK adapter/guard 202 assertions (including direct negatives, verified registration, missing-marker positive, cache reuse/expiry, uncached negatives, legacy rejection, R4J projection and R4K service-stage regressions); unsigned Rebuild/package validation; all 12 PowerShell suites, 1,138 assertions; all 11 repository scripts parsed; added-line privacy scan, 221 relative links across eight affected guidance/status documents and `git diff --check`. The final PowerShell suite count includes the post-call reporting-parser regression; it was not deployed plug-in code. The uploaded package input hash was rechecked unchanged after final validation.

**Phase 3D remains incomplete.** None of `CANDIDATE_CORE_RUNTIME_ACCEPTED_AUDIT_ACTIVATION_PENDING`, `PHASE_3D_COMPLETE_FOR_CURRENT_CANDIDATE_CORE_SCOPE`, or live-verified `DIRECT_WRITE_GUARD_TRUST_MODEL = VERIFIED_API_ANCESTOR` is earned. The package-backed topology remains active, but successful business runtime acceptance is not proven. Candidate UI/BSO Security is not automatically started.

No second update/call, trace-setting write, Profiler operation, new PluginPackage, schema/Choice/API/security/app/audit/publication change, handler/guard-step PATCH, signed legacy assembly update, signing-key access, commit or push was performed by the assistant.

## Earlier R4M Fast-Track Predicate Localization (2026-10-26)

**Classification: `CANDIDATE_CORE_GUARD_FAILURE_LOCALIZED` - `MARKER_MISSING`.** Owner authorization covered a diagnostic-only source/test change, at most two existing unsigned package updates and two CreateCandidate attempts, with the second cycle conditional on a deterministic correction. This continuation remains R4M; the isolated R4N reference in the authorization was treated as a label inconsistency, not a new phase or additional allowance.

The earlier trace below established handler depth 1, Candidate Create guard depth 2, and `CC_GUARD_TRUSTED_PARENT_NOT_FOUND:ANCESTOR_HOPS:1`. It did not prove a failing predicate. The diagnostic build preserved the authorization conditions and now returns the first failed predicate on the nearest ancestor if no ancestor is trusted. It still searches all eight permitted ancestors before rejecting; an uninspected continuation produces `ANCESTOR_BOUND_EXCEEDED`. Per-ancestor traces contain only bounded hop numbers and closed predicate categories. No marker, fingerprint, identity, payload, or candidate value is emitted.

### Exact predicate map

The sequence in [ProtectCandidateCore](../solutions/CandidateCore/DataversePlugin.cs) is:

| Order | Ancestor condition | First-failure category |
|---|---|---|
| 1 | MessageName is `os_sr_cact` | `API_MESSAGE_MISMATCH` |
| 2 | Stage is 30 | `STAGE_MISMATCH` |
| 3 | Mode is 0 | `MODE_MISMATCH` |
| 4 | IsInTransaction is true | `TRANSACTION_MISMATCH` |
| 5 | Positive depth below child depth | `DEPTH_MISMATCH` |
| 6 | UserId equals child UserId | `USER_CONTEXT_MISMATCH` |
| 7 | InitiatingUserId equals child InitiatingUserId | `INITIATING_USER_MISMATCH` |
| 8 | ActionType is present and non-null | `ACTIONTYPE_MISSING` |
| 9 | ActionType is a supported string compatible with the protected write | `ACTIONTYPE_MISMATCH` |
| 10 | Ancestor SharedVariables contains the private intent key | `MARKER_MISSING` |
| 11 | Marker is a string | `MARKER_TYPE_MISMATCH` |
| 12 | Marker equals the canonical protected-mutation fingerprint | `MARKER_FINGERPRINT_MISMATCH` |

Existing child-context gates remain unchanged: unsupported write, invalid stage/mode/transaction/depth or no parent, caller identity mismatch, and missing/malformed Target still fail closed using their existing categories. The current context and caller `tag` are not trusted marker sources. No registration GUID is used as a trust predicate.

### Verified execution and limits

| Gate or operation | Result |
|---|---|
| Target | Owner-confirmed VN LMV IT; fresh PAC/WhoAmI agreement |
| Storage | Exact Candidate/Call/History/Receipt schema reconciliation; Receipt alternate key Active |
| API and package | Unchanged 13 inputs/five outputs; one existing `os_sr_cact_pkg` v1.0.0; unchanged package, assembly and type identities |
| Guards | All 50 package-backed; protected-property fingerprints, configuration hashes, message/filter, impersonation and secure-configuration references exact against retained rollback map |
| Trace setting / active Candidate Core Profiler wrappers | 0 (Off) / 0; no setting or Profiler changes |
| Diagnostic package updates | 1; HTTP 204; immediate post-update topology exact |
| Package disposition | `PACKAGE_UPDATE_ACCEPTED_CONTENT_NOT_BYTE_RECONCILABLE`; no unsupported deployed-byte/timestamp claim |
| Minimal synthetic CreateCandidate dispatches | 1; four required inputs only; no optional parameters |
| First runtime result | HTTP 400 / `0x80040265` |
| Exact safe diagnostic | `DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:TRUSTED_PARENT:MARKER_MISSING:CC_CREATE_CANDIDATE:0x80040265` |
| Pre/post Candidate / Call Log / Status History / Receipt | 0/0/0/0 -> 0/0/0/0 |
| Second package / second CreateCandidate / matrix | Not reached; no deterministic correction established |
| Automatic retries | 0 |
| Final read-only reconciliation | Exact storage/API/package/50-guard properties; trace Off; no active Candidate Core Profiler wrappers; 0/0/0/0 |

Local diagnostic artifact SHA-256:

- DLL: `404667ac488564ea9c7929578f81f441d13c65ed35b320a99973347868a9a66c`
- NuGet package: `2e0fbee6e0f6ef24416ae5c1832ff1c2455e03a3d0acbb993dd031c4b85e3848`

### Proven localization versus unproven repair

The returned category proves that the inspected ancestor passed API message, stage, mode, transaction, depth, both actor comparisons, and operation-specific ActionType checks, but its SharedVariables did not contain the private intent key. Marker CLR type and fingerprint checks were not reached. The observed rejection is at marker presence, not at stage, identity or fingerprint validation; this does not prove that a later fingerprint check would pass after propagation is repaired.

Source inspection confirms `DataverseStore.Authorize` writes the string fingerprint to the handler's SharedVariables immediately before the protected service call, and removes it in `finally`. The organization service is constructed earlier in the handler. The local SDK harness uses a live context reference; it does not reproduce the platform's context serialization/handoff. Neither that ordering nor the absent marker proves when or how the live parent context was captured. In particular, changing service-construction timing would be a hypothesis, not a trace-proven correction.

[Microsoft's execution-context guidance](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/understand-the-data-context#shared-variables) documents SharedVariables between pipeline steps and specific ParentContext cases; it does not establish that this late handler mutation must appear in a nested Create ancestor. Its ParentContext guidance also warns against undocumented dependencies. Therefore no second speculative build, marker bypass, caller-tag authorization, identity relaxation, or semantic guard correction was made. The missing-marker SDK regression reproduces the observed rejection shape, not an asserted transport mechanism.

Runtime acceptance remains blocked. Phase 3D is not complete; the UI/security next-phase classification and runtime-accepted/audit-pending classification are not earned. No additional backend diagnostic was automatically opened.

### Local validation

- Engine harness: PASS, 109 assertions.
- SDK guard harness: PASS, 178 assertions, including all reachable predicate categories, no ancestor, traversal boundary, trusted ancestors, direct-write negatives, action-specific child writes, exact safe rejection messages, service-fault propagation, and R4J projection regressions.
- All 12 PowerShell suites: PASS, 1,134 assertions, including package validation.
- Unsigned package Rebuild: PASS, zero build warnings/errors; no signing-key access.
- All 11 repository scripts parsed; added-line privacy scan and `git diff --check` passed.
- Historical frozen deployment hash pins/consumed locks were not altered. The current bounded session runner used a distinct durable journal and the diagnostic package hash above; no old Apply authorization was reused.

No second update, second CreateCandidate, matrix action, trace-setting write, Profiler activity, new package, handler/guard PATCH, schema/Choice/API/security/app/audit/publication change, legacy signed assembly update, signing-key access, commit, or push occurred.

## Earlier R4M Temporary Exception Trace Diagnostic (2026-10-26)

**Classification: `R4M_TRACE_EVIDENCE_INSUFFICIENT`.** Explicit owner environment-level approval covered only the bounded Off (0) -> Exception (1) -> Off (0) trace window and one synthetic CreateCandidate, using the existing deployed package without Profiler.

| Gate or operation | Verified result |
|---|---|
| Target and identity | VN LMV IT; confirmed target URL and PAC/WhoAmI agreement |
| Package topology | Existing package-backed ApplyCandidateAction; all 50 ProtectCandidateCore guards package-backed |
| Active Candidate Core Profiler wrappers | 0 |
| Original trace setting | 0, retained locally before enable |
| Enable writes / enabled readback | 1 / 1 |
| CreateCandidate dispatches / automatic retries | 1 / 0 |
| Request | Approved minimal synthetic trace-capture contract; no optional parameters |
| Response | HTTP 400 / `0x80040265` |
| Pre-counts: Candidate / Call Log / Status History / Receipt | 0 / 0 / 0 / 0 |
| Immediate post-counts | 0 / 0 / 0 / 0 |
| Restore writes / final readback | 1 / 0 (Off), reconciled in `finally` |
| Trace rows inspected | 2 in a bounded GET-only follow-up after restoration; immediate query returned 0 |

The follow-up included assembly-qualified type-name matching and remained limited to the two Candidate Core types and the diagnostic window. Only sanitized structural markers were retained:

| TypeName | MessageName | Depth | Mode | Safe markers |
|---|---|---|---|---|
| `os_sr_cact.ProtectCandidateCore` | `Create` | 2 | 0 | `CC_GUARD_TRUSTED_PARENT_NOT_FOUND:ANCESTOR_HOPS:1` |
| `os_sr_cact.ApplyCandidateAction` | `os_sr_cact` | 1 | 0 | `CC_STAGE:CC_READ_RECEIPT`; `CC_STAGE:CC_CREATE_CANDIDATE`; `CC_SERVICE_FAULT:CC_CREATE_CANDIDATE:0x80040265` |

This establishes that package-backed execution emitted the expected R4M trusted-parent-search trace, searched one ancestor, and found no accepted trusted parent. It does not prove which conjunct failed: private marker visibility, ancestor message/stage/mode/transaction/depth/actor semantics, operation trust, or fingerprint equality. No actual ancestor tree or marker-present boolean was traced. Therefore `MARKER_NOT_VISIBLE_IN_ANCESTOR_CHAIN`, `TRUSTED_API_ANCESTOR_SHAPE_MISMATCH`, and `MARKER_FINGERPRINT_MISMATCH` remain unproven. Missing R4M trace emission is not the observed issue.

No source correction or trace-derived regression was justified; no rebuild, package validation, or repair test suite was run. Documentation-only validation is reported separately. No further runtime call, Profiler operation, package update/deployment, handler/guard PATCH, schema/API/security/app/audit/publication change, legacy assembly change, signing-key access, commit, or push occurred. The package disposition remains `PACKAGE_UPDATE_ACCEPTED_CONTENT_NOT_BYTE_RECONCILABLE`; no new backend phase was created.

## Phase 3D-R4M Package Update and Earlier Caller-Marker Runtime Failure

### Historical execution-context capture installation gate

The installation-attempt status below is historical. Subsequent live checks verified the installed Profiler type and owner-configured wrappers; cleanup later verified zero active Candidate Core Profiler wrappers and the original Candidate Create guard protected-property fingerprint and package-backed handler exact. Profiler was not uninstalled. The latest trace diagnostic above used no Profiler.

**Subsequent R4M-P installation authorization and result:** the owner explicitly approved installing Microsoft Plug-in Profiler in VN LMV IT. PAC target verification passed. PRT 9.1.0.235 was launched, but this session has no desktop UI control for Install Profiler. One PAC import was attempted using the untouched managed `PluginProfiler` 2.0.0.0 Solution (publisher `mbs`) extracted from the official PRT cabinet. No publication, overwrite, dependency-bypass, or plug-in activation flags were supplied. Dataverse rejected the import with `PluginProfiler.Plugins cannot be installed this way. Please use a microsoft signed solution file to install a microsoft signed assembly`. No signing bypass, altered package, or repeated import was attempted.

Fresh post-error queries returned no `PluginProfiler` Solution and no assembly whose name contained `profiler`. Current installation disposition: `PLUGIN_PROFILER_INSTALLATION_FAILED_MICROSOFT_SIGNED_SOLUTION_REQUIRED`, not missing owner approval. The supported PRT UI installation remains pending under the existing approval. Diagnostic calls and invocation retries remain 0; no profiling, context capture, Candidate Core package update, handler/guard change, source correction, signing-key access, commit, or push occurred. Business counts were not re-counted. The following missing-approval gate is historical.

On 26 October 2026, the owner separately authorized one diagnostic synthetic invocation only after Microsoft Plug-in Profiler was confirmed installed and active on the exact package-backed Candidate Create guard step. The fresh PAC identity check matched the confirmed VN LMV IT target. Read-only FetchXML queries against that explicit target returned:

| Installation evidence | Result |
|---|---|
| Solution unique name or display name contains `profiler` | No results |
| PluginAssembly name contains `profiler` | No results |

Disposition: `PLUGIN_PROFILER_NOT_INSTALLED_REQUIRES_ENVIRONMENT_APPROVAL`. No installation or solution import was attempted. Profiling was not started, no step was changed, and no restoration was required. Diagnostic runtime calls: 0; invocation retries: 0. No raw profile exists from this continuation; no execution-context tree, marker location, or exact live predicate defect is proven. SDK reproduction, source correction, rebuild, and repair validation were not reached. Installation requires separate environment approval; the diagnostic invocation remains unused and gated on Profiler availability.

No package update, handler/guard PATCH, schema/API/security/audit/app/publication/legacy assembly change, signing-key access, commit, or push occurred. The prior 0/0/0/0 business/evidence counts below remain the last verified counts; this installation-gate check did not re-count them. Existing R4M acceptance and package-update authorizations remain consumed. No new backend implementation phase was created.

**Runtime classification: `PACKAGE_GUARD_PARENT_CONTEXT_FAILURE`. Package disposition: `PACKAGE_UPDATE_ACCEPTED_CONTENT_NOT_BYTE_RECONCILABLE`.** The earlier audit stop was `STALE_AUDIT_GOVERNANCE_GATE`, not a valid runtime blocker. Owner direction permits bounded synthetic Candidate Core runtime acceptance while organization auditing is disabled and unchanged. Audit activation remains an external governance/release prerequisite before real candidate rollout; no real candidate data, CV, phone, production email, or real-person reference data is permitted.

Fresh pre-deployment reconciliation verified the confirmed VN LMV IT target and identity, the existing `os_sr_cact_pkg`, package-backed assembly/types and handler topology, all 50 package-backed Candidate Core guards, unchanged Custom API contract, exact Candidate Core schema, Active Operation Receipt key, and 0 Candidate / 0 Call Log / 0 Status History / 0 Receipt rows. The R4M local unsigned artifact passed its existing identity/type/hash checks. The recorded local hashes identify the submitted artifact, not live content.

The existing package was updated exactly once by a PATCH of its content; the service returned HTTP 204. No package was created, and no handler/guard PATCH or legacy assembly update occurred. GET reconciliation retained the same package identity, unique name, version, package-backed handler/types, unchanged API contract, and all 50 package-backed guard mappings. Standard GET did not return `pluginpackage.content` or package assembly bytes. The prior read showed package `modifiedon` advanced to `2026-10-26T08:45:32Z`, while assembly `modifiedon` remained `2026-10-25T08:37:19Z`; that timestamp difference is informational, not a failure predicate.

Under the supported Dataverse plug-in package model, uploaded NuGet content resides on `PluginPackage`, while related `PluginAssembly` rows are managed by Dataverse. Ordinary GET need not make uploaded bytes readable, and `PluginAssembly.modifiedon` need not advance for every package update. The HTTP 204 plus exact package identity/version/topology is accepted package-update evidence, not an uncertain write or deployment failure. Exact deployed-byte equivalence remains unavailable; `SourceHash` was not queried and no local-hash mapping is asserted.

The distinct R4M runtime authorization was consumed by exactly one synthetic CreateCandidate request containing ActionType, a fresh CorrelationId, CandidateName `[SYNTHETIC-E2E] Candidate Core Acceptance`, and a reserved `.invalid` CandidateEmail, with no optional parameters. It returned HTTP 400 / `0x80040265` / `DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:CALLER_MARKER:CC_CREATE_CANDIDATE:0x80040265`, exactly matching the historical R4L diagnostic and without R4M-specific parent-context evidence. Automatic retries: 0. The runtime runner stopped before the matrix. Fresh GET-only post-rejection reconciliation reconfirmed package-backed handler topology and 50/50 package-backed guards; Candidate / Call Log / Status History / Receipt counts were 0/0/0/0. No Candidate row was created.

The single runtime result is behavioral evidence from the package-backed API path, but this exact diagnostic does not distinguish active R4M code whose bounded-parent fix remains insufficient from a package activation/cache issue. Runtime classification is `PACKAGE_GUARD_PARENT_CONTEXT_FAILURE`; package disposition remains `PACKAGE_UPDATE_ACCEPTED_CONTENT_NOT_BYTE_RECONCILABLE`. Preserve the consumed runtime lock and evidence journal. Do not update the package, retry, or invoke another API. Plug-in Profiler/context capture is the next diagnostic to inspect the sanitized ParentContext chain and trusted marker propagation. Organization auditing remained disabled and unchanged, and was not the runtime blocker. No schema, Choice, API contract, security, app, audit-setting, publication, legacy assembly, or signing-key change occurred; no commit or push was made.

### Marker source, R4L diagnosis, and correction

The existing private key is `os_sr_cact.validated_intent`. `DataverseStore.Authorize` writes a string SHA-256 fingerprint of the exact protected operation and target to the `ApplyCandidateAction` execution context's `SharedVariables` immediately before its `OrganizationService.Create` or `Execute` call. Each write removes the marker in `finally`, including service failures. It is not a Custom API parameter, entity field, environment variable, receipt value, request fingerprint, response value, or trace value.

Before R4M, `ProtectCandidateCore` inspected only `context.ParentContext` and required that single context to be the `os_sr_cact` stage-30 parent carrying the matching fingerprint. The R4L child reached the `CALLER_MARKER` rejection category. The offline SDK harness also reproduced the exact source-level mismatch: a matching marker on the trusted API ancestor one or two parent links up was rejected when the immediate parent had no marker. The live R4L trace did not retain a sanitized ParentContext depth/shape, so it does not prove how many contexts separated that live child from its trusted operation. The source defect is the guard's fixed immediate-parent lookup; the exact live ancestor location remains unknown.

R4M now walks no more than eight `ParentContext` links. It accepts only a context whose message is `os_sr_cact`, stage is 30, mode is synchronous, transaction is active, depth is lower than the protected child, user and initiating user agree with the child, `ActionType` is supported and consistent with the protected write category, and private marker exactly matches the target mutation fingerprint. It does not depend on context position or registration GUIDs. It fails closed when no such ancestor is found within the bound. The current context's SharedVariables are not trusted.

SDK harness coverage includes direct Candidate Create without a parent; caller `tag` equal to the marker; a private-key-like value placed in current SharedVariables; unrelated parent with a marker; trusted CreateCandidate marker one and two ancestors up; wrong API message; missing, wrong-type, and wrong-value marker; action/write mismatch; Candidate Create, Candidate Update, Call Log, Status History, and Receipt child writes; and a trusted marker beyond the eight-context limit. It also verifies marker cleanup and that the marker key/value is absent from receipts, outputs, and traces. Synthetic traces contain only trusted-parent found/not-found plus ancestor-hop category.

### Local artifact and checks

The package was rebuilt unsigned from the existing package project. Package ID/version, assembly identity/version, and both plug-in type full names are unchanged. Its five-entry package inventory is unchanged except for the intended DLL bytes; no signing key was accessed.

| R4M local artifact | SHA-256 |
|---|---|
| `os_sr_cact.dll` | `1d32def744252c4bc4f829455f0cb89bdbb656b79cfce69f840d0de3f4236f8e` |
| `os_sr_cact_pkg.1.0.0.nupkg` | `16d3adf6146edbcb22669c93a6bc33ef7cd8b062948108ee9a5cbee98ab3d5de` |
| Five-entry inventory (`path|uncompressed length|compressed length`, sorted and LF-joined) | `b2b341b52d1f19ed63efbb48fde82f0df18dd07db51f29312fa566608f1ee562` |

The current artifact pins are recorded in the package inspection runner. The local unsigned build and identity, version, five-entry inventory, type-name, and no-signing-material checks passed before deployment. Previously recorded local results: Candidate Core engine harness, 109 assertions; SDK adapter/guard harness, 140 assertions; all 12 PowerShell suites, 1,134 assertions; all 11 scripts parsed; R4M trusted-parent suite, 12 source assertions. Those suites were not rerun during this live runtime continuation. The legacy signed harness was not run and no signing key was accessed.

## Phase 3D-R4L Guard Cutover and CreateCandidate Stop (historical; superseded by R4M)

**`CREATECANDIDATE_RUNTIME_FAILURE` — all 50 Candidate Core direct-write guard EventHandlers were migrated to the existing package-backed guard and GET-reconciled. The one authorized CreateCandidate dispatch was rejected by the guard's caller-marker check; no later runtime-matrix operation occurred.**

### Guard migration and reconciliation

The owner-confirmed VN LMV IT target and expected PAC/Dataverse identity guards passed. The retained rollback map covered 50 exact SDK message-processing steps, their protected-property fingerprints, unsecure-configuration hashes, secure-configuration relationship IDs only, and project Solution memberships. No secure-configuration contents were read.

The initial Apply sent one EventHandler PATCH (HTTP 204). Its immediate readback matched the package-backed handler, protected-property digest, and Solution memberships, but the journal compared an empty string to a null configuration hash because the plan hash had been cast to `[string]`. A fresh GET-only reconcile against the immutable map proved configuration, protected properties, memberships, package identity, and the exact one-package/49-legacy topology unchanged. The local journal was preserved, and the runner was corrected to preserve nullable fingerprints.

The first continuation reconciled 14 further EventHandler PATCHes and stopped at local journal persistence before sending the next request. Its journal recorded 14 `GET_RECONCILED`, one `DISPATCH_RESERVED` with no HTTP status or readback, and 34 `PLANNED`; its PATCH count was 14 and automatic retries were 0. The prior/root journal SHA-256 link was verified. Journal-aware GET-only reconciliation mapped all 15 completed steps to package handlers and the remaining 35 steps to legacy handlers with no property or membership drift. The reserved step was proven undispatched and was not retried.

A second continuation preflight then stopped before any PATCH due to a local variable collision; it made 7 GETs, 0 PATCHes, and 0 retries, and did not create a new journal. After correcting the local variable name, both the journal-aware GET-only reconciliation and continuation preflight passed. The new continuation dispatched only the remaining 35 pending EventHandlers and reconciled all 50 package-backed. Its totals were 574 GETs, 35 PATCHes, and 0 retries. Across R4L there were 50 successful one-time EventHandler PATCHes: 1 initial, 14 in the first continuation, and 35 in the final continuation. No rollback PATCH was needed or made.

No package update, new package, Custom API handler PATCH, schema or Choice write, privilege/security change, app change, PublishXml/PublishAllXml, audit-setting change, or legacy assembly write occurred. Both original evidence journals and the continuation journal were preserved locally; no environment-specific IDs or journal contents were added to the repository.

### Single runtime attempt and stop

With all 50 guard steps package-backed, fresh runtime preflight reconciled the existing `os_sr_cact_pkg`, assembly and both exact package types, the unchanged 13-parameter Custom API contract, and the package-backed API handler. It required the 50-step package guard topology and count-only returned 0 Candidates / 0 Call Logs / 0 Status History / 0 Receipts. The one-shot R4L runtime authorization was confirmed unused before Apply.

The runtime runner dispatched CreateCandidate exactly once using the synthetic name `[SYNTHETIC-E2E] Candidate Core Acceptance`, a reserved `.invalid` address, fresh CorrelationId, and no CandidateId or ExpectedStatus. It returned HTTP 400 / `0x80040265` / `DIRECT_WRITE_GUARD_REJECTED:CANDIDATE_CREATE:CALLER_MARKER:CC_CREATE_CANDIDATE:0x80040265`. The journal records one rejected CreateCandidate, zero retries, and no CandidateId reference. A fresh GET-only post-failure preflight again returned 0/0/0/0 and confirmed all 50 package-backed guard steps. No Call Log, Status History, Receipt, or Candidate persisted; the remaining seven API dispatches were not attempted.

This does not establish that the guard-step migration introduced a regression: R4K's preceding CreateCandidate attempt was rejected by the legacy guard with the same Dataverse error code. The R4L package guard provides the specific `CALLER_MARKER` classification, localizing the rejection predicate, but the live request did not capture enough execution context to determine whether the operation handler omitted the marker or Dataverse failed to propagate it. No rollback was performed. The R4L one-shot runtime authorization is consumed; further marker diagnosis or live runtime calls require a new bounded authorization. Final classification: **`CREATECANDIDATE_RUNTIME_FAILURE`**.

### Local validation

All 11 PowerShell suites passed (1,122 assertions), including the 14-assertion R4L guard-cutover suite. The Candidate Core engine harness passed 109 assertions; the SDK adapter/guard harness passed 125 assertions. All 22 PowerShell scripts parsed, relative links in the five changed documentation files resolved, the added-diff privacy scan passed, and `git diff --check` passed. No package was rebuilt or updated in R4L.

## Phase 3D-R4K Guard-Diagnosed CreateCandidate Stop

**`CREATECANDIDATE_RUNTIME_FAILURE` — one update of the existing unsigned package succeeded; one CreateCandidate dispatch was rejected by the retained legacy direct-write guard. Stop without retry or runtime-matrix continuation.**

### Bounded diagnostic change and local validation

The R4K source adds safe stage-specific markers around each organization-service operation and wraps service failures with the operation stage and Dataverse error code. It recognizes the retained legacy guard's exact generic rejection text and emits a categorized diagnostic without returning arbitrary fault text, identifiers, or candidate data. The guard conditions, operation-first SDK input projection, CreateCandidate's optional CandidateId behavior, server-controlled initial state, and existing-record ExpectedStatus checks remain unchanged. The SDK harness covers service ordering/faults, generic legacy-guard recognition, privacy, and package-handler/legacy-guard context. It does not establish the live guard's precise rejection predicate.

The final unsigned package build succeeded with 0 warnings and 0 errors. Candidate Core engine tests passed 109 assertions and SDK adapter/guard tests passed 117 assertions. All 10 PowerShell suites passed (1,108 assertions); all 20 PowerShell scripts parsed. Package identity/content, changed-document link, added-diff privacy, and `git diff --check` checks passed. The prohibited legacy signing key was not accessed.

| Local artifact | SHA-256 |
|---|---|
| `os_sr_cact.dll` | `fd5f46e9d2e9388c7f5fefb90dc327ef9d1d40d241b5897c7e2913a92f2113b0` |
| `os_sr_cact_pkg.1.0.0.nupkg` | `f0403d61e3cfa92595e469e1332716a609c8d597c9d047bfc8bcb9a9379941b8` |
| Five-entry inventory (`path|uncompressed length|compressed length`, sorted and LF-joined) | `9df64f69b291f880e4d379899729f46196c6626a1f71658f6cad3f3d0be0fe92` |

The package identity remains `os_sr_cact_pkg` v1.0.0; the assembly remains unsigned `os_sr_cact` v1.0.0.0 with the exact handler and guard types. The local inventory contains only the previously validated five NuGet entries. The deployment script's package/DLL/inventory pins were refreshed to these validated local artifact fingerprints. The hashes identify the local submitted artifact, not a hash independently read back from the deployed package bytes.

### Live package update and reconciliation

PAC identity and Dataverse WhoAmI/expected-user guards matched the owner-confirmed VN LMV IT target. A fresh pre-update runtime preflight reconciled one existing package and package-backed `os_sr_cact.ApplyCandidateAction` / `os_sr_cact.ProtectCandidateCore` types. The CreateCandidate API still pointed to the package handler; all 13 request parameters matched the current contract, including optional `CandidateId` and optional `ExpectedStatus`. The fresh count-only gate returned 0 Candidates / 0 Call Logs / 0 Status History / 0 Receipts.

PAC CLI 2.13.1 updated the existing package once using its existing PluginPackage identity and the validated `.nupkg`; the command returned success. Immediate GET reconciliation confirmed the same package identity/name/version, package-backed assembly and both exact types, unchanged package-backed API handler and request contract, and 0/0/0/0 business/evidence rows. The package's `modifiedon` advanced. Package update count: 1; automatic retries: 0. No handler/API PATCH, package creation, schema, Choice, security, app, publication, audit-setting, or legacy assembly write occurred.

### Single CreateCandidate dispatch and stop

The guarded runtime runner sent one synthetic CreateCandidate request with a fresh CorrelationId, the approved synthetic candidate name, a reserved `.invalid` email, and no CandidateId or ExpectedStatus. The request fingerprint was `9732a1a9fb35296f511e20f8e32e215d29afcff45f0962c3da021e363a8c9698`. The response was HTTP 400 / `0x80040265` / `DIRECT_WRITE_GUARD_REJECTED:LEGACY_GENERIC_GUARD:CC_CREATE_CANDIDATE:0x80040265`. The exact guard predicate is unknown: the retained deployed guard returned a generic rejection rather than the categorized diagnostics available in the new package source. The failure is localized to the Candidate Create service operation under the legacy guard; this does not establish which parent-context, caller-context, or intent-marker check failed.

A fresh post-failure count-only reconciliation again returned 0 Candidates / 0 Call Logs / 0 Status History / 0 Receipts. The one-shot journal records exactly one CreateCandidate dispatch, HTTP 400, the fingerprint above, and zero retries. No Candidate was retained, no second CreateCandidate request or package update was made, and no later runtime-matrix operation was attempted. No deterministic package-only correction was proven; further live work must first establish the failing guard predicate and authorize any required registration/assembly remediation. Final classification: **`CREATECANDIDATE_RUNTIME_FAILURE`**.

## Phase 3D-R4J Operation-First Input Projection and Runtime Stop

**`CREATECANDIDATE_RUNTIME_FAILURE_UNRESOLVED` — the operation-first adapter correction passed local validation and the existing unsigned package was updated once. The single authorized CreateCandidate call returned HTTP 400 / `0x80040265` / `DATAVERSE_OPERATION_REJECTED`. The sanitized result did not identify a stage or parameter, so no deterministic local defect is proven. Stop without another invocation or a remaining runtime-matrix operation.**

### Diagnosis and correction

Before R4J, `ApplyCandidateAction` copied every SDK `InputParameters` entry into `ActionRequest`. The request constructor applies operation-specific allowlists; therefore a known Custom API parameter that is not applicable to CreateCandidate could reach the generic unexpected-input rejection even when the Web API payload omitted it. This explains a reachable local `UNEXPECTED_INPUT` path, but raw R4I SDK inputs were not captured, so it does not prove which input caused the earlier live error.

The plug-in now reads ActionType and CorrelationId first, validates the operation, checks only SDK parameter names against the declared API contract, and projects only that operation's applicable fields before constructing `ActionRequest`. For CreateCandidate, CandidateId, ExpectedStatus, CallOutcome, ContactedAt, Notes, and Reason are not projected or parsed; their SDK defaults/wrappers cannot enter normalized Values or the fingerprint. CandidateName, CandidateEmail, CandidatePhone, PositionId, and CandidateSourceId remain applicable and strictly validated. Initial status remains server-controlled as `Need Call Candidate`; existing-record ExpectedStatus validation and fail-closed workflow transitions are unchanged.

| Stage | Operation/condition | Safe diagnostic |
|---|---|---|
| SDK adapter | Supported operation identified; an InputParameters key is not one of the 13 declared Custom API parameters | `UNEXPECTED_INPUT:SDK_ADAPTER:OTHER` |
| ActionRequest construction | CreateCandidate direct/canonical request contains a non-empty valid CandidateId | `UNEXPECTED_INPUT:ACTION_REQUEST:CandidateId` |
| ActionRequest construction | The operation-specific allowlist rejects another declared parameter | `UNEXPECTED_INPUT:ACTION_REQUEST:<parameter>` |
| ActionRequest construction | A disallowed key is not a declared parameter | `UNEXPECTED_INPUT:ACTION_REQUEST:OTHER` |
| Engine/repository | No `UNEXPECTED_INPUT` emitter | No `UNEXPECTED_INPUT` diagnostic |
| Dataverse exception translation | Organization-service fault is neither the recognized correlation/key conflict nor row-version conflict | `DATAVERSE_OPERATION_REJECTED` |

The parameter values and arbitrary key text are not included in diagnostics. The runtime error parser preserves the structured stage/parameter code. R4J's live error was only `DATAVERSE_OPERATION_REJECTED`, which is insufficient to attribute it to the adapter or another local branch; do not infer a second fix from that response.

### Local validation and submitted package

The unsigned Release package rebuild succeeded with 0 warnings and 0 errors. The Candidate Core engine harness passed 109 assertions; the real SDK adapter harness passed 92 assertions. The SDK harness saturated all 13 API parameters with CreateCandidate, including non-applicable wrapper/default values, and proved successful creation plus equality of the persisted request fingerprint with a minimal request containing the same applicable values. It also retained UpdateCandidate status validation and covers unknown-operation ordering. All 10 PowerShell suites passed (1,107 assertions); all 20 repository PowerShell scripts parsed; package identity/content assertions passed; the added-line privacy scan, changed-document relative-link validation, and `git diff --check` passed.

The submitted local artifact remains unsigned `os_sr_cact_pkg` v1.0.0 with the unchanged five NuGet entry paths. DLL SHA-256: `7b819af8ad625c4543a355b5f3106ae63e1298f9e9226e7e45d7f800c70e1b48`. Package SHA-256: `f0694ea17ec0ddf1c08bd6aa34dbc35a16cae060c92ca334b6d20286fad65b06`. Inventory fingerprint (SHA-256 of sorted `entry-path|uncompressed-length` lines joined with LF): `92e1661c906e77947280d76e39be7e17265facb80d6e3fae2ec21fc5931a53d8`. The embedded DLL hash matches the local DLL. These are submitted local artifact hashes, not a readback hash of deployed package bytes. No signing key was accessed.

### Guarded live update and reconciliation

Fresh PAC identity and Dataverse WhoAmI/expected-user checks matched the owner-confirmed VN LMV IT target. Before update, the guarded preflight found exactly one existing package, the package-backed `os_sr_cact.ApplyCandidateAction` and `os_sr_cact.ProtectCandidateCore` types, the unchanged 13-parameter API contract and package-backed CreateCandidate handler. Separate read-only reconciliation verified the Candidate Core schema exact and the Operation Receipt alternate key Active. Candidate, Call Log, Candidate Status History, and Operation Receipt counts were 0/0/0/0.

PAC CLI 2.13.1 updated the existing PluginPackage once using its current ID and the validated `.nupkg`; the command exited successfully. Immediate GET reconciliation confirmed the same package ID, name/unique name and version, with package modification metadata advanced. Post-update guarded preflight retained the package-backed handler, exact two types, all 13 request parameters, and 0/0/0/0 rows. No handler PATCH was needed. Deployed package bytes were not independently hashed. Package updates: 1; automatic retries: 0.

### Single runtime invocation and stop

The one synthetic request contained exactly `ActionType`, `CorrelationId`, `CandidateName`, and `CandidateEmail` (reserved `.invalid` domain); CandidateId, ExpectedStatus, PositionId, CandidateSourceId, and other non-applicable parameters were omitted. The runner journal records one CreateCandidate dispatch, payload SHA-256 `c6e7bb97710dc76e142dc76698020ae186d55cb00b7af50622eeac09e88f5c91`, HTTP 400, and zero retries. The sanitized response was `HTTP 400; Dataverse code 0x80040265; DATAVERSE_OPERATION_REJECTED`; no safe stage/parameter diagnostic was returned.

A fresh post-failure count-only preflight again found 0 Candidates, 0 Call Logs, 0 Candidate Status History rows, and 0 Operation Receipts. The Candidate Number was not generated. The post-CreateCandidate RecordCall, replay/conflict, Candidate Answered-to-Waiting transition, stale-status, and scheduling-guard checks were not run. No schema, Choice, Custom API, privilege/security, app, publication, legacy assembly, or signing-key change occurred. The package update and one runtime dispatch are the only live writes in R4J. Any further runtime attempt requires a new owner authorization because this failure did not prove a deterministic local repair.

## Phase 3D-R4I Optional Guid Normalization and SDK Adapter Acceptance

**`CREATECANDIDATE_RUNTIME_FAILURE` — the unsigned package was updated in place once; the single CreateCandidate request was rejected with `UNEXPECTED_INPUT`. Stop without retry.** No subsequent Candidate Core matrix operation was invoked.

### Local correction and validation

The shared operation engine now uses one optional-Guid normalization path for `PositionId` and `CandidateSourceId`. On CreateCandidate, absent, null, and `Guid.Empty` normalize to omission and therefore create no lookup; a non-empty Guid is preserved for the intended lookup; a malformed SDK value is rejected with a parameter-specific `INVALID_GUID_PARAMETER` code. CreateCandidate `CandidateId` absent/null/empty remains valid and is excluded from its normalized fingerprint; malformed values remain rejected. CreateCandidate still ignores `ExpectedStatus`, and the server still selects `Need Call Candidate`. UpdateCandidate retains explicit-null lookup clearing and existing-record status validation.

The SDK adapter harness now references the unsigned package project instead of the legacy signed project. It exercises the real SDK adapter with synthetic contexts and verifies optional-Guid normalization, valid lookup mapping, invalid-value rejection before writes, CandidateId semantics, server-controlled status, and matching/stale UpdateCandidate ExpectedStatus behavior. No signing key was accessed or required.

Validation passed before deployment: unsigned package Release rebuild (0 warnings, 0 errors); Candidate Core engine harness (109 assertions); unsigned SDK adapter harness (86 assertions); all 10 PowerShell suites (1,106 assertions); 20 PowerShell scripts parsed; package inventory/type checks; updated Markdown relative links; added-line privacy scan; and `git diff --check`.

The locally built unsigned `os_sr_cact_pkg` v1.0.0 contains the five approved NuGet entries and no PDB or signing material. DLL SHA-256: `ba2a12a6e99242fabff375ed7272f334477769bdaf4cc33cc665c223db242043`. Package SHA-256: `f70b76dafc5f27477b782950edabcf761391d470cdaacbb9cbc2256c5a0fbfa1`. Package inventory fingerprint (SHA-256 of sorted `entry-path|uncompressed-length` lines joined with LF): `3a2667983f044e9b1e611d493adf991c17808af925fb406bc758e6364440fc4e`. The embedded DLL hash matches the local DLL. These are local artifact hashes, not hashes of the deployed file.

### Guarded live reconciliation and package update

PAC identity and guarded Dataverse WhoAmI matched the owner-confirmed VN LMV IT target and expected user. Fresh pre-update reconciliation confirmed one existing `os_sr_cact_pkg` v1.0.0, one package-backed `os_sr_cact` assembly v1.0.0.0, exactly `os_sr_cact.ApplyCandidateAction` and `os_sr_cact.ProtectCandidateCore`, the unchanged approved Custom API request/response contract, and CreateCandidate's existing package-backed handler. All four Guid request parameters were freshly read: `CandidateId` and `PositionId` are optional Guid; `CorrelationId` is required Guid; `CandidateSourceId` is optional Guid. Their `LogicalEntityName` values were null. Candidate Core schema reconciled exact and the Operation Receipt alternate key was Active. Count-only pre-update reads found 0 Candidates, 0 Call Logs, 0 Candidate Status History rows, and 0 Operation Receipts.

The existing package was updated exactly once using PAC CLI `pac plugin push` with the existing PluginPackage ID and the validated unsigned `.nupkg`. The command returned success. No package was created, no API handler PATCH or cutover occurred, and the legacy signed assembly was unchanged. Fresh GET reconciliation retained the same package identity/version, package-backed assembly and two types, API contract, handler mapping, and legacy inventory. The package record's modified time advanced; the package assembly metadata timestamp did not. Dataverse GET did not expose package content, so the deployed DLL/package content SHA-256 could not be independently read back. Local artifact hashes above identify the submitted package.

The post-update runtime preflight again returned 0/0/0/0 business/evidence rows, the same package-backed handler, the exact two package types, and all 13 request parameters. Automatic retries remained zero.

### Single runtime invocation and stop

The one approved synthetic CreateCandidate request omitted `CandidateId`, `ExpectedStatus`, `PositionId`, and `CandidateSourceId`; it contained only `ActionType`, a fresh `CorrelationId`, synthetic `CandidateName`, and the reserved `.invalid` `CandidateEmail`. The request was dispatched once and rejected with HTTP 400 / Dataverse code `0x80040265` / `UNEXPECTED_INPUT`. The sanitized payload fingerprint is `6dbff488be11058737c499f3b8a3766130d469c7d7fa0d7a79de30ab18ccbdfa`. The raw plug-in InputParameters were not captured, so the source of the unexpected parameter is not established. The earlier `INVALID_LOOKUP` failure was not repeated, but this result does not prove that its historical cause was resolved.

The journal records one rejected CreateCandidate dispatch and zero retries. A fresh post-failure count-only preflight again found 0 Candidates, 0 Call Logs, 0 Candidate Status History rows, and 0 Operation Receipts. No Candidate Number was generated. RecordCall, replay/conflict, UpdateCandidate, and scheduling-guard runtime checks were not invoked. No schema, Choice, API parameter/response, privilege, security, app, audit-setting, publication, or legacy assembly write occurred. Do not retry or vary the payload in this run; further diagnosis requires a new authorization.

## Phase 3D-R4H INVALID_LOOKUP Diagnosis

**`INVALID_LOOKUP_UNRESOLVED` — do not update the package, create reference fixtures, or invoke CreateCandidate again in this run.** The R4G failure remains one rejected request; R4H performed read-only diagnosis only. PAC and guarded Dataverse identity matched the confirmed VN LMV IT target and expected user. The package-aware runtime preflight confirmed package-backed `os_sr_cact.ApplyCandidateAction` routing and fresh Candidate/Call Log/Status History/Operation Receipt counts of 0/0/0/0.

### Exact local error branch

In [Operation.cs](../solutions/CandidateCore/Operation.cs#L84), while processing the allowed Candidate profile fields, any non-null `PositionId` or `CandidateSourceId` value that is not a non-empty .NET `Guid` throws `OperationError("INVALID_LOOKUP")`:

```csharp
if (value != null && (!(value is Guid lookup) || lookup == Guid.Empty))
    throw new OperationError("INVALID_LOOKUP");
```

This branch checks CLR type and empty-GUID status; it does not query whether a row exists, is active, or belongs to a target table. CandidateId is handled in a separate operation-specific branch. The live API parameters below are `Guid`, not `EntityReference`, and have no logical-entity-name metadata.

### Fresh live Custom API request contract

Fresh reads returned exactly one `os_sr_cact` Custom API and 13 request-parameter records. Type codes are the live Custom API metadata values: 1=DateTime, 7=Integer, 10=String, 12=Guid. `LogicalEntityName` was null for every parameter. The live metadata entity exposes no `position` property; parameter order is not material to named JSON request properties.

| UniqueName | Type | IsOptional | LogicalEntityName |
|---|---|---:|---|
| ActionType | String (10) | No | null |
| CallOutcome | Integer (7) | Yes | null |
| CandidateEmail | String (10) | Yes | null |
| CandidateId | Guid (12) | Yes | null |
| CandidateName | String (10) | Yes | null |
| CandidatePhone | String (10) | Yes | null |
| CandidateSourceId | Guid (12) | Yes | null |
| ContactedAt | DateTime (1) | Yes | null |
| CorrelationId | Guid (12) | No | null |
| ExpectedStatus | Integer (7) | Yes | null |
| Notes | String (10) | Yes | null |
| PositionId | Guid (12) | Yes | null |
| Reason | String (10) | Yes | null |

The downloaded live `$metadata` document returned HTTP 200 but contained no `Action` definition or `ActionImport` for this private Custom API. It therefore does not publish a usable CSDL operation signature for `os_sr_cact`; the request-parameter records are the available live parameter-contract source. The records agree with the approved [Phase 3C API contract](PHASE_3C_API_CONTRACT.json) for the relevant GUID types and optionality. No API metadata was changed.

### R4G sanitized request shape and parser evidence

The failed R4G runner constructed these JSON members: `ActionType` (String, `CreateCandidate`), `CorrelationId` (JSON String containing a fresh GUID), `CandidateName` (String, fixed synthetic label), and `CandidateEmail` (String, generated reserved `.invalid` address). The correlation GUID and generated email value are not reproduced here. The request fingerprint is `4ce30f4126dc4ba6b7539f636aba30c071298ee4cc6ee987d07ce5fd0129d2e8`.

| Parameter | R4G request | Caller representation | Live / parser meaning |
|---|---|---|---|
| ActionType | Present | JSON String | String |
| CallOutcome | Omitted | — | Optional Integer |
| CandidateEmail | Present | JSON String | String; operation-required |
| CandidateId | Omitted | — | Optional Guid; valid create semantics |
| CandidateName | Present | JSON String | String; operation-required |
| CandidatePhone | Omitted | — | Optional String |
| CandidateSourceId | Omitted | — | Optional Guid; target when supplied: `os_sr_csrc` |
| ContactedAt | Omitted | — | Optional DateTime |
| CorrelationId | Present | JSON String with GUID syntax | Required Guid; actual plug-in InputParameters CLR value not captured |
| ExpectedStatus | Omitted | — | Optional Integer; ignored for CreateCandidate |
| Notes | Omitted | — | Optional String |
| PositionId | Omitted | — | Optional Guid; target when supplied: `os_sr_pos` |
| Reason | Omitted | — | Optional String |

Thus the R4G HTTP body contained no lookup value, EntityReference-like object, Entity payload, or empty lookup GUID. The actual plug-in `InputParameters` collection was not captured; the R4G failure journal stores only the payload hash and sanitized error. It cannot establish whether Dataverse supplied an omitted optional Guid as absent, null, or `Guid.Empty` to the plug-in. The R4G local request builder is therefore not proven to have serialized a lookup incorrectly, and the local `INVALID_LOOKUP` branch is a possible emitter, not a proven source of that live response.

### Lookup dependencies, reference availability, and trace

| CreateCandidate lookup | Live type | Current Candidate schema | CreateCandidate requirement | Safe-reference read |
|---|---|---|---|---|
| PositionId → `os_sr_pos` | Optional Guid; no LogicalEntityName | Optional Position lookup | Optional | Not required; request omitted it |
| CandidateSourceId → `os_sr_csrc` | Optional Guid; no LogicalEntityName | Optional Candidate Source lookup | Optional | Not required; request omitted it |
| Assigned TA → `os_sr_ta` | No CreateCandidate API parameter | Conditional before booking | Not part of CreateCandidate | Not required |

There are no required CreateCandidate lookup references under the current approved design, so R4H did not query reference-row contents, create synthetic prerequisite rows, or select a real-person TA record. The API and Candidate Core schema reconciliation found no requiredness or logical-table metadata drift. No Candidate, Call Log, History, or Receipt rows were present at the fresh preflight.

A read-only Plugin Trace Log query for `INVALID_LOOKUP` in the bounded R4G execution window returned zero matching entries. No trace settings were enabled or changed. This leaves the exact runtime parameter values and originating throw site unverified.

### Classification and R4H boundaries

The single primary classification is **`INVALID_LOOKUP_UNRESOLVED`**. The local branch condition is known, but neither trace data nor captured plug-in inputs prove that it emitted the R4G error. The R4G request omitted all lookup parameters, and current API metadata marks the lookup GUIDs optional. Therefore:

- local source correction: none;
- package update: 0;
- synthetic prerequisite rows: 0;
- CreateCandidate invocations: 0 in R4H (the single R4G invocation remains failed);
- remaining runtime-matrix operations: 0;
- handler PATCHes, schema/security/app writes, PublishXml/PublishAllXml, and automatic retries: 0.

R4H's package-aware runtime preflight performed 14 GETs and confirmed 0/0/0/0 rows, package-backed routing, zero Custom API invocations, zero business-data writes, and zero retries. A separate legacy-cutover-only preflight performed 121 GETs, including 46 storage reads, then stopped because it requires the API to point to the retained legacy handler. That runner's assumption is not the current R4H baseline; it made no write and is not evidence of live drift. The successful live API/parameter/CSDL/trace read set used four GETs. Read-only discovery did not touch the environment's data or metadata.

No package content hash is claimed for the deployed binary. The local unsigned R4G DLL and package hashes remain as recorded in the [R4G section](#phase-3d-r4g-active-package-update-and-createcandidate-acceptance); they were not rebuilt or redeployed during R4H.

### AI handover

Resume only after obtaining evidence that distinguishes the local parser branch from any platform-side lookup rejection—preferably the original invocation's safe trace/InputParameters evidence if retained, otherwise a separately approved way to observe the runtime representation without a business write. Preserve the live Guid/optional contract and package-backed handler. Do not infer that an omitted optional Guid becomes `Guid.Empty`; do not add fixtures, alter code/package/API metadata, or repeat CreateCandidate based only on the current error symbol. Once the source is established, apply only the matching authorized branch and re-run the zero-row and exact contract gates before any separately authorized runtime call.

## Phase 3D-R4G Active Package Update and CreateCandidate Acceptance

**`CREATECANDIDATE_RUNTIME_FAILURE` — the existing package was updated once and reconciled; one approved CreateCandidate invocation was rejected with `INVALID_LOOKUP`.** The owner explicitly confirmed VN LMV IT as the target. PAC identity and guarded WhoAmI matched the expected environment and user. No retry, payload variation, or subsequent runtime-matrix operation was performed.

### Local package gate

Without rebuilding or modifying the artifact, the existing package was revalidated against the approved source and package contract. `ActionRequest` identifies CreateCandidate before status handling; CreateCandidate ignores `ExpectedStatus` representations and excludes that input from normalized values/fingerprints. Optional CandidateId handling remains in place. The package is unsigned, uniquely named `os_sr_cact_pkg`, version `1.0.0`, and contains the expected assembly `os_sr_cact` version `1.0.0.0` and approved handler/guard type names.

Current local DLL SHA-256: `c1ff0d21d72b2d10f92bf12d02fd381df2b5c16eb3e7b549fb2bcd4ce783f5c9`. Package SHA-256: `4729700e36fa384ae7909c14a2bfee2cf1da8592503292511597121668eebd79`. The embedded DLL hash matches the current DLL. The package inventory contains five paths: `_rels/.rels`, `[Content_Types].xml`, `lib/net462/os_sr_cact.dll`, `os_sr_cact_pkg.nuspec`, and `package/services/metadata/core-properties/nuget.psmdcp`. Fingerprint (SHA-256 of sorted `entry-path|uncompressed-length` lines joined with LF): `f0a38e99466fe5d8ea66a2709495970f04da53a09c747f02a19e6b635168fc97`.

The local Candidate Core harness and applicable offline tests are recorded below in the R4F section. The SDK adapter harness was not run: its legacy signing guard requires protected signing material, which was not accessed. Its status is `LEGACY_SIGNED_HARNESS_NOT_APPLICABLE_TO_PACKAGE_DEPLOYMENT`; it remains outside the unsigned package deployment prerequisite.

### R4G live-operation disposition

Fresh GET reconciliation confirmed the existing `os_sr_cact_pkg` v1.0.0, its package-backed assembly and both expected types, unchanged Custom API contract, exact Candidate Core schema, Active receipt key, and package-backed `ApplyCandidateAction` routing. Candidate Core handlers were package-backed before and after the update; no Custom API handler PATCH was made. The pre-update count-only gate was Candidate/Call Log/Status History/Receipt = 0/0/0/0.

The PRT Update form was opened but not saved because its displayed name/prefix did not unambiguously establish the live package UniqueName. Exactly one in-place update of the existing package was then performed successfully with PAC CLI `pac plugin push`; no package was created and no legacy assembly was changed. Immediate GET reconciliation retained the same package identity, UniqueName, version, assembly/type identities, Solution membership, API contract, and handler route. The package row's `ModifiedOn` advanced; the assembly's `ModifiedOn` did not. Dataverse GET did not expose package content, so neither the pre- nor post-update deployed binary hash is known. The verified local package and DLL SHA-256 values remain those recorded above; they are not evidence of deployed bytes.

The post-update zero-row gate passed. The single synthetic request contained `ActionType`, `CorrelationId`, `CandidateName`, and `CandidateEmail`; it omitted `CandidateId` and `ExpectedStatus`. Its journal fingerprint is `4ce30f4126dc4ba6b7539f636aba30c071298ee4cc6ee987d07ce5fd0129d2e8`. The API returned HTTP 400 / Dataverse `0x80040265` / `INVALID_LOOKUP`; the dispatch journal records one rejected CreateCandidate, zero retries, and classification `CREATECANDIDATE_RUNTIME_FAILURE`. The cause of `INVALID_LOOKUP` is not established by this response and no diagnosis is inferred. The runtime runner stopped before all remaining matrix actions.

A fresh count-only preflight after the rejection again found Candidate/Call Log/Status History/Receipt = 0/0/0/0 and confirmed the package-backed handler remained active. It made 14 GETs, zero Custom API invocations, and zero business-data writes. Package update count: 1; handler PATCHes: 0; CreateCandidate dispatches: 1; automatic retries: 0. Do not retry or resume the matrix without new explicit authorization.

### R4G offline validation

After the R4G documentation and runtime-runner changes, all 10 PowerShell suites passed (1,103 assertions), including the 12-assertion package identity/content suite; the Candidate Core operation harness passed 97 assertions; all 20 project PowerShell scripts parsed; relative Markdown links in the three updated documents resolved; the added-line privacy scan passed; and `git diff --check` passed. No package rebuild, signing-key access, or additional live business API call was performed.

## Phase 3D-R4F CreateCandidate ExpectedStatus Ignore Contract

**Local correction and package preparation complete. The R4F `LIVE_RUNTIME_BASELINE_DRIFT` classification is superseded: it resulted from a stale prompt assumption that the API had been restored to the legacy handler.**

### Bounded local correction

R4E rejected a CreateCandidate request with `EXPECTED_STATUS_NOT_APPLICABLE` even though its Web API payload omitted `ExpectedStatus`. The raw plug-in `InputParameters` were not captured, so the value's exact SDK representation and origin remain unresolved. R4F adopts the owner-approved create semantics: ExpectedStatus is inapplicable because there is no existing Candidate to compare. The server sets the initial status to `Need Call Candidate`.

`ActionRequest` now identifies the action before ExpectedStatus processing. CreateCandidate assigns no ExpectedStatus, does not parse or validate any supplied representation, and omits the parameter from normalized `Values` and the request fingerprint. This covers absent/null, default integer, valid and unsupported integers, strings, and wrapped/non-integer values. UpdateCandidate and existing-record actions retain their existing validation, including malformed-value rejection, required status for operations that require it, and stale-state rejection. CandidateId handling is unchanged.

The dependency-free Candidate Core harness passes 97 assertions. Its new regression cases verify ExpectedStatus-independence of fingerprints and receipt replay, server-controlled create status, wrapper-value ignoring, and continued malformed/stale checks for UpdateCandidate/existing-record actions. The SDK adapter harness source also includes a real `OptionSetValue` CreateCandidate test, but its build is blocked by the existing `CandidateSigningKey` guard. No key was accessed, changed, or supplied.

The runtime runner and existing-package cutover journal now use fresh R4F authorization identifiers. The rollback verifier supports the matching R4F evidence pair and retains support for the historical R4D evidence pair. Existing R4E one-shot locks are not reused.

### Local package and validation

The unsigned package identity remains `os_sr_cact_pkg` version `1.0.0`; assembly identity remains `os_sr_cact` version `1.0.0.0`; package entry inventory remains the same five entries, with only the intended DLL content changed. A normal incremental build and `dotnet pack` left the old `.nupkg` untouched, so the artifact was regenerated with `dotnet build .\solutions\CandidateCorePackage\CandidateCore.Package.csproj -c Release -t:Rebuild --no-restore`. The resulting Release build had 0 warnings and 0 errors. DLL SHA-256: `c1ff0d21d72b2d10f92bf12d02fd381df2b5c16eb3e7b549fb2bcd4ce783f5c9`. Package SHA-256: `4729700e36fa384ae7909c14a2bfee2cf1da8592503292511597121668eebd79`. The embedded DLL hash matches the built DLL hash. The package-content test confirms the exact entry list and unsigned assembly identity.

All 10 PowerShell suites passed (1,103 assertions); the Candidate Core operation harness passed (97 assertions); all 20 project PowerShell scripts parsed successfully; the unsigned package build and package identity/content checks passed; and `git diff --check` is included in the final local validation. No live Dataverse calls were made during these checks.

### Fresh read-only live preflight (historical evidence, status corrected by R4G)

The active PAC organization was freshly verified as VN LMV IT. The guarded existing-package preflight performed 121 GETs and stopped because the current API handler was package-backed rather than the then-expected legacy type. The R4G owner correction establishes that the prompt expectation was stale: package-backed routing was the intended current baseline and was not a package defect or a genuine live drift. The runner's own strict-legacy preflight was therefore inapplicable to the corrected R4G scope. It performed zero POSTs, PATCHes, package updates, handler rollbacks, retries, or business API calls. Its row-count gate was not reached; current business/evidence counts were not established by that attempt.

The exact read-only evidence showed the existing package `os_sr_cact_pkg` (`43765041-4fd0-f111-a05a-002248a1ba20`) and its package-backed File Store assembly `os_sr_cact` (`d71c6048-4fd0-f111-a05a-002248a1ba20`) with types `ApplyCandidateAction` (`d81c6048-4fd0-f111-a05a-002248a1ba20`) and `ProtectCandidateCore` (`d91c6048-4fd0-f111-a05a-002248a1ba20`). The retained legacy assembly/types were also present. The current `os_sr_cact` API (`0745a0bf-4c77-4e64-8125-12bfbf439229`) resolves to package-backed `os_sr_cact.ApplyCandidateAction` (`d81c6048-4fd0-f111-a05a-002248a1ba20`), not legacy type `b3ec49b1-be4c-4fb6-af10-3bac7a30e407`. This confirms the R4E report's package-backed-handler evidence and contradicts the R4F attachment's claimed restored legacy handler. Fresh reads also confirmed the approved API parameter inventory still has `ExpectedStatus` as optional Integer and `CandidateId` as optional GUID; metadata was not changed.

No R4F PRT package update, handler cutover/rollback, CreateCandidate call, or runtime-matrix operation followed. The local package hashes do not establish deployed content, and no live content hash is claimed. R4G supersedes the R4F drift classification and directs package-backed acceptance without redundant handler cutover. The R4E failed CreateCandidate call remains the last runtime invocation.

## Latest Phase 3D-R4E ExpectedStatus Contract Correction

**`CREATECANDIDATE_RUNTIME_FAILURE` — PRT update and handler cutover reconciled; one CreateCandidate invocation rejected; stop without retry.** The R4D package-backed handler test had a single determinate CreateCandidate rejection (`HTTP 400`, Dataverse `0x80040265`, `INVALID_EXPECTED_STATUS`) while the caller omitted ExpectedStatus. The one-shot sequence stopped, all four business/evidence counts were verified zero, and the authorized single PATCH restored the exact legacy handler. R4E does not revisit signing-key diagnosis.

### Fresh live Custom API request contract

The guarded read-only existing-package preflight returned `PLUGIN_PACKAGE_PROCESSED_CUTOVER_PREFLIGHT_READY`, performed 130 GETs, confirmed the retained legacy handler, and verified all four business/evidence row counts were zero. The preflight reconciler compared the exact live input inventory (UniqueName, Type, IsOptional) against the approved contract. Its R4E output additionally records LogicalEntityName:

| UniqueName | Type | IsOptional | LogicalEntityName |
|---|---:|---:|---|
| ActionType | 10 (String) | false | null |
| CallOutcome | 7 (Integer) | true | null |
| CandidateEmail | 10 (String) | true | null |
| CandidateId | 12 (GUID) | true | null |
| CandidateName | 10 (String) | true | null |
| CandidatePhone | 10 (String) | true | null |
| CandidateSourceId | 12 (GUID) | true | null |
| ContactedAt | 1 (DateTime) | true | null |
| CorrelationId | 12 (GUID) | false | null |
| ExpectedStatus | 7 (Integer) | true | null |
| Notes | 10 (String) | true | null |
| PositionId | 12 (GUID) | true | null |
| Reason | 10 (String) | true | null |

The current live metadata matches the repository contract. CandidateName and CandidateEmail are optional at the Custom API metadata layer but required by CreateCandidate operation validation. No metadata was modified.

### Source correction and local validation

The source defect was the shared ExpectedStatus check: if the input dictionary contained ExpectedStatus, the code rejected a nullable/non-Integer value before considering whether the action creates a new Candidate. The live request omitted the optional parameter and received that exact source error code. The executed code did not capture raw `InputParameters`, so the specific Web API-to-SDK representation (absent versus present-null) is not independently logged; the corrected path safely accepts either absent or null for CreateCandidate. It removes null ExpectedStatus from normalized `Values` so absent and null produce the same request fingerprint. Any explicit non-null CreateCandidate ExpectedStatus is rejected with `EXPECTED_STATUS_NOT_APPLICABLE` (wrongly typed non-null input is `INVALID_EXPECTED_STATUS`). Other operations retain their existing validation, including required ExpectedStatus for guarded transitions and stale-state rejection. CandidateId absent/null remains valid for create; malformed values fail, and valid supplied IDs remain unsupported.

The server continues to choose `Need Call Candidate` as initial state. The operation harness verifies absent/null ExpectedStatus, explicit unsupported values, null/absent fingerprint equivalence, CandidateId absent/null/malformed handling, operation-specific validation, matching and stale UpdateCandidate state, status-required transition behavior, audit-inactive creation, receipt creation, and no fabricated initial history.

Validation: all 10 PowerShell suites passed (1,100 assertions); Candidate Core operation harness passed (89 assertions); unsigned Release build succeeded with 0 warnings and 0 errors; package identity/content tests passed (12 assertions). DLL SHA-256: `ac4071d5d31d592d177df5472a9305c5c3279da6a3d37d4b524bc09b17de002a`. Package SHA-256: `3f4ee708e4d6239d5541882dd41f2787dbaa1ac9b2f349d8be5cb81a0b6ea824`. Package identity remains `os_sr_cact_pkg` version `1.0.0`; assembly remains `os_sr_cact` version `1.0.0.0`, unsigned; approved PlugInType full names remain unchanged. The same five entry paths remain and the newly built DLL is embedded; archive metadata may also differ due to repacking. The CandidateCoreSdk harness build was blocked by the pre-existing `CandidateSigningKey` build guard. No signing key was accessed or changed.

### PRT package update, handler cutover, and runtime result

The existing `os_sr_cact_pkg` package was updated exactly once in the already-authenticated PRT session; no new package was registered. Fresh Dataverse GET reconciliation returned the same PluginPackage ID `43765041-4fd0-f111-a05a-002248a1ba20`, name/unique name `os_sr_cact_pkg`, and version `1.0.0`. The post-update package row reported ModifiedOn `10/25/2026 5:57 PM`. Package content is not exposed by the read path, so no deployed-content hash comparison is claimed. The PackageId-linked assembly remains `os_sr_cact` v1.0.0.0, File Store, ID `d71c6048-4fd0-f111-a05a-002248a1ba20`; its exact package-backed types are `ApplyCandidateAction` (`d81c6048-4fd0-f111-a05a-002248a1ba20`) and `ProtectCandidateCore` (`d91c6048-4fd0-f111-a05a-002248a1ba20`). The assembly row's ModifiedOn remained `10/25/2026 3:37 PM`; the API returned the R4E-specific `EXPECTED_STATUS_NOT_APPLICABLE` code through this package-backed handler, which is runtime evidence the corrected handler code executed, although the deployed package bytes could not be directly hashed. The existing legacy assembly and types remain present and unchanged. The updated package SHA-256 is `3f4ee708e4d6239d5541882dd41f2787dbaa1ac9b2f349d8be5cb81a0b6ea824`; embedded DLL SHA-256 is `ac4071d5d31d592d177df5472a9305c5c3279da6a3d37d4b524bc09b17de002a`.

Fresh guarded cutover preflight passed with 130 GETs: exact package identity and type mapping, unchanged API contract/storage/privilege/Solution topology, exact retained legacy handler, and Candidate/Call Log/Status History/Receipt counts all zero. The one API handler PATCH changed only `PluginTypeId`, from legacy `os_sr_cact.ApplyCandidateAction` (`b3ec49b1-be4c-4fb6-af10-3bac7a30e407`) to the package-backed type `os_sr_cact.ApplyCandidateAction` (`d81c6048-4fd0-f111-a05a-002248a1ba20`). Immediate and full reconciliation returned `PLUGIN_PACKAGE_CUTOVER_RECONCILED_RUNTIME_PENDING`. Totals to this point: package updates 1; registrations 0; handler PATCHes 1; rollback PATCHes 0; API invocations 0; retries 0.

The package-backed runtime preflight then verified `os_sr_cact` → `os_sr_cact.ApplyCandidateAction` → `os_sr_cact_pkg` and fresh zero counts (14 GETs). The one-shot runtime runner dispatched exactly one `CreateCandidate` call. The request contained `ActionType`, a fresh `CorrelationId`, the approved synthetic Candidate name, and a reserved `.invalid` email; it omitted `CandidateId`, `ExpectedStatus`, CandidatePhone, and all other optional inputs. It returned HTTP 400, Dataverse `0x80040265`, `EXPECTED_STATUS_NOT_APPLICABLE`. Request-shape fingerprint: `dfd657e5e21b27d0937c009980f005c01fb0e8705e5fc5056ce7a48edf0bec4e`. Package/DLL hashes are recorded above. The API error is the code introduced by R4E for a non-null ExpectedStatus during creation, even though the outgoing request omitted that parameter. Raw plug-in InputParameters were not captured; whether the server synthesized a non-null parameter/default remains unresolved. The runtime journal records one rejected call, no retries, and no raw request values. Its `RuntimeFailureClassification` field is null due a local reporting gap; this report classifies the observed CreateCandidate failure as `CREATECANDIDATE_RUNTIME_FAILURE`. A local runner/test change now records the deterministic error and action-specific classification for future runs; it did not change the already-deployed plug-in or trigger another call.

**Stop boundary:** no second CreateCandidate payload or invocation was attempted. No remaining runtime-matrix calls were made. Post-failure row counts were not queried, so only the pre-invocation zero-row state is verified. No rollback was performed because the failure did not establish a package regression; no automatic repair is authorized. Tenant-write totals for R4E: one existing package update through PRT; one Custom API `PluginTypeId` PATCH; one approved synthetic CreateCandidate invocation; zero new registrations, schema/Choice/API-contract/privilege/security/app/publication/legacy-assembly writes, and zero retries. The primary result is `CREATECANDIDATE_RUNTIME_FAILURE`; stop and await a separately authorized decision before any further runtime call or plug-in/package behavior change. The local runtime-runner classification/logging improvement does not change deployed plug-in behavior.

## Prior Phase 3D-R4D Existing-Package Cutover and Runtime Result

**`PLUGIN_PACKAGE_CUTOVER_ROLLED_BACK` — cutover reconciled; CreateCandidate failed at runtime; the exact legacy handler was restored.** Owner authorization permitted the handler-only cutover and at most one synthetic Candidate after exact reconciliation. Fresh R4D read-only evidence found the existing package, its File Store assembly, and both exact package-backed types. This supersedes the R4B `PLUGIN_PACKAGE_PROCESSING_FAILED` disposition for package-processing status: the package `content` field still returns no fingerprintable value, but PRT processing evidence plus the PackageId-linked assembly and exact types establish processing. No package upload, update, or deletion was performed.

### Fresh package/API/storage reconciliation

| Check | Fresh pre-cutover R4D read-only result |
|---|---|
| PluginPackage `os_sr_cact_pkg` | One exact row; ID `43765041-4fd0-f111-a05a-002248a1ba20` |
| Package-backed assembly `os_sr_cact` | ID `d71c6048-4fd0-f111-a05a-002248a1ba20`; linked by PackageId; SourceType `File Store` |
| Package handler type | `os_sr_cact.ApplyCandidateAction`; ID `d81c6048-4fd0-f111-a05a-002248a1ba20` |
| Package guard type | `os_sr_cact.ProtectCandidateCore`; ID `d91c6048-4fd0-f111-a05a-002248a1ba20` |
| Retained legacy assembly | ID `ebabddad-3635-471b-9e97-88dbb0396df0`; unchanged |
| Legacy handler / guard types | `ApplyCandidateAction` ID `b3ec49b1-be4c-4fb6-af10-3bac7a30e407`; `ProtectCandidateCore` ID `7a31c1da-5a8e-4488-b91e-cb5ae01cb77e` |
| Candidate Core Custom API `os_sr_cact` | ID `0745a0bf-4c77-4e64-8125-12bfbf439229`; bound to the legacy handler before cutover |
| API contract / privilege / Solution | Exact and unchanged; package and assemblies remain in the approved Solution |
| Candidate Core storage / receipt key | Exact; Operation Receipt alternate key Active |
| Business/evidence row counts | Candidate 0; Call Log 0; Status History 0; Operation Receipt 0 |

The live-derived one-to-one handler map and final disposition are:

| Custom API | Current legacy handler | Package-backed replacement |
|---|---|---|
| `os_sr_cact` (`0745a0bf-4c77-4e64-8125-12bfbf439229`) | `os_sr_cact.ApplyCandidateAction` (`b3ec49b1-be4c-4fb6-af10-3bac7a30e407`) | `os_sr_cact.ApplyCandidateAction` (`d81c6048-4fd0-f111-a05a-002248a1ba20`); now restored to the legacy handler |

The retained legacy guard `os_sr_cact.ProtectCandidateCore` remains `7a31c1da-5a8e-4488-b91e-cb5ae01cb77e`; its package-backed exact-typename counterpart is `d91c6048-4fd0-f111-a05a-002248a1ba20`. The exact rollback mapping is retained in the short-lived R4D execution journal as well as recorded here. No type-to-API mapping was inferred from naming; the live API and PlugInType reads establish the relationship. Plug-in types are included with their containing assembly Solution component; no standalone type Solution-component rows are claimed.

### Local continuation path and stop boundary

The deployment runner now has separate `CutoverExistingPreflight`, `CutoverExistingApply`, and `RollbackExistingCutover` paths. Apply repeats identity, Solution, Candidate Core/receipt-key, API contract, package/type/legacy topology, and zero-row gates; writes a new one-shot rollback journal before dispatch; PATCHes only the existing Custom API `PluginTypeId` relationship; uses automatic retries `0`; and immediately GET-reconciles. It does not POST or update the package. Rollback requires a determinately classified R4D runtime defect, uses only the retained legacy handler ID, is limited to one PATCH, and preserves the package and both assemblies.

The one authorized cutover PATCH returned HTTP 204 and immediately reconciled to the package handler. The R4D runtime-specific preflight then returned ready with zero Candidate, Call Log, Status History, and Receipt rows. The runtime runner dispatched CreateCandidate exactly once using the synthetic `[SYNTHETIC-E2E] Candidate Core Acceptance` name and a reserved `.invalid` email, omitting optional `CandidateId` and `ExpectedStatus`. Dataverse rejected the request with HTTP 400, code `0x80040265`, `INVALID_EXPECTED_STATUS`. The call was a determinate rejection (`REJECTED`), not an uncertain write; no automatic retry or second API invocation occurred. A fresh count-only check after rejection again found all four business/evidence counts at zero. No synthetic Candidate or evidence rows were retained.

Primary runtime failure classification: `CREATECANDIDATE_RUNTIME_FAILURE`. The rest of the runtime matrix was not run. The approved one-PATCH rollback returned HTTP 204 and immediately/full-reconciled the Custom API to legacy `os_sr_cact.ApplyCandidateAction` (`b3ec49b1-be4c-4fb6-af10-3bac7a30e407`). The package-backed assembly/types and legacy assembly/types remain present. The final status is `PLUGIN_PACKAGE_CUTOVER_ROLLED_BACK`, with runtime failure classification `CREATECANDIDATE_RUNTIME_FAILURE`; the implementation cause is not yet established. The optional `ExpectedStatus` rejection is an open contract/runtime discrepancy, not a verified root cause. Do not retry the API, re-cut over, update the package, or repair the operation without new authorization and a bounded diagnosis.

R4D action counts: existing package upload/update 0; handler cutover PATCH 1; rollback PATCH 1; Candidate Core Custom API dispatch 1 (rejected); business/evidence rows 0; automatic retries 0; schema, Choice, security, app, organization-audit, or publication writes 0; commit/push 0. The cutover preflight used 130 GETs; cutover apply 203 GETs; runtime preflight 14 GETs; runtime apply 14 GETs; post-failure count/preflight 14 GETs; rollback 194 GETs.

Final offline validation: all 10 PowerShell suites passed (1,099 assertions); the Candidate Core operation harness passed (79 assertions); all 20 PowerShell files parsed; 84 relative links in the modified documents resolved; the added-line privacy scan and `git diff --check` passed. These checks do not constitute live runtime acceptance. See [Current State](CURRENT_STATE.md).

## Latest Phase 3D-R4C Disposition

**`PAC_AUTH_CONTEXT_UNAVAILABLE` — stop before fresh environment reconciliation or package push.** The active local PAC profile is labeled `O-SR-port` and names VN LMV IT as its environment. Its reported token expiry is 24 October 2026, before this continuation on 25 October. The mandatory fresh `pac org who` verification was not run after the expired-token indication. No interactive login, PRT launch, PAC profile selection, or environment switch was attempted.

The frozen local package remains at the approved path and its SHA-256 (`41a18a66aabf0c75356209e6814d93f60aa6d4dc2eebd3a965d9291b3bb8b59b`) and contained DLL SHA-256 (`ba332f58c55c8c13b8eb44df619b8236022f78261b7a02099890b3281a88aaf1`) match the retained R4 artifact. This local check does not establish live package state. The R4B section below records one package row and generated assembly/types; the R4C authorization text says those generated components were not produced by raw package-row creation. Because the authentication gate failed, this discrepancy was not rechecked live. Do not repeat package creation or push until a valid PAC context allows fresh read-only reconciliation.

| R4C action | Count / disposition |
|---|---|
| Local artifact check | Frozen package and DLL hashes exact; artifact not rebuilt |
| Fresh `pac org who` / live metadata reconciliation | Not performed after expired-token indication |
| PAC auth-who profile inspection | Target profile identified; tool does not expose a reliable GET count |
| Fresh package / assembly / type / API / Solution reads | Not performed |
| Raw PluginPackage POST | 0 |
| `pac plugin push` | 0 |
| Custom API handler PATCH / rollback PATCH | 0 / 0 |
| Business API invocations / business-data writes | 0 / 0 |
| Legacy assembly / schema / app writes | 0 / 0 / 0 |
| Automatic retries | 0 |
| Package-backed assemblies / plug-in types observed in R4C | Not queried |
| Commit / push | 0 / 0 |

The auth-who tool's underlying GET count is unknown; no deployment or runtime runner GET was dispatched. Primary result is `PAC_AUTH_CONTEXT_UNAVAILABLE`. Resume only with an already-approved, non-interactive PAC context and fresh target/identity confirmation. See [Current State](CURRENT_STATE.md).

Offline validation: all 10 existing PowerShell suites passed (1,094 assertions); the Candidate Core engine harness passed 79 assertions; the SDK adapter/guard harness passed 56 assertions; the package artifact suite passed 12 assertions; and the R4B deployment-contract suite passed 23 assertions. All 20 PowerShell files parsed, the added-line privacy scan passed, 58 relative links in the modified documents resolved, and `git diff --check` passed. No dedicated PAC NuGet push command-plan test exists in the current test tree; the R4B deployment-contract suite covers the prior direct Web API upload path, not `pac plugin push`. No package rebuild or tenant operation was performed during validation.

## Latest Phase 3D-R4B Disposition

**`PLUGIN_PACKAGE_PROCESSING_FAILED` — stop before Custom API handler cutover or runtime acceptance.** After the fresh read-only gates passed, the guarded direct Web API runner dispatched one authorized package POST. Immediate GET reconciliation found exactly one package record and verified its name, unique name, version, and approved Solution membership. Both the collection GET and a later strong-consistency direct GET returned no nonempty `content`, so the frozen package SHA-256 could not be verified. Live metadata reports the Content column as valid for read; the missing GET value is an unresolved content-reconciliation gap, not proof that the content was absent or incorrect. Microsoft's [Plugin Package table reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/pluginpackage) also lists Content as a readable column.

### Package processing evidence

The read-only post-stop inspection confirmed:

| Check | Live result |
|---|---|
| Package record count | 1 |
| Package name / unique name / version | Exact: `os_sr_cact_pkg` / `os_sr_cact_pkg` / `1.0.0` |
| Approved Solution membership | Exact |
| PluginPackage entity set / primary ID | `pluginpackages` / `pluginpackageid` |
| Content field readback | No nonempty value from collection or direct GET; expected package hash not verified |
| Package-to-assembly relationship | One relationship; lookup attribute `packageid` |
| Generated assembly | One `os_sr_cact`, version `1.0.0.0` |
| Assembly SourceType | `File Store` |
| Generated plug-in types | Exactly `os_sr_cact.ApplyCandidateAction` and `os_sr_cact.ProtectCandidateCore` |

The expected package SHA-256 remains `41a18a66aabf0c75356209e6814d93f60aa6d4dc2eebd3a965d9291b3bb8b59b`; the contained DLL SHA-256 is `ba332f58c55c8c13b8eb44df619b8236022f78261b7a02099890b3281a88aaf1`. The live record did not expose a content value to hash, so neither exact package-content identity nor full package reconciliation is claimed. Generated assembly/type evidence confirms package processing, but does not satisfy the missing content fingerprint gate.

### Fresh gates, writes, and acceptance boundary

The new read-only R4B preflight returned `PLUGIN_PACKAGE_PREFLIGHT_READY`. Its initial JSON total was 626 GETs, but that aggregate omitted the strict legacy runner's separately reported 77 storage-gate GETs. Corrected accounting is 703 GETs: 63 package-runner, 508 strict legacy/API/guard, 77 strict storage-gate, 46 separate storage, and 9 fresh zero-row runtime-gate GETs. It verified the exact package was absent before Apply and all four business/evidence table counts were 0. It made 0 POST/PATCH calls and 0 retries. The deployment runner's aggregate count was corrected locally to include the nested storage gate.

The Apply run made 705 GETs in aggregate: 65 package-runner, 508 strict legacy/API/guard, 77 strict storage-gate, 46 separate storage, and 9 zero-row-gate GETs. The package-runner failure JSON reported only its own 65 GETs; the aggregate includes the separately counted sub-runner GETs. It dispatched exactly one `POST pluginpackages`, then stopped on the absent content readback.

| R4B action | Count / disposition |
|---|---|
| Fresh package preflight | 703 corrected GETs; package absent; 4 business/evidence counts 0 |
| Apply read-only gates | 705 aggregate GETs; strict legacy baseline exact before create |
| Package create | 1 POST; one package record and generated assembly/types found |
| Content fingerprint reconciliation | Not proven; no nonempty content returned |
| Custom API handler PATCH | 0 |
| Rollback PATCH / package delete | 0 / 0 |
| Post-stop GET-only reads | Package inspection: 11 GETs; generic strict reconciler: 255 direct + 77 storage-gate GETs, stopped because its global inventory expects one assembly; expanded targeted inspection: 66 GETs; follow-up including direct package GET: 67 GETs |
| Post-stop exact handler check | API contract exact; API still points to legacy handler; legacy assembly hash and all 50 guard steps exact |
| Total post-stop GETs | 476; 0 POST/PATCH |
| Final fresh preflight + Apply + post-stop GET total | 1,884 |
| Runtime Custom API invocations | 0 |
| Candidate / Call Log / History / Receipt business writes | 0 |
| Automatic retries | 0 |
| Organization auditing, schema, Choices, security, app, publication | No changes |
| Commit / push | 0 / 0 |

The package remains in the approved Solution. The one-shot deployment journal records the package POST dispatch; do not retry or delete the package. The API-handler cutover was not attempted, and runtime acceptance was not started. No synthetic Candidate was created. The older generic reconciler stopped because it expects one total assembly and now sees the legacy plus package-generated assembly. A separate targeted GET-only inspection confirmed the API contract, legacy handler mapping, legacy assembly hash, and guard-step topology after the package POST.

Local validation after these code changes: all 10 PowerShell suites passed 1,094 assertions; the Candidate Core operation-engine harness passed 79 assertions; an existing offline Candidate Core SDK adapter/guard executable passed 56 assertions and was not rebuilt because the strong-name key remains unapproved. All 20 PowerShell files under `scripts/` and `tests/` parsed with zero errors; the added-line privacy scan passed; 76 relative Markdown links resolved; and `git diff --check` passed. The new [R4B deployment assertions](../tests/Phase3DR4BPluginPackageDeployment.Tests.ps1) include 23 checks; the runtime contract suite passed 18 checks. The package artifact itself was not rebuilt in this continuation; the frozen package and DLL hashes remain the previously verified local artifact values.

The repository remains on branch `main` at HEAD `cff0033`; the R4B runner, tests, and documentation changes are uncommitted. No commit or push was made.

Next work is read-only investigation of a supported way to reconcile `pluginpackage.content`. Preserve the created package and all existing mappings. No second package POST, delete, handler PATCH, runtime API call, or other tenant write follows from this stop result. See [Current State](CURRENT_STATE.md) and [test guide](../tests/README.md).

## Historical Phase 3D-R4 PRT Authentication Stop (2026-10-25; superseded by R4B)

**`PLUGIN_PACKAGE_CREATE_BLOCKED_AUTH` — stop before package registration, Custom API handler cutover, or runtime acceptance.** The unsigned package artifact is locally built and verified. Fresh Candidate Core and zero-row gates passed; the approved package is absent by exact-name query. PRT was installed, but its single current-user login attempt failed before organization selection. No tenant mutation or API invocation was dispatched.

### Local package artifact

| Item | Result |
|---|---|
| Package project | [CandidateCore.Package.csproj](../solutions/CandidateCorePackage/CandidateCore.Package.csproj), SDK-style .NET Framework 4.6.2 |
| Package identity | `os_sr_cact_pkg`, version `1.0.0` |
| Contained assembly identity | `os_sr_cact`, version `1.0.0.0`, unsigned / no public-key token |
| Included plug-in types | `os_sr_cact.ApplyCandidateAction`; `os_sr_cact.ProtectCandidateCore` |
| Package contents | One `lib/net462/os_sr_cact.dll` plus NuGet metadata; no PDB, key, or additional assembly |
| Package SHA-256 | `41a18a66aabf0c75356209e6814d93f60aa6d4dc2eebd3a965d9291b3bb8b59b` |
| Contained DLL SHA-256 | `ba332f58c55c8c13b8eb44df619b8236022f78261b7a02099890b3281a88aaf1` |
| Repeatability | Clean Release build and subsequent build both succeeded with 0 warnings / 0 errors and identical package SHA-256 |
| Legacy signed local assembly | Remains `os_sr_cact` v1.0.0.0, token `d73b02688ba7f9aa`, SHA-256 `089deb40816e7fd6d80d117ba3894b5d5dadbcf65ac8111e25bb0520ff6feb85`; unchanged for rollback |

The package test is [Phase3DR4PluginPackage.Tests.ps1](../tests/Phase3DR4PluginPackage.Tests.ps1): it verifies project/package identities, exact package entries, no signing material, unsigned assembly identity, and both contract types using local reflection. It passed 12 assertions. All nine PowerShell suites passed 1,070 assertions; the Candidate Core operation-engine suite passed 79 assertions. The package links the current Candidate Core source without modifying it.

### Registration stop and exact boundary

PAC CLI is version 2.13.1. The [PAC plug-in command reference](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/plugin) shows that `pac plugin push` requires `--pluginId` (an assembly or package ID), but does not establish that an arbitrary new ID creates a first-time package. Microsoft's [PAC CLI package guide](https://learn.microsoft.com/en-us/power-platform/developer/howto/cli-create-package) documents first-time registration through the Plug-in Registration Tool and selection of an existing Solution. PRT 9.1.0.235 was installed locally and opened. Two current-user sign-in attempts (standard Office 365 followed by OAuth) returned a generic login error before organization selection. No credentials were entered, no error log was inspected, and no further authentication retry was made. PAC's existing profile remained unchanged and PAC `org who` continued to verify the expected VN LMV IT organization and user. Because no authenticated PRT session was available and first-time PAC push semantics were not verified, no package ID was guessed and no upload was attempted.

### Fresh deployment and runtime gates

Immediately before the PRT registration attempt, the existing strict reconciler returned `CANDIDATE_CORE_ASSEMBLY_RECONCILED`: 508 GETs (77 storage-gate GETs), 0 POST, 0 PATCH, 0 retries. Storage, Solution/Publisher, API/privilege, assembly, and registration inventory matched the retained exact plan and dispatch evidence. The separate runtime preflight returned `PHASE_3D_RUNTIME_PREFLIGHT_READY`: 9 count-only GETs; Candidate, Call Log, History, and Receipt rows were each 0; API invocations, business writes, audit-setting writes, and retries were all 0. A targeted live FetchXML query filtered the `pluginpackage` table to the exact approved name `os_sr_cact_pkg` and returned no row. PRT authentication failed before selecting an organization, so it did not alter or register a Dataverse component.

| R4 action | Count / disposition |
|---|---|
| Local package builds | 2 successful Release builds; 0 warnings / 0 errors |
| Package assertions | 12 passed |
| All PowerShell suites | 9 suites; 1,070 assertions passed |
| Candidate Core operation-engine suite | 79 assertions passed |
| Fresh registration/storage reconciliation | 508 GETs, including 77 storage-gate GETs; 0 POST/PATCH; exact match |
| Fresh runtime count preflight | 9 GETs; all four business/evidence counts 0 |
| Exact-name package query | 1 targeted FetchXML operation; no matching row |
| PAC / PRT operations | PAC 2.13.1 profile/WhoAmI verified; PRT 9.1.0.235 installed; 2 login failures before organization selection |
| Package create/upload dispatches | 0 |
| Package Solution-membership writes | 0 |
| Custom API handler patches | 0 |
| Plug-in type/step or legacy assembly changes | 0 |
| Runtime API invocations / business-row writes | 0 / 0 |
| Automatic retries | 0 |
| Commit / push | 0 / 0 |

No package component or handler mapping is treated as deployed. The package-name query establishes no matching row at query time; it does not establish that other package records are absent.

The existing legacy `ProtectCandidateCore` registrations and signed assembly were not changed. Any later package cutover must freshly reconcile guard-step topology and preserve the approved direct-write protections. Only after supported first-time package registration, exact Solution membership/type reconciliation, and fresh API/step baseline should the single authorized `PluginTypeId` handler cutover be considered. No schema, Choice, API signature, security, app, organization-audit setting, or publication change is in scope.

### Repository and acceptance status

Starting repository baseline: branch `main`, HEAD `7ee75166a654ddafc24133fa51cc8dafdd9bebcc`. R4 work remains uncommitted; no commit or push was made. The only R4 repository changes are the package project, package assertions, and existing Phase 3D/current-state/test-guide documentation. Local package artifact output is build output only.

The final R4 result is an authentication stop, **not** a failed or uncertain tenant write. The R3 signing-key classification remains `SIGNING_KEY_ACL_NOT_APPROVED` for the old individually signed build path; the key was not used. The future package registration is a separate dependency. No live runtime acceptance is claimed.

## Historical Phase 3D-R3 Disposition

**`SIGNING_KEY_ACL_NOT_APPROVED` — stop before build, fresh live pre-deployment reads, assembly deployment, or runtime acceptance.** The extra inherited `FullControl` principal resolves to a disabled local account, but its organizational/build trust cannot be established. It is classified `UNRESOLVED_PRINCIPAL`; disabled status and local-account resolution do not establish trust.

### Repository and source baseline

The read-only baseline was branch `main`, HEAD and `origin/main` `4858c77b05ae38e14266ec5685dabd8f460115d7` (2026-10-25 12:01:09 +07), with a clean worktree before this documentation update. The committed source already contains the approved optional/null/empty-Guid `CandidateId` CreateCandidate handling and its regressions. No source or test code changed in this continuation.

The signing-key reference is the retained session artifact `phase3c-plugin-signing.snk`; the tracked-safe reference is `session-state/files/phase3c-plugin-signing.snk`. Reference-string SHA-256: `b1d05fbb1b87ad61` (this is a hash of the normalized reference string, not of the key). Key bytes were not read, copied, exported, or hashed.

### Sanitized ACL and provenance

The key owner resolved to the current authorized user. ACL inspection found inherited `Allow / FullControl` entries for SYSTEM, local Administrators, the current authorized user, and one additional disabled local account. The additional account's SID is withheld; its non-reversible reference is `828623bbe96d3f20`. Its ACE is inherited from an explicit ACL on a common profile-root ancestor; the exact path is suppressed. No ACL, account, group, membership, or ownership change was made.

| Principal | ACE | Provenance / disposition |
|---|---|---|
| SYSTEM (`S-1-5-18`) | Allow / FullControl; inherited | Built-in system principal; exact inheritance source not retained |
| Local Administrators (`S-1-5-32-544`) | Allow / FullControl; inherited | Local administration group; exact inheritance source not retained |
| Current authorized user (SID suppressed) | Allow / FullControl; inherited; owner | Resolved to the current operator; exact inheritance source not retained |
| Additional disabled local account (SID reference `828623bbe96d3f20`) | Allow / FullControl; inherited | ACE is explicit at a common profile-root ancestor; trust unresolved |

No Deny ACE was observed in the inspected key ACL.

Because the additional principal cannot be conclusively classified as trusted, the existing key is not approved for use. No attempt was made to change ACLs, disable inheritance, take ownership, or create/use a replacement key.

### Strong-name identity and stop boundary

The existing local `os_sr_cact.dll` was inspected read-only: assembly name `os_sr_cact`, version `1.0.0.0`, public-key token `d73b02688ba7f9aa`, SHA-256 `089deb40816e7fd6d80d117ba3894b5d5dadbcf65ac8111e25bb0520ff6feb85`. This matches the previously reconciled deployed binary's public identity and hash; it does not authorize use of the private key. No signed build was attempted, so corrected-binary signing, test results against a signed build, and corrected DLL hash remain unavailable.

| R3 activity | Result |
|---|---|
| Signing-key ACL / identity resolution | Read-only; additional account trust unresolved; key use not approved |
| Candidate Core source / expected identity | Existing optional `CandidateId` correction retained; expected token matches inspected local assembly |
| PowerShell suites | 8 suites; 1,058 assertions passed |
| Candidate Core operation tests | 79 assertions passed |
| Parser / `git diff --check` before documentation edits | Passed |
| Fresh live pre-deployment GETs / tenant operations | 0 / 0 |
| Signed build / corrected DLL hash | 0 / unavailable |
| Assembly update | 0 |
| API/schema/app/security/audit/publication writes | 0 |
| Business API invocations / business-row writes | 0 / 0 |
| Automatic retries | 0 |
| Commit / push | 0 / 0 |

The next architectural option, `MIGRATE_INDIVIDUAL_ASSEMBLY_TO_PLUGIN_PACKAGE`, is recorded only as a future proposal; no migration or deployment-model change was made. Resume only under a separately authorized and approved protected signing mechanism. Do not alter this key's ACL or use it based on the unresolved account.

## Latest Phase 3D-R2 Disposition

**`SIGNING_KEY_UNAVAILABLE` — no build, tenant read, assembly update, or runtime request was made in this continuation.**

### Baseline and defect assessment

At R2 start the repository was `main`, clean, and at HEAD/origin/main `b90d25bc29ffb1a75e5be7bc8f07c91b5315a526` (2026-10-25 07:43:18 +07). The Candidate Core manifest remained `63f56173f61265f539d23d6ceffb5631e23f438e4e254755c1e24c7d17eb1915`. The deployed assembly remained the previously reconciled `os_sr_cact`, version `1.0.0.0`, hash `089deb40816e7fd6d80d117ba3894b5d5dadbcf65ac8111e25bb0520ff6feb85`. Expected public-key token: `d73b02688ba7f9aa`.

The approved API contract file marks `CandidateId` optional (`optional: true`); the prior Phase 3C deployment report records that only `ActionType` and `CorrelationId` were metadata-required. R2 did not perform a fresh live metadata read because the mandatory signing-key safety gate failed first. The previous runtime request failed with HTTP 400 / `0x80040265` / `UNEXPECTED_INPUT`. The former handler rejected CreateCandidate if the optional `CandidateId` key was present, even with a null value. That source path is a strong, plausible root cause for the observed error, but the live response alone does not identify the offending input with certainty.

The local handler now applies these CreateCandidate rules:

| Input | Local behavior |
|---|---|
| CandidateId omitted | Accepted |
| CandidateId null | Accepted |
| CandidateId empty Guid | Treated as the empty optional representation |
| CandidateId non-empty valid Guid | Rejected as `UNEXPECTED_INPUT`, preserving the approved Create semantics |
| CandidateId wrong type | Rejected deterministically as `INVALID_CANDIDATEID` |
| Unknown parameter / missing required name or email | Rejected; invalid requests do not mutate the store |

The regression tests also verify audit-inactive synthetic CreateCandidate behavior and preserve existing operation, replay, transaction, actor, and fail-closed transition tests. This local source is not built or deployed.

### Signing boundary and stop

The previously retained signing artifact was found by its session-artifact name, but its inherited ACL granted FullControl not only to the current user, SYSTEM, and local Administrators, but also to an additional principal that could not be verified as part of the approved signing boundary. The key owner also did not resolve to an approved category. No key bytes were read, no permissions were changed, and no alternate or replacement key was generated. The key therefore was not used. Per the owner instructions, stop classification is `SIGNING_KEY_UNAVAILABLE`.

The source fingerprint for `solutions/CandidateCore/Operation.cs` after the local correction is `772e2d443a240d377f5a568b357f60e3e907cb7da33c362f78f3d7c7c2936dd4`; Candidate Core test source fingerprint is `b5648cc1111b2d9552474af6caf608bf3bdf61d52864009291841299880f0d1b`. The corrected DLL hash is unavailable because it was not built. Strong-name identity continuity, current live API optionality, and deployment reconciliations were therefore not tested in R2.

| R2 activity | Result |
|---|---|
| PowerShell suites before deployment | 8 suites, 1,058 assertions passed |
| Candidate Core operation tests | 79 assertions passed |
| Parser / `git diff --check` | Passed |
| Fresh live pre-deployment reads | 0 |
| Plug-in build / corrected DLL hash | Not attempted / unavailable |
| Assembly update | 0 |
| API metadata / schema / app / role / audit-setting / publication writes | 0 |
| CreateCandidate / other business API invocations | 0 / 0 |
| Business-row creates / cleanup deletes | 0 / 0 |
| Automatic retries | 0 |
| Commit / push | 0 / 0 |

The changes now in the worktree are limited to the CreateCandidate optional-input correction, its tests, and this report/Current State update. HEAD remains unchanged; no commit or push was made. Do not alter the key ACL, use this key, deploy the local binary, or consume another runtime attempt without an approved protected signing mechanism and the applicable bounded authorization.

## Latest Phase 3D-R Continuation Disposition

**`PHASE_3D_RUNTIME_STOPPED` — the first live Custom API request was definitively rejected; runtime acceptance is incomplete.** No retry or further dispatch was made after the rejection.

Fresh GET-only reconciliation matched the current Candidate Core manifest, storage, Operation Receipt and Active alternate key, Solution/Publisher, Custom API contract and privilege, plug-in types and registrations. It returned `CANDIDATE_CORE_ASSEMBLY_RECONCILED`, with assembly SHA-256 `089deb40816e7fd6d80d117ba3894b5d5dadbcf65ac8111e25bb0520ff6feb85`; organization auditing remains disabled. The approved audit-gate-decoupled assembly was already deployed, so this continuation dispatched no assembly update. The original consumed Phase 3D lock was preserved.

The repository baseline was `main`, HEAD and `origin/main` both `ef5b512e33e38f08fece1db439558afd029e8baf` (2026-10-24 20:50:38 +07), with manifest SHA-256 `63f56173f61265f539d23d6ceffb5631e23f438e4e254755c1e24c7d17eb1915`. The worktree was clean at the start; the six current changes are limited to the Phase 3D report/current state, guarded deployment error reporting, the runtime runner, and its offline assertions. No commit or push occurred. The local plug-in source already lacks the organization-audit runtime rejection; no source rebuild or assembly update was needed for this continuation.

Immediately before Apply, a fresh guarded preflight returned **9 GETs**, zero Candidate, Call Log, Candidate Status History, and Operation Receipt rows, zero API invocations, and zero retries. The new authorization-specific lock/evidence identity was unused; a distinct lock was created without changing the historical lock.

The runner dispatched **one** `CreateCandidate` Custom API request. Dataverse returned HTTP 400, error code `0x80040265`, `UNEXPECTED_INPUT`. The request was rejected; no further action in the matrix was sent. A subsequent guarded count-only preflight returned **9 GETs** and zero rows in all four tables. No Candidate ID or other business-record identifier was created or retained. Organization auditing was not changed.

| Evidence | Phase 3D-R result |
|---|---|
| Current assembly reconciliation | `CANDIDATE_CORE_ASSEMBLY_RECONCILED`; 508 GETs, including 77 storage-gate GETs; 0 POST/PATCH |
| Earlier read-only reconciliation diagnostic | 257 GETs; stopped locally on an omitted expected plan fingerprint; 0 writes |
| Organization auditing | Disabled; unchanged; external governance/release prerequisite, not a runtime gate |
| Pre-Apply zero-row gate | 9 GETs; all four row counts 0 |
| Custom API dispatch | 1 `CreateCandidate`; HTTP 400; `0x80040265`; `UNEXPECTED_INPUT` |
| Other Custom API dispatches | 0; the rest of the matrix was not reached |
| Post-rejection zero-row gate | 9 GETs; all four row counts 0 |
| Successful business-data writes / resulting rows | 0 / 0 |
| New authorization-specific one-shot guard | Consumed; preserved |
| Prior Phase 3D one-shot guard | Preserved; not reused |
| Automatic retries / resends | 0 / 0 |
| Metadata, app, role, audit-setting, publication writes in this continuation | 0 |

The runtime dispatch journal records the request as `REJECTED` with HTTP 400, but its `ResultCode` is null because the runner's allowlist did not yet include `UNEXPECTED_INPUT`. The sanitized command result captured that Dataverse code. The local allowlist was updated afterward; the retained journal was not rewritten. The GET figures above are per captured operation result; diagnostic preflight invocations whose wrapper output was not preserved are not included in an aggregate total.

The local runner and contract assertions now reflect the authorized **eight-dispatch** matrix and expected maximum effects of one Candidate, two Call Logs, two History rows, and four Receipts (nine total rows). This describes the bounded test plan, not live acceptance: execution stopped at the first rejected request. `MarkRound1Scheduled` and the remaining scheduled/result/reschedule checks were not invoked. Offline operation tests verify the scheduler evidence rejection and the result/reschedule evidence guards; the latter actions are `NOT_APPLICABLE_CURRENT_STATE` live because no Candidate was created. Non-admin user/role acceptance remains deferred to the Candidate UI + Security phase.

Do not remove either lock, recreate or reuse the evidence file, or rerun Apply. The rejected request was not resent. Further live acceptance requires a separately bounded authorization after the `UNEXPECTED_INPUT` request-contract/runtime boundary is diagnosed. No cleanup or speculative request was attempted.

### Local Validation in This Continuation

After the rejection, local inspection found a plausible contract-boundary defect: `CandidateId` is an optional Custom API input, but `ActionRequest` rejected CreateCandidate whenever the input dictionary contained the key, including when Dataverse supplied it as null. The local implementation now rejects only a non-null CandidateId on CreateCandidate, with offline tests for both null acceptance and non-null rejection. This is a narrowly scoped local correction, not deployed; the live 400 does not identify which individual input caused `UNEXPECTED_INPUT`, so the diagnosis remains to be confirmed by a separately authorized deployment/runtime attempt.

All eight PowerShell suites passed **1,057 assertions** before the local root-cause correction; after correction, the focused Phase 3D suite passed **17 assertions** and the Candidate operation engine passed **72 assertions**. `git diff --check` and PowerShell parsing passed. The Candidate Core SDK adapter test could not build in this session because no protected `CandidateSigningKey` was configured; no signing material was searched for or exposed. The full PowerShell suites were not rerun after the last targeted correction. These local checks do not establish live operation acceptance.

The local correction does not authorize another assembly update or runtime dispatch. The prior assembly update and authorization-specific one-shot runtime request have already been used; preserve both locks/journals and do not retry or deploy without fresh bounded owner authorization.

The sections below preserve earlier assessments. The former `UNCERTAIN_WRITE_OUTCOME` disposition is superseded by this definitive HTTP 400 rejection; the original `TRANSITION_CONTRACT_FAILURE` is also historical.

## 1. Executive Summary (Historical pre-runtime assessment)

**`TRANSITION_CONTRACT_FAILURE`**

No Candidate fixture or business API invocation was made. Fresh metadata reconciliation passed, but execution must stop before data creation because the deployed operation rejects all business operations while organization auditing is disabled, the requested booking/result/reschedule paths are intentionally fail-closed in the approved contract, and no approved cleanup mechanism is established for records protected by the direct-write guards and restrictive relationships. The classification denotes an acceptance-scope incompatibility, **not a confirmed runtime defect**.

The user authorized synthetic data despite pending organization-level audit activation. That authorization does not authorize bypassing the deployed audit gate, changing plug-in behavior, weakening write guards, or leaving synthetic history behind. The approved API and deployment remain unchanged.

## 2. Repository / Manifest Baseline (Historical)

| Item | Observed |
|---|---|
| Repository / branch | BSO-RS-Support / `main` |
| HEAD | `9e15357ffef1ba011f65053f61c48047050ba68f` |
| HEAD timestamp | `2026-10-24T19:14:02+07:00` |
| `origin/main` | Same as HEAD at inspection |
| Initial worktree | Clean |
| Candidate Core manifest SHA-256 | `63f56173f61265f539d23d6ceffb5631e23f438e4e254755c1e24c7d17eb1915` |
| Receipt contract SHA-256 | `f26116c87e62c3a2faeecdf5e0a63a0ceef20069bdb78d36d9386a73dfed2efc` |
| API contract SHA-256 | `a6f8295df1f72a160c0490b49d457d7c0a6d82e23a3fcac8f1a68aa66b6bbaa9` |

No fetch, commit, push, branch change, or deployment-plan change was made. This report and the synchronized current-status documentation are the only intended repository edits for this run.

## 3. Environment / Identity

The fresh guarded reconciliation matched the owner-authorized VN LMV IT target, the active PAC context, the Dataverse WhoAmI identity, and the process-scoped expected-user guard. Identity values, organization URL, and tenant/environment identifiers are intentionally omitted.

The Power Platform CLI read-only authentication/profile, environment table inventory, Solution inventory, and security-role inventory commands were also used. The profile output contained personal/tenant identifiers and is not reproduced here.

## 4. Live API / Plug-in Baseline (Historical Phase 3C baseline)

Fresh GET-only reconciliation confirmed the existing Candidate Core tables, Operation Receipt and Active alternate key, assembly and types, 50 registration steps, Custom API, all request/response metadata, `ExecutePrivilegeName=prvWriteos_sr_cand`, and Solution membership. The final result remained `CANDIDATE_CORE_API_DEPLOYED_AUDIT_ACTIVATION_PENDING`; no drift was found and nothing was redeployed.

The Phase 3C baseline assembly SHA-256 was `f11d6db0db3a190806ef48daa46a3f3b6befbf7070f236bac5a44b6e40598f0f`; it was superseded by the Phase 3D-R assembly recorded above. The API is the private unbound `os_sr_cact` Action implemented by `os_sr_cact.ApplyCandidateAction`.

## 5. Organization Audit State (Historical pre-correction assessment)

At the time of the historical pre-correction assessment, organization-level auditing was disabled and the earlier assembly enforced an audit runtime gate. The current assembly no longer rejects solely for this setting. Table audit metadata is not a substitute for organization-level audit activation, which remains externally pending.

The owner authorized the bounded synthetic test while this condition remains pending. No audit setting was changed. The later `UNEXPECTED_INPUT` rejection is separate from organization audit state.

## 6. Synthetic Reference Fixtures

The current manifest makes Position and Candidate Source optional for Candidate creation; the TA lookup is conditional before booking. No reference fixture is required for the supported create/call slice. Booking is unavailable in the current API contract. No reference rows were created.

## 7. Candidate Fixture Creation

Candidate A created: **0**. Candidate B created: **0**. No synthetic names, email addresses, or other candidate fields were submitted to Dataverse.

## 8. AutoNumber Runtime Result

Not tested. `AUTONUMBER_RUNTIME_GENERATION_VERIFIED` is **not** claimed.

## 9. RecordCall - No Answer

Not invoked. No Call Log or Operation Receipt was created.

## 10. Identical Replay

Not invoked live. Offline engine assertions cover persisted-result replay, but do not establish deployed Dataverse behavior.

## 11. Conflicting Replay

Not invoked live. Offline engine assertions cover conflicting reuse and uniqueness races; they do not establish deployed Dataverse behavior.

## 12. RecordCall - Answered

Not invoked. Candidate transition, Call Log, History, actor, and receipt effects have no live acceptance evidence from this run.

## 13. Normal Transition Path

No live transition was attempted. `ProceedToScheduling` is present in the current API contract, but organization auditing is disabled and the deployed code fails closed before business effects.

The requested Waiting Manual Scheduling to Round 1 Scheduled success path is not currently supported: `MarkRound1Scheduled` requires trusted scheduler evidence which the deployed API does not accept.

## 14. Reschedule

Not invoked. The approved design and frozen API contract explicitly defer `RequestReschedule` until the later cancellation-attempt evidence boundary exists. The Phase 3D requested success expectation conflicts with that approved fail-closed behavior. No calendar call or cancellation was attempted.

## 15. Stale-State Rejection

Not invoked live. Existing offline assertions verify stale expected status and row-version rejection in synthetic adapters only.

## 16. Offer Extended Terminal Path

Not tested live. The deployed API requires trusted result evidence for `RecordPass`; it remains unavailable in the current contract. No terminal status or rollback request was made.

## 17. Candidate Failed Terminal Path

Not tested live. The deployed API requires trusted result evidence for `RecordFail`; it remains unavailable in the current contract. No terminal status or rollback request was made.

## 18. Transaction / Atomicity Evidence

No live operation was dispatched, so transaction atomicity is **not verified**. Offline host rollback simulations and SDK adapter tests are synthetic unit evidence only.

## 19. Actor Semantics

No live business actor or child row was produced. Caller-context/initiating-user behavior has metadata and offline harness evidence, not live Phase 3D acceptance evidence.

## 20. Operation Receipt Evidence

No receipt row was created or read for this run. Receipt schema and Active uniqueness key remain reconciled; live replay and receipt privacy/result behavior were not exercised.

## 21. Non-admin Test-User Discovery

**`NON_ADMIN_TEST_USER_NOT_AVAILABLE`** for this acceptance run. The available CLI role inventory is not a user/licensing enumeration and does not establish a suitable licensed non-admin Candidate caller. No user identity was selected, disclosed, or granted access. No security change occurred. This classification does not claim that the environment contains no non-admin users.

## 22. Synthetic Cleanup

No rows were created, so cleanup actions dispatched: **0**.

Before creating fixtures, source review established that Candidate Core direct Create/Update is accepted only under the exact validated `os_sr_cact` parent operation; direct Delete/DeleteMultiple is rejected by the deployed guard. Candidate-to-Call/History relationships use restrictive deletion, and there is no approved delete operation in the Custom API. The repository/tooling inspected did not establish a narrowly scoped approved administrative cleanup mechanism that bypasses those protections. No plug-in bypass or alternate delete path was attempted.

## 23. Post-Cleanup Verification

No cleanup was needed. Four sequential count-only FetchXML queries returned **0** for Candidate, Call Log, Candidate Status History, and Operation Receipt. The metadata/API reconciliation was read-only and exact. These are fresh pre-test counts; they do not represent cleanup of this run's records.

## 24. Request / Business Write Counts

| Category | Count |
|---|---:|
| Guarded instrumented GETs (deployment/storage reconciliation) | 335 |
| Count-only FetchXML queries | 4 |
| Custom API invocations | 0 |
| Candidate / Call Log / History / Receipt business writes | 0 |
| Reference-data writes | 0 |

The 335 GET total is the runner's instrumented Web API count (258 registration/identity plus 77 storage-gate reads). Tool-mediated CLI internals and PAC/authentication informational reads are not included in that count.

## 25. Metadata Write Counts

| Category | Count |
|---|---:|
| Schema / Choice / relationship / key writes | 0 |
| Plug-in deployment writes | 0 |
| Custom API / parameter / response writes | 0 |
| App writes | 0 |
| Role / team / security writes | 0 |
| PublishXml / PublishAllXml | 0 / 0 |
| Automatic retries | 0 |

## 26. Retry vs Explicit Replay Counts

Transport retries: **0**. Explicit replay-test API calls: **0**. Conflicting-replay API calls: **0**. No business operation was invoked.

## 27. Offline / Regression Results

All nine local suites passed, **1,157 assertions**:

| Suite | Assertions | Result |
|---|---:|---|
| Phase 3A design | 46 | PASS |
| Phase 3B.2 provisioning | 50 | PASS |
| Reference provisioning | 550 | PASS |
| Readiness | 11 | PASS |
| Model-driven app composition | 329 | PASS |
| Phase 3C receipt contract | 27 | PASS |
| Phase 3C deployment contract | 23 | PASS |
| Candidate operation engine | 68 | PASS |
| SDK adapter / guards | 53 | PASS |

Passing offline tests do not prove live Custom API execution, organization transaction behavior, effective non-admin privileges, AutoNumber generation, or live cleanup.

## 28. Files Changed

- This report.
- [Current State](CURRENT_STATE.md).
- [Master Production Rules](../MASTER_PRODUCTION_RULES.md).
- [Project Context](PROJECT_CONTEXT.md).
- [Implementation Plan](IMPLEMENTATION_PLAN.md).
- [Test Strategy](TEST_STRATEGY.md).
- [Security Model](SECURITY_MODEL.md).

No production source, contract, manifest, deployed metadata, or environment setting changed.

## 29. Final Runtime Classification

**`TRANSITION_CONTRACT_FAILURE`**

The Phase 3D acceptance requirements conflict with the currently approved/deployed fail-closed contract, and the audit gate prevents all business operations. No live behavior failure was observed because no business API was invoked. This result means **runtime acceptance not performed**, not that supported actions were proven broken.

## 30. UI / Security Readiness

**Not yet ready to claim `READY_FOR_CANDIDATE_UI_AND_SECURITY` under the Phase 3D exit rule.** No runtime acceptance passed, and no suitable non-admin caller was established. The deployed metadata is intact; the UI/security stage must not assume live business-operation acceptance.

## 31. Outstanding Governance Items

- IT/Compliance organization-audit activation, retention, access, capacity, and evidence governance remain pending.
- No approved least-privilege non-admin Candidate caller role/user acceptance is established.
- Trusted scheduler booking evidence, result evidence, and cancellation-attempt evidence remain future dependencies.
- A bounded, approved cleanup procedure for synthetic records protected by current guards must be established before any future fixture creation.

No audit, security, or product behavior settings were changed.

## 32. Exact Recommended Next Task

First reconcile the Phase 3D test matrix with the approved Phase 3C contract. Either:

1. keep booking/result/reschedule out of this acceptance until their trusted evidence boundaries are implemented and separately authorized; or
2. obtain explicit product/security approval for a changed contract and implement those evidence boundaries in a separately authorized phase.

Before creating any live fixtures, resolve organization auditing or obtain a separately approved test-only runtime approach that does not bypass the deployed fail-closed guard, establish an exact-ID cleanup method that preserves write protections, and verify a licensed non-admin test identity/role without granting access in this phase. Then issue a new bounded test authorization. Do not invoke production APIs or create records based on this report alone.

## 33. AI HANDOVER

Phase 3C metadata remains exact and deployed as `CANDIDATE_CORE_API_DEPLOYED_AUDIT_ACTIVATION_PENDING`. Current manifest, receipt contract, API contract, plug-in bytes, and registration metadata were not changed. Four business/evidence tables had zero rows in fresh count-only reads. This Phase 3D run created no fixtures and invoked no Custom API.

Do not report AutoNumber, live replay/conflict, transaction atomicity, actor, terminal-state, reschedule, or cleanup behavior as accepted. The current API intentionally rejects scheduler/result/reschedule actions until trusted evidence exists and rejects business execution while organization auditing is disabled. Next work is contract/governance/cleanup reconciliation, not a test-data retry.
