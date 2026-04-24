// ─── mythos-lantern.frag.glsl ────────────────────────────────────────────────
//
// Sprint-001 S5.5 — Mythos-lantern stub shader (fragment stage).
//
// STUB MVP: Renders a single warm lantern sphere at the palace zero-point.
// The sphere has a soft radial glow — brightest at center, dim at edges.
//
// Growth FR60f deferred items (do NOT implement here):
//   - Polar lantern ring (N orbs in orbit around zero-point)
//   - Halo / bloom pass
//   - Mythos-chain heat driving lantern brightness
//   - Animated flicker correlated with oracle activity
//
// Palette:
//   LANTERN_CORE — bright warm gold at lantern center.
//   LANTERN_RIM  — cooler amber at sphere edge.
//   AMBIENT      — dark ambient fill.
//
// ────────────────────────────────────────────────────────────────────────────

precision highp float;

varying vec3 vNormal;
varying vec3 vWorldPos;

const vec3 LANTERN_CORE = vec3(1.00, 0.90, 0.55);
const vec3 LANTERN_RIM  = vec3(0.80, 0.55, 0.20);
const vec3 AMBIENT      = vec3(0.04, 0.04, 0.08);

// Note: `cameraPosition` is a built-in uniform injected by Three.js's
// WebGLRenderer. If this shader is ever compiled outside a Three.js
// ShaderMaterial (raw WebGL / future WebGPU path without tsl translation),
// bind cameraPosition explicitly as `uniform vec3 cameraPosition;`.

void main() {
  // Simple rim-light: dot product with view-up vector gives edge glow.
  vec3 viewDir  = normalize(cameraPosition - vWorldPos);
  float rimDot  = 1.0 - max(dot(vNormal, viewDir), 0.0);
  float core    = 1.0 - rimDot;          // 1 at center, 0 at edge

  // Smooth Fresnel-like glow — lantern brightest at center.
  float glow   = core * core;
  float rim    = pow(rimDot, 3.0) * 0.4; // subtle outer halo

  vec3 color   = AMBIENT + LANTERN_CORE * glow + LANTERN_RIM * rim;

  // Premultiplied alpha so the lantern blends additively with the scene.
  float alpha  = clamp(glow + rim * 0.5, 0.0, 1.0);
  gl_FragColor = vec4(color * alpha, alpha);
}
