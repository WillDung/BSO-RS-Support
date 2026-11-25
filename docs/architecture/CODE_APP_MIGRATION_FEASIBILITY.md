# Power Apps Code Apps Migration Feasibility

## Executive decision

**Conditional GO for an isolated, mock-only feasibility prototype in an approved nonproduction environment. NO-GO for enabling Code Apps in VN LMV IT, replacing any `srapp` feature, or connecting a Code App to Candidate/Schedule operations at this time.**

Microsoft documents Code Apps as a managed platform for code-first web applications, including React, Dataverse, Power Platform connectors, and solution-aware publishing. That establishes product-level compatibility, not target-environment readiness. The environment feature flag and licensing were not verified; the local Code Apps CLI and SDK are absent; and the Code App navigation, selected-record context, private Candidate Core API binding, and production frame/CSP behavior are unproven.

The recommended approach is staged and non-disruptive: retain the model-driven `srapp` as the production shell and Dataverse as business authority; first prove a separate React/TypeScript Code App with synthetic fixtures and a mock availability adapter. Do not migrate the Candidate Console wholesale. For an interface that must remain inside `srapp` and receive selected-record context, continue evaluating the existing Custom Page or the separate model-driven Generative Pages path until Code App launch and context behavior are explicitly verified.

No application, Flow, environment setting, business record, security role, or solution was changed for this assessment. No package was installed, no provider was called, and no Candidate or Schedule operation was executed.

## 1. Current architecture and evidence

### Verified LIVE metadata

