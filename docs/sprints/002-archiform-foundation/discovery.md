---
project: Dreamball
sprint: sprint-002
created: 2026-04-28
new_repo: false
input_quality: existing-prd
has_ux_artifacts: true
has_frontend: true
previous_sprint: sprint-001
---

# Phase 0 Discovery — Sprint-002 Archiform Foundation

## Project Overview

Dreamball is a federated cryptographic agent framework built on a Zig protocol core, WASM runtime, TypeScript/Svelte frontend, and Elysia REST server. Sprint-001 delivered the Memory Palace MVP (28 stories, 6 epics) — a specialized archiform for knowledge management with tree-structured rooms, inscriptions, aqueduct traversal networks, and Qwen3-Embedding-0.6B semantic recall. 

Sprint-002 pivots from single-archiform broadening (asset envelopes) to foundational work that enables the ecosystem: decoupling Memory Palace from the root protocol via a federated archiform registry on aspects.sh, inverting the codegen pipeline to make JSON Schema canonical, introducing a universal action manifest for all archiform operations, and establishing wasm as the sandboxed runtime for executable code across all layers (actions, lenses, derivations, policies).

## Input Analysis

**Input Quality**: `existing-prd` (formal architecture decisions with explicit consequences and migration plans)

**Product Input**: Four dated architecture decision notes produced on 2026-04-25 (the day after sprint-001 completion):

1. **2026-04-25-archiform-registry.md** — aspects.sh becomes the registry for DreamBall archiforms under a 3-layer model (Schema / Manifestation / Instance). Memory Palace becomes one schema-aspect among many. Genesis envelopes gain an `archiform_fp` field; older instances implicitly bind to `dreamball/memory-palace@0.1.0` for back-compat.

2. **2026-04-25-json-schema-canonical.md** — JSON Schema becomes canonical source for all field shapes (root types and archiform extensions). CBOR encoding algorithm stays Zig-canonical with golden test vectors. Codegen flow inverts: `schemas/root-2.0.0.json` + `schemas/<archiform>.json` → generators consuming JSON Schema (not Zig) to emit TS, Valibot, CBOR, Cypher DDL. Sprint-002 must include byte-equivalence gate: regenerated outputs MUST match current Zig-generated outputs.

3. **2026-04-25-action-manifest.md** — Universal action contract declared inside archiform JSON Schema. CLI, REST, MCP, in-renderer, and programmatic clients are mechanical projections of the manifest. Actions are pure transactions (no interactive prompts in action bodies). Confirmation, destructiveness, and idempotency declared as attributes; projection layers render them in their idiom.

4. **2026-04-25-wasm-runtime.md** — Wasm is the runtime for all executable code in DreamBalls (action implementations, lens shaders, derivation rules, policy evaluators). Bun-script fallback for early authoring. Modules run with WASI; imports limited to `dreamball.*` namespace. Content-addressed by blake3(wasm_bytes); action manifest's `implementation.wasm` field is an fp.

**Gaps Requiring Phase 1B User Negotiation**:

- Sprint-001 retrospective recommended "broadening inscriptions beyond text" via `jelly.asset` envelopes (glTF, splats, HDRI, images) as sprint-002 focus. The four 2026-04-25 notes pivot toward archiform-foundation work. Phase 1B must negotiate which is primary: asset-envelope ingestion or archiform-foundation infrastructure. The four notes represent a deliberate architectural pivot *away* from asset work toward ecosystem layering — the user's decision on sprint scope is not yet confirmed.

- Open Questions from retrospective (§Open Questions for Sprint-002 Phase 0) remain unresolved and should surface during Phase 1B requirements expansion.

---

## New Repo Detection

**Classification**: `new_repo: false` (existing codebase)

**Evidence**:
- 117 source files across src (Zig + TypeScript)
- Build manifests: `package.json`, `build.zig`, `jelly-server/package.json`
- Source directories: `src/`, `src/lib/` with mature structure
- Existing commits: 16 substantive commits from sprint-001 over 4 days

---

