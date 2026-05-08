# DING DONG ARCADE — Condensed R&D Phase Plan
# Copy-paste this entire block into Claude Code terminal.

"""
BUILD the Ding Dong Arcade — a pirate social OS / Dreamball platform.

## PHASES (R&D Sprinter)

### PHASE 0 — THE KEY CEREMONY
~/
. 1. Generate Ed25519 keypair from BIP-39 mnemonic
   2. DID document at /identity/did.json (did:key)
   3. Key ceremony UI: mnemonic display + verification test
   4. Shamir backup: split key 3-of-5
   5. Sigil Forge local API: localhost:3001/api/identity/*

### PHASE 1 — THE SEEDLING
. 1. Dream Seed creator form: name, mythos_text, agent_prompt, skills[], media_upload
   2. Store to local SQLite (not localStorage)
   3. CAR export: signed .car with DID signature, import verifies
   4. The Hoard API: localhost:3001/api/hoard/* (blob store + FTS)
   5. Cartridge card UI: pixel-art, CRT scanlines
   6. Media upload → age-encrypted blob

### PHASE 1.5 — THE DREAM MACHINE (PINBALLZ ARCADE)
. 1. Place references/pinballz.html in frontend/static/games/
   2. Create Pinballz.jsx (iframe wrapper + back button)
   3. Route /arcade/pinballz in React Router
   4. Menu entry in ArcadeLobby sidebar
   5. (Sovereignty) WASM physics engine compiled from Zig → replaces inline

### PHASE 1.75 — THE 4DGS RENDER LENS (NEW)
. 1. Add 4DGS Lens to Dreamball Composer component tree
   2. RenderMode selector: 4D-GS → 4D-Rotor → ST-4DGS → Lumina-4DGS
   3. FPS target slider (82 → 583)
   4. Temporal consistency toggle (ST-4DGS on/off)
   5. Dynamic lighting switch (Lumina-4DGS feature)
   6. Gaussian Splat Lens demo page at /demo/splat-4d
   7. Store render preset in Dreamball manifest JSON

### PHASE 2 — THE HATCHING
. 1. libp2p node + GossipSub (no central server)
   2. Lobby topic: t:dingdong/lobby (LAN mDNS discovery)
   3. Per-Dreamball topic: t:dingdong/<casu>/chat
   4. Chat persisted to Hypercore (append-only signed log)
   5. Presence: signed heartbeat on t:dingdong/presence

### PHASE 3 — THE PIRATE FREQUENCY
. 1. WebRTC P2P video broadcast (not fake MP4)
   2. Signed session manifest per broadcast
   3. Token-gated broadcast (valid attestations only)
   4. Synced Lyric Chain (CRDT multi-peer karaoke)
   5. Streaming recording → IPFS CAR chunks

### PHASE 4 — THE DRAGON'S FLIGHT
. 1. Governance Pipeline: phase completion = signed DAG event + quorum
   2. Attestation-Backed Credits: transfer = signed edge in graph
   3. Distributed cron: tasks scheduled via GossipSub
   4. Autonomous forking: new CASU + DAO proposal
   5. Token ledger on Hypercore (verifiable by any peer)

### PHASE 5 — THE GRAND BAZAAR
. 1. DHT Provider Records: discover Dreamballs by capability/schema
   2. Sovereign Syndication Protocol (signed pubsub, not RSS polling)
   3. IPNS subscriptions: follow via IPNS key, auto-push updates
   4. Mesh Nation map: reachable peers + advertised Dreamballs
   5. Offline-first: Hoard + Whisper Net on LAN with no internet

## DIRECTORY STRUCTURE
dingdong/
├── backend/
│   ├── index.js              (Express + libp2p + SQLite)
│   ├── routes/
│   │   ├── dreamballs.js     (CRUD, RSS, export)
│   │   ├── auth.js           (DID ceremony)
│   │   └── identity.js       (Sigil Forge API)
│   ├── data/                 (mock IPFS blobs)
│   └── lib/
│       ├── sigil-forge/      (Ed25519, BIP-39, Shamir)
│       ├── hoard/            (SQLite + FTS + CAR export)
│       └── whisper-net/      (libp2p + GossipSub)
├── frontend/
│   ├── src/
│   │   ├── pages/
│   │   │   ├── Vault.jsx
│   │   │   ├── DreamSeedCreator.jsx
│   │   │   ├── AssembleDreamball.jsx
│   │   │   ├── DreamballDetail.jsx
│   │   │   ├── ArcadeLobby.jsx
│   │   │   └── Pinballz.jsx
│   │   ├── components/
│   │   │   ├── Sidebar.jsx
│   │   │   ├── LiveBroadcastModal.jsx
│   │   │   ├── KaraokeModal.jsx
│   │   │   └── RenderLensPanel.jsx   (NEW — 4DGS controls)
│   │   └── App.jsx
│   ├── games/
│   │   └── pinballz.html
│   └── package.json
└── references/
    ├── pinballz.html
    └── sovereignty-x10-upgrade.md
"""

# Now run:
# npm init -y && npm install libp2p @libp2p/tcp @libp2p/webrtc @chainsafe/libp2p-gossipsub @libp2p/kad-dht @libp2p/mdns @chainsafe/libp2p-noise @peculiar/webcrypto bip39 @noble/ed25519 age-encryption better-sqlite3 @automerge/automerge hypercore vite react react-dom tailwindcss react-grid-layout express cors ws
# mkdir -p dingdong/{backend/{routes,data,lib/{sigil-forge,hoard,whisper-net}},frontend/{src/{pages,components,games},public}}

echo "PHASE PLAN LOADED — Ready to execute Phase 0: The Key Ceremony"
