---
sprint: sprint-001
product: memory-palace
phase: 2B — Epic Design
mode: default
steering: GUIDED
created: 2026-04-21
author: planner (OMC)
total_epics: 6
total_stories_estimated: 28
total_frs: 26
total_nfrs: 9
total_tcs: 21
total_secs: 11
total_arch_decisions: 10
arch_decision_range: D-007..D-016
sprint_size: ambitious
dependency_shape: linear-with-fan-out
---

# Sprint-001 — Epics

Six epics, 28 stories, 26 functional requirements, fully mapped against
the 10 sprint-001 architecture decisions (D-007 through D-016) and the
six prior steering decisions (D-001 through D-006).

Each epic title completes the sentence **"After this epic, the system
can / users can…"** — titles name user/system value, not implementation
layers.

Dependency shape: **strictly linear between foundation and leaf epics**
(Epic 1 → 2 → {3, 6} → {4, 5}), with no forward edges. Epic 1 has zero
dependencies and probes the sprint's highest-leverage early signal
(Risk R3 — WASM ML-DSA-87 verify) in its first story.

---

## Requirements Inventory

### Functional Requirements (26)

All 26 sprint-scoped FRs carried in full from `requirements.md § Functional
Requirements`. Every FR maps to exactly one **canonical home epic** in
the Coverage Map below; secondary touch points are noted in the
consuming epic's *Architecture Constraints* section, not in the Coverage
Map.

| FR | Subject | Canonical Home |
|----|---------|----------------|
| FR1 | Palace mint with required mythos | Epic 3 |
| FR2 | Append-only mythos chain | Epic 3 |
| FR3 | `jelly palace rename-mythos` command | Epic 3 |
| FR4 | Per-child mythos attachment | Epic 3 |
| FR5 | Oracle always-in-context on current mythos head | Epic 4 |
| FR6 | `jelly palace add-room` | Epic 3 |
| FR7 | `jelly palace inscribe` | Epic 3 |
| FR8 | `jelly palace open` | Epic 3 |
| FR9 | State-changes emit signed timeline actions | Epic 3 |
| FR10 | Containment cycle enforcement | Epic 3 |
| FR11 | Oracle mint as Agent DreamBall with own keypair | Epic 4 |
| FR12 | Oracle unconditional palace read access | Epic 4 |
| FR13 | Inscription triples in oracle knowledge-graph | Epic 4 |
| FR14 | Oracle file-watcher | Epic 4 |
| FR15 | `palace` lens | Epic 5 |
| FR16 | `room` lens | Epic 5 |
| FR17 | `inscription` lens | Epic 5 |
| FR18 | Aqueduct traversal events + lazy creation | Epic 5 |
| FR19 | LadybugDB integration via single wrapper | Epic 2 |
| FR20 | Vector extension via LadybugDB | Epic 6 |
| FR21 | Delete-then-insert re-embedding | Epic 2 |
| FR22 | `jelly palace` verb group | Epic 3 |
| FR23 | `jelly show --as-palace` | Epic 3 |
| FR24 | `jelly verify` palace invariants | Epic 3 |
| FR25 | `--archiform` flag | Epic 3 |
| FR26 | Aqueduct electrical properties (Hebbian + Ebbinghaus) | Epic 2 |
| FR27 | Seed archiform registry | Epic 3 |

### Non-Functional Requirements (9)

| NFR | Subject |
|-----|---------|
| NFR10 | Latency (≤500 rooms × ≤50 inscriptions opens first lit room in <2s) |
| NFR11 | Offline-first with one sanctioned exit (embedding ingestion) |
| NFR12 | Dual-signature authorship (Ed25519 + ML-DSA-87) |
| NFR13 | Privacy — no implicit exfiltration |
| NFR14 | Mythos fidelity — warm architectural render, ≤4 new shader materials |
| NFR15 | Crypto + CAS hygiene markers (`TODO-CRYPTO`, `TODO-CAS`, `TODO-EMBEDDING`) |
| NFR16 | Test coverage per envelope (≥5 Zig / ≥3 Vitest / golden-bytes lock) |
| NFR17 | Build-gate green on every commit |
| NFR18 | Round-trip parity (CLI-minted envelopes byte-identical through codegen decoder) |

NFRs cross-cut. Every NFR applies to ≥1 epic. Cross-cutting assignment
recorded per epic in its *Non-Functional Requirements* section.

### Technical Constraints (21)

TC1 (Zig 0.16.0), TC2 (Bun + TS), TC3 (Svelte 5 runes), TC4 (Threlte /
WebGL default, WebGPU opt-in), TC5 (`jelly.wasm` ≤200 KB raw / ≤64 KB
gzipped, ships ML-DSA-87 verify), TC6 (Zig ↔ TS through codegen + HTTP
only), TC7 (dCBOR canonical ordering, scoped floats), TC8 (LadybugDB
v0.15.3 server + kuzu-wasm@0.11.3 browser), TC9 (explicit `close()`),
TC10 (browser IDBFS + bidirectional syncfs), TC11 (archiform registry
via aspects.sh with air-gap fallback), TC12 (single swap boundary
`src/memory-palace/store.ts`), TC13 (CAS source-of-truth; LadybugDB
holds no CBOR bytes), TC14 (timeline + action at `format-version: 3`,
others `2`), TC15 (quorum-policy wire shape Option A), TC16
(conductance intermediate; verifiers MUST NOT reject on mismatch),
TC17 (Vril `strength` monotone on signed chain; freshness renderer-side),
TC18 (mythos canonical vs. poetic chain-split rules), TC19 (dream-field
omnipresent substrate; no new MVP envelope), TC20 (half-float `#7.25`
where precision permits, else `#7.26`), TC21 (separate hybrid keypair
for oracle).

### Security Requirements (11)

SEC1–SEC11 inherited from `requirements.md § Security Requirements`.
All 11 apply; distribution recorded per epic.

### Architecture Decisions (10)

D-007 through D-016 from `architecture-decisions.md`. User approval:
`accept-all-2026-04-21` (recorded in `phase-state.json`).

| ID | Subject | Significance | Canonical Epic |
|----|---------|--------------|----------------|
| D-007 | Store wrapper API surface — domain verbs + escape hatch | CRITICAL | Epic 2 |
| D-008 | File-watcher transactional boundary — inline synchronous | HIGH | Epic 4 |
| D-009 | Shader spike scope — aqueduct-flow end-to-end on live traversal | HIGH | Epic 5 |
| D-010 | WASM ML-DSA-87 verify validation path — golden-fixture round-trip | CRITICAL | Epic 1 |
| D-011 | Oracle secret-key custody — plaintext `.key` with `0600` perms (MVP compromise) | MEDIUM | Epic 3 (writes) / Epic 4 (reads) |
| D-012 | Embedding endpoint wire shape — single POST, no batch, no streaming | MEDIUM | Epic 6 |
| D-013 | CLI dispatch nesting — `palace` as flat-table entry routing internally | MEDIUM | Epic 3 |
| D-014 | Archiform registry cache — snapshot-on-mint, no runtime revalidation | MEDIUM | Epic 3 |
| D-015 | Cross-runtime vector parity — ordinal top-K, ≤10% variance tolerance | HIGH | Epic 2 (spike) / Epic 6 (consumer) |
| D-016 | LadybugDB schema — node labels, relationship types, "timeline as commit log" | CRITICAL | Epic 2 |

---

## FR Coverage Map

Every FR appears in exactly one row. Secondary touch points recorded in
each consuming epic's *Architecture Constraints* (not here).

