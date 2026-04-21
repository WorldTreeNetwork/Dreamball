# Paper Extract: CRDT-Based Game State Synchronization in Peer-to-Peer VR

**Source:** Dantas, A. & Baquero, C. "CRDT-Based Game State Synchronization in Peer-to-Peer VR." PaPoC '25, March 2025. arXiv:2503.17826v1. DOI:10.1145/3721473.3722144.

**Date extracted:** 2026-04-21

---

## Summary

The paper presents BrickSync, a Unity prototype that lets two Meta Quest 3 users collaboratively place and move virtual bricks in a shared VR space using WebRTC P2P data channels for transport and CRDTs for state synchronization — no persistent server required. The authors measure a 75% latency reduction from remote-server baselines (~200 ms) to P2P (~50 ms average, 18 ms best case), confirming that local P2P with CRDTs is viable for co-present VR collaboration. The work surfaces two hard open problems they leave unsolved: (1) how to design CRDT conflict presentation UX ("ghost placement" style) and (2) how to scale beyond a two-peer mesh without restructuring the protocol.

---

## Extraction: 10 Items

### 1. Architecture — Two-Channel Design

BrickSync uses two WebRTC SCTP data channels over a single RTCPeerConnection:

- **RTT channel** — dedicated to ping/latency measurement only. Used to continuously monitor connection quality and display it in the debug HUD. Carries no game state.
- **CRDT channel** — carries all game-state updates (brick spawn events, position/rotation/scale deltas or full-state snapshots). Configured for **ordered delivery** (SCTP ordered mode), achieving source-FIFO ordering.

The channels are initialized simultaneously. Before either can open, peers go through a standard WebRTC SDP offer/answer exchange via a **WebSocket signaling server** (deployed locally or on Azure). Once P2P is established the signaling server is idle — it plays no role in data exchange. The two channels are otherwise independent: RTT measurements never delay CRDT updates.

A fixed-position **video feed window** shows each participant what their partner sees, providing a visual consistency check above and beyond CRDT state. This is rendered over WebRTC video, not a CRDT channel.

*Section 4.1, §4.1.2*

---

### 2. CRDT Choice

The authors iterated through two approaches:

**Phase 1 — Operation-based CRDTs with Vector Clocks.** Operations are translation offsets computed frame-by-frame. Vector clocks track causal order. The system calculates whether incoming operations have been applied, are pending dependencies, or can proceed. This worked on reliable channels but exposed two fatal flaws: (a) reliable delivery is hard and adds latency; (b) rotation (quaternion → Euler) is non-commutative, so operation order changes final object orientation. Their two workarounds — LWW canonical ordering and delta-averaging — are both acknowledged as "inherently limited."

**Phase 2 — State-based CRDTs, specifically an MV-Transformer.** They designed a custom higher-level CRDT they call **MV-Transformer** (Multi-Value Transformer) that encapsulates a GameObject's full Transform state (position, rotation, scale). It tracks which replica(s) currently hold the object (a "who is touching this" register). It toggles between two modes:

- **World-space mode** (modeled on LWW): synchronizes absolute positions. Under concurrent manipulation, objects "oscillate" as the CRDT reconciles both writers. When one user releases, the object snaps to the peer who held it longest.
- **Local-space mode** (modeled on PN-Counter offset logic): synchronizes deltas relative to each peer's last known position. Prevents oscillation but requires careful handling of positional drift.

They reference Automerge and Yjs but conclude neither is optimized for "dynamic, game-like VR settings." They do not use either library — MV-Transformer is hand-rolled in Unity C#.

No delta-state CRDT library is used. The paper cites delta-state CRDTs as a direction for future scaling work but does not implement them.

*Sections 4.2, 4.2.1, 4.2.2*

---

### 3. Transport

