# P0 Slice 2A bounded DEV provisioning stop

**Date:** 2026-11-05. **Target:** owner-confirmed VN LMV IT, unmanaged `os_sr_bso_rs_support` 1.0.0.1.

**Classification:** `P0_SLICE_2A_RECONCILIATION_FAILED:MEMBERSHIP:10`.

This is a partial infrastructure result, **not** `P0_SLICE_2A_INFRASTRUCTURE_PROVISIONED`, deployment acceptance, or runtime acceptance. No repair, repeat write, rollback, or continuation was attempted after the stop. Any future attempt must stop on the now-existing partial components until the owner explicitly authorizes a reviewed continuation or migration plan.

## Authorization and preflight

The owner supplied these approved dispositions:

- `SLICE_2A_OUTLOOK_CONNECTOR_DEV_PATH_FEASIBLE`
- `SLICE_2A_DEV_IDENTITY_OPTION_A_APPROVED`
- `SLICE_2A_SYNTHETIC_MAILBOX_PREREQUISITE_MISSING`
- `SLICE_2A_CUSTOM_GRAPH_PATH_ABANDONED`

Only provider-independent infrastructure was authorized. Option A permits the existing DEV owner connection for later functional testing; no connection was created or used for Outlook in this operation. Synthetic mailbox prerequisites remain unresolved. The custom Graph path was not provisioned.

