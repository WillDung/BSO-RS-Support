---
applyTo: "solutions/**/*"
---
# Dataverse Guidance

- Dataverse is the production source of truth for candidate workflow and business state. SharePoint is not the candidate database.
- Follow the recommended naming strategy, pending approval: Dataverse Publisher Prefix `os` plus project namespace segment `sr_`, yielding final names beginning `os_sr_`. Use the abbreviated Dataverse naming dictionary in [Data Model](../../docs/DATA_MODEL.md). Where the Maker experience automatically prepends `os_`, supply only the `sr_<abbreviation>` stem; otherwise use the full final name once. Do not double-prefix. Treat names as proposals until schema review and approval.
- Keep approved technical names stable. Do not rename or recreate existing objects without an explicit migration plan. Abbreviations are not a security boundary; retain least-privilege access, auditing, and privacy protections.
- Protect critical state transitions with an approved server-side business operation; client and Flow checks alone are insufficient.
- Design keys, relationships, ownership, retention, audit, concurrency, and least-privilege access before provisioning. Do not create tables in Phase 0.
- Use supported solution source workflows. Never include real candidate data or secrets.