| FR | Canonical Home Epic | Rationale |
|----|---------------------|-----------|
| FR1 | Epic 3 — Mint, grow, and name the palace from the CLI | User-facing capability (the `jelly mint --type=palace` verb). Wire shape for `jelly.dreamball.field` with `field-kind: "palace"` is implicit in Epic 1's envelope work; the canonical "who owns the behaviour" is the CLI. |
| FR2 | Epic 3 | Append-only enforcement lives at mint and `rename-mythos` call sites. |
| FR3 | Epic 3 | `jelly palace rename-mythos` command. |
| FR4 | Epic 3 | Per-child mythos attachment via `add-room` / `inscribe` flags. |
| FR5 | Epic 4 — Converse with the oracle who remembers | Oracle conversation layer prepends mythos head body; canonical home is oracle runtime. |
| FR6 | Epic 3 | `jelly palace add-room` command. |
| FR7 | Epic 3 | `jelly palace inscribe` command. |
| FR8 | Epic 3 | `jelly palace open` command. |
| FR9 | Epic 3 | CLI is the emission site for every mutating action; wire support lives in Epic 1 secondary. |
| FR10 | Epic 3 | Cycle rejection at mutation CLI entry points. |
| FR11 | Epic 4 | Oracle mint bundle + separate hybrid keypair seeding. |
| FR12 | Epic 4 | Oracle query layer bypasses Guild policy. |
| FR13 | Epic 4 | Oracle knowledge-graph mirroring of inscription triples. |
| FR14 | Epic 4 | File-watcher skill (D-001 promoted MVP; D-008 transactional boundary). |
| FR15 | Epic 5 — Walk the palace with eyes | `palace` lens is a Svelte/Threlte renderer component. |
| FR16 | Epic 5 | `room` lens. |
| FR17 | Epic 5 | `inscription` lens. |
| FR18 | Epic 5 | Traversal events originate in the renderer. Epic 3 handles the lazy-create CLI/server support (secondary). |
| FR19 | Epic 2 — Remember the palace across runtimes | LadybugDB wrapper is the store itself; TC12 single swap boundary. |
| FR20 | Epic 6 — Recall by resonance | Qwen3 embedding + K-NN query. |
| FR21 | Epic 2 | Delete-then-insert is a store-API primitive (`reembed` verb in D-007). |
| FR22 | Epic 3 | `jelly palace` verb group shape. |
| FR23 | Epic 3 | `jelly show --as-palace` formatting. |
| FR24 | Epic 3 | `jelly verify` palace invariants. |
| FR25 | Epic 3 | `--archiform` flag parsing + attribute attachment at CLI. |
| FR26 | Epic 2 | Aqueduct Hebbian + Ebbinghaus formulas live in `src/memory-palace/aqueduct.ts` (cross-epic coupling table; D-016 schema). Epic 3 invokes on save-time; Epic 5 reads freshness for uniform. |
| FR27 | Epic 3 | Seed archiform registry attached at mint (D-014). |

**Coverage check:** 26/26 FRs assigned; zero duplicates.

---

## Epic List (Summary)

| # | Epic Title | Stories (est.) | Complexity | Depends On | Blocks | Canonical FRs |
|---|------------|----------------|------------|------------|--------|---------------|
| 1 | Speak palace on the wire | 5 | LOW–MED | — | 2, 3, 5, 6 | (wire foundation for all; no canonical FRs — enables FR1, FR9, FR26 wire shapes) |
| 2 | Remember the palace across runtimes | 5 | HIGH | 1 | 3, 4, 6 | FR19, FR21, FR26 |
| 3 | Mint, grow, and name the palace from the CLI | 6 | MEDIUM | 1, 2 | 4, 5 | FR1, FR2, FR3, FR4, FR6, FR7, FR8, FR9, FR10, FR22, FR23, FR24, FR25, FR27 |
| 4 | Converse with the oracle who remembers | 4 | MEDIUM | 1, 2, 3 | — | FR5, FR11, FR12, FR13, FR14 |
| 5 | Walk the palace with eyes | 5 | HIGH | 1, 2, 3 | — | FR15, FR16, FR17, FR18 |
| 6 | Recall by resonance | 3 | MEDIUM | 1, 2 | — | FR20 |

**Sprint totals:** 28 stories, 26 FRs covered, no forward dependencies.

**Dependency graph:**

```
         ┌──► 6 (embedding service)
         │
    1 ──►2 ──► 3 ──► 4 (oracle)
                │
                └──► 5 (renderer)
```

Epic 1's first story probes Risk R3 (WASM ML-DSA-87 verify per D-010).
Epic 2 story 1 is the cross-runtime vector parity spike (D-015). Epic 5
story 1 is the aqueduct-flow shader spike (D-009). Three go/no-go
signals sequenced before deep commitment.

---

## Epic 1 — Speak palace on the wire

**Goal statement:** *After this epic, the system can encode, decode,
verify, and round-trip every palace wire envelope. The palace has a
spoken language; every downstream epic inherits it.*

### Scope

Nine new envelope types, one new Field attribute (`field-kind`), two
format-version families (`3` for timeline + action; `2` for the other
seven), thirteen golden-fixture bytes-locks, full `jelly.wasm`
round-trip, and the ML-DSA-87 WASM verify go/no-go from D-010.

### Out of Scope

- CLI verbs that emit these envelopes (Epic 3).
- Store wrapper or schema (Epic 2).
- Renderer lenses that consume them (Epic 5).
- Quorum-policy enforcement (TC15 lands wire shape only; enforcement is v1.1).

### Primary FRs (canonical home)

None. Epic 1 is pure wire infrastructure. It **enables** FR1, FR9, FR26,
and every other FR that carries a palace envelope, but no FR lists Epic 1
as its canonical home; the user-facing capability always lives in a
consumer epic.

### Secondary touch points (FRs homed elsewhere that this epic enables)

FR1, FR2, FR3, FR4, FR6, FR7, FR9, FR14, FR18, FR25, FR26, FR27 — all
rely on the nine new envelope types or the `field-kind` attribute.

### Non-Functional Requirements

- **NFR12** (primary) — dual Ed25519 + ML-DSA-87 signatures on every
  `jelly.action` and `jelly.trust-observation`; WASM ML-DSA-87 verify
  must be functional (D-010 go/no-go).
- **NFR16** (primary) — ≥5 new Zig tests per envelope type; 13
  golden-fixture bytes-locks per PROTOCOL.md §13.11.
- **NFR18** (primary) — CLI-minted bytes round-trip through codegen TS
  decoder bit-identically.
- **NFR17** — `zig build test` + `bun run test:unit` green on every commit.

### Technical Constraints applicable

TC1, TC5 (ML-DSA-87 verify in WASM budget), TC6 (codegen is the gate),
TC7 (dCBOR ordering; floats scoped to omnispherical-grid + aqueduct
numeric fields), TC14 (per-envelope `format-version`), TC15 (quorum-policy
wire shape lands), TC17 (strength monotone on chain), TC18 (mythos
canonical vs. poetic chain-split at verify), TC19 (dream-field omnipresent;
no new envelope), TC20 (half-float `#7.25` vs single-float `#7.26`).

### Security Requirements applicable

