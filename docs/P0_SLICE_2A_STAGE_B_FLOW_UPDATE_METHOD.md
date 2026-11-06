# P0 Slice 2A — Stage B Flow-update method assessment

**Assessment date:** 2026-11-06.

**Classification: `STAGE_B_CONDITIONAL_UPDATE_METHOD_BLOCKED`.**

**Later evidence:** The [Workflow capability proof](P0_SLICE_2A_WORKFLOW_CONCURRENCY_PROOF.md) established the exact-ETag concurrency sub-capability and independently resolved the caller pin for its bounded reads. The complete OFF/privacy-preserving update remains unproven and unauthorized; this document preserves the earlier assessment.

No Flow update, publication, activation, or other tenant write is authorized or performed by this assessment. The method is blocked because the reviewed authoritative material does not demonstrate a version-specific conditional update of this particular solution-aware Flow's `workflow.clientdata`, including preservation of its state and solution membership. The public example's `If-Match: *` is not a same-version guard. This is a lack of demonstrated proof, not a claim that Microsoft does not support such an operation.

The target Flow must remain OFF. Its last observed OFF state is **historical**, not a fresh verification. The separate Stage A Console cache-token discrepancy remains open under `P0_SLICE_2A_STAGE_A_LIVE_PREFLIGHT_DRIFT_DETECTED`; neither that discrepancy nor this method assessment authorizes a correction or exception.

No change to the canonical workflow, email idempotency, audit, access controls, or ALM rules is proposed.

## Evidence and scope

| Evidence | Status and significance |
|---|---|
| Explicit-target PAC organization check and independent Dataverse `WhoAmI` GET | Fresh in this assessment, using existing authentication. The exact previously recorded environment and organization matched, and PAC and `WhoAmI` agreed on the current caller. No independently retained pin proving that this caller is the previously approved identity was reproduced. Live access stopped before project-resource reads. |
| [Stage A live preflight](P0_SLICE_2A_STAGE_A_LIVE_PREFLIGHT_REPORT.md) | Historical: `os_sr_avchk` was OFF (`statecode=0`, `statuscode=1`) and its canonical definition matched the pre-hardening source. Its reported Solution membership and Console drift are not freshly verified here. |
| Retained session deployment summary | Historical, independently reported that the Flow clientdata matched its source, that the Flow was OFF, and that visible run count was zero at that check. This is not a claim about its current state or lifetime runs. |
| [Local hardened definition](../solutions/AvailabilityQuery/os_sr_avchk.clientdata.json) and [privacy contract](../solutions/AvailabilityQuery/availability-flow.contract.json) | Current repository source only, not a deployed Flow or proof that the service accepts or enforces the settings. |
| Public Microsoft documentation and exposed MCP/PAC tool schemas | Reviewed without sending project metadata externally or invoking their project-resource tools. |

**Live operation inventory:** one explicit-target PAC organization-check invocation and one independent, script-dispatched `WhoAmI` GET; PAC's internal service-request count was not measured. No project Flow, Solution membership, Candidate, Outlook, or runtime Flow read was made in this assessment. There were no writes, update attempts, retries, Flow executions, publications, activations, logins, environment selections, or provisioning operations. Environment identifiers, caller identities, credentials, tokens, and connection details are intentionally omitted.

## Reproduced offline structural comparison

The retained pre-hardening source and current local definition were independently parsed with duplicate-key rejection; a duplicate-key canary was rejected. Object keys were recursively sorted and serialized compactly as UTF-8 for canonical hashing, preserving array order. The earlier Stage A report records the same historical live canonical hash as the retained source:

| Artifact | Exact-byte SHA-256 | Canonical JSON SHA-256 |
|---|---|---|
| Stage A live decoded `clientdata` — historical report only | `BA19AC8D1D306B0934F3A4B35839BA4041437441064C28D051950C3B898F7A37` | `1B60A8E30C19728F16DBC7EE5F16F7EDD4015010B2F09890D6716580E378F864` |
| Retained pre-hardening source | `F901BAAE0ABC5F2A2ECCF74BF59E76FE05189A6E13BF86A981D6D6E4DBEB8811` | `1B60A8E30C19728F16DBC7EE5F16F7EDD4015010B2F09890D6716580E378F864` |
| Current hardened source | `0E1A1DE9CFECE98440B1EC8B52DCD76648A25826A06BCF36FAFCEFBB39C701B0` | `059106A6B6168313FE19067D81566BBB5BC11B85D3A145B4BCB07FBD251ECB66` |

The historical source and sanitized deployment summary were read from `rw\os_sr_avchk.clientdata.json` and `rw\rw-final.json` relative to the retained session evidence directory, not from repository files. The historical live exact hash above was reported by Stage A and was not freshly reproduced.

The strict recursive comparison found exactly **26 changed `runtimeConfiguration.secureData` locations**: one trigger and 25 actions. Removing only these privacy settings yields equal canonical definitions. There are no other JSON differences in the compared sources; this includes the trigger filter, concurrency, actions, expressions, connection references, retries, and terminal writes. This offline result does **not** prove preservation of the live record's identity, OFF state, membership, bindings, or service-side behavior.

