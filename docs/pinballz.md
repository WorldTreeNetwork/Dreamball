# PINBALLZ — Psychedelic Pinball Karaoke for the Dreamball Arcade

A fully self-contained 3D pinball game with interactive physics, scoring,
sound synthesis, and rolling karaoke lyrics — all in a single HTML file.
No build step, no dependencies to install — just open and play.

---

## 🎮 How to Use

### Standalone (Quick Play)
Open `pinballz.html` directly in any modern browser:

```bash
# From anywhere:
xdg-open pinballz.html
# Or drag into Chrome/Firefox/Safari
```

### Embedded in Dreamball Arcade
Add a menu option linking to the game. The HTML is fully encapsulated
— no conflicts with React, Express, or any other framework.

### Controls
| Input | Action |
|---|---|
| **Left paddle:** `A` / `←` / Left button | Flip left flipper |
| **Right paddle:** `D` / `→` / Right button | Flip right flipper |
| **Touch:** Tap buttons on screen | Mobile-friendly |

---

## 🔧 File Structure

```
dingdong/
├── frontend/
│   ├── src/
│   │   ├── pages/
│   │   │   ├── Vault.jsx
│   │   │   ├── DreamSeedCreator.jsx
│   │   │   ├── AssembleDreamball.jsx
│   │   │   ├── DreamballDetail.jsx
│   │   │   ├── ArcadeLobby.jsx
│   │   │   └── Pinballz.jsx       <-- NEW: React wrapper for pinballz
│   │   ├── games/
│   │   │   └── pinballz.html       <-- The standalone game file
│   │   └── App.jsx
│   └── package.json
└── references/
    └── pinballz.html               <-- Also available standalone
```

---

## 🌀 Game Features

### Visuals
- **Three.js 3D renderer** with neon-lit pinball playfield
- **Psychedelic aesthetic** — starfield background, pulsing color lights, emissive bumpers
- **Animated ball aura** — torus rings spinning around the dream ball
- **CSS2D karaoke labels** — floating text above bumpers

### Physics
- Wall bounces with velocity reflection and damping
- Bumper collisions with normal-based velocity deflection + extra kick
- Paddle AABB collision — launches ball upward with lateral spin
- Boundary detection with auto-reset on bottom fall

### Audio
- **Web Audio API synthesis** — no audio files needed
- Bump = triangle wave, Paddle = sawtooth, Wall = square, Score = sine sweep
- Audio context initializes on first button press (browser policy compliant)

### Scoring
- Bumper hit: +15 points (with visual flash)
- Paddle hit: +5 points
- Wall/ceiling bounce: +8 points

### Karaoke
- 7 rolling phrases cycling every 3.5 seconds
- "DREAM • BALL • Z", "PSYCHEDELIC GROOVE", "TRIPPY PINBALL", etc.
- Gradient text with pulsing animation
- Bonus phrase change on bumper hit (30% chance)

---

## 🛠 Building the React Wrapper

To embed in the Dreamball Arcade frontend:

### `Pinballz.jsx`

```jsx
import { useEffect, useRef } from 'react';

export default function Pinballz() {
  const iframeRef = useRef(null);

  return (
    <div className="pinballz-container" style={{
      width: '100vw', height: '100vh', position: 'relative',
      background: '#000', overflow: 'hidden'
    }}>
      <div className="pinballz-back-button" style={{
        position: 'absolute', top: 16, left: 16, zIndex: 1000
      }}>
        <button onClick={() => window.history.back()}
          style={{
            background: 'rgba(20,0,40,0.8)', border: '2px solid #ff00ff',
            color: '#ffe600', padding: '10px 24px', borderRadius: 40,
            fontFamily: 'Courier New', fontSize: '1.2rem', cursor: 'pointer'
          }}>
          ← BACK TO ARCADE
        </button>
      </div>
      <iframe
        ref={iframeRef}
        src="/games/pinballz.html"
        style={{
          width: '100%', height: '100%', border: 'none'
        }}
        title="PINBALLZ"
      />
    </div>
  );
}
```

### Route (in App.jsx or Router)

```jsx
<Route path="/arcade/pinballz" element={<Pinballz />} />
```

---

## 𓋴 PINBALLZ IN THE SOVEREIGNTY PHASES

### Quick-add: Phase 1.5 — The Dream Machine

The pinballz game fits naturally between Phase 1 (The Seedling) and Phase 2 (The Hatching).
Call it **Phase 1.5 — The Dream Machine**.

| Phase | Name | Deliverable |
|---|---|---|
| 1 | The Seedling | Local-first SQLite, CAR export |
| **1.5** | **The Dream Machine** | **PINBALLZ arcade cabinet in the Hoard** |
| 2 | The Hatching | libp2p mesh chat |

### Phase 1.5 Tasks

1. Copy `pinballz.html` to `frontend/static/games/pinballz.html`
2. Create `Pinballz.jsx` component with iframe wrapper
3. Add route `/arcade/pinballz` to the React router
4. Add menu entry in ArcadeLobby sidebar:

```jsx
<button onClick={() => navigate('/arcade/pinballz')}>
  🌀 PINBALLZ
</button>
```

5. (Sovereignty upgrade) Replace the static HTML ball physics with
   a WASM physics engine compiled from Zig — integrates the Dreamball
   pipeline into the game loop.

### Phase 1.5 Sovereignty Upgrade Path

| Current | Sovereignty x10 | When |
|---|---|---|
| Static HTML file | Hosted on IPFS via the Hoard | Phase 1 complete |
| Inline Three.js | Loaded from local cache, not CDN | Phase 2 |
| Score in DOM | Score stored in SQLite + signed attestations | Phase 3 |
| Single-player | P2P multiplayer via GossipSub (ball state sync) | Phase 4 |
| Karaoke from array | Karaoke from Synced Word CRDT (multi-peer lyrics) | Phase 4 |

---

## 📜 The Pinballz Grimoire

> *"By the neon glow of the Dream Machine — let every bumper be a note,
> every flipper a beat, every ball a star. The arcade cabinet sings,
> and the mesh dances."*

— PINBALLZ, Phase 1.5 of the Ding Dong Arcade
