# Security Model

**Status:** Security design proposal and constraints. The published `srapp` reference app retains its accepted System Administrator and System Customizer associations; no project-specific BSO/Admin end-user role is established by that association. Phase 2D.4F made no access changes. Phase 3A owner decisions approve Dataverse Owner as responsible BSO, table auditing for Candidate/Call Log/Status History, and no column-level security for Candidate Name/Email/Phone in the initial slice. Candidate table audit metadata is enabled, but organization-level auditing remains disabled as an external IT/Compliance governance/release prerequisite; the latest authorized assembly update removed it as a runtime rejection. The Phase 3D runtime outcome is `UNCERTAIN_WRITE_OUTCOME`: the one-shot lock was already consumed, no corresponding dispatch journal was found among retained session artifacts inspected, and no Apply retry was made. Four fresh count-only queries found zero rows across the Candidate Core business/evidence tables; this does not establish the earlier API dispatch count. The Custom API is deployed with the existing Candidate write privilege `prvWriteos_sr_cand`; this does not establish an approved least-privilege role or effective non-admin rights. Non-admin acceptance remains deferred to Candidate UI + Security. No role, access, or organization setting was changed in the follow-up. See the [Phase 3D report](PHASE_3D_CANDIDATE_CORE_RUNTIME_ACCEPTANCE_REPORT.md), [Candidate-only provisioning report](PHASE_3A_CANDIDATE_TABLE_PROVISIONING_REPORT.md), [Phase 3A Candidate Core Design](PHASE_3A_CANDIDATE_CORE_DESIGN.md), [Phase 3A.2 readiness report](PHASE_3A2_CANDIDATE_CORE_DECISION_APPLICATION.md), and [Dataverse Schema Specification](DATAVERSE_SCHEMA_SPECIFICATION.md).

## Identity and authentication

Microsoft Entra ID is the target authentication authority. Authentication does not itself grant Dataverse access. Dataverse security roles govern operations and data access. Microsoft 365 connector identity is a separate boundary and must be verified independently for each email/calendar action.

## Roles and access

- **BSO:** primary interactive role; access should follow least privilege and assigned business responsibility.
- **Administrator:** future capability only; define administrative tasks and limit privileged access. Existence/approval of an Admin role is not established.
- **TA:** directory/interviewer contact, not automatically an interactive app role. Additional TA access requires an explicit product decision.
- Candidate/visitor access is not assumed.

Define table privileges, row ownership/sharing, team model, and Custom API execution privileges with security-owner review. The Phase 3A owner-approved initial slice uses Dataverse `ownerid` as the responsible BSO and has no duplicate Assigned BSO lookup. Name/Email/Phone column-level security is explicitly not applied in this initial slice; least-privilege table/row access and auditing remain required. Restrict salary, CV links/documents, email snapshots, and integration diagnostics as appropriate. Validate access with positive and negative tests.

### Proposed schema access boundaries

| Data area | Proposed Dataverse boundary | Sensitive columns/data |
|---|---|---|
| Candidate and child activity records | UserOwned; Candidate Dataverse Owner is responsible BSO; child owner aligned by server-side operation; no implicit access from a lookup | Candidate name/email/phone are not column-secured in initial slice; CV URL, call notes, interview feedback, and visit details remain sensitive |
| Interview results | UserOwned under Candidate owner; only approved BSO/roles | Feedback and salary; field-level security proposed, subject to role design |
| Email dispatch | UserOwned under Candidate owner; narrow table and column privileges; immutable content snapshot after queue | Sender, To/CC snapshots, subject/body, provider IDs; field-level security and explicit retention |
| TA, Position, Candidate Source, Location, Email Template | OrgOwned reference data; BSO read only as needed; restricted admin/integration write | TA email and room resource addresses remain directory/contact information |
| App Configuration | OrgOwned, restricted admin read/write | Nonsecret approved values only; no credentials, tokens, connector URLs, or secrets |
| LEGO Career | OrgOwned, BSO read and integration write | External posting fields; Vietnam filter; no candidate payload |
| Integration Run | OrgOwned, operational-admin/integration-only | Sanitized diagnostics only; no raw payload or candidate PII column |

The Candidate primary name is proposed as Candidate Number rather than personal name because Dataverse exposes a related row's primary name through lookups. Candidate Number is still an internal identifier and must be access-controlled. Alternate-key columns cannot have field-level security; protect their disclosure using row/table privileges. No policy or role assignment is configured by this proposal.

Owner-approved Phase 3A requirement: enable Dataverse table auditing for Candidate, Call Log, and Candidate Status History. The fresh Candidate-only verification confirms organization auditing is disabled while Candidate's table audit metadata is enabled; no Candidate rows were created. The read-only assessment on 19 October 2026 found configured retention of 30 days (not an approved policy) and user-access auditing off. Capacity, historic audit-log presence, audit access, and effects on other applications remain unknown. IT/Compliance must resolve organization-level activation, retention, audit readers, legal hold/DSR, capacity ownership, and change control before Candidate data or audit history can be relied on. No organization setting was changed. The proposed scope and impact are documented in [Dataverse Audit Policy Proposal](DATAVERSE_AUDIT_POLICY.md) and [Audit Impact Assessment](AUDIT_IMPACT_ASSESSMENT.md).

Dataverse auditing is distinct from `os_sr_csh`, the proposed application-owned append-only status history. `os_sr_csh` must capture accepted business transitions through an approved atomic server operation; Dataverse auditing supplements it. The table-audit enablement requirement is approved for the three Candidate-core tables; any additional column-level audit selection for email snapshots, salary, CV links, or later domains must follow IT/Compliance data-minimization and retention review.

## Connector identity

A BSO's app session does not guarantee a connector executes as that BSO. Verify the approved user-scoped connection/run-only pattern, sender/organizer semantics, delegated permissions, and failure behavior in a nonproduction tenant before rollout. Fixed Flow-owner connections must never silently impersonate the current BSO. Deny send/booking when intended identity cannot be established.

## Data protection and operations

Use synthetic fixtures outside approved production use. Do not log tokens, secrets, unnecessary candidate PII, message contents beyond approved audit snapshots, or full external payloads. Define retention, deletion, backup, recovery, audit access, incident ownership, and privacy review. Protect CV URL access and any future SharePoint binary documents; a link is still sensitive data.

## DLP and least privilege

Review organizational DLP policies for Dataverse, Outlook, Teams, SharePoint, HTTP/custom connectors, AI Builder, and Power BI before design is finalized. Grant only required table/API/connector permissions and environment access. No permission or policy exception is assumed. See [Integration Design](INTEGRATION_DESIGN.md) and [ALM Deployment](ALM_DEPLOYMENT.md).
