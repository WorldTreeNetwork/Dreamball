// ─── aqueduct-flow.frag.glsl ────────────────────────────────────────────────
//
// Companion to aqueduct-flow.vert.glsl. See that file's header for the
// full aesthetic/mode documentation.
//
// DEFAULT  (uMode=0): subtle golden thread — thin luminous filament.
// EARTHWORK(uMode=1): visible channel + bank geometry.
//
// Palette:
//   FRESH_GOLD   — warm gold at full conductance + fresh freshness.
//   DUST_OCHRE   — desaturated ochre at floor freshness (Vril ADR §7 "dusty").
//   EARTH_BROWN  — bank geometry tint in earthwork mode.
//   WATER_TEAL   — channel water tint in earthwork mode.
//
// Freshness → hue lerp (fresh=gold, stale=dust): deliberate; matches
// Vril ADR §7 "dimmed by time. Cobwebs, dust."
//
// ────────────────────────────────────────────────────────────────────────────

precision highp float;

uniform float uTime;
uniform float uConductance;
uniform float uFreshness;
uniform int   uMode;

varying float vT;
varying float vLum;
varying vec3  vViewDir;

const vec3 FRESH_GOLD  = vec3(1.00, 0.82, 0.32);
const vec3 DUST_OCHRE  = vec3(0.55, 0.46, 0.32);
const vec3 EARTH_BROWN = vec3(0.36, 0.24, 0.14);
const vec3 WATER_TEAL  = vec3(0.15, 0.38, 0.42);

void main() {
  // Hue lerp: freshness∈[0,1] blends dust→gold.
  vec3 thread = mix(DUST_OCHRE, FRESH_GOLD, uFreshness);

  if (uMode == 1) {
    // Earthwork: composite bank + water + thread.
    // Bank is a wide dim earthy band; water is teal with a subtle ripple
    // driven by uTime; thread rides on top as the luminous overlay.
    float ripple = 0.5 + 0.5 * sin((vT * 12.0) + uTime * 2.0);
    vec3 water = mix(WATER_TEAL, WATER_TEAL * 1.4, ripple);
    vec3 base  = mix(EARTH_BROWN, water, 0.7);
    vec3 color = mix(base, thread, 0.55 * vLum);
    gl_FragColor = vec4(color, 1.0);
  } else {
    // Default: slim luminous thread. Soft falloff at the quad edges so the
    // particles don't look like hard rectangles.
    // vViewDir is unused in default; a future tube primitive would wire it up.
    float edge = smoothstep(0.0, 0.25, vT) * smoothstep(1.0, 0.75, vT);
    vec3 color = thread * vLum * edge;
    // Add a glow alpha so overlapping particles add (premultiplied alpha).
    float alpha = vLum * edge;
    gl_FragColor = vec4(color, alpha);
  }
}
