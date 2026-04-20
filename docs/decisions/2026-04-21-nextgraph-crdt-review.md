# 2026-04-21 — NextGraph spec review + CRDT strategy for FR68/FR60g

## Status

Phase-0 must-read complete (PRD §9 "Phase 0 must-reads"). Not yet a
full ADR — this note captures the comparative reading so that FR68
(multi-writer shared rooms) and FR60g (mythos divergence resolution)
can be implemented without accidentally reinventing a solution
NextGraph has already shipped in an incompatible shape.

Paired with research findings at
`docs/research/crdt-options/findings.md` — this note cites, but does
not duplicate, that report.

## Context

PRD `docs/products/memory-palace/prd.md` §9 names two Phase-0
deliverables as blocking for FR68 and FR60g:

1. Read `docs.nextgraph.org/en/specs/` — specifically the repo format
   and threshold-signature documents.
2. Produce "a one-page diff note in `docs/decisions/` calling out
   where our semantics match theirs, where we diverge deliberately,
   and where we diverge accidentally (and should reconsider)."

The architectural convergence is already flagged in PRD §6.2.2: both
projects independently reached Blake3 + ChaCha20 + Ed25519 +
CBOR-envelope + parent-hash DAG + local-first. NextGraph is **not** a
drop-in dependency (see
`docs/research/graph-db-options/hypotheses/h-nextgraph/findings.md`
for the full rejection analysis) — but its wire format has been field-
tested since 2024 and is the most complete published reference for the
shape of problem Dreamball is solving.

## The NextGraph primitives, distilled

*From `docs.nextgraph.org/en/specs/format-repo/`,
`.../framework/signature/`, `.../framework/crdts/` (fetched
2026-04-21).*

### Repo format

- Commits form a DAG with four reference kinds:
  - `DEPS` — strong predecessors this commit depends on
  - `ACKS` — current valid heads before this commit was inserted
    (multiple ACKs = merge commit)
  - `NACKS` — head commits marked invalid (reverts)
  - `NDEPS` — dependencies removed after this commit (reverts)
- `CommitHeaderV0.compact` flag signals "hard snapshot" — brokers may
  garbage-collect ACK'd bodies after a compact marker.
- Blocks are ≤1 MB, Merkle-tree-chunked, ChaCha20-encrypted with a
  convergent-encryption key derived by
  `BLAKE3.derive_key("NextGraph Data BLAKE3 key", store + readcap)`.
- `BlockId` and `ObjectId` are Blake3-32-byte digests; the root
  block's ID is the object's canonical name.
- Trust chain roots at the **RepoId** (an Ed25519 public key);
  `CertificateV0` chains subsequent certs via
  threshold-crypto signatures (`TotalOrder`, `Owners`, `Store`
  variants).

### Signatures

- Per-commit author Ed25519 signature "to prove authenticity of the
  data, and to verify permissions."
- Two signing regimes:
  - **Asynchronous** — applied after DAG attachment + pub/sub
    distribution; suits continuous editing.
  - **Synchronous** — applied *before* DAG inclusion; the commit
    is invisible to others until the quorum validates.
- Quorum signatures are a `threshold_crypto::Signature` (Rust
  BLS-based threshold-sig crate); separate quorums for async vs sync.
- **No post-quantum signatures anywhere** in NextGraph.
- Key rotation / revocation: not documented at this level.

### CRDTs

- Three composable CRDT back-ends per `Branch.crdt` field:
  `Graph(RDF-OR-set)`, `Yjs(YMap/YArray/YXml/YText)`,
  `Automerge(patches)`, and a placeholder `Elmer`.
- RDF graph CRDT follows **SU-set (SPARQL Update set)** — OR-set over
  triples. Because "RDF predicates are not unique. They can have
  multiple values," triples are inherently a multiset and **cannot
  conflict at the triple level**.
- No merge-rule escalation to the user for RDF; Automerge breaks ties
  by higher actor ID; Yjs uses Lamport clocks.
- Tombstones are commits, not flags — `NACKS` and `NDEPS` carry the
  delete; the original commit stays in the DAG.
- `compact` flag and snapshots enable both body-GC and a non-CRDT
  snapshot read-path.

## Diff table — Dreamball vs NextGraph