SEC1 (dual-signed actions + trust-observations), SEC2 ("all present
sigs verify, no minimum count"), SEC3 (canonical mythos chain public),
SEC8 (quorum stacked-`signed` Option A), SEC9 (trust observations
decentralised).

### Architecture Constraints

- **D-010 (CRITICAL)** — Story 1 acceptance criterion includes the
  golden-fixture ML-DSA-87 WASM verify test
  (`src/lib/wasm/verify.test.ts`). If red, HARD BLOCK per Risk R3 /
  Assumption A12; fall back to server-subprocess verify path and
  reopen `known-gaps.md §1`.
- **TC5 / CLAUDE.md 2026-04-21** — WASM binary budget ≤200 KB raw /
  ≤64 KB gzipped including ML-DSA-87 verify. Budget measured per commit.
- **D-016 (schema, secondary)** — every new envelope whose fields
  require queryability must map to a node label or property in the
  LadybugDB schema (Epic 2 owns the schema DDL; Epic 1 coordinates
  naming).
- **TC6 (codegen gate)** — `tools/schema-gen/main.zig` regenerates
  `src/lib/generated/types.ts` + `schemas.ts` after every envelope
  struct added to `protocol_v2.zig`. No hand-written TS schemas.
- **Cross-epic coupling** — FR9's action envelope shape lands here;
  Epic 3 is the canonical emission site. FR26's aqueduct numeric
  fields land here; Epic 2 owns the computation.

### Primary Modules

- `src/envelope_v2.zig` — 9 new `encode<Type>` functions (Guild /
  Memory / KnowledgeGraph pattern).
- `src/protocol_v2.zig` — 9 new struct types matching PROTOCOL.md §13.
- `src/golden.zig` — 13 `GOLDEN_*_BLAKE3` constants + tests (PROTOCOL.md
  §13.11).
- `tools/schema-gen/main.zig` — emit the new envelope types to TS.
- `src/lib/generated/*.ts` — regenerated; no hand-edits.
- `src/lib/wasm/` — exports + ML-DSA-87 verify validation test.
- `fixtures/ml_dsa_87_golden.json` — emitted by `zig build
  export-mldsa-fixture` (per D-010 test shape).

### Estimated Stories (5)

_Placeholder for Phase 3 story enrichment._ Anchor shapes from Phase 2
scoping:

- **S1.1** — ML-DSA-87 WASM verify validation (D-010 go/no-go, first
  sprint story).
- **S1.2** — Field-kind + `jelly.dreamball.field` palace extension
  (encoder, decoder, golden).
- **S1.3** — Timeline + action envelopes at `format-version: 3` with
  dual-sig integration.
- **S1.4** — Mythos + archiform + layout + element-tag + inscription +
  trust-observation envelopes at `format-version: 2`.
- **S1.5** — Aqueduct envelope + numeric fields (resistance, capacitance,
  strength, conductance, phase) wire shape; `#7.25`/`#7.26` discipline.

### Epic Health Metrics

*(Phase 3 fills: story count, AC count, build-gate coverage. Placeholder.)*

---

## Epic 2 — Remember the palace across runtimes

**Goal statement:** *After this epic, the system can persist palace
state in LadybugDB on the server and `kuzu-wasm` in the browser, replay
it bit-identically from CAS, and serve every future query through one
swap-boundary module. The palace remembers itself.*

### Scope

`src/memory-palace/store.ts` as TC12's single swap boundary, schema DDL
per D-016, domain-verb public API per D-007 (with underscored
escape-hatch `__rawQuery`), bidirectional `syncfs` lifecycle in the
browser (TC10), explicit `close()` discipline on every LadybugDB handle
(TC9), the cross-runtime vector-parity spike as story 1 (D-015), and
the canonical home for FR26's aqueduct formulas in
`src/memory-palace/aqueduct.ts`.

### Out of Scope

- CLI verbs that write through the store (Epic 3).
- Oracle read paths that query through the store (Epic 4).
- Embedding computation (Epic 6).
- Renderer queries (Epic 5).
- ADR quarterly-review / swap evaluation (post-sprint).

### Primary FRs (canonical home)

- **FR19** — LadybugDB integration via single wrapper.
- **FR21** — Delete-then-insert re-embedding.
- **FR26** — Compute aqueduct electrical properties per Hebbian +
  Ebbinghaus (formulas in `aqueduct.ts`; consumers compute + render
  from there).

### Secondary touch points (FRs homed elsewhere that this epic supports)

Every mutation FR in Epic 3 (FR1, FR2, FR3, FR4, FR6, FR7, FR9, FR10,
FR18, FR22, FR25, FR27), every oracle FR in Epic 4 (FR5, FR11, FR12,
FR13, FR14), every renderer FR in Epic 5 (FR15, FR16, FR17, FR18), and
FR20 in Epic 6 all route through `store.ts`.

### Non-Functional Requirements

- **NFR11** (primary) — local reads work offline (LadybugDB lives local).
- **NFR13** — no implicit exfiltration; store never hits network.
- **NFR18** — replay from CAS reproduces same graph shape.
- **NFR17** — build-gate green (server smoke hits native; browser smoke
  hits kuzu-wasm per FR19 acceptance).
- **NFR10** — K-NN query budget (<200 ms for 500 inscriptions top-10) is
  partly store-shape responsibility; partly Epic 6's.

### Technical Constraints applicable

TC8 (LadybugDB v0.15.3 + kuzu-wasm@0.11.3), TC9 (explicit `close()`),
TC10 (`mountIdbfs` + bidirectional `syncfs`), TC12 (single swap boundary
`src/memory-palace/store.ts`), TC13 (CAS source-of-truth; LadybugDB
holds no CBOR bytes), TC16 (conductance intermediate; verifiers MUST NOT
reject), TC17 (Vril strength monotone).

### Security Requirements applicable

SEC6 (no network emission from read paths), SEC7 (`TODO-*` markers
preserved at re-embed + K-NN sites), SEC11 (every state change emits a
signed action *before* effect visible — the store is the atomic site
for the "effect"; Epic 3 signs + Epic 2 persists in one transaction).

### Architecture Constraints

- **D-007 (CRITICAL)** — public API is domain-verb (Containment,
  Mythos, Timeline, Aqueducts, Oracle KG, Vector, Re-embedding,
  Lifecycle) with **only** `__rawQuery<T>` as escape-hatch. Every
  caller in every other epic uses named verbs. `grep` for
  `@ladybugdb/core` or `kuzu-wasm` outside `store.ts` returns empty
  (FR19 acceptance).
- **D-015 (HIGH)** — Story 1 is the vector-parity spike: 100
  deterministic 256d vectors, K-NN top-10 set equality across server +
  browser runtimes, per-item cosine distance within |Δ| ≤ 0.1. Set
  inequality = HARD BLOCK → replan to server-only vector path. Bounded
  variance = WARN + ADR addendum + ship.
- **D-016 (CRITICAL)** — Schema DDL (`src/memory-palace/schema.cypher`)
  executed on `open()`: node labels {`Palace`, `Room`, `Inscription`,
  `Agent`, `Mythos`, `Aqueduct`}, relationship types {`CONTAINS`,
  `MYTHOS_HEAD`, `PREDECESSOR`, `LIVES_IN`, `AQUEDUCT_FROM`,
  `AQUEDUCT_TO`, `KNOWS`}, commit-log table `ActionLog` (actions are
  **not** graph nodes), archiform as property, mythos body carried as
  Blake3 hash (bytes live in CAS per TC13).
- **D-015 consumer contract** (secondary) — Epic 6 invokes `kNN` verb;
  verb implementation selects server-only path if the parity spike
  degraded.
- **Cross-epic coupling — FR26 formulas** — `src/memory-palace/aqueduct.ts`
  is the sole home. Epic 3 invokes `updateAqueductStrength` at save-time;
  Epic 5 reads `conductance` + freshness uniform for shader input. A
  bit-identical unit test across both call sites enforces the contract
  (Risk R7 mitigation).
- **TC9 wrapper type** — every `QueryResult` close is enforced at the
  wrapper's type level (`try/finally` around `qr.close()` per ADR
  2026-04-21-ladybugdb-selection.md § Step 1).

### Primary Modules

- `src/memory-palace/store.ts` (new) — the single swap boundary;
  domain-verb public API per D-007; bidirectional `syncfs` lifecycle.
- `src/memory-palace/aqueduct.ts` (new) — FR26 formulas in ONE code
  block at top of file; `strength`, `conductance`, `phase` pure
  functions.
- `src/memory-palace/schema.cypher` (new) — DDL executed on `open()`.
- `src/lib/backend/` (extend) — `HttpBackend` + `MockBackend` remain;
  `store.ts` is a parallel abstraction per the JellyBackend pattern
  (D-007).

### Estimated Stories (5)

_Placeholder for Phase 3 story enrichment._ Anchor shapes from Phase 2
scoping:

- **S2.1** — Cross-runtime vector-parity spike (D-015 go/no-go, first
  Epic 2 story).
