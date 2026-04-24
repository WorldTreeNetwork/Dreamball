// ─── room-pulse.frag.glsl ────────────────────────────────────────────────────
//
// Sprint-001 S5.5 — Room environment pulse shader (fragment stage).
//
// Palette:
//   PULSE_WARM   — warm amber pulse at high freshness.
//   DUST_HUE     — desaturated ochre at freshness floor (Vril ADR §7 "dusty").
//   AMBIENT_BASE — dark ambient tint when pulse is at minimum.
//
// At freshness < COBWEBS threshold (90d), colour lerps toward DUST_HUE.
// At freshness floor (< SLEEPING, 365d), luminance is ghost-level only.
//
// ────────────────────────────────────────────────────────────────────────────

precision highp float;

uniform float uFreshness;

varying float vPulse;
varying vec3  vNormal;
varying vec2  vUv;

const vec3 PULSE_WARM   = vec3(1.00, 0.76, 0.30);
const vec3 DUST_HUE     = vec3(0.55, 0.46, 0.32);
const vec3 AMBIENT_BASE = vec3(0.05, 0.08, 0.12);

// Freshness thresholds (mirrored from aqueduct.ts constants — renderer-side).
// INVARIANT: these must match freshness(DUSTY_MS / COBWEBS_MS / SLEEPING_MS)
// from src/memory-palace/aqueduct.ts. Drift is prevented by the R7 parity test
// (traversal.test.ts). TODO: promote to uniforms so the TS constants are the
// sole source (renderer imports DUSTY_MS/COBWEBS_MS already — L13 review).
const float DUSTY_NORM    = 0.368; // exp(-1) ≈ freshness at 30d with tau=30d
const float COBWEBS_NORM  = 0.05;  // ≈ exp(-3), freshness at 90d with tau=30d
const float SLEEPING_NORM = 0.001; // ≈ exp(-12.2), freshness at 365d with tau=30d

void main() {
  // Lerp base colour from warm pulse to dust based on freshness.
  // freshnessNorm = 1.0 → fully fresh (warm); 0.0 → fully stale (dust).
  float freshnessNorm = clamp(uFreshness, 0.0, 1.0);
  vec3 pulseColor = mix(DUST_HUE, PULSE_WARM, freshnessNorm);

  // Modulate luminance by pulse and freshness.
  // At sleeping threshold, ghost-luminance only (≤5% of peak).
  float maxLum = max(0.05, freshnessNorm);
  float lum    = AMBIENT_BASE.r + (maxLum - AMBIENT_BASE.r) * vPulse;

  // Simple diffuse for the room-mesh surface.
  float nDotL = max(dot(vNormal, normalize(vec3(1.0, 1.5, 1.0))), 0.0);
  vec3 color  = mix(AMBIENT_BASE, pulseColor * lum, 0.6 + 0.4 * nDotL);

  gl_FragColor = vec4(color, 1.0);
}
