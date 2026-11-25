# Recruitment Dashboard

## Phase 2.2A unified Round 1 UI deployment status (2026-11-25)

**BLOCKED; no production writes or publication occurred.** The exact VN LMV IT target and `srapp`/solution identity were confirmed. The prior environment-resource hash mismatch is explained and its helper baseline pin is reconciled to the owner-authorized NORMAL-mode configuration; fresh current, published, and served bytes match, and the live HTML cache token matches. Deployment remains blocked because no exclusive publication window covering relevant makers and automated publishers is confirmed. Conditional PATCH ETags and scoped `PublishXml` limit risk but cannot prevent a competing publication. Existing external backup files were previously verified, but were not revalidated in this follow-up and do not prove an executable LIVE rollback. No Custom Page or Flow changes are in scope; provider availability, booking confirmation, and external booking operations remain disabled. See the [latest deployment preflight](CURRENT_STATE.md#phase-22a-approved-production-deployment-preflight-2026-11-25) and the [historical LIVE resource reconciliation](CURRENT_STATE.md#historical-phase-22a-live-release-reconciliation-2026-11-25).

## Status

**Phase 2.1 checkpoint (2026-11-25): PARTIAL / exact target and fresh read-only LIVE reconciliation VERIFIED; Studio integration BLOCKED.** PAC matched `https://org14938ec2.crm4.dynamics.com` to VN LMV IT and confirmed `srapp` plus unmanaged solution `os_sr_bso_rs_support` version `1.0.0.1`. The Console verifier returned MATCH across source/current/draft/published/served content for all three WebResources. The existing Custom Page is Published at app version `2026-11-19T06:43:16Z`; its exported binary matches the 2026-11-20 baseline. Target-scoped generated schema types confirm the Candidate, Schedule, TA, and Location identifiers listed in the handoff. No business rows were read, and no Studio edit, publication, provider call, business write, or deployment occurred. Keep the existing preview as fallback and keep the Candidate Console launcher, availability, and external booking disabled. Focused offline tests cover the Console preview and availability UI only; they do not accept the Custom Page. See [Current State](CURRENT_STATE.md#phase-21-candidate-context-integration-checkpoint-2026-11-25).

**2026-11-20 filter layout follow-up deployed.** The filter bar keeps Year, Position, Source, and Assigned TA paired with their dropdowns in four, two, or one column depending on viewport width. Refresh is right-aligned below the filters. Existing filter bindings, reads, error handling, and KPI calculations are unchanged.

**2026-11-20 repair deployed.** The Dashboard now resolves browser `window.Xrm` (or its model-driven parent) and uses the Dataverse Position title column, `os_sr_pos_ttl`. All six live read queries and four filter predicates succeeded under the checked identity. The browser harness verifies KPI rendering, filters, pending queue continuation, and read-failure handling. Owner testing in the actual app is still pending. See the [deployment receipt](CURRENT_STATE.md#recruitment-dashboard-repair-and-obsolete-console-panel-removal-2026-11-20).

**DEPLOYED to the live `srapp` model-driven app on 2026-11-19.** The Dashboard is a read-only model-driven WebResource, not an edited copy of the live Canvas Custom Page. It uses the signed-in user's `Xrm.WebApi` context and existing Dataverse read permissions. It never writes Candidate, Interview Schedule, or other business records and does not invoke Outlook or booking operations.

The exact `srapp` navigation item formerly pointing to `os_atsugground1availability_4d2f7` now points to Recruitment Dashboard. The legacy Custom Page remains in the solution and app component inventory; only its navigation item was replaced. The Dashboard is not a replacement booking experience.

The scoped deployment created `os_/bso/recruitment-dashboard.html` and `os_/bso/recruitment-dashboard.js`, updated the sitemap once with a fresh ETag, and issued one `PublishXml` for exactly those resources plus `srapp`. A fresh unmanaged solution export/unpack confirmed both resource components and the updated sitemap. Published resource content readback matched the local source hashes. No Console, Flow, Custom Page, Candidate, Schedule, role, or booking component was changed.

The owner should open Recruitment Dashboard, verify all six panels and the Year/Position/Source/TA filters load, and confirm the authorized results look correct. This check is read-only; do not create or alter Candidates or Schedules for it.

## Unified Booking Studio handoff (not deployed)

**Phase 2 scope:** the Candidate Console context panel is independent of the Custom Page. It uses signed-in Dataverse reads to show the selected Candidate and matching Round 1 context; it does not launch the standalone page with parameters the page would ignore. Existing manual actions remain separate and available. Replace the interim panel with the contextual launcher only after the Studio changes and bridge contract pass the checks below.

For the sequential owner-only Studio procedure, verified logical schema names, unresolved aliases/control identifiers, acceptance gates, and the post-acceptance navigation sketch, see [Phase 2.1B Studio Implementation Handoff](PHASE_2_1_STUDIO_IMPLEMENTATION.md).

### Fresh LIVE target, version, and schema reconciliation (2026-11-25)

This was read-only and ran only after the supplied URL matched the discovered VN LMV IT environment. PAC confirmed the `srapp` model-driven app and unmanaged `os_sr_bso_rs_support` solution (version `1.0.0.1`) in that environment.

The existing scoped verifier returned **MATCH** for Candidate Console source/current/draft/published/served HTML, JavaScript, and CSS. Versions and hashes are unchanged from the table in the 2026-11-20 reconciliation below; no Console deployment was needed. The existing Custom Page `os_atsugground1availability_4d2f7` is Published with app version `2026-11-19T06:43:16Z`. Its 40,208-byte exported binary SHA-256 remains `eafb8df84c0adfeebac537119f57a3d932058948939d84161d75a514afb29d60`, so there is no page binary/version drift from the 2026-11-20 baseline. Its source still has no Candidate/Schedule `Param()` binding or Dataverse `DatabaseReferences`.

PAC-generated types against the matched URL confirm these live logical identifiers and relationships:

| Table | Primary ID | Verified context fields / lookups |
|---|---|---|
| Candidate `os_sr_cand` | `os_sr_candid` | `os_sr_cand_cnum`, `os_sr_cand_nm`, `os_sr_cand_eml`, `os_sr_cand_stat`, TA lookup `os_sr_cand_ta` to `os_sr_ta` |
| Interview Schedule `os_sr_intv` | `os_sr_intvid` | Candidate `os_sr_intv_cand`, TA `os_sr_intv_ta`, Location `os_sr_intv_loc`, Round `os_sr_intv_rnd`, Start/End `os_sr_intv_strt` / `os_sr_intv_end`, status `os_sr_intv_stat`, result `os_sr_intv_res` |
| TA Directory `os_sr_ta` | `os_sr_taid` | Name `os_sr_ta_nm`, Email `os_sr_ta_eml` |
| Location `os_sr_loc` | `os_sr_locid` | Name `os_sr_loc_nm`, Room/Resource Email `os_sr_loc_rmeml` |

This type-generation read confirms field/lookup/Choice identifiers, not field requiredness, Studio-generated data-source aliases, effective record-level access, or page behavior. No Candidate or Schedule business records were queried. Focused offline validation passed: `node --test .\tests\CandidateConsoleBookingContext.test.cjs .\tests\CandidateConsoleAvailability.test.cjs` (**31 passed**); those tests do not accept the Custom Page or prove LIVE authorization. The Console source still opens its safe booking-context preview; no navigation change was made.

### Fresh LIVE bridge and page reconciliation (2026-11-20)

This was a read-only inspection. No flow was invoked, no availability was queried, no Candidate or Schedule row was read, and no app, flow, connection, or tenant setting was changed.

The Candidate Console baseline is reconciled across repository source (with only its environment-specific HTML cache token normalized), fresh solution export, current/unpublished WebResource content, published content, and authenticated served bytes:

| WebResource | Version | Bytes | SHA-256 |
|---|---:|---:|---|
| `candidate-console.html` | `15695115` | `21725` | `11e87c73005cdae155ec2e43e453e3b484815714a63638d2569575965a713e65` |
| `candidate-console.js` | `15695110` | `193782` | `94fc532e7c85a0b20e08a1edf31105cafc4205440b707df5159508bfd8fd0719` |
| `candidate-console.css` | `14754315` | `5128` | `6681994a0d57e46ed1b3f0be291556fba37be262f822c8b483d31d00f1130fde` |

The existing Custom Page `os_atsugground1availability_4d2f7` is still the pre-Phase-2 binary: app version `2026-11-19T06:43:16Z`, 40,208 bytes, SHA-256 `eafb8df84c0adfeebac537119f57a3d932058948939d84161d75a514afb29d60`. Its source has no `Param()` call or Candidate/Schedule table binding, and its metadata has an empty `DatabaseReferences` collection. Its existing connection references are the Power Apps Flow connection and the preauthorized HTTP-with-Entra connector; no Dataverse table data source is bound to the page.

**`ATSuggAvailabilityBridge` contract, from the live Flow definition and exported Page source:**

- The Power Apps V2 trigger requires one string input, `text`. The Flow parses that JSON string and requires `roomEmail`, `taEmail`, `startDateTime`, and `endDateTime`.
- The Flow sends an HTTP `POST` through `shared_webcontents`; the sanitized definition does not expose a directly verifiable Microsoft Graph endpoint or the external service implementation. Do not claim that this proves a Graph call or its end-to-end calendar-selection behavior.
- The Flow response contains a string `resulttext`. The Page uses it for both slot listing and custom-time checks.
- There is no interview-mode or correlation field. The Page sends both mailbox strings at each of its three call sites, requires exactly two returned schedules, and validates both identities. It cannot express a TA-only request. The Flow/Page request contains no Candidate or BSO mailbox fields, but the external HTTP target's behavior is not visible from this contract, so the end-to-end exclusion guarantee is not established.
- For displayed slots, the Page expects two 96-character `availabilityView` strings and checks six characters per nominal 30-minute slot. The interval represented by each character was not verified; complete 30-minute coverage is therefore not established.

**Separate `os_sr_avchk` Flow contract:** the live definition is listed as Published, while older repository notes describe it as OFF. Reconcile its effective on/off state with the Flow owner before invoking it. Its trigger is a Pending `os_sr_avq` request (no Candidate or Interview Schedule input). The definition reads the TA Directory row by request lookup and reads Location only in its Onsite branch; it passes TA as `RequiredAttendees` and conditionally passes Location as `ResourceAttendees` to Office 365 Outlook `FindMeetingTimes_V2`, then completes the query through `os_sr_avq_complete`. This is definition-level evidence that the separate Flow supports Online TA-only and Offline TA+Room with Dataverse mailbox resolution and no Candidate/BSO attendee fields. It is not the Custom Page's `ATSuggAvailabilityBridge`, is not called by that page, and was not executed or runtime-accepted here. The exact connector-bound identity, effective caller privileges, DLP applicability, run-history protection, and successful response behavior remain unverified.

The live schema metadata confirms Candidate primary ID `os_sr_candid` with Candidate Number, Candidate Name, Candidate Email, Assigned TA, and workflow status; Interview Schedule primary ID `os_sr_intvid` with Candidate, TA, required Location, Round, Start/End, scheduling status, and result; TA Directory primary ID `os_sr_taid` with TA Name/Email; and Location primary ID `os_sr_locid` with Location Name and optional Room/Resource Email. These were metadata reads only. Effective record-level access for the intended application user was not tested.

### Smallest owner Studio changes

The supported model-driven Custom Page context is one record at a time: `pageType`, `name`, `entityName`, and `recordId` ([Microsoft Custom Page navigation example](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/clientapi/navigate-to-custom-page-examples)). The custom page can read `Param("entityName")` and `Param("recordId")`; arbitrary `data` is not a supported Custom Page parameter. Therefore:

- **Create:** navigate with `entityName: "os_sr_cand"` and the selected Candidate GUID as `recordId`.
- **Reschedule/Cancel:** navigate with `entityName: "os_sr_intv"` and the exact Schedule GUID as `recordId`; the page must load the related Candidate through the Schedule lookup and verify the relationship/state. There is no separate operation parameter, so the page must present an explicit operation choice for this schedule context.
- Do not pass two IDs through undocumented URL parameters. Reject a missing, invalid, inaccessible, inactive, stale, or mismatched record context.

### Phase 2.1 Studio handoff and acceptance gates

**Prepared only; no Studio or LIVE page change is claimed.** The existing page is `os_atsugground1availability_4d2f7`, screen `Screen1`. The last LIVE evidence (2026-11-20) identifies these existing controls: `ddScheduleMode` (Available slots / Custom time only), `dpInterviewDate`, `txtTAEmail`, and `txtRoomEmail`. The latter two contain hardcoded address defaults and must not remain user-editable resource identity inputs. Keep the existing page; do not create or import a replacement.

The local solution metadata provides these exact Dataverse table and schema identifiers for the Studio owner to match against the actual data sources:

| Table | Primary ID | Context/display fields and lookups |
|---|---|---|
| Candidate `os_sr_cand` | `os_sr_candid` | Candidate Number `os_sr_cand_cnum`; Name `os_sr_cand_nm`; Email `os_sr_cand_eml`; Assigned TA lookup `os_sr_cand_ta`; workflow status `os_sr_cand_stat`; `statecode` |
| Interview Schedule `os_sr_intv` | `os_sr_intvid` | Candidate lookup `os_sr_intv_cand`; TA lookup `os_sr_intv_ta`; Location lookup `os_sr_intv_loc`; Round `os_sr_intv_rnd`; Start/End `os_sr_intv_strt` / `os_sr_intv_end`; scheduling status `os_sr_intv_stat`; result `os_sr_intv_res`; `statecode` |
| TA Directory `os_sr_ta` | `os_sr_taid` | TA Name `os_sr_ta_nm`; TA Email `os_sr_ta_eml`; `statecode` |
| Location `os_sr_loc` | `os_sr_locid` | Location Name `os_sr_loc_nm`; Room/Resource Email `os_sr_loc_rmeml`; `statecode` |

The 2026-11-25 target-scoped PAC type generation confirms that the listed primary IDs, context/display fields, lookups, and Choice fields exist with the shown logical names and lookup targets. It does not expose field requiredness or Studio-generated data-source aliases. The exact Power Apps data-source aliases, generated Power Fx column identifiers, lookup dereference syntax, choice symbols, and new control names still cannot be verified without the owner’s Studio session; they are **unresolved**. Do not copy a display-name formula or invent those identifiers as if tested.

Initialize on every page entry via `Screen1.OnVisible`, not only `App.OnStart`. This exact Power Fx reset/parameter-validation block must run before record reads:

```powerfx
Set(varContextLoading, true);
Set(varContextError, Blank());
Set(varContextEntity, Param("entityName"));
Set(varContextIdRaw, Param("recordId"));
Set(varContextId, IfError(GUID(varContextIdRaw), Blank()));
Set(varCandidate, Blank());
Set(varSchedule, Blank());
Set(varAssignedTA, Blank());
Set(varOperation, Blank());
Set(varInterviewType, Blank());
Set(varReason, Blank());
Set(varAvailabilityState, "Disabled");
Set(varAvailableSlots, Blank());
If(
    IsBlank(varContextId),
    Set(varContextError, "A valid record context is required."),
    If(
        varContextEntity <> "os_sr_cand" && varContextEntity <> "os_sr_intv",
        Set(varContextError, "Unsupported record context.")
    )
)
```

The illustrative lookup formula in the next section is **not a verified executable formula** until its data-source aliases and generated column/lookup names are matched in Studio. Move per-entry initialization from `App.OnStart` to `Screen1.OnVisible`; then complete and validate the lookups so they fail closed on missing/inaccessible records, data-source errors, inactive records, mismatched Candidate/Schedule/TA relationships, or stale context. Require an active Round 1 Schedule that belongs to the loaded Candidate and exactly one valid current schedule for Reschedule/Cancel. Resolve Assigned TA from the authorized Candidate read; for Schedule context verify the Schedule TA agrees and is active. Clear all previous Candidate/Schedule/TA, operation, interview-type, reason, availability, slot, and error state on each entry. Keep loading visible until reads finish; display explicit empty/unavailable, unauthorized, and error states without treating a parameter as proof of authorization.

Display Candidate Number, Name, Email, Assigned TA, and the Round 1 Schedule/status where applicable. Create/Reschedule/Cancel may be offered only after context validation; all execution remains disabled. Reschedule/Cancel reasons are required but never submitted. Keep Online/Offline separate from `ddScheduleMode`: Online requires an active Assigned TA and hides/unrequires the Room; Offline requires an active authorized Location/Room. The existing controls `txtTAEmail` and `txtRoomEmail` must not supply provider identities. New operation, mode, reference-selector, reason, and state controls have no verified names yet; record their actual Studio names in the owner handoff after creation.

**Owner publish and rollback sequence:** before editing, capture a recoverable copy of the exact existing page and record its current Studio/published version; no validated page backup or Studio restore procedure is present in this repository. Do not publish if the backup or owner rollback path is unavailable. Test the page with synthetic, caller-authorized Candidate and Schedule context first. Publish only the existing page from Studio and verify the published version and context behavior. Do not import a stale solution, replace the page, or change the Console sitemap/launcher as part of this page publish. If any acceptance check fails, restore the captured page version using the owner-verified Studio restore method and republish that page; keep the Console preview as fallback. A later Console launcher change is a separate scoped release after page acceptance.

**Next LIVE acceptance tests (after target confirmation and Studio publish):** reconcile the Console and existing page published versions; verify the model-driven app passes the exact entity/record pair for Candidate Create and Schedule Reschedule/Cancel; test malformed/missing GUID, wrong entity, inaccessible/missing records, inactive Candidate/Schedule/TA/Room, mismatched Schedule-to-Candidate/TA, stale context, and multiple active Round 1 schedules; verify Online TA-only and Offline active Room requiredness; confirm required reasons with all submit/provider controls disabled; verify loading/empty/unauthorized/error states; and reconcile zero Candidate/Schedule writes, availability requests, Flow invocations, and Outlook/Teams invitations. Do not use real Candidate data or run lifecycle Playwright UAT.

In the existing page in Power Apps Studio (not by replacing the exported `.msapp`), the owner must:

1. Add the existing Dataverse tables Candidate (`os_sr_cand`), Interview Schedule (`os_sr_intv`), TA Directory (`os_sr_ta`), and Location (`os_sr_loc`). Add Availability Query (`os_sr_avq`) only if the owner chooses the separate `os_sr_avchk` route. The Studio-generated data-source aliases remain unresolved and must be recorded from the owner’s session.
2. Put per-entry initialization on `Screen1.OnVisible`, not only `App.OnStart`; reset previous state and validate `Param("recordId")` and `Param("entityName")` before any read (see the Phase 2.1 handoff above). The following older bounded context-loading formula uses unverified Studio field/lookup names and is a reference only; the owner must validate those names and run the actual page in Studio before using it:

   ```powerfx
   Set(varContextError, Blank());
   Set(varContextEntity, Param("entityName"));
   Set(
       varContextId,
       If(
           IsBlank(Param("recordId")),
           Blank(),
           IfError(GUID(Param("recordId")), Blank())
       )
   );
   Set(varCandidate, Blank());
   Set(varSchedule, Blank());
   If(
       IsBlank(varContextId),
       Set(varContextError, "A valid record context is required."),
       Switch(
           varContextEntity,
           "os_sr_cand",
           Set(varCandidate, LookUp(Candidates, Candidate = varContextId)),
           "os_sr_intv",
           Set(
               varSchedule,
               LookUp(
                   'Interview Schedules',
                   'Interview Schedule' = varContextId
               )
           ),
           Set(varContextError, "Unsupported record context.")
       )
   );
   If(
       varContextEntity = "os_sr_intv" && IsBlank(varSchedule),
       Set(varContextError, "The selected schedule is unavailable."),
       If(
           varContextEntity = "os_sr_intv",
           Set(
               varCandidate,
               LookUp(
                   Candidates,
                   Candidate = varSchedule.Candidate.Candidate
               )
           )
       )
   );
   If(
       IsBlank(varContextError) && IsBlank(varCandidate),
       Set(varContextError, "The selected Candidate is unavailable.")
   )
   ```

   Before showing actions, also require active Candidate/Schedule state, Round 1, the Schedule's Candidate matching the loaded Candidate, an active Assigned TA, and exactly one valid current Schedule for Reschedule/Cancel. Re-read and validate the exact IDs/version before any later mutation; this formula is not authorization or booking evidence.
3. Keep the existing Available slots / Custom time control distinct from Interview Type. Add an explicit Online/Offline selector and an explicit Create/Reschedule/Cancel choice where applicable. Map the user-facing Offline choice to the existing `os_sr_avq_mod` Onsite choice.
4. Replace literal/default mailbox text inputs with the authorized Assigned TA and active Location records. For `os_sr_avchk`, use row IDs and let its Dataverse-backed Flow resolve TA/Location mailboxes; do not send user-editable mailbox addresses to a provider as resource identity. The Location selector is required only for Offline/Onsite.
5. If reusing `os_sr_avchk`, replace the three direct bridge calls with the authorized Availability Query request/poll/result contract and bind the returned canonical UTC slots. Do not enable availability until the Flow's effective state, identity, DLP, caller Create/Read permissions on `os_sr_avq`, and runtime result contract are confirmed. Keep all booking operations disabled.

The Console must then replace `showBookingContext` as the page-launch action with `Xrm.Navigation.navigateTo` using the contract above, only after the owner has published and verified the context-bound page. The current button still opens the Console preview, not the Custom Page.

A fresh solution export contains the existing Custom Page `os_atsugground1availability_4d2f7`. Its exported `Screen1` source confirms that the current `ddScheduleMode` selects only **Available slots** or **Custom time**; it is not an interview-type selector. The page has `dpInterviewDate`, `txtTAEmail`, and `txtRoomEmail`, and three calls to the existing `ATSuggAvailabilityBridge.Run(...)` connection. The two email inputs have hardcoded defaults, the app has no Dataverse `DatabaseReferences`, and the source has no `Param()` Candidate/Schedule context binding. The sitemap navigation entry now points to Recruitment Dashboard, but the Custom Page component itself remains in the solution.

The verified Power Platform CLI exposes Canvas `download`, `list`, `pack`, `unpack`, and `create`, but no Canvas `upload` command. The existing standard Custom Page was obtained through the solution export; the packed source was not Studio-validated or deployed. Do not replace it with a new page or import a stale whole-solution package.

**Implementation boundary:** The context and availability changes above are owner-only Studio work and are not deployed. The current bridge cannot accept mode, correlation, or canonical record IDs. The separate `os_sr_avchk` definition has the mode-specific resource-selection shape but is not connected to the Page; its effective state, identity, DLP, caller authorization, and runtime result contract remain unresolved. Keep availability and all booking operations disabled until those dependencies and the authorized page context are verified. The approved external booking architecture still lacks implemented event/room operations, durable idempotency/status fields, and verified organizer/sender and Reception/Security configuration. See [Integration Design](INTEGRATION_DESIGN.md#calendar-and-teams), [Data Model](DATA_MODEL.md), and [Product Decisions](PRODUCT_DECISIONS.md#open-decisions-and-external-dependencies).

**External operation contract (proposed; no callable endpoint):** The authenticated server must accept operation, Candidate ID, exact Schedule ID/version where applicable, expected Candidate state, interview type, canonical resource IDs, UTC interval, reason for Reschedule/Cancel, current evidence reference and a caller-generated idempotency key. Recheck access, resource state, Candidate prerequisites, evidence binding and full-interval availability before dispatch. Persist a durable operation receipt and deduplicate by organization, actor, key and payload fingerprint; reject changed payloads using the same key. Resolve the organizer and attendee addresses from approved server-side configuration and authorized records. Online success requires acknowledged Teams event ID and join URL; Offline requires the confirmed response from the Room, not merely an Outlook event ID. Track Candidate/TA invitation and Reception/Security notifications separately with approved recipients and templates. On ambiguous provider results, reconcile against the organizer calendar before retrying; retain prior events and history until replacement or cancellation is confirmed. Never update business state as if a provider side effect occurred when evidence is missing. Deployment requires an approved organizer binding, supported authenticated adapter and least-privilege permissions, durable external booking fields/receipt, and approved visitor notification configuration. Do not substitute the existing manual scheduling action for this contract.

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