- **S2.2** — `store.ts` public API + server adapter (`@ladybugdb/core`,
  explicit close lifecycle).
- **S2.3** — Browser adapter (`kuzu-wasm@0.11.3` + `mountIdbfs` + bidirectional `syncfs`).
- **S2.4** — Schema DDL (D-016) + migration-free init + replay-from-CAS
  acceptance test (FR19 acceptance).
- **S2.5** — `aqueduct.ts` formulas + `updateAqueductStrength` verb +
  `reembed` verb (FR21 delete-then-insert) + unit tests.

### Epic Health Metrics

*(Phase 3 fills. Placeholder.)*

---

## Epic 3 — Mint, grow, and name the palace from the CLI

**Goal statement:** *After this epic, users can mint a palace with a
required mythos, add rooms, inscribe documents, rename the mythos, tag
any node with an archiform, and see the palace round-trip through
`jelly show` + `jelly verify`. Every mutation emits a dual-signed
timeline action. The palace is operable from the command line.*

### Scope

The full `jelly palace` verb group (`mint`, `add-room`, `inscribe`,
`open`, `rename-mythos`), `jelly show --as-palace`, `jelly verify`
palace invariants, the `--archiform` flag on three verbs, seed
archiform registry bundling, lazy aqueduct creation on first traversal
(CLI half; renderer event half is Epic 5), append-only mythos-chain
enforcement, containment cycle rejection, and signed timeline action
emission on every mutation.

### Out of Scope

- Oracle behaviour (Epic 4).
- Renderer (Epic 5).
- Embedding ingestion (Epic 6, called via `--embed-via`).
- Growth / Vision verbs (`layout`, `share`, `rewind`, `observe`,
  `trace`, `gc`, `reflect`, `refresh-archiforms`).

### Primary FRs (canonical home)

- **FR1** — Palace mint with required mythos.
- **FR2** — Append-only mythos chain enforcement.
- **FR3** — `jelly palace rename-mythos` command.
- **FR4** — Per-child mythos attachment (`add-room --mythos`,
  `inscribe --mythos`).
- **FR6** — `jelly palace add-room`.
- **FR7** — `jelly palace inscribe`.
- **FR8** — `jelly palace open`.
- **FR9** — State-changes emit signed timeline actions (CLI emission
  site; wire shape lives in Epic 1).
- **FR10** — Containment cycle enforcement.
- **FR22** — `jelly palace` verb group shape.
- **FR23** — `jelly show --as-palace`.
- **FR24** — `jelly verify` palace invariants.
- **FR25** — `--archiform` flag on add-room / inscribe / `jelly mint
  --type=agent`.
- **FR27** — Seed archiform registry attached at mint.

### Secondary touch points (FRs homed elsewhere that this epic supports)

- **FR18** — Renderer fires traversal events (Epic 5), but the lazy
  aqueduct creation + `aqueduct-created` signed action happen via a
  CLI-bridged path routed through Epic 2's store verbs.
- **FR11** — Mint time seeds the oracle's own hybrid keypair (the
  sibling `.key` file; D-011 writes here). Oracle behaviour itself is
  Epic 4.
- **FR20 / FR21** — Inscribe invokes the embedding service via
  `--embed-via <url>`; delete-then-insert re-embedding delegates to
  Epic 2's `reembed` verb. Canonical home for FR20 is Epic 6.

### Non-Functional Requirements

- **NFR12** — every emitted action dual-signed. Oracle-originated vs.
  custodian-originated each signed with the respective keypair.
- **NFR11** — CLI works fully offline for everything except embedding
  ingestion (FR20 path via Epic 6).
- **NFR13** — no implicit exfiltration; `--embed-via` is the opt-in
  exit point.
- **NFR15** — `TODO-CRYPTO`, `TODO-CAS`, `TODO-EMBEDDING` markers at
  every applicable call site.
- **NFR17** — `scripts/cli-smoke.sh` extended with palace verbs;
  green on every commit.

### Technical Constraints applicable

TC1 (Zig 0.16.0), TC11 (archiform registry via aspects.sh with air-gap
fallback — D-014 makes "air-gap" the always-path), TC12 (CLI writes
through `store.ts`, no direct LadybugDB), TC13 (CAS source-of-truth —
CLI writes CBOR to CAS first, triggers store mirror second), TC14
(timeline + action at `format-version: 3`), TC15 (`jelly.quorum-policy`
wire shape Option A; MVP default `any-admin`), TC21 (separate hybrid
keypair for oracle — mint writes it; Epic 4 reads it).

### Security Requirements applicable

SEC1 (dual-signed mutations), SEC6 (no unsanctioned network exits —
only `--embed-via` explicit), SEC7 (`TODO-*` markers preserved), SEC10
(oracle `.key` custody compromise documented at mint site via D-011),
SEC11 (every state change emits signed action before effect visible).

### Architecture Constraints

- **D-013 (MEDIUM)** — `palace` is a single flat entry in
  `src/cli/dispatch.zig`; internal routing via a new
  `src/cli/palace.zig` with a `subcommands` table. Matches Risk R8
  validation (nested subgroup is a first; architect validated pattern
  in Phase 2A).
- **D-014 (MEDIUM)** — Seed archiform registry is a compiled-in
  `@embedFile` asset at `src/memory-palace/seed/archiform-registry.json`;
  attached at mint time; NO runtime revalidation against
  `aspects.sh`. Bytes deterministic across fresh mints (FR27
  acceptance). TC11 "air-gap fallback" is the always-path.
- **D-011 (MEDIUM — write side)** — Mint writes oracle `.key` to
  `{palace-path}.oracle.key` using `src/key_file.zig` format with
  explicit `chmod 0600`. Marker `TODO-CRYPTO: oracle key is plaintext;
  wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)` at
  write site.
- **D-007 (consumer)** — CLI Zig modules call TS bridge that invokes
  `store.ts` domain verbs. No `@ladybugdb/core` / `kuzu-wasm` imports
  in `src/cli/`. No raw Cypher in CLI code.
- **D-010 (consumer)** — CLI-signed actions must ML-DSA-87-verify in
  WASM (renderer + `jelly-server` share the same binary). Epic 1's
  go/no-go gates Epic 3's dual-sig stories.
- **D-016 (consumer)** — CLI writes map to the schema:
  `add-room` → `ensurePalace` + `addRoom` verbs → `Palace`-
  `CONTAINS`-`Room` subgraph; `inscribe` → `inscribeAvatar` verb →
  `Room`-`CONTAINS`-`Inscription` + (later) `LIVES_IN` triple when
  Epic 4's mirroring fires.
- **Cross-epic coupling — FR18 lazy creation** — When the renderer
  (Epic 5) emits a traversal event, it calls back through a CLI-
  equivalent signed-action path; the `aqueduct-created` signed
  action shape + emission live here. Lazy-creation lock on novel
  `(from, to)` pairs is a single call-site in the palace-mutation
  transaction.

### Primary Modules

- `src/cli/palace.zig` (new) — subcommand router (D-013).
- `src/cli/palace_mint.zig` (new) — FR1, FR11 key-seeding, FR27 registry
  attach.
- `src/cli/palace_add_room.zig` (new) — FR6, FR4, FR25.
- `src/cli/palace_inscribe.zig` (new) — FR7, FR4, FR25, optional
  `--embed-via` flag (FR20 entry point).
- `src/cli/palace_open.zig` (new) — FR8.
- `src/cli/palace_rename_mythos.zig` (new) — FR3, FR2.
- `src/cli/palace_show.zig` (new) — FR23.
- `src/cli/palace_verify.zig` (new) — FR24.
- `src/cli/dispatch.zig` (extend) — single `palace` entry (D-013).
- `src/memory-palace/seed/archiform-registry.json` (new) — D-014 bundle.
- `scripts/cli-smoke.sh` (extend) — full `jelly palace` verb
  coverage.

### Estimated Stories (6)

_Placeholder for Phase 3 story enrichment._ Anchor shapes from Phase 2
scoping:

