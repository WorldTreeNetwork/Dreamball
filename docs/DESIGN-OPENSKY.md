# DESIGN-OPENSKY — Spatial Web OS + Community Research Audit

> Design document covering OpenSky stack choices, community upgrades, and Dreamball integration.
> Research conducted May 2026.

---

## 1. Community Upgrades & Latest Versions

### XR Blocks (Google) — github.com/google/xrblocks
- **Status**: Active, Google-maintained, 2025-2026 expansion
- **Key upgrades**:
  - Vibe Coding XR workflow: Gemini Canvas → XR Blocks → WebXR apps in seconds
  - XR Realism: depth-aware physics, geometry-aware occlusion, lighting estimation
  - XR Interaction: hand tracking, gesture recognition via Android XR
  - XR Blocks Gem: Android XR headset-native scene building (Galaxy XR, Project Aura)
  - arXiv paper 2603.24591: "Vibe Coding XR: Accelerating AI+XR Prototyping"
  - 95.5% one-shot accuracy with Gemini/Claude LLMs
  - Simulated Reality desktop testing + one-click deploy to headset
- **Risk**: Google-controlled; may shift priorities. Fork early.

### A-Frame (Mozilla/Supermedium community) — aframe.io / github.com/aframevr/aframe
- **Status**: v1.6+ stable, active community, thousands of components
- **Key upgrades**:
  - Memory management improvements + tick/tock execution control
  - Bundle for AR devices
  - A-Frame Inspector (browser-based 3D editor, forked for Supercraft)
  - Entity-Component architecture — composable, extensible
  - Wide device support: Vive, Rift, Quest, desktop, mobile
  - Thousands of community components on npm
- **Fork path**: `opensky-aframe` — add Supercraft world-building, spatial portals, CRDT transform sync

### Networked-Aframe — github.com/networked-aframe/networked-aframe
- **Status**: Maintained, active fork ecosystem
- **Key upgrades**:
  - WebRTC + WebSocket dual transport
  - Voice chat / audio streaming baked in
  - Only syncs changed data (delta optimization)
  - Server entity ownership model
  - NAF adapters for native WebRTC channels
  - Easy adapter swap: EasyRTC → uWS → custom signaling
- **Fork path**: `opensky-naf` — add dTelecom spatial audio, Solana node discovery, CRDT state sync instead of WebSocket authority

### Yjs CRDTs — github.com/yjs/yjs
- **Status**: v13+, fastest CRDT implementation, best-of-js ranked
- **Key upgrades**:
  - Network-agnostic (WebSocket, WebRTC, P2P)
  - Rich text bindings (Quill, ProseMirror, Monaco, CodeMirror, TipTap)
  - Yjs 2026 focus: spatial CRDTs for 3D transforms, zone permissions
  - Large community: ~500+ npm dependents
  - OT vs CRDT comparison (2026): Yjs wins for P2P, offline-first, unlimited users
  - y-webrtc provider: fully P2P, no server needed for state sync
- **Fork path**: `opensky-crdt` — Spatial CRDT types (Transform3D, Zone, RoomState), MediaPortal CRDTs

### Helia (IPFS in browser) — github.com/ipfs/helia
- **Status**: Active — modern JS IPFS implementation, Protocol Labs
- **Key upgrades**:
  - Browser-native IPFS: no node needed
  - Helia Bitswap WG meetings (2025-07, 2025-08): Bitswap acceleration
  - IPNS reprovide fixes
  - IPFS Browser Standards 2026 initiative:
    - Ed25519 in WebCrypto API — shipped Chrome 137 (May 2025), 79% browser coverage
    - Service Worker IPFS gateway — fixing Chrome bugs to enable SW IPFS gateways
    - Curve448 — high confidence for Firefox, mid for Safari, low for Chrome
    - ipfs-chromium + ipfs-electron forks with native IPFS support (Little Bear Labs + Protocol Labs)
  - Pinata integration for pinning service
- **Fork path**: `opensky-ipfs` — room state archives, scene asset distribution, identity proofs

