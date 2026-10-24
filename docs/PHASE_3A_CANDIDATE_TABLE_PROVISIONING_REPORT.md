# Candidate-Only Metadata Provisioning Report

**Date:** 23 October 2026  
**Outcome:** `CANDIDATE_TABLE_KEYS_LOOKUPS_AND_SOLUTION_MEMBERSHIP_RECONCILED`  
**Authorization:** The owner's bounded Candidate-table-only authorization was consumed. No further metadata write is authorized by this report.

## 1. Scope and guards

The authorized scope was the existing Candidate Status global Choice and Candidate table metadata, including two alternate keys and lookups to the existing Position, Candidate Source, and TA Directory tables. The guarded process verified the active target and identity, Dataverse `WhoAmI`, the approved unmanaged Solution and Publisher, and live metadata before dispatch. No login or environment switch was performed.

No Call Log or Candidate Status History table, Call Outcome Choice, Custom API, plug-in, role, app navigation, business data, or unrelated metadata was in scope.

## 2. Provisioned metadata

| Component | Verified state |
|---|---|
| Global Choice `os_sr_candstat` | Present in the approved Solution; exact six labels and allocated values reconciled. |
| Candidate table `os_sr_cand` | `UserOwned`, in the approved Solution, table audit metadata enabled. |
| Candidate Number `os_sr_cand_cnum` | AutoNumber format `CAND-{SEQNUM:8}`, String MaxLength 100, primary name; unique alternate key Active. Runtime generation was not tested because no row was created. |
| Candidate Status `os_sr_cand_stat` | Picklist with default `100010000`; expanded global Choice name and metadata ID exactly match `os_sr_candstat`. |
| Correlation ID key | `os_sr_cand_ak_corid` is Active on `os_sr_cand_corid`. |
| Position lookup | `os_sr_pos_cand` targets `os_sr_pos` through `os_sr_cand_pos`. |
| Candidate Source lookup | `os_sr_csrc_cand` targets `os_sr_csrc` through `os_sr_cand_csrc`. |
| TA lookup | `os_sr_ta_cand` targets `os_sr_ta` through `os_sr_cand_ta`. |
| Lookup cascade behavior | Delete is Restrict; Assign, Reparent, and Share use NoCascade. |
| Solution inclusion | Candidate table is a root component with `rootcomponentbehavior=0` (Include Subcomponents), covering its keys and lookup relationships. |

Candidate Status values are:

| Value | Label |
|---:|---|
| 100010000 | Need Call Candidate |
| 100010001 | Candidate Answered |
| 100010002 | Waiting Manual Scheduling |
| 100010003 | Round 1 Scheduled |
| 100010004 | Offer Extended |
| 100010005 | Candidate Failed |

## 3. Audit and data boundary

The Candidate table's audit metadata is enabled. Organization-level auditing is disabled. Under the owner's explicit condition, no real Candidate data may be created until organization-level audit governance is resolved. No Candidate row or other business record was created.

The Candidate Number format and field metadata are verified, but the platform-generated number has not been runtime-tested. A synthetic-row test requires a later, separately authorized operation after the audit prerequisite is satisfied.

## 4. Request and write accounting

The bounded run completed seven metadata writes:

| Write | Count |
|---|---:|
| Candidate Status Choice | 1 |
| Candidate table | 1 |
| Alternate keys | 2 |
| Lookup relationships | 3 |
| **Total** | **7** |

Automatic retries: **0**. Candidate/business-data writes: **0**. Publication, app, access, and organization-setting changes: **0**. The final read-only reconciliation used **31 GET and 0 POST**.

The continuation's first final validator stopped after the five authorized key/relationship POSTs because it incorrectly expected separate SolutionComponent rows for subcomponents. A subsequent GET-only check found the Candidate root's Include Subcomponents behavior and validated the exact children. An initial attribute-count check also misclassified Dataverse-generated lookup `...name` companion columns; the verifier now distinguishes those generated attributes from the approved Candidate fields. Neither verifier correction sent a tenant write, and no POST was retried.

## 5. ALM export disposition

A supported unmanaged PAC export/unpack was performed after provisioning. PAC exported the complete Solution, including the already-existing `srapp` and reference tables, not only Candidate metadata. The unpacked Candidate entity also contained Card, Main, and Quick form files plus SavedQueries; their individual definitions were not retained for detailed review, and no independent form/view edits were made in this task. To avoid retaining out-of-scope source changes in this Candidate-only task, the generated full export was removed from the workspace. No solution source folder or export is currently retained; a full-Solution source pull requires a separately bounded repository-scope decision. No commit or push occurred.

## 6. Final state and next gates

Candidate-only metadata is complete and reconciled. Call Log, Candidate Status History, the Call Outcome Choice, Custom API, and plug-in remain unprovisioned. The published `srapp`, user/role access, and navigation remain unchanged.

Before Candidate data creation, IT/Compliance must resolve organization audit activation, retention, access, and capacity governance. Before Custom API/plugin implementation, the least-privilege Execute privilege and effective-access model must be approved and tested. Any remaining schema work requires separate bounded authorization and a fresh guarded preflight. No commit or push was performed.
