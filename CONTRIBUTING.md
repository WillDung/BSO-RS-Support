# Contributing

## Before changing files

Read the required documents listed in [AGENTS.md](AGENTS.md). Select a bounded phase/task, check the current state, and provide a preflight summary. Preserve existing decisions and content; raise conflicts instead of silently overwriting them.

## Change conventions

- Keep changes focused and use clear Markdown headings, relative links, and consistent status labels.
- Mark statements as current implementation, approved requirement, proposed design, external dependency, or open decision as relevant.
- Keep business terminology consistent with ATSugg meaning and the canonical workflow in [Master Production Rules](MASTER_PRODUCTION_RULES.md).
- Use synthetic data only. Never commit credentials, candidate data, CVs, or production configuration.
- Do not add fabricated Power Platform resources, generated exports, or test evidence.
- For implementation work, include relevant automated/manual validation and update the affected design and state documents.

## Review and commit

Review the full diff, links, security/privacy implications, ALM impact, and acceptance coverage. Use Conventional Commit format when a commit is explicitly requested, for example `docs: define scheduling failure behavior`. Contributors do not commit or push automatically.
