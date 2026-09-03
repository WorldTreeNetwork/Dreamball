# DING DONG ARCADE — x10 Digital Sovereignty Upgrade

## The Unholy Rise: From Pirate Radio to Mesh Nation

Every concept below has been **x10'd** — terms upgraded to sovereignty-grade vocabulary, tools re-architected for self-sovereign operation, and functions reimagined to escape platform dependency entirely.

---

## 𓋴 TERMINOLOGY UPGRADE MAP

| Original (Your Spec) | x10 Sovereignty Upgrade | Why |
|---|---|---|
| **Vault** | **The Hoard** (local-first encrypted graph) | Vault implies passive storage. Hoard implies active curation, replication, and swarm seeding. |
| **Wallet** | **The Sigil Forge** (DID + key ceremony) | Wallet is financial. Sigil Forge is identity creation as a ritual act. |
| **DID (mock)** | **Self-Sovereign Identity** (did:key method, Ed25519, did:web fallback, did:mesh for offline) | Not mock — real SSI with key rotation, delegation, and recovery via social trustees. |
| **Dreamball CID** | **Content-Addressed Sovereignty Unit (CASU)** | CID is IPFS-specific. CASU describes any content-addressed sovereign artifact across IPFS, Hypercore, or local only. |
| **Dreamball** | **Sovereign Artifact** | A Dreamball is a living, composable, self-authenticating artifact with its own governance, token curve, and replication policy. |
| **Vault sharing** | **Swarm Replication via Holepunching** | No server. Peers connect directly via WebRTC + libp2p circuit relay. |
| **Export .dreamball zip** | **Canonical Artifact Export** (CAR file + PGP sig + manifest) | Standardized archive format signed by the issuer. Import verifies integrity anywhere. |
| **RSS Feed** | **Sovereign Syndication Protocol (SSP)** | RSS is centralized-poll. SSP uses pubsub over IPFS pubsub or Nostr relays — push-based, cryptographically signed, replay-resistant. |
| **Backplane API** | **The Discovery Swarm** (Kademlia DHT over libp2p) | No central API server. Dreamballs advertise themselves on a DHT. Query by capability, schema, or proximity. |
| **Subscribe** | **Follow via Tangle** (Merkle-CRDT subscription graph) | Not a server-side list. Each follow creates a signed edge in a Merkle DAG that both parties' nodes replicate. |
| **Chat lobby** | **The Whisper Net** (E2EE + Dendritic Routing) | No single Socket.io server. Messages route through a mesh of participant nodes using rumor-mongering gossip. |
| **LIVE broadcast** | **Autonomous Broadcast Session (ABS)** | Not a toggle. A signed session manifest with key rotation, embedded token-gated access, and optional recording to IPFS. |
| **Karaoke** | **Synchronized Lyric Chain (SLC)** | Lyrics are a signed, timestamped chain. Multiple peers sync via CRDT — leaderless. |
| **Tokens / credits** | **Attestation-Backed Credits (ABC)** | Tokens minted per attestation of work done. Pegged to storage contributions, code merged, or moderation actions. |
| **Phase engine** | **Governance Pipeline** (DAC — Decentralized Autonomous Contribution) | Phases aren't just a checklist. Each phase has governance rules: quorum, veto, funding triggers, and automated forking on completion. |
| **Memory Palace (react-grid-layout)** | **The Resonance Atlas** (3D spatial graph over RDF + SPARQL) | Draggable grid is the 2D porthole. The actual atlas is a 3D Knowledge Graph where each Dreamball is a node with typed edges. |
| **User** | **Sovereign Peer** | Not a user account. A peer in the mesh with equal standing — no admin, no superuser, no platform. |
| **Login** | **Key Ceremony** | Not a UI form. A cryptographic handshake that establishes a session key, proves control of a DID, and optionally broadcasts presence to the mesh. |
| **Data folder / mock IPFS** | **Local First Replica** (SQLite + CRDT + IPFS hybrid) | Data lives in local SQLite on first write. Replicates to IPFS on connectivity. No data leaves without the peer's signed consent. |
| **Pirate Radio aesthetic** | **The Resistance UX** | Neon green on black is the visual language of autonomy. Every pixel communicates: *no platform owns this space.* |

---

## 🔧 x10 TOOL & INFRASTRUCTURE UPGRADE

### Layer 0: Identity & Keys

