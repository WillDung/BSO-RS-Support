# P0 Slice 2A Stage A Live Preflight Report

**Assessment date:** 2026-11-06

**Classification:** `P0_SLICE_2A_STAGE_A_LIVE_PREFLIGHT_BLOCKED`

**Stop:** `STAGE_A_INCOMPLETE_CONSOLE_LAYER_READBACK`

**Scope:** Authorized DEV read-only reconciliation and local documentation only. Stage B was not started.

## Executive result

The exact VN LMV IT target and unmanaged `os_sr_bso_rs_support` Solution were verified before project resources were inspected. The current Flow is OFF and structurally matches the historical pre-hardening deployment, not the hardened local source. The observed Solution membership, role maps, connection bindings, disabled guards, published Console resources, value-less definitions and aggregate counts match the accepted checkpoint.

Stage A is **not a complete pass**: the unpublished/current Console copies and authenticated effective-served bytes were not independently read in this assessment. An anonymous request to each of the two changed resources and the environment resource redirected to sign-in. The published resource hashes and fail-closed source gate are fresh evidence, but they do not prove all three live layers agree. The current guard package's server-side bytes were also not independently hashed.

The previous version of this report incorrectly concluded that authentication was unavailable. That conclusion was unsupported: both workspace MCP servers responded, an existing authenticated context was available, and fresh tenant reads succeeded. This is a readback-coverage block, **not an authentication block or an observed topology drift**.

The full observation window was **2026-11-06 06:10:39-06:34:08 UTC**. The aggregate count window was **06:24:53-06:25:20 UTC**. These are point-in-time observations, not a transactionally consistent tenant snapshot.

## 1. Target and Solution

| Check | Fresh result |
|---|---|
| Environment and organization | Exact URL, environment ID, organization ID and organization unique name matched the previously verified VN LMV IT checkpoint; identity was not selected by display name alone. Identifiers are intentionally not reproduced here. |
| Solution | Exactly one `os_sr_bso_rs_support`, unmanaged, version `1.0.0.1`; its identity matches the checkpoint. |
| Membership | **66** distinct component type/object pairs; all original **60** and the **6** historical wiring additions remain, with no extras or missing entries. Root behaviors match the checkpoint. |
| Availability root | The `os_sr_avq` entity root is present with `Include Subcomponents` (`rootcomponentbehavior = 0`). |
| Flow membership | The existing `os_sr_avchk` workflow is one of the six wiring additions. |

The earlier unmanaged export established inherited table subcomponents; no fresh export was made in this assessment. The current table description confirms the TA and optional Location lookups, required request fields, and exact Mode and Status Choice values. Lookup cascade settings, AutoNumber format and Memo maximum length were not independently re-read here; the [DEV provisioning report](P0_SLICE_2A_DEV_PROVISIONING_REPORT.md) is historical evidence for those details.

## 2. Live Flow identity, state and definition

Exactly one modern Flow definition has `workflow.name = os_sr_avchk`; its workflow ID matches the historical checkpoint and its Solution membership is confirmed. The Dataverse `uniquename` field is blank, so it must not be presented as a verified nonblank unique-name field. The `description` is `Slice 2A Availability Check`; the local contract uses a different display-name phrase. No rename was performed.

| Property | Fresh result |
|---|---|
| State / status | Draft/OFF: `statecode = 0`, `statuscode = 1` |
| ModifiedOn | `2026-11-05T16:06:28Z` |
| Concurrency evidence | SDK `RowVersion = 13151363`, also returned as `versionnumber`; unchanged on a later read. No HTTP ETag or supported conditional single-Flow update behavior was established. |
| Runs | Dataverse `flowrun` aggregate returned **0** visible/retained rows for this Flow; PAC's run-list command returned no results. This does not prove history beyond retention or access limits. |
| Trigger | Dataverse Added/Create on Pending `os_sr_avq`, Organization scope, run as Flow owner; concurrency **1**. |
| Connectors | Dataverse and Office 365 Outlook, using the two references in section 4. |
| Connector behavior | Seven connector actions use `retryPolicy.type = none`. `FindMeetingTimes_V2` has a `PT2M` timeout. No provider operation was executed. |

### Hashes and structural comparison

