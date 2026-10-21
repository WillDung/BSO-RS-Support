# Project Rules

## Boundaries

This repository is the documentation and governance foundation for BSO-RS-Support. The supplied [blueprint](BSO-RS-Support-Phase0-Blueprint.md) is a draft product-design source, not proof of implementation. Phase 0 creates no Power Platform resources. ATSugg is out of implementation scope here and remains intact until approved migration and acceptance.

## Decision authority

Business rules require product-owner/sponsor confirmation. Material architecture, security, data-retention, identity, and production changes require the designated organizational approval before implementation. [MASTER_PRODUCTION_RULES.md](MASTER_PRODUCTION_RULES.md) records invariants; [docs/PRODUCT_DECISIONS.md](docs/PRODUCT_DECISIONS.md) tracks unresolved choices. A proposal does not become an approved decision by appearing in documentation.

## Scope control

Work on one named phase and bounded deliverable at a time. Do not provision environments, connect to tenants, create real solution components, or expand into adjacent features without explicit authorization. Raise conflicts and missing dependencies; do not silently resolve business ambiguity by invention.

## Naming and terminology

Use BSO-RS-Support for the product and ATSugg for the legacy application. Preserve business meanings from ATSugg without carrying over obsolete technical constraints by default. The recommended naming strategy, pending approval, is Dataverse Publisher Prefix `os` plus project namespace segment `sr_`, producing final technical names beginning `os_sr_`. Use the short, consistent technical abbreviations and component-specific patterns in [Data Model](docs/DATA_MODEL.md). Where Power Apps adds the publisher prefix automatically, enter only the `sr_<abbreviation>` stem; where a component requires its full name, use the final `os_sr_<abbreviation>` once. Do not accidentally double-prefix. The owner-approved existing model-driven AppModule is the component-specific exception with actual unique name `srapp`; the prior `os_srapp` proposal is superseded for that app only. This exception does not alter `os_sr_*` naming for Dataverse tables. Display labels may retain clear business wording. Names are proposals until schema review; after approval, keep them stable and do not rename or recreate objects without an explicit migration plan. Do not encode personal data, roles, regions, tenant IDs, or connector identities into names. Abbreviations are not a security boundary; retain required access controls, auditing, DLP, and least-privilege protections.

## Documentation standards

Every document distinguishes current implementation, approved requirement, proposed design, external dependency, and open decision where applicable. Use relative links. Record sources and dates when material. Do not claim tests, permissions, integrations, environments, or deployed resources without evidence. Use synthetic examples only.

## Definition of Done

A change is done when it stays within approved scope; preserves production invariants; has meaningful documentation; includes proportionate validation; reports results truthfully; and leaves unrelated/user-owned files unchanged. Implementation phases also satisfy their approved acceptance criteria and security/ALM reviews.

## Change approval

Get explicit approval for material product, workflow, architecture, identity, privacy, security, or migration changes. Routine wording, typo, or link corrections may proceed. No automatic commit or push. Production changes require formal approval and a rollback plan.
