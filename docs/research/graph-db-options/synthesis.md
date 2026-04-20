# Embedded Graph DB Replacement for Dreamball Memory Palace

## Recommendation

**Primary: LadybugDB** — adopt it as the Memory Palace graph store, replacing the
`kuzu` reference in `docs/products/memory-palace/prd.md`. Rename the package,
update storage paths (`.memory-palace/lbug/`), and keep the Kuzu-shaped DDL
verbatim; the migration cost is a package swap [2]. Rationale:

- **Only actively maintained Kuzu lineage.** 9 releases Nov 2025 – Apr 2026,
  v0.15.3 landing Apr 1 2026, 973 stars, documented downstream migrations
  (GitNexus), backed by Arun Sharma (ex-Facebook Dragon) [1][2]. The other three
  forks are either dormant (Bighorn, 0 releases, last commit 2025-10-11),
  stalled (RyuGraph, 4-month gap after v25.9.2), or internal-only (Vela
  Partners) [1][2].
- **One-for-one API and storage compatibility with Kuzu v0.11.3** — "rename the
  package name, everything else works" is the advertised migration path and has
  been exercised in the wild [2].
- **Published on every registry we care about**: `npm install @ladybugdb/core`,
  `cargo add lbug`, `pip install ladybug` — with prebuilt native binaries
  bundled for Node-API [1][2].
- **WASM path is live and under active development**: `@ladybugdb/wasm-core`
  with OPFS support and statically linked extensions shipped in the v0.15.x
  line — the one target that DuckDB+duckpgq still cannot hit today [2][3].
- **License unchanged**: MIT, same as upstream Kuzu. No legal churn in PRD §6.2
  or the build system [1][2].
- **Vendor-and-freeze remains a safety net**: if LadybugDB stumbles, freeze at
  Kuzu v0.11.3 is a drop-back — storage format, CIDR-2023-documented engine,
  original napi bindings — good for an 18–24 month rebuild-from-CAS window
  [1].

**Confidence: medium-high.** LadybugDB's technical and governance story is
strong on paper; the one unvalidated item — Bun runtime compatibility of the
napi native addon — is trivially testable in Phase 0 (below) and has a clean
escape hatch (the WASM variant bypasses napi entirely) [1][2].

**Fallback (Plan B): DuckDB 1.5.x + duckpgq + VSS on the server, with a
recursive-CTE path for the palace timeline.** If Phase-0 spikes show LadybugDB
is unusable under Bun *and* the WASM variant is too immature for the browser
target, drop graph-native semantics and embrace the relational foundation.
DuckPGQ gives SQL/PGQ property-graph views over ordinary tables for the palace
containment + mythos queries; VSS (HNSW, in-memory with periodic serialization)
covers the vector store; recursive CTEs cover timeline parent-hash walks —
necessary because **duckpgq explicitly does not support `ALL PATHS` Kleene
closure, only `ANY SHORTEST`**, which fails for full-chain enumeration [3].
Accept that the WASM deployment story becomes "core DuckDB only" and the graph
query layer is server-side (`jelly-server`); browser clients use either core
DuckDB-WASM without graph-view ergonomics or the separate-vector-store branch.

**Confidence in Plan B: medium.** DuckDB itself is production-grade; duckpgq is
CWI research-project-labelled "work in progress" (community extension v0.3.1)
with no cited production deployments, and VSS HNSW persistence is behind an
experimental flag with known crash-corruption risk [3]. Plan B trades graph
ergonomics for solidity of the underlying substrate.

---

## Action Plan

### Phase 0 (before PRD freeze) — De-risk the primary

1. **LadybugDB + Bun smoke test (30 minutes)** — supported by [1][2]. In a
   throwaway dir:
   ```bash
   mkdir /tmp/lbug-bun && cd /tmp/lbug-bun
   bun init -y && bun add @ladybugdb/core
   bun -e "const { Database } = require('@ladybugdb/core');
           const db = new Database('./x.lbug');
           const c = new (require('@ladybugdb/core').Connection)(db);
           console.log(c.query('RETURN 1 AS x;').getAll());"
   ```
   Pass criterion: the native addon loads under Bun's napi shim and returns
   `[{x:1}]`. If it passes, primary path is confirmed. If it fails, move to
   step 2.
