# Security Model

## Phase 4A BSO role baseline (27 October 2026)

The DEV environment contains the unassigned `BSO-RS Support - BSO` security role in the root Business Unit. Its solution membership in the unmanaged `os_sr_bso_rs_support` solution was verified by a read-only `solutioncomponent` check (component type Role). The 17 requested business privileges were saved and verified after reloading the role editor:

| Table | Privileges | Depth |
|---|---|---|
| Candidate | Create, Read, Write, Append, Append To | User (Basic) |
| Call Log | Create, Read, Append, Append To | User (Basic) |
| Candidate Status History | Create, Read, Append, Append To | User (Basic) |
| TA Directory | Read | Organization |
| Position | Read | Organization |
| Candidate Source | Read | Organization |
| Location | Read | Organization |

No Operation Receipt privilege was added. Candidate, Call Log, and Candidate Status History Delete privileges were not enabled; no Customize, Publish, solution-administration, or environment-administration privilege was enabled in the role editor. The role editor shows five platform metadata Read defaults (Plug-in Assembly, Plug-in Type, Sdk Message, Sdk Message Processing Step, and Sdk Message Processing Step Image). A prior role readback also identified four SharePoint-related platform defaults that were not exposed as direct controls in the role editor. Those defaults were not changed and must be reviewed before any role assignment. **The role has not been assigned to any user.** Its privileges have not been independently tested as an effective access profile, and the role has not been exported into an unpacked repository solution snapshot. Any assignment requires separate explicit approval and verification against the target user's Business Unit.

This role baseline does not make the DEV direct-write UI or disabled-guard state a production architecture. The Candidate Core production backend remains pending; real candidate data remains prohibited until the required backend, guard restoration, audit, and security acceptance gates are met. See [Current State](CURRENT_STATE.md) and the [Candidate UI implementation note](CANDIDATE_UI_IMPLEMENTATION_NOTE.md).

## Phase 4B role validation (27 October 2026)

The BSO role was re-read after the synthetic reference and scheduling-entry acceptance. The 17 business privileges remain unchanged: Candidate Create/Read/Write/Append/Append To at User depth; Call Log and Candidate Status History Create/Read/Append/Append To at User depth; and Read on TA Directory, Position, Candidate Source, and Location at Organization depth. No Operation Receipt, Delete, Customize, Publish, solution-administration, or environment-administration privilege was added. The role remains unassigned; no user or team role assignments were changed.

The role editor showed five Organization-depth Read defaults for Plug-in Assembly, Plug-in Type, Sdk Message, Sdk Message Processing Step, and Sdk Message Processing Step Image. A prior readback identified four additional SharePoint-related platform defaults that are not exposed as direct controls in the role editor. All nine are classified **REVIEW BEFORE PRODUCTION**: they are not required by the current DEV Candidate Management UI, but were not removed because their full privilege details and a safe supported removal path were not established in this validation. Reconcile their exact rights and platform dependencies before any production assignment. No role privileges were changed.

The app's scheduling draft uses existing TA Directory and Location rows only. Since no scheduling storage exists, no scheduling-table privilege is included in this role validation. Revalidate least privilege if an approved scheduling table is provisioned. The role remains unassigned pending a separately approved test-user target.

## Phase 4C scheduling privilege update (27 October 2026)

After the DEV-only `os_sr_intv` Interview Schedule table was provisioned in `os_sr_bso_rs_support`, the existing `BSO-RS Support - BSO` role was updated and reloaded in the role editor. The table is UserOwned. The role has Create, Read, Append, and Append To at User (Basic) depth; Write, Delete, Assign, and Share remain None because the current UI does not edit or delete schedule rows. Existing Candidate, Call Log, Status History, Position, Candidate Source, Location, and TA Directory grants were not changed. Operation Receipt remains outside the user-facing role.

The role remains unassigned; no user or team role membership was changed. The five visible Organization-depth plug-in/SDK metadata Read defaults and four previously identified SharePoint-related defaults remain unchanged and classified **REVIEW BEFORE PRODUCTION**. Effective access has not been tested with a BSO user. Keep real data prohibited, restore the 50 disabled `ProtectCandidateCore` registrations before security/production acceptance, and treat the DEV direct-write schedule sequence as nontransactional technical debt. Candidate Core production backend remains pending.