Each entry below is a separate changed location. `I+O` means `properties: ["inputs","outputs"]`; array order is as in the local definition.

| Type and transition | Exact trigger or action names |
|---|---|
| Trigger, absent → outputs | `When_a_Pending_availability_query_is_added` |
| Compose, inputs → I+O | `Compose_free`, `Compose_slot`, `Compose_validation_error`, `Compose_drift`, `Compose_location_drift` |
| Compose, absent → I+O | `Compose_terminal`, `Compose_canonical_slots`, `Compose_proposed_result` |
| If, absent → I+O | `Check_response_shape`, `Check_slot_eligible`, `Check_suggestion_valid`, `Check_suggestion_timezone`, `If_validated_snapshot` |
| AppendToArrayVariable, absent → I+O | `Append_observation`, `Append_slot` |
| Foreach, absent → I+O | `For_each_suggestion` |
| SetVariable, absent → I+O | `Set_result_slots`, `Set_location_snapshot`, `Set_ta_snapshot`, `Set_location_changed` |
| Scope, absent → I+O | `Evaluate`, `Reread_references`, `Map_failure` |
| OpenApiConnection, absent → I+O | `Read_query`, `Write_terminal_result` |

The following eight actions already had I+O and must remain protected: `Read_ta`, `Read_location`, `Find_meeting_times`, `Reread_ta`, `Reread_location`, `Find_invalid_attendees`, `Find_ta_entries`, and `Find_room_entries`. All 33 protected actions must be read back: the contract's 32 sensitive actions plus `Set_location_changed`. In particular, platform acceptance and preservation of each listed trigger/action type and its exact `secureData` combination are **unproven**; local JSON validity is not sufficient. Compose input-to-I+O changes, control containers (`If`, `Foreach`, `Scope`), variable and array actions, queries, and connector actions require explicit checks rather than an assumption that all action types behave alike.

## Supported-surface and concurrency assessment

