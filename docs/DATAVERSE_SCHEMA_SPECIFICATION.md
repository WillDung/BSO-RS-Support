# Proposed Dataverse Schema Specification

**Status:** Wider Phase 1C design proposal, originally documented 19 October 2026, with current implementation reconciled through Phase 2D.4F on 23 October 2026. The verified reference-table set includes `os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, and `os_sr_loc`; approved columns and evidence are summarized in [Data Model](DATA_MODEL.md) and [Current State](CURRENT_STATE.md). Candidate, Call Log, Candidate Status History, their keys/relationships, and business operations remain unprovisioned proposals. Their owner decisions are recorded in [Phase 3A](PHASE_3A_CANDIDATE_CORE_DESIGN.md); readiness remains blocked by external audit and API privilege prerequisites, not product decisions.

## Evidence and Decision Labels

**Confirmed** means stated in the supplied requirements or governing docs. **Proposed** means an implementation choice for review. **Decision required** identifies a choice that must be resolved before implementation. No ATSugg database schema or data was available. [Migration Plan](MIGRATION_PLAN.md) and the Phase 0 blueprint provide conceptual source mappings only.

The design covers the 15 requested tables plus one supporting global Choice, `os_sr_candstat`, shared by Candidate and Status History. The existing abbreviation dictionary in [Data Model](DATA_MODEL.md) remains authoritative; the names below use its entity and field tokens. Final logical names use `os_sr_...`; in Maker fields that prepend `os_`, enter only the `sr_<abbreviation>` stem.

Microsoft constraints applied here:

- Custom table logical names require the publisher customization prefix and are lowercase. The selected `os` prefix is valid; Maker adds it automatically in some name inputs. See [Customize Table Definitions](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/customize-entity-metadata) and [Column Definitions](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/entity-attribute-metadata).
- Lookup columns create N:1 relationships. Dataverse lookup results expose the related row's primary name even when the caller cannot read that row; therefore primary names must not contain candidate names, email addresses, CV URLs, or other sensitive values. See [Column data types](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/types-of-fields).
- Alternate keys support text, whole number, decimal, date/time, lookup, and choice columns; each key has at most 16 columns and a 900-byte index limit; a table supports at most 10 keys. Field-secured columns cannot be alternate-key columns. Some characters in key values prevent Web API GET/PATCH by key. See [Work with alternate keys](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/define-alternate-keys-entity).
- For custom tables, ownership is `UserOwned` or `OrgOwned`. Relationship delete behavior supports Restrict, RemoveLink, or Cascade; this proposal uses Restrict for business references and no cascade assignment/sharing. See [Customize Table Definitions](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/customize-entity-metadata) and [Configure relationship cascading behavior](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/configure-entity-relationship-cascading-behavior).
- Text column maximums are 4,000 characters for Text/Text Area and 1,048,576 for Multiline Text. Date/time event fields use User Local (stored as UTC). Autonumber values can have gaps and seeds are environment-specific, not solution-imported. See [Column data types](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/types-of-fields) and [Autonumber columns](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/autonumber-fields).
- Auditing must be enabled at environment, table, and selected-column levels; audit retention remains an organizational decision. See [Manage Dataverse auditing](https://learn.microsoft.com/en-us/power-platform/admin/manage-dataverse-auditing).
- Microsoft documents AutoNumber as supported, but the currently available Dataverse MCP `create_table` tool schema does not offer AutoNumber as a column type. Phase 1D must use a supported Maker/metadata creation path for these primary names or approve a text primary-name alternative; do not silently change the schema.

### Requirement and Default Notation

| Marker | Meaning |
|---|---|
| R | Application-required on row creation; server operations must validate it because Application Required is not a Dataverse API integrity constraint. |
| C | Metadata optional; required by the named business operation/condition. |
| O | Optional. |
| SYS | Dataverse-managed; not supplied by the application. |
| None | No default. |

For Choice columns, option labels are specified below; numeric option values are assigned by Dataverse under the Publisher option-value prefix `10001` and must be recorded/frozen in the solution before release. Do not renumber values after deployment. The system `statecode/statuscode` (Active/Inactive) is separate from business workflow choices.

## Confirmed Business Invariants

- Candidate workflow values are Need Call Candidate, Candidate Answered, Waiting Manual Scheduling, Round 1 Scheduled, Offer Extended, and Candidate Failed. Every accepted status transition after initial row creation creates exactly one Candidate Status History row through the same approved server-side operation. No TA approval stage is part of the workflow.
- Owner-approved Phase 3A rules: Candidate Number is server-generated, immutable, unique, and nonpersonal; Candidate Name and Email are required, Phone optional; Dataverse Owner is the responsible BSO, without a duplicate Assigned BSO field; the initial call outcomes are Answered, No Answer, and Call Back Requested; all state-changing Candidate operations require caller-generated GUID CorrelationId idempotency; Candidate/Call/History table auditing is required; no column-level security is applied to Candidate Name/Email/Phone in the initial slice.
- Answered from Need Call Candidate atomically creates a Call Log, transitions to Candidate Answered, and creates History. No Answer and Call Back Requested create only a Call Log. Reschedule requires reason and records actor, timestamp, correlation, previous/new status, and reason; actual calendar cancellation attempt/evidence is deferred to the scheduling phase.
- Candidate core includes Position and does not include a LEGO Career lookup. The later scheduling/booking boundary enforces the linked-career prerequisite.
- BSO coordinates; TA is an interviewer/directory contact, not automatically an app user or approver. Online booking requires verified TA availability. Offline booking requires verified TA and room availability. Unknown, failed, stale, or conflicting availability is not free.
- Booking is blocked without a valid Candidate CV URL and a valid linked LEGO Career. Only Vietnam postings are visible for this workflow; exactly one title match may auto-select, while zero/multiple require manual resolution.
- Email dispatch preserves intended sender, logical To/CC, subject/body snapshot, and outcome. Idempotency is required; Sent, Failed, and Indeterminate are distinct. Never blindly retry an uncertain send or equate Flow invocation success with delivery.
- These are confirmed business constraints, not proof of implementation. Choice option IDs, operation contracts, provider evidence, and detailed field requirements remain proposed or open as noted below.

## Shared Platform Columns

All tables have a system-generated GUID primary ID and system columns `createdon`, `createdby`, `modifiedon`, `modifiedby`, `statecode`, `statuscode`, and `versionnumber`. User-owned tables also have Dataverse-managed `ownerid` and owning-business-unit fields. Do not create custom duplicates of these columns. Expected primary ID logical names below follow Dataverse's generated `<table logical name>id` form; confirm them in table metadata at build time. `ownerid` is the BSO/team access boundary, not the TA lookup.

## Table Inventory

The primary-name column is shown explicitly. Autonumber primary names are nonpersonal references; gaps are expected. The candidate table uses Candidate Number, not candidate name, as its primary name to reduce PII leakage through lookup controls.

| Table | Purpose / status | Logical name / display name | Ownership | Primary name column | Primary GUID | Usage, dependencies, and migration source |
|---|---|---|---|---|---|---|
| TA Directory | Interviewer directory; need confirmed, exact source fields pending | `os_sr_ta` / TA Directory | OrgOwned | `os_sr_ta_nm` / TA Name (Text) | `os_sr_taid` | Referenced by Candidate and Interview Round. Map ATSugg TA/interviewer directory; actual identity key unavailable. |
| Position | Internal position reference; proposed | `os_sr_pos` / Position | OrgOwned | `os_sr_pos_ttl` / Position Title (Text) | `os_sr_posid` | Referenced by Candidate and LEGO Career. Map ATSugg jobs/positions; duplicate-title behavior pending. |
| Candidate Source | Candidate source reference; proposed | `os_sr_csrc` / Candidate Source | OrgOwned | `os_sr_csrc_nm` / Source Name (Text) | `os_sr_csrcid` | Referenced by Candidate. Map ATSugg source values; normalization and retention pending. |
| Location | Room/resource directory; proposed | `os_sr_loc` / Location | OrgOwned | `os_sr_loc_nm` / Location Name (Text) | `os_sr_locid` | Referenced by Interview Round and Visitor Registration. Map ATSugg locations; room mailbox identity requires verification. |
| App Configuration | Approved nonsecret configuration only; proposed and possibly replaceable by environment variables | `os_sr_acfg` / App Configuration | OrgOwned | `os_sr_acfg_key` / Configuration Key (Text) | `os_sr_acfgid` | No business relationship. No ATSugg mapping identified. Never store credentials, secrets, or environment-specific endpoints as ordinary rows. |
| Candidate | Recruitment workflow record; fields confirmed at business level, schema proposed | `os_sr_cand` / Candidate | UserOwned | `os_sr_cand_cnum` / Candidate Number (Text) | `os_sr_candid` | References Position, Candidate Source, TA, and LEGO Career; parent of calls, history, rounds, dispatches, visits. Map ATSugg candidate/person; exact source columns/keys unavailable. |
| Call Log | Append-only outreach evidence; need confirmed, outcomes pending | `os_sr_call` / Call Log | UserOwned | `os_sr_call_ref` / Call Reference (Autonumber Text) | `os_sr_callid` | N:1 Candidate. Map ATSugg calls/contact events; actor, timestamp/time zone, outcomes and notes require source inventory. |
| Candidate Status History | One row per accepted transition; transition history confirmed | `os_sr_csh` / Candidate Status History | UserOwned | `os_sr_csh_ref` / Transition Reference (Autonumber Text) | `os_sr_cshid` | N:1 Candidate. Map ATSugg status changes only where historical evidence exists; never fabricate actors/timestamps. |
| Interview Round | Interview attempt and external calendar state; proposed | `os_sr_irnd` / Interview Round | UserOwned | `os_sr_irnd_ref` / Interview Reference (Autonumber Text) | `os_sr_irndid` | N:1 Candidate, TA, optional Location. Map ATSugg interviews/rounds/events; provider IDs and actual external state need source inventory. |
| Interview Result | Pass/Fail outcome and feedback; outcome confirmed, fields pending | `os_sr_ires` / Interview Result | UserOwned | `os_sr_ires_ref` / Result Reference (Autonumber Text) | `os_sr_iresid` | Proposed 0..1 per Interview Round. Map ATSugg outcomes/feedback; result versioning and salary semantics pending. |
| Email Template | Approved reusable templates; requirement confirmed, version model proposed | `os_sr_etpl` / Email Template | OrgOwned | `os_sr_etpl_code` / Template Code (Text) | `os_sr_etplid` | Parent of Email Dispatch. Map ATSugg templates if present; exact versions/variables/locales unavailable. |
| Email Dispatch | Immutable-enough dispatch snapshot and outcome; requirements confirmed | `os_sr_edsp` / Email Dispatch | UserOwned | `os_sr_edsp_ref` / Dispatch Reference (Autonumber Text) | `os_sr_edspid` | N:1 Candidate and Email Template. Map ATSugg send history only when sender, recipients, content, and outcomes have evidence. |
| Visitor Registration | Onsite visit record; module proposed, business lifecycle pending | `os_sr_vreg` / Visitor Registration | UserOwned | `os_sr_vreg_ref` / Visit Reference (Autonumber Text) | `os_sr_vregid` | N:1 Candidate, Interview Round, Location. Map ATSugg visitor records if present; requirements/retention pending. |
| LEGO Career | Vietnam-scoped external posting reference; product constraints confirmed, API contract pending | `os_sr_lgcar` / LEGO Career | OrgOwned | `os_sr_lgcar_ttl` / Career Title (Text) | `os_sr_lgcarid` | Optional Position lookup; parent of Candidate. Source is the official careers proxy, not an assumed ATSugg table. |
| Integration Run | Sanitized operational execution record; proposed | `os_sr_irun` / Integration Run | OrgOwned | `os_sr_irun_ref` / Run Reference (Autonumber Text) | `os_sr_irunid` | Correlates operations by ID; no business relationship. No ATSugg mapping proposed; retain legacy run history only if source evidence and need are approved. |

## Column Inventories

These are proposed custom columns in addition to Shared Platform Columns and each table's primary GUID. `Lookup` targets are included. `User Local` Date/Time stores UTC and renders for the user. Dynamic requirements are enforced by the approved server operation, not only by forms.

### `os_sr_ta` — TA Directory

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_ta_nm` | TA Name | Text, 200 | R | None | Nonblank directory display name. Primary name is visible through lookups. |
| `os_sr_ta_eml` | TA Email | Text with Email format, 254 | R | None | Valid email; normalize for duplicate checking. No alternate key until directory identity/plus-address behavior is validated. Treat as contact data. |

