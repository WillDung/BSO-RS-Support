# Phase 1D-B Reference Table Implementation Runbook

**Status:** Readiness plan only, 19 October 2026. No Dataverse resources were created or modified. Table creation requires separate explicit authorization.

This is historical Phase 1D-B readiness evidence. Later Phase 1D-C created only TA. Phase 1D-D prepared a shared automated Web API provisioner and passed read-only checks for the remaining tables without creating them; current inventory and authority are in [Current State](CURRENT_STATE.md). Use [Scripts](../scripts/README.md) for automated commands. This runbook's earlier absence/empty-Solution observations are not current-state claims.

## Verified Target and Resources

| Item | Verified value |
|---|---|
| Environment | VN LMV IT, Production-class, explicitly designated for internal IT development |
| URL | `https://org14938ec2.crm4.dynamics.com/` |
| Environment ID | `92e44afb-6c3a-eb1a-8154-4ed51e1e6e42` |
| Organization ID | `0706072c-54ea-f011-872b-000d3ab60060` |
| Publisher | `os_bso_rs_support`; prefix `os`; ID `ee73e9f3-87cb-f111-a05a-000d3a64b349` |
| Solution | `os_sr_bso_rs_support`; version `1.0.0.0`; Unmanaged; ID `63f48907-88cb-f111-a05a-000d3a64b349` |

CLI and MCP organization IDs matched. The four direct MCP schema describes returned not-found for `os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, and `os_sr_loc`. Solution Component metadata currently returns no rows. No records were queried.

## Exact Table and Column Specification

Definitions below are copied from [Dataverse Schema Specification](DATAVERSE_SCHEMA_SPECIFICATION.md). Logical names are final names. In Maker fields that prepend publisher prefix `os_`, enter only the listed `sr_...` stem; never paste the final `os_sr_...` string into an auto-prefixing input.

| Final table logical name | Maker table-name stem | Display name | Ownership | Primary name (final logical name; Maker stem) | Generated primary GUID logical name |
|---|---|---|---|---|---|
| `os_sr_ta` | `sr_ta` | TA Directory | OrganizationOwned | TA Name: `os_sr_ta_nm`; `sr_ta_nm` | Expected `os_sr_taid` |
| `os_sr_pos` | `sr_pos` | Position | OrganizationOwned | Position Title: `os_sr_pos_ttl`; `sr_pos_ttl` | Expected `os_sr_posid` |
| `os_sr_csrc` | `sr_csrc` | Candidate Source | OrganizationOwned | Source Name: `os_sr_csrc_nm`; `sr_csrc_nm` | Expected `os_sr_csrcid` |
| `os_sr_loc` | `sr_loc` | Location | OrganizationOwned | Location Name: `os_sr_loc_nm`; `sr_loc_nm` | Expected `os_sr_locid` |

The GUID names are Dataverse-generated using `<logical table name>id`; confirm the actual `PrimaryIdAttribute` read-back rather than supplying a custom GUID name.

| Table | Final column logical name | Maker column-name stem | Display name | Type / max | Required | Default | Validation / condition |
|---|---|---|---|---|---|---|---|
| TA Directory | `os_sr_ta_nm` | `sr_ta_nm` | TA Name | Text / 200 | Required | None | Nonblank; primary name appears through lookups. |
| TA Directory | `os_sr_ta_eml` | `sr_ta_eml` | TA Email | Email / 254 | Required | None | Valid email; normalize for duplicate checks. No alternate key. |
| Position | `os_sr_pos_ttl` | `sr_pos_ttl` | Position Title | Text / 200 | Required | None | Nonblank; no uniqueness rule. |
| Candidate Source | `os_sr_csrc_nm` | `sr_csrc_nm` | Source Name | Text / 100 | Required | None | Nonblank; no uniqueness rule. |
| Location | `os_sr_loc_nm` | `sr_loc_nm` | Location Name | Text / 150 | Required | None | Nonblank. |
| Location | `os_sr_loc_rmeml` | `sr_loc_rmeml` | Room/Resource Email | Email / 254 | Optional at create | None | Required by the offline booking operation; validate resource mailbox mapping. |
| Location | `os_sr_loc_det` | `sr_loc_det` | Location Details | Multiline Text / 1,000 | Optional | None | Operational details only; no access codes/secrets. |

`statecode/statuscode` are system columns; use the standard Active/Inactive state and do not add a duplicate active Boolean. Requiredness markers are from the existing schema proposal. Microsoft notes that Application Required is primarily app/form-enforced; any API/process writes must validate required values as well. No custom alternate keys are proposed for these four tables. The ownership choice and primary-name definition are creation-time decisions and must be checked before saving; Microsoft documents that table ownership and names cannot be changed after creation.

Table descriptions were not defined in the approved field inventory. Leave descriptions blank or obtain approved text; do not invent business requirements. Do not add columns, keys, choices, relationships, or sample rows in this batch.

## Maker Portal Creation Sequence (Future, Approval-Gated)

Repeat the full create-and-read-back cycle for one table at a time in this order: `os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, `os_sr_loc`. The tables are independent; this order follows the existing runbook recommendation.

