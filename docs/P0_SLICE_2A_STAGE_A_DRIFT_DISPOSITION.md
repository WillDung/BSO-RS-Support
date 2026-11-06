# P0 Slice 2A Stage A drift disposition

**Assessment date:** 2026-11-06  
**Disposition recommendation:** `P0_SLICE_2A_STAGE_A_CORRECTION_REQUIRED`  
**Console token finding:** `CONSOLE_TOKEN_CORRECTION_RECOMMENDED`  
**Browser request finding:** `BROWSER_NON_GET_EFFECT_UNDETERMINED`  
**Official Stage A status:** remains `P0_SLICE_2A_STAGE_A_LIVE_PREFLIGHT_DRIFT_DETECTED`. This offline recommendation is not an acceptance, exception, or deployment authorization.

## Executive decision

Recommend correcting the generated HTML/configuration pair before Stage B rather than accepting an exception. The expected correction is limited to the target-generated `os_/bso/candidate-console.html`: its environment-script query token changes to match the already-published configuration. No canonical source, configuration, JavaScript, Candidate Core, or other resource change is indicated.

The observed authenticated browser session loaded the current configuration bytes and had Availability disabled. This is evidence against stale configuration in that session, not a guarantee about other clients or service-worker cache behavior. The established token mismatch violates the generator's pair invariant and remains a real deployment inconsistency.

The saved browser request evidence identifies three Dataverse POST paths but not their request/response bodies or persisted effects. A fourth Dataverse non-GET and three other non-GET requests remain unidentified. Record the overall effect as undetermined; unchanged aggregate business-row counts do not prove that no writes occurred. This limitation does not, by itself, prevent a separately approved, isolated Flow-only update.

Stage B is **not ready**. In addition to resolving or explicitly approving the Console deviation, no supported single-Flow update method with conditional concurrency has been demonstrated. The synthetic-mailbox prerequisite continues to block functional runtime verification and activation, not offline preparation.

## 1. Scope and evidence

This review uses the existing [Stage A live report](P0_SLICE_2A_STAGE_A_LIVE_PREFLIGHT_REPORT.md), [DEV provisioning report](P0_SLICE_2A_DEV_PROVISIONING_REPORT.md), [pre-activation plan](P0_SLICE_2A_PRE_ACTIVATION_READINESS.md), [Integration Design](INTEGRATION_DESIGN.md), [Product Decisions](PRODUCT_DECISIONS.md), [Project Rules](../PROJECT_RULES.md), and the current repository sources and tests linked below. The Stage A report contains the six resource hashes, authenticated application observations, historical Flow readback, and the original target-identity verification.

No new PAC, MCP, Web API, or tenant request was made for this disposition. No browser navigation, request replay, snapshot recovery, Flow update, publication, or other tenant operation was performed. The prior authenticated app inspection's automatic requests are retained as observations, not reclassified from unavailable payloads.

## 2. Cache-token root cause

| Evidence layer | HTML token | HTML SHA-256 | Configuration SHA-256 |
|---|---|---|---|
| Authored template / unconfigured configuration | `39135f67e4c9` | `b0d3cede68669fc4bc080100a3318d433cd116b159cee32f8d96f20bd086086e` | `39135f67e4c96959bc0cb983c3b986bdfed1966df34432713180fe11ac0d6c1f` |
| Historical accepted, current published, current/unpublished, and observed app-served bytes | `39135f67e4c9` | `b0d3cede68669fc4bc080100a3318d433cd116b159cee32f8d96f20bd086086e` | `58e03dc262b790b7431f34ca5554422fc86f0d62f6e8b6160805a6b2d906335c` |
| Generator-expected target pair | `58e03dc262b7` | `699afe50dc3a1bb898ddb3cac301edc36b3bb7a861429dfad5e50b5158403e25` | `58e03dc262b790b7431f34ca5554422fc86f0d62f6e8b6160805a6b2d906335c` |

