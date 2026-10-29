# ALM and Deployment

**Status:** Proposed wider delivery approach. Phase 1B created the Publisher and initially empty unmanaged Solution in VN LMV IT Production for internal IT development. On 19 October 2026, separately approved Phase 1D-C created only `os_sr_ta`; independent metadata reads verified schema and Solution inclusion. See [Current State](CURRENT_STATE.md). No pipelines, environment variables, connection references, or other project tables were created.

Phase 1D-D Apply was explicitly approved on 20 October 2026 for Position, Candidate Source, and Location. The first `os_sr_pos` creation POST returned HTTP 401. Read-only reconciliation found no Position metadata and verified that only TA remains in the project inventory. The sequence stopped; no further Apply calls, retries, role changes, audit changes, or data writes occurred. Do not attempt recovery until the cause of the 401 is resolved and an operator-approved retry plan is recorded.

## Phase 1B Resource Record

| Resource | Verified properties |
|---|---|
| Environment | VN LMV IT; Production type; explicitly selected for internal IT development. Environment URL and environment/organization IDs are intentionally not stored in this repository. |
| Publisher | BSO-RS-Support Publisher; unique name `os_bso_rs_support`; customization prefix `os`; option value prefix `10001`; ID `ee73e9f3-87cb-f111-a05a-000d3a64b349`. |
| Solution | BSO-RS-Support; unique name `os_sr_bso_rs_support`; version `1.0.0.0`; Unmanaged; ID `63f48907-88cb-f111-a05a-000d3a64b349`; linked to the Publisher above. |
| Verification | Read-only MCP read-back confirmed Publisher and Solution fields; `pac solution list` independently confirmed Solution name/version/unmanaged state; Solution Component query returned no rows. No tables, apps, or flows were created. |

These resource records do not authorize additional schema, application, flow, security, or deployment work. Follow-on phases require their own approval and production change controls.

## Candidate-Only Metadata Update

The later bounded Candidate-only run created and GET-reconciled the Candidate Status Choice, Candidate table, two Active alternate keys, and three approved lookup relationships in this Solution. The table audit flag is enabled; organization-level auditing remains disabled, so no Candidate records may be created. See the [Candidate-only provisioning report](PHASE_3A_CANDIDATE_TABLE_PROVISIONING_REPORT.md).

A supported PAC export/unpack was performed after provisioning. Because PAC exports the entire Solution, the result also included the existing `srapp` and reference-table components, beyond the Candidate-only source scope. The unpacked Candidate entity contained Card, Main, and Quick form files plus SavedQueries; their individual definitions were not retained for detailed review, and no independent form/view edits were made in this task. The generated export was not retained in the workspace; the `solutions/` source folder therefore still has no full Solution snapshot. No commit or push occurred. A full-solution source pull requires a separately bounded repository-scope decision.

Phase 2C-R3 owner decision on 21 October 2026 officially adopted the existing BSO-RS-Support AppModule (`srapp`, ID `3709bb7c-28cd-f111-a05c-70a8a581cbfa`) in `os_sr_bso_rs_support`. The name `srapp` is the approved component-specific exception; prior expected name `os_srapp` is superseded. Phase 2C closed by adoption, not a successful Create; no AppModule was created, renamed, or recreated. Solution membership is verified by its type-80 root. The AppModule Publisher lookup remains unknown. R2 live state remains Active/Unpublished, with no app components and placeholder-only Published Site Map. Phase 2D composition planning is documented but Phase 2D is not authorized.

## Phase 1D-B Reference Table Readiness

Read-only schema checks on 19 October 2026 found `os_sr_ta`, `os_sr_pos`, `os_sr_csrc`, and `os_sr_loc` absent, and no components currently in the project Solution. The Maker Portal runbook [Phase 1D-B Reference Table Runbook](PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md) specifies creation inside the existing Unmanaged Solution and the independent metadata read-back. This is a plan only; no tables or audit flags have been created/enabled. Environment audit activation remains blocked pending IT/Compliance policy approval; current retention is not an approved value.

## Audit Readiness Gate