- **S3.1** — `jelly palace mint` (FR1, FR2 genesis, FR11 oracle keypair
  seed, FR27 registry attach, D-011 `.key` write, D-014 bundled JSON).
- **S3.2** — `jelly palace add-room` + `inscribe` + `--archiform` flag
  (FR6, FR7, FR4, FR25, FR10 cycle check).
- **S3.3** — `jelly palace rename-mythos` + append-only chain (FR3, FR2).
- **S3.4** — Timeline action emission + dual-sig wiring (FR9 at every
  mutation call site; parent/head hash resolution; lazy aqueduct
  creation per FR18 secondary contract).
- **S3.5** — `jelly show --as-palace` + `jelly verify` invariants (FR23,
  FR24).
- **S3.6** — `jelly palace open` deep-link + `cli-smoke.sh` extension
  (FR8, NFR17).

### Epic Health Metrics

*(Phase 3 fills. Placeholder.)*

---

## Epic 4 — Converse with the oracle who remembers

**Goal statement:** *After this epic, users can converse with the
palace's oracle — an Agent DreamBall with its own hybrid keypair — whose
every turn sits under the current mythos head and whose knowledge-graph
mirrors every inscription. When a file on disk changes, the oracle
notices, bumps the avatar, re-signs, and re-embeds, all inside one
signed-action transaction.*

### Scope

Oracle mint bundle (personality-master-prompt seed, empty memory, empty
knowledge-graph, emotional-register with three axes), separate hybrid
keypair read path, unconditional palace read access (Guild-policy
bypass), synchronous inscription-triple mirroring into LadybugDB,
mythos-head always-in-context prepend, and the file-watcher skill per
D-008 (inline synchronous transactional boundary).

### Out of Scope

- Oracle LLM inference back-end wiring (handled by the consumer
  conversation layer; this epic exposes the always-in-context prepend
  + knowledge-graph query shapes).
- Oracle-initiated palace mutations beyond file-watcher (deferred).
- Recrypt-wallet key custody migration (follow-up gap; SEC10).
- Orphan-quarantine UI dimming (Epic 5 renders; Epic 4 emits the
  `inscription-orphaned` action).

### Primary FRs (canonical home)

- **FR5** — Oracle always-in-context on current mythos head.
- **FR11** — Oracle mint as Agent DreamBall with own keypair (oracle
  runtime side; CLI write side in Epic 3).
- **FR12** — Oracle unconditional palace read access.
- **FR13** — Inscription triples in oracle knowledge-graph, synchronous
  mirroring per Assumption A7.
- **FR14** — Oracle file-watcher (D-001 MVP; D-008 transactional
  boundary).

### Secondary touch points (FRs homed elsewhere that this epic supports)

- **FR9** — File-watcher emits signed timeline actions
  (`inscription-updated`, `inscription-orphaned`); shares the signed-
  action primitive built in Epic 3.
- **FR21** — File-watcher calls `reembed` verb from Epic 2 (delete-
  then-insert in one transaction).
- **FR20** — File-watcher calls the embedding service from Epic 6
  inside the mutex window.

### Non-Functional Requirements

- **NFR11** — Oracle reads stay local; only file-watcher embedding call
  touches network (sanctioned exit).
- **NFR12** — Oracle signs its own actions with its own ML-DSA-87
  keypair (SEC11 provenance).
- **NFR13** — No implicit exfiltration; knowledge-graph queries run
  locally.
- **NFR15** — `TODO-CRYPTO: oracle key is plaintext` marker at every
  oracle-key-read site.

### Technical Constraints applicable

TC13 (CAS source-of-truth), TC21 (separate hybrid keypair for oracle,
sibling `.key` file), TC12 (all reads go through `store.ts`).

### Security Requirements applicable

SEC1 (dual-signed actions), SEC4 (Agent interiority slots Guild-
restricted for others, but oracle reads all palace slots per SEC5),
SEC5 (oracle reads all palace slots regardless of Guild policy),
SEC10 (`.key` custody is MVP compromise; recrypt-wallet migration
follow-up), SEC11 (file-watcher emits signed action before effect
visible).

### Architecture Constraints

- **D-008 (HIGH)** — File-watcher is **inline synchronous** with one
  mutex per palace. Four-step sequence under the mutex: read new bytes
  + Blake3 → early-exit if unchanged (FR21 spy-zero-call assertion) →
  compute new embedding (network exit) → build signed action → atomic
  transaction (`reembed` + `recordAction` + `updateInscription`). Roll
  back on any failure. No queued-async variant.
- **D-011 (MEDIUM — read side)** — Oracle reads `.key` on demand; no
  caching in long-lived memory beyond the immediate syscall scope.
  Every read carries `TODO-CRYPTO: oracle key is plaintext…` marker.
- **D-007 (consumer)** — Oracle uses only domain verbs: `insertTriple`,
  `triplesFor`, `mythosChainTriples`, `setMythosHead`, `headHashes`,
  `reembed`. No `__rawQuery` except for explicitly-diagnostic code
  paths marked as such.
- **D-016 (consumer)** — Knowledge-graph mirroring writes into
  `Inscription` node properties + `LIVES_IN` edges + `Mythos` /
  `MYTHOS_HEAD` nodes/edges. Actions emitted go to `ActionLog` commit-
  log table (not graph nodes); `DISCOVERED_IN` is a property, not an
  edge.
- **D-010 (consumer)** — Oracle-signed actions verify via WASM
  ML-DSA-87 verify; Epic 1 story 1 gates this.
- **Cross-epic coupling — FR14 spans D+B+F** — Per sprint-scope.md
  coupling table: file-watcher is a **thin skill composing B + C + F
  primitives; no new primitives introduced**. Epic 4 owns the skill
  file (`src/memory-palace/file-watcher.ts`); uses `reembed`/
  `recordAction`/`updateInscription` from Epic 2, `signAction` from the
  Epic 3 primitive, and `/embed` HTTP client from Epic 6.
- **Cross-epic coupling — FR14 R6 mitigation** — Fault-injection test
  required: kill embedding endpoint mid-mutex, assert rollback leaves
  both graph and CAS in pre-mutation state.

### Primary Modules

- `src/memory-palace/oracle.ts` (new) — read paths, mythos-head
  prepend, knowledge-graph mirroring.
- `src/memory-palace/file-watcher.ts` (new) — D-008 inline synchronous
  skill.
- `src/memory-palace/seed/oracle-prompt.md` (new) — the
  `personality-master-prompt` seed asset.
- `src/memory-palace/store.ts` (consumer) — `insertTriple`,
  `triplesFor`, `mythosChainTriples`, `reembed` verb calls.

### Estimated Stories (4)

_Placeholder for Phase 3 story enrichment._ Anchor shapes from Phase 2
scoping:

- **S4.1** — Oracle mint bundle + `.key` read-path + mythos-head
  always-in-context prepend (FR5, FR11, D-011).
- **S4.2** — Guild-policy bypass for oracle reads (FR12).
- **S4.3** — Inscription triple mirroring, synchronous in signed-action
  transaction (FR13, Assumption A7 fault-injection test).
- **S4.4** — File-watcher skill (FR14, D-008 transactional boundary,
  orphan quarantine action emission, re-embedding hook).

### Epic Health Metrics

*(Phase 3 fills. Placeholder.)*

---

## Epic 5 — Walk the palace with eyes

**Goal statement:** *After this epic, users can walk their palace —
three new lenses (`palace`, `room`, `inscription`) render omnispherical
topology, room interiors per layout, and inscription text in 3D.
Aqueducts carry Vril as flowing light; room pulse, mythos lantern stub,
and dust-cobweb overlay complete the warm architectural render. Every
traversal emits a signed action and, on first visit between a novel
pair, lazily materialises an aqueduct.*

### Scope

