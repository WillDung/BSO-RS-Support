# P0 Slice 2A Pre-Activation Readiness Report and Controlled Execution Plan

**Assessment date:** 2026-11-06  
**Decision:** `P0_SLICE_2A_PRE_ACTIVATION_PLAN_BLOCKED`  
**Scope:** Offline repository assessment and future change plan only. This is not deployment, activation, runtime, security, or Production authorization.

**Subsequent evidence:** The later [Stage A live reconciliation](P0_SLICE_2A_STAGE_A_LIVE_PREFLIGHT_REPORT.md) supersedes this assessment's statements that the live Flow had not been read. It records the fresh readback and remaining incomplete Console-layer evidence; this document remains the original offline plan.

## Executive decision

The local source hardening is present and the historical deployment baseline can be correlated to its Git source. However, the current live Flow bytes and state have not been freshly read, required configuration values and synthetic mailboxes are absent, and the proposed guard registration contract omits execution order. There is also a retry-policy discrepancy between the Flow contract and the authored Flow definition. These gaps block a safe update or activation now.

The plan below is complete as a gated procedure. Stage A requires separate authorization for read-only access to the exact DEV environment. No tenant operation was performed for this assessment. The reported DEV classification remains `P0_SLICE_2A_RUNTIME_WIRING_DEPLOYED_FEATURE_OFF`; the local classification remains `P0_SLICE_2A_OFFLINE_FLOW_HARDENING_COMPLETE`.

The external runtime blocker remains `SLICE_2A_SYNTHETIC_MAILBOX_PREREQUISITE_MISSING`. The DEV identity remains `DEV_FUNCTIONAL_IDENTITY_ELEVATED_NOT_SECURITY_ACCEPTANCE`. Slice 1 remains independent and functionally accepted.

## 1. Source and baseline reconciliation

### Worktree and hashes

| Item | Offline evidence |
|---|---|
| Git HEAD | `e41d30bf8fb46e151005d0af0fb569f2af342b91` on `main`, tracking `origin/main` |
| Worktree at assessment start | Clean: no modified, staged, or untracked files |
| Hardened Flow JSON SHA-256 | `0E1A1DE9CFECE98440B1EC8B52DCD76648A25826A06BCF36FAFCEFBB39C701B0` |
| Flow contract SHA-256 | `DF5EEEAD064F0FC0BE2448E854A868E8539CB53C5D58322E53A2D8EAE9FCCC35` |
| Historical pre-hardening Git source | Commit `7a64022e1891607b9d4c789d0f03e1c99640df88`; its Flow JSON SHA-256 is `F901BAAE0ABC5F2A2ECCF74BF59E76FE05189A6E13BF86A981D6D6E4DBEB8811` |
| Deployment-time baseline record | The [DEV provisioning report](./P0_SLICE_2A_DEV_PROVISIONING_REPORT.md) records that the live clientdata matched the pre-hardening Flow source at deployment; it records the hash in abbreviated form. |
| Current live comparison | **Incomplete.** No tenant read was authorized or performed for this assessment, so current live bytes, status, run count, and ETag are not independently verified. Do not claim that the current live Flow equals either repository revision. |

The baseline hash independently matches the deployment report's abbreviated `f901baae…8811` value. A Git diff from that baseline to HEAD changes only `runtimeConfiguration.secureData` settings in the Flow JSON. It adds trigger-output protection and action-level input/output protection, or adds outputs where an existing setting protected inputs only. There are no changes in that Flow diff to trigger conditions, concurrency, expressions, connector operations, connection-reference names, request/result fields, or retry policies.

The hardening commit also changed the Flow contract, tests, SDK regression tests, test instructions, and related documentation. Those files are not part of the Flow deployment delta and must not be packed or deployed as additional Power Platform components. The baseline-to-HEAD Flow JSON diff is 182 changed lines (175 insertions and 7 property-list expansions), all secure-data settings. The nine files changed by that historical commit were:

- [CURRENT_STATE.md](./CURRENT_STATE.md)
- [INTEGRATION_DESIGN.md](./INTEGRATION_DESIGN.md)
- [P0_SLICE_2A_DEV_PROVISIONING_REPORT.md](./P0_SLICE_2A_DEV_PROVISIONING_REPORT.md)
- [PROJECT_CONTEXT.md](./PROJECT_CONTEXT.md)
- [availability-flow.contract.json](../solutions/AvailabilityQuery/availability-flow.contract.json)
- [os_sr_avchk.clientdata.json](../solutions/AvailabilityQuery/os_sr_avchk.clientdata.json)
- [AvailabilityQuery.Tests.ps1](../tests/AvailabilityQuery.Tests.ps1)
- [OutlookProviderTests.cs](../tests/AvailabilityQuerySdk/OutlookProviderTests.cs)
- [README.md](../tests/README.md)

The current working tree is clean; this assessment does not alter any of those source files. The Flow source and contract are identified in [Availability Query README](../solutions/AvailabilityQuery/README.md), and the logical Flow requirements are in the [Flow contract](../solutions/AvailabilityQuery/availability-flow.contract.json).

### Deployment-delta classification

