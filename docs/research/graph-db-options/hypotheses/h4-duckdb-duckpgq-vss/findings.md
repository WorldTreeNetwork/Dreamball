# Hypothesis: DuckDB + duckpgq + VSS collapses graph store AND vector store into one embedded, WASM-capable dependency — the unicorn

## Summary

**Qualified NO — promising but not yet the unicorn.** DuckDB itself is production-grade and the combination is architecturally coherent, but duckpgq remains a CWI research project explicitly labelled "work in progress" (community extension v0.3.1 in the catalogue, last pushed April 9, 2026), and the VSS extension's HNSW persistence is still behind an experimental flag with known data-corruption risk on crash. The fatal tiebreaker for a WASM-first deployment is that **neither duckpgq nor VSS appears in the official DuckDB-WASM extension list** as of DuckDB 1.5.2 (April 2026) — the stable WASM extension set covers only 11 core extensions. VSS has historically shipped WASM builds for the in-memory case (confirmed for DuckDB 0.10.2), but duckpgq has no documented WASM loading path. For a server-side or Bun-embedded deployment the story is considerably better.

---

## Evidence

### 1. duckpgq maturity (April 2026)

- **Community extension catalogue version**: 0.3.1. Maintainer `Dtenwolde` (Daniël ten Wolde, CWI, first author of VLDB/CIDR papers) [1].
- **GitHub repo**: `cwida/duckpgq-extension` — 393 stars, 27 forks, 31 open issues, last push **2026-04-09**. MIT license [2].
- **"WIP" disclaimer prominent**: *"DuckPGQ is currently a research project and a work in progress. While we encourage you to explore and experiment with it, please be aware that there may be bugs, incomplete features, or unexpected behaviour."* [3]
- **DuckDB version dependency**: Requires DuckDB ≥ v1.4.1. DuckDB on v1.5.2 (April 13, 2026).
- **No production users cited** anywhere in documentation or discussions. October 2025 financial-crime demo is the first first-party showcase — a demonstration, not production.
- **KuzuDB context**: KuzuDB's archival in Oct 2025 has made the DuckPGQ path more attractive by elimination [7].

### 2. Property graph semantics

**Data model**: DuckPGQ is a **query layer over relational tables**, not a native graph store. Nodes = rows in vertex tables; edges = rows in edge tables with foreign-key columns. The `CREATE PROPERTY GRAPH` statement declares graph semantics on top of existing tables. **This is load-bearing for rebuild-from-CAS**: bulk-insert into ordinary DuckDB tables and the graph view regenerates instantly with no rebuild cost [8].

**Edge properties**: Every column of an edge table is an edge property. Multiple named float/enum/string/BLOB properties on edges are fully supported — just SQL DDL. The financial-crime demo extracts `t.amount` (float) from transfer edges in live queries. No documented limitation on cardinality or types [6][8].

**Path quantifiers**: All standard SQL/PGQ quantifiers implemented:
- `+` — one or more
- `*` — zero or more
- `{n,m}`, `{n,}`, `{,m}` — bounded ranges [9]

**Path constraints by edge label**: `[k:EdgeLabel]` syntax. Multiple label types expressible in a single `CREATE PROPERTY GRAPH` [9].

**Directed vs undirected**: Both supported — `()->()`, `()<-()`, `()-()`, `()<->()` [9].

**DAG traversal / merge points**: Not dedicated, but relational foundation means multiple incoming edges to a node are trivial. Financial-crime demo finds cycles at depths 8–12.

**CRITICAL GAP — ALL PATHS not supported**: Docs explicitly state: *"DuckPGQ will not support ALL Kleene* path-finding, and initially only ANY SHORTEST single-edge Kleene*."* For the palace timeline (which needs full parent-hash chain traversal, not just shortest-path), **the graph query layer cannot be used for that traversal; you'd fall back to recursive CTEs in standard SQL** — which DuckDB handles well, but defeats the ergonomic purpose of duckpgq for that workload [9].

**Performance**: arXiv paper (2505.07595) benchmarks DuckPGQ against Neo4j and Spanner. Graph view creation: 0.2–0.5ms vs Neo4j's ~4,600ms. CSR + vectorised multi-source BFS + SIMD. "Constantly outperform Neo4j" [10][11].

### 3. VSS extension status

- **Core extension** (ships with DuckDB, no separate install) [12].
- **HNSW implementation**: Based on `usearch`. L2/cosine/inner product. Tunable `ef_construction`, `ef_search`, `M`, `M0`.
- **Persistence**: Still behind `SET hnsw_enable_experimental_persistence = true`. **WAL recovery not implemented**. Crash with uncommitted HNSW changes can corrupt the index. Documentation explicitly advises against production use with persistence enabled [12].
- **In-memory only by default**. For Dreamball (rebuild-from-CAS anyway), in-memory HNSW with periodic full serialisation may be acceptable.
- **WASM history**: Confirmed working in DuckDB-WASM at v0.10.2 (May 2024) for in-memory use [13]. Does not appear in current stable WASM extension list (1.5.x).
- **Oct 2024 additions**: `HNSW_INDEX_JOIN` (66× speedup for N:M), `array_cosine_distance`, pgvector-compatible `<=>` operator [14].

### 4. DuckDB-WASM extension availability

The stable DuckDB-WASM extension list (DuckDB 1.5.x) contains exactly 11 extensions: autocomplete, excel, fts, icu, inet, json, parquet, sqlite, sqlsmith, tpcds, tpch. **Neither `duckpgq` nor `vss` is listed** [15].

