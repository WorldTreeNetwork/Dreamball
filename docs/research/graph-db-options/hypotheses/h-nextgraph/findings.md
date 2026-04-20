# Hypothesis: NextGraph as a candidate for the Dreamball Memory Palace graph database

## Summary

NextGraph is **not a viable candidate for the Memory Palace graph database role** in Dreamball's current development timeline. It is an alpha-stage decentralized application platform built around RDF/SPARQL + CRDT + P2P, not an embeddable graph-query engine. The architectural alignment with Dreamball is striking and real — both projects independently arrived at signed DAG commits, BLAKE3 content addressing, CRDT merge semantics, and local-first encrypted storage — but this convergence is an argument for **architectural awareness**, not integration. The overlap is so deep that using NextGraph would mean replacing Dreamball's core wire format, not adding a graph index on top of it. Verdict: **interesting-but-not-applicable** as a graph DB candidate, with a strong flag for the synthesizer that the convergence warrants a "second reading" of the whole PRD.

---

## Evidence

### 1. Embedded, In-Process?

NextGraph ships as a Rust crate (`nextgraph` on crates.io, v0.1.2-alpha.2, November 2025) that exposes a `local_broker` API described as "running embedded in your client program." It has 19 direct Rust dependencies including `ng-client-ws`, `ng-net`, `ng-verifier`, `ng-storage-rocksdb`, and async runtime. The networking stack (`ng-client-ws`, `ng-net`) is a hard dependency — there is no feature flag documented to compile without it. The local broker is architecturally "a reduced instance of the network Broker," not a standalone embedded store.

The Node.js SDK (`@ng-org/web`, v0.1.2-alpha.4, April 2026) exists but is alpha and browser-first; Node.js support is described as "not yet usable as a developer SDK." **Bun is not mentioned anywhere** (pnpm is used internally).

**Assessment**: Rust crate is technically embeddable but carries the full P2P networking stack. JS/TS SDK is alpha-grade and browser-first. Neither path provides a clean embedded-library experience analogous to SQLite/Kuzu today.

Sources: [1] [2] [3]

### 2. Local-First / Offline?

Local-first is a first-class design goal. However, the client protocol documentation explicitly states it "requires a connection to a Broker" for repo operations. Self-hosted broker (`ngd`) is in alpha. The critical question — can you run a fully standalone local store with zero network traffic — is not answered affirmatively anywhere. Architecture separates "local-first data access" (works offline once synced) from "initial setup and ongoing repo management" (requires broker contact).

**Assessment**: Local-first in the CRDT/offline-editing sense: yes. Purely standalone embedded store with no network dependency whatsoever: unclear/probably not without code-level modifications.

Sources: [4] [5]

### 3. Data Model: RDF Triple Store, Not Property Graph

NextGraph is an **RDF triple store** at its core. Query language is SPARQL (via the `ng-oxigraph` fork of Oxigraph). There is no labeled property graph (LPG) model.

**Properties on edges** (a hard requirement for the Memory Palace — aqueduct float weights, enum types, ML-DSA signature bytes) require RDF reification or RDF-star / SPARQL-star (RDF 1.2). The ng-oxigraph fork's RDF-star parity with upstream is undocumented. In RDF each edge-with-property becomes a named resource (reification) or uses RDF-star — semantically expressible but architecturally alien to Dreamball's property graph mental model.

**Assessment**: Pure RDF triple store. No native LPG. Edge properties via RDF-star add significant modeling friction.

Sources: [6] [7]

### 4. Query Language: SPARQL, No DAG-Walk Primitives

SPARQL (via ng-oxigraph). SPARQL 1.1 property path expressions (`+`, `*`, `/`) can express bounded ancestor walks but are not graph traversal in the Cypher/GQL sense — they are regex-style path patterns over triples. For DAG ancestor walks on signed commit chains (`jelly.timeline`), SPARQL property paths work but become unwieldy for production. No `shortestPath()`, no `k-hop neighborhood` primitive, no native DAG topology query. **No vector support** — confirmed absent.

Sources: [6] [8]

### 5. Rebuild from CAS / Blake3 Content Addressing

**The most striking alignment.** NextGraph uses BLAKE3 as content-addressing hash (32-byte digest). Blocks form a Merkle tree. Commits reference parents by content-addressed IDs forming a DAG. Convergent encryption uses ChaCha20.

