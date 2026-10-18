---
applyTo: "solutions/**/*"
---
# Dataverse Guidance

- Dataverse is the production source of truth for candidate workflow and business state. SharePoint is not the candidate database.
- Use the `os_sr` project namespace wherever supported and follow the abbreviated Dataverse naming dictionary in [Data Model](../../docs/DATA_MODEL.md). Whether `os_sr` is accepted as the actual Publisher Prefix remains unverified; do not silently substitute another value. Treat proposed names as unapproved until schema review and publisher validation.
- Keep approved technical names stable. Do not rename or recreate existing objects without an explicit migration plan. Abbreviations are not a security boundary; retain least-privilege access, auditing, and privacy protections.
- Protect critical state transitions with an approved server-side business operation; client and Flow checks alone are insufficient.
- Design keys, relationships, ownership, retention, audit, concurrency, and least-privilege access before provisioning. Do not create tables in Phase 0.
- Use supported solution source workflows. Never include real candidate data or secrets.