Use `statecode` for active/inactive; do not add a duplicate active Boolean. Deactivate rather than delete referenced TAs.

### `os_sr_pos` — Position

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_pos_ttl` | Position Title | Text, 200 | R | None | Nonblank. Duplicate-title/position-code policy is open; do not make title unique by assumption. |

Use `statecode` for active/inactive.

### `os_sr_csrc` — Candidate Source

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_csrc_nm` | Source Name | Text, 100 | R | None | Nonblank. Normalize historical aliases only under an approved mapping. |

Use `statecode` for active/inactive. Source uniqueness and historical-value retention remain open.

### `os_sr_loc` — Location

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_loc_nm` | Location Name | Text, 150 | R | None | Nonblank; no personal data. |
| `os_sr_loc_rmeml` | Room/Resource Email | Text with Email format, 254 | C | None | Required before an offline booking uses this location; validate resource mailbox mapping. |
| `os_sr_loc_det` | Location Details | Multiline Text, 1,000 | O | None | Operational details only; exclude access codes or secrets. |

Use `statecode` for active/inactive. No alternate key until stable room/resource identity is confirmed.

### `os_sr_acfg` — App Configuration

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_acfg_key` | Configuration Key | Text, 100 | R | None | Lowercase stable nonsecret key; primary name and proposed alternate key. |
| `os_sr_acfg_val` | Configuration Value | Text, 4,000 | R | None | Nonsecret approved value only; use environment variables/secret storage for environment-specific or sensitive settings. |
| `os_sr_acfg_dsc` | Description | Multiline Text, 1,000 | O | None | Explain purpose without recording secrets or tenant URLs. |