## Existing Codebase Inventory

### Tech Stack

**Core**:
- **Zig 0.16.0** — Protocol core, wire format (CBOR encode/decode/sign/seal/verify), CLI binary, schema-gen tool
- **TypeScript 6.0.2** — Frontend library, type system, API client, bridge patterns
- **Svelte 5.55.2** — Renderer (Threlte 3D integration)
- **Bun 1.x** — Package manager, runtime for jelly-server and CLI bridge patterns

**Critical Dependencies**:
- **@ladybugdb/core 0.15.3** — Graph database for Knowledge Graph storage (node labels, relationships, ActionLog commit-table)
- **kuzu-wasm 0.11.3** — Cypher query execution (traversal state + kNN recall)
- **elysia 1.4.28 + @elysiajs/eden** — REST framework + typed RPC client
- **valibot 1.3.1 + @valibot/to-json-schema** — Runtime schema validation, JSON Schema round-tripping
- **@threlte/core + @threlte/extras + three.js 0.184.0 + playcanvas 2.18.0** — 3D rendering (palace grid, aqueduct flows, inscription meshes, shaders)

**Crypto**:
- **std.crypto.sign.Ed25519** (Zig std) — Tier 1 signing (default, always available)
- **vendored liboqs subset** (in jelly CLI + jelly.wasm) — ML-DSA-87 post-quantum verify path (Tier 2)
- **recrypt integration** (Rust recrypt-server sibling) — Guild-scoped proxy-recryption (Tier 3)

**Testing & Tooling**:
- **vitest 4.1.3** — Unit test framework
- **@vitest/browser-playwright** — Browser/WASM testing
- **@playwright/test 1.59.1** — E2E testing
- **storybook 10.3.5** — Component documentation
- **prettier 3.8.1 + eslint 10.2.0** — Code style/linting
- **publint 0.3.18** — Package validation

### Project Structure

```
Dreamball/
├── src/                          # Zig protocol core + TypeScript source
│   ├── *.zig                    # 15+ Zig files: main, protocol, envelope, signer, sealing,
│   │                            # identity_envelope, dcbor, json, golden, base58, io
│   ├── wasm_main.zig           # WASM entry point; crypto exports
│   └── lib/
│       ├── generated/           # GENERATED: types.ts, schemas.ts, cbor.ts, cbor.test.ts
│       ├── index.ts            # Main library export
│       ├── backend/            # Storage adapters (HttpBackend for jelly-server)
│       ├── bridge/             # Zig↔TS bridge patterns for mutations
│       │                       # (palace-mint, palace-inscribe, palace-add-room, etc.)
│       ├── wasm/               # WASM loader, verify.test.ts, write-ops.test.ts
│       ├── components/         # Svelte components (to be inventoried)
│       ├── lenses/             # Lens types (AvatarLens, EmotionalStateLens, PalaceLens)
│       ├── stories/            # Storybook story files
│       ├── shaders/            # Four-shader render pack (aqueduct-flow, room-layout, etc.)
│       ├── splat/              # Gaussian splatting renderer
│       └── playcanvas/         # PlayCanvas integration
├── jelly-server/                # Elysia REST server + Eden typed client
│   ├── src/index.ts            # Routes, store initialization
│   └── tsconfig.json
├── tools/
│   ├── schema-gen/
│   │   └── main.zig            # CURRENT: Zig-canonical schema generator (to be inverted)
│   └── wasm-verify-fixture/    # WASM verification test harness
├── scripts/
│   ├── cli-smoke.sh            # Zig CLI end-to-end integration test
│   ├── server-smoke.sh         # jelly-server HTTP end-to-end test
│   ├── bootstrap-kuzu-wasm.ts  # LadybugDB wasm loader
│   └── e2e-cryptography.sh     # Crypto pipeline (mock or real via RECRYPT_SERVER_URL)
├── tests/
│   ├── e2e-cryptography.sh     # Cross-runtime crypto verification
│   └── (inline test blocks in src/*.zig)
├── docs/
│   ├── ARCHITECTURE.md          # Runtime map, crypto tiers, data flows, ADRs
│   ├── PROTOCOL.md             # Wire format spec (prescriptive)
│   ├── VISION.md               # Conceptual model (descriptive; refs ADR-1, §14)
│   ├── known-gaps.md           # TODO-CRYPTO markers, deferred work tracker
│   ├── decisions/              # 23 dated ADR files (2026-04-20 through 2026-04-25)
│   └── sprints/
│       ├── 001-memory-palace-mvp/
│       │   ├── retrospective.md # Sprint-001 execution review (complete, 28/28)
│       │   └── stories/        # Story records
│       └── 002-archiform-foundation/
│           └── (Phase 0 discovery output → here)
├── .github/
│   └── workflows/ci.yml         # CI gates (zig test, smoke, build, bun check, test:unit)
├── build.zig                     # Zig build manifest
├── package.json                  # Bun + npm dependencies (dual-use)
├── tsconfig.json                # Root TypeScript config
├── vite.config.ts              # Vite dev server
├── svelte.config.js            # SvelteKit config
└── .omc/sprint-plan/            # Sprint planning artifacts
    ├── decisions/decision-log.md # Decision chronology
    ├── sprint-001/
    └── sprint-002/
```