- **Transport layer:** WebRTC data channels over SCTP. SCTP supports both ordered and unordered delivery; they chose ordered.
- **Peer discovery / signaling:** WebSocket server, deployed locally or on Azure (zero cost tier). Implements standard SDP offer/answer + ICE candidate exchange.
- **NAT traversal:** STUN servers. Explicitly needed for Eduroam and semi-public academic networks where peers are behind NATs blocking direct connections.
- **TURN relay:** Not mentioned. Only STUN is discussed; TURN fallback is absent and presumably not implemented.
- **Peer count tested:** Two peers only — one-to-one mesh. "This does not reflect the scalability required for real-world applications."
- **Devices:** PC (Windows/Mac) and Meta Quest 3 (Android 11). A bug was found where WebRTC data channels closed arbitrarily on Quest 3, requiring a channel-renegotiation strategy that "introduced additional latency."

*Sections 4.1, 4.1.1, 4.1.2, 5.1.2, 5.1.3*

---

### 4. Latency Numbers

From Table 5 / Figures 5–11 (Appendix):

| Scenario | WebRTC P2P | Local WebSocket | Azure WebSocket |
|---|---|---|---|
| PC↔PC — Ethernet | **18 ms** | 45 ms | 155 ms |
| PC↔PC — WiFi | **25.75 ms** | 71.5 ms | 174 ms |
| Quest↔PC — WiFi | **46 ms** | 50.5 ms | 165.5 ms |
| Quest↔Quest — WiFi | **87.5 ms** | 111.75 ms | 220.5 ms |
| Quest↔Quest — Hotspot | **74 ms** | 215 ms | 236.25 ms |

**Key quote (§6):** "The average latency in P2P configurations is approximately 50 ms, a 75% reduction from the 200 ms observed in remote server connections." P2P outperforms WebSocket by a factor of 2 in optimal conditions.

**Threshold context (§2.1):** Prior research cited establishes that photon-to-motion latency exceeding 100 ms "significantly degrades user experience," and network delays over 230 ms "impair task performance." Quest↔Quest WiFi at 87.5 ms sits comfortably under both thresholds. Quest↔Quest over Azure at 220.5 ms approaches the impairment boundary.

**Where it breaks:** Not systematically measured beyond two peers. The authors note that vector clocks scale linearly in message size with peer count and that state-based CRDT payloads grow proportionally to state size.

**WebRTC payload limit:** 16 KB maximum per message. Their test payloads stayed under this but they flag that larger state will require message chunking.

*Sections 5.4, 6; Appendix A*

---

### 5. Consistency Semantics and Conflict Visualization

The observable anomaly in world-space mode is **object oscillation**: when two users simultaneously grip and move the same brick, CRDT merge repeatedly reconciles their positions, causing the object to visibly oscillate between their controlled positions until one releases. "While not significantly affecting user experience" is their self-assessment, but they acknowledge it raises questions.

Their proposed but not-implemented conflict resolution strategies:

1. **LWW** — most-recent update wins. Clean but eliminates collaborative feel.
2. **Goal-aware heuristics** — favor positions aligned with apparent shared intent (e.g., building a straight wall).
3. **Averaging** — concurrent opposite-direction manipulations converge on the midpoint.
4. **Constraint-based mutual exclusion** — prevent simultaneous manipulation entirely (labeled "last resort").
5. **Dynamic Strategy Switching** — the most interesting proposal: the CRDT itself detects interaction patterns and context and switches between heuristic/LWW/constraint modes at runtime. Example: "default to heuristic-based reconciliation, or last-writer-wins during cooperative tasks but switch to constraint-based mechanisms in competitive or high-conflict scenarios."

**Their core conclusion on UX (§4.2.2):** "The effectiveness of CRDT-based architectures hinges on how divergences ... are presented to users. Providing clear, consistent, and navigable representations of these inconsistencies is crucial for collaboration."

They explicitly invoke dead-reckoning from multiplayer games as a prediction layer that could smooth perceived conflicts.

*Sections 5.3, 4.2.2*

---

### 6. Ephemeral vs. Durable Split

The paper does **not** distinguish between ephemeral state (player pose, cursor, transient object grab) and durable state (object placement that persists after the session). All state — brick positions, who is holding what, poses implied by manipulation — flows through the same CRDT channel with the same consistency semantics.

They pay for this in two ways:
- Player-position-type data (continuous transform updates) generated oscillation artifacts when CRDT merge frequency was high
- The "who is holding this object" tracking is folded into the MV-Transformer as a replica-ownership field, not separated out as a presence channel

