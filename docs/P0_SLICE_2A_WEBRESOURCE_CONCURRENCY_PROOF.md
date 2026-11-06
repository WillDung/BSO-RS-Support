# P0 Slice 2A WebResource concurrency capability proof

**Assessment:** 2026-11-06. **Agent A scope:** read-only capability investigation; this report only.

**Classification: `WEBRESOURCE_CONDITIONAL_UPDATE_UNPROVEN` for the required current/unpublished-layer overwrite protection.**

Actual WebResource optimistic-concurrency eligibility is **established**, not unsupported: the approved target reports `IsOptimisticConcurrencyEnabled = true`; Microsoft documents WebResource PATCH and generic exact-ETag conditional updates. The remaining uncertainty is narrower: whether an intervening unpublished edit necessarily invalidates the precondition used by the intended `webresourceset(webresourceid)` PATCH. The permitted reads found no distinct pending draft. Neither equal content nor the published ETag closes that layer-specific obligation.

**Identity gate: PASS. Publication exclusivity: NOT ESTABLISHED; a concrete organizational control is proposed below.** No platform lock is required merely because publication lacks an ETag. An approved and actually confirmed organizational freeze can provide operational exclusion; no such freeze was obtained in this investigation. No correction, publication, Stage A pass, Stage B approval, security acceptance, or runtime acceptance is claimed.

## 1. Bounded preflight and authority

| Item | Scope |
| --- | --- |
| Requested outcome | Establish actual table/operation eligibility, current-layer ETag applicability, and separate publication control without experimental writes. |
| Initial factual state | Clean worktree at `0486cdd`. The four fast-track reports recorded unproven concurrency/publication controls and an unresolved Console token mismatch. Their previous identity limitation was an assessment-time result, not proof that no retained pin existed. |
| Relevant files | [Project context](PROJECT_CONTEXT.md), [current state](CURRENT_STATE.md), [production rules](../MASTER_PRODUCTION_RULES.md), [workflow](../WORKFLOW.md), [project rules](../PROJECT_RULES.md), documentation instructions, the four reports linked below, guarded Console source, and retained same-session execution metadata. |
| Permitted change | Only this report. Source, tests, shared status documents, old reports, deployment artifacts and frozen pins are unchanged by Agent A. |
| Dependencies and risks | Independent approved caller provenance; explicitly targeted authenticated reads; separation of published/current representations; publication races; no credential/configuration disclosure. |
| Validation plan | Compare retained approval/identity evidence privately; perform minimum gated exact-target reads; compose applicable Microsoft contracts; validate this report's links, privacy patterns, final newline and whitespace. |

Read as historical context, not refreshed inventory:

- [Execution readiness](P0_SLICE_2A_FAST_TRACK_EXECUTION_READINESS.md).
- [Stage A1 correction plan](P0_SLICE_2A_STAGE_A1_CONSOLE_CORRECTION_PLAN.md).
- [Stage B update-method assessment](P0_SLICE_2A_STAGE_B_FLOW_UPDATE_METHOD.md).
- [Independent QA review](P0_SLICE_2A_FAST_TRACK_QA_REVIEW.md).

The current authorization permits bounded read-only investigation. It does not authorize credential creation, environment/profile selection, experimental writes, browser startup, publication, Flow/Outlook/Candidate calls, security/configuration changes, commit or push.

## 2. Independently retained identity gate

The pin was recovered **before** fresh tenant-resource reads, from this same resumed session's retained execution/authorization history. Its values were compared in memory, not printed or copied into this report.

| Evidence | Provenance and result |
| --- | --- |
| Owner instruction, `2026-11-05T13:32:33.732Z` | Explicitly authorized bounded DEV infrastructure in VN LMV IT and recorded `SLICE_2A_DEV_IDENTITY_OPTION_A_APPROVED`. |
| Successful historical PAC execution, `2026-11-05T13:51:56Z`, tool call `call_fVKtRz5bBiWg9cKf81NbiH3c` | Independently retained pre-existing execution baseline. Its result contains usable, unredacted origin, organization, environment and Dataverse caller identifiers, plus the account used for managed-context comparison. This was not a fresh response substituted as approval. |
| Owner continuation, `2026-11-05T14:14:30.110Z` | Accepted the partial infrastructure for continuation. |
| Owner runtime-wiring instruction, `2026-11-05T15:03:13.255Z` | Accepted the infrastructure milestone and explicitly directed DEV Option A to the already-existing Connected connections owned by the approved current DEV owner. This connects the retained execution baseline to the accepted owner path, rather than treating an arbitrary historical caller observation as authorization. |
| Guarded target source | Historical PAC origin, organization and environment each exactly matched the existing guarded target in [Console deployment source](../scripts/Deploy-BsoRsCandidateConsole.ps1). No target was selected by display name alone. |
| Fresh explicit-target PAC | `pac env who --environment <independently pinned origin>` matched the retained origin, organization, environment and caller. |
| Existing managed request context | Existing Az user context matched the retained account; `Get-AzAccessToken` reused that context. Independent `GET WhoAmI` matched the retained Dataverse caller and organization before the three resource/metadata GETs. |