1. **Preflight immediately before the approved run:** run `pac env who` and `pac admin list --name "VN LMV IT"`; compare name, URL, Environment ID, Organization ID, and Production type with the verified values above. Stop on any mismatch; do not switch environments.
2. Verify Publisher `os_bso_rs_support` has prefix `os`, and Solution `os_sr_bso_rs_support` is Unmanaged with that Publisher. Verify the Solution's current component list and the target table is still absent by read-only metadata.
3. Open Power Apps Maker Portal, explicitly select **VN LMV IT**, open **Solutions**, and open **BSO-RS-Support** (`os_sr_bso_rs_support`). Confirm the solution Publisher is **BSO-RS-Support Publisher**; do not use an organizational default publisher.
4. From inside that Solution, choose **New > Table**. Enter the table display name and Maker name stem from the table matrix. Set **Ownership** to **Organization** in table properties before saving. Select the specified primary-name display name, Text type, max length, and Maker stem. Check the final generated name preview is exactly `os_sr_<suffix>` before saving.
5. Add only the listed additional columns with their exact display names, Maker stems, types, lengths, and requiredness. Do not create relationships or alternate keys for these reference tables. Save the table only after the full metadata preview has been checked.
6. Keep table and column audit flags off/unset. Environment auditing is disabled and audit policy is pending IT/Compliance approval; see the audit gate below. Do not populate the table.
7. Perform the independent read-back checks below. Proceed to the next table only after the current table's name, ownership, primary name/ID, fields, and Solution membership pass.

Microsoft documents that creating objects from a solution adds them to that solution. If a table is created through a different supported path, it must be added to the project Solution as a separate, approved operation and independently verified before continuing.

## Settings and Audit Gate

Creation-time properties that must be exact before save:

- Publisher context/name stem and final logical name (names are not renameable after creation).
- Ownership `OrganizationOwned` (ownership type cannot be changed later).
- Primary name column and its type/format.
- Each column's final name, type/format, max length, and requiredness (saved column names and data types cannot generally be changed).

Audit configuration is not permissioned by this runbook. Read-only assessment found environment auditing disabled, configured retention 30 days (not approved policy), user-access auditing disabled, and log capacity unknown. The table/column audit matrix can be prepared independently as documentation, but **do not set table or column audit flags** while the environment-level decision is pending; those flags may begin producing logs after a later environment activation. Environment Start Auditing, retention, User Access Auditing, and per-table/column audit settings are blocked pending written IT/Compliance approval and production change control. No records may be entered before the approved audit plan is active as required by the data governance decision.

## Creation and Read-Back Capabilities

| Tool | Capability | Readiness conclusion |
|---|---|---|
| Power Apps Maker Portal | Create a table in the context of a chosen Solution; configure ownership, primary name, and columns; table components are associated with that Solution. | Supported planned path; use only after separate Phase 1D authorization. |
| MCP `describe` / `search` | Read-only table schema discovery. | Supported for before/after schema checks; direct preflight describes found all four tables absent. |
| MCP `read_query` | Read-only Publisher, Solution, `entity`, `attribute`, and `solutioncomponent` metadata queries. | Supported for identity and Solution membership checks; do not query business tables or `audit`. |
| MCP `create_table` | Table and subset of columns; name argument says not to include prefix. Does not expose OrganizationOwned, explicit primary-name selection, audit properties, alternate keys, or Solution ID. | **Not suitable** for this exact specification; do not invoke. |
| PAC CLI 2.13.1 | `pac table` is not a valid command. `pac solution add-solution-component` adds an already-existing component; it does not create a table. | No direct PAC table-creation path found. Add-existing is only a separately approved recovery if Maker membership is missing. |

## Independent Read-Back Checks (Future, Read-Only)

Run after each table save, before continuing. These are metadata queries only and must not select table records.

1. `mcp_describe(path="tables/os_sr_ta")` (repeat for each logical name): verify final table name and every column logical name/type/format/length exposed by the schema response. Compare with the matrix above.
2. Read the table definition metadata row:

   ```sql
   SELECT logicalname, entityid, componentstate
   FROM entity
   WHERE logicalname = 'os_sr_ta'
   ```

   Repeat with each table name. Expect one metadata definition per table.
3. Verify the table component is in the existing project Solution and its component type is Entity (`1`):

   ```sql
   SELECT e.logicalname, e.entityid, sc.solutionid, sc.componenttype
   FROM solutioncomponent sc
   JOIN entity e ON sc.objectid = e.entityid
   WHERE sc.solutionid = '63f48907-88cb-f111-a05a-000d3a64b349'
     AND sc.componenttype = 1
     AND e.logicalname = 'os_sr_ta'
   ```

