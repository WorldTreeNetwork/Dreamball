# Hypothesis: Survey of the remaining 2026-relevant embedded graph DB field — Oxigraph, SurrealDB, HelixDB, IndraDB, RocksDB/SQLite-custom

## Summary

Of the five named candidates, four are disqualified on hard criteria (wrong license, not embedded, or dormant). One — IndraDB — survives disqualification but is too thin to be a primary contender. The sweep also surfaced one unlisted candidate, **Grafeo**, that is Apache-2.0, genuinely embedded, has Node/Bun/WASM bindings, and ships properties-on-edges plus built-in vector support — but carries serious maturity risk due to AI-generated codebase concerns. No named candidate matches Kuzu or CozoDB on the combination of license + embedded + maturity; Grafeo is the only surprise worth escalating to the synthesizer with a red-flag asterisk.

---

## Evidence

### 1. Oxigraph

- **Embedded**: Yes — ships as a Rust library; also has a CLI server mode. JS package is WASM-compiled and runs in-process.
- **License**: Apache-2.0 / MIT dual-license. [1]
- **Active 2026**: Last release v0.5.6 was March 14, 2026 — actively maintained. [1]
- **Node/Bun binding**: Yes — `oxigraph` npm package (WASM-based), works on Node 18+ and modern browsers. [2]
- **WASM**: Yes — core distribution mode for JS environments.
- **Property graph / edge properties**: **No.** Strictly RDF triples (subject-predicate-object). Edge properties require RDF reification, which is cumbersome and non-standard in practice. [1]
- **DAG traversal / recursive queries**: SPARQL 1.1 property paths support recursive traversal, but the query model is triple-centric.
- **Vector support**: No.
- **Rebuild-from-CAS ergonomics**: Acceptable for RDF bulk load (Turtle, N-Quads, etc.); not property-graph idiomatic.
- **Verdict**: **Disqualified** — RDF/SPARQL only, no native property-graph with edge properties. Appropriate for semantic web / knowledge graph use cases; wrong fit for a property graph with typed edges bearing weights/timestamps.

---

### 2. SurrealDB embedded mode

- **Embedded**: Yes — `@surrealdb/node` runs SurrealDB fully in-process (no network hop) on Node.js, Bun, or Deno, using mem://, surrealkv://, or RocksDB backends. [3][4]
- **License**: **BUSL 1.1** until January 1, 2030, then converts to Apache 2.0. [5] This is a disqualifying license for production use in a closed or commercial product.
- **Active 2026**: Yes — JS SDK 2.0 released, active releases. The `surrealdb.wasm` repo was archived January 2026 (WASM now bundled in main SDK). [3]
- **Node/Bun binding**: Yes, via `@surrealdb/node`. [4]
- **WASM**: Yes, via the main JS SDK.
- **Property graph / edge properties**: SurrealDB is a multi-model document-graph database. Graph traversal uses `->` relation syntax; edges are records that can carry properties.
- **DAG traversal**: Yes, recursive graph traversal supported in SurrealQL.
- **Vector support**: Yes — vector search added in recent releases.
- **Rebuild-from-CAS ergonomics**: Reasonable with SurrealQL upsert semantics.
- **Verdict**: **Disqualified** — BUSL 1.1 is a non-starter for open-source or redistributed use. The technical story is otherwise compelling; worth revisiting if/when Apache 2.0 conversion happens in 2030 or if a commercial license is acceptable.

---

### 3. HelixDB

- **Embedded**: **No.** HelixDB requires a separate server process; clients connect via TypeScript/Python SDKs over the network (default port 6969). The HN thread explicitly confirms "can't run this as an embedded DB like sqlite" — the founders confirmed this is not supported. [6][7]
- **License**: AGPL-3.0. Disqualifying for closed-source embedding; commercial license required.
- **Active 2026**: Yes — v2.3.4 released March 31, 2026; 2,652 commits on main. [6]
- **Node/Bun binding**: Yes — `helix-ts` TypeScript SDK.
- **WASM**: LMDB backend prevents WASM; future custom storage planned. [7]
- **Property graph / edge properties**: Graph + vector combined model; specific edge-property semantics not clearly documented.
- **Vector support**: Yes — built-in embeddings and HNSW-style vector search.
- **Verdict**: **Disqualified** — not embedded (server-required architecture), AGPL-3.0.

