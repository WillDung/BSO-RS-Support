---
applyTo: "automation/**/*"
---
# Power Automate Guidance

- Flows orchestrate integrations and asynchronous work; they do not independently bypass business rules. Critical transitions go through an approved Dataverse business operation.
- Separate the invoking BSO's authorization from connector identity. Never silently use a fixed owner connection to impersonate the BSO.
- Define idempotency, correlation, bounded retry behavior, reconciliation, and explicit Failed/Indeterminate outcomes before implementing external side effects.
- Unknown availability is not free. A successful Flow invocation is not proof of email delivery or calendar booking.
- Use environment variables and connection references in approved ALM; honor DLP. Do not create flows in Phase 0.
