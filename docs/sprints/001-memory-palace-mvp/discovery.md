---
project: memory-palace
sprint: sprint-001
created: 2026-04-21
new_repo: false
input_quality: existing-prd
has_ux_artifacts: false
has_frontend: true
previous_sprint: null
---

## Project Overview

The Memory Palace is a composed application of DreamBall v2 primitives — a palace-as-topology made of Field-typed DreamBalls where each room nests the six v2 types, with an Agent-typed oracle at the zero point, signed timeline DAG, hash-linked mythos chain, Vril-carrying aqueducts, and a 3-lens rendering pack (palace, room, inscription). The MVP tier implements core palace mechanics: minting, room/inscription operations, timeline tracking, vector-indexed knowledge graphs via LadybugDB, and the omnispherical + room + inscription lens pack for rendering. The palace is the first end-to-end demonstration that the v2 primitives add up to something a person can walk around inside.

## Input Analysis

**Input provided**: `docs/products/memory-palace/prd.md` (format_version 2026-04-19, updated 2026-04-21 with Phase 0 close-out ADRs).

**Quality**: `existing-prd`. The PRD contains:
- 8 user journeys (J1–J6, plus activation and reflection flows)
- 4 personas (P0 Wayfarer, P1 Guest, P2 Oracle host, P3 Guild scribe; P4 reused from v2)
- Numbered functional requirements (FR60–FR98) with scope tiers (MVP/Growth/Vision)
- 9 new envelope types (layout, timeline, aqueduct, element-tag, trust-observation, mythos, archiform, plus two Vision-tier)
- 15 NFRs covering rendering, resilience, and operational concerns
- Section 6 (Architecture & Implementation) with runtime kernel spec, knowledge graph design, and Vril flow computation

**Scope for sprint-001**: MVP tier only — specifically FR60 (+60a–d), FR61–65, FR69–72, FR74–77, FR80–82, FR88–90, FR93–95, NFR10–15. Growth and Vision FRs are explicitly out of scope.

**Completeness**: No gaps for MVP execution. Phase 0 ADRs (2026-04-21) have closed three open questions:
1. Dream-field embedding model (ADR 2026-04-21-dream-field-embedding.md) — palace embeds *in* dream field as substrate, does not become one.
2. Graph+vector store selection (ADR 2026-04-21-ladybugdb-selection.md) — LadybugDB for server, kuzu-wasm@0.11.3 for browser (IDBFS persistence pattern validated).
3. NextGraph CRDT compatibility (ADR 2026-04-21-nextgraph-crdt-review.md) — timeline wire format already CRDT-compatible; no protocol change needed.

## New Repo Detection

**Classification**: `new_repo: false` — existing, mature codebase.

**Evidence**:
- 48 `.zig` source files in `src/`
- Build manifests present: `build.zig` (Zig 0.16), `package.json` (Bun), `build.zig.zon`
- Source directories: `src/` (Zig core), `src/lib/` (components, lenses, backend, generated, wasm), `src/cli/` (12 command files), `jelly-server/`, `src/routes/` (SvelteKit showcase)
- CI/CD: `.github/workflows/ci.yml` (gated builds, smoke tests)
- Mature patterns: WASM cross-runtime invariant, Ed25519+ML-DSA-87 hybrid signatures, dCBOR wire format, Threlte/WebGL renderer

## Existing Codebase Inventory

### Tech Stack

**Zig Core** (v0.16.0):
- Protocol encoding/decoding (dCBOR via zbor module)
- Cryptography: Ed25519 (std.crypto.sign), ML-DSA-87 (vendored liboqs 0.13.0)
- CBOR schema generation (`tools/schema-gen/main.zig`)
- CLI toolchain (`jelly` binary)
- WASM module compilation (`jelly.wasm` ≤150 KB)

