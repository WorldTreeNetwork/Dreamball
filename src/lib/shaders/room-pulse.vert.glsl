// ─── room-pulse.vert.glsl ────────────────────────────────────────────────────
//
// Sprint-001 S5.5 — Room environment pulse shader (vertex stage).
//
// Purpose: ambient pulse on the room mesh surface indicating activity level.
//   • Pulse period is inversely proportional to capacitance — high-capacitance
//     rooms pulse faster (more potential for flow).
//   • Freshness tints colour toward dust at the floor threshold (Vril ADR §7).
//
// Uniforms:
//   uTime         — animation clock (seconds).
//   uCapacitance  — from store aqueduct row (range [0,1]).
//   uFreshness    — computed by freshness() in aqueduct.ts; range [0,1].
//
// R7 parity: uFreshness is supplied by the TypeScript wrapper, which imports
// freshness() from src/memory-palace/aqueduct.ts — NOT a copy of the formula.
//
// ────────────────────────────────────────────────────────────────────────────

uniform float uTime;
uniform float uCapacitance;
uniform float uFreshness;

varying float vPulse;
varying vec3  vNormal;
varying vec2  vUv;

void main() {
  // Pulse period: base period 4s, shortened by capacitance (range 0.5–4s).
  // period = 4 / (1 + 3 * capacitance)
  float period = 4.0 / (1.0 + 3.0 * uCapacitance);
  float phase  = uTime / period;

  // Smooth sinusoidal pulse in [0, 1].
  vPulse = 0.5 + 0.5 * sin(phase * 6.28318);

  vNormal = normalize(normalMatrix * normal);
  vUv     = uv;

  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
