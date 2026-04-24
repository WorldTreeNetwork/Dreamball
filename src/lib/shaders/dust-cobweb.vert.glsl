// ─── dust-cobweb.vert.glsl ───────────────────────────────────────────────────
//
// Sprint-001 S5.5 — Dust-cobweb overlay shader (vertex stage).
//
// Purpose: cobweb texture overlays the aqueduct path proportional to decay
// depth when freshness < COBWEBS threshold (90d). At freshness floor (<365d)
// particles drift toward the ambient sink per Vril ADR §9
// "return-to-zero-point is visual, not destructive".
//
// Uniforms:
//   uTime       — animation clock (seconds).
//   uFreshness  — [0,1]; 1 = just traversed, 0 = ancient.
//                 Supplied by wrapper importing freshness() from aqueduct.ts.
//
// Behaviour ranges:
//   freshness > COBWEBS_NORM  — no cobweb; shader is transparent.
//   SLEEPING_NORM < f ≤ COBWEBS_NORM — cobweb overlay with opacity ∝ decay depth.
//   f ≤ SLEEPING_NORM          — cobweb at max opacity; particles drift to sink.
//
// R7 parity: uFreshness is computed by the TypeScript wrapper using
// freshness() from src/memory-palace/aqueduct.ts — never a copy.
//
// ────────────────────────────────────────────────────────────────────────────

uniform float uTime;
uniform float uFreshness;

varying float vFreshness;
varying vec2  vUv;
varying vec3  vWorldPos;

// Cobweb threshold: exp(-3) ≈ 0.05 (freshness at 90d with tau=30d)
const float COBWEBS_NORM = 0.05;

void main() {
  vFreshness = uFreshness;
  vUv        = uv;

  // At sleeping threshold (very stale), slowly drift vertex toward origin.
  // Drift speed scales smoothly across [SLEEPING_NORM, COBWEBS_NORM] so the
  // transition is a gradient rather than a step at f = SLEEPING_NORM (H3 fix).
  // "return-to-zero-point is visual, not destructive" — Vril ADR §9.
  float sleepingNorm = 0.001;
  float driftFactor  = 1.0 - smoothstep(sleepingNorm, COBWEBS_NORM, uFreshness);
  float driftSpeed   = driftFactor * 0.08;
  float driftPhase   = uTime * driftSpeed;

  // Gentle toward-origin drift: lerp position toward zero on XZ plane.
  vec3 driftPos = mix(position, vec3(0.0, position.y, 0.0), sin(driftPhase) * 0.05);

  vWorldPos   = (modelMatrix * vec4(driftPos, 1.0)).xyz;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(driftPos, 1.0);
}
