# CRDT Approaches for Dreamball Memory Palace Multi-Writer Merge

*Research conducted 2026-04-21 for FR68 (shared-room multi-writer) and FR60g
(mythos divergence-resolution). Captured verbatim from the morphist
investigator agent.*

## Summary

For three of the four Dreamball merge problems (`jelly.layout`,
`jelly.action`, `jelly.mythos`), the protocol spec already describes a
Merkle-CRDT by construction — the answer is a bespoke DAG walker, not an
external library. For the fourth (memory-graph triples on the oracle
Agent), no production CRDT library provides a first-class LPG container;
a composable build from OR-Set + LWW-Map primitives is the right path,
with Loro optionally providing the property-value layer. No single
embeddable library solves all four problems.

---

## The four merge problems and their shapes

| Structure | Shape | Key challenge |
|---|---|---|
| `jelly.layout` | Map of `{child-fp → (position, facing)}` | Concurrent move of same item |
| `jelly.action` timeline | Hash-chained DAG, multi-parent already legal | G-Set union of signed nodes |
| `jelly.mythos` canonical chain | Append-only signed chain per DreamBall | Fork detection + quorum canonicalization |
| Memory-graph triples | LPG — nodes + typed edges with float/enum/sig properties | Property edits, tombstone-safe add/remove |

---

## Candidates evaluated

### Automerge (Rust/TS/WASM)

- **Maturity**: Production. v3.2.5 released March 2025. ~10× memory
  reduction in v3. Peritext rich-text fully integrated.
- **License**: MIT
- **Data types**: Map (LWW per key), List (RGA), Text (Peritext),
  Counter. No native graph or tree container.
- **WASM/Bun story**: `@automerge/automerge-wasm` ships two WASM variants
  (Node.js bindings and pure-web build). Bun implements Node-API and
  loads the same WASM bundles Node.js does.
- **Binary format / DAG**: DAG of changes, each SHA-256 content-addressed
  with a `dependencies` array. Actor ID + sequence number identify the
  author. **No built-in cryptographic signing** — authorship asserted,
  not verified.
- **Gap for jelly**: SHA-256 vs Blake3 mismatch for `jelly.action`;
  adopting Automerge would require a translation layer. Mismatch cost
  exceeds benefit.

### Yjs (TypeScript; YATA algorithm)

- **Maturity**: Very high. 900k+ weekly downloads. Most widely deployed
  collaborative-editing CRDT in production.
- **License**: MIT
- **WASM/Bun story**: Pure TypeScript — works in browser, Bun, Deno,
  Node out of the box.
- **Gap for jelly**: Yjs does not model history as a content-addressed
  DAG. Its private binary encoding is not compatible with jelly's
  per-action signing model.

### Loro (Rust/WASM; Replayable Event Graph)

- **Maturity**: v1.0.0 stable encoding locked October 2024. v1.8.2
  current (April 2026). Multi-threaded support added v1.8.0 (Sep 2025).
  Based on Replayable Event Graph — same lineage as Diamond Types /
  eg-walker.
- **License**: MIT
- **Data types**: Text (Fugue), Rich Text, List, **MovableList
  (concurrent move supported)**, Map (LWW), **Tree (movable-tree CRDT —
  Kleppmann et al. algorithm)**, Counter, EphemeralStore. MovableList
  and Tree are the key differentiators over Automerge/Yjs.
- **WASM/Bun story**: Pure WASM delivery via `loro-crdt` npm package.
  WASM loads in browser and in Bun's WASM runtime. No napi native addon.
- **LPG fit**: Medium for Trees/Forests; no general graph. Tree
  container enforces single-parent structure. For LPG edges, a
  Map-of-Maps pattern works but must be manually maintained. Loro
  **does not** support arbitrary graphs.
- **Gap for jelly**: Internal REG event log is not exposed as a
  content-addressed DAG compatible with Blake3/jelly. Signing is
  external.

### Fugue (Weidner et al., 2023; IEEE TPDS paper published Nov 2025)

- **Maturity**: Academic / reference-implementation grade. "The Art of
  the Fugue: Minimizing Interleaving in Collaborative Text Editing"
  (Weidner, Gentle, Kleppmann) first circulated as arXiv 2305.00583 in
  May 2023; formal publication IEEE Transactions on Parallel and
  Distributed Systems 36(11):2425–2437, November 2025.
- **License**: the reference implementation `@mweidner037/list-fugue`
  is MIT.
