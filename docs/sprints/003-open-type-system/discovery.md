---
project: dreamball
sprint: sprint-003
created: 2026-06-27
new_repo: false
input_quality: existing-prd
has_ux_artifacts: false
has_frontend: true
previous_sprint: sprint-002
---

## Project Overview

DreamBall is a Zig-core protocol compiled to a ~178 KB WASM binary (one binary,
browser + Bun) for verifiable, typed-CBOR "DreamBall" containers — identity,
avatars, agents, fields, and the Memory Palace. This sprint opens the **type
system** to consumers: a generic open-kind, typed-body action envelope (+ native
HLC + `parent_hashes`) so the first real external consumer (World-Tree `web/`)
can carry their own typed, signed state as first-class DreamBalls without
hand-rolling CBOR. Source: validated PRD `docs/prd-open-type-system-mvp.md`,
seeded from `docs/VISION.md §17`.

## Input Analysis

Input is an **existing-prd**: `docs/prd-open-type-system-mvp.md`, FR-numbered
(FR1–FR17), tier-tagged, with NFRs, success metrics, scope boundaries, open
questions, and existing-system context. Independently critic-validated this
session (0 blockers). Phase 1 is therefore **light-touch** — re-express the PRD
into the requirements schema, add technical constraints from the architecture
context, and surface the embedded HIGH/CRITICAL decisions for Phase 2A. No gaps
block planning; the open design forks (extend `ball.action` vs new type;
open-kind wire format; envelope_v2→WASM linkage) are explicit Open Questions
routed to Phase 2A.

## New Repo Detection

Existing codebase. Zig (0.16.0) protocol core + Bun/TS library + Svelte
showcase; hundreds of source files, multiple build manifests (`build.zig`,
`package.json`). `new_repo: false`.

## Existing Codebase Inventory

### Tech Stack
- **Zig 0.16.0** — protocol core, CBOR codec, crypto, WASM target (`src/*.zig`,
  `build.zig`). zbor (CBOR), vendored ML-DSA-87.
- **Bun + TypeScript** — library, generated types/schemas, loader, server.
- **Svelte 5 / SvelteKit** — showcase/components (frontend present but not in
  this sprint's scope).
- **Valibot** — generated runtime validation. **Vitest** — TS tests.
- **Elysia** — dreamball-server (Bun) on :9808.

### Project Structure
- `src/*.zig` — protocol core: `protocol.zig`, `protocol_v2.zig` (v2 types),
  `envelope.zig` / `envelope_v2.zig` (CBOR encode/decode), `dcbor.zig`
  (canonical determinism), `wasm_main.zig` (WASM exports), `ml_dsa.zig`,
  `golden.zig` (golden vectors).
- `src/lib/` — TS: `wasm/loader.ts` (WASM wrapper), `generated/*` (types,
  Valibot schemas, cbor.ts), `parse.ts`, `memory-palace/`.
- `tools/schema-gen/` — codegen (`zig build schemagen`).
- `schemas/` — `root-2.0.0.json`, `memory-palace-0.1.0.json` (generated artifacts).
- `scripts/` — `cli-smoke.sh`, `server-smoke.sh`; `tests/e2e-cryptography.sh`.

### Existing Patterns
- **One binary, two runtimes**: the same `dreamball.wasm` loads in browser + Bun;
  single host seam `env.getRandomBytes`.
- **Packed-u64 WASM ABI**: authoring exports return `(ptr<<32)|len`, `0` on error,
  diagnostic via `resultErrPtr/Len`; `mintDreamBall` uses a `lastSecret`
  side-channel. Documented in `docs/abi/wasm-authoring-abi.md`.
- **Canonical dCBOR**: length-first map-key ordering + shortest-int (`dcbor.zig:44`),
  `assertCanonical` on decode; golden vectors in `golden.zig`.
- **Zig-canonical codegen**: Zig types → generated TS/Valibot/cbor.ts/JSON-Schema
  (the `@typeInfo` comptime generator is NOT built yet — generated bodies are
  hand-maintained against a byte-equivalence gate).
- Crypto: Ed25519 (browser/Bun authoring) + ML-DSA-87 (verify in WASM, sign
  CLI-side).
- Test: inline Zig `test "…"` blocks + `zig build test`/`smoke`; Vitest; smoke shells.

### Module Boundaries
Protocol core (Zig) · WASM exports (`wasm_main.zig`) · TS loader/library
(`src/lib`) · Memory Palace (`src/lib/memory-palace`, currently monolithic) ·
codegen (`tools/schema-gen`) · dreamball-server (Elysia).

## Available Artifacts
- `docs/prd-open-type-system-mvp.md` — validated PRD (source for this sprint).
- `docs/VISION.md §17` — strategic frame (the open type system).
- `docs/abi/wasm-authoring-abi.md` — consumer-facing WASM ABI note (this session).
- `docs/decisions/2026-06-25-zig-canonical-supersedes-json-schema.md` — governing ADR.
- Prior sprints: `docs/sprints/001-memory-palace-mvp/`, `002-archiform-foundation/`.

## UX Status
Frontend exists (Svelte showcase) but **UX is not applicable to this sprint** —
the work is protocol / wire-format / WASM-ABI, with no new UI surface. Phase 1.5
(UX design) will be skipped.

## Previous Sprint Intelligence (sprint N>1)

### Key Learnings Carried Forward
- **D-018 (JSON-Schema-canonical) is SUPERSEDED** by the 2026-06-25 Zig-canonical
  ADR. Zig types are now the single canonical source; JSON Schema is a *generated
  artifact*. Do **not** hand-author JSON Schema or add `x-cbor`/`x-zig` extension
  keys (the retired authoring path). This directly governs FR1–FR2.
- **D-023**: `signActionEnvelope` is the Ed25519 signing seam; it is a **raw byte
  signer**, not an envelope builder (confirmed this session). PQ dual-sig deferred.
- **D-019 (Action Manifest)**: the universal action contract — relevant to whether
  the generic op envelope extends `ball.action` or introduces a new type.
- **D-007**: store wrapper API = domain verbs + narrow raw escape-hatch — the
  "typed API over a thin primitive" pattern this sprint extends to authoring.
- The `@typeInfo` Zig→targets generator (beads `Dreamball-m97.2`) is **not built**;
  downstream artifacts are hand-propagated against a byte-equivalence gate — a
  real maintenance-burden constraint for any new type this sprint.

### Active Decisions Carried Forward
D-007 (store wrapper API), D-017 (archiform registry), D-019 (action manifest),
D-023 (Ed25519 sign export) — held. D-018 (JSON-Schema-canonical) — **superseded**
by 2026-06-25 Zig-canonical ADR. Full log: `.omc/sprint-plan/decisions/`.

## Recommendations
- Input is existing-prd → Phase 1 is light-touch re-expression; do not re-derive FRs.
- Skip Phase 1.5 (UX) — no UI surface this sprint.
- Phase 2A is the load-bearing phase: resolve the three Open Questions (extend
  `ball.action` vs new generic type; open-kind wire representation; how/whether to
  link `envelope_v2` into the WASM and the HLC spec from `Dreamball-fch`). Use an
  independent architect pass here.
- Governing constraint for every FR touching types/codegen: **Zig-canonical** —
  edit Zig structs, propagate to generated targets by hand until m97.2 lands.
