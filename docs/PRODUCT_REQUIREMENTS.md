# Product Requirements

Status labels: **Confirmed** = explicit business rule in the supplied product prompt/blueprint; **Proposed** = target design not yet implemented/approved as architecture; **Pending validation** = business detail or external capability must be confirmed. No requirement below implies implementation.

## Modules and requirements

| Module | Requirement | Status |
|---|---|---|
| Candidate operations | Maintain candidate identity/contact details, candidate number, job, source, owner BSO, assigned TA, CV URL, linked career, and current status. | Confirmed at business level; exact fields/schema proposed |
| Candidate queues | Enable BSO to find, filter, and act on candidates in relevant workflow states. | Proposed UX; validate queue definitions and service levels |
| Calling and call log | Record outreach outcome, actor/time, notes, and resulting allowed status. | Confirmed need; outcomes/validation pending |
| Candidate workflow | Support Need Call Candidate → Candidate Answered → Waiting Manual Scheduling → Round 1 Scheduled → Offer Extended or Candidate Failed; reschedule returns to Need Call Candidate. | Confirmed |
| Transition history | Record previous/new status, actor, timestamp, reason when applicable, correlation when applicable; reject invalid transitions. | Confirmed |
| Interview scheduling | BSO coordinates; TA and candidate required; offline room resource attendee; verify required free/busy, fail closed, recheck before booking where supported. | Confirmed |
| Interview outcomes | Record Pass/Fail and relevant feedback; Pass leads to Offer Extended, Fail to Candidate Failed. | Outcome confirmed; fields/gating pending validation |
| Email | Approved templates; preserve intended sender, logical To/CC, subject/body snapshot; idempotency; Sent/Failed/Indeterminate and no blind retry on uncertain send. | Confirmed |
| Visitor registration | Track onsite candidate visits and applicable location/time/status. | Proposed module in blueprint; business rules pending validation |
| LEGO Careers | Use official proxy as intended source; only Vietnam postings visible; exactly one title match auto-selected, zero/multiple manual; valid linked posting required for booking. | Confirmed business constraints; API contract/access pending |
| CV handling | CV URL is canonical initial booking prerequisite. Physical SharePoint file storage is separate design decision. | Confirmed |
| OCR | Consider AI Builder or approved alternative only after privacy, accuracy, licensing/capacity review. | Pending validation |
| Administration | Manage TA directory, positions, sources, locations, approved templates, and configuration as authorized. | Proposed; admin scope/roles pending |
| Reporting | Operational measures in Dataverse; Power BI for advanced reporting if required. | Proposed/conditional |
| Security and privacy | Entra authentication, least privilege, DLP, synthetic development data, protected CV/salary/contact data. | Confirmed principles; exact controls pending |
| Migration and cutover | Map ATSugg data, preserve required history, reconcile, obtain acceptance, and maintain rollback until cutover accepted. | Confirmed objective; source details pending |

## Scope exclusions for Phase 0

No table/app/Flow/API creation, tenant connection, deployment, ATSugg source modification, real data, CV documents, or generated test evidence. Detailed workflows are in [Business Workflows](BUSINESS_WORKFLOWS.md); acceptance is in [Acceptance Criteria](ACCEPTANCE_CRITERIA.md).