### Existing Patterns

**API & Transport**:
- REST via Elysia (port 9808); Eden-typed RPC client for browser consumption
- CBOR wire format (canonical in Zig; mirrored through jelly.wasm in TS runtime)
- MCP server (stdio) for Claude Code agent integration (planned)

**Storage & State**:
- LadybugDB as the primary KG store (node labels, relationships, ActionLog commit table)
- kuzu-wasm for Cypher queries (kNN recall, traversal state)
- File-watcher for oracle state mutations with logical commit-ordering + replay-from-CAS recovery
- Filesystem CAS for `.jelly` files and `.jelly.key` (plaintext, 0600 perms, sprint-001 compromise)

**Crypto & Identity**:
- Three tiers: Ed25519-only (default), Ed25519 + ML-DSA-87 (Tier 2), proxy-recryption (Tier 3, sealed)
- Dual-sig currently broken (sentinel fp substitution in S4.4/S5.5; real signer export needed)
- Genesis envelopes carry root protocol; archiform fps to be added via genesis extension

**Frontend & Rendering**:
- Svelte 5 with Threlte for 3D palace grid
- Four-shader render pack (aqueduct flow, room layout, inscription scroll, emotion state)
- Lens abstraction (AvatarLens, EmotionalStateLens, PalaceLens) for different views
- Storybook for component docs

**Testing & Verification**:
- Inline Zig test blocks (≥51 passing in sprint-001)
- Vitest + @vitest/browser-playwright for TS/WASM
- Smoke gates: `zig build smoke`, `scripts/server-smoke.sh`, `scripts/e2e-cryptography.sh`
- All three gates must pass before commit; none run in isolation

**Modularity**:
- Single monorepo (not split across services yet; all runtime surfaces colocated)
- Cross-runtime invariant: one Zig source of truth; all other surfaces derived (no hand-written schemas)
- Bridge pattern (Zig staging → Bun TS bridge → promote on success) emerging as reusable mutation primitive

### Module Boundaries

