# Hypothesis: CozoDB is the best dark-horse — Datalog + built-in HNSW vectors + embedded Rust with Node bindings beats the Kuzu-lineage on most axes

## Summary

**Verdict: Credible fallback, not a primary contender — as of April 2026.**

CozoDB's technical shape is a near-perfect fit for the Memory Palace's requirements on paper: embedded Rust, MPL-2.0, pluggable storage (RocksDB/SQLite/mem), native HNSW vector search deeply integrated into Datalog, `Bytes` type, recursive queries for DAG traversal, and a functional WASM build. However, the project has effectively stalled: last release was v0.7.6 in December 2023, last code commit December 2024, and the "Is cozo still being maintained?" issue (#301, opened Dec 2024) received eight successive candle-emoji responses from the community through April 2026 with no author reply. The Node binding uses neon + node-pre-gyp and is explicitly broken under Bun bundlers (open issue #303, Jan 2026, unmerged). These two factors — abandonment risk and Bun incompatibility — are both on the deal-breaker list. If either resolves (a community fork picks it up, or someone merges the bundler fix), Cozo becomes a very strong option.

---

## Evidence

### 1. Maintenance Status (CRITICAL FAIL)

- **Last release**: v0.7.6, published 2023-12-11. No release in 16+ months as of April 2026.
- **Last commit**: 2024-12-04 (a bug fix PR merge by a community contributor, not the primary author Ziyang Hu / `zh217`).
- **Commit cadence since v0.7.6**: Sparse community PRs only — RocksDB storage engine update (Nov 2024), AST exposure (Oct 2024), a bug fix (Aug 2024). The primary author's last meaningful commit activity visible in the top-15 was merging PRs, not authoring code.
- **"Is cozo still being maintained?" (issue #301)**: Opened 2025-12-04, 8 comments, all `🕯️` emojis from different community accounts, spanning 2025-12-04 through 2026-04-10. The author (`zh217`) has not replied. This is the clearest possible community signal of perceived abandonment.
- **Open issues**: 47 open, including several unaddressed since mid-2024.
- **New activity April 2026**: Issues #306–310 opened 2026-04-11 and 2026-04-12 (fix sled backend, add redb backend, fix benchmarks). These are community contributions, not author-driven work. Suggests some community is still alive but no maintainer.
- **Stars**: 3,961

### 2. Node/Bun Bindings (DEAL-BREAKER in current state)

- **Binding mechanism**: `cozo-lib-nodejs` uses **neon** (Rust→JS via neon crate) compiled to a `.node` native addon, distributed via `@mapbox/node-pre-gyp` with prebuilt binaries. NAPI version 6.
- **Last publish**: 2023-12-11. No updates since.
- **Bun compatibility**: **Broken for bundlers**. Issue #303 (opened 2026-01-28, open and unmerged as of investigation date) explicitly states: `node-pre-gyp` uses dynamic `require()` path resolution that breaks Bun, esbuild, Webpack, and Rollup at build time. The proposed fix adds a `bundler.js` static entry point but has not been merged — there is no maintainer to merge it.
- **Runtime (not bundled)**: Bun can run NAPI-v6 modules at runtime if the `.node` binary is present on disk via `bun install`. The issue is with bundling/compilation into a standalone binary.

### 3. WASM Feasibility (PARTIAL — mem backend only)

- **Exists and ships**: `cozo-lib-wasm` is a real, published npm package. The WASM demo runs at `https://www.cozodb.org/wasm-demo/`.
- **Storage in WASM**: **Memory only** — no persistence. The browser issue (#213) documents community workarounds (OPFS JSON export, localStorage) but no SQLite-in-WASM path has been merged.
- **Graph algorithms**: Disabled in WASM (rayon requires threads).
- **HNSW in WASM**: Available — "HNSW functionality is available for CozoDB on all platforms… even in the browser with the WASM backend."

### 4. Data Model Fit (STRONG)

**Edge properties with mixed types**: Yes. Cozo relations are key-value with arbitrary column schemas. `Bytes` is a first-class type (ideal for 32-byte Blake3 fingerprints).

**Memory Palace mappings**:
- Containment edge: `:create contains {parent: Bytes, child: Bytes}`
- Aqueduct flow properties: `:create aqueduct {id: Bytes => flow_rate: Float, medium: String, metadata: Json}`
- Timeline DAG: `:create timeline {hash: Bytes => parent_hash: Bytes?, timestamp: Int, payload: Bytes}`
- Knowledge-graph triples: `:create triple {subject: Bytes, predicate: String, object: Any}`

**Recursive queries for ancestor walks**: First-class. Canonical Datalog transitive closure pattern:
```
reachable[child] := *timeline{hash: $root, parent_hash: child}
reachable[child] := reachable[ancestor], *timeline{hash: ancestor, parent_hash: child}
?[child] := reachable[child]
```
Exactly the ancestor-walk pattern needed for timeline rewind and mythos chain verification.

**Path-length bounded traversal**: Expressible by threading a counter through recursive rule heads.

### 5. Vector Search (STRONG technically)

- **Algorithm**: HNSW, native Rust (not a hnswlib wrapper).
- **Parameters**: `dim`, `dtype` (F32/F64), `distance` (L2/Cosine/IP), `m`, `ef_construction`, `filter`.
- **Hybrid queries**: Vector search unifies into Datalog rules as any other relation — native, not bolted on.
- **Persistence**: On-disk with RocksDB/SQLite backends, MVCC incremental updates.
- **HNSW graph as queryable relation**: The proximity graph itself is queryable as a normal relation — unique and powerful.

### 6. Rebuild-from-CAS Ergonomics (GOOD)

- **`import_relations`**: Upsert semantics, transactional.
- **Idempotent writes**: Replaying `.jelly` envelopes is safe; re-importing overwrites in place.
- **`backup`/`restore`**: ~1M rows/sec write, 400K rows/sec restore. Atomic consistent snapshot.

### 7. License (ACCEPTABLE WITH FLAG)

- **MPL-2.0** — file-level copyleft. Not a commercial blocker for unmodified use. Patches to Cozo must be MPL-2.0. With inactive maintainer, patches accumulate in forks.

---

## Confidence

**Level**: high. Maintenance finding unambiguous (candle vigil on #301). Technical capability findings from official docs.

---

## Sources

- [1] https://github.com/cozodb/cozo — repo metadata: 3961 stars, last push 2024-12-04, MPL-2.0
- [3] https://github.com/cozodb/cozo/issues/301 — "Is cozo still being maintained?" 8 candle responses Dec 2025–Apr 2026
- [5] https://github.com/cozodb/cozo/issues/303 — Bundler fix Jan 2026, unmerged
- [12] https://github.com/cozodb/cozo — README: HNSW, performance, storage matrix, recursive queries
- [13] cozo-docs/source/vector.rst — HNSW API, hybrid query syntax, multi-vector per row

---

## Open Questions

1. **Community fork viability** — April 2026 issues suggest ongoing activity. Is there an emerging fork (julep-ai contributors visible in PRs)?
2. **Bundler fix mergability** — Issue #303's fix is trivial. Could community merge it?
3. **Bun runtime (non-bundled) compatibility** — Quick empirical check needed.
4. **WASM persistence via OPFS + SQLite** — `rusqlite` WASM path partially ready.
5. **Time-travel feature** — Cozo has per-relation time travel; may conflict with content-addressed timeline model.

## Sub-Hypotheses

- **[h5a-cozo-fork]**: julep-ai or similar org may have forked and be maintaining Cozo.
- **[h5b-bun-napi-runtime]**: NAPI-v6 `.node` binary may work under Bun at runtime even though bundling is broken.
