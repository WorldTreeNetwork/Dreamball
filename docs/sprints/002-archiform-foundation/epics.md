---
project: Dreamball
sprint: sprint-002
phase: 2B-epic-design
inputDocuments:
  - requirements.md
  - architecture-decisions.md
  - sprint-scope.md
  - discovery.md
created: 2026-04-28
mode: default
steering: AUTONOMOUS
consensus_iterations: 0
epics_in_scope: 7
epics_stretch: 1
total_estimated_stories: 22
---

# Sprint-002 Epics — Archiform Foundation

This file is the Phase 2B output: epic-level decomposition of the 14 IN-scope FRs (and 1 deferred FR12) from `requirements.md`, constrained by decisions D-017..D-036 in `architecture-decisions.md`, and seeded by the cluster shape locked in `sprint-scope.md`. It is the input to Phase 3 (Story Decomposition).

The clustering work was done in Phase 1B; this phase formalizes those clusters as user-value-focused epics, maps every FR/NFR to exactly one epic, cites the architecture decisions that constrain each, and orders them so dependencies flow forward.

---

## Requirements Inventory

### Functional Requirements

| FR | Title | Disposition |
|----|-------|-------------|
| FR1  | Codegen Direction Inversion (root schema) | IN |
| FR2  | Root JSON Schema authoring | IN |
| FR3  | CBOR algorithm stays Zig-canonical with golden vectors | IN |
| FR4  | Memory Palace schema extraction | IN |
| FR5  | Genesis envelope `archiform_fp` field | IN |
| FR6  | Action manifest schema in JSON Schema | IN |
| FR7  | CLI projection from action manifest | IN |
| FR8  | Programmatic projection (TypeScript client) | IN |
| FR9  | MCP projection from action manifest | IN |
| FR10 | Wasm action host inside `jelly` CLI | IN |
| FR11 | `dreamball.*` import namespace | IN |
| FR12 | Bun-script fallback implementation path | **DEFER** (sprint-003+; per Q3 wasm-only sprint) |
| FR13 | Sprint-001 carry-over: Ed25519 sentinel migration | IN |
| FR14 | Migration rollout without breaking sprint-001 smoke gates | IN |
| FR15 | Documentation refresh of refined cross-runtime invariant | IN |

### Non-Functional Requirements

| NFR | Title | Primary epic(s) |
|-----|-------|-----------------|
| NFR1  | Codegen byte-equivalence (gating) | Epic 1 (A) |
| NFR2  | Codegen runtime budget (≤5 s) | Epic 1 (A) |
| NFR3  | Wasm action invocation latency (≤50 ms p95) | Epic 5 (E) |
| NFR4  | Wasm module first-time instantiation (≤100 ms) | Epic 5 (E) |
| NFR5  | kNN recall perf gate — no regression | Cross-cutting (Epics 1, 5; verified in 7) |
| NFR6  | CI total runtime — no material regression | Cross-cutting (all epics) |
| NFR7  | Wasm sandbox memory budget (16 MiB / 64 MiB ceiling) | Epic 5 (E) |
| NFR8  | Validate-on-publish, not validate-on-decode | Epics 1 (A), 5 (E) |
| NFR9  | Generated-file provenance headers | Epic 1 (A) |
| NFR10 | Schema-gen tool structured logging | Epic 1 (A) |
| NFR11 | Wasm action invocation structured events | Epic 5 (E) |

### Architecture Requirements (derived from D-017..D-036)

These are the hard architectural constraints that epic boundaries MUST respect. Each is cited inline by ID in the epic that owns it.