Dreamball uses BLAKE3 for its CAS, ChaCha20 for encryption, and Ed25519 for authorship signatures — **essentially the same cryptographic primitive set**. NextGraph's repository format (commit DAG, DEPS/ACKS references, threshold signatures, hash-addressed blocks) is structurally near-identical to Dreamball's `jelly.timeline` chain.

**However**: FR84 means Dreamball's CAS is authoritative and the graph index is derived. NextGraph's CAS *is* the authoritative store — you cannot feed it external `.jelly` CBOR envelopes and rebuild a NextGraph repo from them. The two systems use content-addressing but with incompatible envelope formats.

**Assessment**: Deep cryptographic and structural alignment. Not interoperable at the envelope level without a full translation layer.

Sources: [9] [10]

### 6. Signed DAGs / Timelines

NextGraph commits are signed by their author (Ed25519 per commit). Additional threshold signatures (multi-party quorum) and async/sync distinction. Signature certificate chain rooted at the RepoID. More sophisticated than Dreamball's current Ed25519 + ML-DSA-87 dual-sig.

**Notably, NextGraph does not mention post-quantum signatures** (ML-DSA, CRYSTALS-Dilithium) anywhere. Dreamball's ML-DSA-87 Tier 2 signing is a differentiator NextGraph does not have.

Sources: [11]

### 7. Vector Support

None. Confirmed absent across docs, crates, and roadmap. Upstream Oxigraph has no vectors either. Hard miss.

### 8. WASM Target

NextGraph's WASM is a full application runtime bundle (CRDT engine + RDF store + network client), not a pure computation module. Browser SDK currently runs in "third-party mode" — application inside an iframe controlled by the Broker Service Provider. Native Tauri plugin (standalone WASM without iframe/broker) described as "coming soon" but not released as of April 2026.

**Cannot be used as a drop-in embedded WASM module** in Dreamball's `jelly.wasm` architecture without major architectural changes.

Sources: [12] [13]

### 9. TypeScript/Bun Bindings

- npm: `@ng-org/web` v0.1.2-alpha.4 (April 2026, actively published)
- Node.js SDK: "not yet usable as a developer SDK"
- Bun: not mentioned
- No Bun-compatible embedded library path. Browser SDK only.

Sources: [3] [14]

### 10. License

Dual-licensed **MIT OR Apache-2.0**. Clean and permissive. No restrictions.

Sources: [15]

### 11. Maintenance Status (April 2026)

- Most recent commit: March 2026 by Niko PLP (sole author)
- Release cadence: 0.1.0-preview (Aug 2024) → 0.1.1-alpha (Sep 2024) → 0.1.2-alpha.1 (Nov 2025) → SDK 0.1.2-alpha.4 (April 2026)
- NLnet Foundation grant funding active
- FOSDEM 2026 presentation confirms active community presence
- GitHub mirror: 84 stars, 9 forks (small)
- Solo-author project (Niko Bonnieure) with NLnet funding

**Assessment**: Actively maintained but alpha software. 14-month gap between 0.1.1-alpha and 0.1.2-alpha.1 suggests slower cadence than roadmap implies. Significant bus-factor risk.

Sources: [16] [17]

### 12. Architectural Integration Fit with Dreamball

The evidence firmly supports: NextGraph overlaps so heavily it would be **architectural redirection**, not integration. Overlap covers content addressing (BLAKE3), encryption (ChaCha20), author signatures (Ed25519), binary envelopes (CBOR), local-first operation, and commit DAG chaining.

Differences:
- Dreamball's wire format is CBOR + Zig-generated schemas; NextGraph's is its own repo format
- Dreamball uses ML-DSA-87 (post-quantum); NextGraph does not
- Dreamball's graph model targets LPG with float/enum edge properties; NextGraph is RDF
- Dreamball's WASM module is a pure computation primitive; NextGraph's WASM is a full application runtime

"Using NextGraph as a graph query index" would require ingesting Dreamball `.jelly` CBOR envelopes, translating them into NextGraph's repo format, storing them in a running NextGraph local broker process, then querying via SPARQL. This is not a library linkage — it is running a second application stack that duplicates most of Dreamball's own core.

---

## Confidence

**Level**: high

Multiple independent primary sources (docs.nextgraph.org, docs.rs, crates.io, lib.rs, git.nextgraph.org, npm, roadmap, release history) converge on the same picture.

