# Product Decisions and Open Items

This log separates explicit product rules from choices requiring confirmation. Statuses reflect the supplied materials, verified environment metadata, and the owner-approved Phase 2C-R3 adoption decision as of 21 October 2026; a design proposal is not approval.

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
| Official model-driven app identity | Adopt the existing AppModule BSO-RS-Support, unique name `srapp`, ID `3709bb7c-28cd-f111-a05c-70a8a581cbfa`, in `os_sr_bso_rs_support`. | Project owner approved 21 October 2026. `srapp` is an app-only naming exception; the earlier `os_srapp` proposal is superseded for this app only. Do not rename or recreate it. Adoption does not imply composition, access grant, or publication. AppModule Publisher lookup remains unknown. |
| Dataverse audit retention | Follow approved organizational IT/Compliance policy; current environment setting is not policy. | Confirmed decision; required retention value and audit scope remain unresolved. Current technical setting is 30 days. |

## Open decisions and external dependencies

| Item | Needed before | Current status |
|---|---|---|
| Dedicated Dev/Test environment(s), region, owners, and access; governance for continued development in Production | Further implementation | VN LMV IT is Production and was explicitly selected for Phase 1B internal IT development; existence/access of separate Dev/Test environments is unverified |
| Phase 2D composition, app Publisher provenance, and end-user access | Composition implementation | Adoption of `srapp` is approved. The AppModule's own Publisher lookup remains unverified; do not infer it from the containing Solution Publisher. R2 found the App active but unpublished, no app components, a placeholder-only Site Map, and System Administrator/System Customizer roles only. Exact TA Main form and public Active view IDs are in the manifest. Phase 2D composition and any role/security changes require separate explicit authorization. Type 10091 remains identity-unknown and must be preserved; no publish or role changes are authorized by the adoption decision. |
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
