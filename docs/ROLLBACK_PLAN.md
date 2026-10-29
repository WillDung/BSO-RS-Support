# BSO-RS-Support Rollback Plan

**Status:** Proposed and not rehearsed. No rollback artifact or downstream recovery operation is claimed to exist. This plan is not authorization to change an environment.

## Preconditions

Before any Test or Production release, record the approved target, release change, recovery owner, recovery window, restore point, expected data impact, and exact rollback authority. Retain the prior reviewed managed Solution, package and web-resource hashes, dependency inventory, configuration policy, and a protected deployment journal outside the repository. Validate that the selected recovery method is supported for that environment before the release begins.

Do not proceed if the prior release cannot be identified exactly, the backup/restore posture is unknown, the rollback package or configuration is unverified, or external email/calendar/SharePoint effects cannot be reconciled.

## Stop and preserve evidence

1. Stop further UI submissions, imports, package updates, and retries.
2. Record the safe stage, sanitized platform code, artifact hash, target label, and dispatch journal location. Do not copy tokens, raw fault text, user IDs, environment IDs, candidate PII, CVs, or connector URLs into the report.
3. Perform read-only reconciliation of deployed component identity/version, package/handler topology, app navigation, configuration resource hashes, and affected synthetic test rows.
4. Do not repeat uncertain or non-idempotent operations. Preserve the journal and obtain explicit owner direction before any recovery write.

## Component-specific recovery

### Candidate Console resources

- Restore only the exact previously reconciled `candidate-console.html`, JavaScript, policy, and configuration resources, with their corresponding prior cache-bust hashes.
- Use the scoped Candidate Console refresh workflow for exact resources and `srapp`; reconcile each published resource and verify sitemap semantics remain unchanged.
- Never use `PublishAllXml`. Do not deploy the checked-in `UNCONFIGURED` template as a substitute for a known-good target configuration unless the approved response is to deliberately block Candidate Management.

### Managed Solution

- Use only the prior reviewed managed package and the approved environment recovery/import procedure. Reconcile Solution identity, version, components, dependencies, app state, and data impact after recovery.
- A managed Solution rollback is not assumed to undo data changes or external side effects. Do not delete business records to simulate rollback.
- The full Solution export and a tested prior managed artifact are not currently present in this workspace; this recovery path is **not ready**.

### Candidate Core package

- Any future package recovery must target the existing `os_sr_cact_pkg` identity exactly once with a previously validated, unsigned package artifact and zero retries.
- Preserve the active package-backed handler and Custom API contract. Do not create a new PluginPackage, patch the handler or guard, modify the separate signed legacy rollback assembly, reactivate `ProtectCandidateCore`, inspect signing keys, enable Profiler, or change PluginTraceLog.
- Require immediate read-only topology reconciliation. If artifact identity or outcome is uncertain, stop; do not resend.
- A prior package artifact and release-specific one-shot rollback procedure have not been independently established for this ALM continuation. Do not infer the legacy signed assembly is an approved package rollback.

## External side effects and data

Candidate Core business writes are transactionally bounded, but a solution rollback does not undo email delivery, calendar events, SharePoint documents, source synchronization, or visitor registration. Those integrations remain outside the initial Candidate Core rehearsal unless separately approved with identity, idempotency, privacy, audit, and compensation controls.

Use synthetic records only. Do not use this plan to restore or reconcile real candidate data or to access ATSugg.

## Recovery acceptance

Recovery is accepted only after:

- the exact target and artifact identities are independently reconciled;
- the Candidate Console and approved app load under the intended test identity;
- Candidate Core remains the only approved protected business-write path;
- direct protected writes remain denied by standard Dataverse privileges;
- synthetic workflow, idempotency, audit, privacy, and recovery checks pass; and
- no unexpected external side effects or unexplained record changes remain.

Production recovery requires separate incident, business, security, and change-control authorization. Current disposition: `ROLLBACK_PLAN_PROPOSED_NOT_REHEARSED`.
