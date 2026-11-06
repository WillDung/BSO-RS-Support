# P0 Slice 2A bounded DEV provisioning reports

## Latest: runtime wiring deployed, feature off (2026-11-05)

**Classification:** `P0_SLICE_2A_RUNTIME_WIRING_DEPLOYED_FEATURE_OFF`. The DEV runtime components are deployed and wired, but the feature is still off. Availability has not been executed. This is not runtime, security or Production acceptance. Identity remains `DEV_FUNCTIONAL_IDENTITY_ELEVATED_NOT_SECURITY_ACCEPTANCE`.

**Remaining blocker:** `SLICE_2A_SYNTHETIC_MAILBOX_PREREQUISITE_MISSING`.

### Authorizations and preflight

The Technical Lead approved binding to two existing `Connected` connections owned by the current DEV owner:
- Office 365 Outlook (`shared-office365-…`)
- Microsoft Dataverse (`shared-commondataser-…`)

No new connection was created. Credentials, CA, consent, permissions and licensing were not changed.

A fresh GET preflight passed, and the writer repeated it immediately before dispatch. It confirmed:
- exact VN LMV IT and the unmanaged `os_sr_bso_rs_support` Solution, with 60 memberships;
- the complete `os_sr_avq` schema;
- the BSO role at its exact 65-entry map;
- the Availability Integration role at four Global privileges, unassigned;
- the Reference Admin role unchanged and unassigned;
- seven definitions, with no values;
- Candidate Core unchanged and all 50 legacy guards disabled;
- zero `os_sr_avq` rows;
- Console hashes unchanged;
- no prior `os_sr_avqg`, `os_sr_` connection references, Flows or custom connectors.

### Offline correction before build

The guard build failed its sandbox reference check. The cause is C# 14 first-class spans: they bound `.SequenceEqual` to `MemoryExtensions` and added a `System.Memory` reference. With Technical Lead approval (`fix_and_continue`), five call sites now use explicit `Enumerable.SequenceEqual`. A regression check was added for this.

The package was rebuilt outside the repository and verified before dispatch:

| Artifact | SHA256 |
|---|---|
| `os_sr_avqg_pkg.1.0.0.nupkg` | `ec596db5b07197f6dc4bf84e135ad6c05daccbed3412635c17057327892fa719` |
| `lib/net462/os_sr_avqg.dll` | `296634c9b75ca25977da33b1e623ab32b72495fd33e3c43c3649f33ea5f8ea01` |

The assembly identity is `os_sr_avqg` 1.0.0.0, unsigned. It references only Framework assemblies and `Microsoft.Xrm.Sdk`. Its single type is `os_sr_avqg.ProtectAvailabilityQuery`.

### Exact write requests

All writes were journaled and one-shot. Every write ran with the Solution header, `MaximumRetryCount 0`, and was acknowledged:

| # | Request | Result |
|---|---|---|
| 1 | POST `pluginpackages` `os_sr_avqg_pkg` 1.0.0 | 204; gate verified exactly one assembly, one type and **zero steps** before continuing |
| 2 | POST connection reference `os_sr_avchk_outlook_cr` ("BSO-RS Availability - Outlook", `shared_office365`) | 204 |
| 3 | POST connection reference `os_sr_avchk_dataverse_cr` ("BSO-RS Availability - Dataverse", `shared_commondataserviceforapps`) | 204 |
| 4 | POST `workflows` `os_sr_avchk` (category 5, "Slice 2A Availability Check", created in Draft/OFF) | 204 |
| 5 | POST WebResource `os_/bso/candidate-console-availability.js` | 204 |
| 6 | PATCH `os_/bso/candidate-console.html` (adds only the availability panel and its script tag) | 204 |
| 7 | `PublishXml` with exactly those two WebResources | 204 |

Totals: **7 writes**, **0 retries**, **0 rejected**.

**Publication scope:** two WebResources only. Not published: `srapp`, the sitemap, other WebResources, `PublishAllXml` and `pac solution publish`.

No guard steps were registered. No Flow activation or run took place.

### Flow `os_sr_avchk`

At deployment, [os_sr_avchk.clientdata.json](../solutions/AvailabilityQuery/os_sr_avchk.clientdata.json) (SHA256 `f901baae…8811`) matched the live clientdata. The offline hardening below changes the local file only; it is no longer asserted to match the deployed Flow.

