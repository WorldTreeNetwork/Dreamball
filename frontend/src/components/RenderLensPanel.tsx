/**
 * 4D Gaussian Splatting Render Lens — Dreamball Composer Addon
 * 
 * Adds a render mode selector panel to the Dreamball detail/composer view.
 * Allows artists to toggle between 4D-GS generations and store
 * the render preset in the Dreamball manifest.
 * 
 * Based on @renderrides' evolution research:
 *   4D-GS      → 82 FPS   (baseline dynamic scenes)
 *   4D-Rotor   → 583 FPS  (RTX 4090, rotation-based)
 *   ST-4DGS    → temporal consistency
 *   Lumina-4DGS → 2026, dynamic illumination
 */

import React, { useState } from 'react';

// ─── Types ───────────────────────────────────────────────

export type RenderMode = '4D-GS' | '4D-Rotor' | 'ST-4DGS' | 'Lumina-4DGS';

export interface RenderPreset {
  mode: RenderMode;
  fpsTarget: number;          // 24 – 583
  temporalConsistency: boolean;
  dynamicLighting: boolean;
  resolution: '720p' | '1080p' | '2K' | '4K';
}

export const DEFAULT_PRESET: RenderPreset = {
  mode: '4D-GS',
  fpsTarget: 82,
  temporalConsistency: false,
  dynamicLighting: false,
  resolution: '1080p',
};

// Mode specs from @renderrides research
const MODE_SPECS: Record<RenderMode, {
  label: string;
  icon: string;
  maxFps: number;
  minFps: number;
  description: string;
  features: string[];
  year: string;
  requirements: string;
}> = {
  '4D-GS': {
    label: '4D Gaussian Splatting',
    icon: '🌀',
    maxFps: 82,
    minFps: 24,
    description: 'Baseline dynamic scene capture. Handles moving scenes, 82 FPS peak.',
    features: ['Dynamic scene capture', 'Per-frame Gaussian optimization'],
    year: '2023',
    requirements: 'RTX 3080+ / 12GB VRAM',
  },
  '4D-Rotor': {
    label: '4D Rotor GS',
    icon: '⚡',
    maxFps: 583,
    minFps: 60,
    description: 'Rotation-based splatting. 583 FPS on RTX 4090 — 7x faster than baseline.',
    features: ['Rotation parameterization', 'Ultra-fast inference', 'Real-time rendering'],
    year: '2024',
    requirements: 'RTX 4090 / 24GB VRAM recommended',
  },
  'ST-4DGS': {
    label: 'Spatial-Temporal 4DGS',
    icon: '🌊',
    maxFps: 240,
    minFps: 30,
    description: 'Adds temporal consistency constraints. No flickering between frames.',
    features: ['Temporal coherence', 'Flicker reduction', 'Consistent motion trails'],
    year: '2025',
    requirements: 'RTX 4080+ / 16GB VRAM',
  },
  'Lumina-4DGS': {
    label: 'Lumina 4DGS',
    icon: '💡',
    maxFps: 120,
    minFps: 24,
    description: '2026 state-of-the-art. Handles rapidly changing illumination in dynamic scenes.',
    features: ['Dynamic illumination', 'Relightable splats', 'Multi-view consistency'],
    year: '2026',
    requirements: 'RTX 4090 / 24GB VRAM',
  },
};

// ─── Component ────────────────────────────────────────────

interface RenderLensPanelProps {
  preset?: RenderPreset;
  onChange?: (preset: RenderPreset) => void;
}