The live hash is SHA-256 of the UTF-8 encoding of the **decoded `clientdata` string** returned by Dataverse, not a hash of the enclosing HTTP response. Source-file hashes are over their exact file bytes. For comparison, JSON was parsed with duplicate-key rejection and serialized as UTF-8 with recursively sorted object keys, compact separators, preserved array order and no insignificant structural whitespace; this canonical hash is separate from the exact-byte hash.

| Definition | Bytes | Exact SHA-256 | Canonical JSON SHA-256 |
|---|---:|---|---|
| Current live decoded `clientdata` | 37,575 | `BA19AC8D1D306B0934F3A4B35839BA4041437441064C28D051950C3B898F7A37` | `1B60A8E30C19728F16DBC7EE5F16F7EDD4015010B2F09890D6716580E378F864` |
| Historical pre-hardening source | 68,580 | `F901BAAE0ABC5F2A2ECCF74BF59E76FE05189A6E13BF86A981D6D6E4DBEB8811` | `1B60A8E30C19728F16DBC7EE5F16F7EDD4015010B2F09890D6716580E378F864` |
| Current hardened [source](../solutions/AvailabilityQuery/os_sr_avchk.clientdata.json) | 74,698 | `0E1A1DE9CFECE98440B1EC8B52DCD76648A25826A06BCF36FAFCEFBB39C701B0` | `059106A6B6168313FE19067D81566BBB5BC11B85D3A145B4BCB07FBD251ECB66` |

The live and historical definitions are **structurally identical**; their raw hashes differ because their JSON serialization differs. The live-versus-hardened comparison has **26 sanitized structural differences**, all in `runtimeConfiguration.secureData`: the hardened source adds trigger-output protection and action protection or expands input-only settings to include outputs. Removing only those settings from both parsed definitions makes them identical. Trigger filters, concurrency, expressions, connector operations, references, result writes and retry policies are otherwise unchanged.

For the contract's 32 sensitive actions, the live definition has **19 with no secure-data setting, 5 with inputs only, and 8 with inputs and outputs**. One additional hardened action outside that 32-action inventory also adds protection. The live trigger has no `secureData` setting. Thus the deployed Flow does **not** contain the later run-history privacy hardening. Even after a separately authorized update, action-type retention and actual run-history suppression require the synthetic runtime gates in the [readiness plan](P0_SLICE_2A_PRE_ACTIVATION_READINESS.md); they are not established by source inspection.

The local [Flow contract](../solutions/AvailabilityQuery/availability-flow.contract.json) exact-file SHA-256 is `DF5EEEAD064F0FC0BE2448E854A868E8539CB53C5D58322E53A2D8EAE9FCCC35`.

## 3. Guard package and registrations

- The current package is `os_sr_avqg_pkg` version `1.0.0`; its package-backed sandbox assembly is `os_sr_avqg` version `1.0.0.0` and contains the single handler `os_sr_avqg.ProtectAvailabilityQuery`. The package and assembly are present in the Solution; the handler is included through the assembly.
- There are **zero** registrations for that handler, and therefore zero active guard steps.
- For the Availability Query Create and Update filters, the read returned **zero** entity-specific PreOperation registrations and zero unfiltered Create/Update PreOperation registrations. This does not replace a fresh check for platform or other applicable registrations before a future write.
- Historical build hashes are package `ec596db5b07197f6dc4bf84e135ad6c05daccbed3412635c17057327892fa719` and DLL `296634c9b75ca25977da33b1e623ab32b72495fd33e3c43c3649f33ea5f8ea01`. The current package record identifies a file-backed package, but its binary content was not independently obtained; server byte equality is **not claimed**.

The [registration contract](../solutions/AvailabilityQuery/availability-plugin-registration.contract.json) still omits `executionOrder`. The earlier suggestion of rank **10** for each step remains an **unapproved proposal**. No collision was observed in the bounded registration reads above; all relevant registrations and ordering dependencies must be rechecked immediately before any separately approved registration.

## 4. Connection references

| Reference | Fresh binding evidence |
|---|---|
| `os_sr_avchk_outlook_cr` | Active; Office 365 Outlook connector; binding matches the approved historical DEV connection, which reports `Connected`. |
| `os_sr_avchk_dataverse_cr` | Active; Microsoft Dataverse connector; binding matches the approved historical DEV connection, which reports `Connected`. |