Use `statecode` for active/inactive. Confirm this table is needed rather than using solution environment variables exclusively.

### `os_sr_cand` — Candidate

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_cand_cnum` | Candidate Number | AutoNumber Text, proposed `CAND-{SEQNUM:8}` | R | Platform | Dataverse-generated, immutable after creation, unique and nonpersonal; proposed primary name and unique alternate key. Validate the format/path before provisioning. |
| `os_sr_cand_nm` | Candidate Name | Text, 200 | R | None | Personal data; required at creation. No column-level security in initial slice; protect by table/row access and auditing. Not the primary name. |
| `os_sr_cand_eml` | Candidate Email | Text with Email format, 254 | R | None | Required at creation; personal data; no column-level security in initial slice; not an alternate key. |
| `os_sr_cand_phn` | Candidate Phone | Text with Phone format, 50 | O | None | Optional at creation; personal data; no column-level security in initial slice. |
| `os_sr_cand_corid` | Creation Correlation ID | GUID text, 36 | R for operation create | None | Unique alternate key to prevent duplicate Candidate creates for one logical operation. |
| `os_sr_cand_pos` | Position | Lookup → `os_sr_pos` | O | None | Optional internal position reference; title duplicates remain possible. |
| `os_sr_cand_csrc` | Candidate Source | Lookup → `os_sr_csrc` | O | None | Optional; retain historical source meaning. |
| `os_sr_cand_ta` | Assigned TA | Lookup → `os_sr_ta` | C | None | Required before booking; TA remains a directory/interviewer, not an app role. |
| `os_sr_cand_cvurl` | Candidate CV URL | URL, 2,000 | C | None | Later booking prerequisite; HTTPS/host/access validation and restricted read. A URL is sensitive. |
| `os_sr_cand_stat` | Candidate Workflow Status | Global Choice `os_sr_candstat` | R | Need Call Candidate | Exact confirmed labels: Need Call Candidate, Candidate Answered, Waiting Manual Scheduling, Round 1 Scheduled, Offer Extended, Candidate Failed. Numeric values assigned once and frozen. Business rules enforced server-side and recorded in Candidate Status History. |

The table is `UserOwned`; Dataverse `ownerid` is the responsible BSO, assigned from the authenticated initiating BSO at creation. Do not add a duplicate Assigned BSO lookup. Initial status on create is not a transition; every later status change must atomically create one history row. Position is included in Candidate core; Candidate-to-LEGO-Career lookup is deferred.

### `os_sr_call` — Call Log

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_call_ref` | Call Reference | Autonumber Text, `CALL-{SEQNUM:8}` | SYS | Platform | Nonpersonal display reference; gaps are expected. |
| `os_sr_call_cand` | Candidate | Lookup → `os_sr_cand` | R | None | Parent candidate; delete restricted. |
| `os_sr_call_out` | Call Outcome | Global Choice `os_sr_callout` | R | None | Owner-approved values: Answered, No Answer, Call Back Requested. |
| `os_sr_call_ctat` | Contacted At | Date/Time, User Local | R | None | Store event time; do not substitute import time. |
| `os_sr_call_ctby` | Contacted By | Lookup → systemuser | R | None | Initiating BSO/business actor, not TA or fixed Flow owner; server operation must resolve authenticated actor. |
| `os_sr_call_nts` | Notes | Multiline Text, 4,000 | O | None | Minimize PII; restrict read/write. |
| `os_sr_call_corid` | Correlation ID | GUID text, 36 | R for operation writes | None | Caller-generated per logical operation; alternate key with Candidate lookup prevents duplicate Call Logs. |