Three new Svelte lenses plugging into `src/lib/lenses/`, four new
Threlte shader materials (`aqueduct-flow`, `room-pulse`,
`mythos-lantern` stub, `dust-cobweb`), renderer-side freshness uniform
driving Vril visual dim per TC17, the aqueduct-flow shader spike as
story 1 (D-009), and traversal-event emission (FR18).

### Out of Scope

- New rendering infrastructure beyond the four materials.
- Mobile-native renderer.
- Shared-palace / federation visuals.
- Peripheral-ghost visualisation (PRD FR78; deferred).
- Vril bottleneck diagnostics (PRD FR98; deferred).
- Element-tag palette/audio bindings.

### Primary FRs (canonical home)

- **FR15** — `palace` lens.
- **FR16** — `room` lens.
- **FR17** — `inscription` lens.
- **FR18** — Aqueduct traversal events + lazy creation (renderer event
  side canonical; Epic 3 handles the CLI-bridged lazy-create + signed
  action shape).

### Secondary touch points (FRs homed elsewhere that this epic supports)

- **FR26** — Renderer reads `conductance` uniform sourced from the
  aqueduct envelope (formula home in Epic 2).

### Non-Functional Requirements

- **NFR10** (primary — renderer latency budget) — opening a palace of
  ≤500 rooms × ≤50 inscriptions renders first lit room in <2s on a
  mid-range laptop.
- **NFR14** (primary — mythos fidelity) — four new materials:
  `aqueduct-flow` (particles along path; speed ∝ conductance; freshness
  uniform dims toward floor), `room-pulse` (pulse period ∝ capacitance;
  freshness tints colour), `mythos-lantern` (stub), `dust-cobweb`
  (visual decay at freshness floor per Vril ADR 2026-04-21).
- **NFR16** — ≥3 Vitest integration tests per lens.
- **NFR17** — Storybook play tests extend build-gate (`bun run
  test-storybook`).

### Technical Constraints applicable

TC3 (Svelte 5 runes only), TC4 (Threlte WebGL default; WebGPU opt-in;
WebGL fallback mandatory), TC6 (TS consumes codegen'd types only; no
hand-written envelope decoding), TC12 (renderer queries `store.ts` via
backend), TC17 (Vril `strength` monotone on chain; freshness uniform
renderer-side only — pure function of `now - last_traversed`).

### Security Requirements applicable

SEC6 (no implicit exfiltration from render paths), SEC11 (traversal
events emit signed actions before renderer reflects movement — the
action is the source-of-truth for "user moved").

### Architecture Constraints

- **D-009 (HIGH)** — Story 1 is the `aqueduct-flow` shader spike:
  Storybook scene with palace + room + two inscriptions + one
  aqueduct renders particles `from → to`, conductance uniform
  drives particle velocity (0.2 → 0.8 visibly speeds), freshness
  uniform dims with `last_traversed` (60-days mock vs. now mock),
  first particle render <200 ms, WebGPU/WebGL fallback verified.
  All six criteria pass → commit to the remaining three materials in
  stories 2–4. aqueduct-flow passes but 2+ link fails → convene
  `/replan` for simpler fallback materials. aqueduct-flow blank/uncompiled
  → HARD BLOCK; replan rendering epic; consider shipping MVP with
  instanced-line aqueducts (Three.js `Line2`) as non-shader fallback.
- **D-007 (consumer)** — Lens components use `aqueductsForRoom`,
  `kNearestInscriptions`, and other store verbs; never raw Cypher.
- **D-010 (consumer)** — Lenses render only envelopes verified in WASM
  (the `jelly.wasm` binary carries ML-DSA-87 verify per Epic 1 story 1).
- **D-016 (consumer)** — Renderer reads from
  `Palace`→`CONTAINS`→`Room`→`CONTAINS`→`Inscription` subgraph,
  `Aqueduct`→`AQUEDUCT_FROM/TO` edges, and `Room.layout_fp` for
  `room` lens.
- **Cross-epic coupling — FR26 conductance uniform** — Formula lives
  in Epic 2's `aqueduct.ts`; renderer imports the same module (not a
  copy) so freshness computation is bit-identical in the unit test
  (Risk R7 mitigation).
- **Cross-epic coupling — FR18 traversal emission** — Renderer emits a
  `move` event via the Epic 3 signed-action primitive; on novel
  `(from_fp, to_fp)` the same call path triggers lazy `jelly.aqueduct`
  creation + paired `aqueduct-created` action. Renderer never directly
  writes to LadybugDB; it routes through the store verb.

### Primary Modules

- `src/lib/lenses/palace/PalaceLens.svelte` (new).
- `src/lib/lenses/room/RoomLens.svelte` (new).
- `src/lib/lenses/inscription/InscriptionLens.svelte` (new).
- `src/lib/components/DreamBallViewer.svelte` (extend) — lens dispatch
  map extended with three new entries.
- `src/lib/shaders/aqueduct-flow.{frag,vert}.glsl` (new).
- `src/lib/shaders/room-pulse.{frag,vert}.glsl` (new).
- `src/lib/shaders/mythos-lantern.{frag,vert}.glsl` (new — stub).
- `src/lib/shaders/dust-cobweb.{frag,vert}.glsl` (new — visual decay
  overlay per Vril ADR).
- `src/memory-palace/aqueduct.ts` (consumer — import for freshness
  uniform).

### Estimated Stories (5)

_Placeholder for Phase 3 story enrichment._ Anchor shapes from Phase 2
scoping:

- **S5.1** — `aqueduct-flow` shader spike (D-009 go/no-go; first Epic 5
  story).
- **S5.2** — `PalaceLens` omnispherical topology with ≥3 rooms
  (FR15).
- **S5.3** — `RoomLens` interior with placement / quaternion / grid
  fallback (FR16).
- **S5.4** — `InscriptionLens` five surfaces (`scroll`, `tablet`,
  `book-spread`, `etched-wall`, `floating-glyph`) with fallback warning
  (FR17).
- **S5.5** — `room-pulse` + `mythos-lantern` stub + `dust-cobweb`
  materials + traversal-event emission + lazy aqueduct creation hookup
  (NFR14 pack, FR18).

### Epic Health Metrics

*(Phase 3 fills. Placeholder.)*

---

## Epic 6 — Recall by resonance

**Goal statement:** *After this epic, the system can embed every
inscription at ingestion time and recall it by semantic similarity.
Qwen3-Embedding-0.6B runs in `jelly-server`, returning 256d MRL-truncated
vectors over a single POST. K-NN queries through LadybugDB's vector
extension complete within the 200 ms budget. Offline, palace reads and
renders work; only ingestion requires the sanctioned network exit.*

### Scope

`jelly-server/src/routes/embed.ts` POST endpoint hosting
Qwen3-Embedding-0.6B (256d MRL-truncated per D-002), CLI
`--embed-via <url>` flag on `jelly palace inscribe`, K-NN query
integration via `store.ts` `kNN` verb (built in Epic 2; Epic 6 is the
primary caller), graceful-degradation path when embedding endpoint
unreachable, and `TODO-EMBEDDING: bring-model-local-or-byo` marker at
every call site.

### Out of Scope

- Local-first WASM/ONNX embedding model (post-MVP follow-up per D-002).
- Quantised low-precision vectors (PRD FR83; deferred).
- Batch ingestion endpoint (D-012: one content in, one vector out).
- Streaming embeddings (D-012).
- Mocked-vector path (rejected as stretch per sprint-scope.md).

### Primary FRs (canonical home)

- **FR20** — Qwen3-Embedding-0.6B + LadybugDB vector extension + K-NN
  query + `--embed-via` CLI hook.

### Secondary touch points (FRs homed elsewhere that this epic supports)

- **FR13** — Oracle knowledge-graph K-NN over inscriptions (oracle
  consumer; canonical home Epic 4).
- **FR21** — Re-embedding delete-then-insert uses the `reembed` verb
  (canonical home Epic 2); Epic 6 supplies the replacement vector.

### Non-Functional Requirements