- **D-017** — Archiform registry (3-layer: schema/manifestation/instance); aspects.sh as registry; `archiform_fp` immutable per ball.
- **D-018** — JSON Schema (draft 2020-12) is canonical for field shapes; CBOR algorithm stays canonical in Zig with golden vectors.
- **D-019** — Action manifest is the universal action contract; pure transactions only (no interactive prompts in action bodies); CLI/programmatic/MCP projections only in sprint-002.
- **D-020** — Wasm is the runtime for all executable code in DreamBalls; WASI + `dreamball.*` imports only.
- **D-021** — LadybugDB transactional model: logical commit-ordering + replay-from-CAS (revises D-008).
- **D-022** — Bridge pattern: Zig staging → Bun bridge → promote-on-success.
- **D-023** — `signActionEnvelope(keypair_bytes, payload_bytes) → ed25519_sig_bytes` export in `jelly.wasm` (revises D-011 signer-parameterisation portion; PQ deferred per 2026-04-25 steering).
- **D-024** — Spike-before-promote default for new shaders/materials/lenses/wasm hosts.
- **D-025** — Forward-declare consumer seam contracts in `architecture-decisions.md`; cross-epic contracts are ADR-events, not story-events.
- **D-026** — Surface registry + `scroll`-baseline fallback chain (renderer-projection consequence; sprint-002 doc impact only).
- **D-027** — Coord frames: polar field, cartesian placements, nested reference frames (renderer-projection consequence; sprint-002 doc impact only).
- **D-028** — Triple-native KG storage (revises D-016); the `Triple` table + `HAS_KNOWLEDGE` rel are schema citizens.
- **D-029** — aspects.sh contract: vendor-first; pin file beside schema (`schemas/.pins/<archiform>-<version>.fp`); refresh path is opt-in Bun script.
- **D-030** — `tools/schema-gen/main.zig` repurposed as JSON-Schema consumer entry point; per-target generators as siblings; legacy moved to `tools/schema-gen/legacy/` for shadow phase, deleted at cutover.
- **D-031** — Wasm signing: signed schema body + content-addressed wasm (transitive authentication via aspects.sh's signing primitive); SEC4 verify-before-instantiate is blake3-only.
- **D-032** — Wasm host architecture: single shared Zig host code targeting CLI (Zig+WASI) and browser (`jelly.wasm`); same `dreamball.*` import contract for both.
- **D-033** — `dreamball.*` import surface locked to 5 imports for sprint-002 (`fp`, `encode_cbor`, `read_node`, `emit_action_envelope`, `now_ms`); any addition is a new ADR.
- **D-034** — Generated TS client wraps existing D-007 store wrapper; D-007 unchanged; IC6 satisfied.
- **D-035** — Action manifest `attributes` is a closed set (`destructive`, `requiresConfirmation`, `confirmationMessage`, `agentVisible`); `effects.kind` is a closed enum (`ActionEnvelope`, `Read`, `Derived`); validator rejects unknown.
- **D-036** — Test-tier defaults per cluster: A/E thorough; B/C/D/G/H smoke; nothing yolo.

### Technical / Security / Integration Constraints

These flow into specific epics by reference:

- **TC1** (zero wire-format change) — Epic 1 owns the byte-equivalence gate; every other epic inherits the constraint.
- **TC2** (all CI gates green) — Cross-cutting (D-036 codifies tier defaults; Epic 7 doc refresh exempt from functional test).
- **TC3** (JSON Schema draft 2020-12) — Epics 1, 2, 4 (manifest schema authoring).
- **TC4** (WASI + `dreamball.*` only) — Epic 5.
- **TC5** (wasm size budgets) — Epic 5 (`jelly.wasm` ≤ 200 KB raw / ≤ 64 KB gzipped includes the new `signActionEnvelope` export from Epic 6).
- **TC6** (aspects.sh vendor-first) — Epic 1 (D-029 pin format), Epic 7 (doc the contract).
- **TC7** (pinned dependency floor) — Cross-cutting; no upgrades in scope.
- **TC8** (content-addressing) — Epic 5 (wasm fps), Epic 1 (schema fps via D-029).
- **TC9** (recrypt naming inheritance) — Cross-cutting; reviewed at story spec time.
- **SEC1** (wasm sandbox host-import whitelist) — Epic 5.
- **SEC2** (host-mediated signing) — Epic 5 (consumes D-023 export from Epic 6).
- **SEC3** (Ed25519 sentinel migration) — Epic 6.
- **SEC4** (verify-before-instantiate) — Epic 5.
- **SEC5** (per-projection permissions; trusted-by-default in sprint-002) — Epic 5 (forward-pointer documented in Epic 7).
- **SEC6** (PQ + key-custody deferred) — Cross-cutting policy; Epic 6 enforces "Ed25519-only single sigs" per project memory.
- **IC1** (§13.7 surface registry unchanged) — Epic 2 (`archiform_fp` is additive back-compat).
- **IC2** (signed-action envelope frozen) — Epic 3, Epic 4, Epic 5 (action invocations serialize to existing envelope shape).
- **IC3** (recrypt sibling alignment) — Cross-cutting.
- **IC4** (sprint-001 instance compatibility) — Epic 1, Epic 2.
- **IC5** (aspects.sh read-vendored-first) — Epic 1, Epic 7.
- **IC6** (D-007 store API unchanged) — Epic 4 (D-034 mandates client wraps store).

---

## FR Coverage Map

Every IN FR maps to exactly one epic. FR12 is explicitly deferred and unmapped.

| FR | Epic # | Epic Name | Story (filled in Phase 3) |
|----|--------|-----------|---------------------------|
| FR1  | Epic 1 | Codegen Inversion Foundation | — |
| FR2  | Epic 1 | Codegen Inversion Foundation | — |
| FR3  | Epic 1 | Codegen Inversion Foundation | — |
| FR14 | Epic 1 | Codegen Inversion Foundation | — |
| FR4  | Epic 2 | Memory Palace as Archiform | — |
| FR5  | Epic 2 | Memory Palace as Archiform | — |
| FR6  | Epic 3 | Action Manifest + CLI Projection | — |
| FR7  | Epic 3 | Action Manifest + CLI Projection | — |
| FR8  | Epic 4 | Programmatic + MCP Projections | — |
| FR9  | Epic 4 | Programmatic + MCP Projections | — |
| FR10 | Epic 5 | Wasm Action Runtime | — |
| FR11 | Epic 5 | Wasm Action Runtime | — |
| FR13 | Epic 6 | Ed25519 Sentinel Migration (Carry-Over) | — |
| FR15 | Epic 7 | Documentation Refresh | — |
| FR12 | **DEFER** | (sprint-003+; per Q3 wasm-only sprint) | — |

**Coverage audit:**
- ✅ Every IN FR (FR1, FR2, FR3, FR4, FR5, FR6, FR7, FR8, FR9, FR10, FR11, FR13, FR14, FR15) appears exactly once.
- ✅ No orphans, no duplicates.
- ✅ FR12 explicitly marked DEFER with rationale.
- ✅ Every NFR is applicable to at least one epic (see Requirements Inventory table above).

---

## Epic List

| # | Title | Goal (one-line) | FRs | Estimated Stories | Complexity | Test Tier (D-036) |
|---|-------|-----------------|-----|-------------------|------------|-------------------|
| 1 | Codegen Inversion Foundation | After this epic, JSON Schema is the canonical source for all field shapes, with byte-equivalent regenerated outputs gated by a shadow-generator phase. | FR1, FR2, FR3, FR14 | 4–5 | HIGH | thorough |
| 2 | Memory Palace as Archiform | After this epic, Memory Palace is one archiform among many, declared in a vendored JSON Schema and bound by an `archiform_fp` field on the genesis envelope. | FR4, FR5 | 3 | MEDIUM | smoke |
| 3 | Action Manifest + CLI Projection | After this epic, archiform actions are declared in JSON Schema and the full `jelly palace *` CLI surface is mechanically projected from that manifest, with a pure-transaction lint enforcing no-prompts-in-action-bodies. | FR6, FR7 | 5 | MEDIUM-HIGH | smoke |
| 4 | Programmatic + MCP Projections | After this epic, the same action manifest is callable from any Bun script (typed TS client) and from any LLM agent (MCP tool spec), without hand-written per-projection code. | FR8, FR9 | 3 | MEDIUM | smoke |
| 5 | Wasm Action Runtime | After this epic, `jelly` CLI loads content-addressed wasm action modules under WASI through a 5-import `dreamball.*` namespace, with verify-before-instantiate and bounded memory. | FR10, FR11 | 4–5 | HIGH | thorough |
| 6 | Ed25519 Sentinel Migration (Carry-Over) | After this epic, every signed-action emission produces a real Ed25519 signature; no derived-fp sentinel substitutions remain in any signature-emitting path. | FR13 | 1–2 | LOW | smoke (with mandatory full-gate verification per `feedback_full_gate_verification`) |
| 7 | Documentation Refresh | After this epic, `ARCHITECTURE.md`, `PROTOCOL.md`, and `dreamball-imports.md` reflect the refined two-part cross-runtime invariant and the 5-import wasm contract; future agents will not drift from the architectural pivot. | FR15 | 1–2 | LOW | smoke (markdown lint + link checker + manual review) |
| 8 [STRETCH] | Sample Second Archiform (Federation Proof) | After this epic, a second tiny archiform (e.g., `dreamball/guestbook@0.1.0`) ships end-to-end through the new pipeline, proving the federation hypothesis. | (no FRs; integration test of the manifold) | 2–3 | MEDIUM | thorough |

**Total IN-scope stories:** ~22 (matches `sprint-scope.md` `estimated_stories: 22`).
**Total stretch stories:** +2–3 if Epic 8 activates.

**Epic count vs phase-state.json:** `epics_count: 7` (IN) + 1 STRETCH (Epic 8). Epic 8 is enumerated below for Phase 3 readiness but does not count against the IN total.

**Dependency graph:**

```
Epic 1 (Codegen Inversion) ──┬──► Epic 2 (Memory Palace Archiform) ──► Epic 3 (Action Manifest + CLI) ──► Epic 4 (Programmatic + MCP)
                             │                                                                                              │
                             │                                                                                              ▼
                             └──► Epic 5 (Wasm Action Runtime) ◄─── Epic 6 (Ed25519 Migration) [independent] ─►  Epic 7 (Doc Refresh)
                                                                                                                            ▲
                                                                                            (cross-cutting; depends on 1–6) ┘

                                           Epic 8 [STRETCH] depends on 1, 2, 3, 5
```

Forward-only edges; no cycles. Epic 1 has zero dependencies. Epic 6 has zero dependencies (parallelisable anytime). Epic 5 depends only on Epic 1 (for the regenerated CBOR codecs the host emits envelopes against; conservatively scheduled here — could fork after Epic 1 lands if capacity allows). Epic 7 is the cross-cutting final pass.

---

## Epic 1: Codegen Inversion Foundation

### Goal

After this epic, **JSON Schema (draft 2020-12) is the canonical source for all field shapes**, and the codegen toolchain at `tools/schema-gen/` consumes those schemas to emit Zig types, TypeScript types, Valibot validators, and CBOR codecs whose bytes are identical to today's outputs. A shadow-generator phase keeps every CI gate green at every commit boundary up to and including the cutover commit.

### Assigned Requirements

- **FR1** — Codegen Direction Inversion (root schema)
- **FR2** — Root JSON Schema authoring (`schemas/root-2.0.0.json`)
- **FR3** — CBOR algorithm stays Zig-canonical with golden vectors (`tests/golden/`)
- **FR14** — Migration rollout without breaking sprint-001 smoke gates (shadow-generator + byte-equivalence cutover commit)
- **NFR1** — Codegen byte-equivalence (gating; the binary acceptance gate for the entire epic)
- **NFR2** — Codegen runtime budget (≤ 5 s on M-series Mac baseline)
- **NFR8** — Validate-on-publish, not validate-on-decode (decoders never call Valibot; codegen is the validation event)
- **NFR9** — Generated-file provenance headers (every generated file: source schema fp, schema semver, generator fp/SHA, "DO NOT EDIT" banner)
- **NFR10** — Schema-gen tool structured logging (which schemas read, which generators dispatched, output bytes, byte-equivalence diff in verify mode)

### Architecture Constraints

- **D-018** — JSON Schema (draft 2020-12) canonical; CBOR algorithm stays in Zig. *Defines the inversion direction itself.*
- **D-029** — aspects.sh contract / pin file format (`schemas/.pins/root-2.0.0.fp`; build-time blake3 verification). *Defines where schemas and pins live; mandates verification at codegen time.*
- **D-030** — `tools/schema-gen/main.zig` repurposed as JSON-Schema consumer entry; per-target generators (`gen_zig.zig`, `gen_ts.zig`, `gen_valibot.zig`, `gen_cbor.zig`, `gen_cypher.zig`); legacy moved to `tools/schema-gen/legacy/` for shadow phase, deleted at cutover. *Defines file structure of the inverted toolchain.*
- **D-035** — Closed `attributes` set + closed `effects.kind` enum (relevant because the root schema authoring commits to the dialect that Epic 3's manifest schema extends).
- **D-024** — Spike-before-promote: lead with a spike that round-trips the three most expressively complex Zig types (envelope, sealed body, signature tier wrapper). Confirms Assumption #1 in `requirements.md` before scaling to the full root.
- **D-025** — Forward-declare consumer seam contracts: the JSON Schema dialect itself is a cross-epic contract; this epic locks it for Epics 2, 3, 4, 5.
- **TC1** — Zero wire-format change (the gate this epic exists to defend).
- **TC3** — JSON Schema draft 2020-12 (the dialect this epic commits to).
- **TC6** — aspects.sh vendor-first contract (the schema lives in `schemas/` and is fp-pinned regardless of aspects.sh availability).
- **IC4** — Sprint-001 instance compatibility (ensured by NFR1 byte-equivalence).

### Dependencies

- **Depends on:** None. This is the foundation epic; Epic 1 has zero dependencies on any other epic in the sprint.
- **Enables:** Epic 2 (archiform extraction depends on the codegen flow), Epic 3 (action manifest schema is JSON-Schema-defined), Epic 4 (TS client and MCP spec are codegen outputs), Epic 5 (wasm host emits envelopes encoded via the regenerated CBOR codecs), Epic 7 (documentation cites the new flow), Epic 8 stretch (second archiform exercises the same flow).

### Estimated Complexity

**HIGH** — Justification:
- 4 FRs and 5 NFRs (the heaviest requirement load of any epic).
- NFR1 byte-equivalence is a binary gate with no partial credit; a single non-deterministic byte fails the migration.
- Touches every file in `src/lib/generated/` (`types.ts`, `schemas.ts`, `cbor.ts`, `cbor.test.ts`) plus `src/memory-palace/schema.cypher` (becomes generated) plus `tools/schema-gen/*` (new file structure per D-030).
- Five separate per-target generators (Zig, TS, Valibot, CBOR, Cypher) all need to land green together.
- Shadow-generator phase (FR14) requires running both the legacy and new generators in parallel CI for the duration of the migration, with byte-equivalence diffing every PR — extra build wiring complexity.
- D-024 mandates a leading spike (the three-most-complex-types round-trip) before scaling, so the epic carries a spike-before-promote budget.

### Test Tier (per D-036)

**thorough** — All 7 gates required: `zig build test`, `zig build smoke`, `bun run check`, `bun run test:unit -- --run`, `scripts/cli-smoke.sh`, `scripts/server-smoke.sh`, `tests/e2e-cryptography.sh`. NFR1 byte-equivalence is itself a custom test gate (`tests/codegen/byte-equivalence.test.ts` or Zig equivalent) added by FR1 acceptance.

### Stories

#### Story 1.1: Codegen Inversion Spike — Round-Trip Three Complex Zig Types

**User Story**: As a Dreamball maintainer, I want a spike that round-trips the three most expressively complex Zig types (envelope, sealed body, signature tier wrapper) through hand-authored JSON Schema and back to byte-identical Zig+TS+Valibot+CBOR outputs, so that Assumption #1 in `requirements.md` is validated before scaling to the full root.
**FRs**: FR1, FR2, FR3 · **Decisions**: D-018, D-024, D-030, D-035, NFR1 · **Complexity**: large · **Test Tier**: thorough

#### Story 1.2: Author `schemas/root-2.0.0.json` + Pin File Format

**User Story**: As an archiform author, I want `schemas/root-2.0.0.json` to fully express the current Zig root type system in JSON Schema draft 2020-12 with a deterministic blake3 pin recorded at `schemas/.pins/root-2.0.0.fp`, so that all downstream codegen consumers have one canonical, fp-pinned source of truth for root field shapes.
**FRs**: FR2, FR14 · **Decisions**: D-018, D-029, D-035, TC3, TC6, TC8, IC4 · **Complexity**: medium · **Test Tier**: thorough

#### Story 1.3: Build Per-Target Generators with Provenance + Logging

**User Story**: As a future runtime, I want `tools/schema-gen/main.zig` to repurpose as the JSON-Schema consumer entry point and dispatch to five per-target generators (`gen_zig`, `gen_ts`, `gen_valibot`, `gen_cbor`, `gen_cypher`) that each emit provenance-headed outputs with structured logging, so that every codegen artifact carries traceable origin metadata.
**FRs**: FR1 · **Decisions**: D-030, D-018, NFR9, NFR10, NFR2, NFR8 · **Complexity**: large · **Test Tier**: thorough

#### Story 1.4: Shadow-Generator Phase + Byte-Equivalence CI Gate

**User Story**: As a CI gate, I want the legacy generator and the new JSON-Schema-driven generator to run side-by-side emitting to `src/lib/generated/` and `src/lib/generated.legacy/` respectively, with a byte-equivalence test diffing the two trees on every PR, so that NFR1 is verified continuously.
**FRs**: FR14, FR1 · **Decisions**: D-030, NFR1, TC1, TC2, IC4 · **Complexity**: medium · **Test Tier**: thorough

#### Story 1.5: Cutover Commit — Delete `tools/schema-gen/legacy/` and `src/lib/generated.legacy/`

**User Story**: As a release engineer, I want one atomic cutover commit that deletes the legacy generator and its shadow output tree, leaving only the JSON-Schema-driven generator in place, so that the architectural pivot is observable in git history as a single, reversible event with all CI gates green.
**FRs**: FR14, FR1 · **Decisions**: D-030, TC1, TC2, NFR1 · **Complexity**: small · **Test Tier**: thorough

*(See `stories/1.{1..5}-*.md` for full BDD acceptance criteria, technical notes, and scope boundaries.)*

## Epic 1 Health Metrics
- **Story count**: 5 (within 4–5 band)
- **Complexity**: 0 small, 2 medium, 2 large, 1 small (1 small / 2 medium / 2 large)
- **FR coverage**: all FRs covered (FR1, FR2, FR3, FR14)
- **Dependency flags**: none within-epic; downstream blocker for Epics 2–7 (foundation)
- **Test tier distribution**: 0 yolo, 0 smoke, 5 thorough (justified — Cluster A per D-036)

---

## Epic 2: Memory Palace as Archiform

### Goal

After this epic, **Memory Palace is one archiform among many**: its schema is extracted from the current Zig source and the hand-maintained `src/memory-palace/schema.cypher` into a vendored, fp-pinned `schemas/memory-palace-0.1.0.json`; per-archiform codegen produces the Zig extensions, TS extensions, Valibot validators, and Cypher DDL from that pinned schema; and every genesis envelope carries an immutable `archiform_fp` field with implicit-binding back-compat for sprint-001 instances that lack it.

### Assigned Requirements

- **FR4** — Memory Palace schema extraction (`schemas/memory-palace-0.1.0.json` + `schemas/.pins/memory-palace-0.1.0.fp`; per-archiform codegen pass; generated Cypher DDL byte-matches pre-migration)
- **FR5** — Genesis envelope `archiform_fp` field (additive, back-compat: sprint-001 envelopes without the field decode to implicit `dreamball/memory-palace@0.1.0` fp)
- **NFR5** — kNN recall perf gate — no regression (cross-cutting, but Memory Palace is the kNN-bearing archiform; this epic is where the regression risk concentrates)

### Architecture Constraints

- **D-017** — Archiform registry / 3-layer model: Memory Palace is the schema-layer archiform; `archiform_fp` is genesis-immutable per ball's lifetime.
- **D-018** — Per-archiform codegen (Zig + TS + Valibot + Cypher) consumes the per-archiform JSON Schema; CBOR algorithm stays Zig.
- **D-021** — LadybugDB transactional model (logical commit-ordering + replay-from-CAS). Memory Palace mutation paths inherit this; the generated Cypher DDL must remain compatible with the existing replay-from-CAS shape.
- **D-028** — Triple-native KG storage. Generated Cypher DDL MUST include the `Triple` table + `HAS_KNOWLEDGE` rel + `Palace→Agent CONTAINS` edge + `Aqueduct.last_traversal_ts` as schema citizens (revising D-016).
- **D-029** — Pin file (`schemas/.pins/memory-palace-0.1.0.fp`) records blake3 of the vendored schema; build-time verification fails on mismatch.
- **IC1** — §13.7 surface registry unchanged; `archiform_fp` is additive back-compat.
- **IC4** — Sprint-001 instance compatibility (ensured by NFR1 byte-equivalence inherited from Epic 1, plus the implicit-binding back-compat in FR5 acceptance).
- **TC3** — JSON Schema draft 2020-12 dialect (per-archiform schemas honor the same dialect Epic 1 commits to).

### Dependencies

- **Depends on:** Epic 1 (the codegen flow that consumes per-archiform schemas must exist; the `tools/schema-gen/main.zig` JSON-Schema-consumer entry point and the `gen_cypher.zig` generator are Epic 1 deliverables).
- **Enables:** Epic 3 (the Memory Palace schema is where action manifests are declared), Epic 8 stretch (second archiform follows the same authoring template).

### Estimated Complexity

**MEDIUM** — Justification:
- 2 FRs of moderate scope; the heavy lifting (codegen flow) is in Epic 1.
- The schema extraction is mostly translation: existing Zig types and `schema.cypher` are the source material; the work is faithful translation into JSON Schema with no semantic change.
- The `archiform_fp` genesis-envelope addition is small surface (one field) but has an explicit back-compat decode test that exercises sprint-001 envelopes.
- The byte-equivalence requirement on generated Cypher DDL (or "documented, justified semantically-equivalent diffs") is a real rabbit hole if the current `schema.cypher` has whitespace/comment patterns the generator must replicate; budget accordingly.
- 3 stories estimated — well within the 2–6 size band; no SIZE WARNING.

### Test Tier (per D-036)

**smoke** — Cluster B default. Must pass: `zig build test`, `zig build smoke`, `bun run check`, `bun run test:unit -- --run`, `scripts/cli-smoke.sh`, `scripts/server-smoke.sh`. (NFR1 byte-equivalence inherits from Epic 1's gate.)

### Stories

#### Story 2.1: Extract Memory Palace Types into `schemas/memory-palace-0.1.0.json` + Pin

**User Story**: As an archiform author, I want Memory Palace types extracted from `src/protocol_v2.zig` and `src/memory-palace/schema.cypher` into a single vendored `schemas/memory-palace-0.1.0.json` with a pinned blake3 fp, so that Memory Palace becomes one archiform among many — declared in JSON Schema, fp-pinned, and ready for per-archiform codegen.
**FRs**: FR4 · **Decisions**: D-017, D-018, D-028, D-029, TC3, TC8, IC1 · **Complexity**: medium · **Test Tier**: smoke

#### Story 2.2: Per-Archiform Codegen Pass + Cypher DDL Byte-Equivalence

**User Story**: As a future runtime, I want the per-archiform codegen pass to consume `schemas/memory-palace-0.1.0.json` and emit Zig + TS + Valibot + Cypher DDL, with the generated `schema.cypher` byte-matching (or with documented semantically-equivalent diffs against) the pre-migration hand-maintained file, so that Memory Palace becomes generated end-to-end without behavioral regression.
**FRs**: FR4 · **Decisions**: D-018, D-028, D-029, D-030, NFR1, NFR5 · **Complexity**: medium · **Test Tier**: thorough (escalated from smoke — touches NFR1 byte-equivalence inheritance)

#### Story 2.3: Genesis Envelope `archiform_fp` Field with Implicit-Binding Back-Compat

**User Story**: As a future runtime, I want the genesis envelope CBOR shape to carry an immutable `archiform_fp` field, with sprint-001 envelopes lacking the field decoding successfully via implicit binding to `dreamball/memory-palace@0.1.0`, so that every ball declares its archiform on the wire from sprint-002 forward without breaking pre-existing instances.
**FRs**: FR5 · **Decisions**: D-017, IC1, IC4, TC8 · **Complexity**: medium · **Test Tier**: thorough (escalated from smoke — wire-format addition per D-036 escalation rule)

*(See `stories/2.{1..3}-*.md` for full BDD acceptance criteria.)*

## Epic 2 Health Metrics
- **Story count**: 3 (within 3 target)
- **Complexity**: 0 small, 3 medium, 0 large
- **FR coverage**: all FRs covered (FR4, FR5)
- **Dependency flags**: depends on Epic 1 (codegen flow); enables Epic 3 (manifest authoring inside this schema)
- **Test tier distribution**: 0 yolo, 1 smoke, 2 thorough (escalations documented inline)

---

## Epic 3: Action Manifest + CLI Projection

### Goal

After this epic, **archiform actions are declared in JSON Schema and the full `jelly palace *` CLI verb surface is projected mechanically from that manifest** — no hand-written verb dispatch in `src/cli/palace*.zig`. The `mint`, `inscribe`, `add-room`, `rename-mythos`, and `move` verbs all derive their `--help`, flag mapping, JSON output shape, and confirmation behavior from the manifest. A pure-transaction lint enforces no interactive prompts inside action bodies; a closed-set validator rejects malformed manifests at codegen time.

### Assigned Requirements

- **FR6** — Action manifest schema in JSON Schema (closed `attributes` set + closed `effects.kind` enum; pure-transaction lint rejects `prompt`/`confirm`/`tty-interactive` inputs)
- **FR7** — CLI projection from action manifest (full 5-verb coverage per Q7; confirmation behavior driven by `attributes.requiresConfirmation` + `attributes.destructive`; `--yes` / `--no-confirm` overrides; `scripts/cli-smoke.sh` passes against the generated dispatcher)

### Architecture Constraints

- **D-019** — Action manifest is the universal action contract; pure transactions only; CLI is one of three sprint-002 projections.
- **D-022** — Bridge pattern for mutation actions: each generated CLI verb composes the canonical staging-dir → bridge → promote-on-success pattern; new verbs follow the same template as `src/lib/bridge/palace-{mint,add-room,inscribe,move,rename-mythos}.ts`.
- **D-024** — Spike-before-promote: the first action manifest authoring + CLI projection (likely `mint`) ships as a spike before scaling to all 5 verbs.
- **D-025** — Forward-declare contracts: the action manifest shape is a cross-epic contract (consumed by Epics 4 and 5); locked in this epic before Epic 4 dispatches.
- **D-035** — Closed `attributes` (`destructive`, `requiresConfirmation`, `confirmationMessage`, `agentVisible`) + closed `effects.kind` enum (`ActionEnvelope`, `Read`, `Derived`); validator rejects unknown keys/values.
- **D-036** — Test-tier defaults (smoke for this cluster; CLI-smoke is the existing gate that catches behavioral regressions).
- **IC2** — Signed-action envelope shape frozen: action invocations serialize to the existing envelope shape; no new top-level fields.

### Dependencies

- **Depends on:** Epic 2 (the action manifest is declared inside the Memory Palace JSON Schema; the per-archiform codegen flow that emits the manifest's typed surface is established in Epic 2). Transitively depends on Epic 1.
- **Enables:** Epic 4 (TS client + MCP spec project from the same manifest authored here), Epic 5 (wasm action runtime executes the actions declared here, via `implementation.wasm` fps).

### Estimated Complexity

**MEDIUM-HIGH** — Justification:
- 2 FRs but full verb coverage means 5 verbs × (manifest authoring + projection generator + smoke verification) = a wide surface.
- Pure-transaction lint is new test infrastructure — must be authored + integrated into codegen.
- Closed-set validator rejection cases (unknown attributes, unknown `effects.kind`, unknown `idempotency` enum, malformed `implementation.wasm` fp) all need test coverage.
- Confirmation prompt behavior (`requiresConfirmation` + `destructive` → TTY prompt unless `--yes`) is non-trivial CLI logic; subtle regressions here would fail `scripts/cli-smoke.sh`.
- D-024 mandates a leading spike (likely `mint`) before scaling — adds a story but de-risks the rest.
- 5 stories estimated — within the 2–6 size band; no SIZE WARNING.

### Test Tier (per D-036)

**smoke** — Cluster C default. CLI smoke (`scripts/cli-smoke.sh`) is the existing gate. Must also pass: `zig build test`, `zig build smoke`, `bun run check`, `bun run test:unit -- --run`, `scripts/server-smoke.sh`. The pure-transaction lint adds a new Vitest target.

### Stories

#### Story 3.1: Action Manifest Schema in Memory Palace JSON Schema + Closed-Set Validator + Pure-Transaction Lint

**User Story**: As an archiform author, I want the action-manifest section of `schemas/memory-palace-0.1.0.json` to declare every sprint-001 verb with closed `attributes` keys and closed `effects.kind` enum, with the generated Valibot validator rejecting unknown keys/values and a pure-transaction lint rejecting interactive input fields, so that every projection inherits one mechanically-checkable contract.
**FRs**: FR6 · **Decisions**: D-019, D-025, D-035, D-024 · **Complexity**: medium · **Test Tier**: smoke

#### Story 3.2: CLI Projection Spike — Project `mint` Verb End-to-End from Action Manifest

**User Story**: As a Dreamball maintainer, I want a spike that projects the `mint` action manifest entry into a generated `jelly palace mint` CLI verb, with `scripts/cli-smoke.sh` covering `mint` passing against the generated dispatcher, so that the projection generator architecture is validated on one verb before scaling.
**FRs**: FR7 · **Decisions**: D-019, D-022, D-024, D-035 · **Complexity**: medium · **Test Tier**: smoke

#### Story 3.3: CLI Projection — `inscribe` and `add-room` Verbs

**User Story**: As an archiform author, I want `jelly palace inscribe` and `jelly palace add-room` to be mechanically projected from the action manifest using the architecture spiked in Story 3.2.
**FRs**: FR7 · **Decisions**: D-019, D-022, D-035, IC2 · **Complexity**: medium · **Test Tier**: smoke

#### Story 3.4: CLI Projection — `rename-mythos` and `move` Verbs

**User Story**: As an archiform author, I want `jelly palace rename-mythos` and `jelly palace move` to be mechanically projected from the action manifest, so the full sprint-001 verb surface is generated.
**FRs**: FR7 · **Decisions**: D-019, D-022, D-035, IC2 · **Complexity**: medium · **Test Tier**: smoke

#### Story 3.5: Remove Hand-Written `src/cli/palace_*.zig` Stubs + CLI Dispatch Cutover

**User Story**: As a release engineer, I want one atomic commit that removes the hand-written verb stubs and updates `src/cli/palace.zig` to dispatch to `src/cli/generated/*` exclusively, so that the FR7 acceptance is closed atomically with all CI gates green.
**FRs**: FR7 · **Decisions**: D-013, D-019, D-022, TC2 · **Complexity**: small · **Test Tier**: smoke

*(See `stories/3.{1..5}-*.md` for full BDD acceptance criteria.)*

## Epic 3 Health Metrics
- **Story count**: 5 (within 5 target)
- **Complexity**: 1 small, 4 medium, 0 large
- **FR coverage**: all FRs covered (FR6, FR7); full 5-verb coverage per Q7
- **Dependency flags**: depends on Epic 2 (manifest declared in Memory Palace schema); enables Epic 4 + 5
- **Test tier distribution**: 0 yolo, 5 smoke, 0 thorough (Cluster C default per D-036)

---

## Epic 4: Programmatic + MCP Projections

### Goal

After this epic, **the same action manifest authored in Epic 3 is callable from any Bun script and from any LLM agent** — a typed TypeScript client (`@dreamball/palace-client`) exposes each action as a function with compile-time-checked input/output shapes; an MCP tool server exposes each action as an MCP tool with input schemas validated by the same Valibot validator the CLI uses, and routes `requiresConfirmation` through MCP elicitation. At least one existing `src/lib/bridge/*` mutation site is migrated to call the generated client and continues to satisfy its existing Vitest coverage. The D-007 store wrapper API stays unchanged.

### Assigned Requirements

- **FR8** — Programmatic projection (TypeScript client; typed `mint({ name, mythosTemplate }) → { palaceFp }`; bridge migration site verified)
- **FR9** — MCP projection (one MCP tool per action; MCP elicitation for `requiresConfirmation` actions; tool input schemas validated by shared Valibot validator)

### Architecture Constraints

- **D-019** — Action manifest as universal action contract: programmatic + MCP are two of three sprint-002 projections; both project mechanically from the manifest.
- **D-034** — Generated TS client wraps existing D-007 store wrapper; D-007 unchanged. The client is the *external* (callsite) API; store wrapper remains the *internal* (mutation primitive) API. AC7-style grep audits carry forward unchanged.
- **D-022** — Bridge pattern: generated client calls store verbs which use the bridge pattern; mutations cross Zig↔TS exactly as today.
- **D-035** — Closed `attributes` / `effects.kind`: both the TS client and the MCP tool spec inherit the closed-set typing; type errors on drift.
- **IC2** — Signed-action envelope frozen: programmatic + MCP invocations serialize to the existing envelope shape via the manifest's `effects.kind: ActionEnvelope` surface.
- **IC6** — D-007 store API unchanged (the constraint that motivates D-034 Option A).

### Dependencies

- **Depends on:** Epic 3 (the action manifest must be authored and validated before two more projections can be generated from it). Transitively depends on Epics 1 and 2.
- **Enables:** Epic 7 (documentation refresh cites the generated client as the canonical Bun-side mutation API; MCP usage docs reference the elicitation flow), Epic 8 stretch (second archiform's actions are callable through the same client/MCP machinery without new code).

### Estimated Complexity

**MEDIUM** — Justification:
- 2 FRs; both are mechanical projections of an already-authored manifest, so the heavy design work is in Epic 3.
- TS client codegen is straightforward (manifest → typed function exports); the bridge migration site is a real integration test but small in scope (one site to migrate, existing Vitest already exercising it).
- MCP projection has one architectural risk: the elicitation flow assumed by D-019 (per Assumption #9 in `requirements.md`) needs a spike against the pinned MCP SDK to confirm support; if elicitation isn't first-class, the design downgrades to a two-call preview/commit idiom.
- New AC suggested by D-034 §Consequences: grep audit that the generated client never imports LadybugDB primitives directly (always goes through `store.ts`). Adds one test surface but cheap.
- 3 stories estimated — within the 2–6 size band; no SIZE WARNING.

### Test Tier (per D-036)

**smoke** — Cluster D default. Vitest covers the bridge migration site; the new client + MCP tools have their own Vitest. Full gate set: `zig build test`, `zig build smoke`, `bun run check`, `bun run test:unit -- --run`, `scripts/cli-smoke.sh`, `scripts/server-smoke.sh`.

### Stories

#### Story 4.1: Generate `@dreamball/palace-client` TypeScript Client + Migrate One Bridge Site

**User Story**: As an agent caller, I want a generated `@dreamball/palace-client` TypeScript module exposing each Memory Palace action as a typed function that wraps the existing D-007 store wrapper, with at least one existing `src/lib/bridge/*` mutation site migrated to call the generated client.
**FRs**: FR8 · **Decisions**: D-019, D-022, D-034, D-035, IC2, IC6 · **Complexity**: medium · **Test Tier**: smoke

#### Story 4.2: Generate MCP Tool Spec + Spike MCP Elicitation Against Pinned SDK

**User Story**: As an agent caller, I want an MCP tool spec generated from the action manifest with confirmation routed through MCP elicitation, with a spike confirming MCP elicitation is supported in the pinned MCP SDK version, so that LLM agents can drive Memory Palace.
**FRs**: FR9 · **Decisions**: D-019, D-035, TC7 · **Complexity**: medium · **Test Tier**: smoke

#### Story 4.3: MCP Server Entrypoint (`bun run mcp`)

**User Story**: As a release engineer, I want a `bun run mcp` entrypoint that hosts the generated MCP tool spec and routes invocations through the generated TS client, so that a Memory Palace MCP server is invokable end-to-end.
**FRs**: FR9 · **Decisions**: D-019, D-034, TC7 · **Complexity**: small · **Test Tier**: smoke

*(See `stories/4.{1..3}-*.md` for full BDD acceptance criteria.)*

## Epic 4 Health Metrics
- **Story count**: 3 (within 3 target)
- **Complexity**: 1 small, 2 medium, 0 large
- **FR coverage**: all FRs covered (FR8, FR9)
- **Dependency flags**: depends on Epic 3 (manifest authoring); enables Epic 7 (doc refresh cites client + MCP)
- **Test tier distribution**: 0 yolo, 3 smoke, 0 thorough (Cluster D default per D-036)

---

## Epic 5: Wasm Action Runtime

### Goal

After this epic, **`jelly` CLI loads content-addressed wasm action modules under WASI through a 5-import `dreamball.*` namespace** — the wasm host verifies `blake3(wasm_bytes) == implementation.wasm` before instantiation, rejects guests that import outside `dreamball.*`, enforces the 16 MiB initial / 64 MiB hard-ceiling memory budget, and emits structured invocation events. The host code is implemented once in Zig and compiled both for the CLI (with WASI) and as the wasm portion of the cross-runtime story (no source divergence). A sample `mint.wasm` runs end-to-end and produces a host-signed envelope via `dreamball.emit_action_envelope`.

### Assigned Requirements

- **FR10** — Wasm action host inside `jelly` CLI (load content-addressed wasm; verify blake3; WASI; 16 MiB default memory configurable via `--wasm-mem-mib`; host code reusable in browser)
- **FR11** — `dreamball.*` import namespace (sprint-002 surface: `dreamball.fp`, `encode_cbor`, `read_node`, `emit_action_envelope`, `now_ms`; module importing outside `dreamball.*` fails to instantiate; each enumerated import exercised by ≥1 test; `docs/dreamball-imports.md` enumerates surface)
- **NFR3** — Wasm action invocation latency ≤ 50 ms p95
- **NFR4** — Wasm module first-time instantiation ≤ 100 ms (sub-1 MB module)
- **NFR7** — Wasm sandbox memory budget (16 MiB initial, 64 MiB hard ceiling, OOM → trap → projection-layer error)
- **NFR8** — Validate-on-publish, not validate-on-decode (the wasm host's emitted envelopes go through CBOR encode without per-call schema validation)
- **NFR11** — Wasm action invocation structured events (action name, actor fp, archiform fp, module fp, duration ms, emit count, outcome)

### Architecture Constraints

- **D-020** — Wasm is the runtime; WASI + `dreamball.*` only. *Defines the runtime model itself.*
- **D-031** — Signed schema body + content-addressed wasm (transitive authentication). SEC4 verify-before-instantiate is blake3-only — no per-module signature check needed in sprint-002.
- **D-032** — Single shared Zig host code targeting CLI (Zig+WASI) and browser (`jelly.wasm`). FR10 acceptance ("host code reusable in browser without source divergence") is the contract this decision implements.
- **D-033** — `dreamball.*` import surface locked to exactly 5 imports for sprint-002; any addition is a new ADR. Mid-sprint discovery of a missing import = blocker per `feedback_dreamball_ac_scope_retreat`.
- **D-024** — Spike-before-promote: the first wasm action implementation (minimal `mint.wasm` → `dreamball.*` host → emit envelope → smoke pass) ships as a spike before scaling to all 5 verbs.
- **D-025** — Forward-declare contracts: the `dreamball.*` import surface is the cross-epic contract that this epic delivers; the contract was locked at Phase 2A (D-033) and this epic implements it.
- **D-022** — Bridge pattern: the wasm host's `dreamball.emit_action_envelope` brokers staging → promote-on-success exactly as `src/lib/bridge/*` does for the CLI bridges.
- **D-023** — `signActionEnvelope` export on `jelly.wasm` (Epic 6) is consumed by the wasm action host's `emit_action_envelope` to produce signatures. **Cross-epic seam:** Epic 5 calls into Epic 6's export.
- **TC4** — WASI + `dreamball.*` imports only.
- **TC5** — Wasm size budgets: `jelly.wasm` ≤ 200 KB raw / ≤ 64 KB gzipped; archiform action modules soft target < 1 MB.
- **TC8** — Content-addressing: wasm modules addressed by `blake3(wasm_bytes)`; `implementation.wasm` is an fp pointer.
- **SEC1** — Wasm sandbox host-import whitelist (modules importing outside `dreamball.*` rejected at module load).
- **SEC2** — Action envelope signing: host-mediated only (guest cannot forge signatures because it has no private key access; host calls `signActionEnvelope` after action returns).
- **SEC4** — Verify-before-instantiate (blake3 match before instantiation; mismatch aborts + emits structured failure event).
- **SEC5** — Per-projection permission grants (sprint-002 trusted-by-default; full `dreamball.*` granted to CLI; per-projection registry deferred to sprint-003 with forward-pointer in Epic 7 docs).
- **IC2** — Signed-action envelope shape frozen: wasm-emitted envelopes serialize to the existing shape.

### Dependencies

- **Depends on:** Epic 1 (wasm host emits envelopes encoded via the regenerated CBOR codecs; the `dreamball.encode_cbor` import calls into the regenerated codec). Effectively Epic 5 can fork after Epic 1 lands; conservatively scheduled here so the host + Cluster C/D can be reasoned about jointly.
- **Cross-epic seam to Epic 6:** Consumes the `signActionEnvelope` export on `jelly.wasm` (D-023 / FR13 deliverable). Epic 5's `dreamball.emit_action_envelope` host implementation calls this export. Phase 3 must sequence Epic 6 (or at least the `signActionEnvelope` export portion) before the Epic 5 spike completes; alternatively, Epic 5 spike can stub the signature with a sentinel ONLY internally and ONLY for the spike, with the seam wired to the real export before the cluster lands green.
- **Enables:** Epic 7 (documentation refresh cites `docs/dreamball-imports.md` and the wasm host architecture; sprint-003 renderer projection inherits the host with no new code), Epic 8 stretch (second archiform's wasm actions run on the same host with no host changes).

### Estimated Complexity

**HIGH** — Justification:
- 2 FRs and 5 NFRs (the second-heaviest requirement load after Epic 1).
- New runtime surface in `jelly` CLI: wasm runtime selection (Zig std `wasm` vs `wasmtime`/`wasmer` C ABI) is a Phase 3 spike outcome, not a Phase 2B given.
- Cross-platform WASI parity (darwin + linux) per Assumption #2 — must confirm in spike, otherwise D-032 single-shared-host commitment may need amendment to allow per-platform shims.
- 5 separate `dreamball.*` imports each need: Zig host implementation, type marshalling between guest CBOR and host Zig types, error semantics, structured logging hook, ≥1 test (per FR11 acceptance).
- Verify-before-instantiate failure mode, import-violation failure mode, memory-limit failure mode all need explicit test coverage (per D-036 thorough-tier expectation).
- Cross-epic seam to Epic 6's `signActionEnvelope` export adds sequencing risk.
- D-024 mandates a leading spike (minimal `mint.wasm`) before scaling to all 5 verb wasm modules.
- 4–5 stories estimated — within the 2–6 size band; no SIZE WARNING.

### Test Tier (per D-036)

**thorough** — Cluster E default. All 7 gates: `zig build test`, `zig build smoke`, `bun run check`, `bun run test:unit -- --run`, `scripts/cli-smoke.sh`, `scripts/server-smoke.sh`, `tests/e2e-cryptography.sh`. Plus new test surface: per-import tests, verify-before-instantiate failure tests, import-violation tests, memory-limit OOM tests, cross-platform WASI parity tests in CI.

### Stories

#### Story 5.1: Wasm Runtime Spike — Choose Runtime; Minimal Host Loads `hello.wasm` on darwin + linux

**User Story**: As a Dreamball maintainer, I want a spike that selects a wasm runtime and demonstrates a minimal Zig wasm host loading `hello.wasm` under WASI on both darwin and linux without source divergence, so that Assumption #2 is validated and D-032's "single shared host" commitment is grounded.
**FRs**: FR10 · **Decisions**: D-020, D-024, D-032, TC4, TC7 · **Complexity**: large · **Test Tier**: thorough

#### Story 5.2: Implement 5 `dreamball.*` Imports + Per-Import Tests + Structured Event Emission

**User Story**: As an archiform author, I want the wasm host to expose exactly the 5 sprint-002-locked `dreamball.*` imports with per-import tests and structured invocation event emission, so guest wasm modules have a complete, observable, locked host-import surface.
**FRs**: FR11, FR10 · **Decisions**: D-020, D-022, D-023, D-032, D-033, NFR3, NFR11, SEC1, SEC2 · **Complexity**: large · **Test Tier**: thorough
**Cross-epic dependency note**: AC4 (`dreamball.emit_action_envelope`) consumes Epic 6 Story 6.1's `signActionEnvelope` export — Story 6.1 should land before Story 5.2 begins per Cross-Epic Seam in Epic 5 §Dependencies.

#### Story 5.3: Wasm Host Failure Paths — Verify-Before-Instantiate, Import-Violation, Memory-Limit

**User Story**: As a CI gate, I want the wasm host to enforce verify-before-instantiate (blake3), import-violation (only `dreamball.*`), and memory-limit (16/64 MiB) failure paths with structured failure events.
**FRs**: FR10, FR11 · **Decisions**: D-020, D-031, D-033, SEC1, SEC4, NFR7, NFR11 · **Complexity**: medium · **Test Tier**: thorough

#### Story 5.4: Author + Run Sample `mint.wasm` End-to-End Against Wasm Host

**User Story**: As a Dreamball maintainer, I want a sample `mint.wasm` guest that loads via `jelly`, executes through the wasm host, and produces a host-signed envelope, so the entire wasm action runtime is exercised end-to-end.
**FRs**: FR10 · **Decisions**: D-019, D-020, D-022, D-023, D-031, D-024 · **Complexity**: medium · **Test Tier**: thorough

#### Story 5.5: Author `docs/dreamball-imports.md` Enumerating the 5-Import Surface

**User Story**: As an archiform author, I want `docs/dreamball-imports.md` to enumerate all 5 sprint-002 `dreamball.*` imports with arity, types, error semantics, and host-trust notes, so future archiform authors have a single canonical reference.
**FRs**: FR11, FR15 (partial) · **Decisions**: D-025, D-033, SEC2 · **Complexity**: small · **Test Tier**: smoke

*(See `stories/5.{1..5}-*.md` for full BDD acceptance criteria.)*

## Epic 5 Health Metrics
- **Story count**: 5 (within 4–5 band)
- **Complexity**: 1 small, 2 medium, 2 large
- **FR coverage**: all FRs covered (FR10, FR11)
- **Dependency flags**: depends on Epic 1 (codegen for envelope CBOR); CROSS-EPIC SEAM with Epic 6 (Story 5.2 AC4 consumes Story 6.1's `signActionEnvelope` export — sequence Story 6.1 first)
- **Test tier distribution**: 0 yolo, 1 smoke, 4 thorough (Cluster E default per D-036)

---

## Epic 6: Ed25519 Sentinel Migration (Carry-Over)

### Goal

After this epic, **every signed-action emission produces a real Ed25519 signature**. The two derived-fp sentinel substitutions in `oracle.ts oracleSignAction` and `store.recordTraversal` (sprint-001 S4.4 / S5.5) consume a new `signActionEnvelope(keypair_bytes, payload_bytes) → ed25519_sig_bytes` export on `jelly.wasm`. No `_sentinelFp` / derived-fp / placeholder bytes remain in any signature-emitting path. The closing of this debt is reflected in `docs/known-gaps.md` (scope-substitution entry → closed; PQ dual-sig debt remains open under the security-pass section).

### Assigned Requirements

- **FR13** — Sprint-001 carry-over: Ed25519 sentinel migration (both call sites consume real Ed25519 signatures; negative test on forged signature; full-gate verification per `feedback_full_gate_verification`; `docs/known-gaps.md` updated)

### Architecture Constraints

- **D-023** — Dual-sig parameterisation through `jelly.wasm` `signActionEnvelope` export. Sprint-002 ships Ed25519-only single signatures; PQ dual-sig deferred to security pass per 2026-04-25 steering. *Defines the export this epic adds; commits to Ed25519-only.*
- **SEC3** — Replace dual-sig sentinels with real Ed25519 single signatures (the security counterpart to FR13).
- **SEC6** — Cryptographic deferrals (PQ dual-sig + key custody explicitly deferred per 2026-04-25 steering and project memory `project_dreamball_pq_deferred`). This epic MUST NOT re-open dual-sig parameterisation; substituting Ed25519-only with sentinels-removed is the sanctioned target.
- **D-022** — Bridge pattern: the migrated call sites continue to operate within the Bun-bridge mutation flow; Ed25519 signing happens within the bridge boundary.
- **D-025** — Forward-declare contracts: `signActionEnvelope` is a cross-epic contract (Epic 5 also consumes it for `dreamball.emit_action_envelope`); locked here as part of the FR13 deliverable.
- **TC2** — All CI gates green; per `feedback_full_gate_verification`, narrow tests are insufficient for verification of this fix.
- **TC5** — `jelly.wasm` size budget (≤ 200 KB raw / ≤ 64 KB gzipped) must hold after the export is added.

### Dependencies

- **Depends on:** None. This epic is fully independent and can run anytime in the sprint. Recommended placement is mid-sprint to absorb capacity slack and to land the `signActionEnvelope` export before Epic 5's wasm host needs it (cross-epic seam).
- **Cross-epic seam to Epic 5:** Provides the `signActionEnvelope` export that Epic 5's `dreamball.emit_action_envelope` consumes. **Sequencing note for Phase 3:** the export portion of Epic 6 should land before Epic 5's spike completes.
- **Enables:** Epic 5 (cross-epic seam: wasm host signature path), Epic 7 (documentation refresh cites the closed sentinel debt).

### Estimated Complexity

**LOW** — Justification:
- 1 FR, small surface: 2 call sites to migrate + 1 wasm export to add + negative-test coverage + `docs/known-gaps.md` update.
- Existing Ed25519 primitives are already in scope (per `requirements.md` Existing Codebase Inventory: signing primitives exist; the missing piece is the `signActionEnvelope` export).
- The full-gate verification mandate per `feedback_full_gate_verification` is a process discipline, not extra implementation work.
- Highest regression-prevention value per story of any epic in the sprint (it closes the silent-substitution regression class explicitly).
- 1–2 stories estimated.
- **Size note:** 1 story is at the lower band edge; per phase-2b validation rule "`[SIZE WARNING: too small — consider merging]` if <2". This epic is intentionally not merged with Epic 7 (Documentation Refresh) because: (a) FR13 is a functional+security requirement with its own crypto verification surface, while FR15 is documentation surface; (b) merging would dilute the test-tier discipline (FR13 mandates full-gate verification per `feedback_full_gate_verification`; FR15 is markdown lint + link checker); (c) the carry-over is a coherent atomic unit ("close the sprint-001 sentinel debt") that is more legible to executors as a standalone epic. **Phase 3 should aim for 2 stories** (one for the `signActionEnvelope` export + one for the call-site migration + negative test) to comfortably clear the size band.

### Test Tier (per D-036)

**smoke** with mandatory full-gate verification per `feedback_full_gate_verification`. The full gate set (`zig build test`, `zig build smoke`, `bun run check`, `bun run test:unit -- --run`, `scripts/cli-smoke.sh`, `scripts/server-smoke.sh`, `tests/e2e-cryptography.sh`) is REQUIRED before this epic is reported done — narrow tests pass false-positive on this class of fix per the project memory entry.

### Stories

#### Story 6.1: Add `signActionEnvelope` Export to `jelly.wasm`

**User Story**: As a future runtime (and as Epic 5's wasm action host), I want `jelly.wasm` to export `signActionEnvelope(keypair_bytes, payload_bytes) → ed25519_sig_bytes` producing real Ed25519 single signatures, with `jelly.wasm`'s size budget (TC5) holding after the export is added.
**FRs**: FR13 · **Decisions**: D-023, D-025, SEC3, SEC6, TC5 · **Complexity**: small · **Test Tier**: smoke (with mandatory full-gate verification per `feedback_full_gate_verification`)
**Cross-epic dependency note**: This story provides the `signActionEnvelope` export consumed by Epic 5 Story 5.2 AC4. Sequence Story 6.1 BEFORE Story 5.2.

#### Story 6.2: Migrate `oracle.ts oracleSignAction` + `store.recordTraversal` to Real Ed25519 Signatures + Negative Test + Update `docs/known-gaps.md`

**User Story**: As a Dreamball maintainer, I want both derived-fp sentinel call sites migrated to consume Story 6.1's `signActionEnvelope` export with a negative test confirming forged signatures fail verification, so that the silent-substitution regression class from sprint-001 S4.4 / S5.5 is closed.
**FRs**: FR13 · **Decisions**: D-022, D-023, D-025, SEC3, SEC6, TC2 · **Complexity**: small · **Test Tier**: smoke (with mandatory full-gate verification per `feedback_full_gate_verification`)

*(See `stories/6.{1,2}-*.md` for full BDD acceptance criteria.)*

## Epic 6 Health Metrics
- **Story count**: 2 (clears the lower band per Phase 2B guidance)
- **Complexity**: 2 small, 0 medium, 0 large
- **FR coverage**: all FRs covered (FR13)
- **Dependency flags**: independent within sprint; CROSS-EPIC SEAM provides `signActionEnvelope` to Epic 5 (sequence 6.1 before 5.2)
- **Test tier distribution**: 0 yolo, 2 smoke (with full-gate-verification escalation), 0 thorough

---

## Epic 7: Documentation Refresh

### Goal

After this epic, **`docs/ARCHITECTURE.md`, `docs/PROTOCOL.md`, and a new `docs/dreamball-imports.md` reflect the architectural pivot** the rest of the sprint delivers — the refined two-part cross-runtime invariant (encoding algorithm in Zig + golden vectors; field shapes in JSON Schema), the wasm action host architecture, the 5-import `dreamball.*` contract, the schema-vendoring + pin-format conventions, the trust model for archiform bundles, and the closed sentinel debt. Future agents reading the docs tree without the sprint-002 decision notes still arrive at a faithful mental model.

### Assigned Requirements

- **FR15** — Documentation refresh (`CLAUDE.md` cross-runtime invariant already landed pre-sprint; `docs/ARCHITECTURE.md` adds/updates ADR for wasm action host + `dreamball.*` import seam + codegen flow diagram; `docs/PROTOCOL.md` adds pointer to JSON Schema files; `docs/dreamball-imports.md` enumerates wasm import surface)

### Architecture Constraints

- **D-025** — Forward-declare consumer seam contracts: this epic produces the public-facing artifact (`docs/dreamball-imports.md`) for the contract that D-033 locked.
- **D-026** — Surface registry + fallback chain: PROTOCOL.md §13.7 wording should reflect this ADR (renderer projection inherits in sprint-003).
- **D-027** — Coord frames composition: PROTOCOL.md §13.2 should cite this ADR.
- **D-029** — aspects.sh contract / pin file format: PROTOCOL.md adds §"Schema vendoring and pin format" subsection per D-029 §Consequences.
- **D-031** — Wasm signing trust model: PROTOCOL.md adds §"Wasm module signing and trust model" subsection per D-031 §Consequences.
- **D-032** — Wasm host architecture: ARCHITECTURE.md cross-runtime invariant section refines to "host code identical across CLI/browser/jelly-server; platform shims differ".
- **D-033** — `dreamball.*` import surface locked to 5: `docs/dreamball-imports.md` enumerates all 5 with arity, types, error semantics, host-trust notes (per FR11 acceptance).
- **D-035** — Closed `attributes` / `effects.kind`: documentation enumerates the closed sets.
- **All other D-** — Citations from upstream epics flow through here; this epic is the canonical surface for "what changed in sprint-002 architecturally."
- **TC9** — Recrypt naming inheritance: doc refresh checks any new vocabulary against `../recrypt/docs/wire-protocol.md`.

### Dependencies

- **Depends on:** Epics 1, 2, 3, 4, 5, 6 (cross-cutting; documents the architectural surface those epics deliver). **Sequencing note:** this epic runs as the *final* epic in the sprint; sub-stories may begin earlier as their upstream surfaces stabilize, but the epic as a whole closes after Epic 6.
- **Enables:** Sprint-003 onboarding (renderer + REST projections); Cluster I stretch (federation proof relies on `docs/dreamball-imports.md` to know what host imports to use); future archiform authors outside the team.

### Estimated Complexity

**LOW** — Justification:
- 1 FR; pure documentation surface (no functional change).
- The substantive content is generated by the upstream epics; this epic is the *editing + integration* pass that lands the changes coherently.
- `docs/dreamball-imports.md` is a new file but its content is tightly bounded (5 imports, fully specified by D-033 + FR11 acceptance).
- ARCHITECTURE.md and PROTOCOL.md edits are surgical (specific subsections).
- Markdown lint + link checker + manual review is the test surface.
- 1–2 stories estimated.
- **Size note:** Like Epic 6, this is at the lower band edge. Phase 3 should aim for 2 stories (one for `docs/dreamball-imports.md` + the `dreamball.*` surface enumeration; one for ARCHITECTURE.md + PROTOCOL.md + cross-doc consistency pass) to comfortably clear the size band. Not merged with Epic 6 because (a) FR15 is cross-cutting documentation while FR13 is targeted security debt closure, (b) FR15 must run *after* the upstream epics stabilize while FR13 can run anytime, (c) the test tiers and gates differ materially.

### Test Tier (per D-036)

**smoke** — Cluster H default. Markdown lint + link checker + manual review. No functional test surface. CI gate set (`zig build test`, `zig build smoke`, `bun run check`, `bun run test:unit -- --run`, `scripts/cli-smoke.sh`, `scripts/server-smoke.sh`) must remain green (no functional change should be introduced; if a doc change breaks a gate, that is a signal of an undocumented assumption to investigate).

### Stories

#### Story 7.1: Update `docs/PROTOCOL.md` — Schema Vendoring + Pin Format + Wasm Trust Model + JSON Schema Pointers

**User Story**: As a future agent reading the docs tree, I want `docs/PROTOCOL.md` to point at JSON Schema files as the authoritative shape source, document the pin format per D-029, document the wasm trust model per D-031, and reflect D-026 / D-027 ADRs in the relevant sections.
**FRs**: FR15 · **Decisions**: D-018, D-026, D-027, D-029, D-031, D-035, TC9 · **Complexity**: medium · **Test Tier**: smoke

#### Story 7.2: Update `docs/ARCHITECTURE.md` Cross-Runtime Invariant + Wasm Action Host + Codegen Flow Diagram + Cross-Doc Consistency Pass

**User Story**: As a future agent onboarding to Dreamball post-sprint-002, I want `docs/ARCHITECTURE.md` to reflect the refined cross-runtime invariant with new sections for the wasm action host, the `dreamball.*` import seam, and the codegen flow, plus a cross-doc consistency pass.
**FRs**: FR15 · **Decisions**: D-018, D-020, D-025, D-029, D-031, D-032, D-033, TC9 · **Complexity**: medium · **Test Tier**: smoke

*(See `stories/7.{1,2}-*.md` for full BDD acceptance criteria.)*

## Epic 7 Health Metrics
- **Story count**: 2 (clears the lower band per Phase 2B guidance)
- **Complexity**: 0 small, 2 medium, 0 large
- **FR coverage**: all FRs covered (FR15)
- **Dependency flags**: depends on Epics 1–6 (cross-cutting; final pass)
- **Test tier distribution**: 0 yolo, 2 smoke, 0 thorough (Cluster H default per D-036)

---

## Epic 8 [STRETCH]: Sample Second Archiform (Federation Proof)

### Goal

After this epic, **a second tiny archiform (e.g., `dreamball/guestbook@0.1.0`) ships end-to-end through the new pipeline** — JSON Schema → action manifest → wasm action → CLI projection — proving the federation hypothesis ("anyone can author a new archiform") with code rather than only with infrastructure. This is the integration test of the entire sprint per `sprint-scope.md` Risk #3.

### Activation Criteria

This epic activates **only if Epics 1–7 complete cleanly with margin**. If a HIGH-complexity epic (Epic 1 or Epic 5) blows estimates, Epic 8 is dropped per `sprint-scope.md` Mitigation #5 (and the federation hypothesis carries to sprint-003 as the leading epic per Risk #3).

### Assigned Requirements

- (no FRs — this epic is purely additive; it exercises the manifold delivered by Epics 1–7)

### Architecture Constraints

- **D-017** — Archiform registry / 3-layer model: the second archiform is authored as if published through aspects.sh (locally-vendored per D-029).
- **D-018** — Per-archiform codegen consumes the new schema; produces Zig + TS + Valibot + Cypher.
- **D-019** — Action manifest: the second archiform declares its own actions.
- **D-020** — Wasm runtime: the second archiform's actions are wasm modules.
- **D-029** — Pin file: the second archiform gets its own `schemas/.pins/<name>-<version>.fp`.
- **D-031** — Trust model: the second archiform's wasm bug fixes require schema reissue (per Phase 2A "soft constraint" attention note in `architecture-decisions.md`).
- **D-033** — `dreamball.*` import surface: the second archiform's wasm uses only the 5 sprint-002 imports.

### Dependencies

- **Depends on:** Epic 1 (codegen flow), Epic 2 (per-archiform authoring template), Epic 3 (action manifest authoring), Epic 5 (wasm host runs the second archiform's actions). Does NOT strictly require Epic 4 (programmatic + MCP) or Epic 7 (documentation refresh), but landing them first makes the federation proof more legible.
- **Enables:** Confident close of the sprint-002 architectural pivot ("we built the right thing"); strong sprint-003 leading position for renderer projection or asset envelopes.

### Estimated Complexity

**MEDIUM** — Justification:
- 2–3 stories: (1) author `schemas/<second>-0.1.0.json` + pin, (2) author + ship one wasm action for the second archiform, (3) project to CLI + verify smoke.
- Most of the work is already done by Epics 1–7; Epic 8 is the *exercise* of that work.
- The second archiform is intentionally tiny (e.g., a guestbook with one `sign` action, or a journal with one `entry` action); scope creep is the primary risk here, not implementation depth.

### Test Tier (per D-036)

**thorough** — Stretch Cluster I default per D-036 ("if pulled in: thorough — it's the integration test of the entire sprint"). All 7 gates required.

### Stories

#### Story 8.1 [STRETCH]: Author `dreamball/guestbook@0.1.0` JSON Schema + Pin + Per-Archiform Codegen

**User Story**: As an archiform author, I want a tiny second archiform `dreamball/guestbook@0.1.0` authored end-to-end through the new pipeline (JSON Schema → pin → per-archiform codegen → Zig + TS + Valibot + Cypher), so that the federation hypothesis is exercised by code rather than only by infrastructure.
**FRs**: (none — integration test) · **Decisions**: D-017, D-018, D-029, D-031, TC3, TC8 · **Complexity**: medium · **Test Tier**: thorough

#### Story 8.2 [STRETCH]: Author + Run Guestbook Wasm Action End-to-End Through Host

**User Story**: As an archiform author, I want a tiny `sign.wasm` for the guestbook archiform that runs end-to-end through the same wasm host (no host changes), proving the host generalizes beyond Memory Palace.
**FRs**: (none — integration test) · **Decisions**: D-019, D-020, D-022, D-023, D-031, D-033 · **Complexity**: medium · **Test Tier**: thorough

#### Story 8.3 [STRETCH]: Project Guestbook Action to CLI Verb + Smoke Verification (Federation Proof Closed)

**User Story**: As an archiform author, I want the guestbook `sign` action mechanically projected to a `jelly guestbook sign ...` CLI verb (with NO generator changes), with a smoke test exercising the entire pipeline end-to-end, so that the federation hypothesis is proven closed.
**FRs**: (none — integration test) · **Decisions**: D-019, D-022, D-035, IC2 · **Complexity**: small · **Test Tier**: thorough

*(See `stories/8.{1..3}-*.md` for full BDD acceptance criteria. Activation: only if Epics 1–7 complete cleanly with margin per `epics.md` §Activation Criteria.)*

## Epic 8 [STRETCH] Health Metrics
- **Story count**: 3 (within 2–3 band)
- **Complexity**: 1 small, 2 medium, 0 large
- **FR coverage**: N/A — integration test of Cluster A/B/C/E manifold; no FRs assigned
- **Dependency flags**: depends on Epics 1, 2, 3, 5; soft dependency on Epics 4 + 7 for legibility
- **Test tier distribution**: 0 yolo, 0 smoke, 3 thorough (Cluster I default per D-036)

---

## Validation Self-Check (Phase 2B planner)

Per the phase-2b file's validation checklist:

**Coverage rules:**
- ✅ Every IN FR (FR1–FR11, FR13–FR15) is assigned to exactly one epic. No orphans, no duplicates. (Verified against the FR Coverage Map table above.)
- ✅ FR12 is explicitly marked DEFER with rationale (Q3 wasm-only sprint; sprint-003+ pickup).
- ✅ Every NFR (NFR1–NFR11) is noted as applicable to at least one epic. (Verified against the NFR table in Requirements Inventory.)

**Size rules:**
- ✅ Epic 1: 4–5 stories. Within band.
- ✅ Epic 2: 3 stories. Within band.
- ✅ Epic 3: 5 stories. Within band.
- ✅ Epic 4: 3 stories. Within band.
- ✅ Epic 5: 4–5 stories. Within band.
- ⚠️ Epic 6: 1–2 stories. **Documented justification** for not merging with Epic 7: FR13 is functional+security with its own full-gate verification mandate (`feedback_full_gate_verification`); FR15 is doc surface with markdown-lint test tier. Phase 3 directed to aim for 2 stories to clear the band comfortably.
- ⚠️ Epic 7: 1–2 stories. **Documented justification** for not merging with Epic 6: cross-cutting timing (Epic 7 is the final epic; Epic 6 can run anytime); test-tier mismatch. Phase 3 directed to aim for 2 stories.
- ✅ Epic 8 STRETCH: 2–3 stories. Within band.

**Dependency rules:**
- ✅ No circular dependencies. Forward-only edges (Epic 1 → 2 → 3 → 4; Epic 1 → 5; Epic 6 independent; Epic 7 depends on 1–6; Epic 8 stretch depends on 1, 2, 3, 5).
- ✅ Epic 1 has zero dependencies.
- ✅ Cross-epic seam (Epic 5 ↔ Epic 6 via `signActionEnvelope` export) is explicitly declared in both epics' Dependencies sections; Phase 3 sequencing note added.

**Architecture rules:**
- ✅ Epic boundaries respect all 20 decisions in `architecture-decisions.md`. Each decision is cited in at least one epic's Architecture Constraints section.
- ✅ No `[ARCH GAP]` markers needed — all architectural patterns required by the epics are present in D-017..D-036.
- ✅ Infrastructure/setup work (codegen toolchain, schema vendoring, pin format) is in Epic 1 (foundation); subsequent epics build on it.

**Quality rules:**
- ✅ Epic goals are user-value statements following "After this epic, ..." form; the "user" here is often a system actor or future archiform author (called out in user instruction).
- ✅ Complexity estimates are justified inline per epic with reference to FR count, architecture constraints, integration surface, and risk class.
- ✅ Earlier epics (1, 2) establish the codegen + schema-extraction foundation that later epics (3, 4, 5) build on; Epic 6 is independent; Epic 7 cross-cuts at the end.

---

## Stories (populated in Phase 3)

*Phase 3: Story Decomposition will fill this section per epic.*

---

## Epic Health Metrics (populated in Phase 3)

*Phase 3 will fill this section with story counts, complexity rollups, dependency flags, and test-tier distributions per epic.*

---

*End of epics.md for sprint-002.*
