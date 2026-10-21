---
name: bso-powerplatform-build-next
description: Implement one authorized BSO-RS-Support Power Platform app slice from VS Code with verification.
disable-model-invocation: true
---
# BSO-RS-Support — Build Next Approved App Slice

Work in BSO-RS-Support, not ATSugg. Read all repository governance and the latest verified CURRENT_STATE and PRODUCT_DECISIONS before selecting work. Use the installed Microsoft Dataverse Skills if present and the existing MCP/PAC/SDK/Web API paths supported by the current environment.

## Goal

Deliver the **next explicitly approved slice** of the actual Power Platform application, not another generic setup report. The outcome must be a verifiable Dataverse/Power Apps/Flow/Solution artifact (if a write is approved) or an exact, executable implementation readiness report (if not).

## Workflow

1. Reconstruct state using read-only metadata. Distinguish live verified resources from proposals and older reports.
2. Choose the smallest dependency-ordered slice (schema → relationships/security → model-driven app/forms/views → custom pages → Custom APIs/plug-ins → Cloud Flows/integrations → tests/ALM) without skipping blocking business/security decisions.
3. Propose exact target components, changes, supported tool(s), dependencies, QA/rollback, and audit/data risks. Ask for **explicit approval of each new write scope**. A prior approval to create other resources does not carry forward. Do not repeatedly ask for an approval already explicitly granted for the same safe scope.
4. Once approved, re-verify target/environment, preview actual payload, execute **once** with no silent retries, and independently read back created resources and Solution membership. In a partial/uncertain result, stop and reconcile read-only; do not automatically delete, retry, recreate or republish.
5. Export/unpack/publish only when the specific operation is approved, validate artifacts and record actual state in project docs. **Do not run git commit, push, pull, sync.**
6. Return PASS/PARTIAL/FAIL with evidence, not just optimistic POST response or GET-only DryRun.

## Special current incident

As last reported: `os_sr_ta` exists, `os_sr_pos` create POST failed HTTP 401 and was reconciled absent; root cause UNKNOWN. Do not retry this POST or use another MCP/SDK route to circumvent the incident without explicit NEW recovery authorization and a diagnostic plan. Test the safe path first; any different auth mechanism remains subject to tenant policies.

## Product constraints

Prefix `os_sr_*` with publisher prefix `os`, namespace `sr`; one Solution `os_sr_bso_rs_support`. BSO is coordinator, TA is interviewer. No TA approval workflow. Use Dataverse as sole business state, enforce status transitions server-side, fail closed on availability, maintain idempotency/audit, protect candidate PII and sender identity. Environment auditing currently off, retention pending IT/Compliance: no real data.

## Completion criteria

Provide a concrete artifact + independent verification, or explicit blocker + no-change report. Provide the next meaningful development slice; no infinite dry-run loop or unnecessary return to earlier completed preflight.