---

### 4. IndraDB

- **Embedded**: Yes — Rust library crate, embeds directly with no server. [8]
- **License**: MPL-2.0 — file-level copyleft but generally permissive for linking; acceptable in most scenarios.
- **Active 2026**: Last release v5.0.0 was August 16, 2025. No evidence of 2026 commits; appears maintenance-mode or slow. [8]
- **Node/Bun binding**: No native bindings found. gRPC server available for cross-language use but that requires a server process.
- **WASM**: No.
- **Property graph / edge properties**: Yes — vertices and edges both support JSON properties. [8]
- **DAG traversal**: Basic multi-hop queries; no dedicated recursive/DAG query language.
- **Vector support**: No.
- **Rebuild-from-CAS ergonomics**: Supports RocksDB backend for persistence; bulk-load ergonomics not documented.
- **Verdict**: **Credible fallback** but weak — MPL-2.0, truly embedded, properties on edges, but no Node/WASM bindings, no vector support, thin query language, and slow development cadence (last release 8 months ago, possible dormancy).

---

### 5. TerminusDB embedded

- **Embedded**: No — TerminusDB is a distributed, server-oriented database. The Rust component is the storage backend library, not a standalone embedded DB.
- **License**: Apache 2.0 (community edition).
- **Active 2026**: Handed off to DFRNT as maintainers in 2025; maintenance trajectory unclear. [9]
- **Node/Bun binding**: REST/GraphQL API only; not in-process.
- **Property graph**: RDF-adjacent with WOQL datalog query language; provenance/versioning focus.
- **Verdict**: **Disqualified** — not embedded, server-oriented, niche query language. Wrong fit.

---

### 6. Custom graph layer over RocksDB or SQLite

- **Implementation cost**: SQLite-based approaches (e.g., `simple-graph`, `sqlite-graph`) can be prototyped in days using two tables (nodes, edges with JSON properties), but lack query planning, traversal optimization, and recursive CTE support for deep graphs. RocksDB-based approaches (e.g., Hexadb) require implementing 6-index triple schemes and custom traversal logic — weeks to months for a production-quality implementation. [10][11]
- **Known patterns**: Oxigraph itself is essentially RocksDB + 6-index RDF store. A property-graph variant would swap triple stores for adjacency-list indices. TinkerPop (JVM) has RocksDB backends (HugeGraph) but that path requires JVM or wrapping in a server.
- **WASM/Bun**: SQLite via WASM (e.g., wa-sqlite, sqlite-vec) is the most portable path; a thin graph layer on top is feasible but hand-rolled.
- **Verdict**: **Credible last-resort baseline.** SQLite with two adjacency tables + JSON properties + recursive CTEs covers 80% of simple graph use cases with near-zero dependency cost. Adequate for DAG traversal without recursive cycles. Estimated effort to production-quality: 1–3 weeks for basic; months for anything approaching Kuzu-grade query planning.

---

### 7. Grafeo (discovered during sweep)

- **Embedded**: Yes — "embeddable with zero external dependencies: no JVM, no Docker, no external processes." [12]
- **License**: Apache-2.0. [12]
- **Active 2026**: v0.5.39 released April 16, 2026; 1,290 commits. Very recently launched. [12]
- **Node/Bun binding**: Yes — `@grafeo-db/js` on npm via napi-rs. [12]
- **WASM**: Yes — `@grafeo-db/wasm` on npm. [12]
- **Property graph / edge properties**: Yes — LPG model with "edges with types and properties." Also supports RDF. [12]
- **DAG traversal**: Supports GQL, Cypher, Gremlin, GraphQL, SPARQL, SQL/PGQ — comprehensive. [12]
- **Vector support**: Yes — HNSW indexing, cosine/Euclidean/dot-product/Manhattan, vector quantization, hybrid graph+vector queries. [12]
- **Rebuild-from-CAS ergonomics**: Not specifically documented but upsert semantics implied by the multi-language query support.
- **Red flags**: HN commenters flagged that the creator committed 100,000–200,000 lines of code per week, is largely AI-generated, and the creator acknowledged "beta status." One commenter: "Using a LLM coded database sounds like hell." Benchmark credibility questioned. [13]
- **Verdict**: **Conditional strong contender** — on paper it checks every box. In practice it is an AI-generated beta with unvalidated benchmarks and an unknown correctness story. Requires independent evaluation (run their test suite, check for data corruption under concurrent writes) before trusting in any production or near-production context.