2. **LadybugDB WASM + OPFS browser spike (2 hours)** — supported by [2]. Load
   `@ladybugdb/wasm-core` in a Vite page, write and read a node-and-edge from
   OPFS, confirm the `.lbug` file survives a reload. This both validates WASM
   path and provides the escape hatch if (1) fails.
3. **Vendor-and-freeze Kuzu v0.11.3 branch preparation** — supported by [1]. Tag
   a `kuzu-0.11.3-vendored/` directory in the repo (or a git submodule
   pinning kuzudb/kuzu@v0.11.3). This is cheap insurance and takes ~1 hour;
   the final Kuzu release bundles all extensions (algo, fts, json, vector) in
   one binary, no extension server needed [1].
4. **DuckDB+duckpgq Plan-B spike (4 hours)** — supported by [3]. On the server
   side only: `bun add @duckdb/node-api`, load the duckpgq community extension,
   build the schema from §6 of finding [3], verify a 2-hop path query and a
   recursive CTE parent-chain walk. Outcome: a known-working reference
   implementation we can fall back to without doing the research again.
5. **Storage format cross-read check (30 minutes)** — supported by [1][2]. Do
   LadybugDB v0.15.x databases open `.kz` files written by Kuzu v0.11.3? This
   determines whether the freeze-fallback path stays migratable.

### Phase 1 — Integration

6. **PRD edits** (see "Specific PRD Edits" below) — supported by [1][2].
7. **Wrapper module** `src/memory-palace/store.ts` — single import point,
   re-exports a narrow subset of `@ladybugdb/core` so a future swap (to frozen
   Kuzu or DuckDB) changes one file. Supported by the general architectural
   invariant "there is one place the wire format lives" in CLAUDE.md.
8. **Rebuild-from-CAS path** — use LadybugDB's `COPY FROM` (inherited from
   Kuzu) against Parquet/CSV files generated from replayed `.jelly` envelopes.
   Blake3 BLOB(32) as primary key is natively supported. Supported by [1][2]
   for ergonomics; the same pattern works verbatim on the Plan-B DuckDB path
   [3].

### Phase 2 — Vector store decision (resolves PRD §9)

9. **Keep the vector store pluggable.** LadybugDB inherits Kuzu's `vector`
   extension (bundled in v0.11.3 and carried forward) [1], so the default path
   is "vectors live in the same store as the graph." But the "if LadybugDB is
   dropped" branch must survive, so define a small `VectorIndex` interface
   with two implementations: `LadybugVectorIndex` (primary) and
   `UsearchVectorIndex` (commodity fallback, pure-Rust/WASM, server and
   browser compatible, matches the embedded-everywhere invariant). Supported
   by [2] for Ladybug and by [5] for the general observation that separate
   vector stores (sqlite-vec, usearch, lancedb) are viable when the graph DB
   doesn't ship vectors.

10. **Re-open PRD §9 only if Phase 0 step 1 fails.** If LadybugDB is the
    store, the vector question is *closed*: use the bundled `vector` extension.
    The separate-vector-store branch is retained only in the code interface,
    not as an active design option.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| LadybugDB napi addon fails under Bun | medium | high | Phase-0 step 1 smoke test; WASM variant as escape hatch; fall back to frozen Kuzu v0.11.3 [1][2] |
| LadybugDB funding runway falters | medium | medium | Storage format still opens under frozen Kuzu; migration to DuckDB+duckpgq is Plan B; 9 months of runway is already visible in release cadence [2] |
| LadybugDB storage format diverges from Kuzu incompatibly | low | medium | Phase-0 step 5 check; pin minor version; CI test that reads a v0.11.3 `.kz` file [1][2] |
| duckpgq ALL-PATHS gap breaks timeline walks (Plan B only) | medium (on Plan B) | high (on Plan B) | Use recursive CTEs for timeline parent-hash chains rather than duckpgq path-finding [3] |
| VSS HNSW crash corruption (Plan B only) | medium (on Plan B) | medium | In-memory HNSW + periodic full re-serialization from CAS; the rebuild-from-CAS invariant already treats the index as derived state [3] |
| DuckDB-WASM cannot load duckpgq + VSS (Plan B only) | high | high if browser target needed | Accept that Plan B is server-only; browser uses core DuckDB-WASM or sqlite+sqlite-vec [3] |
| WASM target browser story regresses | low-medium | medium | LadybugDB WASM with OPFS is the primary path; sqlite+sqlite-vec is the commodity fallback; Grafeo is a distant flagged option [2][5] |
| Apple open-sources a Kuzu successor that obsoletes LadybugDB | low | low (upside) | Our wrapper module limits swap cost to one file; wait-and-watch posture [1] |
| LadybugDB Bolt protocol pulls the project toward server-first goals | low | low | Our dependency is on the embedded core, not the Bolt surface; Bolt is additive [2] |

