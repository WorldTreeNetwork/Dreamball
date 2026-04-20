# 2026-04-21 — LadybugDB selected as Memory Palace graph+vector store

## Status

Accepted. Supersedes the "Kuzu embedded graph database" reference in
earlier drafts of `docs/products/memory-palace/prd.md`.

## Context

Upstream KuzuDB was archived on 2025-10-10 (final release v0.11.3)
following Kùzu Inc.'s Apple acqui-hire. The Memory Palace composition
(`docs/products/memory-palace/prd.md` §6.2) requires a local-first,
embeddable property-graph store with Cypher, a vector index, WASM
reachability, and an MIT-style licence — the exact niche Kuzu
occupied. A replacement was needed before any §6 or §7 code work.

Full research is in
`docs/research/graph-db-options/synthesis.md` and
`docs/research/graph-db-options/summary.json`.

## Decision

**Primary:** LadybugDB (`@ladybugdb/core`, Rust crate `lbug`, storage
files `.lbug`). It is the only Kuzu-lineage fork with sustained
momentum (9 releases Nov 2025 – Apr 2026, v0.15.3 landed
2026-04-01), one-for-one API and storage compatibility with Kuzu
v0.11.3, MIT-licensed, with an actively maintained `vector`
extension (disk-HNSW, SIMD via `simsimd`, cosine/L2/L2sq/dot-product
over `FLOAT[N]` / `DOUBLE[N]` arrays) that closes the PRD §9 vector
store question without a sidecar.

**No pre-committed fallback.** If LadybugDB ever stops being the
right pick, we re-open the graph-DB research
(`docs/research/graph-db-options/synthesis.md`, which still
enumerates DuckDB+duckpgq+VSS, vendor-frozen Kuzu v0.11.3, and the
other reviewed candidates) and swap one file. Pre-committing to a
Plan B today would be cargo-cult: Kuzu is dead as a live choice, we
don't need to keep it on life support as insurance; DuckDB's
graph-query story isn't cohesive enough in 2026 to warrant
pre-building a fallback path we don't expect to take.

Candidates ruled out: Bighorn (dormant), RyuGraph (stalled),
CozoDB (effectively abandoned), Oxigraph (RDF-only), SurrealDB
(BUSL 1.1), HelixDB (not embedded + AGPL), IndraDB (no bindings,
no vector), TerminusDB (not embedded), Grafeo (AI-generated beta).

NextGraph is **not** a graph-DB candidate but has converged on the
same cryptographic substrate (Blake3 + ChaCha20 + Ed25519 + CBOR +
signed DAG + local-first); the cross-reference is captured in PRD
§6.2.2 so FR68 / §6.4 do not accidentally reinvent incompatible
CRDT semantics.

## Consequences

- PRD §6.2 updated to name LadybugDB throughout; storage paths are
  `.memory-palace/lbug/`; FR80 reflects the switch.
- PRD §9 closes the vector-store open question — vectors live in
  LadybugDB via the bundled `vector` extension.
- A thin wrapper `src/memory-palace/store.ts` (not yet written) will
  be the only site importing `@ladybugdb/core`, so a future swap to
  any other graph store touches one file.
- Quarterly review gate: if LadybugDB release cadence stalls for
  >2 months without explanation, re-open the graph-DB research
  (`docs/research/graph-db-options/synthesis.md`) — no
  pre-committed fallback.

## Phase 0 validation — results

### Step 1: Bun + `@ladybugdb/core` napi smoke test

**Result: conditional pass.**

Test (`/tmp/lbug-bun-smoke/smoke.js`, Bun v1.3.3, macOS arm64):
- `require('@ladybugdb/core')` loads cleanly; exports
  `Database`, `Connection`, `PreparedStatement`, `QueryResult`,
  `VERSION = '0.15.3'`, `STORAGE_VERSION = 40`.
- `new Database('./x.lbug')` + `new Connection(db)` succeed.
- `await conn.query('RETURN 1 AS x;')` → `[{x:1}]`.
- Node-table create + insert + MATCH query round-trips data:
  `[{id:"a",body:"hello"}]`.
- Storage files (`x.lbug`, `x.lbug.wal`) are written to disk and
  survive process restart.
- Process exits with status 0 after `SMOKE_PASS` prints.
- **Initial observation:** Bun panics
  (`Segmentation fault at address 0x8`) during process *teardown*
  after userland has completed and the exit code is already 0.
- **Isolation:** under Node v24.6.0 (same script as `.cjs`) the
  panic does not occur. The crash is in Bun's atexit napi
  finalizer walk over still-open native handles, not in
  LadybugDB itself.
- **Clean mitigations (both independently suppress the crash):**
  1. Call `process.exit(0)` at the end of `main()` — skips Bun's
     napi finalizer pass.
  2. Explicitly close every opened handle
     (`await qr.close(); await conn.close(); await db.close();`)
     before the function returns — Bun's finalizer then walks
     already-closed handles and does nothing.

**Interpretation.** Native `@ladybugdb/core` is viable under Bun
with either mitigation applied; the crash path is fully avoidable
without leaving `@ladybugdb/core` for `@ladybugdb/wasm-core`. Our
posture:

1. The thin wrapper `src/memory-palace/store.ts` will wrap every
   `QueryResult` so that callers never forget the three `close()`
   calls — we encode mitigation (2) into the API surface. Pattern:
   ```ts
   async function query<T>(cypher: string, params?: unknown): Promise<T[]> {
     const qr = await conn.query(cypher, params);
     try { return await qr.getAll() as T[]; }
     finally { await qr.close(); }
   }
   ```
   Connection and Database are closed via `defer`/`try-finally`
   at the wrapper's top-level teardown or process signal handler.
2. The `jelly` CLI additionally calls `process.exit(0)` on
   successful completion (mitigation 1) as a belt-and-braces
   measure, since the CLI process lifetime is always short.
3. File a minimal reproducer upstream against Bun (napi finalizer
   over non-explicitly-closed handles) so the belt-and-braces
   becomes unnecessary in a future Bun release.
4. `@ladybugdb/wasm-core` remains the escape hatch for any
   context where we cannot reliably run explicit `close()`
   (third-party code paths, crash paths, test harness teardown),
   per PRD §9.

### Step 2: WASM + OPFS browser spike — deferred

The only remaining Phase 0 item that is still load-bearing:
validate `@ladybugdb/wasm-core` + OPFS in the browser target
(Vite page, round-trip a node/edge, confirm the `.lbug` survives a
reload). ~2 hours. The earlier proposed steps 3–5 (frozen Kuzu
vendor prep, DuckDB Plan-B reference spike, `.lbug`↔`.kz`
cross-read check) have been cut — they exist only to pre-build a
fallback we don't expect to need, and if we ever do need one we
re-open the research rather than carrying pre-decided infrastructure
as dead weight.

## References

- Research synthesis:
  `docs/research/graph-db-options/synthesis.md`
- Summary JSON:
  `docs/research/graph-db-options/summary.json`
- LadybugDB vector-extension effort-sizing:
  `docs/research/graph-db-options/hypotheses/h-ladybug-vector-effort/findings.md`
- PRD §6.2, §6.2.1, §6.2.2, §9, FR80:
  `docs/products/memory-palace/prd.md`
