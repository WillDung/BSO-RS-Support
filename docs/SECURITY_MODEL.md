# Security Model

**Status:** Security design proposal and constraints. No tenant settings, roles, permissions, connector grants, or DLP configuration have been verified. Proposed table ownership and sensitive-field treatment are in [Dataverse Schema Specification](DATAVERSE_SCHEMA_SPECIFICATION.md).

## Identity and authentication

Microsoft Entra ID is the target authentication authority. Authentication does not itself grant Dataverse access. Dataverse security roles govern operations and data access. Microsoft 365 connector identity is a separate boundary and must be verified independently for each email/calendar action.

## Roles and access

- **BSO:** primary interactive role; access should follow least privilege and assigned business responsibility.
- **Administrator:** future capability only; define administrative tasks and limit privileged access. Existence/approval of an Admin role is not established.
- **TA:** directory/interviewer contact, not automatically an interactive app role. Additional TA access requires an explicit product decision.
- Candidate/visitor access is not assumed.

Define table privileges, row ownership/sharing, team model, and field-level security after stakeholder review. Restrict salary, contact details, CV links/documents, email snapshots, and integration diagnostics as appropriate. Validate access with positive and negative tests.

### Proposed schema access boundaries

| Data area | Proposed Dataverse boundary | Sensitive columns/data |
|---|---|---|
| Candidate and child activity records | UserOwned; BSO owner or approved team; child owner aligned by server-side operation; no implicit access from a lookup | Candidate name, email, phone, CV URL; call notes; interview feedback; visit details |
| Interview results | UserOwned under Candidate owner; only approved BSO/roles | Feedback and salary; field-level security proposed, subject to role design |
| Email dispatch | UserOwned under Candidate owner; narrow table and column privileges; immutable content snapshot after queue | Sender, To/CC snapshots, subject/body, provider IDs; field-level security and explicit retention |
| TA, Position, Candidate Source, Location, Email Template | OrgOwned reference data; BSO read only as needed; restricted admin/integration write | TA email and room resource addresses remain directory/contact information |
| App Configuration | OrgOwned, restricted admin read/write | Nonsecret approved values only; no credentials, tokens, connector URLs, or secrets |
| LEGO Career | OrgOwned, BSO read and integration write | External posting fields; Vietnam filter; no candidate payload |
| Integration Run | OrgOwned, operational-admin/integration-only | Sanitized diagnostics only; no raw payload or candidate PII column |

The Candidate primary name is proposed as Candidate Number rather than personal name because Dataverse exposes a related row's primary name through lookups. Candidate Number is still an internal identifier and must be access-controlled. Alternate-key columns cannot have field-level security; protect their disclosure using row/table privileges. No policy or role assignment is configured by this proposal.

Read-only assessment on 19 October 2026 found environment auditing off, configured retention of 30 days (not an approved policy), and user-access auditing off. Capacity, historic audit-log presence, existing table audit flags, and effects on other applications remain unknown. Do not change these settings until IT/Compliance approves retention, scope, audit readers, legal hold/DSR, capacity ownership, and change control. The proposed scope and impact are documented in [Dataverse Audit Policy Proposal](DATAVERSE_AUDIT_POLICY.md) and [Audit Impact Assessment](AUDIT_IMPACT_ASSESSMENT.md).

Dataverse auditing is distinct from `os_sr_csh`, the proposed application-owned append-only status history. `os_sr_csh` must capture accepted business transitions through an approved atomic server operation; Dataverse auditing supplements it. Do not audit sensitive email snapshots, candidate PII, salary, or CV links without an approved column-level decision and data-minimization review.

## Connector identity

A BSO's app session does not guarantee a connector executes as that BSO. Verify the approved user-scoped connection/run-only pattern, sender/organizer semantics, delegated permissions, and failure behavior in a nonproduction tenant before rollout. Fixed Flow-owner connections must never silently impersonate the current BSO. Deny send/booking when intended identity cannot be established.

## Data protection and operations

Use synthetic fixtures outside approved production use. Do not log tokens, secrets, unnecessary candidate PII, message contents beyond approved audit snapshots, or full external payloads. Define retention, deletion, backup, recovery, audit access, incident ownership, and privacy review. Protect CV URL access and any future SharePoint binary documents; a link is still sensitive data.

## DLP and least privilege

Review organizational DLP policies for Dataverse, Outlook, Teams, SharePoint, HTTP/custom connectors, AI Builder, and Power BI before design is finalized. Grant only required table/API/connector permissions and environment access. No permission or policy exception is assumed. See [Integration Design](INTEGRATION_DESIGN.md) and [ALM Deployment](ALM_DEPLOYMENT.md).