| Module | Purpose | Owner Stories (S-001) | Sprint-002 Relevance |
|---|---|---|---|
| **Zig Core** (`src/*.zig`) | Protocol definition, CBOR, signing, sealing, verification, CLI verbs | E1, E2, E3 (all 6 epics touch it) | Inverted: JSON Schema → Zig generators; archiform extensions |
| **WASM** (`src/wasm_main.zig`, `jelly.wasm`) | Cross-runtime crypto primitives (ED25519, ML-DSA-87 verify, blake3) | E2, E4 | Runtime host for actions + lenses; `dreamball.*` import namespace |
| **Store** (`src/lib/backend/`, `store.ts`) | LadybugDB + KG abstraction (domain verbs + escape hatch) | E2, E5, E6 (15 stories) | Unchanged API; archiform extensions loaded by codegen |
| **Bridge** (`src/lib/bridge/*`) | Zig↔TS staging pattern for palace mutations | E3 (5 stories) | Pattern to D-NEW-B; action manifest implementations call it |
| **Oracle** (`oracle.ts`, `policy.ts`, `file-watcher.ts`) | Write identity, policy evaluation, traversal recording | E4 (4 stories) | Signer parameterisation (D-NEW-C) lands here; manifest actions called |
| **Lenses** (`src/lib/lenses/*`) | View abstractions (Avatar, EmotionalState, Palace) | E5 (6 stories) | Derive from action manifest; wasm runtime for computations |
| **Shaders** (`src/lib/shaders/*`) | Four-shader render pack (E5 spike D-009 revision) | E5 (spike + 3 follow-up) | Stateless; wasm derivation rules called from lens shader side |
| **Embedding** (`qwen3.ts`, `embedding-client.ts`, `embed.ts`) | Qwen3-Embedding-0.6B loader + kNN recall | E6 (3 stories) | Weights provisioning deferred (TODO-EMBEDDING); kNN over memory-nodes deferred to S-003 |
| **CLI** (`main.zig`, `palace.zig`) | Verb dispatch (palace mint, inscribe, add-room, etc.) | E3, E4 (2 stories direct) | Generated from action manifest; jelly dispatch unchanged (palace.zig) |
| **Server** (`jelly-server/src/index.ts`) | REST routes, store initialization, subprocess Zig for signing | E3 (1 story), E6 (2 stories) | Action manifest projections (CLI, programmatic, MCP); Eden routes |

---

## Available Artifacts

- `/Users/dukejones/work/Identikey/Dreamball/.omc/sprint-plan/AGENTS.md` — Agent catalog (not yet read; standard OMC template)
- `/Users/dukejones/work/Identikey/Dreamball/.omc/sprint-plan/decisions/decision-log.md` — Sprint-001 ADR chronology (16 decisions D-001 through D-016, all `accepted`)
- `/Users/dukejones/work/Identikey/Dreamball/docs/sprints/001-memory-palace-mvp/retrospective.md` — Full sprint-001 execution review with velocity, learnings, technical debt, and architecture evolution notes
- `/Users/dukejones/work/Identikey/Dreamball/docs/decisions/` — 23 dated ADR files spanning 2026-04-20 through 2026-04-25 (D-001 through D-016 from sprint-001, plus D-NEW-A through D-NEW-H emerging post-sprint)

---

## UX Status

**Frontend Present**: Yes (`has_frontend: true`)

**Rendering Stack Mature**: Svelte 5 + Threlte + three.js + PlayCanvas already in production. Sprint-001 shipped:
- Four-shader render pack (aqueduct flow, room layout, inscription scroll, emotion state)
- Three lens types (Avatar, EmotionalState, Palace)
- Storybook documentation (storybook dev / build-storybook / test-storybook commands)

**UX Artifacts Present**: Yes (`has_ux_artifacts: true`)

- **Visual Designs Shipped**: Palace grid layout, room nesting, aqueduct traversal flows with phase-coloured pulses, inscription mesh text, emotion-state meter
- **Storybook Reference**: `/Users/dukejones/work/Identikey/Dreamball/.storybook/` (Chromatic integration for visual regression testing)
- **Component Gallery**: Stories in `src/lib/stories/` for each lens type

**Implication for Sprint-002**: This is a tools/protocol sprint, not a UX sprint. New UX design work is unlikely. Archiform-foundation and action-manifest work may require new UI patterns (action-confirmation dialogs, streaming result displays) but these follow mechanically from the manifest spec. No new design artifacts needed for Phase 1.

---

## Previous Sprint Intelligence (Sprint-001)

### Key Learnings from Retrospective

**What Held Strongly**:

1. **D-007 store-wrapper discipline** — Single biggest load-bearing decision; zero `__rawQuery` drift outside its sanctioned use in `palace_mint`. AC7-style grep audits (`no __rawQuery in oracle.ts; no fetch( in file-watcher.ts`) caught discipline drift cheaply.

