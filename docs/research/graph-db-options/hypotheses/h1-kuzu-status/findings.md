# Hypothesis: KuzuDB upstream is effectively dead; LadybugDB and Bighorn are the only surviving lineages

## Summary

The hypothesis is **partially confirmed and partially miscalibrated**. KuzuDB upstream is definitively dead: the GitHub repo was archived on October 10, 2025 (read-only), with the final release v0.11.3, following Kuzu Inc.'s acquisition by Apple (confirmed via EU Digital Markets Act filings in February 2026). However, the framing that "LadybugDB and Bighorn are the only surviving lineages" understates the fork landscape — there are at least **three significant forks** (LadybugDB, Bighorn by Kineviz, and RyuGraph by Predictable Labs) plus a fourth production fork maintained by Vela Partners. LadybugDB is the most active and credibly positioned as the community's leading successor, with regular releases through April 2026. Bighorn has no published releases and significantly less traction. RyuGraph is a third contender with MIT license and Python/Rust bindings but less Node.js coverage.

---

## Evidence

### 1. Upstream KuzuDB Status

**Verdict: Confirmed dead.**

- kuzudb/kuzu GitHub repo **archived October 10, 2025**, same day as final release v0.11.3. Pinned notice: "Kuzu is working on something new!" [1]
- Release timeline: v0.11.0 (Jul 13), v0.11.1 (Jul 26), v0.11.2 (Aug 21), v0.11.3 (Oct 10, 2025). [1]
- **Acquisition by Apple** confirmed via EU Digital Markets Act regulatory filings, reported February 11–12, 2026 by 9to5Mac, BetaKit, MacObserver, MacDailyNews. [2][3][4][5]
- The cryptic "working on something new" notice and LinkedIn departure announcement by engineer Prashanth Rao three days before archival are consistent with an acqui-hire under NDA. [6]
- **Storage format note**: v0.11.0 introduced a breaking storage format change (consolidated `data.kz` file). Community members observed format instability across versions. v0.11.3 is terminal — freezing at this point locks in a single format version. [1][7]

---

### 2. LadybugDB

**Verdict: The most active and credible Kuzu successor. Confidence: high.**

- **Provenance**: Fork of kuzudb/kuzu announced October 2025 by Arun Sharma (ex-Facebook Dragon distributed graph system, ex-Google). [8][9]
- **GitHub org**: `LadybugDB/ladybug`
- **License**: MIT (unchanged). Homepage: "Open source forever." [8]
- **Release cadence**: Highly active. [10]
  - v0.15.3 — April 1, 2026
  - v0.15.2 — March 18, 2026
  - v0.15.1 — March 2, 2026
  - v0.15.0 — February 28, 2026
  - v0.14.1 — January 9, 2026
  - v0.14.0 — January 7, 2026
  - v0.13.1 — December 16, 2025
  - v0.13.0 — December 15, 2025
  - Total commits: 5,769 (includes Kuzu history) — 973 stars, 72 forks
- **Stated goals**: "The only viable successor to Kuzu." Full one-to-one Kuzu replacement, focus on agentic solutions and highly regulated industries, lakehouse ecosystem integration. [8]
- **Sponsor**: "Ladybug Memory" (ladybugmem.ai) — some corporate backing, details limited.
- **Bindings**:
  - Python: `pip install ladybug` — confirmed
  - Node.js: `npm install @ladybugdb/core` — confirmed, with prebuilt binaries bundled [11]
  - WASM: Separate repo `LadybugDB/ladybug-wasm`, package `@ladybugdb/wasm-core`, 38 commits, no formal GitHub releases but distributed via npm. v0.15.3 notes mention OPFS integration and statically-linked extensions — actively developed. [12]
  - **Bun compatibility**: No explicit Bun support documented. The Node.js binding ships native (C/C++) binaries via Node-API (napi). Bun has partial Node-API compatibility; native modules with napi _may_ work but are not certified. No Bun-specific install path is documented. [13]
- **Bulk-load ergonomics**: Inherits Kuzu's COPY FROM / file-based import; no evidence of regression.

---

### 3. Bighorn (Kineviz)

**Verdict: Alive but low-momentum; no published releases. Confidence: medium.**

- **Provenance**: Fork by Kineviz (graph visualization company, makers of GraphXR). Announced October 2025. [14][6]
- **GitHub org**: `Kineviz/bighorn`
- **License**: MIT (unchanged). [14]
- **Releases**: **No releases published** as of April 2026. [14]
- **Commit count**: 5,232. 124 stars, 7 forks.
- **Stated goals**: Maintain as open source; integrate into GraphXR as both embedded and standalone server mode. [6][14]
- **Bindings**: Docs mention Python, Rust, and Node.js tutorials — docs appear to be a copy of Kuzu's with version date "Oct 23, 2025" (day after fork). WASM mentioned but not confirmed shipped as separate package. Bun not mentioned. [15]
- **Key concern**: No published releases in 6 months is a signal that Kineviz is using this primarily as an internal dependency for GraphXR rather than as a community-facing database product.

---

### 4. RyuGraph (Predictable Labs)

**Verdict: Third fork with active releases through December 2025; lower Node.js coverage. Confidence: medium.**