**TypeScript/Bun Runtime**:
- SvelteKit 2.57.0 (frontend, showcase app, type-safe routes)
- Svelte 5.55.2 (component lib, 5 lenses: cubemap, cylindrical, omnispherical, flat, thumbnail)
- Threlte 8.5.9 (Three.js 0.184.0 WebGL renderer)
- Vitest 4.1.3 (unit + browser tests via Playwright)
- Storybook 10.3.5 (component isolation)
- Valibot 1.3.1 (schema validation, auto-generated from Zig)
- Elysia 1.4.28 + Eden (jelly-server HTTP API, type-safe client)
- LadybugDB (@ladybugdb/core 0.15.3, kuzu-wasm@0.11.3 browser fallback)

**Dependencies**:
- @elysiajs/cors, @elysiajs/eden, @elysiajs/swagger (jelly-server HTTP)
- @valibot/to-json-schema (schema generation)
- Three.js ecosystem (Threlte, @types/three, PlayCanvas 2.18.0)

### Project Structure

```
/Dreamball/
├── build.zig                    # Zig build orchestration (native, WASM, schemagen, smoke tests)
├── build.zig.zon               # Zig dependency manifest (zbor)
├── package.json                # Bun workspace + TS/Svelte deps
├── src/                         # Zig protocol core (48 .zig files)
│   ├── *.zig                   # Protocol envelope, crypto, CBOR, JSON, CLI dispatch
│   ├── cli/                    # 12 jelly commands (mint, grow, sign, seal, verify, show, etc.)
│   └── lib/                    # TypeScript + WASM output layer
│       ├── components/         # Svelte components (not yet palace-specific)
│       ├── lenses/             # 5 rendering lenses (omnispherical primary for palace)
│       ├── backend/            # HTTP + Mock backends
│       ├── generated/          # Auto-generated TS types + Valibot schemas
│       ├── wasm/               # jelly.wasm binary + JS bindings
│       ├── playcanvas/         # PlayCanvas engine shim (experimental)
│       └── splat/              # Gaussian splatting renderer (experimental)
├── src/routes/                 # SvelteKit showcase routes (not palace-specific yet)
├── jelly-server/               # Bun + Elysia HTTP server
│   ├── src/index.ts            # Server entry
│   ├── src/routes/             # HTTP endpoints
│   └── tsconfig.json
├── scripts/                    # Integration test gates (cli-smoke.sh, server-smoke.sh, e2e-cryptography.sh)
├── tests/                      # E2E test harness
├── docs/                       # Architecture, protocol, vision, decisions, research
│   ├── ARCHITECTURE.md         # The map (one-slide, invariant, runtime, crypto tiers, ADRs)
│   ├── PROTOCOL.md             # Wire format (sections 1–12, v2.1 final)
│   ├── VISION.md               # Philosophy (look/feel/act, stages, graph, form-independence)
│   ├── known-gaps.md           # Deferred items with tracking (PQ verify, zstd, chained recrypt)
│   ├── products/               # Product briefs (dreamball-v2/prd.md, memory-palace/prd.md)
│   ├── decisions/              # ADRs (2026-04-21: dream-field, ladybugdb, nextgraph)
│   ├── research/               # Spike results (graph-db options, CRDT options)
│   └── sprints/                # Sprint planning (001-memory-palace-mvp/)
├── tools/                      # Build tooling
│   └── schema-gen/main.zig     # TypeScript + Valibot codegen from Zig core
├── vendor/                     # Vendored deps (liboqs 0.13.0 ML-DSA-87)
└── .github/workflows/ci.yml    # CI gates (zig build, WASM, smoke tests, Storybook)
```

### Existing Patterns

**Wire Format Authority**: Zig protocol core (`src/*.zig`) is the single source of truth. All TypeScript envelopes/schemas are generated via `zig build schemagen` → `src/lib/generated/*.ts`.

**Cross-Runtime Invariant**: Browser and server load the same `jelly.wasm` binary. No platform-specific conditional code paths. One CBOR bug is fixed in one place (Zig).