- **Claim to fame**: the **first** list/text CRDT proven to satisfy
  *maximal non-interleaving*. The paper establishes that every prior
  list CRDT (RGA, YATA, Logoot, Treedoc, etc.) and every OT family
  exhibits an interleaving anomaly — concurrent insertions at the
  same position can produce character-level interleaved garbage.
  Fugue solves this; two variants (Fugue-Tree and Fugue-List) are
  proven semantically equivalent.
- **Data types**: text/list only. Not a full CRDT library — a primitive.
- **WASM/Bun story**: pure TypeScript reference implementation; no
  runtime dependency beyond the standard library. Drops into Bun and
  the browser without an extra WASM instance.
- **Where Fugue actually matters for Dreamball**:
  - `jelly.inscription` concurrent editing (FR72, Growth tier — if
    two scribes edit the same inscription at the same position, Fugue
    is the algorithm that avoids the interleaving anomaly).
  - Underlies Loro's Text container (Loro picked Fugue over RGA/YATA
    specifically for non-interleaving). Choosing Loro for
    inscription editing transitively picks Fugue.
  - **Not relevant** for `jelly.action` (a DAG-of-events, not a
    sequence of character positions), `jelly.layout` (a map, not a
    sequence), or `jelly.mythos` (a per-custodian chain with
    quorum-resolved forks, not an interleaved text edit).
- **Verdict**: the right *text-level* algorithm when FR72
  concurrent-inscription editing becomes a requirement. MVP doesn't
  need it — inscriptions are single-author. When it does become a
  requirement, reach for Loro (which ships Fugue internally) rather
  than adopting the reference `@mweidner037/list-fugue` directly,
  unless size/tree-shaking becomes a pressure point.

Sources: [22][23][24]

### Diamond Types / eg-walker

Research-grade. GitHub "WIP" as of early 2026. EuroSys 2025 paper
(Gentle + Kleppmann). No stable release, no npm/WASM package. Loro is
the production-ready descendant. **Verdict**: track as theoretical
foundation; do not adopt directly.

### Merkle-CRDTs (Sanjuan et al., 2020; IPFS Cluster pattern)

Published concept (arXiv:2004.00107), not a library. Core idea: use a
Merkle-DAG as the transport and persistence layer for any CRDT. The
DAG's content-addressing gives logical clocks for free. Sync = DAG
traversal comparing head CIDs.