UserOwned; append-only through an approved operation. Migration source: ATSugg calls/contact events; exact outcome values and column mapping unavailable.

### `os_sr_csh` — Candidate Status History

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_csh_ref` | Transition Reference | Autonumber Text, `HIST-{SEQNUM:8}` | SYS | Platform | Nonpersonal reference. |
| `os_sr_csh_cand` | Candidate | Lookup → `os_sr_cand` | R | None | Parent candidate; delete restricted. |
| `os_sr_csh_prevstat` | Previous Status | Global Choice `os_sr_candstat` | R | None | Required for a transition row. |
| `os_sr_csh_newstat` | New Status | Global Choice `os_sr_candstat` | R | None | Must differ from previous status and be allowed by the transition matrix. |
| `os_sr_csh_actr` | Actor | Lookup → systemuser | R | None | Initiating BSO/business actor, not a fixed Flow/service owner; legacy unresolved actors need a documented migration exception/crosswalk. |
| `os_sr_csh_chg` | Changed At | Date/Time, User Local | R | None | Business transition timestamp. |
| `os_sr_csh_rsn` | Reason | Multiline Text, 1,000 | C | None | Mandatory for reschedule. |
| `os_sr_csh_corid` | Correlation ID | GUID text, 36 | R for operation transitions | None | Caller-generated per logical operation; alternate key with Candidate lookup prevents duplicate History. |

UserOwned, append-only. A synchronous approved Dataverse operation must update Candidate status and create this row atomically; application/Flow-only validation is insufficient. Dataverse auditing is owner-approved for Candidate, Call Log, and Candidate Status History and supplements this table. Environment audit enablement and governance remain external prerequisites.

### `os_sr_irnd` — Interview Round

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_irnd_ref` | Interview Reference | Autonumber Text, `INT-{SEQNUM:8}` | SYS | Platform | Nonpersonal reference. |
| `os_sr_irnd_cand` | Candidate | Lookup → `os_sr_cand` | R | None | Parent candidate; delete restricted. |
| `os_sr_irnd_ta` | TA | Lookup → `os_sr_ta` | C | None | Required before booking; TA must be active and availability verified. |
| `os_sr_irnd_loc` | Location | Lookup → `os_sr_loc` | C | None | Required for Offline mode and verified room availability; not required online. |
| `os_sr_irnd_mod` | Interview Mode | Choice: Online, Offline | C | None | Required before booking. |
| `os_sr_irnd_strt` | Start At | Date/Time, User Local | C | None | Required before booking; start < end. |
| `os_sr_irnd_end` | End At | Date/Time, User Local | C | None | Required before booking; time-zone semantics and duration limits need approval. |
| `os_sr_irnd_orgeml` | Intended Organizer Email | Text with Email format, 254 | C | None | Required before booking; intended Microsoft 365 identity must be verified. |
| `os_sr_irnd_evt` | Provider Event ID | Text, 200 | O | None | Set only on confirmed provider result; not personal data. |
| `os_sr_irnd_stat` | Booking Status | Choice | R | Pending (proposed) | Proposed lifecycle labels: Pending, Booking, Scheduled, Cancel Pending, Cancelled, Failed, Indeterminate. Confirm before implementation. |
| `os_sr_irnd_idem` | Booking Idempotency Key | Text, 100 | C | None | Required before external booking; URL-safe opaque token; alternate key. |
| `os_sr_irnd_corid` | Correlation ID | Text, 100 | O | None | Links Dataverse operation, Flow, and provider where supported. |

