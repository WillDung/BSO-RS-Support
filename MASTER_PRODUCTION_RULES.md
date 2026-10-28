# Master Production Rules

These invariants govern design and implementation. See [Project Decisions](docs/PRODUCT_DECISIONS.md) for unresolved choices. A rule here does not assert that a corresponding resource exists.

## Data authority and business operations

- Dataverse is the only production source of truth for candidate workflow and business state. SharePoint stores approved documents, not primary candidate records.
- Power Automate must not bypass business transition rules. Critical state changes pass through an approved Dataverse business operation. For Candidate Core, `os_sr_cact` is implemented and metadata-deployed. Organization-level auditing remains an external governance/release prerequisite, not a runtime rejection; required table-audit metadata and append-only History/Receipt evidence remain mandatory. See the [Phase 3C deployment report](docs/PHASE_3C_CANDIDATE_CORE_API_PLUGIN_REPORT.md) and the [Phase 3D runtime acceptance report](docs/PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md).
- Record each valid transition's previous status, new status, actor, timestamp, applicable reason, and correlation identifier where applicable.

## Identity and roles

- BSO is the primary interactive application user. TA is the assigned interviewer/directory contact, not automatically a separate interactive role or approval stage.
- Additional interactive roles require an explicit product decision. Entra authentication, Dataverse authorization, and Microsoft 365 connector identity are separate boundaries.
- Email and calendar actions use the intended, verified Microsoft 365 identity. A fixed Flow-owner connection must never silently impersonate the current BSO.

## Candidate workflow

Canonical path: Need Call Candidate → Candidate Answered → Waiting Manual Scheduling → Round 1 Scheduled → Offer Extended (Pass) or Candidate Failed (Fail). Reschedule from Round 1 Scheduled returns to Need Call Candidate through an approved business action, with cancellation attempt and audit. No Draft Created, BSO Reviewing, Sent to TA, or TA Approval workflow may be reintroduced without a new explicit product decision.

For the initial Candidate slice, the owner-approved call outcomes are Answered, No Answer, and Call Back Requested. Answered from Need Call Candidate atomically creates a Call Log, advances Candidate to Candidate Answered, and creates one Status History row; No Answer and Call Back Requested create a Call Log only and leave status unchanged. Candidate Name and Email are required; Phone is optional. Candidate Number is server-generated, immutable, unique, and nonpersonal. Dataverse Owner is the responsible BSO; do not add a duplicate Assigned BSO lookup. Every state-changing Candidate operation requires a caller-generated GUID CorrelationId and must be idempotent for that logical operation. The Phase 5A Candidate Core manual reschedule operation requires a reason and preserves actor, timestamp, CorrelationId, previous/new status, and reason in durable business evidence; it does not depend on an external calendar cancellation system.

## Scheduling

- BSO coordinates; TA and candidate are required attendees; for offline interviews the room is a resource attendee.
- Online availability requires verified TA availability. Offline availability requires verified TA and room availability. Unknown, failed, or stale availability is not free.
- Recheck availability immediately before booking where supported. Design event creation, cancellation, reconciliation, and audit explicitly; external calendar operations are not assumed transactional.
- **Phase 5A user-directed manual Candidate Core workflow scope (28 October 2026):** the existing `os_sr_intv` Round 1 row is the durable evidence for the manual workflow transition. Scheduling requires an active TA and Location reference and valid requested schedule inputs; Pass/Fail/Reschedule/Cancel require the exact persisted Round 1 schedule evidence defined by the Candidate Core contract. This row records the BSO's schedule decision; it does not prove live calendar availability, create a Microsoft 365 event, or authorize an external booking. The availability and identity rules above continue to apply whenever a Microsoft 365 calendar event is actually booked or changed.

## Email

- Use approved templates. Preserve logical To/CC, intended sender, subject and rendered body snapshot, and dispatch audit.
- Define a unique idempotency mechanism. Distinguish Sent, Failed, and Indeterminate. Never blindly retry an uncertain send, and never equate Flow invocation success with delivery success.

## CV and LEGO Careers

- Candidate CV URL is the canonical initial booking prerequisite. Binary storage in SharePoint is a separate decision.
- Booking requires a valid linked LEGO Career and CV URL under current product rules.
- The intended source is LEGO's official careers proxy API. Only Vietnam postings are visible for the relevant workflow. Exactly one job-title match may auto-select; zero or multiple matches require manual resolution.

## Audit, privacy, and security

- Preserve business history and sufficient correlation to investigate external actions. Avoid secrets and unnecessary PII in logs.
- Never commit secrets, tokens, passwords, real tenant IDs, production connector URLs, real candidate data, real CVs, or connection credentials. Use synthetic examples.
- Enable Dataverse table auditing for Candidate, Call Log, and Candidate Status History. In the initial Candidate slice, do not apply column-level security to Candidate Name, Email, or Phone; continue to enforce least-privilege table/row access.
- Apply least privilege and organizational DLP/privacy policies. No permission grant is assumed.

## Naming and information disclosure

- Recommended naming strategy, pending approval: use `os` as the Dataverse Publisher Prefix and `sr_` as the project namespace segment, producing final technical names beginning `os_sr_` wherever supported. Microsoft documents prefixes as 2–8 alphanumeric characters beginning with a letter and not starting with `mscrm`; `os` meets this rule. Do not use `os_sr` as the actual Publisher Prefix or silently substitute a different value.
- Where Power Apps automatically prepends the selected Publisher Prefix, provide only the remaining `sr_<abbreviation>` stem. Where a metadata API or component requires the complete technical name, provide the final `os_sr_<abbreviation>` exactly once. Never allow automatic prefixing to produce a double prefix such as `os_os_sr_cand`.
- Use short, consistent abbreviations for technical table names, custom columns, relationships, alternate keys, Custom APIs, plug-in components, and Cloud Flows where technically supported. The internal abbreviation dictionary and proposed patterns are maintained in [Data Model](docs/DATA_MODEL.md).
- Treat all names as proposals until schema review and publisher validation. After approval, keep technical names stable. Do not rename or recreate existing objects without an explicit migration plan.
- Abbreviated names reduce casual disclosure only; they are not a security boundary. Protect data with Dataverse security roles, record-level access control, column-level security where appropriate, auditing, DLP policies, and least-privilege connector access. Never place personal data in names, logs, fixtures, or repository documentation.

## Integrations and operations

- Treat timeouts and partial/ambiguous external outcomes as uncertain, observable states. Use bounded retries only where idempotency and outcome semantics support them; reconcile before repeating non-idempotent actions.
- Sanitize errors and monitor failed/indeterminate email, calendar, and synchronization operations. Do not deactivate valid synchronized records on partial/error responses.

## ALM and production

- Use dedicated Dev, Test, and Production environments where approved; their existence is not established here.
- Use managed Solutions downstream, environment variables, and connection references. Version-control solution components only when exported/unpacked through supported tooling.
- Production changes require approval, a verified deployment plan, backup/recovery consideration, and rollback plan. Do not claim environments, pipelines, or deployments exist.

## Migration and cutover

- ATSugg remains intact as business reference and rollback option through migration and acceptance. Do not assume live database or production data access.
- Define source mapping, identity mapping, history preservation, reconciliation, freeze/delta approach, rollback, and retirement criteria before cutover. Production cutover requires business sign-off and an approved rollback path.
