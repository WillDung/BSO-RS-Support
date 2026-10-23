# Tests

Approved automated test source and synthetic fixtures. Separate unit, integration, authorization, concurrency, failure-recovery, UAT, and production smoke evidence. Never include real candidate data, CVs, credentials, or production exports. No business-application acceptance tests are claimed. See [Test Strategy](../docs/TEST_STRATEGY.md) and [Acceptance Criteria](../docs/ACCEPTANCE_CRITERIA.md).

## Reference Provisioning

[ReferenceTableProvisioning.Tests.ps1](ReferenceTableProvisioning.Tests.ps1) is a dependency-free PowerShell 7.4+ assertion harness. Run `& ./tests/ReferenceTableProvisioning.Tests.ps1` from the repository root. It uses only synthetic metadata and mocked transport; it does not authenticate, acquire tokens, invoke Apply, or make HTTP calls. Plain script assertions are not registered with VS Code's test-discovery API.

The UTC diagnostic timestamp assertion reads the JSON string without PowerShell's automatic culture-dependent date conversion, parses the round-trip value with invariant culture, and verifies a zero UTC offset. It also checks that a non-UTC offset is rejected. Coverage includes four exact schema plans, primary GUID/name/type/length/requiredness validation, Location Memo/Email fields, unexpected columns/keys/relationships, Solution inclusion positive/negative cases, POST/business-row guards, continuation-origin safety, token-refresh callback, Authorization/Content-Type/Solution header construction, HTTP 401/403 classification, diagnostic redaction, and no-retry behavior. The Position create-only recovery checks are synthetic/offline: table and identity gates, effective-privilege result handling, fixed payload fingerprint, one-POST/no-publish/no-extra-attribute guards, `MaximumRetryCount=0`, response-state classification, and GET-only reconciliation outcomes. Separate authenticated read-only DryRuns are documented in [Scripts](../scripts/README.md), not counted as these synthetic tests. Tests make no real HTTP calls.

## Readiness Capability Check

[ReadinessChecks.Tests.ps1](ReadinessChecks.Tests.ps1) is a dependency-free PowerShell 7.4+ assertion harness. Run `& ./tests/ReadinessChecks.Tests.ps1` from the repository root. Synthetic PAC help text verifies recognition of the model `create` command, rejects failed help commands, and rejects help without that command. Synthetic MCP and skill-lock objects verify that configuration is distinguished from discoverability/callability, wildcard/endpoint presence is reported without returning values, lock-path mismatches are detected, and duplicate names can be counted. It does not invoke PAC, authenticate, read local secrets, or access the network.

## Model-Driven App Composition

[ModelDrivenAppComposition.Tests.ps1](ModelDrivenAppComposition.Tests.ps1) is a dependency-free PowerShell 7.4+ assertion harness. Run `& ./tests/ModelDrivenAppComposition.Tests.ps1` from the repository root. It uses synthetic GUIDs, OData metadata, and Site Map XML; PAC, Az token, and HTTP commands are mocked to fail if reached. It verifies PlanOnly default behavior, typed payload keys/types, existing Site Map binding preservation, node ID/localization/metadata preservation, and fail-closed behavior for unexpected navigation. It makes no live calls and never invokes Apply.

## Model-Driven App Composition

[ModelDrivenAppComposition.Tests.ps1](ModelDrivenAppComposition.Tests.ps1) is a dependency-free PowerShell 7.4+ assertion harness for the Phase 2D preparation script. Run `& ./tests/ModelDrivenAppComposition.Tests.ps1` from the repository root. It uses synthetic Site Map XML and synthetic OData metadata; PAC, Az token, and HTTP calls are mocked to fail if reached. It verifies PlanOnly default behavior, exact typed payload IDs/types, existing Site Map binding preservation, node ID/metadata preservation, localization preservation, and fail-closed handling of unexpected navigation. It does not call Apply or the live Dataverse environment.

## Phase 3A Candidate Core Design

[Phase3ACandidateCoreDesign.Tests.ps1](Phase3ACandidateCoreDesign.Tests.ps1) validates the synthetic proposal manifest at [PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json](../docs/PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json). Run `& ./tests/Phase3ACandidateCoreDesign.Tests.ps1` from the repository root with PowerShell 7.4+. It checks the exact three-table scope, owner-approved Candidate Number/contact/owner decisions, both Choices, call-outcome side effects, workflow transitions, deferred LEGO Career dependency, reschedule history requirements, table-audit declarations, GUID CorrelationId idempotency keys, Custom API contract, external readiness gates, zero-tenant-operation declaration, and the report's manifest fingerprint. It makes no authentication, PAC, network, Dataverse, or business-data calls. Passing these assertions validates the proposal shape only; it is not a product-runtime or provisioning test.