The `custom_extension_repository` mechanism theoretically allows loading duckpgq WASM builds, but:
- Not validated as a supported workflow in current documentation
- duckpgq community extension catalogue does not list `wasm` as a supported platform
- Unsigned extension loading required for S3-hosted duckpgq builds

**Practical conclusion**: WASM deployment of duckpgq+VSS is a **Phase-0 spike item**, not a confirmed capability.

### 5. Bun integration

- Original `duckdb` npm package **deprecated** as of DuckDB 1.5.x series. Replacement: `@duckdb/node-api` [16].
- Bun's NAPI compatibility improved; previous `napi_register_module_v1` crash fixed.
- Bun-native binding `@evan/duckdb` claims 2–6× faster than Node but lightly maintained (111 stars, 9 commits) [17].
- For server-side Bun (jelly-server), `@duckdb/node-api` is the recommended path. No known blockers.

### 6. Combined schema sketch

```sql
-- Nodes
CREATE TABLE inscriptions (id BLOB PRIMARY KEY, type TEXT, content TEXT, ...);
CREATE TABLE palaces      (id BLOB PRIMARY KEY, name TEXT, ...);
CREATE TABLE mythos_nodes (id BLOB PRIMARY KEY, label TEXT, ...);
CREATE TABLE timeline_nodes (id BLOB PRIMARY KEY, signed_action BLOB, parent_hash BLOB, ...);

-- Edges (with properties)
CREATE TABLE contains_edges (src BLOB, dst BLOB, direction TEXT);
CREATE TABLE aqueduct_edges (src BLOB, dst BLOB,
  resistance FLOAT, capacitance FLOAT, conductance FLOAT, phase TEXT);
CREATE TABLE timeline_edges (parent BLOB, child BLOB, parent_hash BLOB);

-- Property graph view
CREATE PROPERTY GRAPH memory_palace
  VERTEX TABLES (inscriptions, palaces, mythos_nodes, timeline_nodes)
  EDGE TABLES (contains_edges ..., aqueduct_edges ..., timeline_edges ...);

-- Vector index
ALTER TABLE inscriptions ADD COLUMN embedding FLOAT[1536];
CREATE INDEX inscription_hnsw ON inscriptions USING HNSW (embedding);
```

Timeline parent-hash chain traversal requires **recursive CTE** (not duckpgq, due to ALL PATHS limitation):
```sql
WITH RECURSIVE chain AS (
  SELECT id, parent_hash FROM timeline_nodes WHERE id = $start
  UNION ALL
  SELECT t.id, t.parent_hash FROM timeline_nodes t JOIN chain c ON t.id = c.parent_hash
)
SELECT * FROM chain;
```

### 7. Rebuild-from-CAS ergonomics

DuckDB's bulk-load is industrial-strength: `COPY FROM` Parquet/CSV/JSON, `INSERT OR REPLACE`. Since duckpgq's graph is a view over relational tables, there's no graph-specific bulk-load step — populate underlying tables and the graph view is automatically current. Blake3 as `BLOB` primary key is natively supported.

---

## Confidence

**Level**: medium

Multiple independent sources agree on core facts. WASM co-loadability of duckpgq+VSS in current DuckDB-WASM could not be confirmed from documentation — requires hands-on spike. VSS production readiness assessment is high-confidence.

---

## Sources

- [1] https://raw.githubusercontent.com/duckdb/community-extensions/main/extensions/duckpgq/description.yml
- [2] https://github.com/cwida/duckpgq-extension
- [3] https://duckpgq.org/
- [6] https://duckdb.org/2025/10/22/duckdb-graph-queries-duckpgq
- [7] https://gdotv.com/blog/weekly-edge-kuzu-forks-duckdb-graph-cypher-24-october-2025/
- [8] https://duckpgq.org/documentation/property_graph/
- [9] https://duckpgq.org/documentation/sql_pgq/
- [10] https://arxiv.org/html/2505.07595v1
- [11] https://www.cidrdb.org/cidr2023/papers/p66-wolde.pdf
- [12] https://duckdb.org/docs/current/core_extensions/vss.html
- [13] https://duckdb.org/2024/05/03/vector-similarity-search-vss
- [14] https://duckdb.org/2024/10/23/whats-new-in-the-vss-extension
- [15] https://duckdb.org/docs/current/clients/wasm/extensions.html
- [16] https://github.com/duckdb/duckdb-node
- [17] https://github.com/evanwashere/duckdb

---

## Open Questions

1. **WASM co-loadability of duckpgq + VSS in DuckDB-WASM 1.5.x** — 2-hour spike required.
2. **ALL PATHS limitation impact on palace timeline** — does `ANY SHORTEST` suffice, or do queries need full-path enumeration? Needs PRD §9 query spec.
3. **VSS persistence stability trajectory** — WAL recovery roadmap unclear.
4. **duckpgq stability at v1.4.x** — numbering scheme confusing (0.3.1 catalogue vs 1.4.4 CI).
5. **Blake3 BLOB(32) as PK performance** — fingerprint-keyed node lookups at 10K–100K scale untested.
6. **Bun + @duckdb/node-api + duckpgq** — extension loading via new API undocumented.

## Sub-Hypotheses

- **h4a-duckpgq-wasm-loadability**: Does `custom_extension_repository` load duckpgq inside duckdb-wasm 1.5.x, and can VSS co-exist? Live browser spike required.
- **h4b-vss-wal-recovery-roadmap**: Is VSS HNSW persistence scheduled to exit experimental in DuckDB 1.6.x+? No public timeline.
- **h4c-all-paths-workaround-sufficiency**: Does `ANY SHORTEST` + recursive CTEs cover all required palace query patterns?
