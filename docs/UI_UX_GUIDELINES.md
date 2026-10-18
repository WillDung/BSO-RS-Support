# UI/UX Guidelines

**Status:** Proposed interaction direction for a future Power Apps implementation; no UI is implemented.

## Operating experience

Build a calm, enterprise-grade, data-dense operations console optimized for repeated BSO work. Use Model-driven App conventions by default and keep navigation predictable. Prioritize candidate queues, sortable/filterable tables, search, candidate status visibility, and direct access to candidate history and current actions. Avoid marketing-style landing pages and decorative card-heavy layouts.

## Candidate and scheduling clarity

Candidate detail should make ownership, assigned TA, status, CV URL availability, linked LEGO Career, recent calls, interview rounds/results, visitor records, and relevant audit history scannable. Make allowed next actions and blocked prerequisites explicit. Scheduling views must distinguish online/offline, time zone, TA and room availability evidence, attendees, booking state, and unresolved cancellation/reconciliation.

## Interaction and accessibility

Use Model-driven forms/views and standard accessible controls where sufficient. Use a Custom Page only when a complex workflow (for example, scheduling) cannot be made clear and efficient through standard patterns; document the justification. Support keyboard navigation, visible focus, accessible names, sufficient contrast, predictable tab order, and screen-reader-relevant status/errors. Do not rely on color alone.

Provide stable loading, empty, validation, success, failure, and indeterminate states. Never present an external action as complete merely because a Flow started. Keep responsive text within controls and avoid layout shifts when state changes.

## Design constraints

Do not assume React/Tailwind tokens map directly to Power Apps. Follow accessible Microsoft platform conventions and approved organizational design standards. Avoid exposing salary, contact information, CV links, or message snapshots to users without authorization. See [Security Model](SECURITY_MODEL.md) and [Acceptance Criteria](ACCEPTANCE_CRITERIA.md).