UserOwned under the Candidate owner. BSO coordinates; Candidate and TA are required attendees; room resource is additionally required offline. Unknown, failed, stale, or conflicting availability blocks booking. External event create/cancel is not transactional with Dataverse.

### `os_sr_ires` — Interview Result

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_ires_ref` | Result Reference | Autonumber Text, `RES-{SEQNUM:8}` | SYS | Platform | Nonpersonal reference. |
| `os_sr_ires_irnd` | Interview Round | Lookup → `os_sr_irnd` | R | None | Proposed unique alternate key for one result per round; depends on approved versioning decision. |
| `os_sr_ires_out` | Result | Choice: Pass, Fail | R | None | Confirmed outcomes; validated against current Candidate status by server operation. |
| `os_sr_ires_fb` | Interview Feedback | Multiline Text, 4,000 | O | None | Sensitive; restricted role and field-level security. |
| `os_sr_ires_sal` | Salary | Currency | O | None | Sensitive; field-level security. Currency/precision, meaning, and retention are open. |
| `os_sr_ires_recby` | Recorded By | Lookup → systemuser | R | None | Actual Dataverse actor. |
| `os_sr_ires_recat` | Recorded At | Date/Time, User Local | R | None | Record time for the business result. |

UserOwned under Candidate owner. Migration source: ATSugg interview outcomes/feedback when supported by evidence. One-result-per-round versus revisions is a decision; do not create the unique key until approved.

### `os_sr_etpl` — Email Template

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_etpl_code` | Template Code | Text, 100 | R | None | Nonpersonal stable code; primary name. |
| `os_sr_etpl_ver` | Template Version | Text, 50 | R | None | Immutable version identifier; format/version approval pending. |
| `os_sr_etpl_subj` | Subject Template | Text, 500 | R | None | Variables must be allowlisted; no candidate data in template defaults. |
| `os_sr_etpl_body` | Body Template | Multiline Text, 1,048,576 | R | None | Approved template content; versioned, restricted authoring. |
| `os_sr_etpl_tosn` | Default To Snapshot | Multiline Text, 4,000 | O | None | Proposed JSON array of logical recipient specifications; no secrets or real candidate addresses. |
| `os_sr_etpl_ccsn` | Default CC Snapshot | Multiline Text, 4,000 | O | None | Same serialization rule as To; validate before rendering. |

OrgOwned, admin-maintained, BSO read-only. Use `statecode` to retire a version; do not overwrite a version referenced by dispatch records. Migration source: ATSugg templates if present; contents/version history unavailable.

### `os_sr_edsp` — Email Dispatch

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_edsp_ref` | Dispatch Reference | Autonumber Text, `EML-{SEQNUM:8}` | SYS | Platform | Nonpersonal reference. |
| `os_sr_edsp_cand` | Candidate | Lookup → `os_sr_cand` | R | None | Parent candidate; delete restricted. |
| `os_sr_edsp_etpl` | Email Template | Lookup → `os_sr_etpl` | R | None | Approved template used for the dispatch. |
| `os_sr_edsp_tplver` | Template Version Snapshot | Text, 50 | R | None | Must match the referenced template version at render time. |
| `os_sr_edsp_idem` | Idempotency Key | Text, 100 | R | None | Unique, URL-safe opaque token; alternate key; never blindly retry unknown outcome. |
| `os_sr_edsp_sndr` | Intended Sender | Text with Email format, 254 | R | None | Intended sender identity; sensitive operational metadata. |
| `os_sr_edsp_sndas` | Observed Sender | Text with Email format, 254 | O | None | Populate only from provider evidence; must not claim a verified From without evidence. |
| `os_sr_edsp_tosn` | To Snapshot | Multiline Text, 100,000 | R | None | Immutable JSON array preserving logical recipients; PII, field-secured. |
| `os_sr_edsp_ccsn` | CC Snapshot | Multiline Text, 100,000 | O | None | Immutable JSON array; PII, field-secured. |
| `os_sr_edsp_subj` | Subject Snapshot | Text, 500 | R | None | Immutable rendered subject; sensitive, field-secured. |
| `os_sr_edsp_body` | Body Snapshot | Multiline Text, 1,048,576 | R | None | Immutable rendered content; highly sensitive, field-secured and retention-limited by policy. |
| `os_sr_edsp_stat` | Dispatch Status | Choice: Queued, Sending, Sent, Failed, Indeterminate | R | Queued | Confirmed status semantics; only trusted operation updates status. |
| `os_sr_edsp_prvid` | Provider Correlation | Text, 200 | O | None | Provider message/correlation identifier when returned. |
| `os_sr_edsp_corid` | Operation Correlation ID | Text, 100 | O | None | Correlate Dataverse, Flow, provider. |
| `os_sr_edsp_sentat` | Sent At | Date/Time, User Local | O | None | Set only with provider evidence for Sent. |
| `os_sr_edsp_tryat` | Last Attempt At | Date/Time, User Local | O | None | Last known send attempt, not proof of delivery. |
| `os_sr_edsp_err` | Sanitized Error | Multiline Text, 2,000 | O | None | No tokens, credentials, full payloads, or unnecessary PII. |
| `os_sr_edsp_reqby` | Requested By | Lookup → systemuser | R | None | Dataverse actor; distinct from connector sender identity. |

UserOwned under Candidate owner. Snapshot columns are immutable after dispatch creation; status/attempt fields change only through approved server-side operations. Migration source: ATSugg send history only when sender/recipients/content/outcome evidence exists.

### `os_sr_vreg` — Visitor Registration

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_vreg_ref` | Visit Reference | Autonumber Text, `VIS-{SEQNUM:8}` | SYS | Platform | Nonpersonal reference. |
| `os_sr_vreg_cand` | Candidate | Lookup → `os_sr_cand` | R | None | Sensitive parent; delete restricted. |
| `os_sr_vreg_irnd` | Interview Round | Lookup → `os_sr_irnd` | R | None | Must belong to the same Candidate. |
| `os_sr_vreg_loc` | Location | Lookup → `os_sr_loc` | R | None | Must be active and appropriate for the visit. |
| `os_sr_vreg_visat` | Visit At | Date/Time, User Local | R | None | Time-zone and visit timing rules pending. |
| `os_sr_vreg_stat` | Visit Status | Choice | R | Planned (proposed) | Proposed labels: Planned, Arrived, Completed, Cancelled. Business owner must approve before implementation. |