---

## Sources

- [1] https://docs.rs/nextgraph/latest/nextgraph/ — "local_broker embedded in client program; depends on ng-client-ws, ng-net"
- [2] https://docs.nextgraph.org/en/nodejs/ — "nodeJS SDK ... not yet usable"
- [3] https://github.com/nextgraph-org/nextgraph-rs — "Rust+TS+Python bindings; pnpm workspace; 84 stars; latest commit March 2026"
- [4] https://docs.nextgraph.org/en/local-first/ — "data always accessed locally; CRDT offline sync"
- [5] https://docs.nextgraph.org/en/specs/protocol-client/ — "Client Protocol requires connection to a Broker"
- [6] https://docs.nextgraph.org/en/framework/crdts/ — "Graph CRDT is RDF with OR-set; SPARQL primary query language; no LPG"
- [7] https://lib.rs/crates/ng-oxigraph — "fork of Oxigraph; adds CRDTs to RDF/SPARQL; RocksDB with encryption at rest"
- [8] https://docs.nextgraph.org/en/documents/ — "RDF graph + discrete JSON nature; RepoID as DID"
- [9] https://docs.nextgraph.org/en/specs/format-repo/ — "BLAKE3 content addressing; Merkle tree blocks; ChaCha20 convergent encryption; commit DAG DEPS/ACKS"
- [10] https://git.nextgraph.org/NextGraph/nextgraph-rs — "remove openssl, prepare wasm target"
- [11] https://docs.nextgraph.org/en/framework/signature/ — "per-commit author Ed25519; threshold signatures; certificate chain; no post-quantum"
- [12] https://docs.nextgraph.org/en/web/ — "iframe controlled by Broker Service Provider; Tauri plugin not yet released"
- [13] https://nextgraph.org/introduction/ — "Rust compiles to WASM; full stack in WASM"
- [14] https://www.npmjs.com/package/@ng-org/web — "v0.1.2-alpha.4, April 2026"
- [15] https://crates.io/crates/ng-storage-rocksdb — "MIT OR Apache-2.0"
- [16] https://nextgraph.org/releases/ — "Release history; NLnet-funded"
- [17] https://fosdem.org/2026/schedule/speaker/niko_bonnieure/ — "FOSDEM 2026 presentation"

---

## Verdict

**Category 4: Interesting-but-not-applicable** as a graph database for the Memory Palace.

NextGraph cannot serve as the embedded graph-query index because:
1. Not an embeddable library — it is an application runtime with a network stack
2. Data model (RDF/SPARQL) mismatched to Memory Palace LPG requirements
3. JS/TS SDK browser-first and alpha-grade; no Bun support
4. No vector support
5. Integrating it would mean running a second full application stack that duplicates Dreamball's own core

The primary candidates (LadybugDB/Kuzu, DuckDB+duckpgq) remain the correct direction.

---

## Architectural Convergence Flag — "Second Reading"

**Strong enough to warrant synthesis-level attention.**

Dreamball and NextGraph have independently converged on nearly identical architectural primitives:

| Primitive | Dreamball | NextGraph |
|---|---|---|
| Content addressing | BLAKE3 | BLAKE3 |
| Encryption | ChaCha20 | ChaCha20 convergent |
| Author signature | Ed25519 per commit | Ed25519 per commit |
| Envelope format | CBOR | CBOR |
| Commit chain | DAG with parent hash refs | DAG with DEPS/ACKS hash refs |
| Local-first | Yes, offline-capable | Yes, CRDT offline-capable |
| Sync model | Guild/recrypt proxy-recryption | Threshold signatures + broker |

This is not coincidence — both projects are solving the same underlying problem (local-first signed content-addressed collaborative data with E2E encryption) and both reached for the same cryptographic primitives because those primitives are the right answer.

**Dreamball has already re-invented the storage and signing layer of NextGraph, but with a cleaner embedding story (pure WASM), post-quantum signatures (ML-DSA-87), and a LPG rather than RDF data model.** The PRD's Memory Palace requirements (FR84 rebuild from CAS, FR68 CRDT-compatible shared rooms, signed DAG timelines) read almost like a NextGraph feature list. The team should study NextGraph's protocol specifications before finalizing the Memory Palace wire format — not to switch, but to avoid re-inventing its remaining wheels (threshold signatures, multi-device sync protocol) in an incompatible way.