| Difference from historical deployed source | Classification | Deployment disposition |
|---|---|---|
| Trigger `secureData.properties: ["outputs"]` | Privacy-only correction | Include only in a separately authorized bounded Flow update; Gate 2 and Gate 3 remain required. |
| Sensitive actions receive `["inputs","outputs"]`, including existing input-only settings expanded to cover outputs | Privacy-only correction; exact action-type support uncertain | Include only in the same bounded Flow update; do not remove settings to force an update. |
| Contract wording/status and `runHistoryPrivacy` inventory | Offline documentation/contract change | Do not deploy as a Flow component. |
| Recursive test traversal, SDK cases, and test README | Offline test change | Do not deploy. |
| Other code, Solution components, Console resources, roles, connection references, Candidate Core, or release artifacts | No such change in the hardening commit's Flow delta | Any such difference in a fresh preflight is unexpected and stops the operation. |

### Open source-contract discrepancies

1. The Flow contract's `retry.429` text allows up to two retries, while every connector action in the authored Flow sets `retryPolicy.type` to `none`. The local Flow therefore has no automatic connector retry. Do not add a retry or claim full contract agreement without a separately approved decision; all controlled probes in this plan use zero retries.
2. The offline contract's display name is `BSO-RS Availability Check`; the deployment report records `Slice 2A Availability Check`. Stage A must read the live metadata. Target only the existing `os_sr_avchk` in the exact Solution; do not rename it or update its display name as part of the privacy delta.
3. Some offline schema, role, and environment-variable contract files retain `PROPOSED_SOURCE_OFFLINE_*` status labels even though the latest DEV report records those components as deployed. Treat those files as design contracts, not live readback. The latest dated provisioning report is the historical deployment evidence; a fresh Stage A read is still required.
4. `solutions/AvailabilityQuery/README.md` retains a pre-wiring status sentence that conflicts with the later DEV wiring report. It was left unchanged in this planning task because it is tracked canonical Solution source and editing it would further alter the frozen source fingerprint; the later dated report controls the historical status. Reconcile that README only in a separately scoped source/fingerprint update.

The Flow has one `OpenApiConnectionWebhook` trigger, concurrency 1, and 32 actions listed in `runHistoryPrivacy.sensitiveActions`. The action inventory and proposed source settings are:

| Type | Sensitive action names | Gate 1 source setting | Offline authoritative evidence / uncertainty |
|---|---|---|---|
| Trigger `OpenApiConnectionWebhook` | Trigger (not in the action array) | `outputs` | General Microsoft trigger guidance exists; exact exported-setting retention and run-history behavior for this trigger type are not established offline. |
| `OpenApiConnection` | `Read_query`, `Read_ta`, `Read_location`, `Find_meeting_times`, `Reread_ta`, `Reread_location`, `Write_terminal_result` | `inputs`, `outputs` | General action guidance exists; connector/action-specific retention and obscuring after update are not established offline. |
| `SetVariable` | `Set_ta_snapshot`, `Set_location_snapshot`, `Set_result_slots` | `inputs`, `outputs` | No action-type-specific import/runtime evidence is available offline. |
| `Compose` | `Compose_validation_error`, `Compose_slot`, `Compose_free`, `Compose_canonical_slots`, `Compose_proposed_result`, `Compose_drift`, `Compose_location_drift`, `Compose_terminal` | `inputs`, `outputs` | No action-type-specific import/runtime evidence is available offline. |
| `If` | `Check_response_shape`, `Check_suggestion_timezone`, `Check_suggestion_valid`, `Check_slot_eligible`, `If_validated_snapshot` | `inputs`, `outputs` | No action-type-specific import/runtime evidence is available offline; protection of child branches is not assumed to inherit. |
| `Foreach` | `For_each_suggestion` | `inputs`, `outputs` | No action-type-specific import/runtime evidence is available offline; loop items and outputs require Gate 3 inspection. |
| `Query` | `Find_invalid_attendees`, `Find_ta_entries`, `Find_room_entries` | `inputs`, `outputs` | No action-type-specific import/runtime evidence is available offline. |
| `AppendToArrayVariable` | `Append_observation`, `Append_slot` | `inputs`, `outputs` | No action-type-specific import/runtime evidence is available offline. |
| `Scope` | `Evaluate`, `Map_failure`, `Reread_references` | `inputs`, `outputs` | No action-type-specific import/runtime evidence is available offline; child actions must each retain their own settings. |

Grouping above is by type only; every named action is individually included in the Flow contract and recursive static regression test. The repository cites Microsoft's general [secure inputs and outputs guidance](https://learn.microsoft.com/en-us/power-automate/guidance/coding-guidelines/use-secure-inputs-outputs-triggers), which documents secure-data settings for actions and triggers. Offline evidence does **not** establish acceptance, persistence through update/import, or effective run-history suppression for each listed action type.

No action type is proven unsupported by the available offline evidence; nor is any type-specific combination proven to persist. The highest uncertainty is for `SetVariable`, `Scope`, `If`, `Foreach`, `Query`, and `AppendToArrayVariable`, plus trigger output suppression.

### Three independent privacy gates

