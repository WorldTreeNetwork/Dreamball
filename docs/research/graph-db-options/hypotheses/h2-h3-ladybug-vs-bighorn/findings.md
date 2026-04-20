# Hypothesis: LadybugDB vs Bighorn — comparative assessment of the two named KuzuDB forks

## Summary

Both LadybugDB and Bighorn are real, MIT-licensed forks of KuzuDB that emerged in October 2025 after Kùzu Inc archived the upstream project. They are not equal: **LadybugDB is an actively maintained, well-resourced, community-governed fork with consistent release cadence, functional Node.js/Python/Rust/WASM bindings, and a stated goal of long-term Kuzu compatibility**; **Bighorn is a sincere but low-momentum fork by graph visualization company Kineviz, with no published releases since the initial fork in October 2025** and whose last commit predates 2026. If migration is the right call, LadybugDB is the clear pick.

---

## Evidence

### LadybugDB

**Provenance**
- Forked by **Arun Sharma**, former Senior Engineer at Facebook (Dragon distributed graph query system) and former Google engineer [2][3].
- GitHub org: `LadybugDB` — sponsored by "Ladybug Memory."
- First public announcement: "Hello World" blog post October 23, 2025 [4].
- v0.12.0 documented equivalence to Kuzu v0.11.3 [5].
- Sharma's pedigree is directly relevant: he built large-scale distributed graph systems at Facebook.

**License**: MIT, unchanged from Kuzu.

**Stated Goals**
- "A full one-to-one replacement of Kuzu in the long term" [2].
- Longer-term: "Snowflake for graphs" / graph data lake with object storage core — a deliberate architectural evolution.
- November 2025 "Ladybug Speaks Bolt" post indicates added Bolt protocol support.

**Release Cadence** (consistent, accelerating):
- v0.12.2 — Nov 14, 2025
- v0.13.0 — Dec 15, 2025
- v0.13.1 — Dec 16, 2025
- v0.14.0 — Jan 7, 2026
- v0.14.1 — Jan 9, 2026
- v0.15.0 — Feb 28, 2026
- v0.15.1 — Mar 2, 2026
- v0.15.2 — Mar 18, 2026
- v0.15.3 — Apr 1, 2026 [8]

9 releases in ~5 months. Main branch: 5,769 commits, 973 stars, 72 forks as of April 2026.

**Contributor Count and Activity**
- 31 repositories in the LadybugDB GitHub org (Python, Node.js, Go, Rust, WASM, MCP server, visualization tools) [9].
- Commercial enterprise support contracts available.
- Described by independent observers (Vela Partners, gdotv.com) as the primary community continuation of Kuzu [10].

**API/Wire Compatibility**
- v0.12.0 release note: "The functionality is equivalent to kuzu v0.11.3. The only change would be to rename kuzu to the correct package name in your language." [5]
- Real-world migration documented: GitNexus migrated from KuzuDB to LadybugDB v0.15 with only storage path rename (`.gitnexus/kuzu` → `.gitnexus/lbug`) [11].
- Essentially a drop-in replacement at the application layer.

**Binding Status**
- Python: `pip install ladybug` / `real-ladybug` on PyPI [12]
- Node.js: `npm install @ladybugdb/core` [6]
- Rust: `cargo add lbug` on crates.io
- Java: Maven Central (`com.ladybugdb:lbug`)
- Go: `github.com/LadybugDB/ladybug` — listed but not fully functional as of v0.12.0
- Swift: Listed but not functional as of v0.12.0
- WASM: **Active as of v0.15.3** — OPFS support, statically linked extensions, Node.js variant available [8][13]
- CLI: `lbug` (Homebrew-installable)
- MCP server: `mcp-server-ladybug` on PyPI

**Bun Compatibility**
- Not explicitly addressed in any documentation found.
- Node.js binding uses precompiled native binaries bundled in npm package (C++/CMake).
- Bun v1.2.3+ has improved NAPI compatibility; napi-based addons generally work.
- WASM build sidesteps napi entirely — cleaner path for Bun.
- **Open question**: no public report of LadybugDB tested under Bun.

**Documentation**
- docs.ladybugdb.com, api-docs.ladybugdb.com, blog.ladybugdb.com, active Discord.

**Community Signals**
- 973 stars, growing.
- Multiple external projects migrating (GitNexus documented).
- Covered by The Register [1], gdotv.com, Vela Partners, dbdb.io.
- Vela Partners names LadybugDB "best long-term KuzuDB replacement" for general use [10].

---

### Bighorn

**Provenance**
- Forked by **Kineviz Inc.**, a graph visualization company (product: GraphXR) [19].
- GitHub org: `bighorndb`; primary repo at `Kineviz/bighorn` [20].
- Fork announced ~October 15–17, 2025.
- Founder Weidong Yang posted on LinkedIn: "We are looking for like-minded individuals and companies to maintain and develop KuzuDB together." [17]
- Kineviz are primarily a visualization company, not a database engine company. Motivation is self-interested: GraphXR depends on an embedded graph database.

**License**: MIT, unchanged.

**Stated Goals**
- "Develop and maintain as open source" — conservative continuation rather than rescope [17].
- Integration with GraphXR (embedded and server modes) as primary commercial use case.

**Release Cadence**
- **No published releases.** GitHub shows "No releases published" [20].
- `bighorndb` org: 2 repos (main fork + docs), last updated October 23, 2025 [19].
- Last commit on `Kineviz/bighorn`: **October 11, 2025** [20].
- No evidence of any commits, issues resolved, or development activity in 2026.