export default function RenderLensPanel({ 
  preset: externalPreset, 
  onChange 
}: RenderLensPanelProps) {
  const [internalPreset, setInternalPreset] = useState<RenderPreset>(DEFAULT_PRESET);
  const preset = externalPreset ?? internalPreset;
  const spec = MODE_SPECS[preset.mode];
  const [expanded, setExpanded] = useState(false);

  function update(partial: Partial<RenderPreset>) {
    const next = { ...preset, ...partial };
    if (!onChange) setInternalPreset(next);
    else onChange(next);
  }

  return (
    <div style={styles.container}>
      {/* Header */}
      <div style={styles.header} onClick={() => setExpanded(!expanded)}>
        <span style={styles.headerTitle}>
          {spec.icon} Render Lens — {spec.label}
        </span>
        <span style={styles.headerBadge}>{spec.year}</span>
        <span style={{ marginLeft: 'auto', opacity: 0.6 }}>
          {expanded ? '▲' : '▼'}
        </span>
      </div>

      {expanded && (
        <div style={styles.body}>
          {/* Mode Selector — the 4 evolutionary stages */}
          <label style={styles.sectionLabel}>Generation</label>
          <div style={styles.modeGrid}>
            {(Object.keys(MODE_SPECS) as RenderMode[]).map(mode => {
              const s = MODE_SPECS[mode];
              const active = preset.mode === mode;
              return (
                <button
                  key={mode}
                  onClick={() => update({ mode })}
                  style={{
                    ...styles.modeBtn,
                    ...(active ? styles.modeBtnActive : {}),
                    borderColor: active ? '#00ff9d' : 'rgba(255,255,255,0.15)',
                  }}
                >
                  <span style={{ fontSize: 20 }}>{s.icon}</span>
                  <span style={{ fontSize: 10, fontWeight: 600 }}>
                    {s.label.split(' ').slice(0, 2).join(' ')}
                  </span>
                  <span style={{ fontSize: 9, opacity: 0.6 }}>{s.maxFps} FPS</span>
                </button>
              );
            })}
          </div>

          {/* Description */}
          <p style={styles.description}>
            {spec.description}
            <br />
            <span style={{ opacity: 0.5, fontSize: 10 }}>
              {spec.requirements}
            </span>
          </p>

          {/* FPS Target Slider */}
          <label style={styles.sectionLabel}>
            FPS Target <span style={{ color: '#00ff9d' }}>{preset.fpsTarget}</span>
          </label>
          <input
            type="range"
            min={spec.minFps}
            max={spec.maxFps}
            value={preset.fpsTarget}
            onChange={e => update({ fpsTarget: Number(e.target.value) })}
            style={styles.slider}
          />
          <div style={styles.sliderLabels}>
            <span>{spec.minFps}</span>
            <span>{spec.maxFps} FPS</span>
          </div>

          {/* Feature Toggles */}
          <label style={styles.sectionLabel}>Features</label>
          
          <ToggleRow
            label="Temporal Consistency (ST-4DGS)"
            enabled={preset.temporalConsistency}
            onChange={v => update({ temporalConsistency: v })}
            description="Eliminates flickering between splat frames"
          />

          <ToggleRow
            label="Dynamic Lighting (Lumina)"
            enabled={preset.dynamicLighting}
            onChange={v => update({ dynamicLighting: v })}
            description="Relightable splats under changing illumination"
          />

          {/* Resolution */}
          <label style={styles.sectionLabel}>Output Resolution</label>
          <div style={styles.resolutionRow}>
            {(['720p', '1080p', '2K', '4K'] as const).map(res => (
              <button
                key={res}
                onClick={() => update({ resolution: res })}
                style={{
                  ...styles.resBtn,
                  ...(preset.resolution === res ? styles.resBtnActive : {}),
                }}
              >
                {res}
              </button>
            ))}
          </div>

          {/* Preset JSON (for Dreamball manifest) */}
          <details style={styles.jsonDetails}>
            <summary style={styles.jsonSummary}>📋 Copy Render Preset</summary>
            <pre style={styles.jsonBlock}>
              {JSON.stringify(preset, null, 2)}
            </pre>
          </details>

          {/* Apply to Dreamball button */}
          <button
            onClick={() => {
              // Dispatch event for parent Dreamball Composer to consume
              window.dispatchEvent(new CustomEvent('dreamball:render-preset', {
                detail: preset,
              }));
            }}
            style={styles.applyBtn}
          >
            🔮 Apply to Dreamball Manifest
          </button>
        </div>
      )}

      {/* Active mode indicator bar */}
      <div style={{
        ...styles.activeBar,
        width: `${(preset.fpsTarget / spec.maxFps) * 100}%`,
        background: preset.mode === 'Lumina-4DGS' 
          ? 'linear-gradient(90deg, #00ff9d, #ff00ff)' 
          : '#00ff9d',
      }} />
    </div>
  );
}

// ─── Sub-components ─────────────────────────────────────

function ToggleRow({ 
  label, enabled, onChange, description 
}: { 
  label: string; enabled: boolean; onChange: (v: boolean) => void; description?: string 
}) {
  return (
    <div style={styles.toggleRow}>
      <div>
        <div style={styles.toggleLabel}>{label}</div>
        {description && (
          <div style={styles.toggleDesc}>{description}</div>
        )}
      </div>
      <button
        onClick={() => onChange(!enabled)}
        style={{
          ...styles.toggleSwitch,
          background: enabled ? '#00ff9d' : 'rgba(255,255,255,0.1)',
          justifyContent: enabled ? 'flex-end' : 'flex-start',
        }}
      >
        <div style={{
          ...styles.toggleDot,
          background: enabled ? '#0a0f0f' : '#555',
        }} />
      </button>
    </div>
  );
}

// ─── Styles ──────────────────────────────────────────────