| Gate | Required proof | Current status |
|---|---|---|
| 1 — Source | Each sensitive action/trigger has the intended serialized secure-data setting. | **Passed locally** by JSON inspection and the recursive static test. |
| 2 — Platform acceptance | An authorized single-component update is accepted, then readback/export shows every setting retained on the exact trigger/action. | **Not run; authorization required.** |
| 3 — Runtime effect | An authorized synthetic execution shows no sensitive input/output or loop data in maker-visible run history. | **Not run; runtime authorization and synthetic mailboxes required.** |

Passing Gate 1 does not imply Gate 2 or Gate 3. Any rejected/dropped setting blocks further progress. If a sensitive value is visible at Gate 3, stop, turn the Flow OFF under the same authorization if safe, and require a separately approved architecture correction. Do not copy raw output into a report or use an unprotected diagnostic action.

## 2. Bounded Flow update operation

This is a future operation, not authorization to execute it.

### Preconditions

1. Complete the authorized Stage A read-only preflight below against the exact environment URL, after the owner confirms the URL and read-only access.
2. Resolve `os_sr_avchk` to exactly one existing Flow in unmanaged Solution `os_sr_bso_rs_support`; verify its current OFF state, definition, connection-reference bindings, solution membership, and run count. Preserve the observed live definition as the rollback/readback baseline.
3. Compare current live bytes with the historical pre-hardening source and the expected local hardened source. If the current live definition has any unexplained difference, stop.
4. Confirm the Flow remains OFF and no pending Availability Query could trigger during the update. Confirm no connection, Console, role, environment-variable value, package, or Solution-membership change is included.
5. Confirm the selected supported authoring surface can update only this Flow definition and preserve the `secureData` structure. Identify its concurrency token/ETag behavior before writing.

### One-write boundary and reconciliation

