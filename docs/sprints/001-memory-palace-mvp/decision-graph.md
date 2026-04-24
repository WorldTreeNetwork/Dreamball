---
sprint: sprint-001
product: memory-palace
phase: 5 — Validation Gate
created: 2026-04-21
author: verifier (OMC)
---

# Sprint-001 Decision Graph — D-007 through D-016

Maps each architecture decision to the stories that reference it, with
primary (owns the decision) and secondary (consumer / constraint) roles.

---

## D-007: Store wrapper API — domain verbs + escape hatch (CRITICAL)

**Canonical Epic**: Epic 2

| Story | Role | How referenced |
|-------|------|---------------|
| S2.2 | PRIMARY | Defines `StoreAPI` interface; implements all domain verb groups; `__rawQuery` escape hatch; server adapter |
| S2.3 | PRIMARY | Browser adapter implements identical `StoreAPI`; `syncfs` lifecycle |
| S2.4 | CONSUMER | action-mirror uses `insertTriple`, `setMythosHead`, `appendMythos`, `recordAction` verbs |
| S2.5 | CONSUMER | `reembed`, `updateAqueductStrength`, `getOrCreateAqueduct` implemented via store verbs |
| S3.3 | CONSUMER | CLI calls `store.ensureAqueductLazy`, inscribe uses store inscription verbs |
| S4.1 | CONSUMER | `insertTriple`, `setMythosHead`, `mythosChainTriples` used for oracle MYTHOS_HEAD edge |
| S4.2 | CONSUMER | every read verb accepts `requesterFp`; Guild-policy gate inside store layer |
| S4.3 | CONSUMER | `store.insertTriple`/`updateTriple`/`deleteTriple` only; no raw Cypher in oracle.ts |
| S4.4 | CONSUMER | `store.transaction`, `reembed`, `recordAction`, `updateInscription`, `markOrphaned` |
| S5.1 | CONSUMER | `store.aqueductsForRoom` — no `@ladybugdb/core`/`kuzu-wasm` in lens |
| S5.2 | CONSUMER | `store.getPalace`, `store.roomsFor` — single domain verb calls |
| S5.3 | CONSUMER | `store.roomContents(roomFp)` — single domain verb |
| S5.4 | CONSUMER | `store.inscriptionBody(inscriptionFp)` — single domain verb |
| S5.5 | CONSUMER | `store.recordTraversal` — single call site (D-007 CRITICAL boundary for traversal) |
| S6.3 | CONSUMER | `kNN` domain verb; `OfflineKnnError` typed error |

---

## D-008: File-watcher transactional boundary — inline synchronous (HIGH)

**Canonical Epic**: Epic 4

| Story | Role | How referenced |
|-------|------|---------------|
| S4.4 | PRIMARY | File-watcher IS this decision's implementation; 4-step sequence under mutex; per-palace mutex; full rollback; fault-injection matrix (AC4–AC7) |
| S4.3 | SECONDARY | "D-008 4-step transaction discipline reused" for inscription triple mirroring |

---

## D-009: Shader spike scope — aqueduct-flow E2E go/no-go (HIGH)

**Canonical Epic**: Epic 5

| Story | Role | How referenced |
|-------|------|---------------|
| S5.1 | PRIMARY | This story IS the D-009 spike; all 6 checkboxes (a)–(f) implement the decision shape; go/no-go gate for S5.2–S5.5 |
| S5.5 | SECONDARY | Fallback language for "if S5.1 gate partially failed" references D-009 outcome |

---

## D-010: WASM ML-DSA-87 verify — golden-fixture round-trip (CRITICAL)

**Canonical Epic**: Epic 1

| Story | Role | How referenced |
|-------|------|---------------|
| S1.1 | PRIMARY | This story IS the D-010 validation; AC1–AC6 implement the golden-fixture round-trip shape exactly as specified in D-010; HARD BLOCK on failure |
| S5.1 | CONSUMER | `D-010 consumer` — renderer depends on WASM verify being functional |
| S5.2 | CONSUMER | `D-010 consumer` — PalaceLens decodes through jelly.wasm (needs ML-DSA-87 verify) |
| S5.3 | CONSUMER | `D-010 consumer` listed in Decisions field |
| S5.4 | CONSUMER | `D-010 consumer` listed in Decisions field |
| S5.5 | CONSUMER | `D-010 consumer` — traversal round-trip uses WASM verify end-to-end |

