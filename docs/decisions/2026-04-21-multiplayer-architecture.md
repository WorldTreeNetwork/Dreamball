# 2026-04-21 — Multiplayer architecture: three layers, P2P-first, server as convenience

## Status

Accepted as the architectural shape for shared-palace multiplayer
(Memory Palace PRD J4, FR68, the broader "walk a palace together"
capability). Lands as a decision now, before transport code is
written, because the three layers and their wire boundaries are
expensive to refactor once chosen. Paired with
`2026-04-21-presence-channel-wire.md` for the presence-frame
specification.

## Context

Memory Palace shared rooms are the first piece of Dreamball that
needs real-time multi-writer sync. The literature in this space
consolidated during 2024–2025 around three architectural choices
worth committing to:

1. **Ephemeral state (pose, presence, cursor, "I'm looking at this")
   must NOT go through the signed CRDT**. Loro shipped
   `EphemeralStore` in v1.8.0 (Sep 2025) explicitly for this; Yjs has
   the `Awareness` protocol; Automerge Repo has awareness hooks; all
   converge on the same split. Dantas & Baquero's VR CRDT paper
   (PaPoC '25) is the clearest demonstration of what goes wrong
   without the split — they see visible oscillation when two users
   grip the same object, directly traceable to routing ephemeral
   state through an ordered CRDT channel.
2. **P2P WebRTC data channels deliver 50ms latency vs ~200ms for a
   server relay** (ibid., §5.4) — a 75% reduction that stays under
   the 100ms immersion-degradation threshold. P2P is not optional
   for palace-presence quality; a server-relay-only palace would be
   perceptually broken.
3. **Capability-based authorization + signed delegation DAGs** are
   what local-first systems need for offline-tolerant access
   control. Ink & Switch's Keyhive project (particularly Convergent
   Capabilities, BeeKEM, Sedimentree) is the most complete published
   reference; its primitives are algorithm-level adoptable without
   taking a Rust dependency.

Supporting research:
- `docs/research/vr-crdt-sync-paper-extract.md` — Dantas & Baquero
  full extraction
- `docs/research/keyhive-review/findings.md` — Keyhive pattern
  analysis for Dreamball
- `docs/research/crdt-options/findings.md` — CRDT candidate survey
  (Automerge, Yjs, Loro, Fugue, primitives)
- `docs/decisions/2026-04-21-nextgraph-crdt-review.md` — NextGraph
  diff note (for the signed-DAG baseline)

## Decision

### The three-layer architecture

```
┌──────────────────────────────────────────────────────────────┐
│ DURABLE          jelly.action DAG + jelly.layout + mythos    │
│ (signed)         Ed25519 + ML-DSA-87, dCBOR, Blake3-addressed │
│                  MV-Register for layout conflicts             │
│                  Syncs via Beelay-pattern envelope            │
│                  Sedimentree compaction, RIBLT reconciliation │
│                  Head-hashes set (today's protocol tweak)     │
│                                                                │
│   ▲ (release, finalise, persist)                              │
│   │                                                            │
├──────────────────────────────────────────────────────────────┤
│ PRESENCE         pose, voice, "looking at", "holding this"    │
│ (ephemeral)      raw CBOR frame, session-MAC, NO per-frame sig│
│                  30Hz broadcast-and-forget, TTL on receive    │
│                  Loro-EphemeralStore-shaped (LWW + TTL)       │
│                  Session key from Guild recrypt handshake     │
│                                                                │
│   ▲ (WebRTC data channel direct; WS relay fallback)           │
│   │                                                            │
├──────────────────────────────────────────────────────────────┤
│ TRANSPORT        WebRTC mesh between co-present Guild members │
│                  jelly-server: signaling hub + fallback relay │
│                  Guild capability gates room entry            │
│                  STUN for NAT (no TURN in MVP)                │
└──────────────────────────────────────────────────────────────┘
```

**Rule of thumb for placing state.** If it's persistently part of
the palace when nobody is present, it's durable. If it's only
meaningful while a wayfarer is in the room, it's presence. "Where
you are right now" is presence; "where you put this scroll" is
durable. Some state lives in both — the transition "you picked up
a scroll and carried it" is presence-hot (the pose updates stream
over the fast channel); the transition "you put it back down at a
new position" is durable (one signed `jelly.action` on release).

### Adopted from Keyhive (algorithms, not libraries)

Per `docs/research/keyhive-review/findings.md`:

