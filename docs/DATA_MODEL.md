# Proposed Dataverse Data Model

**Status:** Phase 1C business schema proposal is detailed in [Dataverse Schema Specification](DATAVERSE_SCHEMA_SPECIFICATION.md). No business tables, columns, relationships, or keys are deployed. The project Publisher and empty unmanaged Solution have been created; see [ALM and Deployment](ALM_DEPLOYMENT.md). Schema-owner/security review and resolution of open decisions are required before Phase 1D table provisioning.

## Naming standard and private abbreviation dictionary

The following internal dictionary maps business meanings to proposed technical abbreviations. Keep this mapping in this repository; do not publish it externally. The selected naming strategy is Publisher Prefix `os` plus the project namespace segment `sr_`. Together they form the final technical-name prefix `os_sr_`; examples below show final names, not values to paste blindly into auto-prefixing name fields. The names are proposals; no business schema components are deployed.

| Business meaning | Abbreviation | Example proposed table name |
|---|---|---|
| Candidate | `cand` | `os_sr_cand` |
| Call Log | `call` | `os_sr_call` |
| Candidate Status History | `csh` | `os_sr_csh` |
| Interview Round | `irnd` | `os_sr_irnd` |
| Interview Result | `ires` | `os_sr_ires` |
| TA Directory | `ta` | `os_sr_ta` |
| Location | `loc` | `os_sr_loc` |
| Position | `pos` | `os_sr_pos` |
| Candidate Source | `csrc` | `os_sr_csrc` |
| Email Template | `etpl` | `os_sr_etpl` |
| Email Dispatch | `edsp` | `os_sr_edsp` |
| Visitor Registration | `vreg` | `os_sr_vreg` |
| LEGO Career | `lgcar` | `os_sr_lgcar` |
| Integration Run | `irun` | `os_sr_irun` |
| App Configuration | `acfg` | `os_sr_acfg` |

Additional reusable tokens: `cnum` = Candidate Number; `cnak` = Candidate Number alternate key; `stat` = workflow status; `hist` = history; `res` = result; `loc` = location; `cfg` = configuration; `bk` = booking; `int` = interview; `bkint` = book interview; `cal` = calendar; `calbk` = calendar booking; `eml` = email; `sch` = scheduling; `idem` = idempotency; `corid` = correlation ID; `extid` = external ID; `stp` = plug-in step. Use these only where they describe the field or operation precisely; add new abbreviations to this dictionary before use. Avoid personal values or identifying data in every technical name.

The detailed proposal extends the dictionary with `candstat` = shared Candidate Workflow Status choice; `ak` = alternate key; `nm` = name; `ttl` = title; `phn` = phone; `det` = details; `key` = configuration key; `val` = value; `dsc` = description; `out` = outcome; `ctat` = contacted at; `ctby` = contacted by; `nts` = notes; `actr` = actor; `actkey` = action key; `prevstat`/`newstat` = previous/new status; `chg` = changed at; `rsn` = reason; `mod` = mode; `strt`/`end` = start/end; `orgeml` = organizer email; `evt` = provider event; `fb` = feedback; `sal` = salary; `recby`/`recat` = recorded by/at; `ver`/`tplver` = version/template version; `subj`/`body` = subject/body; `tosn`/`ccsn` = To/CC snapshots; `sndr`/`sndas` = intended/observed sender; `sentat`/`tryat` = sent/last-attempt time; `prvid` = provider ID; `err` = sanitized error; `reqby` = requested by; `visat` = visit at; `ctry` = country; `lsync` = last sync; `knd` = kind; `stgat`/`cmpat` = started/completed at; `rowcnt` = row count; `ref` = nonpersonal autonumber reference. These remain technical tokens, not business requirements.

Apply the convention consistently to Dataverse tables, custom columns, relationships, alternate keys, Custom APIs, plug-in assemblies/types/steps, and Cloud Flows wherever each platform component supports custom naming. Use lowercase abbreviations and the patterns below; keep user-facing display labels readable business terms.

