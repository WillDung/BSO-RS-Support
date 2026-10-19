# Tests

Approved automated test source and synthetic fixtures. Separate unit, integration, authorization, concurrency, failure-recovery, UAT, and production smoke evidence. Never include real candidate data, CVs, credentials, or production exports. No business-application acceptance tests are claimed. See [Test Strategy](../docs/TEST_STRATEGY.md) and [Acceptance Criteria](../docs/ACCEPTANCE_CRITERIA.md).

## Reference Provisioning

[ReferenceTableProvisioning.Tests.ps1](ReferenceTableProvisioning.Tests.ps1) is a dependency-free PowerShell 7.4+ assertion harness. Run `& ./tests/ReferenceTableProvisioning.Tests.ps1` from the repository root. It uses only synthetic metadata and mocked transport; it does not authenticate, acquire tokens, invoke Apply, or make HTTP calls. Plain script assertions are not registered with VS Code's test-discovery API.

On 19 October 2026, 92 assertions passed for four exact schema plans, primary GUID/name/type/length/requiredness validation, Location Memo/Email fields and authoritative label, unexpected columns/keys/relationships, Solution include-subcomponents and explicit-column modes, excluded/shell/null/missing/duplicate membership rejection, POST/business-row guards, and continuation-origin safety. Separate authenticated read-only DryRuns are documented in [Scripts](../scripts/README.md), not counted as these synthetic tests. The new Apply paths remain unexecuted and require approval.