The authors do not name this as a design trade-off. The absence of an explicit ephemeral/durable split is the paper's most significant gap relative to production-grade shared spaces.

*Sections 4.2, 4.2.2, 5.3*

---

### 7. Authentication and Authorization

There is **no authentication, no signing, and no encryption** in BrickSync.

Direct quote (§5.1.3): "We assume a non-Byzantine environment, meaning malicious peers are not accounted for in the current design."

Any peer who can reach the signaling server and complete the SDP handshake can join, send arbitrary CRDT updates, and have them merged into every other peer's state. The CRDT channel has no identity layer. The video feed channel is equally unauthenticated.

This is an explicit scope limitation, not an oversight — the paper is a P2P + CRDT feasibility study, not a security system.

*Section 5.1.3*

---

### 8. Failure Modes

**Peer drop:** CRDTs inherently handle this — each replica continues operating independently. State diverges locally during the partition. No explicit reconnection logic is described; the authors rely on CRDT eventual consistency to merge on reconnect.

**Mid-move drop:** Not explicitly tested. The MV-Transformer's replica-ownership tracking would leave an object "stuck" in the dropped peer's grip state until they rejoin and release, or until the remaining peer's LWW timeout fires (in world-space mode).

**Channel close (Quest-specific bug):** WebRTC data channels closed arbitrarily on Meta Quest 3 (speculated to be Android security policies or Meta Quest OS constraints). A renegotiation strategy was implemented that reopened channels when closed unexpectedly. Cost: "additional latency" and the need to specify channel IDs during initialization. This had implications for idempotency — state-based CRDTs proved more robust here because full-state retransmission on channel reopen is safe.

**High packet loss:** State-based CRDTs provide robustness through full-state retransmission. Op-based CRDTs would lose operations and produce inconsistent state under packet loss without additional sequence tracking.

**Network heterogeneity:** Testing in "semi-public networks" (Eduroam) caused erratic system behavior. Workarounds: mobile hotspots and a remotely-hosted signaling server. STUN alone was insufficient in some network configurations.

*Sections 5.1.2, 5.1.3*

---

### 9. Scaling Limits

The paper is explicit that their work does not address scaling:

**Two peers only.** The entire measurement campaign is 1-to-1. "This does not reflect the scalability required for real-world applications."

**Vector clock scaling (§5.4):** "In scenarios with high numbers of replicas vector clocks become inefficient due to their size, that scales linearly with the number of nodes, resulting in significant metadata and communication overhead."

**State-based bandwidth:** Full-state transmission on every update. Grows proportionally to total state size, not operation size. This is acceptable with two peers but breaks down with more.

**WebRTC mesh scaling:** Not discussed explicitly, but the pairwise WebRTC model implies O(n²) connections. No SFU-style relay, no gossip protocol, no fan-out mechanism is mentioned.

**Delta-state CRDTs** are flagged as a future direction: "Delta-state CRDTs reduce bandwidth via incremental update transmission but still require end-to-end mechanisms guaranteeing causal consistency." They implement none.

**Their scaling future work:** "Scalability research with larger user and object numbers in complex VR environments" is listed first among research priorities.

*Sections 5.4, 7*

---

### 10. Open Questions They Flag

From §7 (Future Work) and §3 (Methodology):

1. **Dynamic Strategy Switching** — embedding adaptive conflict-resolution logic directly into CRDT implementations that switch between heuristic, LWW, and constraint modes based on interaction context. Their primary unsolved problem.
2. **Global Rules** — how to handle non-user-authored state changes (gravity, physics, wind, enemy spawning, chain reactions) in a CRDT model where every update is supposed to have an "author." They propose the concept but provide no solution.
3. **Local-first VR** — applying local-first principles (offline capability, sync-on-reconnect, user data ownership) systematically to VR environments.
4. **Proximity-aware network topologies** — routing updates preferentially to physically co-present peers to reduce latency further.
5. **Scalability beyond 2 peers** — both in WebRTC topology and CRDT overhead.
6. **Synchrony conditions** — the paper explicitly did not address behavior under prolonged partitions or significant message loss.