| Component | Proposed final technical-name pattern | Example final name |
|---|---|---|
| Table | `os_sr_<table-abbreviation>` | `os_sr_cand` |
| Custom column | `os_sr_<table-abbreviation>_<field-abbreviation>` | `os_sr_cand_cnum` |
| Relationship | `os_sr_<source-abbreviation>_<target-abbreviation>[_<purpose-abbreviation>]` | `os_sr_cand_call` |
| Alternate key | `os_sr_<table-abbreviation>_<key-abbreviation>` | `os_sr_cand_cnak` |
| Custom API | `os_sr_<operation-abbreviation>` | `os_sr_bkint` (book interview) |
| Plug-in component | `os_sr_<operation-abbreviation>[_<component-role-abbreviation>]` | `os_sr_bkint_stp` |
| Cloud Flow | `os_sr_<process-abbreviation>` | `os_sr_calbk` (calendar booking) |
| Global Choice | `os_sr_<choice-abbreviation>` | `os_sr_candstat` |

For Dataverse components whose Maker experience automatically applies the solution publisher prefix `os`, use only the `sr_<abbreviation>` stem in the name input so the resulting persisted name is `os_sr_<abbreviation>`. For programmatic metadata or other component fields that require a complete logical/schema/unique name, supply the final `os_sr_<abbreviation>` once. Inspect the resulting name before saving; do not enter the full final name into a field that will prepend `os_` and create `os_os_sr_...`.