Read-only audit configuration assessment on 19 October 2026 found environment auditing off, a configured 30-day retention setting, and user-access auditing off. The 30-day value is not an approved retention policy. Do not enable environment/table/column auditing or user-access auditing until IT/Compliance approvals, capacity review, existing-table audit-flag inventory, audit-reader roles, retention/historic-log treatment, and change control are documented. See [Dataverse Audit Policy Proposal](DATAVERSE_AUDIT_POLICY.md) and [Audit Impact Assessment](AUDIT_IMPACT_ASSESSMENT.md). No audit or environment setting was changed.

## Environments and solutions

Use dedicated Dev, Test, and Production environments where approved. Confirm region, access, capacity, DLP, ownership, backup, and data policies before use. Develop in a solution-aware environment. Export and unpack solution source through supported Power Platform tooling for version control; do not commit generated packages or credentials. Promote managed Solutions downstream, with controlled versioning and release approvals.

## Configuration and connections

Use environment variables for environment-specific nonsecret configuration and supported secret handling for secrets. Use connection references rather than embedded personal connection IDs. Keep connector identity and authorization explicit: the intended BSO email/calendar identity must be verified; a fixed Flow owner must not silently impersonate the BSO. Validate references and permissions at each environment boundary.

## Candidate Console environment configuration (local source; not deployed)

**Current implementation:** the local Candidate Console source now loads a separate environment configuration and pure policy resource before its main script. The checked-in configuration is `UNCONFIGURED`, disables Candidate Core, keeps synthetic-only mode, disables fallback, and sets diagnostics Off. The policy compares the configured HTTPS organization origin and organization ID with the runtime model-driven app context; fallback availability is limited to DEV. DEV and TEST configurations must remain synthetic-only. Non-synthetic PROD mode is representable only as an explicit external configuration and is not approved or present.

The least-privilege app session could not read Environment Variable Definition metadata (`0x80040220`, `prvReadEnvironmentVariableDefinition`). No privilege was granted, and Environment Variable Value access was not independently verified. The implementation therefore uses a guarded configuration web resource rather than requiring the Candidate Console user to read Environment Variables. `New-BsoRsCandidateConsoleEnvironmentConfig.ps1` requires explicit target URL and IDs and writes the generated configuration plus matching hash-busted HTML outside the repository. Do not commit generated files or deployment evidence.

`Deploy-BsoRsCandidateConsole.ps1 -CreateNewResources` is limited to the exact configuration and policy resources, checks the external config against the fixed DEV target, preserves the existing sitemap, and scopes publication to the selected resources and `srapp`. A later refresh that changes configuration must include the exact config and generated HTML resources so the HTML cache token matches the generated configuration hash. Preflight and GET reconciliation are mandatory; retries remain zero. These scripts have not been run for this local refactor, so the new resources and browser behavior are **not verified deployed**.

**Dependencies/open decisions:** the active PAC profile matched the pinned DEV identity during a read-only check, but no full Solution export was performed because target confirmation for that export was unavailable. The full Solution source snapshot and managed release candidate remain outstanding; do not infer that the current resource files constitute a complete Solution. No approved TEST target or target-specific configuration is established (`TEST_TARGET_APPROVAL_REQUIRED`). Production configuration, import, and runtime validation remain unauthorized. Production readiness still requires approved audit, privacy, DLP, backup/recovery, business acceptance, and change-control gates.

## Promotion gates

1. Build and validate in Dev with synthetic data.
2. Review solution contents, dependencies, roles, APIs, flows, environment-variable definitions, and connection references.
3. Import managed to Test; execute integration, authorization, regression, failure-recovery, UAT, and migration rehearsal as relevant.
4. Obtain documented business, security, and release approval.
5. Back up/confirm recovery posture; deploy managed solution to Production through the approved pipeline/change process.
6. Run approved smoke checks and monitor. Roll back or disable affected operations under the approved plan if acceptance fails.

## Backup, recovery, rollback

Define Dataverse backup/restore capability, recovery objectives, data impact, solution rollback/version strategy, external calendar/email side effects, and ownership before production. A solution rollback does not undo sent email or external calendar events; those require reconciliation/compensating operations. Production changes require approval and a rollback plan. Do not claim ATSugg retirement until migration acceptance and retirement criteria are met.