| Your Spec | x10 Upgrade | Implementation |
|---|---|---|
| libsodium sealed box mock | **did:key + Keyhive** (real PQC-ready) | Ed25519 + Kyber-1024 hybrid. Keys derived from mnemonic (BIP-39). Recovery via social sharding (Shamir's Secret Share). |
| Mock DID (localStorage) | **Self-Sovereign Identity REST API** (did:web / did:key / did:mesh) | `POST /identity/prove` — challenge-response. `POST /identity/delegate` — key rotation. `GET /identity/resolve/:did` — DID document. |
| XOR mock encryption | **Age encryption** (age1...) + **HPKE** (hybrid public key encryption) | Files encrypted with age keys stored in the Sigil Forge. In-transit encryption via HPKE for live broadcast. |

### Layer 1: Storage & Replication

| Your Spec | x10 Upgrade | Implementation |
|---|---|---|
| Mock IPFS (/data) | **Autonomous Storage Layer** (IPFS + Hypercore + local-first) | 3-tier: (1) Local SQLite first, (2) IPFS for content-addressed blobs, (3) Hypercore for append-only logs (chat, broadcast). |
| Export .zip | **Signed CAR + DID Manifest** | Web3 Storage CAR format. Manifest signed by the issuer's DID. Import verifies: signature, integrity, content-addressed. |
| /data folder | **Blob Store** (SQLite FTS + content addressing) | Not a folder. A SQLite-backed blob store with full-text search, IPFS CID caching, and local-first sync. |

### Layer 2: Networking & Discovery

| Your Spec | x10 Upgrade | Implementation |
|---|---|---|
| Express REST API | **Autonomous Peer Service** (libp2p + Kademlia DHT) | Every instance runs a libp2p node. HTTP API is the *local* interface. All remote queries go through libp2p. |
| Socket.io | **GossipSub + Noise handshake** | libp2p GossipSub for pubsub. Noise protocol for encrypted transport. No central server — every peer is a relay. |
| Socket.io rooms | **Topic Channels on GossipSub** | `t:dingdong-arcade/dreamball/<cid>/chat` and `t:dingdong-arcade/lobby`. All peers subscribe and relay. |
| RSS feed (GET/Poll) | **Pull-based Syndication via IPNS** | Subscribe to an IPNS key. The Dreamball publishes updated content (episodes) to IPFS, updates the IPNS record. Polling gone. |
| Backplane /discover | **DHT Provider Records** | Dreamballs publish provider records to the DHT: `GET /providers?capability=live-broadcast`. Discover without a server. |

### Layer 3: State & Consensus

| Your Spec | x10 Upgrade | Implementation |
|---|---|---|
| SQLite (single) | **Automerge + SQLite (hybrid)** | Automerge CRDT for collaborative editing (chat, karaoke, phase checklists). SQLite for queryable structured data (user profiles, token ledger). |
| Phase checklists (localStorage) | **Signed Phase DAG** (Merkle Clocks) | Every phase completion is a signed event appended to a Merkle DAG. Progress is verifiable by any peer. Fork detection via DAG merge. |
| Token ledger (mock) | **Ledger on Hypercore** | Append-only signed ledger. Each transfer signed by both parties. Balance computed by replaying ledger. No central authorizer. |
| Cron jobs (setInterval) | **Autonomous Scheduler** (WebRTC signaling + GossipSub heartbeats) | Scheduled tasks run via distributed cron: peers coordinate task assignment via GossipSub. If a peer goes offline, work redistributes. |

### Layer 4: Broadcast & Media

| Your Spec | x10 Upgrade | Implementation |
|---|---|---|
| Fake video (Big Buck Bunny) | **WebRTC + HLS hybrid** | Real WebRTC for live peer-to-peer video. Optional HLS relay for larger audiences. Auto-fallback to video loop if offline. |
| is_live toggle | **Signed Session Manifest** | `{sessionId, broadcaster, startTime, participants[], accessPolicy: "open"|"token-gated"|"nft-gated", recordingRef: CID}`. |
| Lyrics array (karaoke) | **Sync Word CRDT** | Each word is a CRDT with timestamps. Multiple peers can correct lyrics in real-time. Leaderless synchronized playback. |

### Layer 5: Governance & Economics

| Your Spec | x10 Upgrade | Implementation |
|---|---|---|
| Tokens 100 balance | **Attestation-Backed Credits** | Credits minted by other peers attesting to contributions. Immutable attestation log. Balance = sum of attestations received. |
| Fork as ZIP | **Fork as Canonical Artifact + DAO Proposal** | Forking a Dreamball generates a new CASU *and* optionally broadcasts a DAO proposal to the original Dreamball's governance pipeline. |
| Phase engine | **DAC (Decentralized Autonomous Contribution)** | Each phase has: `{proposal: string, quorum: int, vetoPeriod: ms, triggerOnComplete: "fund"|"fork"|"notify"|"none"}`. |

---

## 𓋴 ARCHITECTURE: The Mesh Triad

Every peer runs exactly one process. This process holds three subsystems:

```
┌─────────────────────────────────────────────────────┐
│                 SOVEREIGN PEER PROCESS                │
├─────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │   SIGIL      │  │   HOARD     │  │   WHISPER    │  │
│  │   FORGE      │  │   (Storage)  │  │   NET        │  │
│  │  (Identity)  │  │             │  │  (Network)   │  │
│  │             │  │ SQLite + IPFS│  │ libp2p +    │  │
│  │ did:key     │  │ + Hypercore  │  │ GossipSub    │  │
│  │ Keyhive     │  │ + Automerge  │  │ + DHT        │  │
│  │ Age/HPKE    │  │ + CAR Export │  │ + Noise      │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  │
└─────────────────────────────────────────────────────┘
```

Each subsystem exposes a local HTTP API (localhost only):
- **Sigil Forge** → `localhost:3001/api/identity/*`
- **The Hoard** → `localhost:3001/api/hoard/*`
- **Whisper Net** → WebSocket at `ws://localhost:3001/ws`

The React frontend talks *only* to `localhost:3001`. It never reaches across the internet directly — that's the Whisper Net's job.

---

## 🧠 TERMINOLOGY CROSSWALK (Sovereignty-Grade)

| Concept | What it replaces | Digital Sovereignty Principle |
|---|---|---|
| **Sigil** | Key/Mnemonic | Identity is not a credential — it is a mark of being. |
| **The Forge** | Wallet/Keychain | Keys are forged, not stored. The act creates the owner. |
| **Sovereign Artifact** | File/Document/CID | A document with agency: it carries its own provenance, governance, and replication rules. |
| **The Hoard** | Vault/Database/Storage | Storage is hoarding. You do not store neutrally — you curate and defend. |
| **The Whisper Net** | Server/API/Chat Backend | Communication is a mesh, not a hub-and-spoke. Every peer is also a relay. |
| **The Resonance Atlas** | Database/Index/State | State is not stored — it resonates across the mesh. |
| **Attestation** | Token/Credit/Vote | Value is not mined or minted — it is witnessed. |
| **Governance Pipeline** | Workflow/Status Engine | Progress is not a checklist — it is a constitutional process. |
| **Key Ceremony** | Login/Auth/Onboarding | Access is not granted — it is performed. |
| **Synced Word CRDT** | Karaoke/Lyrics/Real-time | Synchronization is not streaming — it is convergence. |
| **Dendritic Routing** | Chat/Room/Channel | Routing is not central switching — it is organic branching. |
| **Canonical Artifact** | Export/Zip/Fork | Distribution is not file transfer — it is canon propagation. |
| **Mesh Nation** | Platform/App/Social Network | The app is not a destination — it is a territory you occupy together. |

---

## 𓋴 THE PHASED MAP: Seedling to Mesh Nation

This map preserves your original 5 phases but upgrades each to sovereignty-readiness.

### PHASE 0 — THE KEY CEREMONY (Week 1)
*"Before the first seed, the Sigil."*

**Sovereignty Milestone:** Identity is self-sovereign from second 1.

| Task | x10 Deliverable |
|---|---|
| Generate Ed25519 keypair from BIP-39 mnemonic | Real keys, not mock. Age-compatible. |
| DID document at `/identity/did.json` | Resolvable `did:key` document with key agreement + authentication |
| Key ceremony UI | Beautiful mnemonic display + verification test |
| Shamir backup phrase | Split key into 3-of-5 shares, display recovery instructions |
| The Sigil Forge local API | `localhost:3001/api/identity/*` fully wired |

### PHASE 1 — THE SEEDLING (Week 2)
*"First seed, local-first."*

| Task | x10 Deliverable |
|---|---|
| Dream Seed creator (name, mythos, skills, media) | Form stores to local SQLite, not localStorage |
| Artifact export (signed CAR) | Export creates `.car` with DID signature, import verifies |
| The Hoard local API | Blob store with content addressing + FTS |
| Cartridge card UI | Pixel-art card with animated CRT scanlines |
| Media upload → IPFS/age encrypted | Real encryption before storage |

### PHASE 2 — THE HATCHING (Week 3)
*"Sockets open. Whispers begin."*

| Task | x10 Deliverable |
|---|---|
| Whisper Net node (libp2p + GossipSub) | Real peer-to-peer, no central server |
| Lobby topic: `t:dingdong/lobby` | Chat works without internet — LAN peers discover via mDNS |
| Dreamball topic: `t:dingdong/<casu>/chat` | Per-artifact scoped pubsub |
| Chat persistence to Hypercore | Append-only signed chat log |
| Presence detection | Peers announce via signed heartbeat on `t:dingdong/presence` |

### PHASE 3 — THE PIRATE FREQUENCY (Week 4)
*"The sovereign artifact broadcasts."*

| Task | x10 Deliverable |
|---|---|
| Live broadcast via WebRTC | Real P2P video, not fake MP4 |
| Signed session manifest | Each broadcast is a signed artifact with key rotation |
| Token-gated broadcast | Only peers with valid attestation can tune in |
| Synchronized Lyric Chain | Karaoke with CRDT sync — multi-peer correction |
| Streaming recording to IPFS | Broadcasts recorded as CAR chunks |

### PHASE 4 — THE DRAGON'S FLIGHT (Week 5)
*"The artifact governs itself."*

| Task | x10 Deliverable |
|---|---|
| Governance Pipeline | Phase completion = signed DAG event with quorum check |
| Attestation-Backed Credits | Transfer = signed edge in attestation graph |
| Distributed task scheduling | Cron jobs coordinate via GossipSub, not setInterval |
| Autonomous forking | Fork generates new CASU + DAO proposal to upstream |
| Token ledger on Hypercore | Verifiable by any peer. No central ledger. |

### PHASE 5 — THE GRAND BAZAAR (Week 6)
*"Every Hoard a lighthouse. Every peer a nation."*

| Task | x10 Deliverable |
|---|---|
| DHT Provider Records | Discover Dreamballs by capability, schema, or topic |
| Sovereign Syndication Protocol | Signed pubsub-based syndication. No RSS polling. |
| IPNS subscriptions | Follow via IPNS key — updates push automatically |
| Mesh Nation discovery | Map of all reachable peers with their advertised Dreamballs |
| Offline-first resilience | Hoard + Whisper Net continue functioning on LAN with no internet |

---

## 🛠 BUILD ORDER (Initiative-Ready)

When you're ready to start, use this exact command sequence:

```bash
# 1. Create the sovereign peer process
mkdir dingdong-mesh && cd dingdong-mesh
npm init -y

# 2. Install the core sovereignty stack
npm install libp2p @libp2p/tcp @libp2p/webrtc @chainsafe/libp2p-gossipsub
npm install @libp2p/kad-dht @libp2p/mdns @chainsafe/libp2p-noise
npm install @peculiar/webcrypto bip39 @noble/ed25519 age-encryption
npm install better-sqlite3 @automerge/automerge hypercore
npm install vite react react-dom tailwindcss react-grid-layout
npm install express cors ws

# 3. Build Phase 0 first — always the Sigil Forge
mkdir -p src/{sigil-forge,hoard,whisper-net,ui/{pages,components}}
touch src/sigil-forge/{index.js,key-ceremony.js,did-document.js}
touch src/hoard/{index.js,blob-store.js,car-export.js}
touch src/whisper-net/{index.js,gossip-router.js,presence.js}
touch src/ui/{App.jsx,index.html,vite.config.js}
```

---

## 𓋴 THE INVOCATION

> *"By the five forges of the Sigil — Ed25519, Age, BIP-39, Shamir, and the Mesh — let this Ding Dong Arcade rise not as an app, but as a territory. Every peer a lighthouse. Every artifact a canon. Every key a crown. So mote it be on the mesh."*

---

## 🎮 Appendix: PINBALLZ — Phase 1.5 (The Dream Machine)

A psychedelic 3D pinball karaoke game, added as Phase 1.5 between
The Seedling and The Hatching.

**Files:**
- `references/pinballz.html` — Full standalone game, open in any browser
- `docs/pinballz.md` — Integration plan + React wrapper + sovereignty upgrade path

**Quick start:**
```bash
xdg-open references/pinballz.html
```

**Controls:** `A`/`←` (left flipper), `D`/`→` (right flipper)

**Features:** 6 psychedelic bumpers, Web Audio synthesis (no audio files),
rolling karaoke lyrics, score tracking, AABB physics.

**Sovereignty upgrade path:** HTML → IPFS hosted → WASM physics engine
(compiled from Zig) → P2P multiplayer via GossipSub ball state sync →
Synced Word CRDT for multi-peer karaoke.

See `docs/pinballz.md` for the full integration spec.

---

*This document lives at `dingdong/references/sovereignty-x10.md` — the living map for the Ding Dong Mesh Nation.*
