# Product Decisions and Open Items

This log separates explicit product rules from choices requiring confirmation. Statuses reflect the supplied materials and repository evidence through 23 October 2026; a design proposal is not approval.

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
| Official model-driven app identity | Existing AppModule `srapp` is the BSO-RS-Support reference administration app. | Owner adopted it 21 October 2026; the complete 13-component initial app was separately published and accepted through Phase 2D.4F on 23 October. The app-only `srapp` name supersedes `os_srapp`; do not rename/recreate it. The approved app associations remain System Administrator/System Customizer; the Phase 2D publication authorization is consumed. See [Current State](CURRENT_STATE.md). |
| Dataverse audit retention | Follow approved organizational IT/Compliance policy; current environment setting is not policy. | Retention value remains unresolved; Candidate/Call/History table-audit requirement is separately owner-approved. Current technical setting is 30 days. |
| Phase 3A Candidate Number | Server-generated, immutable after creation, unique, and contains no personal information. | Owner explicitly approved 23 October 2026. Proposed Dataverse AutoNumber format is `CAND-{SEQNUM:8}` with String/Text MaxLength 100; runtime generation awaits a later authorized synthetic-row test. |
| Phase 3A call outcomes | Initial outcomes are Answered, No Answer, and Call Back Requested. Answered from Need Call Candidate creates Call Log + Candidate Answered transition + History atomically; the other two log only and do not change status. | Owner explicitly approved 23 October 2026. |
| Phase 3A contact requiredness | Candidate Name and Email required; Phone optional. | Owner explicitly approved 23 October 2026. |
| Phase 3A Candidate ownership | Dataverse record Owner is the responsible BSO; no duplicate Assigned BSO lookup. TA remains a separate interviewer/directory lookup, not the default Candidate owner. | Owner explicitly approved 23 October 2026. |
| Phase 3A reschedule reason/history | Reschedule from Round 1 Scheduled to Need Call Candidate requires a reason and records actor, timestamp, CorrelationId, previous/new status, and reason in Status History. | Owner explicitly approved 23 October 2026. Calendar/event cancellation evidence and execution are deferred to the later scheduling phase; reschedule must remain unavailable until that boundary is implemented. |
| Phase 3A table audit/contact field security | Enable Dataverse table auditing for Candidate, Call Log, and Candidate Status History. Do not apply column-level security to Candidate Name/Email/Phone in the initial slice. | Owner explicitly approved 23 October 2026. Organization-level audit enablement, retention, access, and capacity still require IT/Compliance governance; no tenant setting changed. |
| Phase 3A operation correlation/idempotency | Every state-changing Candidate business operation requires a caller-generated GUID CorrelationId; duplicate execution for one logical operation must not duplicate Call Logs, Status History, or transitions. | Owner explicitly approved 23 October 2026. Proposed CorrelationId also supplies the idempotency token, with scoped unique keys and payload replay checks. |
| Phase 3A LEGO Career dependency | Defer the LEGO Career lookup from Candidate core; Candidate includes Position. Validate linked LEGO Career later at the scheduling/booking boundary, not Candidate creation. | Owner explicitly approved 23 October 2026. The Candidate-to-LEGO-Career relationship is excluded from the current core manifest. |

## Open decisions and external dependencies

| Item | Needed before | Current status |
|---|---|---|
| Dedicated Dev/Test environment(s), region, owners, and access; governance for continued development in Production | Further implementation | VN LMV IT is Production and was explicitly selected for Phase 1B internal IT development; existence/access of separate Dev/Test environments is unverified |
| Phase 2D composition, publication, and browser acceptance | Closed for reference-app milestone | Phase 2D.4F classified `PUBLISHED_UI_ACCEPTED_WITH_DEFERRED_FORM_RECORD_TEST` and `PHASE_2D_COMPLETE`; no more navigation or publication is authorized by that completed work. Existing app Publisher lookup and unrelated type-10091 identity remain unknown; no inference is made from the containing Solution Publisher. |
| Candidate Core least-privilege API privilege/effective-access model | Before API/plugin implementation and provisioning readiness | Security-owner approval and validation remain open; preserve initiating BSO identity, avoid fixed service/Flow-owner impersonation, and do not grant roles in this design phase. See [Security Model](SECURITY_MODEL.md) and [Phase 3A.2 readiness report](PHASE_3A2_CANDIDATE_CORE_DECISION_APPLICATION.md). |
| Organization-level audit enablement, retention, authorized readers, legal hold/DSR, and capacity | Before relying on Candidate Core audit | Last documented environment assessment found auditing disabled; the accepted table-audit requirement does not itself enable organization auditing. IT/Compliance governance remains required. See [Dataverse Audit Policy](DATAVERSE_AUDIT_POLICY.md). |
| Candidate Core Choice allocation, AutoNumber metadata path, exact environment/solution/publisher | Guarded provisioning preflight | Must be verified against current platform metadata and supported tooling before any future write. No tenant reads occurred in Phase 3A.2. |
| Calendar/event cancellation evidence for reschedule | Later scheduling phase | Explicitly deferred. Keep reschedule unavailable until cancellation attempt and outcome evidence are supported; this is not an open Candidate Core product decision. |
| Duplicate Position/Source policy; TA stable identity; room identity; interview result versioning/salary currency; visitor lifecycle; config table vs environment variables | Later schema implementation | Open; do not turn proposed defaults into business rules without approval |
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

The Phase 3A owner decisions are closed and applied in the [Candidate Core design](PHASE_3A_CANDIDATE_CORE_DESIGN.md). Remaining readiness work is to resolve organization-level audit governance and least-privilege Custom API execution privileges, then verify Choice allocation, AutoNumber support, and the exact environment/solution/publisher through a separately authorized guarded preflight. Every metadata/API/plugin write still requires separate explicit bounded authorization. See [Current State](CURRENT_STATE.md).