- Write only the existing Flow's definition, retaining its exact name, Solution, display name, trigger, connection references, OFF state, and all non-privacy behavior. Expected write count: **one**; automatic retry count: **zero**.
- Use conditional update (`If-Match`/ETag or the authoring surface's documented equivalent) if supported. If concurrency control or a single-Flow update surface cannot be established, stop before writing; do not substitute a whole-Solution import or broad publish.
- Do not use `PublishAllXml`, `pac solution publish`, an environment-variable update, or any Console WebResource publication.
- Immediately read back the same Flow. Compare the returned definition against the local expected source and the pre-update snapshot. Confirm the Flow is still OFF, has no new run, retains the same connection bindings and Solution membership, and has every secure-data setting at Gate 2.
- If the write outcome is ambiguous, perform read-only reconciliation only. Do not retry. If readback differs or is incomplete, stop; a rollback is a separate, explicitly authorized conditional update using the just-captured live snapshot.

## 3. Environment-variable readiness worksheet

The latest DEV report says all seven definitions exist without values. That is historical readback, not a fresh check. No value is approved or written in this assessment.

| Schema name | Expected Dataverse type | Source-derived constraints | Proposed value | Approval source | Renderer output | First-runtime check |
|---|---|---|---|---|---|---|
| `os_sr_avq_bhrs` | Text | JSON object keyed by weekday; each configured day has exactly `opens` and `closes` in `HH:mm`; `opens < closes`; missing days are closed; at least one day required. | `OWNER_INPUT_REQUIRED` | Product owner/business-hours approver; exact approver/value not recorded. | `BusinessHours.<Day>=HH:mm-HH:mm` | Use only approved hours; verify a returned slot is fully within the configured local interval. |
| `os_sr_avq_durs` | Text | Comma-separated unique positive integer minutes; each divisible by 15 and no more than 480; at least one value. | `OWNER_INPUT_REQUIRED` | Product owner; exact approval not recorded. | `AllowedDurationsMinutes` | Binding is integer-preserving; each accepted slot has the requested duration. |
| `os_sr_avq_lead` | WholeNumber | Integer minutes; minimum 0 in the guard settings. Flow parameter is currently declared `Float` and converted with `int(string(...))`. | `OWNER_INPUT_REQUIRED` | Product owner; exact approval not recorded. | `MinimumLeadTimeMinutes` | Verify exact integer binding and that no slot starts before the post-provider current UTC plus lead time. |
| `os_sr_avq_hzn` | WholeNumber | Integer days, 1–61. Flow parameter is currently `Float` then converted to integer. | `OWNER_INPUT_REQUIRED` | Product owner/Technical Lead; exact approved value not recorded. | `MaximumHorizonDays` | Verify exact integer binding and the upper bound; reject out-of-horizon requests. |
| `os_sr_avq_exp` | WholeNumber | Integer minutes, 1–1440. Flow parameter is currently `Float` then converted to integer. | `OWNER_INPUT_REQUIRED` | Product owner/security-retention approver; exact approval not recorded. | `ResultExpiryMinutes` | Verify expiry is after queried-at and does not exceed configured expiry (with the guard's one-second tolerance). |
| `os_sr_avq_dom` | Text | Comma-separated exact lowercase DNS domains; no email addresses, wildcard, trailing dot, duplicates, or non-DNS values. Domain ownership and mailbox authorization must be verified by IT. | `OWNER_INPUT_REQUIRED` | IT/mailbox administrator plus product owner; exact domains not recorded. | `AllowedEmailDomains` | Confirm both synthetic mailbox domains are approved; do not use `.invalid` addresses as live targets. |
| `os_sr_avq_maxc` | WholeNumber | Integer 1–200 and no greater than the slot-count limit of 200. Flow parameter is currently `Float` then converted to integer. The technical name is approved; the value is not. | `OWNER_INPUT_REQUIRED` | Technical Lead approved the name/maximum-candidate contract; exact value approval is not recorded. | `MaximumCandidates` | Verify integer binding and that the provider result/slot count is bounded. |

The timezone (`SE Asia Standard Time`) and interval (15 minutes) are fixed in code, not environment variables. The maximum-horizon contract remains at most 61 days. The canonical binding is:

`approved values + separate nonsecret DEV result-writer identity` → `AvailabilityConfigurationRenderer.Render` → identical rendered configuration bytes on both guard steps.

The renderer rejects missing, duplicate, unknown, empty, or invalid values and validates its output through the real plug-in parser. Do not hand-edit step configuration or invent business values. The user ID is environment-specific and must not be copied into this document or source control.

## 4. Guard-step registration readiness

The [registration contract](../solutions/AvailabilityQuery/availability-plugin-registration.contract.json) proposes **two** synchronous, PreOperation steps for `os_sr_avqg.ProtectAvailabilityQuery`, package `os_sr_avqg_pkg`, assembly/namespace `os_sr_avqg`. The latest deployment report records the package/type present with zero steps. No step is registered by this assessment.

| Proposed step | Message/table | Stage/mode | Execution user | Filtering attributes | Images |
|---|---|---|---|---|---|
| `os_sr_avqg_stp_cre` | Create / `os_sr_avq` | PreOperation / 20; Synchronous | Calling User | None specified | None |
| `os_sr_avqg_stp_upd` | Update / `os_sr_avq` | PreOperation / 20; Synchronous | Calling User | `os_sr_avq_stat`, `os_sr_avq_rsn`, `os_sr_avq_err`, `os_sr_avq_slts`, `os_sr_avq_qat`, `os_sr_avq_exp` | None |

**Registration metadata gap:** `executionOrder` is absent from the source contract. Do not assume a platform default or invent an order. Stage C is blocked until the owner/Technical Lead approves an explicit value and the source contract is updated, or provides an authoritative registration record that settles it. Do not register duplicate or partial steps.

**Configuration:** resolve all seven approved values and the separate DEV result-writer identity through the canonical renderer. Bind the exact same rendered bytes as unsecure configuration to both steps. Manual configuration is prohibited. The proposed handler, message, entity, stage, mode, execution user, filter list, and no-image configuration above are the only metadata currently supported by the source contract.

**Security behavior from source:** Create requires `UserId == InitiatingUserId`, a non-empty caller different from the configured result writer, and only the six request fields; it sets state to Pending. Update requires `UserId == InitiatingUserId == ResultWriterUserId`, the current row to be Pending, a single valid terminal transition, and only the six result fields. The plug-in reads references as the calling user and does not write through its service. The field allowlists exclude `ownerid`; Dataverse default ownership behavior must be read back in the synthetic test. These are source/test claims, not live registration evidence.

The requester remains a separate BSO test identity; the Flow Dataverse connection/result writer is the elevated current DEV owner. The Availability Integration role remains unassigned and is not substituted for that owner. This DEV arrangement is not least-privilege security acceptance.

## 5. Synthetic mailbox prerequisites

No mailbox, connection, reference row, or calendar was created or tested.

| Prerequisite | Responsible party | Required evidence before Stage D |
|---|---|---|
| Distinct synthetic TA mailbox | IT mailbox administrator | Mailbox is controlled by the organization, has an IT-approved domain, and can be used only for this test. |
| Synthetic room/resource mailbox | IT mailbox administrator | Resource behavior is configured and confirmed; it is available as `ResourceAttendees` for Onsite tests. |
| Mailbox owner/admin approval | IT and mailbox owner | Written approval for the test identity, calendar windows, expected free/busy changes, and cleanup/retention. |
| Existing Outlook connection access | Environment/connection owner | Read-only confirmation that the already-bound owner connection is Connected and authorized for both synthetic mailboxes. Do not create a connection or change consent, credentials, CA, or licensing. |
| Free/busy and booking permissions | IT/mailbox administrator | Confirmed for the owner connection and the selected synthetic windows. Do not infer access from connection status. |
| Allowed-domain values | IT plus product owner | Exact canonical domains approved and used in `os_sr_avq_dom`; no mailbox address is recorded in the report. |
| Test-only TA and Location references | Authorized reference-data owner | Active synthetic records with approved domain addresses and no Candidate/interview data. Creating or changing them is a separate tenant write authorization. |
| Safe windows/calendar states | Mailbox owner and test operator | UTC windows agreed in advance; any busy event used as a fixture is a separately authorized calendar write. |

Existing `.invalid` addresses are not live provider targets. No real Candidate, Candidate email, CV, interview record, tenant identifier, mailbox address, credential, or connection URL belongs in fixtures or evidence.

## 6. Controlled first-runtime acceptance matrix

This is a test specification, not an executed report. Every row that invokes the live Flow requires a separately approved temporary activation window. Before each run: Stage A must pass, the Flow and guards must match their approved readbacks, approved values must be installed, zero unrelated Pending rows must exist, the exact synthetic fixture must be identified, and the operator must have explicit authorization. Set retries to zero; on an ambiguous result, stop and reconcile read-only.

Evidence must be sanitized: record the scenario, UTC test window, component hashes/status, safe terminal code, counts, and pass/fail only. Do not record mailbox addresses, raw Outlook payloads, tokens, user GUIDs, or sensitive run-history contents.

| ID / scenario | Preconditions, synthetic fixture, and exact operation | Expected result and evidence | Tenant write? | Outlook call? | Gate / stop |
|---|---|---|---|---|---|
| A. Flow parameter binding and integer conversion | With all seven approved values and rendered guard configuration, create one guard-valid Pending query using a synthetic TA and a valid UTC window; observe Flow parameter resolution for lead, horizon, expiry, and maximum candidates. Do not use invented sentinel values. | Integer values equal the approved inputs; no truncation/rounding or configuration error. Capture only pass/fail and the safe terminal outcome. | Yes: one AVQ row. | Yes if request validation succeeds. | `AUTHORIZATION_REQUIRED`. Any binding/conversion fault: stop; no retry. |
| B. WDL expression and null-safety | Test missing/null nested response fields, empty arrays, and malformed attendee members. The standard Outlook action does not provide a controlled way to inject arbitrary response shapes. Use only a separately approved isolated test harness; do not alter the deployed Flow or add a custom connector. | Malformed data never produces Available; result is safe Failed/NoSlots with zero slots and no raw payload. | Only if the approved harness uses a test Flow/query. | No for a stubbed response; otherwise provider-dependent. | **Not executable against the current connector contract without a test seam.** Harness design/deployment requires separate approval. |
| C. First Outlook response and timezone | With both synthetic mailboxes and verified access, submit one valid synthetic request in a safe window and observe the first provider response only. Keep the provider action secured. | Accepted representation is exactly UTC under the offline contract; terminal slots are UTC. Capture only a safe terminal outcome and pass/fail. Do not expose or copy raw provider output; if exact shape/type cannot be established without a separately approved redacted harness, leave it unverified. | Yes: one AVQ row. | Yes. | `AUTHORIZATION_REQUIRED`. Any unrecognized timezone/shape: stop with no retry or automatic conversion. |
| D. Strict UTC DateTime transport | Send one AVQ request with explicit UTC timestamps ending in `Z` through the normal guarded Create path. | Guard receives `DateTimeKind.Utc`; row becomes Pending and proceeds. If rejection is solely because the bound Kind is not UTC, stop and localize transport; do not normalize or retry. | Yes: one AVQ create attempt. | Yes only if guard accepts and Flow proceeds. | `AUTHORIZATION_REQUIRED`; exact transport semantics remain unverified. |
| E. Canonical sorted/deduplicated slots | Feed unsorted, repeated known suggestions to an approved isolated Flow-expression harness; the live Outlook service cannot guarantee this response fixture. Inspect only the terminal slot string. | Parseable JSON contains only distinct `{startUtc,endUtc}` entries in ascending UTC order; duration/count/32,768-character limits hold. | Only in the approved test harness. | No for a stubbed response. | **Blocked pending a separately approved test seam.** Existing C# adapter tests do not prove WDL serialization. |
| F. Terminal outcomes | Run separate synthetic requests for (1) a valid free window, (2) a valid window with no eligible free result, and (3) one safely induced provider/Flow failure. Do not change credentials or permissions to force an error; if no safe failure fixture exists, use an approved harness. | Available: state 100000001, nonempty canonical slots, null reason/error. NoSlots: 100000002, reason `NO_COMMON_SLOT`, empty slots, null error. Failed: 100000003, safe allowlisted error, empty slots. Each run has one terminal result write. | Yes: one AVQ row per case. | Yes for Available/NoSlots and provider-failure case; not necessarily for harness failure. | `AUTHORIZATION_REQUIRED`; zero retries. Ambiguous writes stop and reconcile. |
| G. Required TA and Onsite room matching | Use the synthetic TA online, then TA plus resource mailbox onsite. Arrange free and busy states only in preapproved windows; any calendar event used to create a busy state is separately authorized. | Available only when every expected attendee is exactly free with the expected type; busy/unknown/missing required attendee yields no Available slot. No Candidate or schedule access. | Yes: one AVQ row per case; calendar fixture writes may also be required. | Yes. | `AUTHORIZATION_REQUIRED`. Stop on unexpected attendee shape or timezone. |
| H. Duplicate, missing, extra, and conflicting attendee observations | Identical-free, identical-nonfree, contradictory same-interval, duplicate/missing expected attendee, and extra-attendee fixtures require a controlled provider response. Use an approved isolated harness; existing SDK tests cover adapter semantics only. | Exact expected TA/room identity and type govern the result; conflicting/unknown/malformed data fails closed; extra attendees cannot replace required ones. | Only in an approved test harness. | No for stubbed response. | **Blocked pending a separately approved test seam.** Do not manipulate or substitute the deployed connector. |
| I. Reference drift after a valid snapshot | With an authorized reference-data operator, change only an active state or normalized email on a synthetic TA/Location after the provider call starts and before terminal write. Use two already-approved synthetic domains if changing email. Do not update the query lookup or bypass the guard. | Relevant change/unreadable reference overrides the proposed outcome with Failed / `REFERENCE_CHANGED` / empty reason / `[]`. Capture the safe terminal code and timestamps only. | Yes: one AVQ row plus an authorized TA/Location update. | Yes. | `AUTHORIZATION_REQUIRED`; timing must be bounded. A query-lookup ID change is not safely producible through the current guarded path and requires an approved harness; never bypass the guard. |
| J. Pre-validation errors retain their category | Exercise a guard-valid request that the Flow alone rejects, if such a fixture is proven from the exact expressions. For invalid references/requests rejected by the PreOperation guard, verify the guard rejection rather than claiming a Flow run. Flow-only malformed inputs require an approved harness. | Guard-rejected requests create no row and trigger no Flow. A Flow-level rejection keeps its original safe category and never becomes `REFERENCE_CHANGED` without a validated snapshot. | Attempt may be rejected before row creation; harness may require a test row. | No for guard-rejected case; conditional for harness. | `AUTHORIZATION_REQUIRED` for the negative attempt/harness. No direct writes or guard bypass. |
| K. Trigger filter and bounded concurrency | Read back Create/Pending filter and concurrency 1. For a runtime concurrency probe, create two authorized synthetic Pending requests close together with no unrelated Pending rows. A non-Pending Create cannot be produced through the current guard because Create forces Pending. | Only accepted new Pending requests run; no more than one Flow run is concurrent. This does not prove transactional exactly-once behavior. Capture run counts and start/end timestamps. | Yes: one static read-only check; two AVQ rows for concurrency test. | Yes for each accepted request. | `AUTHORIZATION_REQUIRED`. Non-Pending negative case remains static/harness-only; stop on duplicate or unexpected run. |
| L. Run-history privacy | After Gate 2 readback, execute one approved synthetic request through every reachable sensitive action/loop. Inspect trigger, connector, SetVariable, Scope, If, Foreach, Query, Compose, and array-variable history. Do not export or copy raw values. | Every sensitive input/output is obscured; evidence records only action name/type and pass/fail. Any visible address, snapshot, response, diagnostic, observation, or slot value is a hard stop. | Yes: one AVQ row. | Yes for the complete valid path. | `AUTHORIZATION_REQUIRED`. Gate 3 only; no activation unless temporary-run authorization explicitly covers privacy inspection. |
| M. Elevated owner versus separate BSO requester | Create the query as the separately approved BSO test user; let the existing owner-bound Flow connections perform reads/result update. Keep Availability Integration unassigned. An unauthorized BSO result-write negative test requires separate approval. | Creator and result writer remain distinct; no BSO impersonation; only the owner result writer can pass the guard's terminal update checks. Report role/identity class, not GUIDs. Elevated DEV behavior is not least-privilege acceptance. | Yes: one AVQ row; optional denied update attempt. | Yes for the full valid path. | `AUTHORIZATION_REQUIRED`; any identity collapse or unexpected role change stops the test. |
| N. Candidate/Core and business-table preservation | Take authorized before/after snapshots of Candidate, Call Log, Status History, Interview Schedule, and Operation Receipt counts; compare Candidate Core package/API, all 50 legacy guard states, roles, Solution membership, Console hashes, and effective `availabilityEnabled`. Bound snapshots to the test window and distinguish unrelated concurrent activity. | No Candidate/Core/business-table mutation; Core/API and frozen release fingerprints unchanged; 50 legacy guards disabled; roles and Console unchanged; effective availability remains false after the probe. | Read-only snapshots; the associated probe creates only the authorized AVQ row(s). | No additional call beyond the associated probe. | `AUTHORIZATION_REQUIRED`. Any unexplained change stops rollout and preserves evidence; do not repair automatically. |

No scenario above was executed for this assessment. Each live write, temporary Flow activation, guard registration, mailbox/calendar operation, or reference-data change requires its own explicit authorization and must use synthetic data only.

## 7. Staged controlled execution plan

| Stage | Permitted scope and required authorization | Required evidence / pass condition | Stop and recovery boundary |
|---|---|---|---|
| A — Read-only preflight | Owner supplies and confirms the exact VN LMV IT URL and explicitly authorizes read-only inspection. No writes. | Verify `pac org who`/equivalent identity against the confirmed URL; unmanaged `os_sr_bso_rs_support`; Flow unique name, state, current definition/hash/ETag/run count; guard package/type/step count; connection references and nonsecret binding metadata; seven definitions/value state; role maps/assignments; Console hashes/effective gate; Candidate Core package/API; 50 disabled legacy guards; zero/current AVQ rows; time-windowed business counts; frozen release fingerprints. | Any wrong environment, ambiguity, unapproved drift, incomplete Flow bytes, or unauthorized read stops all later stages. Record exact read-only operation as `AUTHORIZATION_REQUIRED` until approved. |
| B — Hardened Flow update | Separate explicit approval for one existing-Flow definition update only. Flow remains OFF. | Apply only the local privacy delta; conditional update where supported; one write, zero retries; immediate definition/readback hash and Gate 2 proof; same references/membership/display name; no new run. | If single-component update or concurrency control is unverified, do not write. On ambiguous outcome, reconcile read-only; never retry. Rollback requires separate approval. |
| C — Configuration and guard registration | Separate approvals for all seven canonical values, the DEV result-writer binding, explicit execution order, and registration of exactly the two source-defined steps. Flow remains OFF. | Render configuration once; identical bytes on both steps; verify exact handler/message/table/stage/mode/filter/user/images/order, package/type, caller/initiator rules, and role topology. Do not change Candidate Core, roles, or Console. | Missing/invalid/unapproved value, incomplete registration metadata, duplicate/partial step, or mismatch stops. No automatic repair. |
| D — Synthetic first-runtime probe | IT provisions prerequisites. Separate explicit authorization to turn the Flow ON temporarily, create the specified synthetic query, make one Outlook call, inspect privacy, and return Flow to OFF. | One bounded request; exact provider/UTC and terminal evidence; Gate 3 pass; only approved synthetic records; query result reconciled; Flow readback OFF and run count consistent. | Stop after the first unexpected provider shape, exposed sensitive value, ambiguous outcome, or guard mismatch. Zero retries. No second query under this authorization. |
| E — Extended functional/security acceptance | Separate authorization for each additional matrix scenario, any test seam, controlled calendar/reference fixtures, and a non-elevated identity if least-privilege acceptance is required. | Matrix cases pass; BSO and owner remain distinct; Integration role unassigned unless a future separate decision approves otherwise; preservation checks pass. | No permission elevation, role assignment, guard bypass, or test-seam deployment by implication. Failures require review before another run. |
| F — Feature exposure decision | Distinct product/Technical Lead/security approval; not included in this plan. | Decide whether and when to change effective `availabilityEnabled`; separately review Console exposure and release/ALM impact. | Do not enable the feature or publish Console resources during A–E. |

The latest report's expected readback for Stage A is 66 Solution memberships; BSO role at 65 entries; Availability Integration role at exactly four Global privileges and unassigned; Reference Admin unchanged and unassigned; seven definitions present and value-less; guard package/type present with zero steps; Flow OFF with zero runs; zero Availability Query rows; Candidate Core unchanged; all 50 legacy guards disabled; and effective `availabilityEnabled = false`. These are comparison targets from historical evidence, not freshly verified state. The same report records business counts `47, 64, 163, 45, 183`; Stage A must map each count to its table and capture a bounded test-window baseline rather than infer the mapping from this list.

The existing published Console resources remain as reported and the effective setting remains `availabilityEnabled = false`. No `srapp`, sitemap, unrelated WebResource, or Console publication is part of the Flow update.

## 8. Risk register

| Severity | Risk / evidence | Impact | Mitigation | Owner (role; individual not recorded) | Blocking? |
|---|---|---|---|---|---|
| High | Current live definition/state/ETag not freshly read; last live equality evidence is deployment-time only. | Cannot safely establish the current update baseline. | Authorized Stage A read-only preflight and exact readback before any write. | Environment owner / Flow owner | Yes, blocks Stage B. |
| High | Secure-data behavior is unverified for the trigger and 8 action types. | Sensitive mailbox/reference/provider data may appear in run history. | Gate 2 definition readback and Gate 3 synthetic run-history inspection; stop on any exposure. | Power Platform owner / Privacy-Security | Yes, blocks activation. |
| High | Synthetic TA/room mailboxes and approved domains are missing. | No safe provider/runtime test can occur. | IT-owned mailbox provisioning, access and windows; no `.invalid` live target. | IT mailbox administrator | Yes, blocks D/E. |
| High | Seven definitions have no approved values. | Guard/Flow cannot be safely configured or activated. | Obtain value-by-value product/IT approval; render canonically; no invented defaults. | Product owner / Technical Lead / IT | Yes, blocks C/D. |
| High | Registration contract omits execution order; deployed guard has zero steps per report. | Registration could be ambiguous or unsafe. | Obtain an explicit approved order and reconcile the contract before registering exactly two steps. | Technical Lead / Dataverse owner | Yes, blocks C. |
| High | DEV owner is elevated; `DEV_FUNCTIONAL_IDENTITY_ELEVATED_NOT_SECURITY_ACCEPTANCE`. | Functional success cannot establish least-privilege security. | Preserve identity separation; use a separately approved BSO requester and later non-elevated security test. | Security owner / Environment owner | Yes, blocks security acceptance. |
| Medium | `Float`/`int(string(...))`, WDL null behavior, sort/union ordering, and string serialization are not runtime verified. | Runtime binding or result serialization may differ from offline expectations. | First-runtime matrix with safe values and no retry; stop on mismatch. | Flow owner / Technical Lead | Yes, blocks functional acceptance. |
| Medium | Retry and display-name discrepancies exist between contract and deployment report. | Could silently broaden behavior or target metadata incorrectly. | Preserve live metadata; resolve retry policy before runtime acceptance; target by unique name and Solution. | Flow owner / Technical Lead | Yes, blocks final contract acceptance. |
| Medium | Standard Outlook connector cannot deterministically inject malformed/duplicate response shapes; some guard-rejected requests cannot reach Flow validation. | Several negative WDL branches cannot be proven against the live Flow as-is. | Keep current guard intact; use only a separately approved isolated test seam or report those cases as untested. | Power Platform owner / Technical Lead | Yes, blocks those test cases. |
| Medium | Concurrent tenant activity may change unrelated counts during probes. | False attribution of changes to Slice 2A. | Capture bounded before/after windows, table-specific counts, and audit evidence; distinguish unrelated activity. | Test operator / Environment owner | Yes, blocks preservation pass if unresolved. |

## 9. Authorization and input request list

All items below remain outstanding for future execution; none is granted by this report.

1. **Stage A:** exact DEV environment URL and explicit authorization for the listed read-only operations. This task did not connect.
2. **Stage B:** separate approval for one OFF Flow definition update; confirmation of supported single-component update and concurrency/readback behavior.
3. **Contract closure:** owner/Technical Lead decision on the retry mismatch and registration execution order; reconcile the display-name discrepancy by readback, not rename.
4. **Stage C:** approved values for all seven environment variables and approval of the environment-specific nonsecret result-writer binding.
5. **IT prerequisite:** distinct synthetic TA and room mailboxes, approved domains, ownership/admin consent, Outlook access/free-busy, and test windows.
6. **Guard registration:** explicit authorization to register exactly two synchronous steps with the metadata in this report plus an approved execution order and exact rendered configuration.
7. **Stage D:** explicit, temporary Flow activation authorization covering one synthetic AVQ create, one Outlook call, sanitized run-history inspection, and return to OFF.
8. **Stage E:** per-scenario authorization for additional query rows, calendar/reference writes, denied-write tests, test-harness design/deployment, and any non-elevated identity acceptance.
9. **Stage F:** a separate feature-exposure decision; no `availabilityEnabled` change is implied.

No Production approval, connection creation, credential/consent/CA change, Candidate operation, Core change, Console publish, commit, or push is requested or authorized here.

## 10. Offline validation performed

The following checks were run locally; none connects to the tenant or invokes Outlook:

| Command | Result |
|---|---|
| `pwsh -NoLogo -NoProfile -File .\tests\AvailabilityQuery.Tests.ps1` | 168 checks passed |
| `dotnet run --project .\tests\AvailabilityQuerySdk\AvailabilityQuerySdk.Tests.csproj` | 520 checks passed |
| `pwsh -NoLogo -NoProfile -File .\tests\CandidateConsole.Tests.ps1` | 78 checks passed |
| `pwsh -NoLogo -NoProfile -File .\tests\BsoRsSolutionMembership.Tests.ps1` | 19 checks passed |
| `node --test .\tests\CandidateConsoleAvailability.test.cjs` | 8 tests passed |
| `node --check .\solutions\CandidateConsole\WebResources\os_\bso\candidate-console-availability.js` | Passed |
| Flow/contract JSON syntax and duplicate-key validation | 2 files passed |
| `git diff --check` | Passed |
| Git baseline/hash comparison | Historical Flow source hash matched the deployment report's abbreviated baseline; the Flow diff contains secure-data settings only. |

Two broader repository gates were also run and **did not pass**:

| Command | Result and interpretation |
|---|---|
| `pwsh -NoLogo -NoProfile -File .\tests\BsoRsReleaseSource.Tests.ps1` | Failed its canonical-source scan because the pre-existing local Flow contract contains a DEV environment label. The scan found no evidence in this output of a credential or production URL. No Solution source was changed by this assessment. |
| `pwsh -NoLogo -NoProfile -File .\tests\BsoRsProductionReadiness.Tests.ps1` | Failed the frozen canonical source/root fingerprint assertion. The measured canonical Solution source is 191 files / `6fc18176a1b891a417b7c48e14da2a6b7fbc08a0958c1831c022666337afc3d6`; the frozen manifest expects 171 files / `fff8b7879c2b756f3a2b1753159135a0dc00a890a20e4445870a0fd23ea984d1`. This is consistent with the already documented `P0_SOURCE_AHEAD_OF_FROZEN_RELEASE_ARTIFACT`; it is not evidence that the frozen artifact or manifest changed in this task. No pin was updated or test bypass used. |

These are offline source checks, not Power Automate import, run-history, runtime, security, or Production acceptance.

## 11. Preservation statement

For this assessment: no tenant connection or read/write operation occurred; no Flow, guard, connection, environment value, mailbox, reference row, query row, calendar, Candidate, Call Log, Status History, Interview Schedule, Receipt, Candidate Core, role, Console resource, or release artifact was changed. No Flow was activated, no Outlook call was made, and no publication, commit, or push occurred.

The local Flow source and contract hashes above are evidence of repository bytes only. Historical preservation targets are BSO's exact 65-entry map, the unassigned four-privilege Availability Integration role, unchanged/unassigned Reference Admin, existing connection references/connections, unchanged Candidate Core package/API, 50 disabled legacy guards, unchanged Solution membership, existing published Console resources with `availabilityEnabled = false`, unchanged frozen managed artifacts/manifests/fingerprints, and no Candidate/Call/History/Interview/Receipt mutation. The reported deployed Flow remains OFF, but its current live state was not freshly verified in this assessment. The historical deployment report remains intact; this report does not replace or rewrite its evidence.
