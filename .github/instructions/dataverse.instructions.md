---
applyTo: "solutions/**/*"
---
# Dataverse Guidance

- Dataverse is the production source of truth for candidate workflow and business state. SharePoint is not the candidate database.
- Treat entity names and prefix `brs_` in [Data Model](../../docs/DATA_MODEL.md) as proposals until schema review and publisher approval.
- Protect critical state transitions with an approved server-side business operation; client and Flow checks alone are insufficient.
- Design keys, relationships, ownership, retention, audit, concurrency, and least-privilege access before provisioning. Do not create tables in Phase 0.
- Use supported solution source workflows. Never include real candidate data or secrets.