The Flow runs these steps:
1. A Dataverse "Added" trigger on `os_sr_avq`, filtered to `Pending`, with Organization scope, run as the Flow owner, and concurrency 1.
2. Read the query; if it is not Pending, stop with no write.
3. Validate configuration.
4. Read the TA and optional Location, and capture a snapshot.
5. Validate the request.
6. Call `FindMeetingTimes_V2`: secured, no retry, PT2M timeout.
7. Validate the strict response shape. Keep free-only attendees: the TA must be `required` and `free`; for Onsite, exactly one `free` resource.
8. Normalize to canonical 15-minute UTC slots, with lead, business-hours, same-local-date, count and size checks.
9. Re-read the references.
10. Apply the `REFERENCE_CHANGED` override.
11. Write the six result fields once with `UpdateOnlyRecord`.

The deployment-time source secured the reference reads and provider call. The Flow does not use Candidate, Candidate Core, `os_sr_intv`, Status History, Operation Receipt, events, email, Teams or Graph connectors.

**Interpretation:** the drift override applies only after reference validation has produced a snapshot. Otherwise, pre-validation errors such as `TA_INACTIVE` would always become `REFERENCE_CHANGED`.

**First-activation gates.** These are unverified because the Flow has never run:
- the type of the Number environment-variable parameters (declared `Float`, converted to `int`);
- `sort()` and compact `string()` serialization of arrays;
- null-safety under non-lazy `if`/`and`;
- obscuring of variables and loops in run history.

The guard remains the server-side backstop that re-validates every slot. The Flow is **untested**, and it cannot be activated until the seven definitions have approved values.

### Offline Flow hardening and pre-activation verification (2026-11-06)

**Local classification:** `P0_SLICE_2A_OFFLINE_FLOW_HARDENING_COMPLETE`. This describes source and offline regression readiness only. The deployed VN LMV IT Flow remains unchanged and OFF; no Flow update, activation, publish, tenant access, provider call or mailbox access occurred.

The Flow source now applies action-level secure inputs/outputs at each sensitive boundary: query/reference reads; TA and Location snapshot setters; validation expressions that consume mailbox addresses; Outlook response validation; the suggestion loop and attendee filters; observation and slot construction; reference rereads/comparisons; and terminal result construction/write. The trigger output and containing scopes are also marked. Protection is placed on each relevant action; parent settings are not treated as inherited by child actions.