The five table examples above use lowercase letters and underscores, begin with a letter, and are final names rather than publisher-prefix values. Microsoft documents the customization prefix as 2–8 alphanumeric characters, beginning with a letter; it also says the prefix cannot start with `mscrm`. `os` meets these documented character and length rules. A read-only publisher metadata check in VN LMV IT on 19 October 2026 found no publisher using prefix `os`; this is a time-bound conflict check, not approval or creation evidence. See [Customize Table Definitions](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/customize-entity-metadata), [Publisher table reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/publisher), and [solution publisher guidance](https://learn.microsoft.com/en-us/power-platform/alm/solution-concepts-alm#solution-publisher).

Some names cannot or should not follow the final-name pattern. The Publisher `CustomizationPrefix` is `os` by design, not an `os_sr_` component name. Platform-assigned GUIDs, immutable IDs, and system-owned names are not custom names and cannot be forced to begin `os_sr_`. Some primary-column and relationship names may be generated or constrained by their parent metadata; inspect their resulting schema names instead of assuming a free-form suffix. Cloud Flow IDs are platform-assigned, while a user-settable Flow display name should use the full `os_sr_...` form because it does not rely on Dataverse publisher auto-prefixing. Plug-in assembly/type/step names also need component-specific handling; use the full final form where the registration/build tool permits a custom name, and do not assume `os_` will be inserted. Validate each component type's actual name field, allowed characters, length, reserved words, uniqueness, relationship/key constraints, and generated result before creation. If a platform-controlled name cannot follow the convention, document the exception rather than renaming a generated object or silently changing the namespace.

Once technical names are approved, keep them stable. Do not rename or recreate an existing component without an explicit migration plan addressing dependencies, data, integrations, and deployment. The project Publisher and empty Solution are recorded in [ALM and Deployment](ALM_DEPLOYMENT.md); no business schema components are deployed.

Abbreviations are a naming and information-disclosure reduction measure, not a security boundary. Protect sensitive data with Dataverse security roles, record-level access control, column-level security when appropriate, auditing, data loss prevention policies, and least-privilege connector access. Never expose personal data in names, logs, fixtures, or repository documentation.

## Proposed entities

The per-table implementation proposal, including full column inventory, requiredness, defaults, validation, keys, relationships, delete behavior, ownership, auditing, security, dependencies, and migration mapping, is maintained in [Dataverse Schema Specification](DATAVERSE_SCHEMA_SPECIFICATION.md). The exact first-four reference table sequence, Maker input stems, solution checks, and recovery plan are in [Phase 1D-B Reference Table Runbook](PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md). This overview and its abbreviation dictionary remain authoritative for business abbreviations.

| Business entity | Proposed technical table name | Purpose and key relationships | Ownership / key considerations |
|---|---|---|---|
| Candidate | `os_sr_cand` | Main candidate, contact, candidate number, job/source, status, BSO owner, TA, CV URL, LEGO Career | Candidate Number unique; likely user/team owned, confirm access model |
| Call Log | `os_sr_call` | Append-only outreach outcome, time, actor, notes; N:1 Candidate | Candidate lookup; audit actor/time; restrict edits/deletion per retention decision |
| Candidate Status History | `os_sr_csh` | Previous/new status, actor, timestamp, reason, correlation; N:1 Candidate | Append-only business history; unique transition/action token to reduce duplicates |
| Interview Round | `os_sr_irnd` | Candidate, TA, mode, room, start/end, organizer, provider event ID, status; N:1 Candidate | Event/action correlation unique as applicable; define multiple attempts and time zones |
| Interview Result | `os_sr_ires` | Pass/Fail, feedback, salary, recorded by/at; relationship to Candidate and Round | Enforce one valid result or versioning policy; salary field protection decision |
| TA Directory | `os_sr_ta` | Email, display name, active | Stable directory identifier/email uniqueness; not an interactive user role by default |
| Location | `os_sr_loc` | Name, room/resource email, details, active | Stable location and resource identity; validate room mailbox mapping |
| Position | `os_sr_pos` | Title, active | Decide stable key and duplicate-title handling |
| Candidate Source | `os_sr_csrc` | Source name, active | Decide stable key and whether historical values are retained |
| Email Template | `os_sr_etpl` | Code, subject/body, To/CC defaults, active | Stable code; allowlisted variables; approval/versioning and localization policy |
| Email Dispatch | `os_sr_edsp` | Candidate, idempotency key, intended sender, To/CC, subject/body snapshot, state, provider correlation, timestamps/errors | Idempotency key unique; restrict PII/body access and retention; states Queued/Sending/Sent/Failed/Indeterminate |
| Visitor Registration | `os_sr_vreg` | Candidate, interview, location, visit time, status | Relationship/cardinality and retention require validation |
| LEGO Career | `os_sr_lgcar` | External ID, position/title, location/country, URL, status, last sync | External ID unique; upsert key; avoid deactivation on partial sync |
| Integration Run | `os_sr_irun` | Kind, correlation, start/end, state, sanitized error | Restrict payload/PII; retention and observability policy required |
| App Configuration | `os_sr_acfg` | Logical key and approved nonsecret value | Prefer environment variables for environment-specific settings/secrets; do not store secrets as ordinary rows |

## Relationship sketch

```mermaid
erDiagram
    os_sr_cand ||--o{ os_sr_call : os_sr_cand_call
    os_sr_cand ||--o{ os_sr_csh : os_sr_cand_csh
    os_sr_cand ||--o{ os_sr_irnd : os_sr_cand_irnd
    os_sr_irnd ||--o| os_sr_ires : os_sr_irnd_ires
    os_sr_cand ||--o{ os_sr_edsp : os_sr_cand_edsp
    os_sr_cand ||--o{ os_sr_vreg : os_sr_cand_vreg
    os_sr_irnd ||--o{ os_sr_vreg : os_sr_irnd_vreg
    os_sr_ta ||--o{ os_sr_irnd : os_sr_ta_irnd
    os_sr_loc ||--o{ os_sr_irnd : os_sr_loc_irnd
    os_sr_pos ||--o{ os_sr_cand : os_sr_pos_cand
    os_sr_csrc ||--o{ os_sr_cand : os_sr_csrc_cand
    os_sr_lgcar ||--o{ os_sr_cand : os_sr_lgcar_cand
```

The nodes and relationship labels use proposed abbreviated identifiers; cardinalities are conceptual and need schema review, especially Interview Result, Location, and LEGO Career. Do not treat this diagram as a deployed schema.

## Cross-cutting design questions

Confirm primary names/alternate keys, ownership (user/team/org), row sharing, field-level security for salary and personal details, audit configuration, retention/deletion/archiving, optimistic concurrency, time zone strategy, cascade behavior, duplicate detection, and migration identity keys. Critical status changes should atomically record state/history within an approved server-side operation. External effects remain separately correlated and reconciled.