**Cryptography Tiers**:
- Tier 1 (default): Ed25519 only (native in Zig, WASM, browser)
- Tier 2 (production): Ed25519 + ML-DSA-87 hybrid (native CLI via liboqs, server subprocesses CLI, browser stays Ed25519-only for bundle size)
- Tier 3 (future): recrypt-server proxy-recryption for Guild keyspace

**Rendering**: Lens-based composable views (cubemap, cylindrical, omnispherical, flat, thumbnail). Each lens is a Svelte component that reads the same `jelly.wasm`-decoded envelope. New lenses (palace, room, inscription) extend the pack without refactoring existing ones.

**API Style**: 
- CLI: Zig binary with subcommand dispatch (`jelly mint`, `jelly seal`, `jelly verify`, etc.)
- HTTP: Elysia routes (`jelly-server/src/routes/`) with type-safe Eden client (`treaty<App>`)
- WASM: Exported functions (`mintDreamBall`, `growDreamBall`, `verifyJelly`, etc.)
- MCP (stdio): Bun server wrapping CLI commands (not yet palace-specific)

**Test Framework**: 
- Zig inline tests (51+ passing in `src/*.zig` test blocks)
- Vitest + Playwright for Svelte + TypeScript
- Storybook play tests
- Bash integration gates (`cli-smoke.sh`, `server-smoke.sh`, `e2e-cryptography.sh`)

**Patterns Specific to Memory Palace** (to be implemented):
- Timeline DAG with Merkle-rooted signed actions
- Aqueduct flow model (resistance, capacitance, conductance, phase)
- Knowledge graph via LadybugDB Cypher queries + vector index
- Mythos chain (genesis immutable, canonical append-only, poetic per-author)
- Resonance kernel (vector-matching against inscriptions, K-NN salience)

### Module Boundaries

1. **Protocol Core** (`src/*.zig`):
   - `envelope.zig`, `envelope_v2.zig` — v1/v2 envelope definitions
   - `cbor.zig` — CBOR encoding/decoding
   - `json.zig` — JSON export/import
   - `fingerprint.zig`, `graph.zig`, `key_file.zig` — identity, containment, key management
   - `ml_dsa.zig` — hybrid signature wrappers

2. **CLI** (`src/cli/*.zig`):
   - `dispatch.zig` — command routing
   - `mint.zig` — DreamBall genesis
   - `grow.zig` — revision minting
   - `seal_relic.zig`, `seal.zig` — DragonBall wrapping
   - `sign.zig`, `join_guild.zig` — signature operations
   - `transmit.zig` — transmission (v2.1 added)
   - `show.zig`, `export_json.zig`, `import_json.zig` — I/O operations

3. **WASM Module** (`src/lib/wasm/jelly.wasm` + `src/lib/wasm/index.ts`):
   - Exported: `mintDreamBall`, `growDreamBall`, `verifyJelly`, `joinGuildWasm`, `sealRelix` (subset)
   - Imports: `env.getRandomBytes` (host-supplied randomness)

4. **Components** (`src/lib/components/`):
   - Generic Svelte components (not yet palace-specific; to be extended)

5. **Lenses** (`src/lib/lenses/`):
   - `cubemap`, `cylindrical`, `omnispherical`, `flat`, `thumbnail` (existing)
   - **New for palace**: `palace` (omnispherical palace view), `room` (interior layout), `inscription` (text on mesh)

6. **Backend** (`src/lib/backend/`):
   - `HttpBackend.ts` — talks to jelly-server via Eden
   - `MockBackend.ts` — in-memory stubs for Storybook/Vitest

7. **jelly-server** (`jelly-server/src/`):
   - HTTP routes wrapping CLI + WASM
   - Eden type-safe client definitions
   - Swagger docs auto-generated from Elysia routes

8. **Type Generation** (`tools/schema-gen/main.zig`):
   - Reads Zig envelope definitions
   - Outputs `src/lib/generated/types.ts` (TypeScript interfaces)
   - Outputs `src/lib/generated/schemas.ts` (Valibot schema validators)

## Available Artifacts