- **Provenance**: Fork by Predictable Labs Inc., announced by Akon Dey (former CEO of Dgraph). October 31, 2025. [16][17]
- **GitHub**: `predictable-labs/ryugraph`
- **License**: MIT
- **Releases**: v25.9.0 (Oct 25), v25.9.1 (Nov 16), v25.9.2 (Dec 6, 2025). **No releases after December 2025** — 4-month gap. [18]
- **Stars**: 133
- **Bindings**: Python confirmed, Rust confirmed, WASM mentioned in README. **Node.js NOT confirmed in release notes or README**. Bun not mentioned. [18]

---

### 5. Vela Partners Fork

**Verdict: Fourth fork, production-validated but private-leaning. Confidence: high.**

- Vela Partners maintains `Vela-Engineering/kuzu`, a fork adding concurrent multi-writer support for multi-agent workloads.
- Benchmarks show compelling performance: 374x faster than Neo4j on 2nd-degree path queries (100K nodes, 2.4M edges), 53x faster ingestion.
- Described as "production-tested." Focus is AI agent memory use cases.
- Less likely to be a community-facing alternative; more an internal fork. [19]

---

### 6. Vendor-and-Freeze Viability (Kuzu v0.11.3)

**Verdict: Viable for a rebuild-as-index use case, with caveats. Confidence: medium.**

- v0.11.3 is the final release and bundles all extensions (algo, fts, json, vector) — no extension server needed post-freeze. [1]
- Storage format changed significantly in v0.11.0; v0.11.3 is a patch on top of v0.11.0's format — "recently broken-in" not "years-stable".
- Engine backed by CIDR 2023 peer-reviewed research paper, described by Vela Partners as "stable and documented." [19]
- **Risk**: No security patches, no bug fixes after October 10, 2025. For a rebuildable index (not source of truth), this risk is substantially reduced.
- **Upside**: Node.js bindings for v0.11.3 are the original Kuzu napi bindings, known working.
- **Bun note**: No confirmed working Bun + Kuzu 0.11.3 report found.

---

## Confidence

**Level**: high

Multiple independent primary sources agree on the core facts. Medium-confidence claims: Bun native compatibility (no direct test data); Bighorn's actual development activity behind zero releases.

---

## Sources

- [1] https://github.com/kuzudb/kuzu — "Archived Oct 10, 2025, read-only. Final release v0.11.3."
- [2] https://9to5mac.com/2026/02/11/kuzu-database-company-joins-apples-list-of-recent-acquisitions/
- [3] https://betakit.com/apple-strikes-deal-to-acquire-canadian-database-software-startup-kuzu/
- [4] https://macdailynews.com/2026/02/12/apple-acquires-graph-database-maker-kuzu/
- [5] https://www.macobserver.com/news/apple-buys-graph-database-startup-kuzu-eu-filing-shows-more/
- [6] https://www.theregister.com/2025/10/14/kuzudb_abandoned/
- [7] https://news.ycombinator.com/item?id=45560036
- [8] https://ladybugdb.com/
- [9] https://gdotv.com/blog/weekly-edge-kuzu-forks-duckdb-graph-cypher-24-october-2025/
- [10] https://github.com/LadybugDB/ladybug/releases
- [11] https://docs.ladybugdb.com/installation/
- [12] https://github.com/LadybugDB/ladybug-wasm
- [13] https://bun.com/docs/runtime/nodejs-compat
- [14] https://github.com/Kineviz/bighorn
- [15] https://kineviz.github.io/bighorndb-docs/tutorials/
- [16] https://gdotv.com/blog/yearly-edge-graph-technology-news-recap-2025/
- [17] https://github.com/predictable-labs/ryugraph
- [18] https://github.com/predictable-labs/ryugraph/releases
- [19] https://www.vela.partners/blog/kuzudb-ai-agent-memory-graph-database
- [20] https://cocoindex.io/docs/targets/ladybug

---

## Open Questions

1. **Bun + LadybugDB @ladybugdb/core**: Does the napi binding actually load under Bun's runtime? Needs a 5-minute `bun add @ladybugdb/core && bun -e "require('@ladybugdb/core')"` smoke test.
2. **LadybugDB WASM completeness**: Is `@ladybugdb/wasm-core` production-usable in a browser context, or still aspirational?
3. **Bighorn development velocity behind zero releases**: Kineviz may be doing active internal development without publishing. Commit log check needed.
4. **RyuGraph Node.js binding**: No npm package for RyuGraph was found.
5. **Storage format compatibility across forks**: Do LadybugDB v0.15.x databases read files created by Kuzu v0.11.3?
6. **LadybugDB "Ladybug Memory" sponsor**: VC-funded or founder-funded?
7. **Apple's intended use**: Whether Apple will open-source a successor is unknown.

---

## Sub-Hypotheses

- **[ladybug-bun-napi]**: LadybugDB's `@ladybugdb/core` is loadable under Bun via Node-API compatibility — requires live runtime test, not web research.
- **[kuzu-freeze-stability]**: Kuzu v0.11.3 vendored as a static binary is safe to operate as rebuild-from-CAS index for 18–24 months — depends on CVE surface area not directly available in sources.