- **NFR11** (primary — sanctioned exit) — embedding creation is the
  single documented network exit; every other palace operation works
  offline.
- **NFR13** — opt-in `--embed-via` flag; default local
  `http://localhost:9808/embed`; user-supplied URL allowed.
- **NFR15** (primary) — `TODO-EMBEDDING: bring-model-local-or-byo`
  marker at every call site (CLI flag handler, server route, client
  module, file-watcher invocation).
- **NFR10** — K-NN top-10 over 500 inscriptions <200 ms (FR20
  acceptance).
- **NFR17** — `scripts/server-smoke.sh` extended with embedding
  endpoint smoke.

### Technical Constraints applicable

TC2 (Bun + TS), TC8 (LadybugDB vector extension), TC12 (K-NN through
`store.ts` only), TC13 (CAS source-of-truth; embedding is a persisted
property on `Inscription` row, not a separately-stored bytes blob).

### Security Requirements applicable

SEC6 (sanctioned exit explicitly documented; palace content leaves
only via explicit `--embed-via` user action), SEC7 (`TODO-EMBEDDING`
markers preserved; no silent upgrade of the interim path).

### Architecture Constraints

- **D-012 (MEDIUM)** — Single POST `/embed`, one content in, one vector
  out. No batch, no streaming. Request body: `{content: string,
  contentType: 'text/markdown'|'text/plain'|'text/asciidoc'}` with 1 MB
  limit. Response: `{vector: number[256], model: 'qwen3-embedding-0.6b',
  dimension: 256, truncation: 'mrl-256'}`. Elysia route with strict
  TypeBox schema.
- **D-015 (consumer)** — K-NN queries use the verified cross-runtime
  path from Epic 2 story 1. If the parity spike degraded to server-
  only, Epic 6's `kNN` calls route through `HttpBackend` only and a
  documented NFR11 relaxation ships.
- **D-007 (consumer)** — Vector writes via `upsertEmbedding` /
  `reembed`; reads via `kNN`. No raw Cypher in `jelly-server` or CLI.
- **D-016 (consumer)** — Embedding is a column on `Inscription`
  (`embedding: FLOAT[256]`), not a separate node. K-NN query pattern
  per D-016 § Epic F consequences:
  ```
  CALL QUERY_VECTOR_INDEX('inscription_emb', $q, $k)
    YIELD node AS i, distance
  MATCH (i:Inscription)-[:LIVES_IN]->(r:Room)
  RETURN i.fp, r.fp, distance
  ORDER BY distance;
  ```
- **D-002 (inherited)** — Qwen3-Embedding-0.6B (Apache 2.0) at 1024d
  native, MRL-truncated to 256d after server-side processing. Every
  site carries `TODO-EMBEDDING: bring-model-local-or-byo`.
- **Cross-epic coupling — NFR11 offline degradation** — Only ingestion
  hits network; reads + renders + oracle queries all local. Phase 5
  validation disables network and runs palace ops end-to-end to
  verify.

### Primary Modules

- `jelly-server/src/routes/embed.ts` (new) — D-012 wire shape.
- `src/memory-palace/embedding-client.ts` (new) — HTTP client with
  graceful-degradation shape; called by CLI and file-watcher.
- `src/cli/palace_inscribe.zig` (consumer) — `--embed-via` flag handler
  (Epic 3 surface; Epic 6 supplies the client module it invokes).
- `src/memory-palace/store.ts` (consumer) — `upsertEmbedding`, `kNN`,
  `reembed` verbs from Epic 2.
- `scripts/server-smoke.sh` (extend) — `/embed` endpoint smoke.

### Estimated Stories (3)

_Placeholder for Phase 3 story enrichment._ Anchor shapes from Phase 2
scoping:

- **S6.1** — `jelly-server` `/embed` endpoint with Qwen3-Embedding-0.6b
  + 256d MRL truncation (D-012, D-002).
- **S6.2** — `embedding-client.ts` HTTP client + graceful-degradation
  path + `--embed-via` CLI flag wiring + `TODO-EMBEDDING` markers
  (NFR11, NFR13, NFR15).
- **S6.3** — K-NN integration test (500 inscriptions, top-10 <200 ms,
  FR20 acceptance) + `server-smoke.sh` extension.

### Epic Health Metrics

*(Phase 3 fills. Placeholder.)*

---

## Epic Health Metrics (Phase 3 placeholder)

Filled during Phase 3 story enrichment. Shape:

| Epic | Stories | ACs total | Build-gates covered | Golden fixtures | Open Questions |
|------|---------|-----------|---------------------|-----------------|----------------|
| 1 | 5 | _tbd_ | zig-test, zig-smoke, bun-test-unit, codegen | 13 | _tbd_ |
| 2 | 5 | _tbd_ | bun-test-unit, cli-smoke, server-smoke | — | _tbd_ |
| 3 | 6 | _tbd_ | cli-smoke, zig-smoke | — | _tbd_ |
| 4 | 4 | _tbd_ | server-smoke, e2e-cryptography | — | _tbd_ |
| 5 | 5 | _tbd_ | test-storybook, bun-test-unit | — | _tbd_ |
| 6 | 3 | _tbd_ | server-smoke, bun-test-unit | — | _tbd_ |
| **Total** | **28** | _tbd_ | (all gates extended) | 13 | _tbd_ |

---

## Self-Validation (Phase 2B Checklist)

**Coverage:**

- [x] All 26 FRs assigned to exactly one canonical home epic (FR Coverage
  Map table: 26 rows, zero duplicates).
- [x] All 9 NFRs noted as applicable to ≥1 epic (NFR10→Epic 5, NFR11→Epic
  2/3/4/6, NFR12→Epic 1/3/4, NFR13→Epic 2/3/4/6, NFR14→Epic 5, NFR15→Epic
  3/4/6, NFR16→Epic 1/5, NFR17→all, NFR18→Epic 1).
- [x] All 11 SECs noted as applicable to ≥1 epic.
- [x] All 21 TCs noted as applicable to ≥1 epic.
- [x] All 10 architecture decisions (D-007..D-016) referenced by their
  canonical epic with a one-line note on how they constrain.

**Size:**

- [x] Each epic has 2–6 stories (actual: 5/5/6/4/5/3 — all within
  range; total 28 matches `phase-state.json` estimate).

**Dependencies:**

- [x] No cycles. Dependency graph: 1 → 2 → {3, 6} → {4, 5}.
- [x] Epic 1 has zero dependencies.
- [x] Epic N never depends on Epic N+1 (no forward edges).
- [x] Cross-epic couplings (FR26 formulas, FR14 file-watcher, FR18 lazy
  creation, NFR11 offline, NFR12 dual-sig) declared explicitly in each
  consumer epic's *Architecture Constraints* section, not hidden.

**Architecture alignment:**

- [x] Every epic references its constraining D-007..D-016 decisions with
  a one-line constraint note.
- [x] No `[ARCH GAP]` flags — Phase 2A covered the architectural surface
  (10 decisions adopted; user `accept-all-2026-04-21`).
- [x] Risk register (R1–R8) mitigations embedded in story-1 gates for
  Epics 1, 2, 5 (R3, R2/R5, R4).

**Quality:**

- [x] Every epic title completes "After this epic, the system can /
  users can…" — user/system-value framing, not layer names.
- [x] Every "Out of Scope" section names concrete excluded items, not
  hand-waves.
- [x] Every cross-epic contract is named (FR26 formulas in
  `aqueduct.ts`; FR14 skill composes B+C+F; NFR12 dual-sig sign-sites;
  NFR11 ingestion-only exit).

---

## Stories — Phase 3 Decomposition

Per-epic story specs (with BDD acceptance criteria + technical notes +
scope boundaries) live as separate files under `stories/` to keep this
index document readable. Each file is the single source of truth for
its epic's stories.