### MediaPipe Face Mesh — github.com/google-ai-edge/mediapipe
- **Status**: v2.6+, Face Landmarker API (replaces legacy Face Mesh)
- **Key upgrades**:
  - Face Landmarker: 468 landmarks + blendshapes + face transform
  - 3 models: Face Detector (135K params), Face Landmark (603K params) — ~1MB total
  - Sub-millisecond processing on-device
  - Browser + Node.js + WASM support
  - Web demo shortcomings noted (issue #6214): limited avatar rendering examples
  - Float16 compressed face mesh = ~85 KB/s over WebRTC data channel
  - Banuba comparison (2026): MediaPipe strongest open-source option, Banuba better for commercial AR filters
- **Fork path**: `opensky-face` — avatar billboard with MediaPipe-driven expression, audio-reactive ring pulse

### dTelecom Spatial Audio — github.com/dTelecom/spatial-audio
- **Status**: Active, Solana-based decentralized real-time comms
- **Key upgrades**:
  - 2D spatial world demo: join, navigate, hear others by position
  - WebRTC + Web Audio PannerNode for proximity
  - Solana node discovery (decentralized peer discovery)
  - dTelecom seed round: real-time infrastructure for humans + AI agents
  - Speech-to-Text, TTS baked in
- **Alternative**: LiveKit spatial audio tutorial (WebRTC + React + WebAudio PannerNode) — production-grade, great TS API
- **Fork path**: `opensky-audio` — dual provider (dTelecom P2P / LiveKit hosted), proximity zones, whisper mode

### Coinbase AgentKit + Solana — coinbase.com/developer-platform/products/agentkit
- **Status**: Active, Feb 2026 Agentic Wallets launch
- **Key upgrades**:
  - Agentic Wallets (Feb 11 2026): wallets designed specifically for AI agents
  - Multi-network: EVM + Solana
  - Model-agnostic: LangChain, any LLM
  - Solana Agent Kit (sendaifun/solana-agent-kit): 60+ Solana actions
  - Agent-to-agent transactions in-room
  - Token-gated room access, tip jars, media asset marketplace
  - AI Tinkerers community with 220+ cities building on AgentKit
- **Fork path**: `opensky-economy` — token-gated rooms, AI agent wallets, spatial marketplace

---

## 2. Dreamball Integration Map

### Layer-by-layer integration

| Layer | OpenSky | Dreamball | Bridge |
|-------|---------|-----------|--------|
| **Identity** | Ed25519 WebCrypto (Chrome 137) | ML-DSA-87 + Ed25511 in dCBOR | Sign room ownership with Dingdong identity |
| **State** | Yjs CRDTs + y-webrtc | Dingdong dCBOR envelopes + CRDT | Yjs Map → dCBOR serialization → IPFS persistence |
| **Worlds** | XR Blocks + A-Frame scenes | Render Lens (4DGS) → Dreamball manifest | AI-generated scenes become Dreamball deployable artifacts |
| **Sync** | Networked-Aframe WebRTC | Whisper Net (LoRa mesh) | WebRTC bridges browser ↔ mesh for hybrid connectivity |
| **Voice** | dTelecom / LiveKit spatial | Signal Forge | Proximity voice equals mesh whisper; spatial zones = forge levels |
| **Faces** | MediaPipe Face Mesh | Avatar Lens | Face mesh signature → identity verification |
| **Economy** | AgentKit + Solana | 100 token mock → real token | Token-gated rooms, media marketplace in Render Lens |
| **Storage** | Helia IPFS / Pinata | Permanence layer + IPNS | Room state archives as permanently retrievable artifacts |
| **AI** | Claude Code + Gemini + XR Blocks | Multi-agent parallel research (Phd Parallel Pattern) | Rooms generate via natural language → XR Blocks → Dreamball manifest |

### Sovereignty upgrade mapping

| Sovereignty Principle | OpenSky Implementation |
|-----------------------|----------------------|
| Local-first | Yjs CRDTs: no server authority needed |
| P2P-first | y-webrtc + dTelecom Solana: fully P2P state + voice |
| Decentralized identity | Ed25519 WebCrypto + Dingdong ML-DSA-87 |
| Permanent state | Helia IPFS: room state survives host disconnect |
| Open protocol | CC0 license, forkable stack, no API keys required |
| No vendor lock | Every layer has an open-source fork alternative |

---

## 3. Fission Points (What Makes OpenSky Novel)

1. **CRDT-driven spatial state** — transforms, physics, zone permissions as Yjs CRDTs. No authoritative server.
2. **AI-native room generation** — XR Blocks + Gemini/Claude → "a meditation garden with floating screens" → instant room
3. **Avatar-as-billboard** — MediaPipe face mesh + audio-reactive ring. Not a 3D model — a living self-portrait.
4. **Proximity as protocol** — voice fades with distance, media portals have spatial influence radius, rooms have audible zones
5. **Save = mint** — `/opensky save` creates permanent IPFS artifact. Rooms are NFTs of presence.
6. **Fork = deploy** — `/opensky fork --repo opensky-stack` clones the entire platform. Every room is a potential fork point.
7. **Spatial Web OS** — not an app. A browser becomes the operating system for shared presence.

---

## 4. Community Ecosystem Summary

| Component | Stars | Forks | Activity | 2025/2026 Signal |
|-----------|-------|-------|----------|-------------------|
| XR Blocks | ~2.5k | ~300 | High (Google) | arXiv paper, Android XR launch, Gemini integration |
| A-Frame | ~17k | ~4k | Moderate | Stable, mature, component ecosystem |
| Networked-Aframe | ~1.7k | ~600 | Active | Fork-friendly, adapter architecture |
| Yjs | ~18k | ~800 | Very High | Best-of-js, spatial CRDTs emerging |
| Helia | ~1.5k | ~150 | Active | Browser Standards 2026 initiative |
| MediaPipe | ~28k | ~9k | Very High (Google) | Face Landmarker v2, WASM, on-device |
| dTelecom | ~200 | ~30 | Growing | Seed round, Solana-based |
| AgentKit | ~8k | ~2k | Very High (Coinbase) | Agentic Wallets Feb 2026 |

---

*Design document for Dreamball project — May 2026*