- **Sedimentree compaction** for `jelly.timeline` garbage
  collection. Stratum level = leading zero nibbles in a
  `jelly.action`'s Blake3 hash. Level-n strata compact ~16^n
  actions. Adds one new envelope (`jelly.stratum`) to PROTOCOL.md
  §13. Purely algorithmic; no Keyhive dependency.
- **RIBLT** (Rateless Invertible Bloom Lookup Tables) for Guild
  membership and timeline head reconciliation. Standalone
  algorithm; 5 differences in 10⁹ items reconcile in ~7.5 × 32-byte
  symbols.
- **Beelay envelope pattern** for peer-to-peer sync messages —
  `{ payload, audience, timestamp, sender-sig }`. The `audience`
  field binds the message to a recipient pubkey (PITM-forwarding
  defence); `timestamp` with clock-skew window blocks replays.
  Adopt the shape, reimplement in Zig with Ed25519 + ML-DSA-87
  dual sigs. Name this envelope `jelly.peer-message`.

### Adopted from NextGraph (already landed 2026-04-21)

- `jelly.timeline.head-hashes` (set, v3) — transiently holds
  multiple heads during concurrent writes.
- `jelly.action.deps` / `.nacks` optional attributes — NextGraph
  DEPS/NACKS semantics.
- `jelly.quorum-policy` via stacked per-admin `'signed'`
  attributes — rejects threshold-aggregate schemes that can't
  compose with ML-DSA-87.

### Adopted from Dantas & Baquero VR paper

- **The oscillation-as-bug-report.** Their MV-Transformer world-
  space mode oscillates because two peers write the same position
  through an ordered CRDT. We avoid this by design: presence
  channel handles the "while held" trajectory (high frequency, no
  consistency promise), durable channel handles the final resting
  position via MV-Register (conflict surfaces as ghost-placement,
  not oscillation).
- **Their local-space-mode drift warning.** Their offset-based
  mode prevents oscillation but accumulates drift. We need a
  bounded-drift strategy for MV-Register resolution — documented
  as an open question in PRD §9 and spike acceptance criterion.
- **Latency budget.** P2P mesh target: <100ms room-to-room-peer
  presence latency. Server-relay fallback: <300ms with degraded-
  lane indicator in UI.

### Rejected — with reasoning

- **Rust FFI on beelay-core / keyhive_core.** Pre-alpha, unaudited,
  Automerge-coupled, and adding a second Rust-compiled WASM next
  to `jelly.wasm` violates ARCHITECTURE.md ADR-1's one-WASM
  invariant. We adopt the ideas; we write the code in Zig.
- **Causal Keys for per-action encryption.** Keyhive trades forward
  secrecy for history access. Dreamball's recrypt model is the
  inverse — new Guild members get a rewrap for the current state,
  not historical keys. Our model is correct for sealed-artifact
  use; Causal Keys solve a different problem.
- **TURN-relayed WebRTC for MVP.** MVP is local network + STUN only.
  Shipping TURN means running (or paying for) TURN infrastructure,
  which doesn't belong in Phase 0. Server-WebSocket fallback
  covers users who can't NAT-punch; they experience the 200ms
  relay lane with a visible degraded indicator.
- **SFU (Selective Forwarding Unit) topology.** MVP is a WebRTC
  mesh. SFU becomes necessary around 8+ peers; we don't reach that
  in the MVP palace. Flag as Growth-tier when the first palace
  sees real multi-user load.
- **Per-frame presence signing.** ML-DSA-87 signatures are ~4.6 KB
  each. At 30Hz × 20 peers × one sig-per-frame, we'd blow the
  entire WebRTC bandwidth budget on signatures. Presence is
  session-MAC'd after a signed handshake. See
  `2026-04-21-presence-channel-wire.md`.

### Deferred explicitly

- **BeeKEM-style rotating group session keys.** Our current model
  (recrypt proxy-recryption of a static Guild key) has no ratchet
  and no post-compromise security. A PQ-BeeKEM variant (X25519 →
  ML-KEM-768 at tree nodes) would close this. **Deferred** because
  no published PQ-BeeKEM spec exists; implementing one is novel
  cryptographic engineering that wants a dedicated security-design
  document and external review before Zig code lands. Tracked as
  Growth-tier. For MVP, the session MAC key is derived from the
  current static Guild key and rotated per-session (per wayfarer
  entering the room), not per-message.
- **Convergent Capabilities for `jelly.dreamball.guild`**. Moving
  Guild membership to an OR-set operation log with signed tombstones
  would improve offline-concurrent Guild edits. Wire-breaking
  change; belongs before first production Guild deployment.
  Tracked Vision-tier.
