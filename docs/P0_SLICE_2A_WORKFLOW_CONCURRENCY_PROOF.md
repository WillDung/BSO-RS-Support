# P0 Slice 2A — Workflow conditional-update capability proof

**Agent B assessment, 2026-11-06.**

**Classification: `WORKFLOW_CLIENTDATA_CONDITIONAL_UPDATE_UNPROVEN`.**

**Concurrency sub-outcome: SUPPORTED. State/metadata/definition preservation sub-outcome: UNPROVEN for the proposed complete update.** This overall classification covers the requested end-to-end OFF/privacy-preserving operation, not just its concurrency mechanism. It is not a finding that Workflow updates are unsupported.

Microsoft documents updating solution-aware cloud flows through Dataverse, identifies `clientdata` as their definition and connection-reference document, and documents exact-ETag conditional PATCH semantics. These contracts compose: the identity-gated fresh Workflow metadata read returned `IsOptimisticConcurrencyEnabled=true`, and the exact existing OFF Flow read returned an opaque HTTP ETag. A Workflow-specific conditional-update example or an experimental stale PATCH is not required to establish the supported concurrency method.

The remaining gap is narrower than the earlier generic-method report: public documentation does not promise that this entire proposed privacy delta survives service normalization, and no update/readback was performed to establish post-update OFF state, installation identity, owner, bindings and membership. No experimental write was used to fill that gap. The method is documented; execution and preservation acceptance are not granted.

## 1. Bounded preflight and factual baseline

| Item | Scope and disposition |
| --- | --- |
| Requested outcome | Establish whether an exact-version, existing-record, `clientdata`-only update of OFF `os_sr_avchk` has supported semantics; distinguish concurrency from preservation and runtime privacy. |
| Repository baseline | Clean worktree at `0486cdd` when inspected. Only this report is authored by Agent B. No source, tests, shared documents, or earlier reports are changed. |
| Required reading | [Project context](PROJECT_CONTEXT.md), [Current State](CURRENT_STATE.md), [production rules](../MASTER_PRODUCTION_RULES.md), [workflow](../WORKFLOW.md), [project rules](../PROJECT_RULES.md), repository documentation guidance, and the four fast-track reports linked below. |
| Historical implementation | The [Stage A live report](P0_SLICE_2A_STAGE_A_LIVE_PREFLIGHT_REPORT.md) and [earlier method assessment](P0_SLICE_2A_STAGE_B_FLOW_UPDATE_METHOD.md) record an OFF, pre-hardening solution-aware Flow; `statecode=0`, `statuscode=1`; an SDK RowVersion; and previously reconciled membership. These are **historical**, not fresh observations in this assessment. |
| Authorized investigation | Public Microsoft documentation; bounded local approval/guard/summary evidence; managed read-surface schema discovery. Tenant reads were conditional on independently establishing the approved target and caller first. |
| Dependencies and risks | Identity provenance and table capability were resolved below; Flow service normalization, complete stable-installation baseline, connection and membership preservation, separate execution approval, and separate runtime privacy acceptance remain. A new fresh token is needed immediately before any later approved dispatch. |
| Validation plan | Inspect citations and reasoning, distinguish historical/fresh evidence, verify relative file links, final newline, whitespace, obvious privacy patterns, and own-file diff. No application suite is warranted for a report-only change. |

The prior [Console plan](P0_SLICE_2A_STAGE_A1_CONSOLE_CORRECTION_PLAN.md), [Flow method assessment](P0_SLICE_2A_STAGE_B_FLOW_UPDATE_METHOD.md), [QA review](P0_SLICE_2A_FAST_TRACK_QA_REVIEW.md), and [consolidated readiness report](P0_SLICE_2A_FAST_TRACK_EXECUTION_READINESS.md) remain unchanged. This report narrows the earlier generic-method uncertainty; it does not close Stage A drift or authorize an exception.

## 2. Identity gate — approved retained pin recovered and freshly matched

An independently retained execution baseline can qualify without a newly typed user identifier, **if** its identity value is traceable to the explicitly authorized and accepted DEV Option A owner. Merely agreeing with today's PAC caller cannot create that provenance.