---

## D-011: Oracle secret-key custody — plaintext `.key` 0600 perms (MEDIUM)

**Canonical Epic**: Epic 3 (writes) / Epic 4 (reads)

| Story | Role | How referenced |
|-------|------|---------------|
| S3.2 | PRIMARY (write) | Generates `.oracle.key` at mint; mode 0600; `TODO-CRYPTO` marker adjacent to write site (AC6, AC3) |
| S4.1 | PRIMARY (read) | Reads `.oracle.key` on demand; `TODO-CRYPTO` marker at every read site (AC3); `buildSystemPrompt` uses key reader |
| S4.2 | CONSUMER | Oracle fp derived from `.key` for `isOracleRequester` check |
| S4.4 | CONSUMER | `oracleSignAction` uses `.oracle.key` reader; `TODO-CRYPTO` marker required (AC9) |

---

## D-012: Embedding endpoint wire shape — single POST, no batch (MEDIUM)

**Canonical Epic**: Epic 6

| Story | Role | How referenced |
|-------|------|---------------|
| S6.1 | PRIMARY | Route implements D-012 exactly: single POST `/embed`, `{content, contentType}` → `{vector, model, dimension, truncation}`; negative AC (AC6) asserts no batch/streaming |
| S6.2 | CONSUMER | `embedding-client.ts` consumes D-012 wire shape; `--embed-via` flag routes to D-012-compliant endpoint |
| S6.3 | CONSUMER | `kNN` query-embed step calls D-012-compliant endpoint for query vectorisation |

---

## D-013: CLI dispatch nesting — `palace` as flat-table internal router (MEDIUM)

**Canonical Epic**: Epic 3

| Story | Role | How referenced |
|-------|------|---------------|
| S3.1 | PRIMARY | This story validates D-013 (R8 risk gate): `palace` as single entry in `dispatch.zig` routing to `palace.zig` SubCommand table; AC1–AC5 test dispatch behaviour exactly as D-013 specifies |
| S3.5 | CONSUMER | `D-013 (consumer)` listed in Decisions; `palace open` routes via the nested dispatch |

---

## D-014: Archiform registry cache — snapshot-on-mint, no revalidation (MEDIUM)

**Canonical Epic**: Epic 3

| Story | Role | How referenced |
|-------|------|---------------|
| S3.2 | PRIMARY | `@embedFile` registry determinism (AC5): fresh-mint registry bytes identical across two mints; `aspects.sh` resolve with air-gap asset fallback at mint, not at runtime; TC11 compliance |

---

## D-015: Cross-runtime vector parity — ordinal top-K, ≤10% variance (HIGH)

**Canonical Epic**: Epic 2 (spike) / Epic 6 (consumer)

| Story | Role | How referenced |
|-------|------|---------------|
| S2.1 | PRIMARY | This story IS the D-015 spike; AC2 establishes server ground truth; AC3 asserts browser parity (set-equal fps, |Δ| ≤ 0.1); AC4 WARN path; AC5 HARD BLOCK with replan |
| S2.3 | CONSUMER | `D-015 (consumer — kNN per S2.1 outcome)`: browser adapter K-NN routing depends on D-015 result; HTTP fallback path documented if degraded |
| S6.3 | CONSUMER | AC6 explicitly routes `store.kNN` based on D-015 parity-spike result from `docs/decisions/2026-04-21-vector-parity.md`; server vs browser-local vs HTTP-fallback |

---

## D-016: LadybugDB schema — node labels, rel types, ActionLog commit-log (CRITICAL)

**Canonical Epic**: Epic 2