2. **D-015 vector-parity spike** — max |Δ| = 0.000048 against 0.1 threshold; eliminated entire kuzu-wasm fallback branch from S2.3 and S6.3. Worth the upfront investment.

3. **R5 perf gate** — 200ms hard budget cleared by 23× (p50 = 8.7ms, p95 = 9.1ms). Seeded 500-corpus fixture pattern is reusable.

4. **Bridge pattern** (Zig staging → Bun bridge → promote on success) — Delivered SEC11 atomicity cleanly; reused across 5 stories. Candidate for D-NEW-B.

5. **Mock seams** (`JELLY_EMBED_MOCK=1`, `JELLY_SERVER_NO_LISTEN=1`) — Kept CI fast without compromising production wire shape.

**What Didn't Work** (regression classes):

1. **S5.4 Silent scope substitution (HIGH)** — Original delivery used HTML overlay divs instead of 3D mesh text. Not caught by automated audit gate; caught by user review. Remediated cleanly.

2. **S4.4 + S5.5 Dual-sig sentinel substitution (HIGH)** — Both detected that `jelly.wasm` lacks `signActionEnvelope(keypair, bytes)` and substituted derived-fp sentinel rather than raising a blocker. Same regression class as S5.4. Deferred as D-NEW-C.

3. **Late-discovered StoreAPI surface gaps** — `getPalace`, `roomsFor`, `roomContents`, `inscriptionBody` added ad-hoc by E5 rather than driven from spec. Planning gap: surface authority should live in architecture-decisions, not story-execution time.

4. **Two stories stalled mid-execution** (S3.4, S3.6) — Dev Agent Record signing pattern ambiguous on executor timeout; orchestrator finalized manually.

5. **Pre-existing dirty tree** — 27 unrelated test failures in S5.1 from sibling work not gated at story entry.

### Technical Debt Summary

**Highest Priority** (blocks sprint-002 forward progress):

- **Dual-sig WASM signer not parameterised** — sentinel fp in `oracle.ts oracleSignAction` and `store.recordTraversal`. Must land before any story shipping real dual-sigs. Retrospective recommends: migrate sentinel call sites to real Ed25519 single signatures (small lift; closes "scope substitution" finding). D-NEW-C.

- **TODO-CRYPTO oracle key plaintext** — 6 stories compound on D-011 (plaintext + 0600 perms accepted for MVP). Recrypt-wallet integration + chained proxy-recryption deferred to security pass (steering decision 2026-04-25 — Ed25519-only OK for sprint-002).

- **Partial-write window in inscription mirroring** — LadybugDB v0.15.3 lacks BEGIN/COMMIT. Sprint-001 documented "retry-is-idempotent" semantics; high priority for sprint-002 if mutations expand.

**Medium Priority** (sprint-002 candidates):

- **AC6 rename propagation + AC7 compile-in seed** (S4.1 silent deferrals) — should fold into oracle-hardening story
- **`casDir` configuration plumbing** — needs `PALACE_CAS_DIR` env or `opts.casDir`
- **Storybook test-infra repair** — pre-existing Playwright+Chromium harness issue; S6.3 had to skip AC10 coverage
- **Qwen3 weights provisioning** — loader landed (S6.1); weights are operational gap (TODO-EMBEDDING)

**Low Priority** (post-MVP backlog):

- **kNN over memory-nodes** — MVP scoped to inscriptions only; candidate for S-003 Growth promotion
- **Quantised vectors + hybrid lexical+semantic** — post-MVP
- **store.ts runtime auto-routing** — punted via direct `store.browser.ts` import; S-003 reattempt

### Architecture Decisions Carried Forward

From decision-log.md (16 decisions, all `accepted`):

