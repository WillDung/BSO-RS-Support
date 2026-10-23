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
| Dataverse audit retention | Follow approved organizational IT/Compliance policy; current environment setting is not policy. | Confirmed decision; required retention value and audit scope remain unresolved. Current technical setting is 30 days. |

## Open decisions and external dependencies

| Item | Needed before | Current status |
|---|---|---|
| Dedicated Dev/Test environment(s), region, owners, and access; governance for continued development in Production | Further implementation | VN LMV IT is Production and was explicitly selected for Phase 1B internal IT development; existence/access of separate Dev/Test environments is unverified |
| Phase 2D composition, publication, and browser acceptance | Closed for reference-app milestone | Phase 2D.4F classified `PUBLISHED_UI_ACCEPTED_WITH_DEFERRED_FORM_RECORD_TEST` and `PHASE_2D_COMPLETE`; no more navigation or publication is authorized by that completed work. Existing app Publisher lookup and unrelated type-10091 identity remain unknown; no inference is made from the containing Solution Publisher. |
| Dataverse entity ownership, relationships, keys, audit/retention, concurrency, security boundary | Schema approval | Proposed in [Dataverse Schema Specification](DATAVERSE_SCHEMA_SPECIFICATION.md); owner/security review required. Phase 3A specifically remains `BLOCKED_PRODUCT_DECISION`; see [Candidate Core Design](PHASE_3A_CANDIDATE_CORE_DESIGN.md). |
| Candidate Number source/generation/format; Candidate create-time requiredness; call outcome taxonomy; Candidate BSO/owner semantics; reschedule evidence/reason; field-security/audit policy; operation idempotency contract; LEGO Career lookup dependency | Before Candidate-core provisioning | Unresolved. Phase 3A.1 requested explicit owner decisions but received no owner-authored selections; none of its recommendations is accepted. Preserve `BLOCKED_PRODUCT_DECISION` and do not turn proposal defaults into business rules. See [Phase 3A.1 Decision Closure](PHASE_3A1_CANDIDATE_CORE_DECISION_CLOSURE.md). |
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

Next recommended step for the core recruitment slice is to resolve the Phase 3A Candidate Number, Call Outcome, contact-requiredness, ownership, reschedule-evidence, privacy/audit, Custom API execution, and LEGO Career dependency decisions. Update and revalidate the proposal before any provisioning request. Every metadata write still requires separate explicit bounded authorization. See [Current State](CURRENT_STATE.md).