Fresh PAC and Dataverse identity checks agreed on the exact confirmed target. The unmanaged Solution, publisher prefix `os`, version, and accepted 51-membership fingerprint matched the [Slice 1 baseline](CURRENT_STATE.md#normal-srapp-candidate-console-entrypoint-accepted-without-tenant-writes-2026-11-05). The complete BSO map matched all 60 canonical entries; Reference Admin matched 20 entries and had zero user/team assignments. Candidate Core remained package-backed with package version 1.0.0, ModifiedOn `2026-11-05T05:54:24Z`, 21 inputs, five outputs, and one optional `ProfileFieldMask`. All 50 legacy guards were disabled.

The table, named relationships, availability role, and availability configuration definitions were absent before provisioning. Published Console resources had no availability panel or enabled availability flag.

## Acknowledged requests and stop

| Request | Result |
|---|---|
| Create `os_sr_avq` and its nonlookup fields | HTTP 204 |
| Create required TA lookup and `os_sr_ta_avq` | HTTP 204 |
| `AddSolutionComponent`, type 10, for the new TA relationship | HTTP 200 |

The next GET did not return the single explicit type-10 `solutioncomponent` row required by the execution guard. Provisioning stopped immediately with the classification above.

Subsequent **read-only** reconciliation found 52 Solution memberships: all original 51 retained, plus the `os_sr_avq` entity root with `rootcomponentbehavior=0` (include subcomponents). An actual unmanaged export and separate unpack include both `os_sr_avq` and `os_sr_ta_avq`. Thus the evidence establishes export coverage of the TA relationship, **not** that the relationship is absent from the Solution. The stop concerns the explicit-row membership assertion; its relationship to Dataverse subcomponent membership requires a separately reviewed correction. No validator change was used to resume provisioning.

**Provisioning write requests:** 3, all acknowledged. **Write retries:** 0. **Publication calls:** 0. Export/unpack was read-only source capture, not a provisioning retry. Its actual output and detailed GET/journal evidence are retained in the session workspace; the incomplete export was not adopted into canonical release source or frozen artifacts.

## Exact partial schema readback

The table display labels are **Availability Query / Availability Queries**, ownership is **UserOwned**, and auditing is **Off**. Primary ID is `os_sr_avqid`; primary name is `os_sr_avq_ref`.

| Field | Actual type and constraints | Requiredness |
|---|---|---|
| `os_sr_avq_ref` | String(100), primary name, AutoNumber `AVQ-{SEQNUM:8}` | ApplicationRequired |
| `os_sr_avq_ta` | Lookup to `os_sr_ta` | ApplicationRequired |
| `os_sr_avq_loc` | **Not created** | Not applicable |
| `os_sr_avq_mod` | Local Choice: Online=100000000, Onsite=100000001 | ApplicationRequired |
| `os_sr_avq_strt` | DateTime, DateAndTime, UserLocal | ApplicationRequired |
| `os_sr_avq_end` | DateTime, DateAndTime, UserLocal | ApplicationRequired |
| `os_sr_avq_dur` | Integer, min 15 / max 480 | ApplicationRequired |
| `os_sr_avq_stat` | Local Choice: Pending=100000000, Available=100000001, NoSlots=100000002, Failed=100000003 | ApplicationRequired |
| `os_sr_avq_rsn` | String(40) | None |
| `os_sr_avq_err` | String(40) | None |
| `os_sr_avq_slts` | Memo(32768) | None |
| `os_sr_avq_qat` | DateTime, DateAndTime, UserLocal | None |
| `os_sr_avq_exp` | DateTime, DateAndTime, UserLocal | None |

Dataverse-generated lookup display/Choice virtual fields are not additional payload-storage fields. No Candidate lookup, Interview Schedule lookup, mailbox-address field, or raw provider-response field was created.

`os_sr_ta_avq` references `os_sr_ta` through `os_sr_avq_ta`, with Delete **Restrict**; Assign, Share, Unshare, Reparent, Merge and RollupView are **NoCascade**. The server additionally reports Archive **RemoveLink**; no archive setting was requested or changed. `os_sr_loc_avq` is **not created**.

## Unexecuted role and configuration scope

- **BSO privilege delta: zero.** The complete resulting map remains the original 60 canonical entries. Even the approved Availability Query Create/Read/Append and TA/Location AppendTo additions were not reached.
- **Availability Integration role: not created and not assigned.** Its requested future definition remains Availability Query Read/Write and TA/Location Read at Organization depth, with no Candidate/Core execution, business writes, customization, security administration, or unproven platform-baseline grants.
- **Environment-variable definitions: none created.** The unexecuted definitions are `os_sr_avq_bhrs`, `os_sr_avq_durs`, `os_sr_avq_lead`, `os_sr_avq_hzn`, `os_sr_avq_exp`, and `os_sr_avq_dom`. No defaults, values, mailbox addresses, user IDs, credentials, client IDs, or secrets were written.
- Timezone `SE Asia Standard Time`, interval 15 minutes, and maximum horizon <=61 days remain the [offline configuration contract](../solutions/AvailabilityQuery/availability-environment-variables.json), not configured runtime values.

## Final preservation reconciliation

GET-only checks verified:

- BSO's complete 60-entry map unchanged; Reference Admin's complete 20-entry map unchanged and unassigned.
- Candidate Core package modification baseline/version, assembly linkage, API settings, every input/output definition and every legacy-guard registration unchanged; all 50 guards still disabled. Server package byte equality is not claimed.
- All original Solution memberships retained; only one entity-root membership added.
- All five published Console resource hashes unchanged. Availability remains effectively disabled: no availability panel/module was deployed and no enabled flag was introduced. No Console or app publication occurred.
- Zero `os_sr_avq` runtime rows.

| Business table | Before | After | Rows modified in reconciliation window |
|---|---:|---:|---:|
| Candidate | 47 | 47 | 0 |
| Call Log | 64 | 64 | 0 |
| Status History | 163 | 163 | 0 |
| Interview Schedule | 45 | 45 | 0 |
| Operation Receipt | 183 | 183 | 0 |

The bounded window was `2026-11-05T13:42:46Z` through `2026-11-05T13:46:37Z`. No concurrent business-row modification was observed in that window. Counts are aggregate checks, not a claim of runtime availability acceptance.

No Candidate operation, Outlook connection, connection reference, Cloud Flow, Find meeting times call, Availability Query guard deployment, TA/Location email change, query-row creation, Console panel publication, commit, or push occurred. No `PublishAllXml` or `pac solution publish` was used. Slice 1 remains accepted and independent; real-data and Production gates remain closed.