| Epic | File | Stories | Tier mix |
|---|---|---|---|
| 1. Speak palace on the wire | [`stories/epic-1.md`](stories/epic-1.md) | 5 | 3 thorough · 2 smoke |
| 2. Remember the palace across runtimes | [`stories/epic-2.md`](stories/epic-2.md) | 5 | 5 thorough |
| 3. Mint, grow, and name from the CLI | [`stories/epic-3.md`](stories/epic-3.md) | 6 | 3 thorough · 2 smoke · 1 yolo |
| 4. Converse with the oracle who remembers | [`stories/epic-4.md`](stories/epic-4.md) | 4 | 3 thorough · 1 smoke |
| 5. Walk the palace with eyes | [`stories/epic-5.md`](stories/epic-5.md) | 5 | 2 thorough · 3 smoke |
| 6. Recall by resonance | [`stories/epic-6.md`](stories/epic-6.md) | 3 | 2 thorough · 1 smoke |
| **Total** | — | **28** | **18 thorough · 9 smoke · 1 yolo** |

### Aggregate health

- **Story count target**: ambitious sprint = 15–30. **28 stories** sits in the upper-middle of the band ✓.
- **Test-tier distribution**: 64% thorough, 32% smoke, 4% yolo. Thorough concentration justified by data-integrity (Epic 2 5/5), cross-epic coupling (Epic 4 file-watcher, Epic 5 traversal round-trip), and risk-gate posture (Epics 1, 2, 5 each open with thorough gate).
- **Risk-gate placement**: three story-1 slots probe sprint risks early — Epic 1 S1.1 (R3 WASM ML-DSA verify) · Epic 2 S2.1 (R2 cross-runtime vector parity) · Epic 5 S5.1 (R4 Threlte shader new territory). Each carries a documented HARD-BLOCK fallback so failure triggers replan.
- **FR coverage**: 26/26 primary sprint FRs assigned to a canonical story. Multi-home FRs (FR1, FR9, FR18, FR26) resolved per Phase 2B rules with secondary touch points recorded in consumer-epic Architecture Constraints. No orphans, no duplicates.
- **Cross-epic dependency graph**: still acyclic. Epic 4 S4.4 consumes Epic 6 S6.2 (`embedding-client.ts`); Epic 6 does not depend back. Epic 5 S5.5 round-trips through Epic 2 + Epic 3 (consumes their primitives, doesn't reverse).

### Cross-epic reconciliation findings (Phase 3 verifier pass)

Inline reconciliation across all six story files:

1. **`Inscription.orphaned: BOOL` column** — added by Epic 4 S4.4 (orphan handling) but Epic 2 S2.4 schema enumeration doesn't list it. **Fix at S2.4 kickoff:** extend `src/memory-palace/schema.cypher` with `orphaned: BOOL DEFAULT false` on `Inscription`. Land upfront in S2.4; S4.4 only writes to it. Schema migrations mid-sprint are an anti-pattern given the single-`open()` DDL story.
2. **Action-kind enum upfront** — multiple new kinds introduced across epics: `palace-minted` (S3.2), `room-added` (S3.3), `avatar-inscribed` (S3.3), `aqueduct-created` (S3.3+S5.5), `move` (S5.5+S4.3), `true-naming` (S3.4), `inscription-updated` (S4.4), `inscription-orphaned` (S4.4), `inscription-pending-embedding` (S6.2). **Fix at S1.2 kickoff:** Epic 1 Story 1.2 adds the full enum to `Action.action_kind` upfront so codegen (S1.5) emits a stable union for downstream consumers. No naming drift across epics.
3. **`Inscription.source_blake3` vs `body_hash`** — Epic 4 S4.4 references `source_blake3`; Epic 2 S2.4 mentions `body_hash`. Same concept, two names. **Fix at S2.4 kickoff:** standardise on `source_blake3` (matches `jelly.inscription.source` envelope semantics).
4. **Test fixture count (13 vs 14)** — Epic 1 S1.4 carries an open question about the canonical fixture count per PROTOCOL.md §13.11. **Resolve at S1.4 kickoff** by reading lines 1156–1181; update both S1.4 and PROTOCOL.md in the same commit if the count is 14.
5. **No duplicate stories detected.** Lazy aqueduct creation appears in both Epic 3 S3.3 (CLI inscribe-into-room edge) and Epic 5 S5.5 (renderer room↔room traversal); both call the same Epic 2 helper through `store.recordTraversal`/`ensureAqueductLazy`. Distinct call sites of the same primitive.
6. **No scope boundary violations detected.** Each story's `Does NOT` list cleanly defers to the canonical owner.
7. **No naming conflicts detected.** Schema vocabulary (`Palace`, `Room`, `Inscription`, `Agent`, `Mythos`, `Aqueduct`, `ActionLog`) consistent across all six story files.

**Reconciliation status: clean** (1 minor schema fix + 1 enum-upfront + 1 wording standardisation; all auto-fixable at story kickoff, no architecture rework).

### Risk register status post-Phase 3

| ID | Severity | Where mitigated | Status |
|----|----------|-----------------|--------|
| R1 | HIGH | Epic 2 S2.3 (Chromium-only MVP per OQ3) | Open — Phase 5 Playwright FF+Safari smoke is the trigger for HTTP-fallback story |
| R2 | MED-HIGH | Epic 2 S2.1 first story | Open — gated by spike outcome |
| R3 | HIGH | Epic 1 S1.1 first story | Open — gated by WASM verify test |
| R4 | HIGH | Epic 5 S5.1 first story | Open — gated by 6-checkbox shader spike |
| R5 | MED | Epic 6 S6.3 perf test | Open — measured during execution |
| R6 | MED | Epic 4 S4.4 fault-injection matrix + Epic 6 S6.2 client-reuse contract | Mitigated at design level; tested at execution |
| R7 | MED | Epic 2 S2.5 + Epic 5 S5.5 bit-identical parity test | Mitigated at design level; tested at execution |
| R8 | LOW-MED | Epic 3 S3.1 dispatch scaffold first story | Open — gated by A3 validation |

### Phase 4 enrichment

**Skipped** in default mode per orchestrator. Stories ship to execution as stubs with BDD criteria. Enrichment available on-demand via inter-epic huddle (`[enrich N.M]`) or when sprint-exec detects a complex story that would benefit. Four high-complexity stories flagged for likely on-demand enrichment: **Epic 2 S2.5** (FR26 formula home with R7 parity), **Epic 4 S4.4** (file-watcher D-008 fault-injection matrix), **Epic 5 S5.5** (renderer round-trip + 3 shaders + NFR10 close), **Epic 6 S6.3** (K-NN perf budget + offline graceful-degradation).

---

## Changelog

- **2026-04-21 (later)** — Phase 3 Story Decomposition complete. Six parallel planner agents (opus) returned 28 story stubs with full BDD acceptance criteria, technical notes, and scope boundaries. Per-epic files written to `stories/` (one per epic, ~280–530 lines each). Inline cross-epic reconciliation pass produced 3 minor fixes to apply at story kickoff (Inscription.orphaned column, action-kind enum upfront, source_blake3 wording standardisation) — all auto-fixable, no architecture rework. Reconciliation status: clean. Phase 4 enrichment skipped per default-mode orchestrator. Next: Phase 5 validation (sonnet verifier + readiness report).
- **2026-04-21** — Initial `epics.md` from Phase 2B Epic Design.
  Formalised the six-cluster structure proposed in `sprint-scope.md §
  In-Scope Clusters`. Preserved cluster ordering A→B→C→D→E→F as Epic
  1→2→3→4→5→6; renamed to palace-mythos user-value titles. Resolved
  multi-home FRs (FR1, FR9, FR18, FR26) to canonical homes per the
  phase-prompt rules with secondary touch points recorded in consumer
  epics. Mapped all 26 FRs, 9 NFRs, 21 TCs, 11 SECs, and 10 architecture
  decisions (D-007..D-016). Dependency graph verified acyclic with
  zero forward edges. Epic sizes 5/5/6/4/5/3 all within the 2–6 band.
  Phase 3 story enrichment is the next phase.
