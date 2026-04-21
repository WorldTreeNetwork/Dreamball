# Keyhive Review — Patterns for Dreamball's Sync Layer

*Research conducted 2026-04-21. Output captured verbatim from the
morphist investigator agent.*

## Summary

Keyhive is a pre-alpha Rust workspace from Ink & Switch exploring
local-first access control for Automerge-backed documents. It is
organised into three conceptual layers — Convergent Capabilities (a
CRDT-native delegation DAG), a Group Management CRDT (coordination-
free membership + revocation), and E2EE with Causal Keys (per-commit
encryption tied to causal history) — plus BeeKEM (a decentralised
Continuous Group Key Agreement protocol) and Sedimentree
(probabilistic DAG compression for encrypted sync). All cryptographic
work uses classical curves only (Ed25519 / X25519 /
ChaCha20-Poly1305). No post-quantum primitives exist anywhere in
Keyhive.

**Verdict on integration:** Keyhive is not a drop-in dependency for
Dreamball, but five of its primitives are directly instructive.
BeeKEM is the most novel and closest to a genuine gap in our design:
we have Guild keyspaces backed by recrypt proxy-recryption, but no
protocol for ratcheting shared group keys under membership change
without a trusted server. Sedimentree's trailing-zeros DAG compaction
is directly adoptable as a compression policy for the `jelly.timeline`
DAG. Convergent Capabilities' delegation-chain model maps cleanly
onto our Guild policy layer. We should **not** take a Rust FFI
dependency — the crate is pre-alpha, unaudited, and assumes an
Automerge document model we have explicitly replaced with dCBOR
envelopes.

---

## Primitive-by-Primitive Extraction

### 1. Convergent Capabilities and the Delegation DAG

**What it is.** Convergent capabilities ("concap") sit between object-
capabilities (ocaps) and certificate capabilities (UCAN, SPKI/SDSI,
zcap-ld). Ocaps are fail-stop under network partition — incompatible
with local-first offline operation. Certificate-capabilities are
partition-tolerant but stateless chains that lose flexibility (no
CRDT-side membership state). Concaps embed CRDT state into the
capability itself, so the capability graph converges under concurrent
delegation operations.

**Access levels.** Four named levels: `pull` (receive synced bytes,
no plaintext), `read`, `write`, `admin`. The level is carried in the
delegation record.

**Delegation structure.** Each delegation is a signed record from a
delegator's keypair to a delegatee's public key, scoped to a document
or group and carrying an access level. The chain from a root document
key through intermediate groups to leaf device keys is the
"delegation DAG." Following the DAG from any leaf to the document
root tells you the maximum access level for that leaf. "By following
the delegations between groups, we can discover which public keys
have what kind of access to a certain document." [1]

**Revocation.** "The Group Management CRDT provides self-certifying,
concurrent group management complete with coordination-free
revocation." Revocation is a signed tombstone that propagates as a
CRDT operation — no central revocation server, no certificate
blacklist. [1]

**Comparison to recrypt + Guild.** Dreamball's `jelly.dreamball.guild`
carries a flat `member`/`admin` list signed as a snapshot. Keyhive's
concap model adds multi-hop delegation chains (A delegates to group
G, G delegates to device D) and CRDT-merge semantics for concurrent
offline edits. Recrypt proxy-recryption handles key distribution (how
a new user gets a sealed DragonBall); concap handles policy-graph
(who has what access level). These are complementary, not competing.

### 2. BeeKEM — Decentralised Continuous Group Key Agreement

**Problem.** TreeKEM (the MLS basis, RFC 9420) requires a central
server to impose a total order of operations. Causal TreeKEM
(Weidner) relaxes to causal order but requires associative-commutative
cryptographic operations (BLS-like). BeeKEM uses only X25519 DH and
BLAKE3 — standard primitives — and requires only causal order, making
it suitable for fully decentralised peers.

**Tree structure.** A balanced binary tree: leaf nodes hold member
IDs and X25519 DH public keys; inner nodes hold secrets encrypted
toward the parent; the root secret is the group key.

**Deriving the root secret.** A member starts at its leaf, performs
DH with its sibling at each level to decrypt the parent node secret,
traverses up to the root. O(log N) operations.

**Membership changes.**
- *Add:* New member inserted at next blank leaf on the right; the
  path to root is blanked. Concurrent adds resolved by sorting all
  concurrently added leaves and blanking their paths — CRDT-native,
  no server.
- *Remove:* Removed member's leaf and its entire path to root are
  blanked. "At least one remaining member must perform an Update Key
  operation to restore a root secret" when root is blank. This is a
  live obligation.