**Result:** exact approved target and previously approved DEV-owner caller were established independently and then freshly matched. Historical approval provenance and current authorization are separate: the former identifies the permitted caller; the present request authorizes these reads. The earlier helper's practice of deriving `ExpectedUserId` from a current PAC response alone was **not** used as the independent pin.

Retained evidence locations were `events.jsonl`, `files\rw\` metadata summaries and guarded source within the same resumed session. They are protected/local evidence, not repository deliverables. No raw credential cache was opened. No deployment helper was executed or dot-sourced for authentication. No login, new credential, environment selection or privilege grant occurred.

## 3. Exact live evidence

**Metadata captured:** `2026-11-06T12:12:19.5346982Z`; subsequent definition reads occurred in the same bounded invocation. Explicit requests used the independently pinned origin, API v9.2, GET only, zero application retries, no redirects and a 90-second request timeout.

### 3.1 Actual table applicability

```text
GET EntityDefinitions(LogicalName='webresource')
    ?$select=LogicalName,SchemaName,EntitySetName,PrimaryIdAttribute,
             IsOptimisticConcurrencyEnabled,IsManaged,OwnershipType

LogicalName: webresource
SchemaName: WebResource
EntitySetName: webresourceset
PrimaryIdAttribute: webresourceid
IsOptimisticConcurrencyEnabled: true
IsManaged: true
OwnershipType: OrganizationOwned
```

`IsManaged = true` here describes the table metadata; it is not the selected HTML component's managed status.

### 3.2 Independently retrieved definition representations

Both requests used the exact name predicate `name eq 'os_/bso/candidate-console.html'`, selecting only `webresourceid,name,webresourcetype,content,componentstate,versionnumber,webresourceidunique,ismanaged,modifiedon`.

```text
GET webresourceset?$select=<columns above>&$filter=<exact name predicate>
GET webresourceset/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()
    ?$select=<columns above>&$filter=<exact name predicate>
