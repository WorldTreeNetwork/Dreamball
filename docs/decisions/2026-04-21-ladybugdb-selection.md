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

### Step 2a: WASM browser spike (`@ladybugdb/wasm-core`) — partial pass with persistence gap

**Runtime: PASS.** `@ladybugdb/wasm-core` v0.15.3 default async
(single-threaded) build loads cleanly under Vite + Chromium with no
cross-origin-isolation configuration. In-memory database works: node
table create, inserts, rel table + edge insert, MATCH-with-edge
query all round-trip correctly. This is the minimum evidence we
needed that a browser-side palace client is feasible.

**Persistence: BLOCKED at the library layer** (as of v0.15.3). None
of the four packaged FS configurations currently supports putting a
`.lbug` file on persistent browser storage:

| Build | OPFS mount | IDBFS mount | DB open on mount |
|---|---|---|---|
| default (single-threaded async) | ✓ succeeds | ✗ `FS.filesystems.IDBFS` undefined | ✗ `Aborted(Assertion failed: invalid handle: 1)` at `opfs_backend.cpp:292` inside the first `Database.init()` — the Emscripten WasmFS OPFS backend requires a pthread worker context (OPFS sync-access handles only work off the main thread, per browser spec) and this build has no pthreads |
| multithreaded async | ✓ / ✗ | ✓ / ✗ | both mount calls hang with `thread pool exhausted` — the build ships with a fixed PTHREAD_POOL_SIZE that is consumed by the worker dispatch machinery before FS mount can claim a thread |
| multithreaded sync | n/a | n/a | `init()` fails because pthread workers resolve to `http://host/undefined` under Vite; the bundled build's worker URL resolution doesn't survive Vite's ES-module transforms |
| nodejs | uses NODEFS; browser-incompatible by design | — | — |

The reproducer lives at `/tmp/lbug-wasm-spike/` for anyone who wants
to retry on a future release.

**Implication for Memory Palace architecture.** The PRD's palace
lens (FR63, FR74–79) is designed around a local-first browser
palace — the browser running LadybugDB directly against OPFS. That
deployment is not available today via the published packages. Three
directions are open, with a recommendation:

1. **Server-authoritative LadybugDB; browser is a view.**
   `jelly-server` owns the persistent graph via `@ladybugdb/core`
   (already validated, see "Phase 0 validation — results"). The
   browser either queries the server over HTTP/WebSocket with a
   small in-browser cache, or keeps an in-memory LadybugDB seeded
   from a server snapshot on each load. This changes FR74–79 from
   "local render" to "networked render with ephemeral cache" —
   acceptable for MVP since `jelly-server` exists and is on the
   critical path anyway.
2. **Bytes-in-IndexedDB, runtime-in-memory.** Serialize the `.lbug`
   file (or a replay log of envelopes) to IndexedDB via the
   browser's native API, load bytes into an in-memory LadybugDB at
   page load, write changes back on close/unload. This keeps the
   "browser-local palace" semantics but depends on LadybugDB
   supporting a bytes-in / bytes-out serialization mode. Needs
   research.
3. **Wait for or contribute an upstream fix.** File an issue with
   LadybugDB requesting: (a) default build with IDBFS compiled in
   (simplest browser persistence story, uses IndexedDB under the
   hood, no pthread requirement), or (b) multithreaded build with
   a larger `PTHREAD_POOL_SIZE` so OPFS mount doesn't starve. Both
   are build-flag changes on their side; neither is an architecture
   rewrite.

**Recommendation: take direction 1 for MVP** (server-authoritative
with in-memory browser cache), while filing direction 3 upstream as
a quality-of-life ask. Direction 2 is a fallback if the upstream
request stalls.

### Step 2b: WASM browser spike (`kuzu-wasm@0.11.3`, upstream) — FULL PASS