- *Update Key:* A member rotates its DH public key, rotating the root
  secret. Fresh randomness provides post-compromise security.

**Forward secrecy / post-compromise security.** BeeKEM provides both.
Key rotation changes the root secret; old secrets are unreachable
from new ones. A compromised old leaf key grants nothing once a
remaining member performs Update Key.

**Comparison to recrypt.** Recrypt proxy-recryption rewraps a sealed
payload from key A to key B without the server seeing plaintext — it
is a one-to-one static rewrap. BeeKEM establishes a rotating shared
group secret agreed by N parties, ratcheting on membership change.
They solve different subproblems. Dreamball currently has no BeeKEM
equivalent — the Guild keyspace is a static key bundle, not a
rotating session key.

**PQ note.** BeeKEM uses X25519 exclusively for key exchange.
Swapping to ML-KEM-768 (CRYSTALS-Kyber) at each tree node is
theoretically feasible — the tree topology and membership-change
logic are unaffected; the DH arithmetic becomes KEM encapsulation —
but no published PQ-BeeKEM spec exists as of April 2026.

### 3. Sedimentree — Probabilistic DAG Compression

**What it is.** A data structure for syncing a causal commit graph
between peers where the server holds only encrypted blobs. Chunk
boundaries are determined purely by hash values, so all peers
independently agree on the same compaction level for any range of
history without coordination.

**Trailing-zeros boundary selection.** "Interpreting the hash of each
commit as a number, [we use] the number of leading zeros in the
number as the level of the chunk boundary." A commit whose hash has
two leading zeros is a level-2 stratum boundary. The probability of
n leading zeros is 10^-n, so boundaries at level n occur
approximately every 10^n commits. Level-1 strata are frequent and
small; level-3 span ~1000 commits.

**Strata and compaction.** Commits within a stratum are stored as one
encrypted blob. A "minimal" sedimentree discards everything a lower
stratum already covers. Checkpoint commits (commits whose hash would
be a stratum boundary) prevent premature discarding during sync.

**Wire format.** A sync summary contains only stratum boundary hashes
and loose commit hashes — not internal checkpoint hashes or actual
data. The receiver identifies missing strata/blobs and requests only
those. Bandwidth is proportional to the set difference, not the total
history size.

**Interaction with E2EE.** The sync server never sees plaintext.
Blobs are encrypted; the sedimentree structure is determined by
commit hashes, which the server stores and relays without decrypting.

**Relevance to Dreamball.** The `jelly.timeline` DAG of `jelly.action`
envelopes is structurally identical to Sedimentree's input: Blake3-
addressed, parent-hash-linked, signed. The trailing-zeros policy
could be applied verbatim — define stratum level as leading zero
nibbles in the Blake3 hash of a `jelly.action` envelope; level-n
compaction absorbs all actions between two level-n boundaries into a
single encrypted blob. This is purely algorithmic and requires no
Keyhive code.

### 4. Convergent Capabilities — the CRDT Layer

**What it is.** The "Convergent" part means the capability graph is
itself a CRDT. Concurrent delegation adds use OR-set semantics (both
survive). Revocations are signed tombstones that propagate and are
accepted by all replicas without coordination.

**Position in the capability spectrum.**
- Ocaps: live references; fail-stop under partition.
- Cert-caps (UCAN, SPKI, zcap-ld): stateless certificate chains;
  partition-tolerant but static.
- Concaps: embeds CRDT state into the capability record. Partition-
  tolerant. OR-set merge of concurrent delegations.

