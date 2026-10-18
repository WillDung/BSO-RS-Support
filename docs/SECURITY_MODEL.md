# Security Model

**Status:** Security design proposal and constraints. No tenant settings, roles, permissions, connector grants, or DLP configuration have been verified.

## Identity and authentication

Microsoft Entra ID is the target authentication authority. Authentication does not itself grant Dataverse access. Dataverse security roles govern operations and data access. Microsoft 365 connector identity is a separate boundary and must be verified independently for each email/calendar action.

## Roles and access

- **BSO:** primary interactive role; access should follow least privilege and assigned business responsibility.
- **Administrator:** future capability only; define administrative tasks and limit privileged access. Existence/approval of an Admin role is not established.
- **TA:** directory/interviewer contact, not automatically an interactive app role. Additional TA access requires an explicit product decision.
- Candidate/visitor access is not assumed.

Define table privileges, row ownership/sharing, team model, and field-level security after stakeholder review. Restrict salary, contact details, CV links/documents, email snapshots, and integration diagnostics as appropriate. Validate access with positive and negative tests.

## Connector identity

A BSO's app session does not guarantee a connector executes as that BSO. Verify the approved user-scoped connection/run-only pattern, sender/organizer semantics, delegated permissions, and failure behavior in a nonproduction tenant before rollout. Fixed Flow-owner connections must never silently impersonate the current BSO. Deny send/booking when intended identity cannot be established.

## Data protection and operations

Use synthetic fixtures outside approved production use. Do not log tokens, secrets, unnecessary candidate PII, message contents beyond approved audit snapshots, or full external payloads. Define retention, deletion, backup, recovery, audit access, incident ownership, and privacy review. Protect CV URL access and any future SharePoint binary documents; a link is still sensitive data.

## DLP and least privilege

Review organizational DLP policies for Dataverse, Outlook, Teams, SharePoint, HTTP/custom connectors, AI Builder, and Power BI before design is finalized. Grant only required table/API/connector permissions and environment access. No permission or policy exception is assumed. See [Integration Design](INTEGRATION_DESIGN.md) and [ALM Deployment](ALM_DEPLOYMENT.md).
