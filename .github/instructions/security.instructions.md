---
applyTo: "**/*security*"
---
# Security Guidance

- Apply least privilege and organizational privacy/DLP policies. Do not assume a permission, role, environment, or connector is granted.
- Keep Entra authentication, Dataverse authorization, and Microsoft 365 connector identity distinct. Verify intended sender and organizer identities.
- Never add credentials, tokens, real tenant identifiers, production URLs, candidate PII, or real documents. Use synthetic examples.
- Protect salary/contact data and CV access; define retention and audit before implementation.
- See [Security Model](../../docs/SECURITY_MODEL.md) and [Master Production Rules](../../MASTER_PRODUCTION_RULES.md).
