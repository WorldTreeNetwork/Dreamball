// ─── dust-cobweb.frag.glsl ───────────────────────────────────────────────────
//
// Sprint-001 S5.5 — Dust-cobweb overlay shader (fragment stage).
//
// Cobweb opacity proportional to decay depth when freshness < cobweb threshold.
// At freshness floor (<365d sleeping), draws particles drifting toward ambient
// sink per Vril ADR §9 "return-to-zero-point is visual, not destructive".
//
// Palette:
//   COBWEB_GREY  — desaturated cool grey for cobweb filaments.
//   DUST_OCHRE   — dusty ochre at intermediate staleness.
//   SINK_BLUE    — cold blue ambient sink color for fully-sleeping aqueducts.
//
// Opacity curve:
//   freshness = 1.0  → opacity = 0   (invisible — fresh aqueduct)
//   freshness = 0.05 → opacity ≈ 0.4 (cobweb threshold)
//   freshness = 0.0  → opacity = 0.8 (sleeping — full cobweb)
//
// ────────────────────────────────────────────────────────────────────────────

precision highp float;

uniform float uFreshness;

varying float vFreshness;
varying vec2  vUv;

const vec3 COBWEB_GREY = vec3(0.72, 0.70, 0.68);
const vec3 DUST_OCHRE  = vec3(0.55, 0.46, 0.32);
const vec3 SINK_BLUE   = vec3(0.12, 0.18, 0.28);

// Freshness thresholds — must track aqueduct.ts's DUSTY_MS/COBWEBS_MS/SLEEPING_MS.
// Drift is detectable via the R7 parity test (traversal.test.ts).
// Cobweb overlay engages below this freshness threshold (≈ exp(-3), 90d, tau=30d).
const float COBWEBS_NORM  = 0.05;
// Sleeping threshold (≈ exp(-12.2), 365d, tau=30d).
const float SLEEPING_NORM = 0.001;

// Cheap procedural cobweb pattern from UV coords.
// Generates a faint radial + cross-hatch pattern mimicking silk strands.
float cobwebPattern(vec2 uv) {
  // Polar coords from UV center
  vec2 centered = uv - 0.5;
  float r       = length(centered);
  float theta   = atan(centered.y, centered.x);

  // Radial rings (sparse, like actual cobweb)
  float rings = abs(sin(r * 20.0)) * 0.3;

  // Angular spokes (8 spokes)
  float spokes = abs(sin(theta * 8.0)) * 0.2;

  return clamp(rings + spokes, 0.0, 1.0);
}

void main() {
  float f = clamp(vFreshness, 0.0, 1.0);

  // Opacity: zero above cobweb threshold, ramps up as aqueduct decays.
  float decayDepth = clamp(1.0 - (f / COBWEBS_NORM), 0.0, 1.0);
  float opacity    = decayDepth * 0.8;

  if (opacity < 0.01) {
    discard;  // Invisible above threshold — no overdraw cost.
  }

  // Colour: lerp from dust ochre → cobweb grey → sink blue as decay deepens.
  // smoothstep so the sleep tint eases in across [SLEEPING_NORM, COBWEBS_NORM]
  // instead of step-stopping at f = SLEEPING_NORM (H3 review fix).
  float sleepFactor = 1.0 - smoothstep(SLEEPING_NORM, COBWEBS_NORM, f);
  vec3 base         = mix(DUST_OCHRE, COBWEB_GREY, decayDepth);
  vec3 color        = mix(base, SINK_BLUE, sleepFactor * 0.5);

  // Multiply by cobweb pattern for visual texture
  float pattern = cobwebPattern(vUv);
  color = color * (0.4 + 0.6 * pattern);

  gl_FragColor = vec4(color, opacity * pattern);
}