---

## Confidence

**Level**: medium

Multiple primary sources (GitHub repos, official docs, HN threads) were consulted for each candidate. Grafeo's technical claims are from its own README and not independently benchmarked; the maturity concern is well-sourced from HN. SurrealDB license status is directly confirmed from the LICENSE file. Confidence would be high except for Grafeo's uncertain real-world correctness.

---

## Sources

- [1] https://github.com/oxigraph/oxigraph — "Apache-2.0 / MIT dual license; v0.5.6 released March 14, 2026; RDF-only"
- [2] https://www.npmjs.com/package/oxigraph — "Node 18+ WASM-based npm package"
- [3] https://surrealdb.com/blog/introducing-javascript-sdk-2-0 — "JS SDK 2.0; surrealdb.wasm archived Jan 2026, WASM now in main SDK"
- [4] https://surrealdb.com/docs/sdk/javascript/engines/node — "in-process embedded mode for Node/Bun/Deno; mem:// and surrealkv:// protocols"
- [5] https://github.com/surrealdb/surrealdb/blob/main/LICENSE — "BUSL 1.1; change date Jan 1 2030; converts to Apache 2.0"
- [6] https://github.com/HelixDB/helix-db — "AGPL-3.0; server-required; v2.3.4 March 31 2026; Rust + LMDB"
- [7] https://news.ycombinator.com/item?id=43975423 — "founders confirm no embedded mode; AGPL concern; WASM blocked by LMDB"
- [8] https://github.com/indradb/indradb — "MPL-2.0; v5.0.0 August 2025; in-process Rust lib; no Node/WASM bindings; no vector"
- [9] https://github.com/terminusdb/terminusdb — "server-oriented; DFRNT new maintainer 2025; not embedded"
- [10] https://github.com/dpapathanasiou/simple-graph — "SQLite two-table graph pattern with JSON properties"
- [11] https://github.com/angshuman/hexadb — "RocksDB-based triple store / graph; six-index scheme"
- [12] https://github.com/GrafeoDB/grafeo — "Apache-2.0; embedded; Node + WASM bindings; LPG+RDF; vector; v0.5.39 April 16 2026"
- [13] https://news.ycombinator.com/item?id=47467567 — "HN reception: AI-generated codebase concern; beta status confirmed by creator; benchmark credibility questioned"

---

## Shortlist for Synthesis

**Candidates from this survey that deserve inclusion in the final synthesis:**

1. **Grafeo** — Apache-2.0, genuinely embedded, Node + WASM bindings, LPG with edge properties, vector support, Cypher/GQL/SPARQL, active April 2026. Must be flagged with maturity/AI-codebase asterisk and requires independent correctness validation before use.

*(IndraDB is not shortlisted — no Node/WASM bindings, no vector support, possibly dormant.)*

**Everything explicitly ruled out:**

| Candidate | Reason |
|---|---|
| Oxigraph | RDF-only, no property graph with edge properties |
| SurrealDB | BUSL 1.1 license (disqualifying) |
| HelixDB | Not embedded (requires server process); AGPL-3.0 |
| IndraDB | No Node/WASM bindings, no vector, possible dormancy — too thin to compete |
| TerminusDB | Not embedded, server-oriented, niche query language |

**RocksDB/SQLite custom fallback (2-sentence viability):**

A custom SQLite-based graph layer (two tables: nodes, edges with JSON properties + recursive CTEs) is the lowest-risk last resort — it runs everywhere SQLite runs, including WASM, with zero new dependencies and a 1–3 week build time for basic DAG traversal. It cannot match Kuzu or CozoDB on query planning, index sophistication, or bulk-load throughput, so it is a ceiling-capped option appropriate only if every purpose-built embedded graph DB is disqualified on license or correctness grounds.
