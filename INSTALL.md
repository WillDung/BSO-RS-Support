# BSO-RS-Support — VS Code Power Platform integration kit

**Purpose:** make GitHub Copilot Agent in VS Code the primary development cockpit for the BSO-RS-Support Power Platform application. This is a project-local overlay; it is **not** the app itself, and it does not install a remote MCP server or modify Dataverse until run in the user's workspace.

**Current truth from owner-provided reports:** VN LMV IT is the authorized development environment (technically Production); Publisher `os_bso_rs_support` (prefix `os`); unmanaged Solution `os_sr_bso_rs_support`; `os_sr_ta` exists and is verified; `os_sr_pos`, `os_sr_csrc`, `os_sr_loc` are absent. A real `os_sr_pos` metadata POST received HTTP 401; its root cause is UNKNOWN. No repeat of that write is authorized by this kit.

## Apply the overlay

1. Open your **BSO-RS-Support** repository in VS Code. **Do not apply this to ATSugg** (the separately supplied legacy repository).
2. Extract this archive into the BSO-RS-Support repository root, preserving `.github/`, `scripts/` and `docs/`. The paths in this archive are **additive**, not replacements of existing files. Inspect the diff before any Git operation.
3. Open PowerShell 7 terminal in VS Code and run:

   ```powershell
   pwsh -NoProfile -File .\scripts\Test-BsoVsCodeReadiness.ps1
   ```

   This is strictly read-only and performs a limited PAC environment/Solution check. It never exports a token, creates tables or reads business rows.
4. Install Microsoft-maintained Dataverse agent skills by a supported installer **after reviewing its source and installer permissions**. From VS Code GitHub Copilot, where the command is supported, Microsoft's repository documents:

   ```text
   /plugin install dataverse@awesome-copilot
   ```

   Alternate project-local skills install (select GitHub Copilot when prompted; **omit** `-g` to avoid global install):

   ```powershell
   npx skills add microsoft/Dataverse-skills -s "*"
   ```

   Official source: https://github.com/microsoft/Dataverse-skills . Availability and install behavior depend on VS Code, GitHub Copilot, Node/npm and organization policy. **Choose one route**; do not blindly install both. The official Dataverse Skills are an agent skill collection, not a replacement MCP server.
5. Keep the existing project's `.vscode/mcp.json` (Power Platform CLI MCP and Dataverse MCP). Do not replace it and do not create conflicting duplicate server names. In the VS Code Copilot tool chooser, check that the intended Dataverse MCP tools are discoverable and that the correct authorized environment is selected.
6. Start GitHub Copilot **Agent** and run the prompt `.github/prompts/bso-powerplatform-bootstrap.prompt.md` (VS Code prompt selector, or paste its body). After its report, use `.github/prompts/bso-powerplatform-build-next.prompt.md` for each agreed development slice.
7. You own Git commit/push/sync. The agent must not run these actions.

## What it can and cannot do

- Copilot + Dataverse Skills + MCP/SDK/Web API can author Dataverse tables, columns, relationships, forms/views, and manage solution artifacts **when authorized capabilities and permissions allow**.
- PAC CLI supports model-driven app creation where `pac model create` is present; Copilot must check your **installed** CLI help and independently verify the app is in the target Solution. Other app capabilities (custom pages, commands, Cloud Flows, custom APIs, plug-ins, security roles, integration connectors) require feature-specific tooling and tests; some may still require an interactive designer or tenant approval.
- **No tool bypasses Dataverse permissions or Conditional Access.** Installing a community MCP does not prove or repair the prior HTTP 401. The existing incident remains a gated recovery.
- Audit policy is unresolved; do not enable environment auditing, change retention or load real employee/candidate information.

## Project-wide invariant

Target platform is Model-driven App + optional Custom Pages + Dataverse + Cloud Flows/Outlook/Teams/SharePoint, no new React/FastAPI/PostgreSQL backend. The existing ATSugg repository is a functional reference, not the deployment target. All project-owned technical names use the approved `os_sr_*` convention (Publisher Prefix `os` + namespace `sr`). Do not restore deprecated TA approvals.

## Safe uninstall

Delete only the additive files listed in this kit's manifest if you choose not to use it. Any Dataverse Skills installed by an external tool must be uninstalled using that tool's documented mechanism. No external tool or module is installed by unpacking this archive.
