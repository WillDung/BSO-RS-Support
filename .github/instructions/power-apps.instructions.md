---
applyTo: "solutions/**/*"
---
# Power Apps Guidance

- Model-driven App conventions are the default for operational workflows; justify each Custom Page by interaction complexity or demonstrated usability need.
- Treat UI validation as helpful feedback, not an enforcement boundary. Critical business transitions must be protected by the approved Dataverse operation.
- Keep candidate status, owner, assigned TA, scheduling state, and audit visibility clear. Provide accessible keyboard interaction and explicit loading/error/empty states.
- Do not assume React or Tailwind tokens transfer directly to Power Apps. Do not create or claim components are deployed without approval and evidence.
- Follow [Master Production Rules](../../MASTER_PRODUCTION_RULES.md) and [UI/UX Guidelines](../../docs/UI_UX_GUIDELINES.md).