For both connections, the recorded creator and authenticated account matched the active approved DEV-owner identity in a private comparison. No account identifiers, connection parameters or credentials are recorded here. No new connection, consent, permission, license, credential or role assignment was created. This remains `DEV_FUNCTIONAL_IDENTITY_ELEVATED_NOT_SECURITY_ACCEPTANCE`.

## 5. Environment-variable definitions

All seven exact definition identities and types match the provisioning checkpoint. Aggregate readback found **zero non-null defaults** and **zero associated value records**; no value contents were requested.

| Definition | Live Dataverse type | Default/value |
|---|---|---|
| `os_sr_avq_bhrs` | String | None / none |
| `os_sr_avq_durs` | String | None / none |
| `os_sr_avq_lead` | Number | None / none |
| `os_sr_avq_hzn` | Number | None / none |
| `os_sr_avq_exp` | Number | None / none |
| `os_sr_avq_dom` | String | None / none |
| `os_sr_avq_maxc` | Number | None / none |

The offline [configuration contract](../solutions/AvailabilityQuery/availability-environment-variables.json) fixes the timezone to `SE Asia Standard Time`, interval to 15 minutes, horizon to at most 61 days and maximum candidates to 1-200. These are contract constraints, not configured tenant values. The synthetic-mailbox prerequisite was not tested or supplied in this assessment.

## 6. Roles and Candidate Core

All privilege IDs, names and depths were compared with the complete accepted checkpoint maps:

- **BSO:** exactly **65** entries, no missing or extra entries. Availability Query has Create, Read and Append at User depth and no Write, Delete, Assign or Share; TA and Location AppendTo remain Global.
- **Availability Integration:** exactly **4 Global** entries: Availability Query Read/Write and TA/Location Read. No user, team or application-user assignments were returned.
- **Reference Admin:** exactly **20** entries, unchanged; no user, team or application-user assignments were returned.
- **Candidate Core:** package identity, version and historical UTC ModifiedOn match; its package-backed assembly and two types, API identity/settings, all **21** request parameters and **5** response properties match the checkpoint. Server package byte equality is not claimed. A historical retained signed assembly is separate from the package-backed assembly.
- **Legacy guards:** all **50** package-backed `ProtectCandidateCore` registrations match the checkpoint and remain disabled.

No Candidate Core operation was invoked. No `os_`-prefixed custom connector was returned; the live Flow uses only the two standard connector references above. This is not a directory-wide Entra application inventory.

## 7. Console and feature gate

These are SHA-256 hashes of base64-decoded **published Dataverse WebResource content**. All six match the historical published checkpoint; the five non-environment resources also match their authored repository files.

| Published resource | SHA-256 |
|---|---|
| `candidate-console.html` | `b0d3cede68669fc4bc080100a3318d433cd116b159cee32f8d96f20bd086086e` |
| `candidate-console-availability.js` | `97487ef0c2a6ece4185a2b1d17a76804d9b58535cbeaee3c27b0596fd4ae7921` |
| `candidate-console-environment.js` | `58e03dc262b790b7431f34ca5554422fc86f0d62f6e8b6160805a6b2d906335c` |
| `candidate-console.js` | `cb26a8d5a859e9a72b27e25ee8220a4ad5704d4473dd37af0ee7b69ec0d55e53` |
| `candidate-console-policy.js` | `29cbcc97c11a39e9a0d3f0177a3582e2edf96d388796612bee1d3149724d6348` |
| `candidate-console.css` | `6681994a0d57e46ed1b3f0be291556fba37be262f822c8b483d31d00f1130fde` |

The published HTML references the availability module. The published environment resource has no `availabilityEnabled` property, and the published module requires `availabilityEnabled === true` before loading references or creating a query. On the **published content examined**, this gate is false. The environment resource intentionally differs from the repository's unconfigured template.

The ordinary published-resource query and an empty `componentstate = 1` result do **not** substitute for `RetrieveUnpublishedMultiple`. Authenticated effective-served bytes were also not read: anonymous resource requests returned HTTP 302. Therefore current/unpublished = published = served is **not freshly established**, and the effective browser-served gate is not independently verified. No WebResource, app, sitemap or other component was published.

## 8. Aggregate row counts

Only server-side counts were read; no Candidate field values or business rows were retrieved.