*Sections 3, 7*

---

## Dreamball Framing Questions

### How does their architecture map onto our three DreamBall types (Field/Avatar/Object)?

Their single CRDT channel carries what maps to all three of our types without differentiation. For Dreamball the natural decomposition is:

- **Field (jelly.dreamball.field):** The palace environment is durable, authored by the curator, and changes rarely. It maps to their brick-spawn state — long-lived object insertions that should be on the CRDT/durable channel. One key difference: their bricks have no independent identity or signature. Ours are signed DreamBall envelopes with a `jelly.layout` placement record.
- **Avatar (jelly.dreamball.avatar):** Player pose, movement, and presence are the pure ephemeral stream — equivalent to their continuous transform updates that caused oscillation when run through the CRDT. Their architecture collapses this into the same channel as object placement and pays with oscillation artifacts. We should explicitly route Avatar pose onto a **separate ephemeral channel** (WebRTC unreliable/unordered datagram) and never put it into the jelly.timeline DAG.
- **Tool/Object (jelly.dreamball.tool or any placed object):** Corresponds to their manipulable bricks — the state that benefits from CRDT merge semantics and should be durable. Their MV-Transformer per-brick maps to our `MV-Register`-per-item in `jelly.layout`. The "who is holding this" tracking in MV-Transformer is worth implementing as a presence field parallel to placement, not embedded in the placement CRDT itself.

### What can we reuse verbatim, what do we adapt, what do we do differently?

**Reuse verbatim:**
- The two-channel split: a lightweight dedicated latency/heartbeat channel (their RTT channel) and the data channel. Adopt this exactly.
- STUN for NAT traversal in co-present guild contexts.
- WebSocket signaling server as a thin bootstrapping layer (their approach is functionally identical to our `jelly-server`-as-signaling-hub plan).
- The ordered SCTP data channel for durable CRDT state (their CRDT channel → our `jelly.timeline`/`jelly.layout` channel).
- The insight that "CRDTs are a natural fit for architecting shared game-state in collaborative systems" — this validates our Merkle-DAG / MV-Register architecture choices.

**Adapt:**
- Their MV-Transformer (per-object multi-value state) maps to our `MV-Register`-per-item in `jelly.layout`, but we need to add a **signed authorship field** on every placement update so the "who last touched this" provenance is cryptographically asserted, not just tracked in memory.
- Their oscillation fix (world-space LWW + hold-length tiebreaker) is a reasonable default for our ghost-placement UX. Adapt as: show both positions as translucent "ghost" states while merge is pending, then snap when one author releases — cleaner than invisible oscillation.
- Their Dynamic Strategy Switching proposal is exactly what our `MV-Register` conflict policy needs. Implement a context-aware mode: cooperative (guild members co-building) defaults to averaging/midpoint; competitive (arena tool placement) defaults to LWW.

**Do differently (crypto substrate changes the picture):**
- Authentication and signing: every `jelly.action` on our timeline is signed by the acting identity. This eliminates their non-Byzantine assumption as a security requirement — we verify before merging. This is the core Dreamball differentiator.
- Encryption: Guild keyspace + proxy-recryption means co-present peers share a keyspace and can send encrypted CRDT updates. Their updates are plaintext. Ours need an envelope-level encryption layer on the WebRTC channel (or at minimum guild-key-signed payload integrity).
- Durable state is not just in-memory: our `jelly.timeline` DAG and `jelly.layout` MV-Register are persisted signed CBOR, not ephemeral Unity MonoBehaviours. The merge function on reconnect is a DAG head reconciliation, not a simple LWW timestamp comparison.
- No persistent server dependency for state: our jelly-server is a relay and signaling hub but the authoritative state is the signed DAG that any peer can hold. Their setup requires the signaling server for any reconnect.

### Measurements/numbers worth citing in the Dreamball multiplayer PRD