4. Verify column components are in the same Solution (Attribute=`2`):

   ```sql
   SELECT e.logicalname AS tablelogicalname, a.logicalname AS attributelogicalname,
          sc.solutionid, sc.componenttype
   FROM solutioncomponent sc
   JOIN attribute a ON sc.objectid = a.attributeid
   JOIN entity e ON a.attributeof = e.entityid
   WHERE sc.solutionid = '63f48907-88cb-f111-a05a-000d3a64b349'
     AND sc.componenttype = 2
     AND e.logicalname = 'os_sr_ta'
   ```

   Confirm all specified custom columns are represented explicitly, or that the table's root Solution component has `rootcomponentbehavior=0` (**Include Subcomponents**), which includes its columns without separate attribute rows. Never treat absence of explicit attribute rows alone as missing membership. Shell-only/excluded subcomponents require explicit column membership. Repeat for each table.
5. Ownership and `PrimaryIdAttribute`/`PrimaryNameAttribute` must be independently verified through the Maker table properties or a read-only Dataverse Web API `EntityDefinitions(LogicalName='os_sr_ta')` metadata GET. The current MCP table/Entity schema views do not expose `OwnershipType` reliably. Verify expected generated GUID name `os_sr_taid`, and equivalent names for other tables; do not treat the metadata `entityid` as the row primary GUID column.
6. Confirm table/column `IsAuditEnabled` remains false/unset using Maker metadata or an authorized metadata read-back. Do not read the Audit table.

## Duplicate and Identity Policies (Unresolved)

| Table | Existing key proposal | Outstanding rule |
|---|---|---|
| TA Directory | No alternate key | Stable TA identity, email normalization, duplicate email policy, and whether email may be unique. |
| Position | No alternate key | Duplicate titles and stable position code/identity. |
| Candidate Source | No alternate key | Alias normalization and whether canonical source name is unique. |
| Location | No alternate key | Stable room/resource identifier and duplicate location policy. |

Do not add a key or duplicate-detection rule without the business/data owner deciding the identity semantics. The GUID primary ID remains the only enforced uniqueness for these reference tables in this proposal.

## Partial-Creation Recovery

- Before retrying any uncertain operation, perform read-only direct schema describe, `entity` metadata lookup, and Solution Component membership checks. Never repeat a create call based only on a timeout or missing UI response.
- If no table metadata exists, report the result and wait for the approved operator's decision before retrying.
- If a table exists with correct properties but is not in the Solution, stop. After explicit approval, use Maker **Add existing > Table** or the documented `pac solution add-solution-component --solutionUniqueName os_sr_bso_rs_support --component <schema-name-or-id> --componentType 1` path, then re-read membership.
- If logical name, ownership, or primary name/ID is wrong, do not rename, delete, or recreate. Ownership/table names cannot be changed after creation; preserve the object and escalate for an approved migration/recovery plan.
- If only a non-key column is missing or incorrect, stop and compare the actual schema to the approved field inventory. Any repair is a separate explicit change; do not add unlisted columns or change types/requiredness silently.
- Never delete a table as rollback. No records are to be created in this batch, so recovery is metadata reconciliation and owner-directed forward repair, not data restore.

## Phase 1D Authorization Checklist

All items require affirmative confirmation before the first table creation:

- [ ] Explicit approval for Phase 1D-B table creation in VN LMV IT Production, designated for internal IT development.
- [ ] Preflight confirms expected URL, environment/organization IDs, Publisher `os_bso_rs_support`/prefix `os`, and Unmanaged Solution `os_sr_bso_rs_support`.
- [ ] Table order and exact four final names, display names, OrganizationOwned ownership, primary names, GUID names, and column definitions approved as written here.
- [ ] Owner accepts there are no alternate keys for these four tables until identity/duplicate policies are decided; no duplicate enforcement is claimed.
- [ ] Audit policy/retention approval status reviewed; environment/table/column/user-access audit settings remain unchanged in this phase.
- [ ] Operator agrees to create one table, independently read it back, verify Solution membership, then continue; no automatic retries or deletions.
- [ ] Recovery owner and change record/approval reference captured before starting.

No checklist item is checked by this readiness document. Phase 1D-B is not approved or executed.

## Microsoft References

- [Create a custom table in Dataverse](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/data-platform-create-entity)
- [Solution concepts and creating objects in a solution](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/create-solution)
- [Table definitions: primary ID, primary name, and ownership](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/entity-metadata)
- [Column creation, naming, requiredness, and data types](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/create-edit-field-portal)
- [Dataverse audit policy and environment-level prerequisites](DATAVERSE_AUDIT_POLICY.md)