const styles: Record<string, React.CSSProperties> = {
  container: {
    background: 'rgba(10, 15, 15, 0.95)',
    border: '1px solid rgba(0, 255, 157, 0.2)',
    borderRadius: 12,
    overflow: 'hidden',
    fontFamily: "'Courier New', monospace",
    color: '#c8d6e5',
    margin: '8px 0',
  },
  header: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    padding: '12px 16px',
    cursor: 'pointer',
    userSelect: 'none',
  },
  headerTitle: { fontSize: 13, fontWeight: 600 },
  headerBadge: {
    background: 'rgba(0, 255, 157, 0.15)',
    color: '#00ff9d',
    padding: '2px 8px',
    borderRadius: 20,
    fontSize: 9,
    fontWeight: 600,
  },
  body: { padding: '0 16px 16px' },
  sectionLabel: {
    display: 'block',
    fontSize: 10,
    fontWeight: 600,
    color: '#8899aa',
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginTop: 12,
    marginBottom: 6,
  },
  modeGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(4, 1fr)',
    gap: 6,
  },
  modeBtn: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: 4,
    padding: '10px 4px',
    background: 'rgba(255,255,255,0.03)',
    border: '1px solid rgba(255,255,255,0.15)',
    borderRadius: 8,
    color: '#c8d6e5',
    cursor: 'pointer',
    fontSize: 10,
    fontFamily: "'Courier New', monospace",
    transition: 'all 0.2s',
  },
  modeBtnActive: {
    background: 'rgba(0, 255, 157, 0.1)',
    boxShadow: '0 0 12px rgba(0, 255, 157, 0.2)',
  },
  description: {
    fontSize: 11,
    lineHeight: 1.5,
    color: '#8899aa',
    margin: '8px 0 4px',
  },
  slider: {
    width: '100%',
    height: 4,
    appearance: 'none',
    background: 'rgba(0, 255, 157, 0.2)',
    borderRadius: 2,
    outline: 'none',
    cursor: 'pointer',
  },
  sliderLabels: {
    display: 'flex',
    justifyContent: 'space-between',
    fontSize: 9,
    color: '#576574',
    marginTop: 2,
  },
  toggleRow: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: '6px 0',
    borderBottom: '1px solid rgba(255,255,255,0.03)',
  },
  toggleLabel: { fontSize: 11, color: '#c8d6e5' },
  toggleDesc: { fontSize: 9, color: '#576574', marginTop: 1 },
  toggleSwitch: {
    width: 36,
    height: 18,
    borderRadius: 20,
    border: 'none',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    padding: 2,
    transition: 'all 0.2s',
    flexShrink: 0,
  },
  toggleDot: {
    width: 14,
    height: 14,
    borderRadius: '50%',
    transition: 'all 0.2s',
  },
  resolutionRow: {
    display: 'flex',
    gap: 6,
  },
  resBtn: {
    flex: 1,
    padding: '6px 0',
    background: 'rgba(255,255,255,0.03)',
    border: '1px solid rgba(255,255,255,0.1)',
    borderRadius: 6,
    color: '#c8d6e5',
    fontSize: 10,
    fontFamily: "'Courier New', monospace",
    cursor: 'pointer',
    textAlign: 'center',
  },
  resBtnActive: {
    background: 'rgba(0, 255, 157, 0.15)',
    borderColor: '#00ff9d',
    color: '#00ff9d',
  },
  jsonDetails: { marginTop: 12 },
  jsonSummary: {
    fontSize: 10,
    color: '#576574',
    cursor: 'pointer',
    marginBottom: 4,
  },
  jsonBlock: {
    background: 'rgba(0,0,0,0.4)',
    padding: 8,
    borderRadius: 6,
    fontSize: 9,
    lineHeight: 1.5,
    overflow: 'auto',
    maxHeight: 120,
  },
  applyBtn: {
    width: '100%',
    marginTop: 12,
    padding: '10px 0',
    background: 'linear-gradient(135deg, rgba(0, 255, 157, 0.15), rgba(255, 0, 255, 0.1))',
    border: '1px solid rgba(0, 255, 157, 0.3)',
    borderRadius: 8,
    color: '#00ff9d',
    fontSize: 12,
    fontWeight: 600,
    fontFamily: "'Courier New', monospace",
    cursor: 'pointer',
    letterSpacing: 1,
    transition: 'all 0.2s',
  },
  activeBar: {
    height: 3,
    transition: 'width 0.3s ease',
  },
};

// ─── CSS-in-JS for pseudo-selectors ─────────────────────
const styleSheet = document.createElement('style');
styleSheet.textContent = `
  input[type="range"]::-webkit-slider-thumb {
    appearance: none;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: #00ff9d;
    cursor: pointer;
    box-shadow: 0 0 8px rgba(0, 255, 157, 0.4);
  }
  input[type="range"]::-moz-range-thumb {
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: #00ff9d;
    cursor: pointer;
    border: none;
  }
  details > summary { list-style: none; }
  details > summary::-webkit-details-marker { display: none; }
`;
document.head.appendChild(styleSheet);