- **Global Rules / physics / ambient state** (Dantas & Baquero's
  named open problem). Our Vril flow + aqueduct conductance is
  exactly this category. The decision: treat ambient state as
  *emergent from signed presence+timeline events*, not as a
  globally simulated continuous field. Aqueducts brighten because
  people traversed; Vril pools because rooms were visited; no
  central physics tick. This is a Dreamball-specific answer to an
  unsolved field problem, enabled by our timeline design.

## Consequences

### Protocol additions (future; not landing in this ADR)

- `jelly.peer-message` — Beelay-pattern peer sync envelope
  (durable-channel payload wrapper).
- `jelly.stratum` — Sedimentree compacted-strata envelope.
- `jelly.presence-frame` — the raw presence-channel frame format
  (specified in paired ADR, never stored in CAS).
- `jelly.session-handshake` — establishes session MAC key at room
  entry, signed with hybrid Ed25519+ML-DSA-87 once.

### Code structure

- `src/lib/multiplayer/` — new module for client-side WebRTC +
  presence + durable-sync orchestration.
  - `signaling.ts` — WebRTC offer/answer via jelly-server WS.
  - `presence.ts` — raw-CBOR frame send/recv, session MAC, TTL
    cache.
  - `durable.ts` — jelly.peer-message encode/decode, Sedimentree
    sync, RIBLT reconciliation.
  - `room.ts` — lifecycle: join → handshake → presence stream
    starts → durable replay → user-visible "ready".
- `jelly-server` extensions:
  - `/signal/:room-fp` WebSocket — SDP/ICE relay, Guild-gated.
  - Existing timeline endpoints — unchanged, used for durable
    fallback when peers can't WebRTC each other.
- Zig side:
  - `src/presence.zig` — frame encode/decode + session MAC.
  - `src/sedimentree.zig` — stratum-boundary detection and
    compaction.
  - `src/riblt.zig` — set reconciliation.
- No changes to `jelly.wasm` boundary — multiplayer runs in host
  JS/TS with WASM only for crypto primitives already exported.

### Guild capability semantics

- A Guild member's DreamBall fingerprint is their identity in the
  signaling/presence/durable flows.
- Signaling hub (`/signal/:room-fp`) rejects non-Guild fingerprints
  before SDP exchange, with a clear error.
- Session MAC key is derived from the Guild's current session
  material (post-recrypt) using HKDF over `(guild-fp, room-fp,
  session-id, timestamp)`.
- On Guild membership change, the next session a peer enters uses
  a fresh MAC key. Active sessions continue under their existing
  MAC; a removed member's session expires on natural TTL (typically
  5 minutes) or an explicit kick-action from a Guild admin.
- **This MVP model has no in-session key rotation** — that's the
  BeeKEM gap above. A compromised MAC key lets an attacker read
  presence traffic for up to one session window. Durable state is
  still signed; it cannot be forged. The attack surface is
  "observe pose + voice", not "fake a palace modification". This
  is acceptable for MVP; explicitly documented as a known
  limitation.

## Verification strategy

- Minimal spike (~1 week): two browsers, one palace, one room, two
  avatars. WebRTC data channel via jelly-server signaling. 30Hz
  pose broadcast renders the other user's capsule. Pick up and
  drop an object → durable `jelly.action move` persists across
  reload. Acceptance: <100ms presence latency on localhost, no
  signatures on pose frames.
- Maximal-delight spike (~2-3 weeks on top of minimal): Guild
  gating at signaling, MV-Register ghost-placement on concurrent
  moves, Vril shimmer driven by presence traffic, rejoin-after-
  offline via RIBLT, jelly-server kill-test (WebRTC mesh
  continues).

Success = "this palace feels alive with two people" at the
maximal-delight tier.

## References

- Paired ADR: `2026-04-21-presence-channel-wire.md`
- `docs/research/vr-crdt-sync-paper-extract.md`
- `docs/research/keyhive-review/findings.md`
- `docs/research/crdt-options/findings.md`
- `docs/decisions/2026-04-21-nextgraph-crdt-review.md`
- Dantas & Baquero, "CRDT-Based Game State Synchronization in
  Peer-to-Peer VR", PaPoC '25: https://arxiv.org/abs/2503.17826
- Ink & Switch Keyhive notebook:
  https://www.inkandswitch.com/keyhive/
- PROTOCOL.md §12.7 (`jelly.guild-policy`, `quorum-policy`), §13.3
  (`head-hashes`, `deps`, `nacks`)
- Memory Palace PRD §9 (Phase 0 must-reads, FR68, FR79)
