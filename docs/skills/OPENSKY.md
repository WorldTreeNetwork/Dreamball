# 🪷 OPENSKY — Spatial Web Operating System (Super Skill Reference)

> A shared URL becomes a world. A browser becomes a door.

---

## What It Is

**OpenSky** is a spatial web operating system. You send someone a link and they step into a 3D room with you — your avatar a floating billboard that pulses when you speak, your media portals hovering in space, your voice carried by proximity. It's MySpace rebuilt for spatial computing. Fork it. Vibe it. Own it.

---

## The Stack (Fork & Integrate)

| Layer | Fork From | Why It's Chosen |
|-------|-----------|-----------------|
| Rendering + XR | **XR Blocks** (Google) — github.com/google/xrblocks | AI-native spatial prototyping; 95.5% one-shot accuracy with Gemini/Claude |
| 3D Engine | **A-Frame** + Three.js — aframe.io | HTML-like scene building; massive ecosystem |
| Multiplayer Sync | **Networked-Aframe** — github.com/networked-aframe/networked-aframe | WebRTC + WebSocket; only syncs changed data; built-in voice |
| State Consistency | **Yjs** CRDTs + y-webrtc | Local-first; no server authority; offline-capable |
| Voice + Spatial Audio | **dTelecom spatial audio** + Web Audio PannerNode | Proximity attenuation; Solana-based node discovery |
| Face Tracking | **MediaPipe Face Mesh** | 468 landmarks → 3D mesh; float16 compressed = ~85 KB/s |
| Decentralized Storage | **Helia** (IPFS in browser) + Pinata | Scene states & media stored peer-to-peer |
| Transactions | **Coinbase AgentKit** + Solana | Media marketplace; tip jars; asset trading in-room |
| AI Code Generation | **Claude Code** + XR Blocks bridge | Natural language → deployed room in seconds |
| Signaling | Custom Node.js + WebSocket | Stateless; minimal; no user data stored |

---

## Commands (Vibe Coding Interface)

```
/opensky new "meditation garden with floating screens"
    → Room spawns at https://opensky.world/room-uuid
    → Everyone who enters sees the garden

/opensky portal --url "youtube.com/watch?v=..." --at "0,1.5,-2"
    → Video wall appears in space, everyone watches together

/opensky vibe --mood "cyberpunk marketplace"
    → Lighting, fog, post-processing shift in real-time for all

/opensky speak
    → Your avatar ring pulses; voice fades with distance

/opensky save
    → Entire room state → IPFS; returns permanent hash

/opensky fork --repo opensky-stack
    → Entire platform cloned, ready for your changes
```

---

## Process (Phase Map)

### Phase 1 — The Skeleton (Week 1-2)
Fork XR Blocks → opensky-xr. Fork Networked-Aframe → opensky-naf. Deploy signaling server. Get one sphere synced between two browsers.

### Phase 2 — The Face (Week 3-4)
Replace sphere with camera-facing plane + profile picture. Wire MediaPipe face mesh over WebRTC data channel. Add audio-reactive ring.

### Phase 3 — The Garden (Week 5-6)
Build media portals (iframes rendered to Three.js textures). Add spatial GUI (drag handles, context menus). Implement CRDT sync for object positions.

### Phase 4 — The City (Week 7-8)
Decentralized storage via IPFS. Spatial audio with distance attenuation. Transaction layer for buying/selling media assets. Room templates.

### Phase 5 — The Sky (Week 9+)
Mobile optimization. VR headset support. AI agent inhabitants. Federation (rooms linking to rooms). Self-hosting guide. Community governance.

### Phase 6 — The Storm (Community Upgrade)
- **Livestorm integration**: WebRTC-native spatial chat with dTelecom + LiveKit alternative paths
- **A-Frame Supercraft**: Decentralized world-building UI via A-Frame Inspector fork
- **Helia Bitswap acceleration**: Browser-native IPFS block exchange for instant world loading
- **2025+ WebCrypto Ed25519**: Already shipped in Chrome 137 — use for signing room states without external libs

### Phase 7 — The Network (Agent Integration)
- **Solana Agent Kit** (sendaifun/solana-agent-kit): 60+ Solana actions for in-room economy
- **Coinbase Agentic Wallets** (Feb 2026 launch): AI agent wallets for autonomous spatial commerce
- **Claude Code → OpenSky Bridge**: Natural language room authoring via MCP protocol

### Phase 8 — The Continuum (Spatial Fabric)
- **Yjs → Spatial CRDTs**: Extend text/array CRDTs to 3D transforms, physics state, zone permissions
- **LiveKit spatial audio**: Production-grade alternative to dTelecom for larger rooms
- **A-Frame v2.0+ community**: Memory management, tick/tock execution control, Bundle for AR
- **IPFS Browser Standards 2026**: Service Worker IPFS gateways, Curve448 in Firefox

---

## Dreamball Integration Points

| OpenSky Layer | Dreamball Equivalent | Integration |
|---------------|---------------------|-------------|
| Networked-Aframe | Whisper Net (LoRa mesh) | WebRTC bridges mesh to browser |
| Yjs CRDTs | Dingdong CBOR envelopes | Yjs maps → dCBOR for persistence |
| Helia IPFS | Permanence layer | Scene states stored as Dreamball artifacts |
| MediaPipe Face Mesh | Avatar Lens | Face mesh → Dreamball identity signature |
| XR Blocks + Gemini | Render Lens (4DGS) | AI-generated spatial scenes via Dreamball manifest |
| AgentKit | Token-gated rooms | Room access via Dreamball token balance |
| dTelecom spatial | Signal Forge | Proximity voice + mesh whisper integration |

---

## Links

| Resource | URL |
|----------|-----|
| XR Blocks | github.com/google/xrblocks |
| A-Frame | aframe.io / github.com/aframevr/aframe |
| Networked-Aframe | github.com/networked-aframe/networked-aframe |
| Yjs | github.com/yjs/yjs |
| Helia | github.com/ipfs/helia |
| MediaPipe | github.com/google-ai-edge/mediapipe |
| dTelecom | github.com/dTelecom/spatial-audio |
| Coinbase AgentKit | github.com/coinbase/agentkit |
| Solana Agent Kit | github.com/sendaifun/solana-agent-kit |
| LiveKit spatial audio | livekit.com |
| IPFS Browser Standards 2026 | discuss.ipfs.tech/t/19917 |

---

*Poetry of the Stack*

> A-Frame is the earth — solid, dependable, HTML-accessible.
> XR Blocks is the wind — AI breathes scenes into existence.
> Networked-Aframe is the fire — real-time sync, data burning between peers.
> Yjs CRDTs are the water — state flows, converges, never conflicts.
> IPFS is the seed — your world survives, decentralized, permanent.