The latest published reconciliation in [Current State](../CURRENT_STATE.md#phase-2-custom-page-and-availability-flow-reconciliation-2026-11-20) and [Recruitment Dashboard](../RECRUITMENT_DASHBOARD.md#fresh-live-bridge-and-page-reconciliation-2026-11-20) records the current Console baseline:

| Component | Published version | SHA-256 |
|---|---:|---|
| Candidate Console HTML | `15695115` | `11e87c73005cdae155ec2e43e453e3b484815714a63638d2569575965a713e65` |
| Candidate Console JavaScript | `15695110` | `94fc532e7c85a0b20e08a1edf31105cafc4205440b707df5159508bfd8fd0719` |
| Candidate Console CSS | `14754315` | `6681994a0d57e46ed1b3f0be291556fba37be262f822c8b483d31d00f1130fde` |

These are the last reconciled live hashes, not a new served-byte check performed for this report. The live `srapp` model-driven app was present in the read-only app inventory. A read-only generated-page listing for `srapp` returned **no generated pages**. A standalone Code Apps inventory was not obtained because the Code Apps `pa` CLI is unavailable locally; the absence of a Code App link in the `srapp` sitemap does not establish that no standalone Code App exists in the environment.

Read-only Dataverse Custom API metadata in this assessment confirmed `os_sr_cact` (“Apply Candidate Action”) is published, private, an action (not a function), and requires `prvReados_sr_cand` to execute. Its metadata has 25 request parameters and 11 response properties, including `CreatedCandidateId` and `CandidateNumber`. `CreateCandidate` is an `ActionType` value sent to this API; it is not a separate endpoint. Do not treat the API's execute privilege as Candidate Create authorization. The backend additionally binds policy to the exact organization and checks the caller's effective `prvCreateos_sr_cand` privilege for NORMAL Create. Preserve that boundary and the existing SingleUserDev isolation behavior. See [Candidate Core authorization](../../solutions/CandidateCore/NormalCreateAuthorization.cs), [operation contract](../../solutions/CandidateCore/Operation.cs), and the [Custom API metadata](../../solutions/customapis/os_sr_cact/customapi.xml).

The current model-driven sitemap contains Candidate Management and Recruitment Dashboard WebResources plus TA Directory, Positions, Candidate Sources, and Locations entity pages; see [srapp sitemap source](../../solutions/AppModuleSiteMaps/srapp/AppModuleSiteMap.xml). It does not contain a Code App or a generated page. The sitemap source is repository evidence; the deployed app/navigation baseline is described in the live reconciliation above.

### Repository source and documented live contracts

| Area | Reusable today | Boundary or gap |
|---|---|---|
| Candidate Console | HTML/CSS and a large vanilla JavaScript WebResource. It resolves `Xrm` from the model-driven app, uses model-driven organization context, and calls the Dataverse Web API. See [Console JavaScript](../../solutions/CandidateConsole/WebResources/os_/bso/candidate-console.js), [HTML](../../solutions/CandidateConsole/WebResources/os_/bso/candidate-console.html), and [CSS](../../solutions/CandidateConsole/WebResources/os_/bso/candidate-console.css). | It is not a React/TypeScript component package. Code Apps should not be assumed to provide the `Xrm` global or the current same-origin Web API route. Port UI and validation behavior deliberately; do not copy the WebResource shell unchanged. |
| Candidate Core | `os_sr_cact` and its synchronous plug-in implement the authorized Candidate workflow, correlation/idempotency, Candidate Number response, and server-side authorization. | Keep authoritative Candidate mutations behind the existing business operation. A Code App must not use generated table `create`/`update` methods as a shortcut. Compatibility of the private API with the Code Apps generator has not been tested. |
| Dataverse model | Candidate `os_sr_cand`, Interview Schedule `os_sr_intv`, TA Directory `os_sr_ta`, Location `os_sr_loc`, Availability Query `os_sr_avq`, and related Call, Status History, and Operation Receipt tables are documented in [Data Model](../DATA_MODEL.md). Candidate and Schedule lookups and primary keys were verified as metadata in the latest Phase 2 reconciliation. `os_sr_avq` has TA, optional Location, mode, interval, and result fields, but deliberately has no Candidate or Interview Schedule lookup. | This is metadata/schema evidence, not proof of effective record-level access for a Code App connection. Do not read Candidate business rows for a feasibility prototype. |
| `ATSuggAvailabilityBridge` | Existing published Flow has a Power Apps V2 trigger and expects a JSON string containing `roomEmail`, `taEmail`, `startDateTime`, and `endDateTime`. | It has no mode or correlation input and requires both mailbox strings. The HTTP target implementation and end-to-end calendar selection are not visible in the verified contract. It does not establish ONLINE TA-only availability and is not suitable for the pilot. |
| `os_sr_avchk` | The separate Flow contract resolves TA and, for Onsite, Location from Dataverse; it uses Office 365 Outlook `Find meeting times (V2)` and writes a bounded result through `os_sr_avq_complete`. The Flow definition was listed as Published in the latest reconciliation. | Effective on/off state has conflicting historical/source claims, and connector identity, DLP, result transport, and runtime behavior are not accepted. It is a Dataverse-row-triggered Flow, not a Power Apps-triggered instant Flow. Do not invoke it in the pilot. See [availability Flow contract](../../solutions/AvailabilityQuery/availability-flow.contract.json) and [Integration Design](../INTEGRATION_DESIGN.md). |
| Existing Round 1 Custom Page | `os_atsugground1availability_4d2f7` is retained in the Solution. | The latest reconciliation records no `Param()` call, no Candidate/Schedule data source, and no Dataverse `DatabaseReferences`. It is not currently bound to Candidate Management context. Create/Reschedule/Cancel and provider booking remain incomplete. |

No Candidate or Schedule business records were read for this assessment.

## 2. Code Apps prerequisites and target verification

Microsoft Learn documents these prerequisites and capabilities:

| Requirement | Assessment |
|---|---|
| Environment feature | An environment administrator or Power Platform administrator must enable **Power Apps code apps** under the environment's Product/Features settings; environment-group rules can also govern it. **VN LMV IT enablement is unverified.** The Admin Center page redirected to sign-in and did not expose settings; the `env_list-settings` tool call returned a workflow inventory, not the feature flag. No setting was changed. |
| Developer toolchain | Official prerequisites include an IDE, LTS Node.js, npm, Git, and the Code Apps `pa` CLI. Locally, Node `26.13.1` reports LTS codename `Lithium`, npm `12.2.1`, Git `2.56.1`, and PAC CLI `2.13.1` are present. The separate `pa` command is not installed. |
| Client SDK | Microsoft documents `@microsoft/power-apps` and requires version `1.1.1` or later for the documented Dataverse-action and Flow integration. No Code Apps project, `power.config.json`, or local/global `@microsoft/power-apps` package was found. No dependency was installed. |
| User licensing | End users need Power Apps Premium, pay-as-you-go, App Pass, auto-claim, or qualifying Dynamics use rights. **Target-user entitlements and environment capacity/billing were not checked.** |
| Environment permissions | Makers need access to the environment, app/solution, operation, and any underlying connector connections. Code App sharing grants play/edit access; sharing is not a Dataverse privilege grant. Effective maker, user, connector, and table/API permissions for a Code App are unverified. |
| Dataverse support | The documented client library supports Dataverse tables, CRUD, lookups, paging, and generated services. The CLI can generate a service for a Dataverse action/function. This makes the data/API surface technically plausible, but does not establish access to this environment's private `os_sr_cact` API or its precise runtime authorization behavior. |
| Authentication and authorization | The managed host provides Microsoft Entra authentication/authorization. Dataverse table/API privileges and connector connection identity remain distinct. Preserve the existing Candidate Core server checks; do not infer that app sign-in, API execute privilege, or a Flow-owner connection grants Candidate Create. |
| DLP and Conditional Access | Code Apps support managed-platform DLP enforcement, sharing limits, and Conditional Access capabilities. This does **not** prove which policies apply to this environment, its Flow connections, or a future app. IT/security owners must verify applicability and approve any required policy. |
| ALM | `pa app push` publishes a Code App and accepts `--solution-id`; `pa app share` controls app access. The reviewed CLI reference documents no Power Platform Git integration for Code Apps. No app ID, Code App solution membership, connection references, or promotion pipeline was verified for this project. |

The installed PAC CLI is not the Code Apps `pa` CLI. The product being generally documented and the machine having PAC installed do not establish that the target environment can host a Code App.

## 3. Confirmed compatibility, blockers, and unknowns

### Confirmed from official documentation

- Code Apps support code-first single-page applications, including React, and the Power Apps client library generates typed models/services for connected sources.
- Dataverse actions/functions can be added as generated services. App code can therefore be designed to call an approved server operation instead of directly mutating protected business tables.
- Code Apps can use solution-aware Power Automate flows only when they are **instant flows using a Power Apps trigger**. Scheduled and automated flows, and instant flows using other triggers, are not supported by the documented Code Apps Flow integration.
- Code App assets are served from a publicly accessible endpoint without IP-based restrictions. Do not put candidate data, secrets, or tenant configuration in compiled assets. Microsoft recommends Conditional Access for location-based access controls.
- Secure implicit connections are not supported. Connector consent and the actual connection identity must be reviewed.
- The Code Apps local-development instructions require Local Network Access permission for public-origin pages calling localhost; when an iframe is used for that local scenario, the documented iframe attribute is `allow="local-network-access"`.
- The documentation reviewed does **not** establish a supported production iframe/CSP configuration for embedding a hosted Code App inside this model-driven `srapp`, nor a selected-Candidate deep-link parameter contract. Do not treat Custom Page `entityName`/`recordId` parameters as Code App parameters.

### Exact blockers and next owner actions

| Blocker | Evidence | Owner action before proceeding |
|---|---|---|
| Code Apps not verified enabled | Admin Center session did not expose target settings; no reliable feature-flag read was available. | Environment/Power Platform admin confirms feature state and any environment-group rule. Enable only in an explicitly approved nonproduction environment. |
| License and maker rights unknown | Microsoft licensing prerequisites are documented, but no user entitlement or capacity check was made. | Power Platform licensing/environment owner confirms the pilot users' license, capacity, and maker permissions. |
| Missing local Code Apps tooling | `pa` and `@microsoft/power-apps` are absent; there is no app project. | Development owner provisions the supported CLI/SDK in an isolated project after the environment is approved. |
| Private Custom API generation unproven | Live `os_sr_cact` is `isprivate=true` and uses `prvReados_sr_cand`; the `pa` generator was unavailable locally. | Prove generated-service discovery/call compatibility in nonproduction without invoking a Candidate mutation. Do not make the API public or broaden its execute privilege as a workaround. Keep the backend's effective Candidate Create check. |
| Candidate/Schedule launch context unsupported/unverified | Current `srapp` is a model-driven app; existing Console uses `Xrm`; existing Custom Page's documented record context is not a Code App contract. | App owner/Power Platform architect documents and tests a supported launch, route, and return path. Pass IDs only; re-read and validate access and Candidate/Schedule linkage in Dataverse. Do not place Candidate name/email in a URL or treat an ID as authorization. |
| Embed/CSP behavior unverified | Public hosting and local iframe Local Network Access are documented; production `srapp` frame policy is not. | Security/platform owner verifies the supported embedding or navigation model and applicable CSP/frame restrictions. Until then, treat a Code App as a separately launched application. |
| Availability path is not pilot-ready | `ATSuggAvailabilityBridge` lacks mode/correlation and requires both mailboxes. `os_sr_avchk` is a separate row-trigger Flow with unresolved effective state and unaccepted runtime/identity/DLP. | Flow/identity/security owners reconcile effective Flow state, connector identity, DLP, request/result contract, and runtime acceptance. Keep actual provider calls disabled in the initial pilot. |
| Privacy/operations controls not established for a Code App | Existing repository controls distinguish business history, environment audit policy, DLP, connector identity, retention, and incident ownership. | IT/privacy/security owners confirm applicable audit, retention, data minimization, DLP, monitoring, incident owner, and release/change controls. Code Apps platform support is not approval evidence. |

## 4. Migration options

| Option | Effort and maintainability | Security and integration | Deployment and ability to preserve live features |
|---|---|---|---|
| **A. Keep model-driven app; migrate UI incrementally to React WebResources** | Medium UI/build work. React can improve component structure, but it remains a WebResource and requires an explicit bundle/version discipline. Existing HTML/JS/CSS are not already React components. | Best continuity with current `Xrm`, selected-record context, Candidate Core calls, and model-driven authorization. Still must avoid direct protected-table mutations and keep connector identity separate. | Lowest platform change: retain `srapp`, publish only changed WebResources through the existing guarded process, and restore prior source/assets if needed. Does not deliver a Power Apps Code App. |
| **B. Incremental standalone Power Apps Code App** | Highest initial integration/tooling effort; potentially strong long-term React/TypeScript organization with generated service types and independent UI tests. | Entra-managed host and connectors are a good product fit. However, Code App context/iframe behavior in `srapp`, private API generation, per-user permissions, public asset hosting, DLP, and connection identity need proof. | New app/solution/connection/sharing lifecycle and `pa app push`; platform Git integration is not supported. A separate prototype can leave live `srapp` untouched, but wholesale replacement is not ready. |
| **C. Canvas/Custom Page or model-driven Generative Pages** | Canvas/Custom Page uses Studio/Power Fx; it is not a React migration. The separate `pac model genpage` path supports TypeScript page source and model-driven app attachment, but it is a different product/lifecycle from Code Apps. | More naturally fits in-app navigation. Microsoft documents Custom Page navigation with one record context (`entityName` + `recordId`). The current Custom Page is unbound, and generated pages are not present in `srapp`; each still needs authorization, connector, DLP, and privacy validation. | Could preserve model-driven shell and context with less navigation uncertainty. It requires owner Studio or the supported generative-page tooling and a separate ALM/rollback proof. A read-only `pac model genpage list` for `srapp` returned no pages. |

**Interpretation:** If the requirement is a React/TypeScript application, Option B is viable as an isolated proof-of-concept, not as the next production release. If the requirement is a booking view launched from a selected Candidate inside `srapp`, Option A or C has the more direct integration path until Code App context and embedding are demonstrated.

## 5. Recommended target architecture

1. Keep `srapp`, Candidate Core, current WebResources, the Custom Page, and Flows unchanged during the pilot. Dataverse remains the authority for Candidate and Schedule state.
2. Create a separate Code App only in an approved nonproduction environment. Use React/TypeScript, a pinned lockfile, generated Dataverse services for explicitly approved reads, and an isolated solution/app identity. Do not place tenant-specific values or secrets in the bundle.
3. Begin with synthetic in-memory fixtures. Define a typed context contract (`operation`, `candidateId`, optional `scheduleId`) as an untrusted navigation hint. Before any future display or mutation, re-read only the authorized Dataverse records and verify state, Candidate/Schedule relationship, active references, and caller access. Do not put Candidate name, email, TA mailbox, or Room mailbox in the URL.
4. Keep Candidate Create and workflow transitions behind `os_sr_cact` and its existing server authorization/idempotency. Do not use the generated Dataverse table `create`/`update` services for Candidate or Schedule mutations. Do not weaken API privacy or execute privileges to make code generation convenient.
5. Define an availability adapter interface, but use a deterministic mock implementation in the pilot. Do not invoke `ATSuggAvailabilityBridge`, `os_sr_avchk`, Outlook, Graph, or Teams. A later provider adapter must have a separately accepted identity, DLP, idempotency, error, and reconciliation contract.
6. Treat Create/Reschedule/Cancel as disabled in this pilot. The prototype proves presentation, context validation, state behavior, and packaging only; it is not booking acceptance.
7. Prefer a separately launched app for the first Code App proof. Add a `srapp` entry or iframe only after the platform owner proves a supported launch path, context handling, frame/CSP behavior, and return-to-list experience.

## 6. Isolated booking pilot plan

### Scope and interface contracts

- **Candidate context:** synthetic Candidate ID and operation enum; optional synthetic Schedule ID for Reschedule/Cancel. The UI displays only fixture data until an authorized, read-only record-binding test is separately approved.
- **Availability request:** interview type (`ONLINE`/`OFFLINE`), TA reference ID, optional Location ID (required only Offline), date/interval, and a client correlation ID. No mailbox strings are accepted from the UI.
- **Availability result:** explicit `Pending`, `Available`, `Unavailable`, and `Failed` states; slots use canonical UTC intervals. Any change to date, type, TA, or Location invalidates the displayed result.
- **Provider:** mock only. `ONLINE` mock request contains TA only; `OFFLINE` mock request contains TA plus Room. Neither branch calls a real connector.
- **Mutation:** no Candidate/Schedule writes, no calls to `os_sr_cact`, no invitations, and no events. Create/Reschedule/Cancel controls remain disabled or clearly marked as prototype-only.

### Acceptance checks

1. App initializes, runs locally, builds, and publishes only to the approved isolated environment; the main `srapp` sitemap and current resources remain unchanged.
2. Invalid/missing context, unsupported operation, stale/mismatched Schedule-to-Candidate context, and denied Dataverse access fail closed without showing record data.
3. ONLINE hides/does not request a Room; OFFLINE requires a Location. Synthetic mock results cover Pending, Available, Unavailable, Failed, malformed response, and stale-result invalidation.
4. Automated and manual network/log inspection confirms no provider endpoint, mailbox address, Candidate/Schedule mutation, invitation, or calendar event is sent.
5. App permission/sharing tests distinguish app access from Dataverse table/API rights. A caller lacking Candidate Create must not obtain a mutation path through the Code App.
6. A prior published prototype build can be restored using the documented release procedure before any owner considers integration with `srapp`.

## 7. Rollback and release controls

There is no Code App deployment to roll back from this assessment. For a future isolated pilot:

- Keep the prototype in a separate source folder/branch and solution; never stage it as a replacement for the existing Candidate Console or Custom Page.
- Before each publish, preserve the reviewed source revision, lockfile, sanitized `power.config.json`, build output and digest, app/solution identity, connector-reference inventory, and approval record. Do not commit connection secrets or credentials.
- Publish with the Code Apps CLI to the explicit pilot solution. Verify the app identity, deployed version, permissions, connections, and data boundaries after publishing.
- The reviewed CLI reference documents `pa app push` but no dedicated “restore previous app version” command. The proposed rollback is to restore the previous reviewed source/build and republish it to the same verified app/solution, then verify the served build and sharing state. This procedure remains untested and must be rehearsed in the isolated environment.
- Keep any future Candidate Core/API/Flow/schema change as a separately reviewed component delta. A Code App rollback must never leave a callable mutation endpoint with weaker authorization. Do not disable or alter the existing Core API as a shortcut; reconcile in-flight external operations before any future provider rollback.
- Do not alter the production sitemap, share a pilot app with production users, or use live Candidate/Schedule data as part of the pilot.

## 8. GO / NO-GO

**GO:** continue architecture work and, after an approved nonproduction environment and license/tooling are established, build a mock-only isolated Code App prototype.

**NO-GO:** enabling Code Apps in VN LMV IT, publishing a Code App into or linking it from production `srapp`, replacing Candidate Management, reading Candidate/Schedule business rows in the prototype, invoking existing availability Flows, or enabling Create/Reschedule/Cancel.

The decision can be reconsidered when the environment feature and user license are verified; `pa`/SDK and solution ALM are available; the private `os_sr_cact` generated-service path is proven without weakening its server checks; the navigation/context/frame contract is tested; and privacy, DLP, connector identity, monitoring, and release approvals are documented.

## Evidence and references

### Repository evidence

- [Current State](../CURRENT_STATE.md) — latest live Console/Page/Flow reconciliation and deployment boundaries.
- [Recruitment Dashboard and Phase 2 handoff](../RECRUITMENT_DASHBOARD.md) — served-resource evidence, bridge contract, Custom Page state, and owner-only Studio work.
- [Architecture](../ARCHITECTURE.md), [Data Model](../DATA_MODEL.md), [Security Model](../SECURITY_MODEL.md), [Integration Design](../INTEGRATION_DESIGN.md), and [ALM Deployment](../ALM_DEPLOYMENT.md) — business authority, identities, access, integrations, and release invariants.
- [Master Production Rules](../../MASTER_PRODUCTION_RULES.md) — workflow, authorization, privacy, audit, and external-operation requirements.

### Microsoft documentation

- [Power Apps Code Apps overview](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/overview) — React support, prerequisites, environment enablement, licensing, managed platform, and limitations.
- [Code Apps architecture](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/architecture) — client library, generated services, configuration, and host.
- [Create a Code App](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/how-to/create-an-app-from-scratch) — CLI, local development, build, and publish.
- [Connect a Code App to Dataverse](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/how-to/connect-to-dataverse) and [connect to data](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/how-to/connect-to-data) — generated data services and supported scenarios.
- [Add a Dataverse action or function](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/how-to/add-dataverse-action-function) — generated Custom API/function services.
- [Add Power Automate flows](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/how-to/add-flows) — supported Power Apps-triggered instant Flow requirements and limitations.
- [Code Apps CLI reference](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/reference/cli) and [system limits and configuration](https://learn.microsoft.com/en-us/power-apps/developer/code-apps/system-limits-configuration) — publish/share commands, hosted assets, and local iframe network-access guidance.
- [Model-driven Custom Page navigation](https://learn.microsoft.com/en-us/power-apps/developer/model-driven-apps/clientapi/navigate-to-custom-page-examples) — supported Custom Page record context.
- [PAC model and Generative Pages commands](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/model) — separate model-driven page list/download/upload/attach lifecycle.