- P2P WebRTC RTT: **18 ms** (PC↔PC ethernet, best case), **87.5 ms** (Quest↔Quest WiFi, worst co-present case) — both well under the 100 ms immersion-degradation threshold.
- P2P outperforms relay server by **~75%** on average (50 ms vs 200 ms).
- Quest↔Quest WiFi WebSocket (non-P2P local relay): 111.75 ms — still under 230 ms task-impairment threshold, meaning jelly-server as relay fallback is acceptable quality-of-service.
- Quest↔Quest Azure relay: 220.5 ms — approaching the 230 ms impairment boundary. Remote relay is a last resort, not a primary path.
- 16 KB WebRTC SCTP payload ceiling — relevant for sizing `jelly.layout` update messages; large palace state snapshots will need chunking.

### What doesn't apply because of our crypto-first substrate?

1. Their "non-Byzantine" assumption is the entire security model — or lack thereof. Our signed CBOR envelopes and Ed25519/ML-DSA authorship on every action mean we can operate in adversarial (Byzantine-lite) contexts. Any peer injecting a forged update will fail signature verification before merge.
2. Their in-memory CRDT state (Unity MonoBehaviour) has no persistence or export. Our state is the signed DAG itself — the CRDT *is* the archive.
3. Their "who is holding this" ownership tracking is informal and lost on disconnect. Our `jelly.action` timeline records every grab/release as a signed action with actor fingerprint — the history is forensic.
4. Their conflict resolution is purely geometric (positions, rotations). Ours extends to semantic conflicts (two users simultaneously true-naming a DreamBall, FR60g) where the quorum-policy mechanism applies, not averaging.

### The single most valuable sentence in the paper for our framing

Section 4.2.2:

> "The effectiveness of CRDT-based architectures hinges on how divergences ... are presented to users. Providing clear, consistent, and navigable representations of these inconsistencies is crucial for collaboration."

This is the design imperative for our "ghost placement" UX: the CRDT resolves state eventually, but the user experience of *seeing* the divergence and *understanding* it is the product problem. The paper demonstrates this is unsolved in their prototype; Dreamball needs a concrete answer in the PRD.

---

## What to Cite in the Dreamball Multiplayer PRD

Use these specific results when writing the multiplayer design rationale:

**Architecture validation:**
> Dantas & Baquero (PaPoC '25) demonstrate that CRDTs over WebRTC P2P achieve 18–87 ms RTT for co-present VR peers — well under the 100 ms immersion threshold — while a relay-server architecture reaches 165–220 ms on the same hardware, approaching the 230 ms task-impairment boundary. This validates Dreamball's hybrid design: WebRTC P2P for co-present guild members, jelly-server relay only as fallback.

**Two-channel split:**
> They confirm a clean separation between a heartbeat/RTT measurement channel and the CRDT state channel. Dreamball adopts this: one lightweight presence/heartbeat channel (ephemeral Avatar poses, ping), one ordered data channel (jelly.timeline actions, jelly.layout placement MV-Register updates).

**Ephemeral/durable gap (Dreamball differentiator):**
> BrickSync routes all state through a single CRDT channel and pays with oscillation artifacts under concurrent manipulation. Dreamball explicitly separates Avatar pose (unreliable ephemeral datagram) from Object placement (ordered durable CRDT channel). This is the primary architectural lesson extracted from their prototype.

**Ghost placement UX:**
> Their MV-Transformer oscillation behavior and §5.3 conflict visualization discussion are the published baseline for our ghost-placement design. We should cite their Dynamic Strategy Switching proposal as the motivation for our context-aware MV-Register policy (cooperative vs. competitive mode).

**Scaling caveat:**
> The paper's measurements are two-peer only. Scaling beyond a small guild mesh (>6–8 peers) requires moving away from a pairwise WebRTC model. Dreamball's guild-scoped keyspace naturally bounds co-presence to guild size, keeping the mesh manageable for the product's initial target (intimate palace sessions, not MMO scale).

**Auth as differentiator (no citation needed — it's our gap they don't fill):**
> BrickSync assumes a non-Byzantine environment with no authentication or signing. Dreamball's signed CBOR envelopes and Ed25519/ML-DSA-87 authorship on every jelly.action are the cryptographic gap the paper leaves open; filling it is our protocol's core value proposition.