- `/Users/dukejones/work/Identikey/Dreamball/docs/products/memory-palace/prd.md` — Memory Palace PRD (scope-tiered, MVP/Growth/Vision, 98 FRs)
- `/Users/dukejones/work/Identikey/Dreamball/docs/ARCHITECTURE.md` — Runtime map + crypto tiers + ADRs
- `/Users/dukejones/work/Identikey/Dreamball/docs/PROTOCOL.md` — Wire format (dCBOR, v2.1 final, sections 1–12)
- `/Users/dukejones/work/Identikey/Dreamball/docs/VISION.md` — Philosophical foundation (look/feel/act, fractal, form-independence)
- `/Users/dukejones/work/Identikey/Dreamball/docs/known-gaps.md` — Deferred items (PQ verify, zstd, chained recrypt, etc.)
- `/Users/dukejones/work/Identikey/Dreamball/docs/decisions/2026-04-21-dream-field-embedding.md` — ADR: dream field as omnipresent substrate
- `/Users/dukejones/work/Identikey/Dreamball/docs/decisions/2026-04-21-ladybugdb-selection.md` — ADR: LadybugDB + kuzu-wasm fallback
- `/Users/dukejones/work/Identikey/Dreamball/docs/decisions/2026-04-21-nextgraph-crdt-review.md` — ADR: CRDT compatibility verified
- `/Users/dukejones/work/Identikey/Dreamball/docs/decisions/2026-04-20-terminology-rename.md` — ADR: Phase 0 terminology sweep
- `/Users/dukejones/work/Identikey/Dreamball/docs/research/graph-db-options/synthesis.md` — Graph DB spike (Kuzu → LadybugDB reasoning)
- `/Users/dukejones/work/Identikey/Dreamball/.omc/sprint-plan/sprint-001/phase-state.json` — Sprint state (Phase 0 active)

## UX Status

**has_ux_artifacts: false** (by design, per user flag `--skip-ux`).

Rationale: NFR14 ("The palace renderer shall draw Vril aqueducts as flowing, pulsing, living conduits, not inert geometry") and VISION §15 (mythos-as-keystone, Vril-as-flowing-light, omnispherical onion layers, eight lenses) already lock the aesthetic direction. User has explicitly scoped visual design out of sprint-001 intake to focus on mechanics + MVP prototype.

**Frontend status**: Present and mature. Svelte 5 + Threlte + WebGL engine already in place. Three new lenses (palace, room, inscription) will plug into the existing lens pack; no new rendering infrastructure is needed.

## Recommendations

### For Phase 1 (Requirements → Architecture & Stories)

1. **Input is complete and locked.** MVP FRs (FR60–65, 69–77, 80–82, 88–90, 93–95, NFR10–15) are numbered, acceptance-criteriaed, and scope-tiered. No PRD expansion needed. Phase 0 ADRs have closed all "lock in Phase 0" open questions. Phase 1 analyst agent should proceed directly to story enrichment (no requirements expansion loop required).

2. **Three architectural pillars are decided and locked** — do not re-open:
   - **Storage**: LadybugDB (@ladybugdb/core) for server, kuzu-wasm@0.11.3 for browser (IDBFS persistence). Wrapper abstraction at `src/memory-palace/store.ts` (not yet written).
   - **Dream-field model**: Palace embeds *in* dream field as substrate, not *becomes* one. Rendering hook separates ambient-dream-field pass from outermost Field envelope.
   - **CRDT compatibility**: Timeline DAG wire format already CRDT-commutative. NextGraph interop verified; no protocol change needed for MVP.

3. **UX spec is locked, not in scope for sprint-001.** VISION §15 + NFR14 form the aesthetic baseline. Do not request Figma/wireframe work. Three new lenses (palace, room, inscription) are engineering tasks, not UX design tasks.

4. **CLI baseline is stable.** The `jelly` command family is mature (`mint`, `grow`, `seal`, `sign`, `verify`, `show`, `export-json`, `import-json`, `join-guild`, `seal-relic`, `transmit`). Palace commands (FR60–65, 88–90) extend this family; no refactoring of existing command structure is needed.

