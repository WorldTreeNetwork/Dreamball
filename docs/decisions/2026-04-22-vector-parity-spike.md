# 2026-04-22 — Vector parity spike outcome (D-015 R2 gate, S2.1)

**Decision area**: Cross-runtime K-NN vector index parity  
**Sprint**: sprint-001 (memory-palace MVP)  
**Story**: S2.1 — Cross-runtime vector-parity spike  
**Outcome**: PASS — local kuzu-wasm kNN is viable; HTTP fallback not needed for MVP

---

## Why this spike existed

D-015 identified risk R2: "LadybugDB vector-extension graph-join parity across runtimes unverified."
The memory palace MVP (Epic 2) needs K-NN queries to work both on the server
(`@ladybugdb/core` native napi) and in the browser (`kuzu-wasm@0.11.3` WASM).

NFR11 requires offline-capable local-first K-NN — if the browser WASM couldn't produce
the same top-K as the server, the fallback would be server-only K-NN over HTTP, breaking
the offline contract for every palace interaction that needs "find related inscriptions."

Epic 6 (embedding + retrieval routes) and S2.3 (browser store adapter) both gate their
K-NN code path on this outcome: if PASS, they use local WASM; if HARD BLOCK, Epic 6 adds
a `/kNN` HTTP route and S2.3 delegates to it.

---

## What was measured

Fixture: 100 unit-normalised 256-dimensional Float32 vectors, LCG seed=42.
Query vector: LCG seed=43. Same generator on both runtimes.
Cypher: `CALL QUERY_VECTOR_INDEX('Inscription', 'inscription_emb', $q, 10)`.

| Runtime | Library | Top-10 fps |
|---------|---------|------------|
| Server (Bun + vitest) | @ladybugdb/core 0.15.3 | v79, v18, v31, v32, v1, v28, v33, v66, v44, v60 |
| Browser (Playwright Chromium) | kuzu-wasm 0.11.3 | v79, v18, v31, v32, v1, v28, v33, v66, v44, v60 |

**Set-equal**: YES — identical fps in identical rank order.
**Max |Δ| cosine distance**: 0.000048 — far below the 0.1 acceptance threshold from D-015.

Outcome class per D-015 §Decision: **PASS** (option 2 — ordinal top-K with ≤10% variance).

---

## Why the numbers are this close

Both @ladybugdb/core and kuzu-wasm@0.11.3 are built from the same KuzuDB C++ codebase
(LadybugDB is a fork of KuzuDB). The WASM build uses the same HNSW vector index
implementation as the native build. With unit-normalised vectors and an in-memory index
of only 100 rows, there is no numerical divergence path — both runtimes traverse the
exact same HNSW graph structure. The 0.000048 delta on v79 is floating-point rounding
from the Float32 cast in the Cypher literal vs the native Float32Array path, not an
algorithmic difference.

At production scale (10k+ inscriptions) some HNSW approximation divergence is expected,
but D-015 §Decision already accepts set-equality as the contract, not byte-identity.

---

## API differences discovered during the spike

These are load-bearing for S2.3 implementors:

1. **Extension loading**: `@ladybugdb/core` requires `INSTALL VECTOR; LOAD EXTENSION VECTOR`
   before `CREATE_VECTOR_INDEX`. `kuzu-wasm` bundles the extension — no load step needed.
2. **QueryResult API**: `@ladybugdb/core` exposes `qr.getAll()`. `kuzu-wasm` browser async
   build exposes `qr.getAllObjects()`. The `nodejs` variant also uses `getAllObjects()`.
3. **Worker path**: `kuzu.setWorkerPath(url)` must be called before first DB operation.
   The worker JS must be served same-origin (S2.3 AC1: `bun run bootstrap` copies it to `static/`).
4. **WASM init in non-browser environments**: The default and nodejs kuzu-wasm builds crash
   with `Aborted(Assertion failed)` under Bun's worker-thread implementation. Only the
   Playwright Chromium browser environment is confirmed stable for the async build.

---

## Consequences for downstream stories

- **S2.3** (browser store adapter): implement `kNN()` using local `QUERY_VECTOR_INDEX`.
  No HTTP fallback path needed. S2.3 AC7 applies (local kNN confirmed by this spike).
- **S6.3** (Epic 6 embedding routes): no `/kNN` HTTP endpoint required for MVP.
  Chromium-only validation per OQ3/R1 is sufficient for the MVP local-first contract.
- **D-015 constraint**: no Epic story may assert byte-identical vector distances across
  runtimes. All K-NN assertions remain set-membership assertions (same fps returned).
- **NFR11** remains fully satisfied: offline palace K-NN works without a server round-trip
  in Chromium (the MVP target browser per OQ3).

---

## Artefacts

- `src/memory-palace/fixtures/knn-parity.ts` — deterministic LCG fixture generator; SHA-256 pin
- `src/memory-palace/parity.test.ts` — vitest: AC1 (fixture pin), AC2 (server ground truth), AC4/AC5 paths
- `tests/parity-browser.e2e.ts` — Playwright: AC3 (browser parity), outcome classification, addendum writer
- `tests/parity-fixture/` — static HTML harness + pre-generated fixture data (270 KB)
- `playwright.config.ts` — Playwright config with inline static webServer
- `docs/sprints/001-memory-palace-mvp/addenda/S2.1-parity-result.md` — measured numbers
