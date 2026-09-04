---
sprint: sprint-003
sprint_size: standard
created: 2026-06-27
total_frs: 11
in_scope_frs: 11
deferred_frs: 0
estimated_stories: 13
estimated_epics: 3
velocity_basis: sprint-002
---

# Sprint Scope

> Historical sprint record. Zig-canonical / `Dreamball-m97.2` language in
> this folder is superseded by
> [ADR 2026-08-06](../../decisions/2026-08-06-rust-canonical.md).
> Do not implement the `@typeInfo` generator. VISION §17 is now §1.

## Sprint Size
**standard** (8–18 stories) — the MVP is a single coherent end-to-end slice (a new
wire type + its WASM authoring/verify surface + the cross-runtime determinism
gate). It cannot be meaningfully sub-divided below ~10 stories without shipping
something that doesn't round-trip. Not `ambitious` because the PRD's Growth/Vision
FRs (renderer dispatch, self-serve non-Zig authoring, palace extraction, m97.2
generator, PQ) are explicitly deferred.

## In-Scope Clusters

### Cluster A: Generic action envelope (the wire type)
- **FRs**: FR5 (open-kind/typed-body/HLC/parent_hashes envelope), FR3 (canonical
  dCBOR encode/decode), FR4 (schema + canonical-form validation), FR10 (native HLC),
  FR1 (define the type in the Zig-canonical pipeline).
- **Estimated stories**: 5–6
- **Complexity**: high (new wire type; HLC spec; dCBOR determinism; the Q1/Q4
  architecture decisions land here).
- **Rationale**: foundation — everything else encodes/signs/verifies this type.

### Cluster B: WASM authoring + JS surface
- **FRs**: FR6 (WASM encode+sign export), FR7 (TS loader wrapper, browser + Bun),
  FR9 (verify export + wrapper).
- **Estimated stories**: 4
- **Complexity**: medium (extends the existing packed-u64 export pattern, but must
  link `envelope_v2` into the WASM — TC6 — which is net-new binary code).
- **Depends on**: Cluster A.

### Cluster C: Determinism, codegen & gates
- **FRs**: FR8 (content_hash + cross-runtime golden vector), FR2 (generate
  downstream TS/Valibot/cbor.ts/JSON-Schema from the Zig type), FR11 (all gates green).
- **Estimated stories**: 3–4
- **Complexity**: medium (golden vectors across CLI+WASM; manual codegen propagation
  per TC5).
- **Depends on**: Cluster A (type), Cluster B (WASM build to hash against).

## Stretch Goals

### Cluster D: Second worked consumer type
- **FRs**: FR1/FR2 generality (a second type, e.g. `object3d`, authored through the
  same pipeline).
- **Estimated stories**: 2
- **Include if**: Clusters A–C complete cleanly. Proves the pipeline generalizes
  beyond the op envelope (de-risks the "open type system" claim) without being
  required for the World-Tree unblock.

## Deferred to Future Sprints
Everything mapped to PRD FR12–FR17 (already Out of Scope in requirements.md):
renderer-dispatch-by-field-presence (Growth), self-serve non-Zig type authoring
(Growth; Q3), dag-cbor↔native parity (Growth), Memory Palace extraction (Vision),
`@typeInfo` generator m97.2 (Vision), PQ WASM authoring (Vision). Tracked in beads
(`Dreamball-m97`, etc.) — no `.omc/backlog.md` present to append to.

## Scope Risks
- **Q1 unresolved (extend `ball.action` vs new `ball.op`)** — affects all three
  clusters. Mitigation: resolve in Phase 2A before story decomposition.
- **HLC spec (Q4) not yet written** — Cluster A blocks on it. Mitigation: write the
  HLC PROTOCOL.md note as the first Cluster-A story; freeze before content_hash.
- **envelope_v2 → WASM size** — Cluster B adds binary code; size relaxed (NFR5) but
  record it.

## FR Disposition Summary

| FR | Cluster | Status | Rationale |
|----|---------|--------|-----------|
| FR1 | A | IN | define the op type in the Zig pipeline (proves the pipeline) |
| FR2 | C | IN | generate downstream targets from the Zig type |
| FR3 | A | IN | canonical encode/decode |
| FR4 | A | IN | validation (schema + canonical-form) |
| FR5 | A | IN | the generic envelope itself (core) |
| FR6 | B | IN | WASM encode+sign export |
| FR7 | B | IN | TS loader wrapper |
| FR8 | C | IN | content_hash + cross-runtime golden vector |
| FR9 | B | IN | verify |
| FR10 | A | IN | native HLC |
| FR11 | C | IN | all gates green |