| ID | Title | Tier | Notes |
|---|---|---|---|
| D-001 | Oracle file-watcher → MVP | HIGH | Held; sync mutation + CAS recovery |
| D-002 | Qwen3 256d MRL-truncated | HIGH | Held; server-hosted; weights deferred |
| D-003 | Aqueduct lazy-on-first-traversal | MEDIUM | Held; perf gate confirmed |
| D-004 | Aqueduct formulas (Hebbian+Ebbinghaus) | HIGH | Held; R7 bit-identity tests locked drift |
| D-005 | Oracle write identity = sibling hybrid keypair | HIGH | Held; plaintext 0600 for sprint-001; recrypt deferred |
| D-006 | Head-hashes pluralization | HIGH | Held; spec-present, code verified |
| D-007 | Store wrapper API (domain verbs + escape hatch) | CRITICAL | Held; zero drift, load-bearing decision |
| D-008 | File-watcher transactional = inline | HIGH | Partial; revised to logical-ordering + replay; candidate D-NEW-A |
| D-009 | Shader spike = aqueduct-flow E2E | HIGH | Revised; broadened to 4-shader pack; +3 follow-ups |
| D-010 | WASM ML-DSA-87 verify | CRITICAL | Partial; Vitest green, Playwright deferred |
| D-011 | Oracle key plaintext 0600 | MEDIUM | Partial; custody held, signer parameterisation gap surfaced (D-NEW-C) |
| D-012 | Embedding endpoint = single POST /embed | MEDIUM | Held; one mid-sprint reconcile (S4.4→S6.1→S6.2) |
| D-013 | CLI dispatch = flat-table (palace.zig) | MEDIUM | Held; R8 risk cleanly resolved |
| D-014 | Archiform registry cache = snapshot-on-mint | MEDIUM | Held; byte-deterministic |
| D-015 | Vector parity ≤0.1 ordinal distance | HIGH | Held; spike returned 0.000048; fallback eliminated |
| D-016 | LadybugDB schema (node+rel+ActionLog) | CRITICAL | Partial/revised; additive DDL S2.5/S3.2, one structural retrofit (KG-as-JSON → Triple table) |

**Decisions Needing Revision in Sprint-002**:

- **D-008** — explicit ADR for "logical-ordering + replay-from-CAS" transactional model
- **D-011** — close dual-sig parameterisation hole; add `signActionEnvelope(keypair, bytes)` export to jelly.wasm
- **D-016** — promote `2026-04-24-kg-triple-native-storage` to numbered decision; codify `Palace→Agent CONTAINS` edge and `Aqueduct.last_traversal_ts` as schema citizens

**New Decisions to Promote** (D-NEW-A through D-NEW-H from retrospective §Next Epic Preparation):

- **D-NEW-A** — LadybugDB transactional model (logical-commit + replay)
- **D-NEW-B** — Bridge pattern for Zig↔TS palace mutations
- **D-NEW-C** — Dual-sig parameterisation through jelly.wasm
- **D-NEW-D** — Spike-before-promote default for new shaders/materials/lenses
- **D-NEW-E** — Forward-declare consumer seam contracts in architecture-decisions.md
- **D-NEW-F** (already ADR) — Surface registry + fallback chain
- **D-NEW-G** (already ADR) — Coord-frames composition
- **D-NEW-H** (already ADR) — Triple-native KG storage

---

## Recommendations

### 1. **Scope Tension — Asset Envelopes vs. Archiform Foundation**

The retrospective's "Sprint-002 Focus" (§Recommended Focus) recommended **broadening inscriptions beyond text** via `jelly.asset` envelopes (glTF, splats, HDRI, images). The four 2026-04-25 decision notes represent a **pivot away** from this toward foundational work: archiform registry, JSON-Schema canonicalization, action manifest, wasm runtime.

**Flag for Phase 1B**: User input required to settle scope. Both paths are valid; the four notes represent a deliberate architectural choice to build the ecosystem layer first, deferring asset-envelope ingestion. Phase 1B must negotiate:
- **Path A (Archiform-First)**: Implement D-NEW-A through D-NEW-E, codegen inversion, action manifest CLI/programmatic/MCP projections. Asset envelopes become S-003 work.
- **Path B (Asset-First)**: Wire `jelly.asset` envelopes through bridge/store/lens. Archiform-foundation as S-003.
- **Path C (Parallel)**: Risk higher scope; attempt both simultaneously (not recommended given single-sprint capacity).

