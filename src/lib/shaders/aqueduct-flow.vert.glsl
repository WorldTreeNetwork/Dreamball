// ─── aqueduct-flow.vert.glsl ────────────────────────────────────────────────
//
// Sprint-001 S5.1 — D-009 risk-gate shader.
//
// Aesthetic modes (documented here so the variant stays discoverable; per
// Story 5.1 "Aesthetic direction — subtle golden thread"):
//
//   • DEFAULT (uMode = 0): subtle golden thread. A thin luminous filament
//     traces the traversal path. Conductance modulates luminance + flow
//     speed. Freshness tints hue toward dust. Intended for busy scenes of
//     50 aqueducts; stays visually calm and fits ≤2ms frame budget.
//
//   • EARTHWORK (uMode = 1): opt-in Storybook control. Visible channel +
//     water volume + bank geometry. Used for showcase / presentation shots
//     celebrating an especially-strong memory bond. Parametric — the
//     variant is a uniform switch that expands the tube's radius and
//     enables a second pass of banks geometry in the fragment shader.
//     Hand-authored earthwork geometry is deferred (Growth tier).
//
// Uniforms:
//   uTime          — animation clock (seconds). Driven by Threlte's render loop.
//   uConductance   — from store.ts; Epic-2 formula at src/memory-palace/aqueduct.ts.
//   uFreshness     — from store.ts-derived store; uses freshness() in aqueduct.ts.
//   uMode          — 0 = thread (default), 1 = earthwork (opt-in).
//   uParticleCount — total particles along this aqueduct; clamped in JS.
//
// R7 parity: uniforms are supplied FROM the TypeScript wrapper which imports
// the SAME freshness() pure function as the server-side parity test (S5.5).
//
// ────────────────────────────────────────────────────────────────────────────

uniform float uTime;
uniform float uConductance;
uniform float uFreshness;
uniform int   uMode;
uniform float uParticleCount;

// Per-instance attribute: normalised position along the aqueduct path [0, 1].
// The wrapper lays out particles as an InstancedMesh; `instanceT` encodes the
// birth offset so each particle occupies a distinct slot on the path.
attribute float instanceT;

varying float vT;        // particle position on path in [0, 1] after flow
varying float vLum;      // luminance modulated by conductance × freshness
varying vec3  vViewDir;  // for the fragment's filament falloff

void main() {
  // Flow speed is proportional to conductance. Freshness scales luminance.
  // Speed coefficient 0.15 gives visible motion at conductance=0.2 within
  // 200ms mount latency (NFR10 slice); tunable via Storybook.
  float speed = uConductance * 0.15;

  // Wrap t into [0, 1] so particles loop along the path.
  float t = fract(instanceT + uTime * speed);
  vT = t;

  // Earthwork expands the channel's cross-section radius 3×.
  float radius = (uMode == 1) ? 0.12 : 0.04;

  // The wrapper passes two endpoint uniforms via `position.xy` on the
  // instanced mesh's quad — we treat object-space position as parametric:
  //   position.x in [-1, 1] is cross-section u
  //   position.y in [-1, 1] is cross-section v
  //   the vertex shader places each particle at path-position t
  //
  // The actual path geometry comes from uniforms uFrom / uTo supplied by the
  // wrapper (see Svelte material), interpolated linearly here. More complex
  // curves can be swapped in without re-authoring the shader (Story 5.2+).
  //
  // For the spike we use a straight segment from (-1,0,0) to (+1,0,0).
  // TODO FR18: accept path endpoints via attribute (per-instance uFrom/uTo)
  // or uniform so room-to-room aqueducts render at their real world positions
  // instead of collapsing to the local origin.
  vec3 from = vec3(-1.0, 0.0, 0.0);
  vec3 to   = vec3( 1.0, 0.0, 0.0);
  vec3 mid  = mix(from, to, t);

  // Local cross-section — billboard-ish quad around the path.
  vec3 offset = vec3(0.0, position.y * radius, position.x * radius);
  vec3 worldPos = mid + offset;

  // Luminance: conductance drives flow-strength, freshness dims toward floor.
  // At freshness ≤ 0.10 (floor), luminance drops to ≤ 10% of fresh baseline
  // (Story 5.1 AC (c) "freshness at floor dims luminance to ≤10%").
  float baseLum = max(uConductance, 0.15);
  vLum = baseLum * max(uFreshness, 0.10);

  vec4 mvPos = modelViewMatrix * vec4(worldPos, 1.0);
  vViewDir = normalize(-mvPos.xyz);
  gl_Position = projectionMatrix * mvPos;
}
