# Candidate UI Implementation Note

**Status:** Not implemented or published. The first-visible vertical-slice acceptance criterion is unmet.

## Intended experience

The approved MVP experience is `srapp` → New Candidate → save → Record Call → see Candidate status, Call Log, and Status History. Candidate creation and call/state changes must use Candidate Core unless an explicitly approved, isolated DEV fallback is available. The app remains caller-context and must not silently impersonate a BSO through a fixed Flow-owner connection.

## Current evidence

- One existing unsigned Candidate Core package update was made in VN LMV IT.
- The single synthetic CreateCandidate acceptance request was rejected at `CC_CREATE_CANDIDATE` with `DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_PROTECTED_WRITE:CC_CREATE_CANDIDATE:0x80040265`.
- A post-attempt GET-only reconciliation confirmed 0 Candidates / 0 Call Logs / 0 Status History rows / 0 Operation Receipts.
- No Candidate navigation, custom page, form, command, Power Automate flow, or app publication was created in this run.
- Read-only flow listing returned 34 cloud flows; no names or descriptions matched Candidate, Record Call, Status History, DEV/TEMP, BSO-RS, or `os_sr`. This does not rule out a relevant flow under another name. No supported flow-creation operation was available in the session tools.
- Read-only generated-page listing found no custom pages for `srapp`.
- A custom-page upload/sitemap tool is available, but creating a page alone would not satisfy the workflow: the production Custom API path is currently rejected, and no working DEV flow exists to handle writes. No unusable page was published.
- The maker portal browser entry redirected to Microsoft sign-in. No interactive sign-in was initiated, and browser-based app verification was not performed.

## DEV fallback blocker

The requested DEV flow cannot presently provide the permitted direct-write fallback while the package guard rejects Candidate, Call Log, and Status History writes without a trusted `os_sr_cact` ancestor. Calling Candidate Core from the flow is also blocked by the observed guard failure. Adding a guard bypass would contradict the still-required direct-write rejection and caller-identity rules; no such bypass, owner impersonation, or second business backend was introduced.

To resume, the owner must resolve that constraint explicitly: either authorize a bounded Candidate Core correction (without starting another readiness phase), or approve a specific DEV-only exception to the direct-write guard and its identity/security implications. A safe, verified flow-authoring path and run-only-user connection design would also be required before a flow is created. Until then, do not claim a working UI, DEV fallback, or production-ready backend.

See the [current state](CURRENT_STATE.md), [project context](PROJECT_CONTEXT.md), and [Phase 3D runtime report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).