| Axis | Dreamball | NextGraph | Match / Deliberate / Accidental |
|---|---|---|---|
| Content-addressing hash | Blake3-32 | Blake3-32 | **Match** |
| Envelope format | dCBOR | CBOR (own dialect) | **Match** (same family) |
| Author signature algorithm | Ed25519 + ML-DSA-87 (hybrid) | Ed25519 only | **Deliberate divergence** — jelly is PQ-ready, NG is not |
| Commit DAG parents | `parent-hashes[]` (single list) | `DEPS` + `ACKS` (two lists) | **Accidental** — NG's split is richer; see below |
| Multi-head state during concurrent writes | `head-hash` (singular) | implicit via ACKs = latest heads | **Accidental** — we need a set; see Q1 below |
| Revert / invalidation primitive | not specified | `NACKS` + `NDEPS` | **Accidental gap** |
| Body GC / snapshot signal | not specified | `compact` flag on CommitHeader | **Accidental gap** |
| Block max size | implicit ("whole envelope") | 1 MB chunks, Merkle-tree | **Deliberate divergence** — jelly's CAS already chunks attachments via sidecars; no need to replicate |
| Convergent encryption | ChaCha20 + fingerprint key | ChaCha20 + derived convergent key | **Match** (both follow the convergent-encryption pattern) |
| Graph CRDT model | LPG with typed edge props | RDF OR-set (SU-set) | **Deliberate divergence** — explicit LPG choice |
| Multi-CRDT per branch | not modelled | `BranchCrdt` enum (Graph/YMap/.../Automerge) | **Deliberate divergence** — jelly keeps one model |
| Threshold / quorum signatures | Guild-admin single-sig today, FR60g reserves quorum for mythos | `threshold_crypto::Signature` (BLS) | **Accidental gap** — FR60g lacks a specified wire shape |
| Sync vs async signing distinction | not modelled | two-regime quorum | **Not needed** — jelly's per-commit dual-sig covers authenticity without a second regime; revisit if group editing requires it |
| Post-quantum roadmap | ML-DSA-87 already shipping for nodes | none | **Deliberate divergence** (and upside — NG will have to add this later) |

## Where we should adjust before implementing FR68 / FR60g

Three "accidental" items from the diff are worth fixing *before* the
relevant Zig code lands, because fixing them later means a wire break.

### 1. Pluralize `jelly.timeline.head-hash` → `head-hashes`

NextGraph's ACKs list is always a set, even when the set has size 1
(a non-merge commit has one ACK, the prior head). This is because a
concurrent two-writer state naturally produces two heads until
someone emits a merge.

Our §13.3 fixes `head-hash` as a single attribute. If a shared room
ever sees two concurrent appends from different wayfarers, we have no
wire-legal way to represent the transient "two heads, one merge
pending" state — the timeline envelope stops being signable by either
writer alone.

**Change**: in `docs/PROTOCOL.md §13.3` (the `jelly.timeline` envelope
definition), change

```
"head-hash": h'…32…'
```

to

```
"head-hashes": [h'…32…', h'…32…', ...]   ; set, cardinality ≥ 1
```

Resolved single-head timelines carry a 1-element set. Multi-writer
branches carry 2+ until a merge action lands. No change to
`jelly.action` itself — `parent-hashes[]` already handles the merge
case correctly.

This is a pre-FR68 protocol change. Cost is one Zig encoder tweak,
one golden-fixture rebase, one `src/lib/generated/*.ts` regen.

### 2. Adopt NextGraph's DEPS / ACKS split — or deliberately don't

NextGraph distinguishes:

- **DEPS** — "I logically depend on these; they must exist before I
  make sense"
- **ACKS** — "these were the heads when I wrote; I am aware of them
  and claim to merge over them"

In jelly today, `parent-hashes[]` on a `jelly.action` conflates both:
the parent is both the causal dependency and the acknowledged head.

Two scenarios where that conflation hurts:

- A `move` action has a logical dependency on the `inscribe` action
  that created the item being moved (DEPS relation), plus it
  acknowledges whatever other actions were in-flight on the same room
  (ACKS relation). Today both go in `parent-hashes[]` and the
  renderer can't tell which.
- Reverts (FR67 "rewind" territory) want a way to say "this action
  invalidates that earlier action" without re-walking the DAG and
  comparing semantic predicates.

**Recommendation**: add `deps` and `nacks` as optional attributes on
`jelly.action`, keeping `parent-hashes[]` as the ACKS-equivalent.
`deps` carries "logical predecessors this action depends on";
`nacks` carries "prior head actions this one invalidates" (for FR67
rewinds). This matches NG's vocabulary without requiring their
envelope layout.

Cost: three new optional fields on one envelope type; no breaking
change (absent = empty).

### 3. Specify the FR60g quorum wire shape now

FR60g ("mythos divergence resolution") says: "the Guild's
conflict-resolution policy (default: quorum of admins) picks the
canonical successor." Today there is **no wire shape** for "m-of-n
admins co-sign this `true-naming` action." If we ship FR60a–FR60f
without pinning this down, the shape will be invented ad-hoc at the
first fork.

Two ways to model it, both compatible with the existing signature
rule ("all present signatures must verify"):