UserOwned under Candidate owner. Restrict access and determine retention/notifications before use. Migration source: ATSugg visitor records if present; actual rules pending.

### `os_sr_lgcar` — LEGO Career

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_lgcar_ttl` | Career Title | Text, 200 | R | None | External title; primary name. |
| `os_sr_lgcar_extid` | External Career ID | Text, 100 | R | None | Stable proxy ID; proposed alternate key. Validate key-safe characters; preserve original ID and use a safe lookup strategy if API key characters are incompatible. |
| `os_sr_lgcar_pos` | Position | Lookup → `os_sr_pos` | O | None | Optional mapped internal position; title match is not a stable identity. |
| `os_sr_lgcar_loc` | External Location | Text, 250 | O | None | Source location text; interpretation pending API owner. |
| `os_sr_lgcar_ctry` | Country Code | Text, 2 | R | None | Sync only Vietnam records (`VN`) for this workflow; reject/segregate other country values rather than rewrite them. |
| `os_sr_lgcar_url` | Career URL | URL, 2,000 | R | None | Validate HTTPS and approved source/host; no API endpoint assumed. |
| `os_sr_lgcar_lsync` | Last Successful Sync At | Date/Time, User Local | O | None | Update only after successful authoritative sync. |

OrgOwned; integration writer, BSO read. Use `statecode` to deactivate only after complete authoritative sync; never deactivate on partial/error response. No ATSugg source mapping assumed.

### `os_sr_irun` — Integration Run

| Logical name | Display name | Dataverse type / limit | Req. | Default | Validation / classification |
|---|---|---|---|---|---|
| `os_sr_irun_ref` | Run Reference | Autonumber Text, `RUN-{SEQNUM:8}` | SYS | Platform | Nonpersonal reference. |
| `os_sr_irun_knd` | Run Kind | Text, 100 | R | None | Proposed values include LEGO sync, email dispatch, interview booking/cancellation; approve taxonomy. |
| `os_sr_irun_corid` | Correlation ID | Text, 100 | R | None | Nonsecret correlation token; not assumed unique across attempts. |
| `os_sr_irun_stat` | Run Status | Choice | R | Running (proposed) | Proposed labels: Queued, Running, Succeeded, Failed, Indeterminate; confirm before implementation. |
| `os_sr_irun_stgat` | Started At | Date/Time, User Local | R | None | Operational start time. |
| `os_sr_irun_cmpat` | Completed At | Date/Time, User Local | O | None | Set when run ends. |
| `os_sr_irun_rowcnt` | Records Processed | Whole Number, minimum 0 | O | None | Count only; no payload. |
| `os_sr_irun_err` | Sanitized Error | Multiline Text, 2,000 | O | None | Restricted operational diagnostics; no secrets, candidate payloads, or full provider responses. |

OrgOwned; read/write restricted to integration administrators/service operation. No payload column. No ATSugg mapping proposed.

## Alternate Keys

Key schema names below are proposed final names. No key column may have field-level security; enforce access at table/row level for key values. Every key is subject to Dataverse's 900-byte/16-column limits and online index-creation status. Candidate Number and external IDs require character validation before relying on Web API alternate-key GET/PATCH. Key values containing `/`, `<`, `>`, `*`, `%`, `&`, `:`, `\\`, `?`, or `+` can make those operations fail.

| Table | Proposed key name | Columns | Decision / feasibility |
|---|---|---|---|
| Candidate | `os_sr_cand_ak_cnum` | `os_sr_cand_cnum` | Owner-approved unique, nonpersonal, Dataverse-generated Candidate Number; proposed format must be validated against supported AutoNumber metadata behavior. |
| Candidate | `os_sr_cand_ak_corid` | `os_sr_cand_corid` | Proposed unique creation CorrelationId key to prevent duplicate Candidate creates. |
| Call Log | `os_sr_call_ak_cand_action` | `os_sr_call_cand`, `os_sr_call_corid` | Proposed per-Candidate GUID CorrelationId idempotency key. |
| Candidate Status History | `os_sr_csh_ak_cand_action` | `os_sr_csh_cand`, `os_sr_csh_corid` | Proposed per-Candidate GUID CorrelationId key to prevent duplicate History rows. |
| Interview Round | `os_sr_irnd_ak_idem` | `os_sr_irnd_idem` | Required before non-idempotent provider booking; key token generated URL-safe. |
| Interview Result | `os_sr_ires_ak_irnd` | `os_sr_ires_irnd` | Conditional: only if one result per round is approved; remove/defer for versioned results. |
| Email Template | `os_sr_etpl_ak_codever` | `os_sr_etpl_code`, `os_sr_etpl_ver` | Proposed; supports immutable versions. |
| Email Dispatch | `os_sr_edsp_ak_idem` | `os_sr_edsp_idem` | Confirmed need for unique idempotency; use URL-safe opaque tokens. |
| LEGO Career | `os_sr_lgcar_ak_extid` | `os_sr_lgcar_extid` | Confirmed stable external key; validate proxy ID characters and length. |
| App Configuration | `os_sr_acfg_ak_key` | `os_sr_acfg_key` | Proposed; use safe stable ASCII key values. |
| TA, Position, Candidate Source, Location, Visitor Registration, Integration Run | None initially | None | Stable external IDs/duplicate policies are unknown. Do not make names or emails unique without approval. |

## Relationships and Delete Behavior

All relationships are proposed One-to-Many (lookup on the child) except the conditional one-result-per-round constraint. Hard deletes are restricted; deactivate reference rows and use approved retention/deletion processes. Set Delete=`Restrict`, Assign/Share/Unshare/Reparent=`No Cascade` unless a reviewed test proves another behavior is needed. Sharing/ownership is not assumed to flow from a parent lookup.

| Proposed relationship schema name | Parent → child | Lookup column | Cardinality / requiredness | Delete and integrity rule |
|---|---|---|---|---|
| `os_sr_cand_call` | Candidate → Call Log | `os_sr_call_cand` | 1:N, required | Restrict; child retains candidate history. |
| `os_sr_cand_csh` | Candidate → Status History | `os_sr_csh_cand` | 1:N, required | Restrict; never cascade-delete transition evidence. |
| `os_sr_cand_irnd` | Candidate → Interview Round | `os_sr_irnd_cand` | 1:N, required | Restrict; server operation checks candidate prerequisites. |
| `os_sr_ta_irnd` | TA → Interview Round | `os_sr_irnd_ta` | 1:N, conditional | Restrict; inactive TA cannot be booked, remains for history. |
| `os_sr_loc_irnd` | Location → Interview Round | `os_sr_irnd_loc` | 1:N, conditional offline | Restrict; room/resource validation required offline. |
| `os_sr_pos_cand` | Position → Candidate | `os_sr_cand_pos` | 1:N, optional | Restrict; deactivate rather than delete. |
| `os_sr_csrc_cand` | Candidate Source → Candidate | `os_sr_cand_csrc` | 1:N, optional | Restrict; retain historical source rows. |
| `os_sr_lgcar_cand` | LEGO Career → Candidate (future booking boundary only) | Candidate lookup deferred from Phase 3A | Future-phase only | Not part of Candidate Core; validate linked career at the later scheduling/booking boundary. |
| `os_sr_cand_edsp` | Candidate → Email Dispatch | `os_sr_edsp_cand` | 1:N, required | Restrict; preserve dispatch evidence. |
| `os_sr_etpl_edsp` | Email Template → Email Dispatch | `os_sr_edsp_etpl` | 1:N, required | Restrict; old template versions remain referenced. |
| `os_sr_irnd_ires` | Interview Round → Interview Result | `os_sr_ires_irnd` | 1:0..1 proposed | Restrict; enforce by alternate key only if one-result policy approved. |
| `os_sr_cand_vreg` | Candidate → Visitor Registration | `os_sr_vreg_cand` | 1:N, required | Restrict; sensitive history retained under policy. |
| `os_sr_irnd_vreg` | Interview Round → Visitor Registration | `os_sr_vreg_irnd` | 1:N, required | Restrict; validate same Candidate across both lookups. |
| `os_sr_loc_vreg` | Location → Visitor Registration | `os_sr_vreg_loc` | 1:N, required | Restrict; keep visit history when location is inactive. |
| `os_sr_pos_lgcar` | Position → LEGO Career | `os_sr_lgcar_pos` | 1:N, optional | Restrict; external titles may not map to internal positions. |

App Configuration and Integration Run have no business lookups in this proposal; use correlation identifiers rather than storing raw payloads or inventing polymorphic references.

## Ownership, Audit, and Security

| Table group | Ownership and access proposal | Audit proposal |
|---|---|---|
| TA, Position, Candidate Source, Location, App Configuration, Email Template, LEGO Career | OrgOwned. BSO read only where needed; restricted admin/integration write. TA email remains directory PII. | Enable table audit; audit active state and business fields. App Configuration changes require admin audit; never store secrets. |
| Candidate, Call Log, Candidate Status History, Interview Round, Interview Result, Email Dispatch, Visitor Registration | UserOwned. Candidate Dataverse Owner is the responsible BSO; child owner assigned by approved server operation. Use explicit sharing only; do not infer access from lookups. | Candidate/Call/History table auditing is owner-approved; audit scope for later-domain tables remains proposed. |
| Integration Run | OrgOwned, restricted to operational administrators/integration role; errors sanitized and no payload column. | Audit run status and sanitized diagnostics; retention/monitoring policy required. |

Sensitive columns: `cand_nm`, `cand_eml`, `cand_phn`, `cand_cvurl`; `ires_fb`, `ires_sal`; `edsp_sndr`, `edsp_sndas`, `edsp_tosn`, `edsp_ccsn`, `edsp_subj`, `edsp_body`; and `irun_err`. Owner decision: do not apply column-level security to Candidate Name/Email/Phone in the initial slice; least-privilege table/row permissions still apply. Review other sensitive columns for later domains under their own policy. Candidate Number and all alternate-key columns cannot be field-secured; limit their disclosure through table/row access. The primary name is exposed through lookup results, so Candidate Number is deliberately the non-name primary value. No roles, sharing, audit settings, DLP policy, or connector permissions are asserted configured.

The Candidate, Call Log, and Status History operations must not trust client-side or Flow-only enforcement. A reviewed synchronous Dataverse business operation must validate transitions, update Candidate, and create the Status History row atomically. Call/transition/booking/dispatch keys must be checked before external effects. Email snapshot columns are immutable after queueing; only trusted operations may update status/result fields. `Indeterminate` is persisted, reconciled, and never blindly retried.

Dataverse audit is supplemental to purpose-built status/dispatch history, not a replacement. Audit-history display can truncate large attribute values; the immutable Email Dispatch body snapshot is the authoritative full content, not the audit log rendering. Organization-level audit enablement, retention duration, audit visibility, deletion/DSR procedures, and access to audit logs remain organizational gates. The Phase 3A table-audit requirement is approved, but no setting was changed and the last documented organization audit state is disabled.

## Migration Mapping

| Table | ATSugg concept mapping | Migration status / constraints |
|---|---|---|
| TA Directory | TA/interviewer directory | Conceptual only; map stable identity/email and preserve unresolved actors without granting app access. |
| Position | Internal jobs/positions | Source fields and duplicate-title handling unknown. |
| Candidate Source | Source values | Normalize only with approved crosswalk; retain historic meaning. |
| Location | Locations/rooms | Verify room mailbox identity and source-to-resource mapping. |
| App Configuration | None identified | New operational configuration; do not migrate secrets or endpoints. |
| Candidate | Candidate/person | Map candidate number, identity/contact, owner, status, lookups, CV URL. Source schema, IDs, format and counts unavailable. |
| Call Log | Calls/contact events | Map outcomes, actor, timestamps/time zone and notes; don't fabricate missing evidence. |
| Status History | Status changes | Preserve order/actor/time where available; map only approved canonical transitions. |
| Interview Round | Interviews/rounds/events | Map TA, mode, room, start/end, event ID and external state where source supports them. |
| Interview Result | Interview outcomes/feedback | Map Pass/Fail and feedback; salary meaning/access/retention require decision. |
| Email Template | Templates | Map content, version, variables and locale only if present and approved. |
| Email Dispatch | Email send history | Import as audited historical evidence only when recipients, sender, snapshots and outcomes are supported by source. Never infer Sent. |
| Visitor Registration | Visitor records | Candidate/interview/location relationship and retention pending source inventory. |
| LEGO Career | Official careers proxy | New integration dataset, not an assumed ATSugg table; Vietnam filter and external ID contract required. |
| Integration Run | Operational integration logs | New; do not migrate full payloads. Import sanitized history only if required and supported. |

Actual ATSugg documentation, schema, records, and access were not present/inspected. Preserve source identifiers in an approved crosswalk where permitted; do not add speculative source-ID columns until the source inventory confirms them. Trial migration must reconcile required keys, relationships, workflow history, and exceptions before cutover.

## Decisions Required Before Phase 1D

1. Candidate Core decisions for Candidate Number, contact requiredness, call outcomes, BSO ownership, reschedule reason, audit/field security, operation CorrelationId, and LEGO Career deferral are owner-approved in [Phase 3A](PHASE_3A_CANDIDATE_CORE_DESIGN.md); external audit and Custom API privilege gates remain open.
2. For later phases, confirm call-channel timing/backdate validation and migration mapping without changing the approved initial outcome taxonomy.
3. Confirm TA directory stable identity key, duplicate policy, and TA email access; email is not made unique here.
4. Confirm Position and Candidate Source duplicate/identity rules and Location resource identity.
5. Approve booking status options, time-zone/duration limits, room requirement and owner/organizer identity semantics.
6. Decide one result per round versus result versioning, salary semantics/currency/retention, and feedback access.
7. Approve visitor lifecycle values, notification scope, and retention.
8. Confirm LEGO API ID/country/location/URL schema and behavior for removed postings; no API contract is available.
9. Decide whether App Configuration is needed instead of solution environment variables; set configuration owners and nonsecret data scope.
10. Approve record ownership/sharing, role matrix, sensitive-field profiles, audit/retention, DLP, integration identities, and source migration mappings.
11. Review all proposed alternate keys against actual values, field-security exclusions, OData key characters, and live index creation before using them.

No table, column, key, relationship, role, choice, API, plug-in, app, or Flow was created by this Phase 1C documentation work.