Rerun of the persistence test against the original upstream
`kuzu-wasm@0.11.3` package (the final Kuzu release before the fork
split). Same Vite 8.0.9 + Chromium setup, no cross-origin
isolation, no COOP/COEP, no pthread workers. Verified reproducer at
`/tmp/kuzu-wasm-spike/`. Result: **clean persistence across page
reloads.**

Pattern that works (copy for `src/memory-palace/store.ts`):

1. Copy the worker script into a statically served location. Under
   SvelteKit, drop `node_modules/kuzu-wasm/kuzu_wasm_worker.js`
   into `static/kuzu_wasm_worker.js` (or add a `bun run bootstrap`
   script that copies it on install).
2. `import kuzu from 'kuzu-wasm'` and call
   `kuzu.setWorkerPath('/kuzu_wasm_worker.js')` once at module init.
3. Lifecycle per session:
   ```ts
   await kuzu.FS.mkdir('/data').catch(() => {});
   await kuzu.FS.mountIdbfs('/data');
   await kuzu.FS.syncfs(true);                 // IndexedDB → FS
   const db = new kuzu.Database('/data/palace.kz');
   const conn = new kuzu.Connection(db);
   // …queries…
   await conn.close();
   await db.close();
   await kuzu.FS.syncfs(false);                // FS → IndexedDB
   await kuzu.FS.unmount('/data');
   ```
4. The database path in kuzu-wasm v0.11.3 is a **file**, not a
   directory (this differs from the upstream `browser_persistent`
   example which targeted an older v0.8 API that used a directory).
5. Confirmed incrementing behaviour across three page reloads:
   `prior=0 → prior=2 → prior=3 → prior=4` (each load appends one
   row and the new total shows up next load).

Wire-format implication: LadybugDB advertises storage-format
compatibility with Kuzu v0.11.3, so a `.kz` or `.lbug` file
written by `kuzu-wasm@0.11.3` in the browser can be read by the
server-side `@ladybugdb/core`. The cross-runtime invariant holds.

### Decision: adopt kuzu-wasm@0.11.3 in the browser as interim; file upstream

`src/memory-palace/store.ts` will be a thin wrapper that routes to
`@ladybugdb/core` on the server (Bun) and `kuzu-wasm@0.11.3` in
the browser. Both share the same Cypher/API surface and the same
on-disk storage format; the wrapper's public contract is one file.

Parallel: upstream issue filed —
[LadybugDB/ladybug#399](https://github.com/LadybugDB/ladybug/issues/399)
— asking them to (a) restore IDBFS in the default
@ladybugdb/wasm-core build (trivial `-lidbfs.js` linker flag
change; the `mountIdbfs` method already exists on the JS wrapper,
the backing filesystem is absent), and (b) build the multithreaded
variant with `-sPTHREAD_POOL_SIZE_STRICT=0` so the pool auto-grows
instead of deadlocking on FS mount. Both are one-line build
changes on their side; each would let us consolidate on
@ladybugdb/wasm-core and drop the legacy kuzu-wasm dependency.

**Vite and SvelteKit are both fine.** No plugin workarounds,
adapter changes, or bundler migrations required. We remain on the
canonical stack.

**Consequence for PRD §6.2.1.** The swap-boundary wrapper
(`src/memory-palace/store.ts`) now has an explicit split:
`jelly-server` imports `@ladybugdb/core` (napi); the browser lens
pack imports `kuzu-wasm@0.11.3` for IDBFS-backed persistence
(storage-compatible with `.lbug`). Once the upstream IDBFS fix
lands, swap the browser import to `@ladybugdb/wasm-core` — the API
surface is identical. The wrapper's public contract is unchanged
in either case.

## References

- Research synthesis:
  `docs/research/graph-db-options/synthesis.md`
- Summary JSON:
  `docs/research/graph-db-options/summary.json`
- LadybugDB vector-extension effort-sizing:
  `docs/research/graph-db-options/hypotheses/h-ladybug-vector-effort/findings.md`
- PRD §6.2, §6.2.1, §6.2.2, §9, FR80:
  `docs/products/memory-palace/prd.md`
