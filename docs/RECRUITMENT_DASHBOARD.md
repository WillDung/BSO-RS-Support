# Recruitment Dashboard

## Status

**2026-11-20 filter layout follow-up deployed.** The filter bar keeps Year, Position, Source, and Assigned TA paired with their dropdowns in four, two, or one column depending on viewport width. Refresh is right-aligned below the filters. Existing filter bindings, reads, error handling, and KPI calculations are unchanged.

**2026-11-20 repair deployed.** The Dashboard now resolves browser `window.Xrm` (or its model-driven parent) and uses the Dataverse Position title column, `os_sr_pos_ttl`. All six live read queries and four filter predicates succeeded under the checked identity. The browser harness verifies KPI rendering, filters, pending queue continuation, and read-failure handling. Owner testing in the actual app is still pending. See the [deployment receipt](CURRENT_STATE.md#recruitment-dashboard-repair-and-obsolete-console-panel-removal-2026-11-20).

**DEPLOYED to the live `srapp` model-driven app on 2026-11-19.** The Dashboard is a read-only model-driven WebResource, not an edited copy of the live Canvas Custom Page. It uses the signed-in user's `Xrm.WebApi` context and existing Dataverse read permissions. It never writes Candidate, Interview Schedule, or other business records and does not invoke Outlook or booking operations.

The exact `srapp` navigation item formerly pointing to `os_atsugground1availability_4d2f7` now points to Recruitment Dashboard. The legacy Custom Page remains in the solution and app component inventory; only its navigation item was replaced. The Dashboard is not a replacement booking experience.

The scoped deployment created `os_/bso/recruitment-dashboard.html` and `os_/bso/recruitment-dashboard.js`, updated the sitemap once with a fresh ETag, and issued one `PublishXml` for exactly those resources plus `srapp`. A fresh unmanaged solution export/unpack confirmed both resource components and the updated sitemap. Published resource content readback matched the local source hashes. No Console, Flow, Custom Page, Candidate, Schedule, role, or booking component was changed.

The owner should open Recruitment Dashboard, verify all six panels and the Year/Position/Source/TA filters load, and confirm the authorized results look correct. This check is read-only; do not create or alter Candidates or Schedules for it.

## Unified Booking Studio handoff (not deployed)

A fresh solution export contains the existing Custom Page `os_atsugground1availability_4d2f7`. Its exported `Screen1` source confirms that the current `ddScheduleMode` selects only **Available slots** or **Custom time**; it is not an interview-type selector. The page has `dpInterviewDate`, `txtTAEmail`, and `txtRoomEmail`, and three calls to the existing `ATSuggAvailabilityBridge.Run(...)` connection. The two email inputs have hardcoded defaults, the app has no Dataverse `DatabaseReferences`, and the source has no `Param()` Candidate/Schedule context binding. The sitemap navigation entry now points to Recruitment Dashboard, but the Custom Page component itself remains in the solution.

The verified Power Platform CLI exposes Canvas `download`, `list`, `pack`, `unpack`, and `create`, but no Canvas `upload` command. The existing standard Custom Page was obtained through the solution export; the packed source was not Studio-validated or deployed. Do not replace it with a new page or import a stale whole-solution package.

When the owner edits this existing page in Power Apps Studio, the bounded changes are:

1. Add a separate **Interview Type** choice with **Online — Microsoft Teams** and **Offline — At Factory**; retain `ddScheduleMode` for Available slots versus Custom time.
2. Replace `txtTAEmail` and `txtRoomEmail` defaults with validated Candidate Assigned TA and selected Meeting Room records. Do not use typed/default mailbox addresses as production resource identity.
3. Add model-driven app context that supplies a required Candidate ID and, for reschedule/cancel, the Schedule ID. Load Candidate status/email, assigned TA, Room, and current Round 1 Schedule from authorized Dataverse records; fail closed on missing or stale context. Neither parameter is currently present in the page.
4. Online availability must call a supported bridge with TA only. Offline availability must call it with TA and Room. Candidate and BSO calendars must never be queried. Keep the existing 30-minute slots, custom-time path, full-interval recheck, and stale-result invalidation.
5. Keep Create, Reschedule, and Cancel unavailable in the page until the separately authorized booking operation and external event/room/notification contracts are implemented and verified. Do not create events or send invitations from a Canvas formula.

These are owner Studio changes, not deployed behavior. Mode-specific availability is blocked because the current bridge contract returns both Room and TA results and the Flow is not included as an editable solution component in the fresh export. Candidate-context reads are blocked because the current page has no Dataverse data source or record-parameter binding. The approved booking architecture does not provision its proposed event IDs, Teams URL, idempotency/status fields, or booking APIs; organizer/sender policy and configured Reception/Security recipients also remain unverified. See [Integration Design](INTEGRATION_DESIGN.md#calendar-and-teams), [Data Model](DATA_MODEL.md), and [Product Decisions](PRODUCT_DECISIONS.md#open-decisions-and-external-dependencies).

## KPI contract

All Candidate-cohort metrics use the selected year-to-date window in Vietnam time (`Asia/Ho_Chi_Minh`, UTC+07:00): from local January 1 at 00:00 through the current local month/day/time. For a prior year, the window ends at the equivalent local month/day/time, with February 29 clipped to February 28 when needed. Dataverse `createdon` boundaries are sent as UTC instants; the end is exclusive.

| Metric | Definition and denominator | Exclusions |
|---|---|---|
| YTD Candidates | Count of distinct active `os_sr_cand` rows with `createdon` in the selected YTD window. | Inactive Candidate rows; records outside the selected Position, Source, or Assigned TA filter. |
| Pending Actions | Count of those active Candidates in Need Call Candidate, Candidate Answered, or Waiting Manual Scheduling. The same three statuses define the queue. | All other Candidate statuses and inactive rows. |
| Average Lead Time | Arithmetic mean of `(current active Round 1 schedule start - Candidate createdon)` in 24-hour days. One current schedule per Candidate is selected by latest schedule `createdon`. The denominator is the number of selected Candidates with a positive, valid lead interval. | Candidates not currently Round 1 Scheduled; Proposed, Cancelled, Superseded, non-Round-1, and inactive schedules; missing or non-positive intervals. A zero denominator displays unavailable, not zero days. |
| Interviews Scheduled | Distinct Candidate count in the selected YTD cohort whose current status is Round 1 Scheduled and who has an active Round 1 schedule whose Scheduling Status is Scheduled or unset (legacy manual schedule). | Inactive Candidates/schedules, non-Round-1 schedules, Proposed/Cancelled/Superseded schedules, and Candidates with a different current workflow status. |
| Candidate Pipeline by Status | Active Candidate counts grouped by current workflow status for the selected YTD cohort. Unknown status values are kept in an Unmapped status bucket rather than silently discarded. | Inactive rows and rows outside the selected YTD/filter cohort. |
| Pending Action Queue | First 50 matching active Candidates, ordered by oldest `createdon` and then Candidate ID. Load more follows the server-issued continuation link. Rows show Candidate name/number, workflow status, Position, Source, Assigned TA, and creation date; email, phone, and CV URL are not requested. | Same status, date, and reference filters as Pending Actions. |

Position, Source, and Assigned TA filters use Candidate lookup references. The TA filter on scheduled interviews additionally requires the active Round 1 schedule's TA to match the selected Candidate Assigned TA; mismatches are excluded. Results are limited to records the signed-in user may read. Query failures and invalid/over-limit responses produce an explicit unavailable state; they are never converted to zero counts.

## Validation and release boundary

Offline tests cover Vietnam-time YTD boundaries, prior-year leap-day clipping, status aggregation, status/lookup filters, minimal queue projection, schedule deduplication, legacy schedule rows, and lead-time denominator behavior.

The owner performs the read-only live Dashboard check after scoped deployment: open `Recruitment Dashboard`, verify filters and all six panels load, compare a selected Candidate's status/Assigned TA and an active Round 1 schedule through existing read-only views, and confirm the page displays the same authorized counts. Do not create or alter Candidates or Schedules for this test.