The bounded investigation examined the retained session's `files\rw` summaries and guarded source, their directly referenced Slice 2A common/preflight source and baseline property structure, and selected historical user/tool evidence:

1. The historical owner runtime-wiring instruction explicitly retained `SLICE_2A_DEV_IDENTITY_OPTION_A_APPROVED` and authorized binding both references to the already-existing Connected connections owned by the approved current DEV owner. The [provisioning report](P0_SLICE_2A_DEV_PROVISIONING_REPORT.md) records the resulting accepted feature-OFF wiring. This establishes **approval provenance**, not by itself a recoverable caller identifier.
2. `Rw-Common.ps1` checks WhoAmI against expected organization and user values. Tracing its dependency shows that `Assert-PacIdentity` in the known guarded provisioning source assigns `ExpectedUserId` from the PAC output being checked. That is a contemporaneous cross-surface consistency check, **not an independent historical caller pin**. The helper was inspected as text, never executed or dot-sourced.
3. Retained `rw-preflight.json` has `Classification` and `Snapshot`, without a retained WhoAmI/caller field. `rw-final.json`'s Flow summary has identity/name/category/type/state/hash/result fields but no owner/caller field; its connection-reference summaries have reference/binding/state fields, not an independently retained connection creator/caller identity. No connection or definition bytes are reproduced here.
4. The initially inspected later PAC result was redacted. Agent A then located an earlier **pre-existing retained PAC execution result dated 2026-11-05T13:51:56Z** containing a usable caller and exact target baseline. Agent B independently verified the historical owner instructions at **13:32:33Z** (bounded VN LMV IT provisioning with Option A approved), **14:14:30Z** (partial-schema acceptance and authorized continuation), and **15:03:13Z** (accepted infrastructure/current DEV-owner Option A runtime wiring). Agent B independently extracted that exact retained execution result in memory; no value was printed or persisted. This is the approval-linked execution baseline, not a pin invented from today's observation. A connection identifier or an unmapped Entra creator identifier was not substituted.

**Result: identity gate PASS.** Before project/metadata reads, Agent B compared the historical origin, organization and environment to the independently retained guarded target literals; required exact VN LMV IT; ran `pac env who --environment <privately-resolved-approved-origin>` using the existing context; and matched origin, environment, organization and caller to that historical pin. The existing managed Az account matched the historical account, and an independent exact-origin Dataverse WhoAmI GET matched the approved caller and organization.

Existing `Az.Accounts` supplied the access token in memory; no write-capable helper was executed or dot-sourced, no raw token cache or credentials were inspected, and no login, environment/profile selection or authentication recreation occurred. Exact-origin GETs disabled retries and redirects. Tokens, caller/target identifiers and URLs were not persisted. The actual four-GET ledger is in section 9; PAC's internal request count was not measured.

### Fresh sanitized metadata, after the gate

| Exact scoped read | Fresh result |
| --- | --- |
| Workflow `EntityDefinitions`, selecting only `IsOptimisticConcurrencyEnabled` | **true**. |
| Existing Flow resolved by retained runtime-wiring object identity; no definition requested | Same historical `workflowid`, exact name `os_sr_avchk`, category **5**, type **1**, OFF **statecode 0/statuscode 1**, unmanaged, `componentstate=0`. |
| Installation/ownership/version fields of that same record | `workflowidunique` is present and well-formed; owner equals the independently approved Option A caller pin; `versionnumber` is present; fresh `@odata.etag` has opaque weak-ETag syntax. Values intentionally withheld and not retained. No older `workflowidunique` baseline was recovered, so cross-time installation equality is not claimed. |
| Solution components filtered by retained approved Solution identity, `componenttype=29`, and the exact Flow object | Exactly **one** membership, object matches the Flow, no next page. This is not a refreshed 66-component inventory or proof about all other memberships. |

No `clientdata`, unrelated Flow definition, connection binding, run/history or business row was read. The fresh OFF observation is not a post-update preservation test. `componentstate=0` is not proof of designer-version/draft semantics.

## 3. Microsoft contracts that actually apply

All sources below are Microsoft primary documentation retrieved for this assessment without tenant content. External URLs are public documentation only.