**Group Management CRDT.** Groups are a thin pattern on top of
concaps: a group is a named public key whose membership set is
managed by an OR-set CRDT over signed member-add records, with
revocation via signed tombstones. Self-certifying (each operation
carries the signer's public key and signature). Coordination-free
(revocation propagates as a normal CRDT operation; no server
acknowledgement required before it is locally effective).

**Relationship to Dreamball.** The current `jelly.dreamball.guild` is
a signed snapshot — closer to a cert-cap than a concap. Adopting
concap semantics would mean representing Guild membership as an OR-
set of signed add-operations and removals as signed tombstones rather
than a re-signed envelope with a shorter member list. The benefit:
two Guild admins can independently add members while offline and
their states merge without conflict. The cost: new wire format
(`jelly.guild-op` envelope type) and more complex verification. This
is a Vision-tier consideration.

### 5. Causal Keys — Per-Commit Encryption

**What it is.** Causal encryption ties each document chunk's
encryption key to its causal history. "Having the key to some
encrypted chunk lets you iteratively discover the rest of the keys
for that chunk's causal history, but not its parents." Similar in
spirit to a Cryptree (Grolimund et al.) but adapted to a DAG.

**Key chaining direction.** The chain goes downward toward causal
predecessors (history), not upward toward successors (future).
Knowing a key for chunk C gives you keys for C's causal predecessors,
but not for chunks causally after C. This is the **opposite of a
ratchet**. The system explicitly "sacrifices forward secrecy" in
exchange for "secrecy of concurrent and future chunks." The
rationale: CRDTs require access to the entire causal history to
reconstruct document state; any new reader must be able to decrypt
all history.

**Derivation.** Recursive key wrapping via HKDF. The full primitive
inventory: Ed25519 (signing), X25519 (key exchange), ChaCha20-Poly1305
(symmetric encryption), HKDF (key derivation), SIV-based nonce
generation.

**Not a ratchet.** A reader with the current group key can derive all
historical keys. This is a deliberate trade-off for CRDT history
access, not an oversight.

**Relationship to Dreamball.** Dreamball uses recrypt proxy-recryption
for sealing DragonBalls; `jelly.action` envelopes on a timeline are
not individually encrypted at the protocol level. Causal Keys would
be relevant if Dreamball wanted per-action timeline encryption.
However, Keyhive's model grants new Guild members access to all
history — the inverse of what Dreamball's recrypt model can do (grant
access only from join point onward). The right answer depends on
product requirements; the design tension should be resolved before
per-action encryption is specified.

### 6. Session and Transport Layer (Beelay)

**What it is.** Beelay ("Beehive relay") is an RPC protocol for
syncing Automerge documents over any transport providing
confidentiality. Transport-agnostic.

**Envelope structure.** Each message is `Envelope { message: Message,
signature: Signature, sender: PublicKey }` where `Message { payload,
audience, timestamp }`. The `audience` field binds the message to a
specific recipient public key, preventing PITM forwarding attacks.
The `timestamp` with clock-skew grace periods prevents replay
attacks. All authentication is Ed25519.

**Three-phase sync.**
1. *Membership graph sync* — RIBLT (Rateless Invertible Bloom Lookup
   Tables) over the group/delegation operation set. Reconciling 5
   differing items out of 1 billion takes ~7.5 symbols (32 bytes
   each).
2. *Document collection sync* — RIBLT over `(document_id, state_hash)`
   pairs.
3. *Document content sync* — Sedimentree-based: exchange summaries,
   identify missing strata/blobs, request only those.

**Common case: two round trips** via pipelining.

**No presence channel.** Beelay is durable state sync, not real-time
pub/sub. Presence would be a separate layer.

**Relationship to Dreamball.** Dreamball's jelly-server provides HTTP
endpoints for DreamBall exchange but has no peer-sync protocol.
RIBLT is particularly interesting for Guild membership reconciliation
when two admin devices reconnect after being offline. Adoptable as
an algorithm independent of the Keyhive codebase.

### 7. Post-Quantum Status

**Finding: none.** Keyhive uses only classical cryptography:
- Signing: Ed25519
- Key exchange: X25519
- Symmetric: ChaCha20-Poly1305
- KDF: HKDF
- Hash: BLAKE3
- No ML-DSA, ML-KEM, or any NIST PQC primitive appears anywhere.

**Swapping Ed25519 for hybrid Ed25519+ML-DSA-87 in Keyhive's
signature paths.** Additive under Dreamball's "all present must
verify" rule (PROTOCOL.md §2.3) — no structural change to the
delegation DAG or BeeKEM tree; just wider signature attributes on
Beelay envelopes and delegation records.

**Swapping X25519 for ML-KEM in BeeKEM.** BeeKEM's inner-node secrets
are derived via X25519 DH between sibling keys. Replacing with
ML-KEM-768 at each tree node would provide PQ-secure group key
agreement. The tree topology and membership-change logic are
unaffected; the DH arithmetic changes to KEM encapsulation. No
published PQ-BeeKEM variant exists as of April 2026 — this would be
novel cryptographic engineering.

---

## Diff Table — Dreamball vs Keyhive