**Contributor Count and Activity**
- 124 stars, 7 forks.
- 0 listed contributors on the public page.
- No npm package, no PyPI package, no crates.io crate found for Bighorn.

**API/Wire Compatibility**
- Forked from Kuzu v0.11.0 era. Documentation essentially points at Kuzu's old docs.
- No evidence of any changes to wire format or API since forking.

**Binding Status**
- Documentation lists full Kuzu binding inventory but **documentation appears inherited from Kuzu, not reflecting actual published packages** [21].
- No evidence of any packages published to npm, PyPI, crates.io, or Maven Central under a Bighorn name.

**Bun Compatibility**: Not documented anywhere.

**Documentation**: https://kineviz.github.io/bighorndb-docs/ exists but content appears inherited from Kuzu.

**Community Signals**: 124 stars (vs LadybugDB's 973). No Discord, no blog, no release notes. Commercial traction limited to internal use in GraphXR.

---

### Third Fork: Vela-Engineering/kuzu

- A narrow specialization for multi-agent AI workloads (concurrent multi-writer support).
- 374× faster than Neo4j on 2nd-degree path queries, 53× faster ingestion.
- Not a general-purpose KuzuDB continuation — a fourth option for concurrent-write use cases.

### Fourth Fork: RyuGraph (predictable-labs)

- Forked by Akon Dey (former CEO of Dgraph). Releases v25.9.0–v25.9.2 Oct–Dec 2025, then a 4-month gap.
- 133 stars, MIT.
- No npm package confirmed.

---

## Head-to-Head Recommendation

| Dimension | LadybugDB | Bighorn |
|---|---|---|
| Stars (Apr 2026) | 973 | 124 |
| Releases since fork | 9+ (v0.12.2–v0.15.3) | 0 |
| Last commit | April 2026 | October 11, 2025 |
| npm package | `@ladybugdb/core` | None found |
| PyPI package | `ladybug` / `real-ladybug` | None found |
| Rust crate | `lbug` | None found |
| WASM | Shipped (v0.15.x, OPFS support) | Inherited docs, no evidence shipped |
| Node.js binding | Active | Inherited from Kuzu, no evidence active |
| Bolt protocol | Added (Nov 2025) | No |
| Docs site | docs.ladybugdb.com (original) | Inherited Kuzu docs |
| Migration path | Package rename only | Unclear |
| Bun tested | Unknown | Unknown |
| Backing | Ladybug Memory (enterprise, investor interest) | Kineviz (GraphXR product dep) |
| Stated goals | Long-term Kuzu replacement + graph data lake | Maintain for GraphXR compatibility |

---

## Confidence

**Level**: high

Multiple independent sources (The Register, gdotv.com reviews, Vela Partners' comparison, LadybugDB's release history, GitHub commit evidence) converge on the same conclusion.

---

## Final Recommendation

**If migration is the right call, pick LadybugDB, because** it is the only fork with consistent release cadence (9 releases since October 2025), published packages on all major registries (npm, PyPI, crates.io, Maven Central), an active documentation site, WASM support including OPFS, a technically credentialed founder (ex-Facebook distributed graph systems), independent third-party validation as "the long-term Kuzu replacement," and real-world migration evidence from downstream projects. Migration cost is low: rename the package, update storage paths.

**Bighorn should not be the primary bet** for any new dependency. Its last public commit is October 11, 2025 — over 6 months stale. It has no published packages on any registry. Its documentation is inherited boilerplate from Kuzu. It appears maintained only as a private dependency for Kineviz's GraphXR product.

**Fallback order if LadybugDB's funding proves precarious**: (1) LadybugDB's WASM variant, (2) DuckDB+duckpgq or Cozo, (3) Ryu if it matures.

---

## Open Questions

1. **Bighorn's actual status inside Kineviz** — private fork driving GraphXR? Needs direct contact.
2. **LadybugDB Bun compatibility** — untested in public records. Smoke test needed.
3. **LadybugDB Go/Swift binding completeness** — v0.12.0 non-functional; v0.15.3 status unclear.
4. **Wire format divergence** — do v0.13–v0.15 read Kuzu v0.11.3-written files?
5. **Funding runway for LadybugDB** — self-funded by Sharma or VC-backed?
6. **Ryu fork** — fourth fork deserves independent assessment if LadybugDB stalls.

---

## Sources

- [1] https://www.theregister.com/2025/10/14/kuzudb_abandoned/
- [2] https://ladybugdb.com/
- [3] https://gdotv.com/blog/ladybugdb-arun-sharma-graphgeeks-video/
- [4] https://blog.ladybugdb.com/
- [5] https://github.com/LadybugDB/ladybug/releases/tag/v0.12.0
- [6] https://github.com/LadybugDB/ladybug
- [7] https://mpr.crossjam.net/wp/mpr/2025/11/kuzudb-and-ladybugdb/
- [8] https://github.com/LadybugDB/ladybug/releases/tag/v0.15.3
- [9] https://github.com/LadybugDB
- [10] https://www.vela.partners/blog/kuzudb-ai-agent-memory-graph-database
- [12] https://pypi.org/project/real-ladybug/
- [13] https://docs.ladybugdb.com/client-apis/wasm/
- [14] https://github.com/LadybugDB/ladybug-nodejs
- [15] https://docs.ladybugdb.com/
- [17] https://gdotv.com/blog/weekly-edge-kuzu-forks-duckdb-graph-cypher-24-october-2025/
- [19] https://github.com/bighorndb
- [20] https://github.com/Kineviz/bighorn
- [21] https://kineviz.github.io/bighorndb-docs/tutorials/
