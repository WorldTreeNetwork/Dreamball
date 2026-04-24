// ─── mythos-lantern.vert.glsl ────────────────────────────────────────────────
//
// Sprint-001 S5.5 — Mythos-lantern stub shader (vertex stage).
//
// STUB MVP: Single lantern-like point-light drawn at the palace fountain
// zero-point. Full lantern-ring (FR60f) is deferred to Growth tier.
//
// Acceptance note (S5.5 AC — per-shader micro-spike gate):
//   This stub delivers: single static lantern sphere at origin, no uniforms
//   required. The Growth tier will add:
//     - lantern-ring topology (N lanterns in polar orbit)
//     - halo / bloom post-process pass
//     - mythos-chain heat: hotter when more true-naming actions recently
//   These are NOT sprint-001 deliverables. The stub is kept as a reference
//   implementation matching sprint-004-logavatar's /spike/* pattern.
//
// No dynamic uniforms at MVP — the lantern is static.
//
// ────────────────────────────────────────────────────────────────────────────

varying vec3 vNormal;
varying vec3 vWorldPos;

void main() {
  vNormal   = normalize(normalMatrix * normal);
  vWorldPos = (modelMatrix * vec4(position, 1.0)).xyz;

  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
