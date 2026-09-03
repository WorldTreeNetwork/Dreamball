# 4D Gaussian Splatting Render Lens — Dreamball Composer Addon

**Phase:** 1.75 — The 4DGS Render Lens
**Source:** @renderrides research reel (Instagram, May 2026)
**Evolution:** 4D-GS → 4D-Rotor → ST-4DGS → Lumina-4DGS

---

## What This Is

A React component (`RenderLensPanel.tsx`) that adds a **render mode selector**
to the Dreamball Composer view. Artists choose their splatting generation
like a camera lens — the preset gets stored in the Dreamball manifest JSON.

## The Four Render Generations

| Icon | Mode | Max FPS | When | Key Feature |
|---|---|---|---|---|
| 🌀 | 4D-GS (baseline) | 82 | 2023 | Dynamic scene capture |
| ⚡ | 4D-Rotor | 583 | 2024 | Rotation param — 7x faster |
| 🌊 | ST-4DGS | 240 | 2025 | Temporal consistency, no flicker |
| 💡 | Lumina-4DGS | 120 | 2026 | Dynamic illumination, relightable |

## Component API

```tsx
import RenderLensPanel from './components/RenderLensPanel';

// Controlled (external state)
const [preset, setPreset] = useState<RenderPreset>(DEFAULT_PRESET);
<RenderLensPanel preset={preset} onChange={setPreset} />

// Uncontrolled (internal state)
<RenderLensPanel />
```

## Manifest Integration

The component dispatches a `CustomEvent` when "Apply to Dreamball Manifest" is
clicked:

```tsx
window.addEventListener('dreamball:render-preset', (e: CustomEvent) => {
  const preset: RenderPreset = e.detail;
  dreamball.render = { ...dreamball.render, ...preset };
  saveDreamball(dreamball);
});
```

The preset is stored in the Dreamball JSON under a `render` key:

```json
{
  "identity": "bafy...",
  "name": "My Dreamball",
  "render": {
    "mode": "Lumina-4DGS",
    "fpsTarget": 60,
    "temporalConsistency": true,
    "dynamicLighting": true,
    "resolution": "1080p"
  }
}
```

## Where to Add It

### In the Dreamball Detail page (`DreamballDetail.jsx`):

```jsx
import RenderLensPanel from '../components/RenderLensPanel';

// Inside the page JSX, next to the Phase checklist:
<div className="composer-section">
  <h3>🌀 Render Lens</h3>
  <RenderLensPanel 
    preset={dreamball.render}
    onChange={(preset) => updateDreamball({ render: preset })}
  />
</div>
```

### In the Gaussian Splat demo page (`/demo/splat-4d`):

```jsx
import RenderLensPanel from '../components/RenderLensPanel';
import SplatRenderer from '../components/SplatRenderer';

export default function Splat4DDemo() {
  const [preset, setPreset] = useState(DEFAULT_PRESET);
  
  return (
    <SplitView>
      <SplatRenderer mode={preset.mode} fpsTarget={preset.fpsTarget} />
      <RenderLensPanel preset={preset} onChange={setPreset} />
    </SplitView>
  );
}
```

## Files Created

| File | Purpose |
|---|---|
| `frontend/src/components/RenderLensPanel.tsx` | The React component (14KB, standalone) |
| `docs/4dgs-render-lens.md` | This integration doc |
| `references/phase-plan-claude-terminal.md` | Condensed Claude Code terminal plan |

## Sovereignty Upgrade Path

| Step | What | Phase |
|---|---|---|
| 1 | React component with inline CSS-in-JS | Phase 1.75 |
| 2 | Preset stored in SQLite via Hoard API | Phase 2 |
| 3 | Render presets shared via GossipSub topic | Phase 3 |
| 4 | WASM 4DGS decoder from Zig core | Phase 4 |
| 5 | Distributed render farm via Peer-to-Peer DAG | Phase 5 |

---

> *"From 82 FPS to 583. From static light to Lumina. The Dreamball
> sees in 4D."* — @renderrides