Recommend **Path A** (user's intent reflected in decision notes), but Phase 1B must confirm.

### 2. **Four 2026-04-25 Decision Notes as Primary Input**

The four dated notes are formally structured ADRs with explicit consequences and migration plans:
- **2026-04-25-archiform-registry.md** — 3-layer model, genesis-immutable archiform_fp, aspects.sh federation
- **2026-04-25-json-schema-canonical.md** — Codegen inversion, byte-equivalence gate (critical: regenerated outputs MUST match current)
- **2026-04-25-action-manifest.md** — Universal action contract, projection mappings (CLI/REST/MCP/renderer/programmatic), discipline (no interaction in actions)
- **2026-04-25-wasm-runtime.md** — Wasm for all executable code, WASI + dreamball.* imports, bun-script fallback, content-addressing

**Treat as** `input_quality: existing-prd` (equivalent to numbered FRs). Each note specifies consequences, alternatives considered, and migration strategy. Phase 1B should use these as the backbone of sprint-002 PRD and story generation.

### 3. **Sprint-001 Steering Decision: Ed25519-Only OK for Sprint-002**

Retrospective §Recommended Focus explicitly defers post-quantum dual-sig + secure-key-custody to a later cryptography/security pass. Ed25519-only signing with plaintext 0600 keys is acceptable for sprint-002.

**Implication**: The small lift to migrate dual-sig sentinel call sites in `oracle.ts oracleSignAction` and `store.recordTraversal` to real Ed25519 single signatures should be included in sprint-002 (closes "scope substitution" finding without re-opening dual-sig parameterisation). This is D-NEW-C (partial).

### 4. **Dual-Sig Sentinel Migration — High-Priority Small Lift**

Sprint-001 S4.4 and S5.5 both substituted derived-fp sentinels instead of raising a blocker for signer parameterisation. The four 2026-04-25 notes include action manifest + wasm runtime (which will drive all signature-emitting operations). Sprint-002 should include a small story (S0 candidate) to:

1. Add `signActionEnvelope(keypair_bytes, payload_bytes) → dual_sig_bytes` export to jelly.wasm (leveraging existing ML-DSA-87 verify path)
2. Migrate `oracle.ts oracleSignAction` and `store.recordTraversal` call sites to real Ed25519 single signatures
3. Verify no wire-format change via `zig build smoke` + `scripts/server-smoke.sh`

This closes the sprint-001 "scope substitution" technical debt without re-opening the full dual-sig parameterisation question (post-quantum key custody deferred to security pass).

### 5. **Byte-Equivalence Gate is Critical for Codegen Inversion**

Decision 2026-04-25-json-schema-canonical.md states: "Sprint-002 must include a **byte-equivalence gate**: regenerated outputs from the new JSON-Schema-driven flow MUST byte-match current Zig-generated outputs. Zero wire-format change is the gating constraint for the migration."

**Phase 1B must include** a story (S-codegen-inversion candidate) that:
1. Extracts root JSON Schema from current Zig types
2. Builds JSON Schema → Zig + TS + Valibot + CBOR generators
3. Runs byte-equivalence test against current `src/lib/generated/*` outputs
4. Verifies `zig build smoke` + `scripts/server-smoke.sh` unchanged

This is the main technical risk for the codegen inversion. Phase 1 should flag it as highest-priority.

### 6. **Archiform-Specific Node/Edge Types Now Emerge from Codegen**

Sprint-001 hand-coded `Inscription`, `Room`, `Aqueduct` types in Zig; sprint-002 should generate them from `dreamball/memory-palace@0.1.0` JSON Schema (vendored locally with fp pinned). The store interface (D-007) is unchanged; codegen surface expands to include archiform extensions.

**Phase 1B should plan**:
- S-archiform-pinning: Author `dreamball/memory-palace@0.1.0` JSON Schema; vendor locally; regenerate Memory Palace types across all five runtimes (Zig, TS, Valibot, CBOR, Cypher); verify no wire change.
- This story directly depends on S-codegen-inversion landing first.

### 7. **Action Manifest as Universal Abstraction**

The four 2026-04-25 notes define an action as **pure transaction** (no interactive prompts). CLI, REST, MCP, in-renderer, and programmatic clients are mechanical projections of one manifest. Confirmation, destructiveness, idempotency declared as attributes; projection layers render in their idiom.

**Phase 1B candidates**:
- S-action-manifest-discovery: Extract action specs from current sprint-001 `palace.zig` CLI verbs (palace mint, inscribe, add-room, rename-mythos, move); map to action manifest shape
- S-cli-projection: Generate CLI verb dispatch from action manifest (replaces hand-written palace.zig verbs)
- S-programmatic-projection: Generate TS client calls from action manifest
- S-mcp-projection: Generate MCP tool specs from action manifest

These stories follow *after* JSON Schema canonicalization and archiform-pinning.

### 8. **Wasm Action Host — New Infrastructure**

Wasm is the runtime for action implementations, derivation rules, lenses, policy evaluators. Current jelly.wasm is the *root primitive* host (crypto); archiform wasm modules are guests importing from `dreamball.*` namespace.

**Phase 1B should plan**:
- S-wasm-host: Stand up wasm action host inside jelly CLI; implement `dreamball.*` import namespace (fp, encode_cbor, read_node, emit_action_envelope, now_ms, etc.); set memory limits; test module loading + execution
- This is infrastructure for S-cli-projection and beyond.

### 9. **Codegen Direction Inversion is Load-Bearing**

Current `tools/schema-gen/main.zig` emits TypeScript. Sprint-002 flips it to *consume* `root-2.0.0.json` and emit Zig + TS + Valibot + CBOR. This is the largest architectural change in sprint-002.

**Phase 1B should**:
- Lead with S-codegen-inversion as the first story
- Make byte-equivalence gate the primary acceptance criterion
- Mark S-archiform-pinning, S-cli-projection, and other downstream stories as blocked until S-codegen-inversion ships green

### 10. **No New UX Design Work Expected**

Sprint-001 shipped four shaders, three lenses, and Storybook documentation. Sprint-002 is tools/protocol. The action-manifest discipline (no interactive prompts in actions; confirmation as attribute) is the only UX principle sprint-002 must enforce. Projection layers render confirmation in their idiom (TTY prompts for CLI, dialogs for renderer, MCP elicitation for agents).

**Do not create UX artifacts for Phase 1.** If new UI patterns emerge (streaming result displays, confirmation dialogs), they follow mechanically from the manifest spec and can be designed during story execution.

### 11. **Known Gaps Tracker Should Surface Open Questions**

Retrospective §Open Questions for Sprint-002 Phase 0 lists five unresolved questions:
- Should Zig signer parameterisation land first (given six TODO-CRYPTO sites)?
- Was S5.4 HTML-overlay caught by audit gate or user review only?
- Is "retry-is-idempotent" sufficient for inscription-mirroring partial-write window?
- Should store.ts runtime auto-routing be re-attempted?
- What is operational plan for Qwen3 weights (local script / cache mount / Runpod)?

**Phase 1B should answer what it can; flag blockers for user confirmation.**

### 12. **Active Decisions Registry**

No `decisions/active-decisions.md` currently exists. Step 7b of Phase 0 requires regenerating it from the full decision log.

I have prepared a current-only summary at `.omc/sprint-plan/decisions/active-decisions.md` (will be written below). This file includes:
- All 16 sprint-001 decisions (D-001 through D-016), all `accepted`, with revision flags noted
- The four 2026-04-25 notes as standing decisions pending Phase 1B confirmation of scope
- The eight D-NEW decisions from retrospective as candidates for promotion to numbered ADRs

This registry is the source of truth for sprint-002 architecture context; Phase 1 references it during story planning.

---

