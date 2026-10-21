# Product Decisions and Open Items

This log separates explicit product rules from choices requiring confirmation. Statuses reflect the supplied materials and verified Phase 1B resource metadata as of 19 October 2026; a design proposal is not approval.

## Established product rules

| Topic | Current rule | Basis/status |
|---|---|---|
| Product and legacy | BSO-RS-Support will eventually replace ATSugg; keep ATSugg intact through migration and acceptance. | Confirmed objective |
| Primary user | BSO interacts; TA is interviewer/directory contact, not automatically app user or approver. | Confirmed |
| Workflow | Canonical statuses and transitions in [Master Production Rules](../MASTER_PRODUCTION_RULES.md). | Confirmed |
| Data authority | Dataverse is only production candidate workflow/business source of truth. | Confirmed target constraint |
| Availability | TA required online; TA and room required offline; unknown is not free. | Confirmed |
| CV and job | CV URL and valid linked LEGO career required for booking; Vietnam-only careers; exactly-one title match only. | Confirmed |
| Email outcome | Preserve sender/recipients/content; idempotency; distinguish Sent, Failed, Indeterminate. | Confirmed |
| Platform | Premium/Dataverse production use approved in principle. | Confirmed; detailed tenant configuration not confirmed |
| Technical naming | Dataverse Publisher Prefix `os` plus project namespace segment `sr_`; final technical names begin `os_sr_` and use the abbreviated dictionary. | Selected and implemented for the project Publisher on 19 October 2026; component naming remains subject to schema review |
| Dataverse audit retention | Follow approved organizational IT/Compliance policy; current environment setting is not policy. | Confirmed decision; required retention value and audit scope remain unresolved. Current technical setting is 30 days. |

## Open decisions and external dependencies

| Item | Needed before | Current status |
|---|---|---|
| Dedicated Dev/Test environment(s), region, owners, and access; governance for continued development in Production | Further implementation | VN LMV IT is Production and was explicitly selected for Phase 1B internal IT development; existence/access of separate Dev/Test environments is unverified |
| Model-driven App technical name | AppModule creation | Owner-approved in Phase 2C for exactly one unpublished app: display name `BSO-RS-Support`, caller suffix `srapp`, expected final `os_srapp`. This is a component-specific exception to `os_sr_*` for this app only; table names, Solution name, Publisher, and prefix remain unchanged. Read-only AppModule checks found no name conflict. Actual final value requires independent read-back. Execution is blocked by two unexplained Solution-component roots (types `80` and `10091`); no AppModule write was sent. |
| Dataverse entity ownership, relationships, keys, audit/retention, concurrency, security boundary | Schema approval | Proposed in [Dataverse Schema Specification](DATAVERSE_SCHEMA_SPECIFICATION.md); owner/security review required |
| Candidate number generation/format; candidate field requiredness; call outcome taxonomy; duplicate positions/sources; TA stable identity; room identity; interview result versioning/salary currency; visitor lifecycle; config table vs environment variables | Phase 1D schema implementation | Open; do not turn proposed defaults into business rules without approval |
| TA, Position, Candidate Source, and Location duplicate/identity policies | Phase 1D-B reference table creation | No alternate keys proposed. TA email uniqueness, position title identity, source normalization/uniqueness, and room/location stable identity remain unresolved; see [Phase 1D-B Reference Table Runbook](PHASE_1D_B_REFERENCE_TABLE_RUNBOOK.md). |
| BSO M365 connection model; whether per-user Outlook connection is permitted and can reliably expose intended From | Email implementation | Tenant policy and technical verification required |
| TA and room mailbox availability permissions; test accounts; organizer policy | Scheduling implementation | Unknown |
| DLP treatment of Outlook, Teams, HTTP/custom connector, SharePoint, AI Builder, Power BI | Integration design | Tenant review required |
| LEGO proxy API contract, authentication, rate limits, pagination, data fields, country/location semantics | Careers sync | External dependency; no endpoint/credentials recorded |
| CV access policy, URL validation, physical storage/migration need, retention | Booking and migration | Open |
| AI Builder/OCR approval, capacity, accuracy, privacy, alternative | OCR scope | Conditional; not approved for implementation |
| Power BI need/capacity and dataset/security model | Reporting scope | Conditional |
| ATSugg schema, live record volume, data quality, identity map, retention/legal hold | Migration plan | Not available in inspected repository; no live access assumed |
| Historical status and email/calendar audit availability | Migration acceptance | Requires source inventory |
| Visitor workflow, admin responsibilities, SLA/KPI definitions, interview-result details | Detailed requirements | Validate with business owner |
| Production retention, backup/recovery, monitoring ownership and incident process | Production readiness | Organizational decision required |
| Audit policy: retention period/categories, historic-log effect, authorized readers, export/preservation, legal hold/DSR, user-access auditing, log capacity/owner, sensitive-field data minimization, approval owner/change control | Before audit activation | Required IT/Compliance approval; see [Dataverse Audit Policy Proposal](DATAVERSE_AUDIT_POLICY.md) and [Audit Impact Assessment](AUDIT_IMPACT_ASSESSMENT.md). Do not treat current 30-day setting as approval. |

## Approval boundary

Next recommended step is schema-owner/security review of the proposed Phase 1C design and resolution of the listed open decisions. Phase 1D implementation and table provisioning require separate explicit approval. See [Current State](CURRENT_STATE.md).