5. **WASM/HTTP API boundary is set.** The server-authoritative model (from 2026-04-21 LadybugDB ADR step 2b recommendation) means:
   - jelly-server owns the persistent LadybugDB graph (`@ladybugdb/core`)
   - Browser keeps an ephemeral in-memory LadybugDB seeded from server snapshots
   - Frontend queries server over HTTP/WebSocket for fresh data
   - Aqueduct rendering reads Vril properties computed from the server graph

### For Phase 4 (Story Enrichment → Story Cards)

1. **No UX artifact input needed.** Palace, room, and inscription lenses (FR74–77) are rendering engineering tasks mapped directly from PRD §6.1–6.3. Storybook play tests will serve as the acceptance test surface; no separate Figma/design review gate.

2. **Lens pack is extensible.** New lenses follow the existing pattern (Svelte component, reads `jelly.wasm`-decoded envelope, exports view component). Story cards can reference existing lens implementations as reference.

3. **Knowledge graph + vector index are co-located.** The thin wrapper (`src/memory-palace/store.ts`) will surface a unified Cypher query interface; stories should not split "graph query" from "vector search" — they compose.

### For Phase 5 (Story Execution)

1. **Story sequencing matters.** Recommended grouping:
   - **Epic 1**: Core CLI commands (FR60–65, 88) — `jelly palace mint`, `add-room`, `inscribe`, `show`, `verify`
   - **Epic 2**: Oracle + knowledge graph (FR69–71, 80–82, 93–95) — agent bootstrap, LadybugDB integration, archiform registry
   - **Epic 3**: Timeline + aqueducts (FR64, 77, 94) — signed DAG, flow computation
   - **Epic 4**: Rendering (FR74–77) — palace, room, inscription lenses + Threlte integration
   - **Epic 5**: Mythos chain (FR60a–d, 72) — genesis immutable, rename, oracle reflection (FR72 is Growth; defer)

2. **LadybugDB integration is foundational.** Stories depending on FR80–82 (vector store setup) should land before any oracle or resonance kernel work.

3. **Test gates are in place.** Extend `scripts/cli-smoke.sh` with palace-specific commands; extend `tests/e2e-cryptography.sh` if needed for multi-signature timeline actions. Storybook play tests will cover rendering lenses.

### Cross-Sprint Continuity

1. **Phase 0 ADRs carry into Phase 1 as decided constraints.** Do not re-open graph-DB selection, dream-field embedding, or CRDT semantics. If future work requires a revision (e.g., LadybugDB release cadence stalls), that decision goes into a new ADR, not into the MVP story backlog.

2. **Known gaps (docs/known-gaps.md) stay stable.** ML-DSA-87 browser verification, zstd compression, and chained proxy-recryption remain deferred post-MVP. This sprint's story cards should not create secondary tasks trying to close them.

3. **Quarterly review gate on LadybugDB.** Per ADR 2026-04-21-ladybugdb-selection.md, if LadybugDB release cadence stalls >2 months without explanation, re-open `docs/research/graph-db-options/synthesis.md` and consider a swap. This is not a sprint-001 concern — document it in the release checklist instead.

---

## Summary

**Sprint-001 is fully scoped and ready for Phase 1.** The PRD is complete (existing-prd quality), the codebase is mature and instrumented, three architectural pillars are locked (storage, dream-field model, CRDT compatibility), and the MVP tier (24 FRs + 6 NFRs) is clearly delineated from Growth/Vision work. No PRD expansion, no UX artifact creation, and no architectural re-thinking is needed before proceeding to story enrichment.

The Memory Palace MVP will be the first end-to-end demonstration that DreamBall v2 primitives compose into a coherent experience. Phase 1 should focus on translating the 24 MVP FRs into 5–6 epics grouped by technical dependency and story sequencing the epics for a clean, testable execution flow.