The Microsoft [secure data guidance](https://learn.microsoft.com/en-us/power-automate/guidance/coding-guidelines/use-secure-inputs-outputs-triggers) documents secure inputs/outputs as action settings, but available offline evidence does not establish that each action type in this definition retains its setting after solution import and in run history. This remains `RUNTIME_VERIFICATION_REQUIRED`, particularly for trigger outputs, SetVariable, Scope, If and Foreach. Before activation, a separately authorized synthetic run must inspect sanitized run history for addresses, snapshots, provider response/diagnostics, attendee observations, loop items and derived data. Any rejected, dropped or ineffective secure-data setting is a hard stop; do not activate.

Number environment-variable parameters remain `Float`, converted with `int(string(...))`; sorting remains `sort(union(...), 'startUtc')`, and slots are serialized with `string()`. Static source review cannot prove Power Automate binding, WDL function edge behavior, canonical object serialization, or null/lazy evaluation. Keep these as `RUNTIME_VERIFICATION_REQUIRED`; do not change them speculatively.

Offline SDK regression coverage verifies identical free duplicates are deduplicated; identical non-free observations never establish free; contradictory same-interval observations fail closed; duplicate/missing expected attendees do not establish free; an extra valid attendee cannot replace the expected TA; unknown availability and malformed shapes fail closed; and an empty suggestion list returns NoSlots. These validate the C# reference adapter, not execution of the Flow. The Flow remains untested.

The trigger is Create-only, Pending-filtered and concurrency 1. This does not prove transactional exactly-once behavior or prevent all overlapping external changes. The server-side guard remains authoritative. The requester BSO identity and elevated DEV owner result-writer/Outlook connection remain distinct; `DEV_FUNCTIONAL_IDENTITY_ELEVATED_NOT_SECURITY_ACCEPTANCE` is unchanged.

#### First-runtime verification matrix

| Area | Bounded synthetic probe | Pass condition / stop |
|---|---|---|
| Number parameters | Resolve one authorized integer Number value through the Flow parameter and `int(string(...))`. | Correct integer; any binding/conversion fault stops. |
| WDL and serialization | Feed unsorted, repeated known suggestions; inspect terminal slot text and size. | Exact distinct ascending UTC `{startUtc,endUtc}` array; stable parse; within 200 and 32,768 characters. |
| Null/malformed shapes | Use empty suggestions, missing nested fields, null/malformed attendee entries, unknown values and bad UTC representation. | Safe deterministic Failed/NoSlots result; never Available from malformed data; no raw payload in logs. |
| Availability observations | Probe exact free TA/room, non-free, missing/duplicate expected entries, extra attendee, repeated same result and contradictory same interval. | Exact TA plus Onsite room required; conflicts fail closed; no unknown or non-free observation establishes free. |
| Run-history privacy | Inspect trigger and each sensitive action/loop for secure settings and sanitized run history. | No address, reference snapshot, response, diagnostics, attendee observation or loop data visible; otherwise stop. |
| Reference drift | After a valid initial snapshot, change ID, active state or normalized email; separately cause a reread failure; change only display name. Repeat for Available, NoSlots and provider-error outcomes. | Relevant change/unreadable reference yields Failed / `REFERENCE_CHANGED` / empty reason / `[]`; display-name-only change does not. Pre-validation errors retain their own categories. |
| UTC and Outlook shape | First synthetic Outlook response only; capture sanitized field types/time-zone representation. | Exact accepted UTC representation; any different timezone or malformed shape stops with no retry or automatic conversion. |
| Identity and preservation | Use separate test BSO requester and approved DEV owner connection; read back affected rows and role/package topology. | Requester is not impersonated by connector identity; no Candidate/Core mutation; Integration role remains unassigned; all 50 legacy guards remain disabled. |
| Lifecycle and concurrency | Observe one new Pending request and a non-Pending control; inspect run count and final row. | Non-Pending has no result write; one terminal update for the observed run. Do not infer a transactional exactly-once guarantee from concurrency 1. |

### Final reconciliation (fresh GET)

**Guard**

| Component | ID |
|---|---|
| Package | `52463ecb-32d9-f111-a05b-002248997b22` |
| Assembly | `c609c1d1-32d9-f111-a05b-002248997b22` (sandbox) |
| Type | `c709c1d1-32d9-f111-a05b-002248997b22` |

The guard has **0 steps, so 0 active**. Stored package content is not returned on read. Integrity therefore rests on the pre-dispatch hash gate and the live assembly and type identity.

**Connection references**

Both connection references are active and bound exactly to the approved connections. `pac connection list` reports both connections as `Connected`. There are zero custom `os_` connectors and no project Graph or Entra path.

**Flow**

`a5e012da-32d9-f111-a05b-002248997b22`, statecode 0 / statuscode 1 (**OFF**), 0 runs.

**Console**

For both resources, authored = RetrieveUnpublished = published = served `/WebResources/`:

| Resource | SHA256 |
|---|---|
| `candidate-console.html` | `b0d3cede68669fc4bc080100a3318d433cd116b159cee32f8d96f20bd086086e` |
| `candidate-console-availability.js` | `97487ef0c2a6ece4185a2b1d17a76804d9b58535cbeaee3c27b0596fd4ae7921` |

`candidate-console-environment.js` is unchanged (`58e03dc2…`) and declares no `availabilityEnabled`. The module gates on `availabilityEnabled !== true`, so the effective state is **`availabilityEnabled = false`**. Other WebResources are unchanged.

**Solution membership: 60 → 66**

| Component type | Added | Root behavior |
|---|---|---|
| 10150 | 2 connection references | 0 |
| 91 | `os_sr_avqg` assembly | 0 |
| 10039 | package | 0 |
| 29 | Flow | 0 |
| 61 | availability JS | 0 |

No membership was removed. The plugin type is included through its assembly.

**Preserved**
- The BSO role is unchanged at its exact 65-entry map. Its `os_sr_avq` privileges remain Create, Read and Append at User depth only.
- The Availability Integration role still has exactly 4 privileges and is unassigned.
- The Reference Admin role is unchanged and unassigned.
- Candidate Core package/API is unchanged, and all 50 legacy guards remain disabled.
- The 7 definitions still have no values.
- There are 0 `os_sr_avq` rows.
- Business counts are unchanged: 47, 64, 163, 45, 183.

No Candidate operation, Outlook call, mailbox access or TA/Location email update took place.

## Superseded: authorized infrastructure completion (2026-11-05)

**Classification:** `P0_SLICE_2A_INFRASTRUCTURE_PROVISIONED` (provider-independent DEV infrastructure only; no runtime, provider, guard-deployment or Production acceptance).

### Authorizations

After the integration-role stop below, the Technical Lead authorized (`remove_and_continue`) a bounded one-shot continuation: remove exactly the four recorded SharePoint defaults from the unassigned integration role, create the seven definitions, publish `os_sr_avq` entity metadata only, then reconcile. A fresh GET preflight first proved the exact recorded stop state: 53 memberships, BSO 65, an eight-entry unassigned role, zero definitions and preserved Core/reference/guards/Console.

The first removal request used parameter `PrivilegeId`, and OData rejected it with **HTTP 400 during payload validation**. Execution stopped without retrying. A fresh GET proved no change: eight entries, unassigned, zero definitions. Service `$metadata` showed that the bound `RemovePrivilegeRole` action takes a `Privilege` entity reference. The Technical Lead then separately authorized (`corrected_continue`) a new one-shot continuation using that corrected payload. The rejected journal entry was retained, and the corrected requests used new operation names.

### Exact new write requests

| # | Operation | Response |
|---|---|---|
| 5 | `RemovePrivilegeRole` `prvCreateSharePointData` (`PrivilegeId` payload) | **HTTP 400 rejected; not executed; not retried** |
| 6-9 | `RemovePrivilegeRole` with `Privilege` reference: `prvCreateSharePointData`, `prvReadSharePointData`, `prvReadSharePointDocument`, `prvWriteSharePointData` | HTTP 204 each |
| 10-16 | Create definitions `os_sr_avq_bhrs`, `_durs`, `_lead`, `_hzn`, `_exp`, `_dom`, `_maxc` (Solution header; no default/current value) | HTTP 204 each |
| 17 | `PublishXml` `<entities><entity>os_sr_avq</entity></entities>` only | HTTP 204 |

Overall continuation: **16 acknowledged writes**, consisting of 4 from the stopped continuation plus 12 from this completion. There was also **1 rejected request**, and write retries were **0**. No `AddSolutionComponent` was needed, because every definition was already in the Solution through the create header. Each definition was verified by readback before the next step.

**Publication scope:** a single `os_sr_avq` entity metadata PublishXml. There was no `PublishAllXml`, no `pac solution publish`, and no Console WebResource or app publication.

### Environment-variable definitions

| Schema name | Type | Display name |
|---|---|---|
| `os_sr_avq_bhrs` | String (100000000) | Availability Business Hours |
| `os_sr_avq_durs` | String (100000000) | Availability Allowed Durations |
| `os_sr_avq_lead` | Number (100000001) | Availability Minimum Lead Time |
| `os_sr_avq_hzn` | Number (100000001) | Availability Maximum Horizon |
| `os_sr_avq_exp` | Number (100000001) | Availability Result Expiry |
| `os_sr_avq_dom` | String (100000000) | Availability Allowed Email Domains |
| `os_sr_avq_maxc` | Number (100000001) | Availability Maximum Candidates |

None has a default value or an environment-variable value. No mailbox address, user ID, credential, client ID or secret was written. Horizon must be <=61 days and MaxCandidates must be 1-200. The timezone is fixed in code as `SE Asia Standard Time`, with a 15-minute interval; these remain code and configuration-renderer constraints. Because no values exist, availability cannot be configured or enabled.

### Final reconciliation (fresh GET plus unmanaged export/unpack)

- **Schema:** the complete `os_sr_avq` schema is exact, including both `os_sr_ta_avq` and `os_sr_loc_avq` with Delete Restrict and all other cascades NoCascade. The export proves all **15 schema children** through the Include-Subcomponents entity root using the corrected validator.
- **Solution:** there are **60 memberships**. The accepted 52 are retained, plus the integration-role root and seven environment-variable definition roots, all with behavior 0. No membership was removed. The export contains all seven definition folders and no value files.
- **BSO:** **65 entries**, matching the canonical 60 plus the five approved additions below exactly.
- **Availability Integration:** **exactly four Global entries**: `prvReados_sr_avq`, `prvWriteos_sr_avq`, `prvReados_sr_ta` and `prvReados_sr_loc`. It has zero user or team assignments and is not auto-assigned. The exported role XML matches the same four entries.
- **Preservation:** Reference Admin is unchanged and unassigned. Candidate Core package, assembly, types, API, inputs and outputs are unchanged. All 50 legacy guards remain disabled. All five Console resource hashes are unchanged, and availability remains effectively disabled.
- **Rows:** there are zero Availability Query rows. Candidate, Call, History, Interview and Receipt counts are **47/64/163/45/183**. There were zero modified rows in the bounded window starting at the continuation start.

No Outlook connection, connection reference, Flow, Find meeting times execution, guard-package deployment, TA/Location mailbox update, query row, Candidate operation, Candidate Core change, Console publication, commit or push occurred. Synthetic mailbox prerequisites, runtime/security acceptance and Production gates remain open. Canonical release role XML/manifests were not overwritten from the DEV export.

---

## Superseded continuation checkpoint: integration-role exact-map stop (2026-11-05)

**Classification at that point:** `P0_SLICE_2A_CONTINUATION_STOP:EXACT_FOUR_INTEGRATION_PRIVILEGES`. The authorized completion above superseded it.

At that point, the schema was complete, but the new unassigned integration role contained four unapproved SharePoint defaults in addition to the four requested privileges. GET readback detected the mismatch after an acknowledged privilege-replacement action. No removal, retry, further provisioning or publication followed until the separate authorization above.

### Approved continuation and corrected validator

Technical-lead decisions: `P0_SLICE_2A_MEMBERSHIP_VALIDATOR_FALSE_NEGATIVE_CONFIRMED`, `P0_SLICE_2A_PARTIAL_SCHEMA_ACCEPTED_FOR_CONTINUATION`, and `P0_SLICE_2A_OUTLOOK_OFFLINE_REFACTOR_ACCEPTED`. The technical name `os_sr_avq_maxc` / Maximum Candidates is approved, bounded to 1-200 by the offline provider/configuration contract.

[BsoRsSolutionMembership.psm1](../scripts/BsoRsSolutionMembership.psm1) now accepts either exact explicit target-Solution child membership, or the complete chain of:

1. Exact metadata identity, name, owning entity and relationship/lookup binding.
2. The owning entity root in the target Solution with behavior **0 / Include Subcomponents**.
3. Matching Solution identity and Include-Subcomponents entity root in the actual unmanaged export.
4. The exact exported entity attribute and, for relationships, relationship index and detailed referencing/referenced entity/lookup binding.

Shell/exclusion behaviors 1 and 2, missing evidence, duplicate explicit rows and cross-Solution evidence reject. No dedicated type-10 row is required when the inherited chain passes. The previous `AddSolutionComponent` was **not retried**, and no relationship membership request was made in this continuation.

Offline regression validation passed **19 membership checks** and **122 Availability Query static checks** before new tenant writes. The shared validator was then exercised on actual fresh preflight and final exports, not just synthetic fixtures.

### Fresh continuation preflight

PAC and Dataverse agreed on the previously owner-confirmed exact VN LMV IT target and unmanaged `os_sr_bso_rs_support` 1.0.0.1. All 52 memberships matched the accepted partial state: original 51 retained, plus the Availability Query entity root with behavior 0.

The complete partial schema matched the original report, including metadata identities, constraints and exact Choice values; TA lookup/relationship existed with requiredness/cascades exact, while Location lookup/relationship were absent. BSO remained canonical 60; integration role and all seven Slice 2A definitions were absent. Reference Admin was unchanged/unassigned; Candidate Core package/API/inputs/outputs and all 50 disabled guard registrations matched; Console hashes and disabled feature state matched; Availability Query rows were zero. Business counts remained 47/64/163/45/183.

A fresh read-only unmanaged export/unpack proved all **13 existing schema children** through the corrected validator, including the TA relationship without an explicit relationship row. No unexpected preflight drift was found.

### Exact new write requests

| # | Operation | Response |
|---|---|---|
| 1 | Create only optional `os_sr_avq_loc` and `os_sr_loc_avq` | HTTP 204 |
| 2 | Add only the approved five-privilege BSO delta below | HTTP 204 |
| 3 | Create unassigned `BSO-RS Support - Availability Integration` | HTTP 204 |
| 4 | Initialize that role using `ReplacePrivilegesRole` with exactly the four requested privileges | HTTP 204 |

After request 1, fresh metadata and a new export proved all **15 completed schema children** before role changes began. After request 2, the entire BSO map matched the 60-entry baseline plus exactly five approved additions. Request 4 did **not** yield the requested exact map: the four SharePoint defaults remained. This is a genuine new role-map stop, not the resolved membership false negative.

**Continuation provisioning writes: 4. Write retries: 0. Publication calls: 0.** Across both operations there were seven acknowledged provisioning requests, with zero write retries. Read-only exports/unpacks are evidence capture, not provisioning retries. Existing table/TA metadata was never recreated. No explicit `AddSolutionComponent` was invoked in this continuation.

### Complete live schema at stop

Table `os_sr_avq`: **Availability Query / Availability Queries**, **UserOwned**, audit **Off**, primary ID `os_sr_avqid`. No Candidate/Interview Schedule lookup, provider-response field, or mailbox-address field exists.

| Field | Verified type/constraints | Requiredness |
|---|---|---|
| `os_sr_avq_ref` | String(100), primary name, AutoNumber `AVQ-{SEQNUM:8}` | ApplicationRequired |
| `os_sr_avq_ta` | Lookup to `os_sr_ta` | ApplicationRequired |
| `os_sr_avq_loc` | Lookup to `os_sr_loc` | None |
| `os_sr_avq_mod` | Local Choice: Online=100000000, Onsite=100000001 | ApplicationRequired |
| `os_sr_avq_strt` | DateTime, DateAndTime, UserLocal | ApplicationRequired |
| `os_sr_avq_end` | DateTime, DateAndTime, UserLocal | ApplicationRequired |
| `os_sr_avq_dur` | Integer, min 15 / max 480 | ApplicationRequired |
| `os_sr_avq_stat` | Local Choice: Pending=100000000, Available=100000001, NoSlots=100000002, Failed=100000003 | ApplicationRequired |
| `os_sr_avq_rsn` | String(40) | None |
| `os_sr_avq_err` | String(40) | None |
| `os_sr_avq_slts` | Memo(32768) | None |
| `os_sr_avq_qat` | DateTime, DateAndTime, UserLocal | None |
| `os_sr_avq_exp` | DateTime, DateAndTime, UserLocal | None |

Both `os_sr_ta_avq` and `os_sr_loc_avq` have Delete **Restrict**, with Assign/Share/Unshare/Reparent/Merge/RollupView **NoCascade**. System Archive behavior is reported as RemoveLink, unchanged by the requested cascade contract. This is metadata acceptance only; no guard or runtime availability behavior was tested.

### Exact resulting role maps

**BSO: 65 entries**, exactly the original canonical 60 plus:

| Added privilege | Depth |
|---|---|
| `prvCreateos_sr_avq` | Basic / User |
| `prvReados_sr_avq` | Basic / User |
| `prvAppendos_sr_avq` | Basic / User |
| `prvAppendToos_sr_ta` | Global / Organization |
| `prvAppendToos_sr_loc` | Global / Organization |

Both AppendTo grants were absent from the baseline and are needed to associate query lookups with referenced TA/Location rows under Dataverse Append/AppendTo authorization. No Availability Query Write/Delete/Assign/Share, Candidate/Core grant, or administrative grant was added to BSO. Existing assignments are unchanged.

**Availability Integration: eight entries, zero user/team assignments, not auto-assigned.** The four requested Global entries are present: `prvReados_sr_avq`, `prvWriteos_sr_avq`, `prvReados_sr_ta`, `prvReados_sr_loc`. The exact four unexpected Global entries are:

- `prvCreateSharePointData`
- `prvReadSharePointData`
- `prvReadSharePointDocument`
- `prvWriteSharePointData`

These are not accepted as proven minimum Flow requirements. No Candidate/Call/History/Interview/Receipt write privilege, `os_sr_cact` execute privilege, or customization/security-administration privilege is present in this eight-entry map. **Do not assign the role.** Any bounded correction or further continuation requires a new explicit authorization; this operation did not remove the defaults or repeat the replacement.

### Definitions, export, publication and preservation

**No environment-variable definition was reached.** All seven remain absent: `os_sr_avq_bhrs`, `os_sr_avq_durs`, `os_sr_avq_lead`, `os_sr_avq_hzn`, `os_sr_avq_exp`, `os_sr_avq_dom`, `os_sr_avq_maxc`. No default/current value, mailbox address, identity, client ID or secret was written. Horizon <=61, MaxCandidates 1-200, timezone `SE Asia Standard Time`, and 15-minute interval remain offline code/configuration constraints, not configured runtime values.

Final read-only Solution membership count is **53**: all accepted 52 retained, plus the newly created role root automatically included by the create request's Solution header. Both relationships/lookups export under the Include-Subcomponents table root without manufacturing child membership rows. A final actual unmanaged export/unpack proves all 15 schema children and matches the **complete BSO, Reference Admin and actual eight-entry integration role maps**. The stopped-state export is retained outside canonical release source; frozen artifacts/manifests and Solution version are unchanged.

Publication scope actually executed: **none**. The planned single-entity `os_sr_avq` PublishXml was not reached. No Console WebResource, app, or Publish All operation occurred.

Final GET reconciliation confirms unchanged Candidate Core package modification baseline/version, assembly/types/API/every input/output and all 50 disabled guards; unchanged/unassigned 20-entry Reference Admin; unchanged five published Console hashes; effective availability disabled; and zero Availability Query rows. Server package byte equality is not claimed.

Candidate/Call/History/Interview/Receipt counts remained **47/64/163/45/183**. Each had zero rows modified in the bounded continuation window **2026-11-05T14:21:49Z through 2026-11-05T14:26:37Z**; no concurrent business-row modification was observed in that window.

No Outlook connection, connection reference, Flow, Find meeting times execution, guard-package deployment, TA/Location mailbox update, runtime query row, Candidate operation, Candidate Core change, Console publication, commit or push occurred. Synthetic mailbox prerequisites and runtime/security/Production acceptance remain unresolved.

---

## Historical initial operation: membership assertion stop

**Date:** 2026-11-05. **Target:** owner-confirmed VN LMV IT, unmanaged `os_sr_bso_rs_support` 1.0.0.1.

**Classification:** `P0_SLICE_2A_RECONCILIATION_FAILED:MEMBERSHIP:10`.

This is a partial infrastructure result, **not** `P0_SLICE_2A_INFRASTRUCTURE_PROVISIONED`, deployment acceptance, or runtime acceptance. No repair, repeat write, rollback, or continuation was attempted after the stop. Any future attempt must stop on the now-existing partial components until the owner explicitly authorizes a reviewed continuation or migration plan.

## Authorization and preflight

The owner supplied these approved dispositions:

- `SLICE_2A_OUTLOOK_CONNECTOR_DEV_PATH_FEASIBLE`
- `SLICE_2A_DEV_IDENTITY_OPTION_A_APPROVED`
- `SLICE_2A_SYNTHETIC_MAILBOX_PREREQUISITE_MISSING`
- `SLICE_2A_CUSTOM_GRAPH_PATH_ABANDONED`

Only provider-independent infrastructure was authorized. Option A permits the existing DEV owner connection for later functional testing; no connection was created or used for Outlook in this operation. Synthetic mailbox prerequisites remain unresolved. The custom Graph path was not provisioned.

Fresh PAC and Dataverse identity checks agreed on the exact confirmed target. The unmanaged Solution, publisher prefix `os`, version, and accepted 51-membership fingerprint matched the [Slice 1 baseline](CURRENT_STATE.md#normal-srapp-candidate-console-entrypoint-accepted-without-tenant-writes-2026-11-05). The complete BSO map matched all 60 canonical entries; Reference Admin matched 20 entries and had zero user/team assignments. Candidate Core remained package-backed with package version 1.0.0, ModifiedOn `2026-11-05T05:54:24Z`, 21 inputs, five outputs, and one optional `ProfileFieldMask`. All 50 legacy guards were disabled.

The table, named relationships, availability role, and availability configuration definitions were absent before provisioning. Published Console resources had no availability panel or enabled availability flag.

## Acknowledged requests and stop

| Request | Result |
|---|---|
| Create `os_sr_avq` and its nonlookup fields | HTTP 204 |
| Create required TA lookup and `os_sr_ta_avq` | HTTP 204 |
| `AddSolutionComponent`, type 10, for the new TA relationship | HTTP 200 |

The next GET did not return the single explicit type-10 `solutioncomponent` row required by the execution guard. Provisioning stopped immediately with the classification above.

Subsequent **read-only** reconciliation found 52 Solution memberships: all original 51 retained, plus the `os_sr_avq` entity root with `rootcomponentbehavior=0` (include subcomponents). An actual unmanaged export and separate unpack include both `os_sr_avq` and `os_sr_ta_avq`. Thus the evidence establishes export coverage of the TA relationship, **not** that the relationship is absent from the Solution. The stop concerns the explicit-row membership assertion; its relationship to Dataverse subcomponent membership requires a separately reviewed correction. No validator change was used to resume provisioning.

**Provisioning write requests:** 3, all acknowledged. **Write retries:** 0. **Publication calls:** 0. Export/unpack was read-only source capture, not a provisioning retry. Its actual output and detailed GET/journal evidence are retained in the session workspace; the incomplete export was not adopted into canonical release source or frozen artifacts.

## Exact partial schema readback

The table display labels are **Availability Query / Availability Queries**, ownership is **UserOwned**, and auditing is **Off**. Primary ID is `os_sr_avqid`; primary name is `os_sr_avq_ref`.

| Field | Actual type and constraints | Requiredness |
|---|---|---|
| `os_sr_avq_ref` | String(100), primary name, AutoNumber `AVQ-{SEQNUM:8}` | ApplicationRequired |
| `os_sr_avq_ta` | Lookup to `os_sr_ta` | ApplicationRequired |
| `os_sr_avq_loc` | **Not created** | Not applicable |
| `os_sr_avq_mod` | Local Choice: Online=100000000, Onsite=100000001 | ApplicationRequired |
| `os_sr_avq_strt` | DateTime, DateAndTime, UserLocal | ApplicationRequired |
| `os_sr_avq_end` | DateTime, DateAndTime, UserLocal | ApplicationRequired |
| `os_sr_avq_dur` | Integer, min 15 / max 480 | ApplicationRequired |
| `os_sr_avq_stat` | Local Choice: Pending=100000000, Available=100000001, NoSlots=100000002, Failed=100000003 | ApplicationRequired |
| `os_sr_avq_rsn` | String(40) | None |
| `os_sr_avq_err` | String(40) | None |
| `os_sr_avq_slts` | Memo(32768) | None |
| `os_sr_avq_qat` | DateTime, DateAndTime, UserLocal | None |
| `os_sr_avq_exp` | DateTime, DateAndTime, UserLocal | None |

Dataverse-generated lookup display/Choice virtual fields are not additional payload-storage fields. No Candidate lookup, Interview Schedule lookup, mailbox-address field, or raw provider-response field was created.

`os_sr_ta_avq` references `os_sr_ta` through `os_sr_avq_ta`, with Delete **Restrict**; Assign, Share, Unshare, Reparent, Merge and RollupView are **NoCascade**. The server additionally reports Archive **RemoveLink**; no archive setting was requested or changed. `os_sr_loc_avq` is **not created**.

## Unexecuted role and configuration scope

- **BSO privilege delta: zero.** The complete resulting map remains the original 60 canonical entries. Even the approved Availability Query Create/Read/Append and TA/Location AppendTo additions were not reached.
- **Availability Integration role: not created and not assigned.** Its requested future definition remains Availability Query Read/Write and TA/Location Read at Organization depth, with no Candidate/Core execution, business writes, customization, security administration, or unproven platform-baseline grants.
- **Environment-variable definitions: none created.** The unexecuted definitions are `os_sr_avq_bhrs`, `os_sr_avq_durs`, `os_sr_avq_lead`, `os_sr_avq_hzn`, `os_sr_avq_exp`, and `os_sr_avq_dom`. No defaults, values, mailbox addresses, user IDs, credentials, client IDs, or secrets were written.
- Timezone `SE Asia Standard Time`, interval 15 minutes, and maximum horizon <=61 days remain the [offline configuration contract](../solutions/AvailabilityQuery/availability-environment-variables.json), not configured runtime values.

## Final preservation reconciliation

GET-only checks verified:

- BSO's complete 60-entry map unchanged; Reference Admin's complete 20-entry map unchanged and unassigned.
- Candidate Core package modification baseline/version, assembly linkage, API settings, every input/output definition and every legacy-guard registration unchanged; all 50 guards still disabled. Server package byte equality is not claimed.
- All original Solution memberships retained; only one entity-root membership added.
- All five published Console resource hashes unchanged. Availability remains effectively disabled: no availability panel/module was deployed and no enabled flag was introduced. No Console or app publication occurred.
- Zero `os_sr_avq` runtime rows.

| Business table | Before | After | Rows modified in reconciliation window |
|---|---:|---:|---:|
| Candidate | 47 | 47 | 0 |
| Call Log | 64 | 64 | 0 |
| Status History | 163 | 163 | 0 |
| Interview Schedule | 45 | 45 | 0 |
| Operation Receipt | 183 | 183 | 0 |

The bounded window was `2026-11-05T13:42:46Z` through `2026-11-05T13:46:37Z`. No concurrent business-row modification was observed in that window. Counts are aggregate checks, not a claim of runtime availability acceptance.

No Candidate operation, Outlook connection, connection reference, Cloud Flow, Find meeting times call, Availability Query guard deployment, TA/Location email change, query-row creation, Console panel publication, commit, or push occurred. No `PublishAllXml` or `pac solution publish` was used. Slice 1 remains accepted and independent; real-data and Production gates remain closed.