| Story | Role | How referenced |
|-------|------|---------------|
| S2.4 | PRIMARY | This story IS D-016: creates `schema.cypher` with exact node labels (Palace, Room, Inscription, Agent, Mythos, Aqueduct, ActionLog), relationship types (CONTAINS, MYTHOS_HEAD, PREDECESSOR, LIVES_IN, AQUEDUCT_FROM, AQUEDUCT_TO, KNOWS), and ActionLog as commit-log table |
| S2.1 | CONSUMER | `D-016 (consumer — Inscription.embedding column)` |
| S2.2 | CONSUMER | Domain verbs satisfy D-016 node/rel shapes; AC4 validates ActionLog (not `Action` node) |
| S2.5 | CONSUMER | Aqueduct schema row (resistance, capacitance, strength, conductance, phase, revision) |
| S3.3 | CONSUMER | Schema writes from CLI inscribe path (Inscription node, CONTAINS, LIVES_IN) |
| S4.1 | CONSUMER | MYTHOS_HEAD edge written on oracle mint |
| S4.2 | CONSUMER | `custodian-of-record` on Palace node |
| S4.3 | CONSUMER | LIVES_IN edge for inscription triples; ActionLog row per action |
| S5.2 | CONSUMER | PalaceLens reads Palace + Room nodes via store verbs |
| S5.3 | CONSUMER | RoomLens reads Room + Inscription nodes via `store.roomContents` |
| S5.4 | CONSUMER | InscriptionLens reads Inscription.surface, Inscription.source_blake3 |
| S6.3 | CONSUMER | K-NN Cypher pattern matches D-016 exactly (AC2): `QUERY_VECTOR_INDEX` + `LIVES_IN` graph-join |

---

## Summary Matrix

| Decision | Primary Story | Secondary Stories | Total Stories |
|----------|:-------------:|:-----------------:|:-------------:|
| D-007 | S2.2, S2.3 | S2.4, S2.5, S3.3, S4.1–S4.4, S5.1–S5.5, S6.3 | 15 |
| D-008 | S4.4 | S4.3 | 2 |
| D-009 | S5.1 | S5.5 | 2 |
| D-010 | S1.1 | S5.1–S5.5 | 6 |
| D-011 | S3.2, S4.1 | S4.2, S4.4 | 4 |
| D-012 | S6.1 | S6.2, S6.3 | 3 |
| D-013 | S3.1 | S3.5 | 2 |
| D-014 | S3.2 | — | 1 |
| D-015 | S2.1 | S2.3, S6.3 | 3 |
| D-016 | S2.4 | S2.1, S2.2, S2.5, S3.3, S4.1–S4.3, S5.2–S5.4, S6.3 | 12 |

**D-007 and D-016 are the most cross-cutting decisions** — both CRITICAL and both spanning the majority of epics. They are the load-bearing abstractions (store API surface and graph schema) around which all other stories compose.

**D-014 has the narrowest footprint** — one story (S3.2) owns both primary and sole implementation. No risk of drift.

---

## Epic 5 deep-dive ADRs (2026-04-24)

Three standalone ADRs landed during `/refine --epic=5` to keep Epic 5's
Web-engine implementation composable with future rendering engines
(Unreal, Blender, MR/VR). None are load-bearing on sprint-001 execution;
they document the architecture that lets sprint-002+ add splats and
cross-engine support without replanning.

### ADR 2026-04-24-surface-registry

**Canonical Epic**: Epic 5

| Story | Role | How referenced |
|-------|------|---------------|
| S5.4 | PRIMARY | AC2 revised — walks `Inscription.fallback` chain, logs structured `surface-fallback` event; `scroll` canonical baseline |
| S5.2–S5.5 | SECONDARY | All lens dispatchers follow the "registry + fallback" pattern for future surfaces |

### ADR 2026-04-24-renderer-compositing

**Canonical Epic**: Epic 5 (architecture only — no sprint-001 code)

| Story | Role | How referenced |
|-------|------|---------------|
| — | ARCHITECTURAL | Sprint-001 ships Strategy A (same-pass, splat-free); pre-commits Strategy C (multi-canvas CSS) for splat follow-up |

### ADR 2026-04-24-coord-frames

**Canonical Epic**: Epic 5 (architecture; affirms §12.2 + §13.2)

| Story | Role | How referenced |
|-------|------|---------------|
| S5.2 | CONSUMER | `PalaceLens` resolves room world matrices at load from cartesian placements + field's polar shell |
| S5.3 | CONSUMER | `RoomLens` inherits room's world matrix, composes local cartesian placements |
| S5.4 | CONSUMER | Inscription placements are cartesian local-to-room |

See also: [`docs/prd-rendering-engines.md`](../../prd-rendering-engines.md)
for the integrating narrative.

### D-009 revision 2026-04-24

Amendments (documented in-place in `architecture-decisions.md`):
1. Library version pin added to S5.1 success report (AC g).
2. Per-shader micro-spike ACs added to S5.5 for `room-pulse`,
   `dust-cobweb`, `mythos-lantern`. Direct application of
   sprint-004-logavatar's "spike before promote" learning.