```

The second is a documented composable **Web API function**, therefore an HTTP GET, not a mutating POST action. Older reports' generic description as an action is not the HTTP method used here.

| Sanitized evidence | Ordinary/published definition | Current/unpublished definition |
| --- | --- | --- |
| Returned records | Exactly 1; no next page | Exactly 1; no next page |
| Exact name | `os_/bso/candidate-console.html` | Same exact name |
| `webresourcetype` | `1` / HTML | `1` / HTML |
| `componentstate` | `0` | `0` |
| Component `ismanaged` | `false` | `false` |
| `modifiedon` | `2026-11-05T16:06:47Z` | `2026-11-05T16:06:47Z` |
| Decoded byte length | 18,928 | 18,928 |
| Decoded SHA-256 | `b0d3cede68669fc4bc080100a3318d433cd116b159cee32f8d96f20bd086086e` | `b0d3cede68669fc4bc080100a3318d433cd116b159cee32f8d96f20bd086086e` |
| `@odata.etag` | Present, opaque | Present, opaque; obtained from this function response itself |
| ETag comparison | Exact equality with current response | Exact equality with ordinary response |
| `versionnumber` | Present | Present |
| Stable object/version identity comparison | Same `webresourceid` and `webresourceidunique` across responses | Compared privately; identifiers omitted |

Base64 content was decoded and hashed **in memory only**. No live HTML or configuration bytes were saved. The opaque tags were compared exactly, not ordered, interpreted as timestamps, or synthesized from `versionnumber`. No ETag here is permission for a later write or a reusable execution token.

This independently refreshes **only the HTML definitions and WebResource metadata**. It does not refresh the six-resource inventory, configuration gate, Solution membership, Flow OFF state, guards, roles, Candidate rows, effective app-served bytes or any runtime behavior.

## 4. Microsoft contracts and capability decision

The following are primary Microsoft sources, consulted on 2026-11-06 without transmitting tenant content.

| Contract | Established applicability | Boundary |
| --- | --- | --- |
| [WebResource table reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/webresource) | Documents `PATCH /webresourceset(webresourceid)`, `content` as writable Base64 bytes, and both ordinary and unpublished retrieval messages. The live entity-set/key match this contract. | Does not itself specify the concurrency token's relationship to separate published/unpublished storage versions. |
| [Web resources](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/web-resources) | Explicitly says WebResources are database records managed using standard create/retrieve/update techniques. This is not a custom speculative update endpoint. | Does not add an atomic edit-plus-publish operation. |
| [Conditional Web API operations](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/perform-conditional-operations-using-web-api) | Documents table eligibility through `IsOptimisticConcurrencyEnabled`, opaque ETags and exact `If-Match` PATCH: a mismatching version returns `412`. Actual table eligibility is now established. | `If-Match: *` prevents creation, not stale overwrites. An ETag protects the record version it represents, not automatically another layer. |
| [Update/delete table rows](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/update-delete-table-rows) | PATCH updates the identified record; include only changed properties. A proposed correction body can contain only `content`. | This is not proof of byte-for-byte server preservation or absence of plug-in/platform side effects. |
| [RetrieveUnpublishedMultiple](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/retrieveunpublishedmultiple) | Composable collection-bound function, explicitly bound to `webresource`; retrieves unpublished organization-owned records. The exact supported function was read. | No separate draft-specific update URI or conditional publication parameter is supplied here. |
| [RetrieveUnpublishedRequest notes](https://learn.microsoft.com/en-us/dotnet/api/microsoft.crm.sdk.messages.retrieveunpublishedrequest?view=dataverse-sdk-latest) | Returns the current unpublished version; when published, it and ordinary Retrieve return the same data. They differ after update but before publication. | Explains why equal current/published responses here do not exercise a distinct pending draft. |
| [Publish customizations](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/publish-customizations) | Updates to UI-affecting items require publication; unpublished definitions must be retrieved when editing them. Specified publication is separate from update. | Does not promise a transaction spanning PATCH, independent reads and publication. |

### What is supported, and what is not yet proven

1. **Supported at table/ordinary-record level:** exact-version conditional WebResource PATCH follows the documented generic conditional-operation contract because actual table eligibility and the ordinary PATCH operation are established. A WebResource-specific stale-ETag example is not required merely to establish this general support.
2. **Observed current representation:** the unpublished function returned its own opaque ETag, with the same object and version identity as the ordinary representation. No distinct pending draft was observed.
3. **Required unresolved draft obligation:** the reviewed contracts and this no-draft snapshot do not establish that an intervening unpublished-only edit necessarily changes the version evaluated by the intended ordinary PATCH. Equal hashes, matching tags, `componentstate = 0`, and matching version identities cannot demonstrate that race behavior. No experimental stale-tag or draft-creation write was authorized.
4. **Update versus publication:** staging changed content and publishing it are separate operations. A content-only PATCH is not a PublishXml request and the documented lifecycle requires publication after update. Nevertheless, this investigation did not execute an update and cannot certify actual layer/byte preservation afterward.
5. **Normalization/preservation is a separate proof obligation:** even a supported conditional update can accept and normalize content or invoke platform behavior. A later authorized operation must independently read current and published definitions and compare exact decoded bytes and other relevant baselines. Do not label concurrency unsupported because preservation is untested, or claim preservation because concurrency is enabled.

Thus `UNSUPPORTED` would be false on the evidence; `SUPPORTED` without qualification would overstate the exact draft-race guarantee required by Stage A1. The top-level classification remains **UNPROVEN for that bounded requirement**, not for generic Dataverse ETags.

**Smallest technical gap:** an applicable Microsoft statement identifying which WebResource version an exact `If-Match` PATCH evaluates when an unpublished version exists, including an unpublished edit that races after the read. Obtain vendor clarification or already-existing authoritative evidence; do not create a draft, send a stale PATCH, or run a helper to manufacture proof under this authorization.

## 5. Separate publication-exclusivity outcome

[PublishXml](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/reference/publishxml) publishes specified solution components and exposes only `ParameterXml`. The [Publish request schema](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/publish-request-schema) expressly permits a `webresources` collection containing a WebResource GUID.

Future payload shape, **not an invocation**:

```xml
<importexportxml><webresources><webresource>HTML_WEBRESOURCE_OBJECT_ID</webresource></webresources></importexportxml>
```

Resolve the placeholder to the stable HTML `webresourceid`, not `webresourceidunique` or a Solution-component row ID. Require exactly one collection and one resource; omit app modules, sitemap, entities and all other resources. Do not substitute PublishAllXml or whole-Solution publication.

Neither the documented action parameter nor this schema provides an expected content hash, ETag, revision, lease, or lock parameter. No platform compare-and-publish or atomic PATCH-plus-PublishXml guarantee was established. This is a statement about the reviewed public contract, not a claim that Microsoft has no internal serialization.

**Operational result: `PUBLICATION_EXCLUSIVITY_NOT_ESTABLISHED`.** There is no recorded designated operator/freeze approval or confirmation from other possible editors/publishers for a future change window. The following is a proposed organizational control, not a platform transaction and not an already-established control:

- [ ] Owner approves the exact HTML-only correction, designated operator, independent reviewer, change window, recovery responsibility and procedural concurrency risk.
- [ ] Owner approves a resource-specific edit/publication freeze covering final preflight through independent post-publication readback; prevent publish-all/import/pipeline activity that can include this HTML.
- [ ] Every relevant maker/customizer, administrator, release operator and automated publisher/pipeline owner positively confirms quiescence. Identify the actual actors/processes; do not invent a pipeline or assume none exists.
- [ ] Record who confirmed, window boundaries and the exception/escalation route in approved restricted evidence. Publish only by the designated operator. No credential sharing or role removal is implied.
- [ ] Immediately before update, independently revalidate caller/target, exact current and published identities/bytes/ETags, expected one-token delta, relevant membership and disabled feature baseline. Preserve separately recoverable published/current copies only under separately approved restricted evidence handling.
- [ ] After a definitely acknowledged update, re-read both definitions: current must contain only the approved delta; published must remain the captured prior version. Any other difference stops before publication.
- [ ] Immediately before the separately authorized one-resource publication, reconfirm freeze and current bytes/version. These checks detect drift but do not alone eliminate the read-to-publish race.
- [ ] After a definitely acknowledged publication, independently verify both definitions and scoped unaffected baselines; reconcile the operator journal and available authorized platform/change audit. Do not assume organization auditing is enabled or that an audit record proves absent concurrent activity.
- [ ] A conflicting edit/publish, unconfirmed actor, freeze breach, failed precondition, unexpected normalization, timeout/lost response, audit discrepancy or incomplete readback means **STOP**. No blind retry, automatic publish, automatic rollback or privilege/configuration change.
- [ ] Release the freeze only after reviewer reconciliation or an explicit incident disposition.

A documented, owner-approved organizational freeze with actual confirmations can suffice as the operational publication control; a fictitious platform lock is not a prerequisite. It is not technically enforced atomicity and cannot be reported as one. Scope/readback checks also do not prove unrelated actors performed no unrelated operations.

## 6. Shortest safe next step and future prerequisites

**Next step under read-only scope:** obtain the narrow draft-version contract clarification above and obtain owner/operator/publisher confirmations for the proposed freeze. No further broad inventory or authentication discovery is needed to state the present capability decision.

**Shortest safe alternative if that contract remains unavailable:** separately propose a single-operator, owner-approved serialized authoring/publication procedure under an actually confirmed organizational freeze, with immediate layer checks and restricted recoverable snapshots. The owner must explicitly accept procedural exclusion in place of a demonstrated draft-version precondition. Do not silently downgrade the Stage A1 conditional-update requirement, claim that the maker UI supplies the missing guarantee, or execute this alternative now.

Before any later update or publication:

1. Obtain separate explicit scope for the content change, publication and evidence storage; a read-only capability proof is not execution approval.
2. Refresh the independently pinned caller/target comparison and all time-sensitive preflight items required by the [correction plan](P0_SLICE_2A_STAGE_A1_CONSOLE_CORRECTION_PLAN.md), including all six resources and membership. This report's HTML-only reads do not replace them.
3. Resolve the narrow concurrency gap or explicitly approve the procedural alternative; establish the actual freeze and reviewer/operation journal.
4. Regenerate the reviewed token-only HTML in memory from verified inputs. Keep configuration, feature enablement, source and all other resources unchanged.
5. Separately approve secure retention and recovery of immediately preceding published/current bytes; a hash is not a recoverable backup. No such snapshots were created here.
6. Dispatch only a newly authorized, narrowly reviewed operation with no automatic retries; verify bytes/layers independently. A later rollback needs its own approval and fresh state, not reuse of an old ETag.
7. Any app-served-byte check requires its own browser/automatic-request approval. This investigation neither launches a browser nor closes `BROWSER_NON_GET_EFFECT_UNDETERMINED`.

Slice 1 workflow, fail-closed scheduling, email idempotency, audit/privacy/ALM boundaries and the [production rules](../MASTER_PRODUCTION_RULES.md) remain unchanged. No mailbox, Flow activation, guard registration, runtime acceptance or Production gate is closed.

## 7. Actual no-write invocation ledger

These are actions by Agent A in **this investigation**, not imported historical operation counts.

| Invocation or action | Actual count/result | HTTP semantics and retry boundary |
| --- | --- | --- |
| Deferred Dataverse tool discovery | 1 successful discovery; returned managed schema/query/custom-API tools | Tool-schema discovery only; no returned tenant tool was invoked. Two later identity-tool searches were canceled and supplied no tool result. |
| Local evidence/approval/source inspection | Read-only view/search, in-memory JSON/PowerShell/Python parsing and Git status/revision checks | No tenant HTTP action. Retained summaries contain historical deployments, not current writes. |
| Session-store authorization searches | 2 local read-only queries; both returned no rows | No tenant HTTP action. Direct retained same-session user events and execution metadata supplied the pin instead. |
| `pac env who --help` | 1 local syntax probe; unknown argument, usage returned | Not a tenant identity result; no successful tenant operation claimed from it. |
| Fresh `pac env who --environment <pinned origin>` | 1 successful invocation | Read-only organization/caller check; internal service request/retry count not instrumented. No environment selection. |
| `Get-AzContext` | 2 local context inspections | Existing managed user context only; no login or context switch. |
| `Get-AzAccessToken -ResourceUrl <pinned origin> -AsSecureString` | 1 managed credential acquisition | Existing authentication only. Token never logged or saved; internal token-service traffic/refresh count not instrumented. No raw cache access or credential creation. |
| `GET WhoAmI` | 1 success | Explicit-target semantic identity read; zero application retries and redirects. |
| `GET EntityDefinitions(LogicalName='webresource')` with section-3 projection | 1 success | Exact table metadata read; zero application retries and redirects. |
| `GET webresourceset` with exact HTML predicate/projection | 1 success | Published-definition read; one row, no next page; zero application retries and redirects. |
| `GET webresourceset/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()` with same predicate/projection | 1 success | Current/unpublished-definition read; one row, no next page; zero application retries and redirects. |
| Microsoft public documentation fetches | 12 fetch invocations across the 9 primary pages cited above; repeated ranges were pagination, not failed tenant retries | Public documentation reads only; redirects/internal fetch requests not instrumented. No tenant bytes or identifiers sent to documentation sites. |
| Tenant mutation, PATCH/DELETE/PublishXml, helper execution, browser startup, Flow/Outlook/Candidate business call, role/guard/config change, environment/profile selection, credential creation, commit/push | **0 each** | No experimental or negative-test write. |

**Explicit Dataverse HTTP ledger:** four GETs, four successes, zero failed requests, zero application retries, zero redirects, zero POST/PATCH/DELETE. The one PAC invocation and managed credential acquisition have unmeasured internal traffic, so four is not asserted as the total number of all network requests. Historical deployment writes and older Stage A browser requests were not repeated.

No canonical DEV bytes were persisted. Only sanitized metadata, hashes and comparisons are retained in this report.

## 8. Validation and limitations

Performed: independent historical-pin/source comparison; exact-target fresh caller gate; successful metadata and both exact-name definition reads; singleton/no-pagination checks; private object/version/ETag comparison; Base64 decode/length/SHA-256 in memory; review of applicable Microsoft contracts; report-relative-link, privacy-pattern, newline, trailing-whitespace and diff checks.

No source or tests changed, so no implementation regression suite was needed or run by Agent A. No stale-tag experiment, divergent-draft test, PATCH, publication, normalization test, operational freeze, audit query, browser observation, served-byte verification or rollback was performed. No claim is made about present Flow/guard/role/configuration/business state beyond the bounded HTML/table reads above. Prior acceptance, hashes and failing release gates remain historical where not explicitly refreshed.