## Phase 4D Interview Schedule result privilege gap (28 October 2026)

The DEV result implementation updates an existing Interview Schedule row before changing Candidate status. The current unassigned role has Interview Schedule Create, Read, Append, and Append To at User (Basic) depth, but Write remains None; therefore, the current role does not have the table privilege required to record Pass/Fail. No privilege was broadened and no user/team membership was changed. A minimum User (Basic) Write grant is a prerequisite for BSO-role acceptance and requires explicit authorization; do not treat an app action or system-authorized browser test as proof of BSO effective access. `Delete`, `Assign`, and `Share` remain None. The result workflow still requires fresh synthetic browser acceptance and persistence-after-reload verification. The role remains unassigned.

## Current Candidate Core trust contract (26 October 2026)

### R4O server-registration-backed protected-write classification

**Current live disposition:** the earlier `OTHER_PROTECTED_WRITE` CreateCandidate result proved runtime-shape classification inadequate. Static source already allowed Candidate Create and Receipt Create for CreateCandidate; the allowlist was not broadened. The current source uses the guard execution context's server-owned `OwningExtension` to resolve the current `sdkmessageprocessingstep`, active state, exact `ProtectCandidateCore` PlugInType, package-backed assembly/package, SDK message, and matching SDK message filter. Only six exact table/message pairs map to canonical WriteCodes; Associate/Disassociate retain the relationship-specific path. Exact unsupported registrations fail closed. Populated runtime MessageName and PrimaryEntityName values are consistency checks, not classifier inputs. All 50 live registrations resolved before and after the package update. One CreateCandidate failed with `UNSUPPORTED_GUARD_REGISTRATION`; that category does not identify the internal metadata check. The runtime matrix did not run, and the model is not runtime accepted. No further repair or backend diagnostic was performed. See the full [Phase 3D report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).

The [source-derived eight-action matrix](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md) is authoritative for the current write scope: CreateCandidate allows Candidate Create and Receipt Create; UpdateCandidate allows Candidate Update and Receipt Create; RecordCall allows outcome-dependent Candidate Update/Call Create/History Create plus Receipt Create; ProceedToScheduling allows Candidate Update/History Create/Receipt Create. All other pairs deny. MarkRound1Scheduled/RecordPass/RecordFail/RequestReschedule fail before writes with current missing evidence, so none may create receipts. Receipt Update/Upsert and arbitrary protected mutations remain blocked.

The verified API ancestor/action contract below remains a separate authorization requirement; deriving the child WriteCode from registration does not by itself authorize a write. Action/write labels are not authorization inputs, no wildcard permission is introduced, and no identity predicate, privilege, or server-owned trust requirement is relaxed. Exact child write order, receipt replay/failure semantics, all live registration rows, and offline matrix coverage are recorded in the runtime report.

**Earlier runtime disposition:** the single authorized existing-package update returned HTTP 204, but the single acceptance CreateCandidate failed with `UNSUPPORTED_CORE_WRITE_CONTEXT` (HTTP 400 / `0x80040265`). Counts remained 0/0/0/0. No matrix or further repair ran. The contract below is implemented/deployed, not proven runtime accepted. Organization tracing remained Off and no Profiler was used. See the [runtime report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).

Owner approval supersedes the required SharedVariables marker after the live `MARKER_MISSING` localization. The corrected guard requires a bounded (maximum eight ancestors), synchronous, transactional `os_sr_cact` ancestor at stage 30, with positive/lower depth, matching UserId and InitiatingUserId, and a supported ActionType compatible with the protected message/table. The ancestor's server-owned `OwningExtension` must reference `sdkmessageprocessingstep`. Calling-user read-only resolution follows its `eventhandler` to the exact `os_sr_cact.ApplyCandidateAction` PlugInType, `os_sr_cact` assembly v1.0.0.0 and existing `os_sr_cact_pkg` package v1.0.0. No registration ID is hard-coded. Missing, wrong or unreadable registration metadata fails closed with a sanitized category; no privilege grant or elevation is implicit.

Positive validation is cached for at most one minute by organization, calling user and server-owned extension ID; the cache is process-local, locked and capped at 128 entries. Negative results are not cached. Expiry/process restart requires validation again. Deployment/rollback procedures must account for this bounded cache lifetime. Correctness must not depend on cache persistence.