| Surface or evidence | What is established | What remains missing |
|---|---|---|
| [Microsoft: manage cloud flows with code](https://learn.microsoft.com/en-us/power-automate/manage-flows-with-code) and [Workflow table reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/workflow) | The guidance covers flows on the Solutions tab, represents them as `workflow` records, describes `clientdata` as a JSON-encoded string, and shows a `PATCH` of selected Flow properties. The table reference lists `ClientData` among writable attributes. | The published update example changes description, owner, and state and uses `If-Match: *`; it does not demonstrate a version-conditional `clientdata` update or preservation of this Flow's settings. Do not copy its owner/state changes. |
| [Microsoft: conditional Web API operations](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/perform-conditional-operations-using-web-api) and [optimistic concurrency](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/optimistic-concurrency) | Generic Dataverse guidance describes version-specific ETags, precondition failure, SDK `RowVersion`, and the importance of optimistic-concurrency support for the table. | Generic table examples, the historical numeric version, or receiving an ETag do not establish that the exact solution-aware Workflow/clientdata update enforces the intended version condition. Endpoint-specific applicability and behavior are not demonstrated here. |
| Exposed Dataverse MCP | `read_query` can read records but has no explicit environment argument; `update_record` has no documented ETag or conditional-header argument. Neither was invoked for project data. | These schemas do not establish an explicitly targeted, conditional single-Flow update. |
| Exposed PAC MCP | Preview Flow-list and action-list schemas accept an explicit environment and workflow filter; `env_fetch` also accepts an explicit environment. These are read surfaces, not proof of update concurrency or privacy enforcement. | No exposed, demonstrated single-Flow version-conditional update. No project-resource listing or fetch was invoked. |
| [Power Automate Management connector: Update flow](https://learn.microsoft.com/en-us/connectors/flowmanagement/#update-flow) | A management update operation is documented. | Its published operation schema exposes no documented `If-Match` input and includes additional Flow properties. It is not demonstrated to preserve the required state and metadata under a version precondition. It was not invoked. |
| Solution import | General solution ALM is a distinct mechanism. | It is not evidence of an isolated, concurrency-protected, single-Flow definition update and is outside this assessment's authorization. |

Do not conflate four different things: SDK `Entity.RowVersion` is an SDK concurrency property; Dataverse `versionnumber` is a table column; `@odata.etag` is an opaque HTTP entity tag; and `If-Match` is an actual request precondition whose **endpoint enforcement** must be established. A historical `RowVersion` or `versionnumber` is not a reusable HTTP ETag. Even a fresh ETag read is not proof that the intended Flow update honors it. In the generic Dataverse guidance, `If-Match: *` prevents an upsert from creating a missing row; it does not compare the previously read version.

### Best candidate only — explicitly non-executable and unverified

The following describes a possible research direction, **not an approved or runnable request**. Placeholders are not values, and no request should be constructed or sent from it:

```text
Candidate surface: PATCH <approved-organization>/api/data/v9.2/workflows(<existing-flow-id>)
Candidate content type: application/json
Candidate body shape: {"clientdata":"<escaped-JSON-string-of-reviewed-definition>"}
Candidate precondition: If-Match = <exact opaque ETag from the same fresh Flow read>
Unverified: whether this solution-aware PATCH enforces that ETag or needs solution context
```

The missing proof is an authoritative, applicable statement of the supported method and headers for this Flow's `clientdata`, including any required solution or layer context; that the relevant Workflow table/operation supports optimistic concurrency; and that an exact stale ETag causes a precondition failure without applying the change. The solution-aware operation must also preserve the existing Flow identity, OFF state, references, and Solution membership. A capability flag or generic OData example alone is not sufficient proof of all of these conditions. Obtain Microsoft-authoritative endpoint-specific evidence and a separately authorized preservation assessment before proposing a concrete request; do not treat an unproven candidate as a fallback.

## Prerequisites and exact Gate 2 readback

The [Stage A drift disposition](P0_SLICE_2A_STAGE_A_DRIFT_DISPOSITION.md) and [pre-activation readiness plan](P0_SLICE_2A_PRE_ACTIVATION_READINESS.md) remain controlling. Before any future update is even proposed:

1. Resolve the Stage A Console discrepancy by its separately approved correction or explicit exception. Re-establish the approved environment, organization, and previously approved caller independently; stop before project reads if any pin or authentication is unavailable. Reuse an existing authenticated context, with explicit target selection in each permitted read; no login or profile/environment selection is implied.
2. Obtain the missing endpoint-specific concurrency proof, action-type preservation evidence, and separate explicit approval for the precise scope. Read only the approved Flow and its Solution membership under that approval. Verify exact Flow and installation identity in memory, category/type, owner, connection references, membership, and OFF state. If actual connection bindings cannot be verified from these reads, stop and obtain separate authorization for the necessary binding metadata; do not assume the bindings. Do not expose identifiers or connection details.
3. Parse fresh `clientdata` with duplicate-key rejection and compare it to the historical baseline. The proposed privacy-only change is invalid if any unrelated fresh drift exists; stop and reassess instead of overwriting it. Obtain a fresh opaque conditional token only if the supported endpoint and precondition have been established. A read or token does not itself grant write approval.
4. Require a reviewed, one-shot, separately authorized update plan with no extra changed properties, state changes, or automatic retries. If the required conditional update or preservation cannot be proved, remain blocked; never replace the precondition with `*`.

**Gate 2, after any separately approved future update:** independently read the exact same Flow and its membership in the approved Solution, using a verified target and caller. Check:

- The same Flow/installation identity, owner, category/type, Solution membership, connection-reference identities and bindings, and OFF state (`statecode=0`, `statuscode=1`) as the verified pre-update snapshot. Compare sensitive identifiers privately; do not log or publish them.
- Duplicate-key rejection and complete canonical comparison against the hardened definition, including the trigger, filter, concurrency, action structure, expressions, retries, terminal writes, and references. Unexpected server normalization or any other difference is a STOP for review, not an assumed equivalence.
- The trigger's outputs protection, every one of the 25 changed actions (including the extra `Set_location_changed`), and all eight previously protected actions. Check the exact accepted `secureData.properties` values for all 33 protected actions; settings that are rejected, silently dropped, or rewritten do not pass.
- No unexpected state, membership, reference, or definition change. Report only sanitized pass/fail and hashes; do not persist raw clientdata containing sensitive connection information.

Any timeout, lost response, `412`, unexpected readback, or ambiguous outcome means **STOP; no automatic retry**. Do not infer success or failure from an incomplete response. A separately authorized read-only investigation may establish the actual state. Rollback is a separate decision and approval: it requires an approved baseline, a newly verified target and caller, a demonstrated conditional method and fresh concurrency condition, and its own readback. Never blindly restore a stale definition or change state as an improvised rollback.

## Separate functional and privacy gates

Gate 2 establishes configuration preservation only. It does not prove execution correctness or secrecy in run history. The Flow remains OFF under the present authorization.

- **Functional gate:** under a separately authorized synthetic runtime plan, test numeric parameter binding; WDL sorting and serialization; strict timezone handling; synthetic mailbox behavior; guard configuration and order; and separation of application authorization from connector identity. Preserve fail-closed scheduling and terminal-write behavior. Failures require STOP and review.
- **Runtime privacy gate:** separately inspect appropriately authorized synthetic run history for trigger outputs and the input/output behavior of each relevant connector, Compose, variable/array, Query, If, Foreach, and Scope action. Confirm that settings were not merely retained as JSON but actually prevent sensitive values from appearing. Record sanitized results only; any exposure or unsupported setting blocks activation and requires an architecture correction.

Any runtime execution or temporary activation requires its own explicit bounded approval and OFF-state restoration plan; this document authorizes neither. No Outlook, Candidate, or production business-data operation is part of the current assessment.