| Primary authority | Applicable normative content | Limit of that evidence |
| --- | --- | --- |
| [Work with cloud flows using code](https://learn.microsoft.com/en-us/power-automate/manage-flows-with-code) | Explicitly covers flows on the **Solutions** tab; permits Dataverse SDK or Web API management. `workflowid` identifies a flow across imports; `workflowidunique` identifies its installation. `clientdata` is string-encoded JSON containing definition and connection references. Under **Update a cloud flow**: “set only the properties you want to change.” | Its sample changes owner/state/description and uses `If-Match: *`. Those sample choices are not mandatory update properties and are not an exact-version example. The creation default OFF statement is not a promise about updating an existing Flow. |
| [Workflow table reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/workflow) and [Web API Workflow EntityType](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/workflow) | Workflow's documented Update operation is `PATCH /workflows(workflowid)`, linked to the generic Web API update contract. The table lists ClientData as writable; the Web API represents it as `Edm.String`. The primary key is `workflowid`, not `workflowidunique`. | The writable-list introduction allows create **or** update validity; that list alone would not prove every column's update semantics. Here it is read together with solution-flow authoring and the documented Update operation. Neither reference provides this tenant's concurrency flag or a guarantee about every secure-data combination. |
| [Update/delete table rows — basic update](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/update-delete-table-rows#basic-update) | PATCH sends the properties being changed. Microsoft explicitly warns against resending unchanged properties because that can trigger business logic and auditing. | A minimal request limits **submitted changes**; it does not prove that platform processing cannot normalize data or affect derived metadata. |
| [Perform conditional operations — optimistic concurrency](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/perform-conditional-operations-using-web-api#apply-optimistic-concurrency) | Dataverse supports ETag conditional operations. Exact `If-Match` on update fails with `412 Precondition Failed` if the version differs; a match permits the update. ETags are opaque. The article documents the table capability metadata read. | Actual Workflow capability was established by the scoped live read, not inferred from an account sample or ETag presence. No stale-token mutation is necessary to apply this normative contract, and none is authorized here. |
| [Optimistic concurrency](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/optimistic-concurrency) | Check `IsOptimisticConcurrencyEnabled`. Supports SDK `UpdateRequest` with `ConcurrencyBehavior.IfRowVersionMatches`, and links the corresponding Web API mechanism. | “All custom tables” does not prove applicability to this system table. SDK support does not make an arbitrary helper conditional. |
| [Edit a solution-aware cloud flow](https://learn.microsoft.com/en-us/power-automate/edit-solution-aware-flow) | Stop a flow before editing; turning it on is a separate step. Editing the existing Flow is supported. **Save As** duplicates it. | Designer procedure is not a documented exact-version HTTP precondition, nor a promise that a code PATCH and designer draft publication have identical internals. |
| [Drafts and versioning](https://learn.microsoft.com/en-us/power-automate/drafts-versioning) | Solution-aware flows have distinct draft/published versions; publication makes changes effective at runtime. | UI Draft/Published status must not be conflated with `statecode` OFF/ON or assumed to identify a specific Dataverse versioned layer. No undocumented draft/version endpoint or PublishXml step is inferred. |

### Composition, rather than a missing-sample veto

The positive support chain is: **solution-aware cloud flow → Workflow record → documented Workflow Update/PATCH → selected-property update → generic Dataverse exact-ETag precondition, when optimistic concurrency is enabled for that table**. The Workflow reference itself links its Update operation to the generic update documentation. The docs do not restrict exact-ETag semantics to accounts or explicitly exempt solution-aware `clientdata`.

Therefore, a table-specific conditional-PATCH example or an experimental stale PATCH is **not required** to establish supported concurrency here: the actual metadata is true, the exact category-5 existing Flow was retrieved through the documented entity set, and its fresh HTTP ETag was returned. This establishes normative precondition enforcement for the documented update, not an observed mutation test or proof of service-side privacy normalization.

Any later execution must revalidate capability and obtain its own fresh exact-record ETag rather than reuse this observation. If capability is then false, this route no longer meets the requirement; do not enable the flag or substitute a wildcard. An ETag alone cannot overrule the capability result.

## 4. Four version concepts, and what they protect

| Concept | Meaning and permitted use |
| --- | --- |
| SDK `Entity.RowVersion` | SDK concurrency property used with the documented `UpdateRequest` and `IfRowVersionMatches`. A historical value is not a fresh HTTP token; an ordinary SDK `Update` without the required concurrency behavior is not equivalent. |
| `versionnumber` | Read-only row-version column. Useful as metadata evidence, not an independently constructed HTTP precondition. Do not turn its digits into `W/"..."`. |
| Fresh `@odata.etag` | The opaque value returned by the **same exact record** Web API read at the approved origin. Preserve its syntax privately and verbatim. It does not cover separate connection-reference records, solution-component records, other actors, or the whole installation. |
| Actual `If-Match` enforcement | The precondition on the supported PATCH, established by the applicable Dataverse contract and actual table capability. Getting an ETag or placing a header in a proposed request is not itself proof that a helper transmits/enforces it. The proposed executor must demonstrably preserve the header and disable automatic retry. |

`If-Match: *` checks record existence, not equality with the previously read version, and is **unacceptable**. ModifiedOn comparisons and preflight/readback alone do not close a concurrent-edit race. No numeric ordering or relationship among ETags is assumed.

The discovered Dataverse MCP schema offers reads but no explicit target argument on `read_query`; the discovered `invoke_api` is a Custom API invocation surface, not an arbitrary HTTP GET facility. These schemas alone cannot expose the required exact-origin metadata/HTTP-token path. Therefore the bounded GETs used existing managed Az authentication and an explicitly restricted HTTP reader, not a Custom API workaround or a write-capable helper. This is a surface limitation, not platform unsupportedness.

## 5. Separate preservation proof obligations

| Obligation | Established contract or historical evidence | Current outcome |
| --- | --- | --- |
| Existing-record authoring | Documented Workflow PATCH and selected-property solution-flow update. No create, delete/recreate, Save As, or import is necessary to express the intended change. | **Documented method; exact existing category-5 target freshly matched.** |
| Exact-version concurrency | Normative generic contract composes with the documented Workflow Update operation; actual capability is true and an opaque token was freshly observed. | **SUPPORTED.** No mutation test, token construction or wildcard substitution was used. |
| Flow and installation identity | Address the retained existing `workflowid`; do not submit identity, owner or state properties. Microsoft distinguishes `workflowid` from `workflowidunique`. | Submitted scope can preserve identity by design; actual stable `workflowid`, `workflowidunique` and any separately retained installation identity still need pre/post comparison. Do not claim a reinstall or installation-identity guarantee from the URI alone. |
| Owner, OFF state, category/type | Omit these properties; never copy the example's `ownerid` or `statecode=1`. Fresh OFF is `0/1`, category/type `5/1`; owner matches the approved pin. Editing while stopped is documented. | **Fresh baseline passed; post-update preservation unproven.** Property omission does not prove all service-side behavior. |
| Connections | `clientdata` includes the connection-reference mapping; the approved semantic delta must preserve it exactly. A `clientdata`-only request replaces that string as a whole, not individual nested JSON paths. | Existing bindings and separate connection records are not protected by the Workflow ETag. No current binding or preservation claim is made. |
| Solution membership/layers | No membership operation is part of the PATCH; updating an existing member is different from adding/recreating a Flow. | One exact approved Solution membership freshly matched; independent later pre/post comparison remains required. A Workflow ETag is not a membership lock. No solution header is asserted mandatory without applicable documentation. |
| Definition normalization | Prior offline evidence isolates privacy changes only. | **Unproven for this full delta.** A capability flag cannot prove acceptance/retention of trigger and all action-type settings, default insertion, or draft/published behavior. |
| Runtime privacy | [Microsoft secure-data guidance](https://learn.microsoft.com/en-us/power-automate/guidance/coding-guidelines/use-secure-inputs-outputs-triggers) documents secure inputs/outputs settings. | **Not tested.** Accepted JSON is not evidence that every relevant runtime path hides sensitive values. |

No whole-record freeze is claimed: a legitimate successful update normally changes system version/modification metadata. Preservation means specified stable business/installation identities, state, bindings and membership, plus an explicitly reviewed complete definition; it does not require the old ETag or ModifiedOn to remain unchanged.

## 6. Non-executing candidate specification and exact later gates

**Reviewed NON-EXECUTING specification; not execution-ready. No mutation request or payload was constructed or sent.** The concurrency method is supported; the following bounds a future proposal without bypassing the overall preservation/normalization gap.

1. **Identity and authorization:** revalidate against the independently retained accepted Option A pin; privately verify exact origin, environment, organization, actual managed caller and target. Require separate one-shot update approval and Stage A correction/explicit exception disposition. No reauthentication or environment selection is implicit.
2. **Minimal permitted future metadata read:** only `EntityDefinitions(LogicalName='workflow')?$select=IsOptimisticConcurrencyEnabled`. Require true for the optimistic-concurrency method. Do not change metadata to make the gate pass.
3. **Exact-record preflight:** retrieve only the approved Flow's `workflowid`, `workflowidunique`, name, category/type, `statecode/statuscode`, owner lookup, managed/layer indicators where supported, `versionnumber`, and fresh opaque HTTP ETag. Match the existing Flow identity and approved Solution's type-29 membership with narrowly filtered reads; never list other definitions. This assessment observed but did not retain the installation identifier. Obtain an approved recoverable pre-update installation baseline; absence of an older comparison is a gap, not permission to adopt a different record.
4. **Definition/binding approval:** only under the later approved definition-read scope, read the exact Flow `clientdata` in memory, reject duplicate keys, and compare the entire structure against its approved baseline. Verify reference mappings and actual binding evidence without exposing or persisting connection bytes. Separately authorize the minimum binding metadata read if needed. The current task did not perform this definition read.
5. **Delta:** replace only `clientdata`, encoded as a JSON string containing the fully reviewed definition. No owner/state/category/type/identity/connection-reference-row/member/configuration property is submitted. The conceptual destination is the existing `/api/data/v9.2/workflows(<approved-existing-workflowid>)`; the precondition is that same fresh read's exact opaque `If-Match`, never `*`. No undocumented solution-context header, PublishXml, Flow publication/activation, or second operation is appended.
6. **Dispatch boundary:** first review a non-executing executor specification proving exact origin, no redirects, no implicit retries, verbatim precondition, single existing-record destination and `clientdata`-only body. This report implements no executor and grants no dispatch permission. Other actors changing related records remain outside this row token; any required exclusion window must cover those dependencies.
7. **Gate 2:** after a separately authorized acknowledged update, independently reread the same record and exact membership. Require identical Flow/installation identities, owner, OFF `0/1`, category/type, managed/layer expectations, complete connection mappings/bindings and approved membership. Reject duplicate keys and compare the entire returned definition against the reviewed candidate, not merely a hash or selected action. Unexpected normalization, settings dropped/rewritten, state or layer ambiguity, missing metadata, or unrelated drift is **STOP**, not assumed equivalence. A 2xx alone does not pass.

### Privacy inventory carried forward, not freshly remeasured

The [earlier method report](P0_SLICE_2A_STAGE_B_FLOW_UPDATE_METHOD.md#reproduced-offline-structural-comparison) and [QA comparison](P0_SLICE_2A_FAST_TRACK_QA_REVIEW.md#c4--high-serialized-privacy-settings-are-not-runtime-privacy-acceptance) are the prior evidence for **26** changed `runtimeConfiguration.secureData` sites: one trigger and 25 actions. This assessment did not rerun their comparison, retrieve live clientdata, or claim new tests.

Gate 2 must check all of those sites: trigger outputs; `Compose_free`, `Compose_slot`, `Compose_validation_error`, `Compose_drift`, `Compose_location_drift`, `Compose_terminal`, `Compose_canonical_slots`, `Compose_proposed_result`; `Check_response_shape`, `Check_slot_eligible`, `Check_suggestion_valid`, `Check_suggestion_timezone`, `If_validated_snapshot`; `Append_observation`, `Append_slot`; `For_each_suggestion`; `Set_result_slots`, `Set_location_snapshot`, `Set_ta_snapshot`, `Set_location_changed`; `Evaluate`, `Reread_references`, `Map_failure`; `Read_query`, `Write_terminal_result`.

It must also retain the eight already protected actions: `Read_ta`, `Read_location`, `Find_meeting_times`, `Reread_ta`, `Reread_location`, `Find_invalid_attendees`, `Find_ta_entries`, `Find_room_entries`. That is **33 protected actions**, including `Set_location_changed` outside the contract's 32-action inventory, plus the trigger. Require the exact intended inputs/outputs combinations, not mere presence of `secureData`. Trigger/action structure, expressions, concurrency, retries, terminal writes and references must otherwise match completely.

**Separate runtime privacy gap:** Gate 2 cannot prove run-history suppression. Only a separately approved synthetic runtime matrix can exercise relevant trigger, connector, Compose, variable/array, Query and nested control paths and inspect sanitized outcomes. No Outlook/Candidate calls, run history, activation, synthetic runtime, mailbox access, guard/configuration/role change, or feature enablement belongs to this capability proof. The synthetic-mailbox blocker and elevated-DEV-identity security limitation remain historical open gates.

## 7. Isolated supported alternatives — no silent ALM expansion

The exact-existing-Flow designer edit is a documented isolated authoring alternative, with stop/edit/save and separate turn-on steps. It neither requires a whole-solution import nor a new Flow identity. However, it uses the prohibited browser surface here and exposes no documented exact-version precondition in the reviewed procedure. It cannot replace this requirement with a human “last read looked current” check; **Save As** is specifically unsuitable because it duplicates the Flow.

For transport ALM, [exporting a specific solution cloud flow](https://learn.microsoft.com/en-us/power-automate/export-flow-solution#export-a-specific-solution-cloud-flow) requires a solution and its dependency closure. A smaller solution is a potential separately scoped transport, **not** a raw single-Flow import into the existing solution. No new container, component inclusion, export, package construction or import is authorized or performed here.

[Import-flow guidance](https://learn.microsoft.com/en-us/power-automate/import-flow-solution#what-will-the-flow-state-be-after-import) says an update to an already-existing OFF Flow leaves it OFF, but also documents import ownership and flow state transitions during imports. Those are ALM-specific rules, not a normative guarantee for `clientdata` PATCH, and do not provide a fresh per-Workflow ETag precondition. They cannot establish owner/installation/membership preservation for an unbuilt package.

[Solution patches](https://learn.microsoft.com/en-us/power-platform/alm/create-patches-simplify-solution-updates) and [table segmentation](https://learn.microsoft.com/en-us/power-platform/alm/segmented-solutions-alm) do not demonstrate an isolated exact-version conditional Flow update: the reviewed guidance concerns table/assets, dependencies and solution layering; patches also create parent dependencies and lock the parent against edits/exports while dependent patches exist. Do not assume “patch” means HTTP PATCH, Flow-only payload, or concurrency protection. No supported alternative was established that simultaneously preserves this scope and replaces the exact-version requirement.

## 8. Minimal missing evidence, next operation, rollback and STOP

**Shortest safe next operation:** request Microsoft product confirmation, without tenant/private payload, of whether a category-5 OFF solution-aware Flow's `clientdata`-only update preserves OFF/installation/owner/membership and retains the listed secure-data settings across service normalization. This is an evidence request, not permission to open a support case with tenant content or perform a write. If the owner accepts conditional Gate 2 verification instead of advance vendor assurance, separately approve the narrowly scoped fresh-definition/preservation preflight; do not execute from this report.

The concurrency-method question is resolved by the true live capability plus applicable normative contracts. A new fresh exact-record ETag is nevertheless a later dispatch prerequisite, not a reusable report artifact. Current connection bytes and full definition were deliberately not collected; obtaining their narrowly scoped comparison and recoverable baseline needs the separate approved scope.

**Is Microsoft confirmation necessary?**

- Not for the exact-ETag concurrency method: normative documentation composes, and owner identity/live applicability were verified. A vendor letter or experimental stale write is not required to repeat that proof.
- If Workflow reports false, do not claim the same route works, change the flag, or experiment. A different supported exact-version mechanism would need Microsoft documentation or confirmation.
- Public material reviewed does not supply an advance blanket guarantee of OFF/installation/owner/membership preservation and retention of every privacy setting in this exact `clientdata` delta. If such a guarantee is required **before any authorized update**, seek Microsoft product confirmation covering solution-aware category-5 clientdata normalization, version/draft semantics, OFF state, installation identity, owner, mappings and membership. Otherwise those outcomes remain explicit later Gate 2 acceptance obligations; runtime privacy still needs its separate gate. No vendor promise is invented.

**Rollback:** not automatic and not authorized. Before any later approved write, securely retain and independently verify the actual preceding definition and stable metadata under an approved custodian/retention policy; a hash is not a recoverable backup. A restore needs new approval, fresh identity/state/ETag, proven conditional semantics and a reviewed definition-only delta, followed by the same Gate 2. Never restore a stale whole record, recreate the Flow, change owner/state, or import a whole solution as an improvised rollback.

**Ambiguous result rule:** `412`, rejection, timeout, lost response, unexpected response/state/normalization, failed readback or related-record drift means **STOP**. No automatic retry, activation, publication, alternate-surface replay or compensating write. Only separately permitted read-only reconciliation may determine the actual outcome; uncertainty is not evidence that nothing happened.

## 9. Actual operation ledger and no-write statement

| Actual operation class | Result / boundary |
| --- | --- |
| Local repository reads | Required baselines/rules/guidance, four latest fast-track reports, targeted provisioning-report identity references, and the known guarded identity function. |
| Local retained-evidence reads | Bounded runtime-wiring approval interval and selected identity/connection evidence; summary property inspection and directly related guarded source; Agent A's earlier PAC-baseline locator followed by Agent B's independent in-memory extraction/comparison. No helper execution, token cache, credential collection, or persistence of identifiers/configuration/connection bytes. |
| Session-history discovery | Two bounded read-only history queries returned no rows; the retained local session evidence above supplied approval provenance instead. |
| Deferred-tool discovery | Searched Dataverse managed tools first; inspected discovered schemas only. **Zero** Dataverse MCP invocations, including no custom invocation. |
| Public documentation retrieval | Microsoft Learn pages cited above; SDK/update/conditional metadata references also consulted. No tenant/project payload sent to a public service. |
| Existing local managed contexts | Command/module availability check; one explicit-target `pac env who --environment` invocation, existing Az account check and in-memory managed token acquisition. PAC's internal request count was not measured; no auth/environment/profile mutation. |
| Tenant GET 1 | Exact-origin WhoAmI; caller and organization equal independently retained approved pin. Before any project/metadata read. |
| Tenant GET 2 | Exact Workflow EntityDefinitions, selecting concurrency flag only; true. |
| Tenant GET 3 | Retained exact Flow identity, selecting only the section-2 identity/state/ownership/version/layer fields; HTTP ETag observed; no `clientdata`. |
| Tenant GET 4 | Exact approved Solution + Flow object + type-29 membership filter; one row, no next page. |
| Other tenant access | **Zero** unrelated definitions, business rows, runtime/history or connection reads. No full Solution inventory. All four GETs had retries=0 and redirects=0; raw responses remained in memory only. |
| Mutation/execution | **Zero** experimental PATCH/DELETE, fake-payload requests, tenant writes, PublishXml, Flow updates/runs/activation, browser, Candidate/Outlook calls, roles/guards/config changes, credentials/login/environment selection, commit or push. No automatic retry. |
| Authored output | This report only. Other current workstream reports appearing in shared worktree status were not changed by Agent B. |

**Validation performed:** all 15 relative file-link occurrences resolved; public citation hosts were Microsoft Learn only; final newline and absence of trailing whitespace passed; the report passed an obvious GUID/tenant-origin/email/token-pattern scan. Pattern scanning is not a comprehensive privacy guarantee. `git diff --check -- docs\P0_SLICE_2A_WORKFLOW_CONCURRENCY_PROOF.md` passed; because the report is new/untracked, its full text was also checked directly for newline/whitespace. No source/application suite was run or claimed. Own-file review confirmed only this report was authored; no commit or push occurred.

This assessment ends at the capability boundary. It preserves Dataverse authority, canonical workflow, identity separation, fail-closed scheduling, email idempotency, privacy, audit, ALM and ATSugg protections in the [production rules](../MASTER_PRODUCTION_RULES.md).