- **Option A — multi-`signed` attribute stacking** (simplest): a
  quorum `true-naming` action carries N `'signed'` attributes (each
  Ed25519 + ML-DSA-87 pair), one per co-signing admin. Verify
  succeeds if *all* present sigs verify AND the Guild policy is
  satisfied (policy-side check: does the set of signers meet the
  threshold defined in the `jelly.guild` envelope?).
- **Option B — NextGraph-style threshold signature**: a single
  `threshold_crypto::Signature` combining m-of-n admins. Cleaner
  aggregate; requires a BLS implementation or equivalent; does not
  compose naturally with hybrid Ed25519+ML-DSA-87 because ML-DSA-87
  has no threshold scheme in the reference literature.

**Recommendation**: Option A. It is the policy-side check in jelly's
existing signature rule, implemented once. It preserves per-admin PQ
coverage (every admin's ML-DSA-87 sig is independently verifiable).
The cost is that verification is O(N) sigs where NextGraph is O(1) —
acceptable for Guild quorums which are typically ≤10.

Cost: no new envelope; one new attribute on `jelly.guild`
(`quorum-policy`: `{ kind: "m-of-n", m: <int>, admins: [<fp>,...] }`)
plus verify-side policy evaluation.

## CRDT strategy per Dreamball structure (from findings.md)

| Structure | CRDT primitive | Library or bespoke |
|---|---|---|
| `jelly.action` timeline | Merkle-CRDT G-Set over signed, Blake3-addressed actions | Bespoke DAG walker; no library |
| `jelly.layout` | MV-Register per `child-fp` (surfaces both concurrent moves as ghost-placements; matches the "rejected-action ghost" UX already in §9) | Bespoke; ~80 lines |
| `jelly.mythos` divergence (FR60g) | Signed-chain fork protocol with Guild-quorum canonicalization + `shadow-naming` preservation | Bespoke; wire shape specified above |
| Oracle memory-graph triples (LPG) | OR-Set for nodes and edges + LWW-Map per edge for properties | Primary: bespoke; consider Loro (pure WASM, no napi) if concurrent property edits become a hotspot |
| `jelly.inscription` text editing (FR72, Growth) | LWW on the `jelly.asset` hash is sufficient at MVP; Peritext/Automerge only if concurrent text merging becomes a requirement | Defer — MVP is single-author per inscription |

The key finding: **we do not need a CRDT library for the MVP palace.**
Three of four structures are already Merkle-CRDT-shaped by the
existing protocol; the fourth (memory-graph triples) composes from
textbook primitives. Loro is the fallback if the oracle Agent
eventually admits multi-writer property edits.

## Actions before FR68 lands

- [ ] Update `docs/PROTOCOL.md §13.3` to pluralize `head-hash` →
      `head-hashes` (set). Rebase golden fixtures.
- [ ] Add optional `deps` and `nacks` attributes to `jelly.action` in
      `docs/PROTOCOL.md §13.4`. No code yet — spec-only.
- [ ] Add `quorum-policy` attribute to `jelly.guild` (FR60g
      pre-work). Specify Option A (multi-signed stacking) as the
      wire shape.
- [ ] Cross-link this note from PRD §9 Phase-0-must-reads as the
      Phase-0 deliverable.
- [ ] Open tracking issues for Loro spike (memory-graph oracle layer,
      Growth tier) and Peritext/Automerge evaluation (inscription
      concurrent editing, Growth tier).

## Why we still don't use NextGraph itself

The diff above is a compliment, not a redirection. Every place our
semantics converge with NG's, we reach the same primitive through our
own reasoning. Every place we deliberately diverge (LPG over RDF;
hybrid PQ sigs; pure-computation WASM), the divergence is load-bearing
for Dreamball's positioning — dropping it to adopt NG would regress
the protocol's PQ story and replace the LPG model with an RDF model we
explicitly rejected in `docs/research/graph-db-options/synthesis.md`.

NextGraph's value to us, long-term, is as a *shape reference* — a
published, shipping, signed-DAG + CRDT + local-first system whose wire
shape we can compare against before freezing our own. That is what
this note is.

## References

- `docs/products/memory-palace/prd.md` §6.2.2, §9 Phase-0-must-reads,
  FR68, FR60g
- `docs/research/graph-db-options/hypotheses/h-nextgraph/findings.md`
  — the original NextGraph architectural-convergence survey
- `docs/research/crdt-options/findings.md` — full CRDT candidate
  survey and citations (April 2026)
- `docs/PROTOCOL.md §13.3`, `§13.4` — the `jelly.timeline` and
  `jelly.action` envelopes referenced in the recommended changes
- NextGraph live docs (fetched 2026-04-21):
  - https://docs.nextgraph.org/en/specs/format-repo/
  - https://docs.nextgraph.org/en/framework/signature/
  - https://docs.nextgraph.org/en/framework/crdts/