| Axis | Dreamball | Keyhive | Classification |
|---|---|---|---|
| Content-addressing hash | Blake3 | BLAKE3 | **Match** |
| Wire format | dCBOR envelopes (#6.200/#6.201) | Automerge binary + Beelay frames | **Deliberate divergence** |
| Signing algorithm | Ed25519 + ML-DSA-87 hybrid | Ed25519 only | **Deliberate divergence** (Dreamball advantage) |
| Group key distribution | recrypt proxy-recryption (static rewrap) | BeeKEM (rotating DH tree, ratcheting) | **Accidental gap** — Dreamball has no rotating group-session-key protocol |
| Group membership model | `jelly.guild` signed snapshot (flat list) | Group Management CRDT (OR-set ops + tombstones) | **Accidental gap** — CRDT merge would improve offline-concurrent Guild edits |
| Revocation | Re-sign Guild with updated list; no tombstone | Coordination-free signed tombstone, CRDT-propagated | **Accidental gap** — Keyhive's tombstone model is stronger |
| Per-commit encryption | Not specified at timeline level | Causal Keys — recursive key wrapping per chunk | **Deliberate divergence** — Dreamball encrypts at bundle level |
| DAG compaction / GC | Not specified | Sedimentree trailing-zeros probabilistic strata | **Accidental gap** — directly adoptable |
| Sync membership reconciliation | Not specified | RIBLT set reconciliation | **Accidental gap** — algorithm adoptable independently |
| Document identity | Ed25519 pubkey + genesis-hash in core | Ed25519 pubkey (Automerge-compatible) | **Match in spirit** |
| Delegation / roles | `jelly.guild-policy` slots + `quorum-policy` stacked sigs | Concap delegation DAG, 4 access levels | **Match in spirit**; Keyhive's multi-hop DAG is richer |
| Post-quantum | ML-DSA-87 on all signed envelopes | None | **Deliberate divergence** (Dreamball advantage) |
| Transport | HTTP (jelly-server, Elysia/Bun) | Beelay over any transport, RPC + RIBLT | **Accidental gap** — Dreamball has no peer-sync protocol |
| Forward secrecy / post-compromise | Not specified | BeeKEM: yes (key rotation + Update Key) | **Accidental gap** |
| History access for new members | Not specified | Causal Keys give all-history access | **Design tension** — Keyhive trades forward secrecy for history |
| CRDT data model | LPG (jelly.action DAG, jelly.memory, jelly.kg) | Automerge (Map/List/Text) | **Deliberate divergence** |
| Runtime | Zig + WASM + Bun | Rust + WASM | **Incompatible for direct FFI** |

---

## Design Questions for Dreamball

### Adopt verbatim (modulo PQ substitution)

**Sedimentree compaction policy** — the trailing-zeros boundary rule
is a pure algorithm, implementation-independent. Define stratum level
for `jelly.action` as leading zero nibbles in the Blake3 hash of the
action's canonical bytes. Level-n strata compact every ~16^n actions.
Apply the "minimal" reduction rule (discard everything a lower
stratum supports). This is the `jelly.timeline` sync and GC protocol.
Requires a new `jelly.stratum` envelope in PROTOCOL.md §13 and a spec
entry for the compaction ceremony (who signs, quorum policy).
**Confidence: adopt — algorithmic, no Keyhive dependency.**

**RIBLT for Guild membership reconciliation** — RIBLT (Ozisik et al.
2019) is a standalone published algorithm. Adopt for the protocol
step "two Guild admin devices reconnect and reconcile membership
operations." Replaces naive full-list exchange. **Confidence: adopt
at Growth tier.**

**Beelay's `{payload, audience, timestamp}` envelope pattern** —
adopt as the Dreamball peer-to-peer sync message shape, with
Ed25519+ML-DSA-87 dual signatures replacing Keyhive's Ed25519-only
signing. **Confidence: adopt the pattern; reimplement in Zig, not in
Rust.**

### Adapt heavily

**BeeKEM** — to get PQ-secure rotating group session keys, implement
a BeeKEM variant where tree-node DH operations use ML-KEM-768 instead
of X25519 (or a hybrid X25519+ML-KEM). The tree topology, blank-
path-on-remove, Update Key obligation all carry over. This is a
significant Zig implementation (~500–1000 lines) and novel
cryptographic engineering — no published PQ-BeeKEM spec exists.
**Worth doing for Growth sync tier; requires a dedicated security-
focused design document first.**

**Convergent Capabilities / Group Management CRDT** — adopting CRDT
membership for `jelly.dreamball.guild` means replacing the signed-
snapshot member list with an OR-set of signed add-operations plus
signed tombstones. This is a wire-format change (new `jelly.guild-op`
envelope type). Not breaking to the delegation policy model —
semantics of who-can-do-what are identical; only the merge behavior
for concurrent offline edits changes. **Adopt at Vision tier; specify
wire shape before first production Guild deployment.**

### Explicitly reject

**Causal Keys as primary per-action encryption model** — Keyhive
trades forward secrecy for history access. Dreamball's recrypt model
supports the inverse: a new Guild member gets a proxy-recrypted
bundle key but does not automatically inherit historical session
keys. The recrypt model is the right fit for Dreamball's sealed-
artifact primary use case. Causal Keys are only relevant for a
hypothetical "fully open palace history" mode where all members must
reconstruct all history. **Reject as primary model.**

**The Automerge document model** — Keyhive is architected around
Automerge. Dreamball has explicitly rejected Automerge (SHA-256 vs
Blake3, no signing, wrong data model). This rejection is load-bearing
for Dreamball's PQ story. **Reject: not a dependency, not a pattern
to adopt.**

**beelay-core / keyhive_core as a Rust FFI crate** — three reasons:
(1) pre-alpha, no security audit — incompatible with Dreamball's
PQ-integrity positioning; (2) Automerge coupling throughout
keyhive_core's data structures; (3) adding a Rust-compiled WASM
alongside jelly.wasm breaks the "one WASM binary, host-supplied
randomness" invariant (ARCHITECTURE.md ADR-1) and reintroduces the
two-WASM co-existence problem flagged in
`docs/research/crdt-options/findings.md`. **Reject as a crate
dependency; reimplement the algorithms in Zig.**

### Wire-format compatibility with our dCBOR

Keyhive and Beelay use Rust bincode-style serialisation and
Automerge's own binary format — neither is dCBOR. The systems are
wire-incompatible at every level. The Beelay `{message, signature,
sender}` structure could be expressed as a `jelly.peer-message` dCBOR
envelope trivially. BeeKEM tree state would map to a
`jelly.bee-kem-state` envelope. Concap delegation records would map
to a `jelly.delegation` envelope. None of these require protocol
negotiation with Keyhive deployments — we are adopting algorithms,
not federating. This is the same relationship Dreamball has with
NextGraph: strong architectural convergence, zero wire compatibility,
deliberate divergence in envelope format.

---

## Open Questions

1. **PQ-BeeKEM specification.** No published spec for a post-quantum
   BeeKEM variant exists. Implementing this means novel cryptographic
   engineering, not spec-following. Requires a dedicated security-
   focused design document and external review before Zig code lands.

2. **RIBLT standalone WASM.** Is there a production-quality RIBLT
   implementation with a clean WASM compilation story outside of
   beelay-core? The Keyhive RIBLT implementation is entangled with
   the rest of beelay-core. A standalone crate or clean-room Zig
   implementation would be needed.

3. **Guild snapshot vs. CRDT-op-log for membership.** Migrating
   `jelly.dreamball.guild` to a CRDT operation log is wire-breaking.
   The right time to do this is before the first production Guild
   deployment, not after. Flag as a pre-GA decision point.

4. **Sedimentree and the Palace timeline GC protocol.** Implementing
   Sedimentree for `jelly.timeline` requires specifying: who emits
   the level-n stratum blob, who signs it, what the new
   `jelly.stratum` envelope looks like. Needs a spec entry in
   PROTOCOL.md §13 and a compaction ceremony spec in the Guild policy
   model.

5. **BeeKEM "Update Key obligation."** On member removal, at least
   one remaining member must perform an Update Key before the group
   key is fresh. In an async/offline Guild, no member may be
   available to do this promptly. Is a deferred Update Key (applied
   on next reconnect) an acceptable security posture, or does
   jelly-server need to enforce an eager-update policy?

---

## Sources

- [1] https://www.inkandswitch.com/keyhive/notebook/01/ — "Welcome to
  the Keyhive" (Sep 2024)
- [2] https://www.inkandswitch.com/keyhive/notebook/00/ — "Keyhive
  Background"
- [3] https://www.inkandswitch.com/keyhive/notebook/ — notebook index
- [4] https://www.inkandswitch.com/keyhive/notebook/02/ — "Group Key
  Agreement with BeeKEM"
- [5] https://deepwiki.com/inkandswitch/keyhive — architectural
  summary and module inventory
- [6] https://github.com/inkandswitch/keyhive/blob/main/design/sedimentree.md
  — Sedimentree design doc
- [7] https://www.inkandswitch.com/keyhive/notebook/05/ — "Syncing
  Keyhive" (Mar 2025)
- [8] https://www.inkandswitch.com/newsletter/dispatch-014/ — GAIOS
  dispatch
- [9] https://github.com/inkandswitch/keyhive — repository root
- [10] https://recapworkshop.online/recap25/contributions/8-keyhive.html
  — RECAP'25 abstract
