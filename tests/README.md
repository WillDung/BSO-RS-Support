# Tests

Approved automated test source and synthetic fixtures. Separate unit, integration, authorization, concurrency, failure-recovery, UAT, and production smoke evidence. Never include real candidate data, CVs, credentials, or production exports. No business-application acceptance tests are claimed. See [Test Strategy](../docs/TEST_STRATEGY.md) and [Acceptance Criteria](../docs/ACCEPTANCE_CRITERIA.md).

## Reference Provisioning

[ReferenceTableProvisioning.Tests.ps1](ReferenceTableProvisioning.Tests.ps1) is a dependency-free PowerShell 7.4+ assertion harness. Run `& ./tests/ReferenceTableProvisioning.Tests.ps1` from the repository root. It uses only synthetic metadata and mocked transport; it does not authenticate, acquire tokens, invoke Apply, or make HTTP calls. Plain script assertions are not registered with VS Code's test-discovery API.

On 20 October 2026, 46 assertions passed for four exact schema plans, primary GUID/name/type/length/requiredness validation, Location Memo/Email fields, unexpected columns/keys/relationships, Solution inclusion positive/negative cases, POST/business-row guards, continuation-origin safety, token-refresh callback, Authorization/Content-Type/Solution header construction, HTTP 401/403 classification, diagnostic redaction, and no-retry behavior. Separate authenticated read-only DryRuns are documented in [Scripts](../scripts/README.md), not counted as these synthetic tests. Tests make no real HTTP calls.
