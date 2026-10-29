# Production Release Runbook

**Status:** Offline gate/runbook only; not an approved change or deployment procedure. No Production target is recorded here. Production release remains prohibited until every required gate is backed by owner-approved evidence.

Use the frozen [Release Input Manifest](RELEASE_INPUT_MANIFEST.json) as the sole source identity. The same canonical release inputs may be used for Test and Production, but target-specific settings, approvals, and identity evidence must be supplied separately for each environment. Never copy a DEV-generated configuration or use the DEV-origin managed review archive.

## Mandatory no-write gates

Before any Production connection or write, the release owner must verify and record all of the following. A missing, stale, contradictory, or unverified item is a hard stop:

1. **Production target:** explicit approval of the environment display name, exact organization URL, Environment ID, Organization ID, and region; PAC `org who` and Dataverse `WhoAmI` must agree with the approved target. Keep the values in approved external evidence, not this repository.
2. **Artifact:** managed Solution artifact hash is pinned to the approved release record; unique name is `os_sr_bso_rs_support`; version is explicitly approved; artifact is not DEV-origin; Candidate Core package and Console/configuration hashes match the frozen release inputs.
3. **Production approval:** formal change/release approval names the exact artifact and target.
4. **Governance:** audit policy/retention/readers/capacity, privacy/data processing, and DLP are approved; current environment settings are not substitutes for policy approval.
5. **Migration:** an approved decision exists for `GREENFIELD_NO_IMPORT` or `MIGRATION_REQUIRED`. If migration is required, signed mapping, identity/history preservation, reconciliation, freeze/delta, cutover, and rollback plans are prerequisites.
6. **Backup and recovery:** pre-import backup/restore point and baseline inventory are verified; prior approved managed Solution, existing Candidate Core package, Candidate Console resources, and target configuration are hash-pinned; rollback authority and rehearsal are approved.
7. **Security:** Production BSO-only identity, exact `srapp` access, effective least privilege, Candidate Core execution, and five direct protected-write denials are approved and have target-specific acceptance evidence. Phase 5B DEV acceptance alone is not Production acceptance.
8. **Operations:** deployment, rollback, support, monitoring, incident escalation, and backup/restore validation owners are assigned; recovery objectives are approved.
9. **Integrations and data:** initial-launch decisions and DLP/identity/idempotency/recovery controls are approved for every integration to be enabled; real candidate data use is separately authorized.

The offline [solution import gate](../scripts/Test-BsoRsSolutionImportGate.ps1) validates supplied approval evidence and a managed-artifact SHA-256 without connecting or importing. It is not a Production deployment runner. Missing Production evidence returns `PRODUCTION_APPROVAL_REQUIRED`.

## Controlled import contract

When and only when separately authorized:

- Require an explicit target argument and fresh target identity agreement before any write.
- Import only the exact pinned managed artifact. Do not select the DEV-origin review archive.
- Do not use `PublishAllXml`, force overwrite, skip dependency checks, or an unapproved upgrade mode.
- Use zero retries for an ambiguous write. Stop and reconcile read-only; never resend an uncertain import.
- Reconcile Solution identity/version/state, publisher, root and included components, `srapp` and Site Map, web-resource hashes, target configuration, package identity/hash evidence where supported, Custom API handler topology, and all 50 guard registrations remaining inactive.
- Require the approved BSO identity's exact-app browser acceptance, synthetic positive lifecycle, replay/conflict/stale-status checks, five direct-write denials, rollback/recovery exercise, and final read-only reconciliation before production acceptance.

No command in this document was run. The Production import path is not authorized by this runbook's existence.

## Recovery ownership checklist

| Responsibility | Required evidence |
|---|---|
| Deployment owner | Named accountable owner and approved change window |
| Rollback owner | Named decision-maker and exact rollback authority |
| Support owner | Service desk/team and response coverage |
| Monitoring owner | Alert/query ownership and escalation destination |
| Incident escalation owner | Security/business/IT escalation chain |
| Recovery objective | Approved RTO/RPO or explicit business decision |
| Backup/restore validation owner | Named owner and verified restore-point/recovery evidence |

All entries remain `OWNER_REQUIRED`; no names or recovery objectives are assumed.