The old private marker may remain as non-authoritative, nonpersisted evidence. Its presence, CLR type and fingerprint no longer authorize or reject a child write. Neither a caller `tag`, caller-provided parameter nor entity attribute can provide the server-owned execution registration. Direct writes and unrelated parents remain blocked. Removal of mutation-fingerprint authorization is intentional: the approved implementation and operation-specific ancestor are now the trust boundary, not an exact child payload fingerprint. The API engine still owns validation, transitions, idempotency and caller-context writes.

Receipts remain append-only: accepted operations create receipts; replay reads existing receipts without updating them. The authorization's reference to receipt create/update does not introduce a receipt-update path or override append-only protection.

**Legacy handler rollback also requires matching guard rollback.** The current guard does not trust the retained legacy signed assembly merely because its type/name matches. Do not modify that assembly or broaden package trust for convenience. Non-admin registration-read permissions and runtime acceptance remain separate evidence requirements; no new access is granted.

[Microsoft's ParentContext guidance](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/understand-the-data-context#parentcontext) warns that undocumented context relationships can change. Retest the verified ancestor shape after platform/package changes and fail closed on drift. See the latest [runtime report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md) for deployment/acceptance evidence. Older runtime/Profiler recommendations in the historical baseline below are superseded; do not invoke Profiler or enable trace logging for this run.

## Historical security baseline

**Status:** Security design proposal and constraints. The published `srapp` reference app retains its accepted System Administrator and System Customizer associations; no project-specific BSO/Admin end-user role is established by that association. Phase 2D.4F made no access changes. Phase 3A owner decisions approve Dataverse Owner as responsible BSO, table auditing for Candidate/Call Log/Status History, and no column-level security for Candidate Name/Email/Phone in the initial slice. Candidate table audit metadata is enabled, while organization-level auditing remains disabled and unchanged as an external IT/Compliance governance/release prerequisite before real candidate rollout. Owner direction permits bounded synthetic Candidate Core runtime acceptance while audit activation is pending; it does not permit real candidate data. R4M package disposition is `PACKAGE_UPDATE_ACCEPTED_CONTENT_NOT_BYTE_RECONCILABLE`: the single existing-package update returned HTTP 204 and package identity/version/topology remained exact, while standard GET did not expose deployed bytes. The one synthetic CreateCandidate call returned the exact R4L `CALLER_MARKER` diagnostic, so runtime classification is `PACKAGE_GUARD_PARENT_CONTEXT_FAILURE`; no matrix action followed, and post-failure counts were zero. The next diagnostic is Plug-in Profiler/context capture; no retry or package update is authorized. The Custom API is deployed with the existing Candidate write privilege `prvWriteos_sr_cand`; this does not establish an approved least-privilege role or effective non-admin rights. Non-admin acceptance remains deferred to Candidate UI + Security. No role, access, or organization setting was changed. See the [Phase 3D report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md), [Candidate-only provisioning report](PHASE_3A_CANDIDATE_TABLE_PROVISIONING_REPORT.md), [Phase 3A Candidate Core Design](PHASE_3A_CANDIDATE_CORE_DESIGN.md), [Phase 3A.2 readiness report](PHASE_3A2_CANDIDATE_CORE_DECISION_APPLICATION.md), and [Dataverse Schema Specification](DATAVERSE_SCHEMA_SPECIFICATION.md).

## Identity and authentication

Microsoft Entra ID is the target authentication authority. Authentication does not itself grant Dataverse access. Dataverse security roles govern operations and data access. Microsoft 365 connector identity is a separate boundary and must be verified independently for each email/calendar action.

## Roles and access

- **BSO:** primary interactive role; access should follow least privilege and assigned business responsibility.
- **Administrator:** future capability only; define administrative tasks and limit privileged access. Existence/approval of an Admin role is not established.
- **TA:** directory/interviewer contact, not automatically an interactive app role. Additional TA access requires an explicit product decision.
- Candidate/visitor access is not assumed.

Define table privileges, row ownership/sharing, team model, and Custom API execution privileges with security-owner review. The Phase 3A owner-approved initial slice uses Dataverse `ownerid` as the responsible BSO and has no duplicate Assigned BSO lookup. Name/Email/Phone column-level security is explicitly not applied in this initial slice; least-privilege table/row access and auditing remain required. Restrict salary, CV links/documents, email snapshots, and integration diagnostics as appropriate. Validate access with positive and negative tests.

### Proposed schema access boundaries

| Data area | Proposed Dataverse boundary | Sensitive columns/data |
|---|---|---|
| Candidate and child activity records | UserOwned; Candidate Dataverse Owner is responsible BSO; child owner aligned by server-side operation; no implicit access from a lookup | Candidate name/email/phone are not column-secured in initial slice; CV URL, call notes, interview feedback, and visit details remain sensitive |
| Interview results | UserOwned under Candidate owner; only approved BSO/roles | Feedback and salary; field-level security proposed, subject to role design |
| Email dispatch | UserOwned under Candidate owner; narrow table and column privileges; immutable content snapshot after queue | Sender, To/CC snapshots, subject/body, provider IDs; field-level security and explicit retention |
| TA, Position, Candidate Source, Location, Email Template | OrgOwned reference data; BSO read only as needed; restricted admin/integration write | TA email and room resource addresses remain directory/contact information |
| App Configuration | OrgOwned, restricted admin read/write | Nonsecret approved values only; no credentials, tokens, connector URLs, or secrets |
| LEGO Career | OrgOwned, BSO read and integration write | External posting fields; Vietnam filter; no candidate payload |
| Integration Run | OrgOwned, operational-admin/integration-only | Sanitized diagnostics only; no raw payload or candidate PII column |

The Candidate primary name is proposed as Candidate Number rather than personal name because Dataverse exposes a related row's primary name through lookups. Candidate Number is still an internal identifier and must be access-controlled. Alternate-key columns cannot have field-level security; protect their disclosure using row/table privileges. No policy or role assignment is configured by this proposal.

Owner-approved Phase 3A requirement: enable Dataverse table auditing for Candidate, Call Log, and Candidate Status History. Candidate table audit metadata is enabled, but the organization-level toggle is disabled and unchanged. The read-only assessment on 19 October 2026 found configured retention of 30 days (not an approved policy) and user-access auditing off; capacity, historic audit-log presence, audit access, and effects on other applications remain unknown. This pending organization audit state does not block the explicitly authorized bounded synthetic Candidate Core acceptance; it remains an external governance/release prerequisite before real candidate rollout or reliance on audit history. No real candidate data is permitted under the synthetic acceptance authorization, and no organization setting was changed. IT/Compliance must resolve activation, retention, audit readers, legal hold/DSR, capacity ownership, and change control. The proposed scope and impact are documented in [Dataverse Audit Policy Proposal](DATAVERSE_AUDIT_POLICY.md) and [Audit Impact Assessment](AUDIT_IMPACT_ASSESSMENT.md).

Dataverse auditing is distinct from `os_sr_csh`, the proposed application-owned append-only status history. `os_sr_csh` must capture accepted business transitions through an approved atomic server operation; Dataverse auditing supplements it. The table-audit enablement requirement is approved for the three Candidate-core tables; any additional column-level audit selection for email snapshots, salary, CV links, or later domains must follow IT/Compliance data-minimization and retention review.

## Connector identity

A BSO's app session does not guarantee a connector executes as that BSO. Verify the approved user-scoped connection/run-only pattern, sender/organizer semantics, delegated permissions, and failure behavior in a nonproduction tenant before rollout. Fixed Flow-owner connections must never silently impersonate the current BSO. Deny send/booking when intended identity cannot be established.

## Data protection and operations

Use synthetic fixtures outside approved production use. Do not log tokens, secrets, unnecessary candidate PII, message contents beyond approved audit snapshots, or full external payloads. Define retention, deletion, backup, recovery, audit access, incident ownership, and privacy review. Protect CV URL access and any future SharePoint binary documents; a link is still sensitive data.

## DLP and least privilege

Review organizational DLP policies for Dataverse, Outlook, Teams, SharePoint, HTTP/custom connectors, AI Builder, and Power BI before design is finalized. Grant only required table/API/connector permissions and environment access. No permission or policy exception is assumed. See [Integration Design](INTEGRATION_DESIGN.md) and [ALM Deployment](ALM_DEPLOYMENT.md).
