# Product Decisions and Open Items

This log separates explicit product rules from choices requiring confirmation. Statuses reflect the supplied materials as of 18 October 2026; a design proposal is not approval.

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

## Open decisions and external dependencies

| Item | Needed before | Current status |
|---|---|---|
| Approved Dev/Test/Production environment(s), region, owners, and access | Phase 1 provisioning | Unknown; do not assume they exist |
| Required project namespace `os_sr`; confirm whether exact value is valid as Dataverse Publisher Prefix | Schema/solution creation | `os_sr` is five characters and meets the documented eight-character maximum; underscore acceptance is not stated in the published reference and remains unverified. Do not substitute another prefix without explicit decision. |
| Dataverse entity ownership, relationships, keys, audit/retention, concurrency, security boundary | Schema approval | Design review required |
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

## Approval boundary

Next recommended step is **Phase 1A — Dataverse schema design review, before provisioning tables.** It is not authorization to provision resources. A new explicit instruction is required before Phase 1A begins. See [Current State](CURRENT_STATE.md).
