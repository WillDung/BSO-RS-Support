# Candidate UI Implementation Note

**Status (27 October 2026):** Implemented, published, and browser-accepted in VN LMV IT as a DEV-only direct-write fallback. Not production-ready.

**Acceptance:** `FIRST_VISIBLE_VERTICAL_SLICE_COMPLETE_DEV_DIRECT_WRITE_FALLBACK`; `CANDIDATE_MANAGEMENT_UI_WORKING`; `CREATE_CANDIDATE_WORKING`; `RECORD_CALL_WORKING`; `STATUS_HISTORY_VISIBLE`; `CANDIDATE_CORE_PRODUCTION_BACKEND_REMAINS_PENDING`.

One synthetic Candidate was created and appeared in the list with a server-generated Candidate Number and `Need Call Candidate` status. No Answer created one Call Log and preserved status. Answered created the second Call Log, changed status to `Candidate Answered`, and created the visible `Need Call Candidate -> Candidate Answered` Status History entry. Final readback: Candidate / Call Log / Status History / Operation Receipt = **1 / 2 / 1 / 0**.

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
