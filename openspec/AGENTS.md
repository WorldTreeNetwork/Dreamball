# OpenSpec-lite

Instructions for agents. The durable copy of the rules is
[`project.md`](project.md). Living capability truth lives in
[`specs/<capability>/spec.md`](specs/) once a change is folded.

## Before any task

- Living truth is `openspec/specs/<capability>/spec.md`, not a SHALL in
  `changes/` or `docs/`.
- `changes/` is not a mandate. Read the disposition banner. PENDING is
  a draft. PARKED is not work. Archived means folded — do not implement it.
- Restore-only, typo, pin, comment, test-for-existing-spec: fix directly.
  Do not scaffold a change.
- New behavior: verb-led `change-id`, `proposal.md` + `tasks.md` + deltas.
  `design.md` only when cross-cutting.
- Do not start write work on PENDING or PARKED. Wait for ACTIVE BUILD
  (human activation) unless the rigor is vibe/brief and permission is already write.

## Deltas, not rewrites

```
## ADDED Requirements
### Requirement: <name>
The system SHALL …
#### Scenario: <name>
- GIVEN …
- WHEN …
- THEN …
```

MODIFIED pastes the entire living requirement, then edits.

## Search

- Specs: `openspec/specs/*/spec.md`
- In-flight: `openspec/changes/*/proposal.md` (skip `archive/`)
