# Phase 2.1B Studio Implementation Handoff

**Status: OWNER-ONLY PREPARATION.** This is an implementation procedure for the existing Round 1 Availability Custom Page. No Studio edit, publication, Console navigation change, Flow change, provider call, or business write is made or claimed by this document.

The latest verified target, app/page version, and schema evidence is in [Current State](./CURRENT_STATE.md#phase-21-candidate-context-integration-checkpoint-2026-11-25) and the [Phase 2.1 handoff](./RECRUITMENT_DASHBOARD.md#phase-21-studio-handoff-and-acceptance-gates). Do not repeat environment discovery or baseline reconciliation unless there is new evidence of drift.

## 1. First owner action and stop conditions

**First owner action:** in Power Apps Studio, open the existing `srapp` solution component **ATSugg - Round 1 Availability**, logical name `os_atsugground1availability_4d2f7`, and confirm that the page being edited is the existing Custom Page with screen `Screen1`. Do not use Save As, create another page, import a solution, or migrate to a Code App.

Before editing:

1. Record the current published app version `2026-11-19T06:43:16Z` and establish a recoverable, owner-approved backup/restore path for this exact page. The repository does not establish a page-specific Studio restore procedure. **Stop before editing if the owner cannot verify how to restore and republish the captured page.**
2. Record the current page identity and the actual Studio control names/properties visible to the owner. The page binary is not checked into `solutions/`; use Studio as the authority for generated identifiers.
3. Use only existing, owner-authorized synthetic records for acceptance. Do not create or modify records, grant access, or use real candidate data.

The existing target and published baseline are verified; effective access for the intended interactive application user is not. Metadata or a successful PAC connection does not prove that the page caller can read a Candidate, Schedule, TA, or Location row. See [Security Model](./SECURITY_MODEL.md#approved-single-bso-check-calendar-scope-2026-11-07) and [Master Production Rules](../MASTER_PRODUCTION_RULES.md#identity-and-roles).

## 2. Existing page controls and verified schema

The existing page is `os_atsugground1availability_4d2f7`, screen `Screen1`. The last reconciled page source identifies:

| Existing control | Verified current purpose | Required handling |
|---|---|---|
| `ddScheduleMode` | Chooses **Available slots** or **Custom time** | Keep it for that purpose. It is not Online/Offline. |
| `dpInterviewDate` | Interview date input | Retain; it does not authorize or execute availability. |
| `txtTAEmail` | Text input with a hardcoded email default | Remove the hardcoded default and do not use it as resource identity or a provider input. Prefer a read-only display bound to the authorized Assigned TA, or hide it. Confirm the control type/property in Studio. |
| `txtRoomEmail` | Text input with a hardcoded email default | Remove the hardcoded default and do not use it as a Room selector or provider input. Prefer a Location selector showing authorized active Location records, or hide it. Confirm the control type/property in Studio. |

The page has three existing `ATSuggAvailabilityBridge.Run(...)` call sites. Their triggering control names are not established in the repository. Find them in Studio by locating each `.Run(` formula; keep every trigger disabled and detach the calls for this phase. Do not invoke the legacy bridge with placeholder or user-entered mailbox values.

Target-scoped PAC-generated types verified these logical names and lookup targets. Power Fx's Studio-generated aliases and field tokens are not implied by this table.

| Dataverse table | Primary ID | Verified context fields and lookups |
|---|---|---|
| Candidate `os_sr_cand` | `os_sr_candid` | Candidate Number `os_sr_cand_cnum`; Name `os_sr_cand_nm`; Email `os_sr_cand_eml`; workflow status `os_sr_cand_stat`; Assigned TA lookup `os_sr_cand_ta` to `os_sr_ta`; `statecode` |
| Interview Schedule `os_sr_intv` | `os_sr_intvid` | Candidate lookup `os_sr_intv_cand`; TA lookup `os_sr_intv_ta`; Location lookup `os_sr_intv_loc`; Round `os_sr_intv_rnd`; Start/End `os_sr_intv_strt` / `os_sr_intv_end`; scheduling status `os_sr_intv_stat`; result `os_sr_intv_res`; `statecode` |
| TA Directory `os_sr_ta` | `os_sr_taid` | TA Name `os_sr_ta_nm`; TA Email `os_sr_ta_eml`; `statecode` |
| Location `os_sr_loc` | `os_sr_locid` | Location Name `os_sr_loc_nm`; Room/Resource Email `os_sr_loc_rmeml`; `statecode` |

Round 1 is the only supported `os_sr_intv_rnd` value (`100000000`). The documented `os_sr_intv_stat` values are Proposed (`100000000`), Scheduled (`100000001`), Cancelled (`100000002`), and Superseded (`100000003`); legacy blank lifecycle values are treated as Scheduled by the existing workflow. These Dataverse values do not establish the enum token names Studio will generate.

**Schema dependency to resolve before any future business write:** the documented Schedule schema marks `os_sr_intv_loc` as a required lookup, while the Online UI requirement hides/unrequires a Room. The UI can hide the Room in this phase, but that does not make the Dataverse lookup optional. Do not change the schema or invent an Online placeholder Location here. Resolve the mismatch through an explicitly approved design before implementing any schedule write. The documented schema is in [Data Model](./DATA_MODEL.md#verified-round-1-interview-schedule-dev-table).

## 3. Unresolved Studio identifiers

Record the actual values in the owner’s Studio change notes before entering any lookup formula. Do not replace these with guessed display names.

| Identifier | Verified part | Still unresolved; owner must confirm in Studio |
|---|---|---|
| Dataverse data-source aliases | The four logical tables listed above | Exact data-source names shown in the page's Data pane and their Power Fx references |
| Column/lookup expressions | Logical IDs and fields listed above | Studio's formula-bar tokens for primary IDs, lookup records/IDs, `statecode`, Choice fields, and lookup dereferences |
| Choice symbols | Dataverse Choice fields and documented values | Studio-generated enum/label symbols and comparison syntax |
| Existing availability triggers | Three `.Run(` call sites exist | Names of the three controls/formulas containing them |
| New UI controls | None are established | Actual names chosen for operation, interview type, Location, reason, loading/error/empty state, and Candidate/Schedule display controls |
| Control properties | Existing control names above | Whether the control is classic/modern and which properties (`Default`/`Value`, `Selected`/`SelectedItems`, `DisplayMode`, etc.) are available |
| Published-page acceptance launch | Supported record context is defined below | An owner-approved way to launch the published page with a selected synthetic record while the permanent Console navigation remains unchanged |

For new controls, names such as `ddOperation`, `ddInterviewType`, `cmbLocation`, `txtReason`, `lblContextLoading`, `lblContextError`, and `lblContextEmpty` are suggestions only. If the owner chooses different names, use those actual names consistently and record them. The exact `Param("entityName")`, `Param("recordId")`, `GUID`, and `IfError` identifiers below are verified.

## 4. Sequential Power Apps Studio procedure

### Step 1 — Open the existing page and capture recovery

Open the existing page from `srapp` / `os_sr_bso_rs_support`; verify its unique name before editing. Record the published version and make the owner-approved recoverable backup described in section 1. Do not publish a backup by creating a replacement page. If the restore path is not proven, stop.

### Step 2 — Add only the required Dataverse data sources

In the existing page's **Data** pane, add these existing Dataverse tables:

1. Candidate (`os_sr_cand`)
2. Interview Schedule (`os_sr_intv`)
3. TA Directory (`os_sr_ta`)
4. Location (`os_sr_loc`)

For each, record the exact alias Studio displays and verify the logical table/field names against section 2. Do not add Availability Query (`os_sr_avq`) for this handoff; no Flow or availability backend is in scope.

### Step 3 — Initialize and validate every page entry

Select `Screen1` and put per-entry initialization on `Screen1.OnVisible`, not only `App.OnStart`. This is the prepared reset/parameter-validation block from the current handoff:

```powerfx
Set(varContextLoading, true);
Set(varContextError, Blank());
Set(varContextEntity, Param("entityName"));
Set(varContextIdRaw, Param("recordId"));
Set(varContextId, IfError(GUID(varContextIdRaw), Blank()));
Set(varContextReady, false);
Set(varCandidate, Blank());
Set(varSchedule, Blank());
Set(varAssignedTA, Blank());
Set(varLocation, Blank());
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

The reset clears the context-ready flag and Location record as well as the variables from the prepared snippet. After creating the new UI controls, also reset their selections at the start of each `OnVisible` run:

```powerfx
Reset(<<OPERATION_CONTROL>>);
Reset(<<INTERVIEW_TYPE_CONTROL>>);
Reset(<<LOCATION_SELECTOR_CONTROL>>);
Reset(<<REASON_CONTROL>>)
```

Replace the tokens with the actual control names from Studio. Add this after the validation block so malformed/missing context exits loading without reading Dataverse:

```powerfx
If(
    !IsBlank(varContextError),
    Set(varContextLoading, false)
)
```

For a valid entity/GUID, leave loading on while the reads and validations below run. In every success/error exit, set loading false. Set `varContextReady` true only after every required read and relationship/state check succeeds. Never treat a GUID or entity name as proof of authorization.

### Step 4 — Resolve records using Studio-confirmed aliases

The following are **not paste-ready**: replace every `<<...>>` token with the actual formula token selected from Studio autocomplete. The logical table/field behind each token must match section 2. Wrap each Dataverse read in `IfError`; use a fixed, sanitized unavailable/error message and never display raw connector errors.

Candidate-context lookup template:

```powerfx
IfError(
    Set(
        varCandidate,
        LookUp(
            <<CANDIDATE_DATA_SOURCE_ALIAS>>,
            <<CANDIDATE_PRIMARY_ID_EXPRESSION>> = varContextId
        )
    ),
    Set(varContextError, "Candidate is unavailable or not authorized.")
);
If(
    IsBlank(varCandidate) && IsBlank(varContextError),
    Set(varContextError, "Candidate is unavailable or not authorized.")
)
```

Schedule-context lookup template:

```powerfx
IfError(
    Set(
        varSchedule,
        LookUp(
            <<SCHEDULE_DATA_SOURCE_ALIAS>>,
            <<SCHEDULE_PRIMARY_ID_EXPRESSION>> = varContextId
        )
    ),
    Set(varContextError, "Schedule is unavailable or not authorized.")
);
If(
    IsBlank(varSchedule) && IsBlank(varContextError),
    Set(varContextError, "Schedule is unavailable or not authorized.")
)
```

Only after a Schedule is readable, active, and Round 1, resolve its Candidate through the verified `os_sr_intv_cand` relationship. Resolve Assigned TA through the loaded Candidate's `os_sr_cand_ta` relationship. For Schedule context, also resolve the Schedule's `os_sr_intv_ta` and require that it is the same active TA. Apply the same `IfError`/generic unavailable behavior to each relationship read.

Before setting `varContextReady`:

- Require an active Candidate and an active Assigned TA. Missing or inaccessible Assigned TA blocks context.
- For Candidate/Create context, require the Candidate state/status to be eligible for Create and no current active Round 1 Schedule that would make the context ambiguous or duplicate.
- For Schedule context, require the Schedule to be active, Round 1, eligible current status/result, and linked to the active Candidate just loaded. Compare the loaded Candidate ID to the Schedule's Candidate lookup ID using Studio-confirmed ID expressions.
- Require exactly one valid current Round 1 Schedule for Reschedule/Cancel. Reject stale, inactive, mismatched, or ambiguous state; do not pick the first match.
- Resolve Location only from a readable active Location row when Offline is selected. Never use an email textbox as the Location identity.

Dataverse reads run as the signed-in page user. If a read returns blank or errors, fail closed with a generic unavailable/not-authorized state; do not infer whether a row exists behind access controls. Validate with the intended interactive app identity, not merely the PAC identity.

### Step 5 — Bind context, loading, and error UI

Use the owner-confirmed new label names. These formulas are exact once the owner creates those controls:

```powerfx
<<LOADING_LABEL>>.Visible = varContextLoading
<<ERROR_LABEL>>.Visible = !varContextLoading && !IsBlank(varContextError)
<<ERROR_LABEL>>.Text = varContextError
<<EMPTY_LABEL>>.Visible = !varContextLoading && IsBlank(varContextError) && !varContextReady
<<CONTEXT_DETAILS_CONTAINER>>.Visible = varContextReady
```

Display Candidate Number, Candidate Name, Candidate Email, Assigned TA, and—when Schedule context is valid—Round 1 Schedule and current status. The field member expressions for the labels remain placeholders until Studio autocomplete confirms them. Do not display record details while loading or after an error.

### Step 6 — Prepare Online/Offline UI without executing availability

Keep the existing `ddScheduleMode` for Available slots / Custom time. Create a separate classic Dropdown named by the owner for Interview Type. If named `ddInterviewType`, this static `Items` formula is exact:

```powerfx
["Online", "Offline"]
```

Required UI behavior:

- **Online:** active Assigned TA is required by context validation; hide and clear the Location/Room selector; do not require or submit a Room.
- **Offline:** active Assigned TA remains required; show the Location selector and require a selected active, caller-readable Location before presenting the context as UI-ready.
- Keep the selector's data-source and active-state expressions as placeholders until the owner confirms the Studio alias and Choice syntax:

```powerfx
<<LOCATION_SELECTOR>>.Items =
    Filter(<<LOCATION_DATA_SOURCE_ALIAS>>, <<LOCATION_ACTIVE_PREDICATE>>)

<<LOCATION_SELECTOR>>.Visible =
    varContextReady && ddInterviewType.Selected.Value = "Offline"

<<LOCATION_SELECTOR>>.DisplayMode =
    If(
        varContextReady && ddInterviewType.Selected.Value = "Offline",
        DisplayMode.Edit,
        DisplayMode.Disabled
    )
```

The `<<...>>` formulas are not executable until replaced. Validate Room requiredness with an explicit visible validation message; do not rely on an unverified control `Required` property. The selector should display Location Name and retain the authorized Location row/ID, not a manually entered mailbox.

Remove or blank the hardcoded defaults from `txtTAEmail` and `txtRoomEmail`; do not leave editable mailbox inputs. Prefer replacing their display role with read-only labels bound to the authorized TA/Location records. If retained, confirm their Studio control types and disable or hide them.

The actual control names for all three existing `ATSuggAvailabilityBridge.Run(...)` call sites are unresolved. In Studio, locate each call, disable its trigger, and remove/detach the call formula for this phase. Keep the existing availability controls visible if useful, but all availability execution controls must remain `DisplayMode.Disabled`; do not display fabricated available slots or success. Create/Reschedule/Cancel choices are display-only, and any reason for Reschedule/Cancel is required in the UI but never submitted.

### Step 7 — Save draft, validate, and publish only behind gates

1. Save the existing page as a draft. Do not use Save As, import a stale solution, add a sitemap item, or edit the Console.
2. In Studio, confirm formula compilation and the loading, empty, error, TA, Online, Offline, Room, and required-reason UI states. Confirm all actions remain disabled and all `.Run(...)` call sites are detached.
3. Before publishing, verify the recoverable backup, owner rollback method, Studio aliases/fields, and a supported owner-approved way to launch the published page with a selected synthetic record. The current Console navigation must remain unchanged until page acceptance. If there is no supported test launch path that avoids manually entering record IDs, stop and report that acceptance is blocked; do not enable the permanent launcher just to bypass this gate.
4. Only after these prerequisites pass and the owner explicitly approves the page publication, publish the **existing page only** from Studio. Record the new published app version. Do not publish a solution or Flow as part of this procedure.
5. Run the acceptance matrix below against the published page as the intended interactive user. If any test fails, keep Console navigation, availability, and booking disabled; restore the captured page using the owner-verified recovery method and confirm the restored published version.

## 5. Synthetic acceptance matrix

Use only already-existing, owner-authorized synthetic rows. Select records through an approved UI/test route; do not type IDs manually, create fixtures, alter sharing, or change roles. If a needed synthetic record or authorized launch route does not exist, mark that case **BLOCKED** rather than manufacturing it.

| Case | Context/input | Expected result |
|---|---|---|
| Valid Candidate context | `entityName = "os_sr_cand"` and a selected, readable active synthetic Candidate in **Waiting Manual Scheduling**, with active Assigned TA and no current active Round 1 Schedule | Candidate Number/Name/Email and Assigned TA display; Create UI choice may appear; context is ready but all execution remains disabled |
| Valid Schedule context | `entityName = "os_sr_intv"` and a selected, readable active Round 1 Schedule with Scheduled (or documented legacy-unset) lifecycle and Pending result, linked to an active Candidate; Schedule TA matches the Candidate Assigned TA and is active | Candidate and Schedule/status display; Reschedule/Cancel UI choices and required reason field appear; no change is submitted |
| Invalid/missing `recordId` | Missing, malformed GUID; also test a valid-format ID that is not readable using an approved synthetic test case | Invalid input is rejected before reads. Unavailable/unreadable input shows a generic message, exposes no row details, and never treats the parameter as authorization |
| Unauthorized record | Run as the intended interactive app user against an existing synthetic row that user cannot read, if one is available under existing permissions | No data is shown; generic unavailable/not-authorized state; no role, sharing, or privilege changes. If no such row exists, mark this case blocked |
| Missing Assigned TA | Readable synthetic Candidate with no Assigned TA, if one already exists | Clear blocked/error state; no operation choice is actionable; no availability call |
| Online without Room | Valid context and active Assigned TA; choose Online with no Location selected | TA requirement remains satisfied; Room selector hidden and not required; no availability or provider request; action remains disabled |
| Offline requires Room | Valid context and active Assigned TA; choose Offline with no Location, then with an existing active readable Location | Without Location, show required validation and remain not ready for availability. With Location, show the selected Location in UI only; still no provider request or booking |

Also test wrong `entityName`, inactive Candidate/Schedule/TA/Location, mismatched Schedule-to-Candidate/TA, multiple current Round 1 Schedules, data-source read failure, reopening with a different context (no stale state), and loading/error recovery. All cases must show zero Candidate/Schedule writes, Flow invocations, availability/provider requests, and Outlook/Teams invitations. Do not infer access from metadata; perform the tests as the intended application user and record any access case that cannot be exercised without changing permissions as blocked.

## 6. Smallest safe Console navigation change — future release only

**Do not make or activate this change before the published Custom Page passes the acceptance matrix.** The current Candidate Console button `open-booking-context` calls `showBookingContext()` and opens the safe preview. Keep that behavior unchanged until acceptance.

After acceptance, the smallest safe change is a separately reviewed Console release that reuses the existing `showBookingContext()` candidate/schedule re-read and eligibility checks, then replaces the preview-launch action with one `Xrm.Navigation.navigateTo` call. Do not navigate directly from a stale list selection or bypass the current authorization/state checks.

Within the already-validated context in `showBookingContext()` (`canManage`, `active`, `candidate`, and the existing `c`/`i` table mappings), the supported one-record input is:

```javascript
const pageInput = {
  pageType: "custom",
  name: "os_atsugground1availability_4d2f7",
  entityName: canManage ? i.logicalName : c.logicalName,
  recordId: normalizeGuid(canManage ? active[0][i.id] : candidate[c.id])
};
const appXrm = xrm();
if (!appXrm.Navigation || typeof appXrm.Navigation.navigateTo !== "function") {
  throw new Error("CUSTOM_PAGE_NAVIGATION_UNAVAILABLE");
}
await appXrm.Navigation.navigateTo(pageInput, {
  target: 2,
  position: 1,
  width: { value: 80, unit: "%" }
});
```

For Create, this passes only the selected Candidate (`os_sr_cand`) ID. For Reschedule/Cancel, it passes only the exact active Schedule (`os_sr_intv`) ID; the page resolves and validates the related Candidate itself. Do not pass an operation, second ID, arbitrary `data`, email, or manually entered identifier. Preserve sanitized error handling around navigation. The current `xrm()` helper and `showBookingContext()` are in [`candidate-console.js`](../solutions/CandidateConsole/WebResources/os_/bso/candidate-console.js); the supported navigation contract is in [Microsoft's Custom Page navigation example](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/clientapi/navigate-to-custom-page-examples).

## 7. Owner-only Studio actions

These tasks require the page owner in Power Apps Studio: establish the backup/rollback method; open the existing page; add the four data sources; record Studio aliases and generated tokens; add/rename controls; edit `Screen1.OnVisible`; bind context/read/error/display formulas; remove hardcoded mailbox defaults; detach the three legacy bridge calls; keep execution disabled; validate draft formulas/UI; publish the existing page only after gates; and restore it if acceptance fails.

Copilot has not changed the page or Console and must not claim these actions are deployed. Phase 2.1 remains **PARTIAL/BLOCKED** until the existing published Custom Page passes authorized synthetic context acceptance. Only then may a separate owner-approved Console navigation release be considered.