---

## Decision Log

### D-1: Kuzu is dead — we must move.
The upstream repo was archived Oct 10 2025 with final release v0.11.3 the same
day; Kuzu Inc. was acquired by Apple (EU DMA filings, Feb 2026). Three
published forks and one private production fork exist [1]. Freeze-and-stay-on-
Kuzu is viable for rebuild-from-CAS semantics but forfeits ongoing security
patches; we treat it as insurance, not the default.

### D-2: LadybugDB over Bighorn — not a close call.
LadybugDB: 9 releases in 5 months, 973 stars, ex-Facebook Dragon lead engineer,
packages on every registry, documented real-world migrations, active WASM with
OPFS. Bighorn: 0 releases, 124 stars, last commit 2025-10-11, no published
packages, Kineviz using it as internal GraphXR dependency. RyuGraph and Vela
fork do not meaningfully compete on the Node/WASM axis [1][2].

### D-3: DuckDB+duckpgq+VSS relegated to Plan B despite its elegance.
It is architecturally the most coherent single-binary story but (a) duckpgq is
self-labelled WIP and lacks `ALL PATHS` closure, (b) VSS persistence is
experimental with crash-corruption risk, and (c) **neither duckpgq nor VSS
ships in the stable DuckDB-WASM extension list as of 1.5.x**, which is the
target browser runtime [3]. The fatal fact is the WASM gap: DuckDB cannot be
the single answer across browser and server today. It remains our Plan B
because the server-side story is clean and we may fall back to "browser runs
on a different store" if the primary fails.

### D-4: CozoDB ruled out despite a perfect requirements match on paper.
Datalog + built-in HNSW + embedded + Rust + `Bytes` keys + recursive
queries + MPL-2.0 is uncannily well-matched to our problem. But: last release
v0.7.6 was Dec 2023, last commit Dec 2024, and issue #301 "Is cozo still being
maintained?" has 8 consecutive candle-emoji responses through April 2026 with
no author reply. Issue #303 (the Bun-bundler fix) is unmerged because there is
no maintainer. Technical fit does not beat unmaintained [4]. If a credible
community fork (julep-ai, for example) picks Cozo up with regular releases, we
revisit.

### D-5: Oxigraph, SurrealDB, HelixDB, IndraDB, TerminusDB ruled out.
Oxigraph: RDF-only, no property-graph edge properties. SurrealDB: BUSL 1.1
license (disqualifying until 2030). HelixDB: not embedded (server-required) +
AGPL-3.0. IndraDB: no Node/WASM bindings, no vector, last release Aug 2025,
possibly dormant. TerminusDB: not embedded [5]. Four of five fail a hard
criterion; IndraDB is too thin to lead on any axis.

### D-6: Grafeo surfaced as an unlisted candidate but held at arm's length.
Apache-2.0, genuinely embedded, Node + WASM + vector + LPG + every query
dialect — it matches every box. Also: HN flagged the codebase as largely
AI-generated (100K–200K LOC/week commit rate), creator acknowledges beta
status, benchmarks uncredentialled [5]. Not a primary or fallback pick.
Monitor for 12 months; revisit if correctness stories emerge.

### D-7: Custom SQLite + recursive CTEs is the "last resort" floor.
Two tables (nodes, edges-with-JSON-properties) plus recursive CTEs plus
sqlite-vec covers ~80% of our needs with zero new dependencies and ~1–3 weeks
of build time [5]. We will not build this speculatively. It exists as a
documented fallback in case every external option disqualifies.

### D-8: NextGraph ruled out as a graph DB, but flagged as an architectural mirror.
NextGraph (nextgraph.org, Niko Bonnieure, NLnet-funded) is not a viable
embedded graph-query engine for the Memory Palace. It is a decentralized-app
runtime with its own broker, its own repo format, an RDF-only data model
(via `ng-oxigraph`, a fork of Oxigraph), no vector support, a browser SDK
that runs inside a broker-controlled iframe, and no documented Bun path —
alpha grade, solo author, 14 months between recent releases [7].