| Table | Historical checkpoint | Fresh count |
|---|---:|---:|
| Candidate | 47 | 47 |
| Call Log | 64 | 64 |
| Candidate Status History | 163 | 163 |
| Interview Schedule | 45 | 45 |
| Operation Receipt | 183 | 183 |
| Availability Query | 0 | 0 |

Counts were collected sequentially within the window above. Equal counts do not exclude concurrent updates or offsetting inserts/deletes; no causal claim about unrelated tenant activity is made.

## 9. Offline checks and open decisions

| Check | Result |
|---|---|
| Availability Query static checks | Passed: **168** |
| Availability Query SDK harness | Passed: **520** |
| Solution membership regression | Passed: **19** |
| Flow, Flow contract, registration and environment-variable JSON syntax and duplicate keys | Passed: **4** files |
| Release-source test | **Failed:** the Flow contract `deploymentState` contains a non-secret DEV environment label rejected by the release-neutrality assertion. |
| Production-readiness test | **Failed:** canonical source/root fingerprint differs from the frozen release manifest. |
| Documentation link check and `git diff --check` | Passed after this report update. |

The current canonical Solution source measured **191** files with fingerprint `6fc18176a1b891a417b7c48e14da2a6b7fbc08a0958c1831c022666337afc3d6`; the frozen manifest expects **171** and `fff8b7879c2b756f3a2b1753159135a0dc00a890a20e4445870a0fd23ea984d1`. No Solution source, frozen manifest or pin was changed to conceal either failure.

The Flow contract permits up to two 429 retries honoring `Retry-After`, while the live and authored connector actions use no retries. **Proposal, not approval:** retain zero retries for initial live acceptance; separately review any bounded retry design for deadline, throttling, idempotency and ambiguous timeouts. Separately scope any neutral `deploymentState` wording correction and release-fingerprint decision.

## 10. Decision and next gates

Stage B is **not ready to start** from this incomplete assessment. First obtain authorized read-only evidence for the current/unpublished Console copies and authenticated served bytes, and recheck time-sensitive state. Establish a supported, single-Flow authoring surface and its conditional concurrency behavior; the observed SDK RowVersion alone is not proof of an `If-Match`-protected update. Any material unexpected drift must stop the sequence, not trigger repair.

The missing synthetic mailbox prerequisite, value-less configuration, unapproved guard execution order, undeployed privacy hardening and runtime privacy-verification gates continue to prevent functional activation. The original classification `SLICE_2A_SYNTHETIC_MAILBOX_PREREQUISITE_MISSING` remains the historical prerequisite status; this assessment did not test mailbox availability. Stage B and all activation require separate authorization.

This assessment performed **zero tenant writes**, **zero write retries**, **zero publication calls**, **zero availability or Candidate operations**, and **zero Outlook/calendar/mailbox operations**. Some failed or repeated read-only probes were corrected without a write. No commit or push was performed by this assessment.

## Sources

- [Project Context](PROJECT_CONTEXT.md), [Current State](CURRENT_STATE.md), [Master Production Rules](../MASTER_PRODUCTION_RULES.md), and [Workflow](../WORKFLOW.md).
- [Pre-activation readiness plan](P0_SLICE_2A_PRE_ACTIVATION_READINESS.md), [DEV provisioning report](P0_SLICE_2A_DEV_PROVISIONING_REPORT.md), [Integration Design](INTEGRATION_DESIGN.md), and [Product Decisions](PRODUCT_DECISIONS.md).
- [Flow definition](../solutions/AvailabilityQuery/os_sr_avchk.clientdata.json), [Flow contract](../solutions/AvailabilityQuery/availability-flow.contract.json), [registration contract](../solutions/AvailabilityQuery/availability-plugin-registration.contract.json), [environment-variable contract](../solutions/AvailabilityQuery/availability-environment-variables.json), and [role delta contract](../solutions/AvailabilityQuery/availability-role-delta.json).
- [Availability Query tests](../tests/AvailabilityQuery.Tests.ps1), [SDK test project](../tests/AvailabilityQuerySdk/), [membership tests](../tests/BsoRsSolutionMembership.Tests.ps1), [release-source test](../tests/BsoRsReleaseSource.Tests.ps1), and [production-readiness test](../tests/BsoRsProductionReadiness.Tests.ps1).
