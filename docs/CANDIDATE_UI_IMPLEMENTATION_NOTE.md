# Candidate UI Implementation Note

**Current status (27 October 2026):** Phase 4A and the Phase 4B reference/security slice are implemented, published, and browser-accepted in VN LMV IT as a DEV-only direct-write fallback. `PHASE_4B_REFERENCE_AND_SECURITY_COMPLETE`; `SCHEDULING_STORAGE_NOT_PROVISIONED`; `BSO_SECURITY_ROLE_VALIDATED_UNASSIGNED`. Not production-ready.

Phase 4B created one synthetic `[DEV]` Position, Candidate Source, Location, and TA Directory reference row; no existing reference data was overwritten. Candidate Create loads Position and Candidate Source and displays the saved references. Browser acceptance created one synthetic Candidate using both references, verified Candidate Number/name/email/status/Created On and reference values, recorded one Answered Call Log, then moved the Candidate from `Candidate Answered` to `Waiting Manual Scheduling` with both transitions visible in Status History. Search by Candidate Number and the status filter were also verified.

The `Schedule Round 1` action is visible only for a synthetic Candidate at `Waiting Manual Scheduling`. Its draft form includes Candidate, TA, Interview Date, Start Time, Location, and Notes; the synthetic TA and Location choices loaded. The `Save Schedule` control is disabled and the form states `SCHEDULING_STORAGE_NOT_PROVISIONED`. Live metadata returned not found for the proposed `os_sr_irnd`, `os_sr_ires`, and `os_sr_vreg` tables and found no interview/scheduling persistence table. No scheduling write occurred, no Candidate advanced to `Round 1 Scheduled`, and no schema was created. The acceptance Candidate remains at `Waiting Manual Scheduling`. Next work is a separately scoped scheduling-storage provisioning decision and implementation, not a scheduling-complete milestone.

The `BSO-RS Support - BSO` role was re-read: its 17 intended business privileges remain at the expected depths and the role remains unassigned. Five organization-level plug-in/SDK metadata Read defaults and four previously identified SharePoint-related defaults were not changed; all are classified `REVIEW BEFORE PRODUCTION`. No role assignment, package deployment, schema change, or guard change occurred in this phase. **`REAL DATA PROHIBITED`; `VN_LMV_IT_PROTECT_CANDIDATE_CORE_DEV_KILL_SWITCH_ACTIVE`; `CANDIDATE_CORE_PRODUCTION_BACKEND_REMAINS_PENDING`.**

## Phase 4A acceptance record (27 October 2026)

**Phase 4A classification:** `PHASE_4A_CANDIDATE_UI_DEV_USABLE`; `CANDIDATE_SEARCH_AND_DETAIL_WORKING`; `RECORD_CALL_UX_WORKING`; `WAITING_MANUAL_SCHEDULING_TRANSITION_WORKING`; `BSO_SECURITY_ROLE_BASELINE_CREATED`; `VN_LMV_IT_PROTECT_CANDIDATE_CORE_DEV_KILL_SWITCH_ACTIVE`; `REAL_DATA_PROHIBITED`; `CANDIDATE_CORE_PRODUCTION_BACKEND_REMAINS_PENDING`. At Phase 4A close, the later Phase 4B reference/security work had not started; its current outcome is recorded above.

Browser acceptance used one fresh synthetic Candidate. Search and status filtering worked; the Candidate detail showed its fields and histories; the No Answer and Answered calls created two Call Logs and the expected first status transition; the guarded button then moved the Candidate from `Candidate Answered` to `Waiting Manual Scheduling`, producing the second visible Status History transition. Final acceptance-scope readback: Candidate / Call Log / Status History / Operation Receipt = **1 / 2 / 2 / 0**. No Receipt write occurred and arbitrary status editing was not exposed. The Position and Candidate Source tables were readable but empty, so their optional selection path was not exercised.

The first visible slice was separately accepted earlier: a synthetic Candidate appeared with its server-generated Candidate Number and `Need Call Candidate` status; No Answer preserved status; Answered moved it to `Candidate Answered` with visible Status History. That acceptance readback was Candidate / Call Log / Status History / Operation Receipt = **1 / 2 / 1 / 0**.