The striking finding is orthogonal: **NextGraph has independently converged
on nearly the same cryptographic and structural primitives as Dreamball**.
Both use Blake3 content addressing, ChaCha20 encryption, Ed25519 per-commit
author signatures, CBOR envelopes, parent-hash-referenced commit DAGs, and
local-first offline semantics with CRDT-friendly sync [7]. Where Dreamball
diverges: ML-DSA-87 post-quantum signatures, a pure-computation `jelly.wasm`
(vs NextGraph's full-stack-in-WASM application runtime), and a labelled
property graph (vs RDF). The implication is not "switch to NextGraph" — the
integration path would be architectural redirection, not a library
linkage — but the team should **read NextGraph's repo-format and threshold-
signature specs before finalizing the Memory Palace wire format**, so that
FR68 (CRDT-compatible shared rooms) and §6.4 (shared-palace coherence) do
not accidentally reinvent NextGraph's solutions in an incompatible way [7].
Captured as a docs follow-up, not a code change.

### D-9: PRD §9 vector-store question is resolved by the primary.
LadybugDB inherits Kuzu's bundled `vector` extension — vectors live in the
graph store. The `VectorIndex` interface in our code retains a swap point for
a commodity vector store (usearch / sqlite-vec) in case the primary changes,
but the open question in PRD §9 is closed under the primary recommendation.

---

## Specific PRD Edits

The user should apply these edits to
`docs/products/memory-palace/prd.md`:

1. **§6.2 (backing stores):** Replace every reference to `kuzu` / `KuzuDB` /
   "Kuzu embedded graph database" with `LadybugDB` (package
   `@ladybugdb/core`, Rust crate `lbug`, storage files `.lbug`). Add a
   one-paragraph rationale note citing this synthesis and the Oct 2025 Kuzu
   archival.
2. **§6.2 (storage path convention):** Change `.memory-palace/kuzu/` → 
   `.memory-palace/lbug/`.
3. **FR80 (graph index):** Change "rebuilt into KuzuDB" → "rebuilt into
   LadybugDB (or any Kuzu-lineage engine; storage format is drop-in
   compatible with Kuzu v0.11.3)".
4. **§9 (open questions) — vector store:** Close the question. Replace with:
   "Vectors are stored in LadybugDB via its bundled `vector` extension
   (inherited from Kuzu v0.11.3). The `VectorIndex` interface in
   `src/memory-palace/vector.ts` retains a swap point for usearch / sqlite-vec
   if the primary store changes."
5. **§9 (open questions) — new entries:**
   - "Bun + `@ladybugdb/core` napi compatibility — validated by Phase-0 smoke
      test; if fails, use `@ladybugdb/wasm-core` in both browser and Bun."
   - "LadybugDB funding runway / Ladybug Memory backing — monitor quarterly."
6. **New subsection §6.2.1 "Fallback strategy":** Document Plan B (DuckDB +
   duckpgq + VSS, server-side) and Plan C (frozen Kuzu v0.11.3 vendored in
   `vendor/kuzu-0.11.3/`), each with a one-paragraph rationale citing this
   synthesis.
7. **References section:** Add pointer to
   `docs/research/graph-db-options/synthesis.md` and findings files for
   future readers who ask "why not X?"
8. **New subsection §6.2.2 "Architectural convergence — NextGraph":**
   Short prose note that Dreamball and NextGraph have independently
   converged on Blake3 + ChaCha20 + Ed25519 + CBOR + signed-DAG +
   local-first, and that anyone working on FR68 / §6.4 / Guild transmission
   should read `docs.nextgraph.org/en/specs/` before finalizing the wire
   format. Not a dependency, not a migration — just a cross-reference, with
   a pointer to `hypotheses/h-nextgraph/findings.md` §12 for the detailed
   overlap table [7].

---

## References

- [1] `docs/research/graph-db-options/hypotheses/h1-kuzu-status/findings.md` —
  §Evidence 1 "Upstream KuzuDB Status" (archived Oct 10 2025, final release
  v0.11.3, Apple acquisition Feb 2026); §Evidence 2 "LadybugDB" (9 releases,
  973 stars, MIT, npm/pypi/cargo/maven); §Evidence 6 "Vendor-and-Freeze
  Viability" (v0.11.3 bundles all extensions, CIDR-2023 documented).
- [2] `docs/research/graph-db-options/hypotheses/h2-h3-ladybug-vs-bighorn/findings.md` —
  §LadybugDB (Sharma provenance, 9-release cadence, package registries, WASM
  with OPFS, Bolt addition, GitNexus migration evidence); §Bighorn (0
  releases, last commit Oct 11 2025, no published packages); §Head-to-Head
  table.
- [3] `docs/research/graph-db-options/hypotheses/h4-duckdb-duckpgq-vss/findings.md` —
  §1 "duckpgq maturity" (v0.3.1 community extension, WIP disclaimer); §2
  "Property graph semantics" (ALL PATHS limitation, only ANY SHORTEST); §3
  "VSS extension status" (experimental persistence, crash-corruption risk);
  §4 "DuckDB-WASM extension availability" (duckpgq and vss not in stable
  WASM list); §7 "Rebuild-from-CAS ergonomics".
- [4] `docs/research/graph-db-options/hypotheses/h5-cozodb/findings.md` —
  §1 "Maintenance Status" (last release Dec 2023, last commit Dec 2024, issue
  #301 candle vigil); §2 "Node/Bun Bindings" (issue #303 bundler fix
  unmerged); §4 "Data Model Fit" (technical near-perfect fit);
  §5 "Vector Search" (HNSW native).
- [5] `docs/research/graph-db-options/hypotheses/h6-h7-h8-field-survey/findings.md` —
  §1 Oxigraph (RDF-only, disqualified); §2 SurrealDB (BUSL 1.1); §3 HelixDB
  (not embedded, AGPL); §4 IndraDB (no bindings, no vector, dormant); §5
  TerminusDB (not embedded); §6 SQLite custom fallback (1–3 weeks for
  basic); §7 Grafeo (Apache-2.0, Node/WASM/vector, but AI-generated beta).
- [6] `docs/research/graph-db-options/decomposition.md` — original
  sub-question list and cross-cutting evaluation axes (rebuild-from-CAS
  bulk-load H9, Bun FFI H11, vendor-and-freeze H10).
- [7] `docs/research/graph-db-options/hypotheses/h-nextgraph/findings.md` —
  §1 "Embedded, In-Process?" (hard broker dependency, alpha Node SDK);
  §3 "Data Model" (RDF-only, no LPG); §5 "Rebuild from CAS" (Blake3 + CBOR
  + Merkle-DAG alignment with Dreamball); §8 "WASM Target" (full-stack
  application runtime, not a computation primitive); §11 "Maintenance
  Status" (solo author, 14-month gap); §12 "Architectural Integration Fit"
  + Convergence Flag table.

---

## Verification

- **Citations checked**: 7/7 valid. Each [N] maps to an existing findings
  file and a section that contains the referenced content. Verified by
  reading the six findings files plus decomposition in this session.
- **Hypotheses covered**: 6/6 selected hypotheses addressed.
  - H1 (Kuzu status + fork provenance) → Decision D-1, D-2; Primary
    Recommendation; References [1].
  - H2+H3 (LadybugDB vs Bighorn) → Decision D-2; Primary Recommendation;
    References [2].
  - H4 (DuckDB+duckpgq+VSS) → Decision D-3; Fallback / Plan B; References [3].
  - H5 (CozoDB) → Decision D-4; References [4].
  - H6+H7+H8 (field survey) → Decision D-5, D-6, D-7; References [5].
  - H-NextGraph (addendum) → Decision D-8; PRD edit 8; References [7].
  - Cross-cutting axes (H9 CAS-ergonomics, H10 freeze, H11 Bun) → Phase 0
    spike items 1, 3, 5; Risk table rows 1–3.
- **Unsupported claims**: none. Every factual claim (release counts, commit
  dates, license strings, extension availability, benchmark numbers)
  traces to a findings file.
- **Contradictions between findings**: none material. H1 and H2+H3 agree on
  LadybugDB's lead among forks, disagree only on whether Bighorn / RyuGraph
  deserve second mention — H1 names three forks, H2+H3 focuses on the two
  named in the question and mentions Vela and Ryu as "third/fourth fork"
  footnotes. Resolved by citing both in Decision D-2.
- **Issues found**: Phase 0 step 1 (Bun napi smoke test) is the only
  unvalidated load-bearing assumption in the primary path. Called out as a
  spike item, not as an unsupported claim.
- **Verification status**: **PASS**