The expected HTML hash was reproduced offline by substituting the configuration hash prefix into the canonical HTML. A byte comparison after normalizing only that token confirmed that the token is the **only** difference. The six authored, published, unpublished, and served resource hashes are recorded in the [Stage A report](P0_SLICE_2A_STAGE_A_LIVE_PREFLIGHT_REPORT.md#7-console-and-feature-gate).

The [historical runtime-wiring journal](P0_SLICE_2A_DEV_PROVISIONING_REPORT.md) records that its HTML PATCH added only the Availability panel and its script reference; it does not record a configuration-token substitution. That scoped HTML update therefore retained the pre-existing authored token. It is the supported proximate cause of the accepted mismatch. The report does not establish the author's intent to preserve that token.

The canonical [generator](../scripts/New-BsoRsCandidateConsoleEnvironmentConfig.ps1) writes target-specific configuration and matching HTML to external output paths; it does not rewrite the canonical HTML template. The normal refresh path in [Deploy-BsoRsCandidateConsole.ps1](../scripts/Deploy-BsoRsCandidateConsole.ps1) requires the externally generated HTML and verifies that it differs from source only by the configuration-hash token. Its publish-only path rejects replacement content, so publishing existing bytes alone cannot repair the mismatch. The historical wiring journal records a direct resource PATCH and scoped publish, not invocation of this generator/refresh pair. Consequently, there is no evidence that the generator intentionally preserves the stale token; the deployment change simply did not apply its generated HTML output.

### Cache semantics and evidence limits

HTTP caches normally key responses by the request target URI; a changed query token therefore distinguishes the environment-script URL ([RFC 9111, cache keys](https://www.rfc-editor.org/rfc/rfc9111.html)). For the Service Worker Cache API, `Cache.match()` defaults `ignoreSearch` to `false`, but a worker can explicitly ignore the query or implement custom matching ([MDN Cache.match](https://developer.mozilla.org/en-US/docs/Web/API/Cache/match)). No service-worker implementation was found in the inspected Candidate Console sources. The observed resource was served through a service worker, and the response at the old token contained the current configuration hash. That proves only what this browser session received; it does not establish how every client or service worker handles the new token.

In the observed session, `availabilityEnabled` was absent and all eight Availability controls were disabled. No stale configuration was observed there. This does not make the mismatch an accepted exception or prove freshness for other sessions.

## 3. Recommended correction

**Recommendation:** `CONSOLE_TOKEN_CORRECTION_RECOMMENDED`.

If separately authorized, make a one-resource, target-specific deployment correction:

1. Keep the canonical HTML source and environment configuration unchanged. Generate the paired HTML outside the repository from the already-verified DEV configuration; the expected token is `58e03dc262b7`, and the expected HTML SHA-256 is `699afe50dc3a1bb898ddb3cac301edc36b3bb7a861429dfad5e50b5158403e25`.
2. Update only the existing `os_/bso/candidate-console.html` content with that generated output, then publish only that WebResource through an approved exact-component mechanism. The existing helper's old resource inventory is not sufficient evidence that it can safely perform this update unmodified. No configuration PATCH, panel/JavaScript change, `srapp` or sitemap publication, cache clearing, or service-worker change is indicated.
3. Use a single dispatch with zero retries. If its result is ambiguous, read back before any further action; do not automatically repeat the PATCH or publish.

This is a proposal, not authorization. The HTML continues to reference the same environment, policy, main Console, and Availability scripts; only the environment-script URL token changes. Candidate Core source and API behavior are not affected by this HTML-only delta.

**Post-correction verification plan:** independently read current/unpublished and published HTML; require the expected hash; compare the exact target-generated body to the canonical template with only the token transformed; verify the environment resource remains at the expected configuration hash; verify the other five resources remain unchanged; then, only with a separately approved browser-observation method, compare authenticated normal-app served bytes and confirm the Availability gate remains false. Do not equate definition equality with served-byte equality.

**Tests to add or confirm before correction:** extend `CandidateConsoleConfiguration.Tests.ps1` to assert that generated HTML equals source HTML except for the one version token and that the token is derived from the exact generated configuration bytes. Run `CandidateConsole.Tests.ps1` to protect script order, panel behavior, and the unchanged Candidate Core path. The current generator test already checks that the generated token matches the configuration hash.

An exception could be considered for an isolated Flow-only change while Availability remains off, because the captured app session served current configuration and no stale value was observed. It is **not recommended**: other clients and worker cache matching are unverified, the helper's generated-pair invariant is violated, and no owner-approved exception exists. Leaving a mismatch in place also complicates the next independent Console reconciliation.

## 4. Browser non-GET request finding

**Finding:** `BROWSER_NON_GET_EFFECT_UNDETERMINED`.

The [Stage A report](P0_SLICE_2A_STAGE_A_LIVE_PREFLIGHT_REPORT.md#7-console-and-feature-gate) records one permitted Candidate-list GET in each of two instrumented loads. In the second load, four Dataverse non-GET requests and three other non-GET requests were counted. A subsequent passive audit recorded three Dataverse POST endpoint names. The retained evidence does not establish that these three names account for the same four-request set. Request/response bodies, status codes, correlation IDs, server-side operation records, and persistence evidence were not retained.

| Observed request | Category supported by evidence | Mutation capability / execution evidence | Limit |
|---|---|---|---|
| `POST /api/data/v9.0/msdyn_ReportToMonitoringHub` | Platform monitoring/telemetry, inferred from endpoint name | A POST to this path was observed. The name suggests a report operation, so a telemetry side effect cannot be excluded. Durable persistence is not independently established. | No operation metadata, body, response, or matching operation record was retained. |
| `POST /api/data/v9.0/GetRecentItems` | Platform/session operation, retrieval-like by name | Request dispatch was observed. POST alone does not establish mutation; neither read-only semantics nor absence of side effects is verified. | No operation metadata, body, response, or matching operation record was retained. |
| `POST /api/data/v9.0/GetCopilotSettingsForEnvironment` | Platform/environment-configuration operation, retrieval-like by name | Request dispatch was observed. No business-table mutation is shown, but non-mutation is not independently established. | No operation metadata, body, response, or matching operation record was retained. |
| Fourth Dataverse non-GET | Dataverse endpoint category only | Counted during the second instrumented load. Its endpoint and mutation capability are unknown. | Exact request metadata was not preserved. |
| Three other non-GET requests | Other, unclassified | Counted during the second instrumented load. Their endpoints and effects are unknown. | Exact request metadata was not preserved. |

The prior audit observed no URL containing `os_sr_cact` in the second capture. That does not rule out a business effect through another endpoint or a batch request. No business operation was intentionally clicked or invoked. The unchanged aggregate row counts in the earlier Stage A window are not evidence that these requests had no effect. No automatic snapshot was recovered or inspected for this review.

The endpoint labels above are not substitutes for operation definitions. Because the method/path evidence does not establish request semantics or persistence, the combined result remains `BROWSER_NON_GET_EFFECT_UNDETERMINED`, not “no mutation” and not “business mutation detected.”

## 5. Stage A disposition and Stage B gate

**Disposition recommendation:** `P0_SLICE_2A_STAGE_A_CORRECTION_REQUIRED`. Keep the official Stage A classification `P0_SLICE_2A_STAGE_A_LIVE_PREFLIGHT_DRIFT_DETECTED` unchanged. The cache mismatch is deterministic and correctable, but no correction or exception has been approved. The non-GET uncertainty remains an audit limitation; it does not independently block a future Flow-only update if that update is separately approved and uses an isolated, verified control path.

The browser evidence does not justify declaring that the earlier requests were harmless. It also does not establish a Candidate business mutation. Their uncertain effects should be preserved as a limitation, not used as a claim of zero writes.

### Recorded readiness facts (historical; revalidate before a future write)

- Live `os_sr_avchk` was read as Draft/OFF; its decoded definition was structurally identical to the historical pre-hardening source. The local hardened source differs in 26 structural locations, all within `runtimeConfiguration.secureData`.
- The recorded Flow `RowVersion` was `13151363`. This is a point-in-time value, not a current concurrency token.
- Solution membership was 66.
- The guard package/type existed with zero registrations/steps.
- Seven environment-variable definitions had no values.
- Availability Integration remained unassigned.
- Candidate Core topology was unchanged; all 50 legacy guards remained disabled.
- Availability remained disabled and zero Availability Query rows were reported.

These are historical Stage A observations, not fresh assertions about current tenant state. The missing synthetic-mailbox prerequisite remains a functional-runtime blocker; it does not by itself prevent an offline review of a Flow definition while the Flow remains OFF.

### Stage B technical readiness checklist

Stage B remains blocked until there is a separate authorization and all of the following are satisfied:

1. **Resolve the Console drift:** complete the one-resource correction and readback above, or obtain a documented owner-approved exception that explicitly accepts the generated-pair deviation and its cross-client cache uncertainty. Neither is granted by this report.
2. **Revalidate immediately before any Flow write:** reconfirm the exact environment and organization, unmanaged Solution, 66-member baseline, target Flow identity and OFF state, current definition/version, zero guard steps, value-less definitions, unassigned Integration role, unchanged Candidate Core, disabled legacy guards, zero Availability Query rows, and the disabled feature gate. Stop on any unexpected drift.
3. **Prove the update surface:** the supported ALM candidate is a solution-aware Flow carried through Power Platform solution export/import; Microsoft describes Solutions as the ALM mechanism for Power Apps and Power Automate ([Solution concepts](https://learn.microsoft.com/en-us/power-platform/alm/solution-concepts-alm)). However, the evidence reviewed here does not demonstrate a package containing only the existing Flow, a package import that cannot disturb other components, or an import-level optimistic-concurrency precondition. Treat it as a candidate, not an approved method. Verify exact package component closure and OFF-state behavior, and identify the supported concurrency mechanism before use. Do not assume a generic `workflow` PATCH, PAC command, or full-Solution import is a conditional single-Flow update.
4. **Prove concurrency control:** the selected surface must document and expose an ETag/`If-Match` or equivalent optimistic-concurrency precondition for this Flow update. Re-read the current version immediately before dispatch and bind the update to it. `RowVersion = 13151363` alone is not proof of a supported conditional update. If no supported precondition exists, do not write.
5. **Prepare the exact delta:** compare the current live definition to the approved local hardening and require the only changes to be the intended `secureData` settings. Preserve trigger, concurrency, expressions, connector references/actions, retry settings, and terminal-write behavior. Keep the Flow OFF.
6. **Dispatch once:** use zero retries. On a timeout, lost response, precondition failure, or ambiguous result, stop and perform read-only reconciliation before considering any action. Do not replay an uncertain update.
7. **Reconcile independently:** verify the same Flow identity and Solution membership, OFF state, exact expected `secureData` delta, unchanged trigger/actions/references/retry policies, zero new runs, unchanged 66-member Solution, zero guard steps, unchanged roles/configuration/Candidate Core/50 disabled guards, zero Availability Query rows, and `availabilityEnabled = false`.
8. **Handle failure without an automatic rollback:** retain a protected pre-update definition/hash for the authorized change record. If the readback is ambiguous or differs unexpectedly, keep the Flow OFF and stop. A compensating restore requires separate approval and the same supported conditional-concurrency control; never retry or restore blindly.
9. **Keep activation separate:** do not activate the Flow or guard steps. Synthetic mailboxes, value-bearing configuration, and bounded synthetic privacy/runtime verification require separate prerequisites and authorization.

## 6. Offline contract closure recommendations

No canonical Solution source, contract, frozen manifest, release pin, or checksum was changed in this review.

| Difference | Minimal recommendation | Regression coverage |
|---|---|---|
| Contract permits up to two `429` retries honoring `Retry-After`, while all **7** Flow `OpenApiConnection` actions use `retryPolicy.type = none`. | Preserve the current conservative no-retry implementation. Obtain an owner/technical decision before changing the contract or Flow. If no retries are approved, update only the contract wording to state that `429` is surfaced as the safe throttled failure and no connector action retries automatically. If retries are desired, separately prove connector support, bounded deadline/`Retry-After` behavior and ambiguous-outcome safety; never retry the terminal result write. | Extend `AvailabilityQuery.Tests.ps1` to assert exact contract/implementation agreement and recursively inspect all connector actions, including the terminal write. Add bounded 429/deadline cases to an approved offline connector-policy harness; do not test against the live provider here. |
| Registration contract omits `executionOrder`; rank 10 was only an unapproved proposal. | Do not insert rank 10 or register steps. Record ordering as an explicit open decision / registration gate in the contract. Before any separately approved registration, approve the numeric order, reconcile all applicable existing steps for collisions, and encode the approved order in the contract and exact registration request. | Extend `AvailabilityQuery.Tests.ps1` to ensure the registration contract marks ordering unresolved and is not treated as executable until approved. Once approved, assert both exact ranks and a collision-free, fresh preflight before dispatch; re-read actual registered ranks afterward. |
| Flow contract `deploymentState` contains a DEV environment label and fails the ReleaseSource neutrality assertion. | Replace the environment-specific sentence with release-neutral wording such as: `This contract describes local source; deployment status is recorded in the dated environment reconciliation report.` Keep factual DEV status in dated documentation, not frozen canonical contract source. | Update the corresponding `AvailabilityQuery.Tests.ps1` assertion; run `BsoRsReleaseSource.Tests.ps1`. Do not bypass its gate. Reconcile canonical fingerprints separately and do not rewrite frozen pins to force a pass. |

The release-source check currently fails on its DEV-target-neutrality assertion. Production-readiness currently fails on the canonical source/root fingerprint comparison: **191** current canonical source files / fingerprint `6fc18176a1b891a417b7c48e14da2a6b7fbc08a0958c1831c022666337afc3d6` versus frozen **171** / `fff8b7879c2b756f3a2b1753159135a0dc00a890a20e4445870a0fd23ea984d1`. Preserve this drift for a separately approved source/fingerprint reconciliation; do not change manifests or pins here.

## 7. Validation

| Check | Result |
|---|---|
| `pwsh -NoLogo -NoProfile -File .\tests\CandidateConsoleConfiguration.Tests.ps1` | Passed: **21** |
| `pwsh -NoLogo -NoProfile -File .\tests\CandidateConsole.Tests.ps1` | Passed: **78** |
| `pwsh -NoLogo -NoProfile -File .\tests\AvailabilityQuery.Tests.ps1` | Passed: **168** |
| JSON syntax and duplicate-key validation for five reviewed Availability Query JSON files | Passed: **5** files |
| `pwsh -NoLogo -NoProfile -File .\tests\BsoRsReleaseSource.Tests.ps1` | Failed at `Canonical release source contains no DEV target configuration or credential-like values`; this is the documented DEV-label neutrality issue. |
| `pwsh -NoLogo -NoProfile -File .\tests\BsoRsProductionReadiness.Tests.ps1` | Failed at `Verify the frozen canonical source and root-component fingerprints`; the 191-versus-171 drift remains unchanged. |
| Documentation links | Passed: all **154** relative file paths resolve and all local section anchors added by this disposition resolve. An extended check also found one pre-existing stale `DATA_MODEL.md` heading fragment in untouched `CURRENT_STATE.md` text; it was not changed as unrelated scope. |
| `git diff --check` | Passed after the documentation updates. |
| Initial ad hoc HTML-hash command | Failed because this PowerShell version's `Get-FileHash` does not accept `-InputObject`; the check was corrected to hash UTF-8 bytes directly and reproduced the expected HTML hash. |

No failed assertion was weakened. No source or frozen release artifact was modified.

## 8. Tenant operation inventory and next boundary

For this disposition review: **0 new tenant reads, 0 intentional tenant writes, 0 write retries, 0 publications, 0 browser navigations, and 0 Flow or provider executions**. Earlier automatic browser POSTs and their unresolved effects are described in section 4 and the [Stage A live report](P0_SLICE_2A_STAGE_A_LIVE_PREFLIGHT_REPORT.md#7-console-and-feature-gate). No claim of zero total effects from those earlier requests is made.

The next executable boundary is a separate authorization decision: approve or reject the one-resource Console correction, then separately authorize the bounded Stage B Flow update only after a supported update method and conditional-concurrency behavior are demonstrated. This report performs neither action. No Stage B deployment, activation, commit, or push is authorized.