The unassigned role `BSO-RS Support - BSO` was added to `os_sr_bso_rs_support` and verified as a Role solution component. Its 17 requested table privileges and depths were verified after reload: User (Basic) for Candidate Create/Read/Write/Append/Append To, Call Log Create/Read/Append/Append To, and Candidate Status History Create/Read/Append/Append To; Organization for Read on TA Directory, Position, Candidate Source, and Location. No Operation Receipt or Candidate/Call Log/Status History Delete privilege was set. Platform defaults remain in the role and require security review before any assignment. The role has not been assigned to a user or exported into an unpacked repository solution snapshot.

**`VN_LMV_IT_PROTECT_CANDIDATE_CORE_DEV_KILL_SWITCH_ACTIVE`. REAL DATA PROHIBITED. MUST RESTORE GUARDS BEFORE SECURITY/PRODUCTION ACCEPTANCE.** All 50 live registrations handled by `os_sr_cact.ProtectCandidateCore` are inactive in VN LMV IT; both `ApplyCandidateAction` steps remain active. The redacted pre-change restoration baseline and protected-property fingerprints are stored in the private session-state file `vn-lmv-it-protectcandidatecore-baseline-20261027.json`. Do not treat this DEV exception as a production architecture or readiness decision.

## Intended experience

The approved MVP experience is `srapp` → New Candidate → save → Record Call → see Candidate status, Call Log, and Status History. Candidate creation and call/state changes must use Candidate Core unless an explicitly approved, isolated DEV fallback is available. The app remains caller-context and must not silently impersonate a BSO through a fixed Flow-owner connection.

## Historical pre-DEV evidence (26 October 2026)

- One existing unsigned Candidate Core package update was made in VN LMV IT.
- The single synthetic CreateCandidate acceptance request was rejected at `CC_CREATE_CANDIDATE` with `DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_PROTECTED_WRITE:CC_CREATE_CANDIDATE:0x80040265`.
- A post-attempt GET-only reconciliation confirmed 0 Candidates / 0 Call Logs / 0 Status History rows / 0 Operation Receipts.
- No Candidate navigation, custom page, form, command, Power Automate flow, or app publication was created in this run.
- Read-only flow listing returned 34 cloud flows; no names or descriptions matched Candidate, Record Call, Status History, DEV/TEMP, BSO-RS, or `os_sr`. This does not rule out a relevant flow under another name. No supported flow-creation operation was available in the session tools.
- Read-only generated-page listing found no custom pages for `srapp`.
- A later shared, authenticated maker session verified the existing `srapp` (`BSO-RS-Support`) is accessible in the VN LMV IT app editor. Its navigation contains Administration plus TA Directory, Positions, Candidate Sources, and Locations views/forms; no Candidate, Call Log, or Status History page is present. The embedded app preview shows reference-data navigation only.
- The same authenticated Power Apps Flows page exposed a list/filter-only widget (My flows, Shared with me, All flows) with no flow-create control. The visible My flows list contained only document-automation flows; the earlier environment-wide list had 34 flows and no matching Candidate/DEV names or descriptions. These checks do not exclude an unrelated flow under another name.
- The Power Automate maker URL opened separately redirects to Microsoft sign-in in this browser context; no interactive sign-in was initiated. A custom-page upload/sitemap tool is available, but creating a page alone would not satisfy the workflow: the production Custom API path is currently rejected, and no working DEV flow exists to handle writes. No unusable page was published.

## Historical DEV fallback blocker (superseded 27 October 2026)

The requested DEV flow cannot presently provide the permitted direct-write fallback while the package guard rejects Candidate, Call Log, and Status History writes without a trusted `os_sr_cact` ancestor. Calling Candidate Core from the flow is also blocked by the observed guard failure. Adding a guard bypass would contradict the still-required direct-write rejection and caller-identity rules; no such bypass, owner impersonation, or second business backend was introduced. The newly shared maker session enables inspection of `srapp` and its flow list, but did not expose a flow-authoring surface.

To resume, the owner must resolve that constraint explicitly: either authorize a bounded Candidate Core correction (without starting another readiness phase), or approve a specific DEV-only exception to the direct-write guard and its identity/security implications. A safe, verified flow-authoring path and run-only-user connection design would also be required before a flow is created. Until then, do not claim a working UI, DEV fallback, or production-ready backend.

See the [current state](CURRENT_STATE.md), [project context](PROJECT_CONTEXT.md), and [Phase 3D runtime report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).