The **ipfs-log** (OrbitDB's append-only log) is the closest production
reference: each entry is a signed envelope with parent-hash references,
forming a causal DAG. ipfs-log is archived (moved into OrbitDB 2.x) but
the pattern is sound.

**Critical finding**: `jelly.action` is **already a Merkle-CRDT** by
construction. Each action is Blake3-addressed, carries `parent-hashes[]`,
is signed by the actor, and `head-hash` is the current leaf. Merging two
timelines is G-Set union of DAG nodes followed by re-computing the
multi-head set. No library needed — just a DAG walker.

### Peritext / Ink & Switch

Now fully integrated into Automerge. The standalone `peritext` repo is
a prototype only. Relevant to `jelly.inscription` multi-author editing
(FR72, Growth tier). Not an immediate concern — inscriptions are
write-once or single-author in Phase 0.

### OR-Set / LWW-Map / MV-Register primitives

Key primitives for memory-graph construction:

| Primitive | Dreamball use-case fit |
|---|---|
| **G-Set** | `jelly.action` DAG node set — all adds, no deletes; perfect fit |
| **OR-Set** | Room membership, tag sets, memory nodes and edges |
| **LWW-Register** | Position/facing per item in `jelly.layout`; simplest |
| **LWW-Map** | Full `jelly.layout` — each child-fp maps to an LWW position |
| **MV-Register** | Both concurrent positions shown as ghost placements |
| **OR-Map** | Only adds value over LWW-Map when concurrent key deletion matters |

The move-semantics literature (Kleppmann, PaPoC 2020) confirms: for
concurrent moves, assign UIDs independent of position, store position
as a mutable LWW property. MV-Register surfaces both positions; LWW
discards the loser. For the ghost-placement UX spec, MV-Register is the
correct primitive.

### Graph CRDTs (academic)

No production CRDT library as of April 2026 provides a first-class LPG
container with typed, weighted edges and concurrent property edits.

- **2P2P-Graph** (classic): Too restrictive — once removed, vertex can
  never re-appear; no edge properties.
- **DAG CRDT (Borth, PaPoC '25)**: Most recent academic work on DAG
  CRDTs. Confirms the `jelly.action` DAG design is theoretically sound
  — a DAG with add-only edges is a G-Set of (parent, child) pairs,
  trivially convergent.
- **NextGraph Graph CRDT**: Uses RDF OR-set (SU-set formalism).
  Explicitly rejected as data model by jelly's spec.

---

## NextGraph framework — diff note

NextGraph combines three CRDT models: Graph CRDT (RDF OR-set),
Automerge, and Yjs. Commits are Ed25519-signed per author; the commit
DAG references predecessors (DEPS) and acknowledgments (ACKS).
Threshold cryptography for quorum operations — architecturally the
closest external system to Dreamball.

**Diff against Dreamball**:

- NextGraph uses RDF triples for graph data; jelly explicitly rejects
  RDF as the data model.
- NextGraph signing is Ed25519 only; Dreamball requires hybrid
  Ed25519+ML-DSA-87.
- NextGraph's quorum scheme differs from jelly's Guild-admin policy.
- Adopting NextGraph would replace jelly's entire envelope / signing /
  storage stack.
- NextGraph's *design choices* (combined CRDT models, causal-DAG
  commits with per-author sigs, quorum-validated root mutations) are
  strong external validation of Dreamball's own architecture.
  NextGraph explicitly lists Loro as a future integration candidate.

---

## Answers to the four specific questions

### Q1: `jelly.layout` concurrent move — LWW vs OR-Map?

**Use MV-Register per item, not pure LWW and not OR-Map.**

LWW-per-item silently discards the losing move. OR-Map adds value only
when concurrent *deletion* of a key matters (rarely relevant for
layout). The ghost-placement spec ("rejected-action ghost") calls for
surfacing both positions, which is exactly what MV-Register does.

Implementation: the `jelly.layout` envelope holds
`child-fp → [placement...]`. Single entry in the non-conflicted case.
When merge detects two concurrent writes (same `child-fp`, same
predecessor hash, different actors), both entries are retained; the
renderer shows one as primary and one as ghost. The custodian emits a
follow-up multi-parent `move` action to resolve. This is ~80 lines of
Zig/TypeScript operating on the existing action DAG — no external CRDT
library.

### Q2: `jelly.action` timeline DAG — Automerge/Loro drop-in or bespoke walk?

**Bespoke walk. `jelly.action` is already a Merkle-CRDT; complete it by
pluralizing `head-hash` to `head-hashes`.**

The protocol spec already describes: Blake3-addressed actions,
`parent-hashes[]`, per-actor Ed25519+ML-DSA-87 signatures, `head-hash`
leaf pointer. Merge is G-Set union of action sets + re-compute heads.
The Sanjuan et al. Merkle-CRDT pattern and ipfs-log both confirm this at
production scale.

Automerge uses SHA-256, has no signing, and models map/list/text — not
domain action logs. Loro's internal REG is not exposed as a Blake3 DAG.
Neither is a drop-in; both require more work than the bespoke walk.

Required protocol change: `jelly.timeline.head-hash` (singular §13.3) →
`head-hashes` (set) to represent multi-head state during unresolved
concurrent writes. Resolved timelines have exactly one head.

### Q3: `jelly.mythos` conflicting successors — literature pattern?

**Git-fork semantics with Guild-quorum canonicalization. No CRDT
library; a signed-chain fork protocol.**

1. **Detect**: Fork = two `jelly.mythos` envelopes sharing the same
   `predecessor` hash but with different Blake3 hashes.
2. **Preserve**: Losing branch re-published as `shadow-naming` action on
   the palace timeline.
3. **Canonicalize**: Guild admins emit a quorum-signed `true-naming`
   action pointing at the winning successor; the winning mythos
   envelope's `discovered-in` field references this action.
4. **FR60g (Vision)**: Threshold-signature m-of-n quorum on the
   canonicalization action. NextGraph's partial-order quorum commit
   design is the most complete published reference. The Dreamball
   version must include ML-DSA-87 co-signatures on the quorum action.

Precedents: Certificate Transparency (RFC 6962/9162) for fork detection
via signed tree heads; Hypercore for multi-signer append-only logs;
NextGraph for threshold-sig quorum commits.

### Q4: Embeddable CRDT library with clean Bun+WASM story?

**Loro is the best candidate for the property-value layer of
memory-graph triples.**

- `loro-crdt` npm package is pure WASM — works in Bun and browser,
  no napi.
- MIT license.
- LWW-Map per edge-id gives concurrent property-edit resolution.
- If the oracle Agent is single-writer, plain Zig LWW-Map is sufficient
  and Loro adds nothing.
- Automerge is also a viable alternative (same WASM story) but heavier;
  its advantage (Peritext text) is only relevant for inscription
  editing (Growth tier).

Neither Loro nor Automerge replaces the need for a bespoke OR-Set for
nodes and edges; those must still be implemented.

---

## Open questions the investigation surfaced

1. **`head-hash` → `head-hashes` protocol change**: §13.3 specifies a
   single `head-hash`. Multi-writer concurrent append produces multiple
   heads. Does this become a set attribute, or does the protocol
   require a merge action to reduce to single-head before publishing?
   Needs a decision before FR68 implementation.

2. **Guild quorum canonicalization wire shape (FR60g)**: Should the
   `true-naming` quorum action carry a threshold-sig bundle (m-of-n
   sigs in one action envelope, à la NextGraph) or multiple independent
   `jelly.action` entries from each admin? The former is cleaner but
   requires a new attribute type.

3. **Loro + jelly.wasm two-WASM co-existence spike**: feasible in
   principle; untested in jelly's Bun/browser host. Memory overhead and
   instantiation time need verification before committing Loro to the
   oracle Agent property layer.

4. **OR-Set tombstone GC protocol**: without GC, OR-Set tombstones in
   the memory-graph grow indefinitely. Need a Guild-initiated compaction
   protocol that preserves causal history verification (checkpoint the
   Blake3 root of the compacted state).

5. **Inscription concurrent editing scope**: if two scribes edit the
   same `jelly.inscription` concurrently (FR72, Growth), is the
   `jelly.asset` reference updated LWW (one full text wins) or does
   inscription content become a Peritext/Automerge document? The latter
   is a significant protocol surface change.

---

## Sources

- [1] https://automerge.org — Automerge homepage, production-readiness
  claims, v3 announcement
- [2] https://github.com/automerge/automerge/releases/ — Release history;
  v3.2.5 March 2025
- [3] https://automerge.org/automerge-binary-format-spec/ — Binary format
  spec; SHA-256 content-addressing, change DAG, no signing
- [4] https://github.com/yjs/yjs — Yjs repo; YATA model, pure TS, 900k+
  weekly downloads
- [5] https://github.com/loro-dev/loro — Loro repo; data types, MIT
  license, WASM delivery
- [6] https://www.loro.dev/llms-full.txt — Loro full changelog; v1.0.0
  stable encoding Oct 2024, v1.8.2 current April 2026
- [7] https://loro.dev/blog/movable-tree — Loro movable-tree blog;
  Kleppmann et al. algorithm, Fractional Index child ordering
- [8] https://github.com/josephg/diamond-types — Diamond Types repo;
  WIP status confirmed Feb 2026 issues
- [9] https://arxiv.org/abs/2004.00107 — Merkle-CRDTs: Merkle-DAGs meet
  CRDTs (Sanjuan et al., 2020)
- [10] https://github.com/orbitdb-archive/ipfs-log — ipfs-log; signed
  append-only CRDT on IPFS
- [11] https://open.source.network/blog/how-defradb-uses-merkle-crdts-to-maintain-data-consistency-and-conflict-free
  — DefraDB Merkle-CRDT production usage
- [12] https://www.inkandswitch.com/peritext/ — Peritext essay
- [13] https://github.com/inkandswitch/peritext — Peritext reference
  implementation
- [14] https://mattweidner.com/2023/09/26/crdt-survey-2.html — CRDT
  Survey Part 2 (Weidner 2023)
- [15] https://www.bartoszsypytkowski.com/crdt-map/ — State-based CRDTs:
  Maps; OR-Map vs LWW-Map analysis
- [16] https://martin.kleppmann.com/papers/list-move-papoc20.pdf —
  Moving Elements in List CRDTs (Kleppmann, PaPoC 2020)
- [17] https://dl.acm.org/doi/10.1145/3721473.3722141 — DAG CRDT paper,
  PaPoC 2025 (Borth)
- [18] https://www.researchgate.net/publication/328036636_The_Causal_Graph_CRDT_for_Complex_Document_Structure
  — Causal Graph CRDT (Weiss et al.)
- [19] https://crdt.tech/implementations — CRDT implementations list
- [20] https://docs.nextgraph.org/en/framework/crdts/ — NextGraph CRDT
  framework
- [21] https://docs.nextgraph.org/en/specs/format-repo/ — NextGraph repo
  format spec
- [22] https://arxiv.org/abs/2305.00583 — The Art of the Fugue:
  Minimizing Interleaving in Collaborative Text Editing (Weidner,
  Gentle, Kleppmann, 2023)
- [23] https://mattweidner.com/2022/10/21/basic-list-crdt.html —
  Weidner, "Fugue: A Basic List CRDT" (introductory exposition,
  tree-variant)
- [24] https://loro.dev/blog/loro-richtext — Loro's rationale for
  adopting Fugue as the underlying text algorithm
