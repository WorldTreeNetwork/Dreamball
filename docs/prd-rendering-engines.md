# PRD — Rendering Engines

**Status:** Draft v0 — 2026-04-24
**Scope:** Forward-looking. Sprint-001 ships the Web rendering engine (Threlte/Three.js)
via `PalaceLens.svelte` / `RoomLens.svelte` / `InscriptionLens.svelte`. This PRD
names the *structure* that keeps future rendering engines (Unreal, Blender,
native MR/VR) consumable against the same envelopes without protocol churn.
Sibling docs: [`PROTOCOL.md`](PROTOCOL.md) · [`VISION.md`](VISION.md) ·
[`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## 1. The stack

```
     ┌──────────────────────────────────────────────┐
     │  Rendering engine (pixels)                   │  Web (Threlte / Three.js)
     │                                              │  Unreal 5 (UE5 + Niagara)
     │                                              │  Blender (EEVEE / Cycles)
     │                                              │  Native MR/VR (visionOS, OpenXR)
     ├──────────────────────────────────────────────┤
     │  Lens (semantic binding)                     │  PalaceLens / RoomLens / InscriptionLens
     │  — maps envelope → rendering engine calls    │  (names stay consistent across engines;
     │  — chooses surfaces, compositing, LoD         │   each engine ships its own implementation)
     ├──────────────────────────────────────────────┤
     │  Store API / Domain verbs (D-007)            │  getPalace, roomContents, recordTraversal …
     │  — platform-neutral; adapter-swappable       │
     ├──────────────────────────────────────────────┤
     │  Envelope layer (PROTOCOL.md)                │  jelly.dreamball.field, .palace, .room,
     │  — CBOR bytes; dual-signed; CAS-addressed    │   .inscription, .mythos, .aqueduct, .layout, …
     └──────────────────────────────────────────────┘
```

**Rules:**

1. Envelopes carry **semantics**, never **pixels**. Coordinates, orientations,
   surface hints, ambient-palette, freshness inputs are semantic. Particle
   density, shader uniforms, frame budgets, compositing strategies are *not*
   in the protocol. They live in the lens / rendering-engine layer.
2. A **lens** is a named semantic binding (`PalaceLens`, `RoomLens`,
   `InscriptionLens`, `TimelineLens`, `AqueductLens`, …) whose contract is
   the store API + envelope shape. Each rendering engine ships its own
   implementation of each lens.
3. A **rendering engine** is the actual pixel producer. It doesn't know
   about envelopes directly; it receives decoded DTOs from the lens and
   emits frames. Multiple engines MAY render the same envelope.
4. **Freshness, conductance, phase, and other time-derived quantities** live
   in the **renderer-consumed code** (`aqueduct.ts`), not on the wire.
   This keeps the wire ontologically pure; renderers import the same
   module the oracle uses (bit-identical per R7 parity).

---

## 2. The field / dreamfield / world-shader

The outermost layer of a scene is `jelly.dreamball.field` (§12.1.5 in
PROTOCOL.md). Today it carries `omnispherical-grid`, `ambient-palette`,
`dream-field-id`. **This envelope IS the world-shader layer** — the
HDRI-equivalent for Dreamball scenes.

### 2.1 What a field declares

- **Topology** — `jelly.omnispherical-grid` (polar: pole-north, pole-south,
  camera-ring {radius, tilt, fov}, layer-depth onion shells, resolution).
  Field-level space is *polar* because at the outermost layer the natural
  description is "distance from origin + angle" — nested dreamballs are
  reference frames inside the shell.
- **Ambience** — `ambient-palette` (hex colors or asset refs). The
  Blender-HDRI analogue: sets the environmental light + sky + horizon tint.
  Extensible: a future `hdri-source: <jelly.asset media-type=image/hdr>`
  attribute could carry a captured environment map without a breaking
  protocol change (new attribute, old readers ignore).
- **Identity** — `dream-field-id` groups related fields (e.g. variants of
  the same palace for time-of-day or season).

### 2.2 Extensions (follow-up sprints, reserved now)

- **`splat-scene` attribute**: a field MAY carry a 3D Gaussian splat asset
  (`jelly.asset` with media-type `application/splat+sog` or `+spz`) as its
  environmental geometry. The splat sits as the shell; inscriptions and
  rooms live inside it in local cartesian frames. Authoring tooling for
  importing splat captures into a Dreamball field is a future concern
  (see §9 "real-space import pipeline") — the protocol just reserves the
  slot.
- **`hdri-cubemap` attribute**: reserved for captured environment probes.
- **`worldshader-program` attribute**: reserved for parametric shader
  programs (e.g. a noise-field, a caustic, a dynamic sky). Renderer-engine-
  specific; shipped as a small DSL that compiles to GLSL / HLSL / MSL /
  OSL. Out of sprint-001 scope.

### 2.3 Why "field" not "world"

"World" connotes a singular global. Dreamball fields are composable,
nestable, and personal. A palace has a field. A room MAY override the
ambient inside it (growth-tier). A guild common-room MAY share one field
across all members. "Field" captures this multiplicity; "world-shader"
is the Blender analogy, used only as a communication shortcut.

---

## 3. Content modalities — how a "thing" gets its pixels

A Dreamball object's visual body is carried as a `jelly.asset` (Blake3-
addressed bytes + media-type). The lens picks a renderer path based on the
media-type of the asset AND the inscription/object's `surface` hint:

| Modality | Media-type | Description | Compression |
|---|---|---|---|
| Text-on-surface | `text/markdown`, `text/plain`, `text/asciidoc` | Rendered via §13.7 inscription lens; surface hint chooses scroll/tablet/etched-wall/… | — |
| Textured mesh | `model/gltf-binary`, `model/gltf+json` | Standard PBR — BaseColor / Metallic-Roughness / Normal / AO / Emissive textures | Draco + KTX2 |
| Splatted capture | `application/splat+sog`, `application/splat+spz`, `application/splat+ply` | 3D Gaussian splat — *compression of viewpoint-conditional color tensor* | SOG 95% / SPZ 90% |
| Procedural shader | `application/worldshader+v1` (reserved) | Tiny parametric program; renderer compiles to native | — |
| Glyph / symbol | `image/svg+xml`, `image/png` | Flat symbolic overlay | — |
| Media (audio/video) | `audio/*`, `video/*` | Spatial ambient or attached clip | — |

**Splats are compression, not a different thing.** A splat is a tensor of
colors parameterized by camera viewpoint — mathematically equivalent to a
dense view-dependent sampling of the object's appearance. It doesn't
replace mesh/material; it's an alternate delivery channel for the same
visual intent. A mature scene MAY carry both (mesh for structure, splat
for photoreal appearance) with the renderer doing depth-composited
hybrid rendering (see §5.3).

**Dynamic objects are harder to splat.** Static captures are the sweet
spot. When objects move inside a scene, the splat's viewpoint-conditional
color tensor drifts; today the workflow is re-capture or per-instance
LBS-rigged Gaussians (sprint-004-logavatar proved this path). For
Dreamball: static room-shell splats + mesh-based movable objects is the
pragmatic hybrid.

**Splats are queryable, not just renderable.** A splat scene
densely answers two questions that the rest of the rendering pipeline
asks constantly: `sampleRadiance(p, ω) → RGB` (what colour and
intensity arrive at point `p` from direction `ω`?) and
`sampleDensity(p) → α` (how much occluding matter sits there?).
Bloom-as-postprocess is one example of a stage that *fakes* an answer
the splat already encoded — but the same critique generalises to IBL,
ambient occlusion, reflections, fog, light probes, and per-aspect
mood shaders. §4 promotes those two queries to the renderer's primary
primitives and specifies the consumer pattern, the operator algebra
that handles post-effects, and the bloom-replacement (§4.3.1) as the
first concrete consumer to ship. See [`docs/VISION.md`](VISION.md)
§4.4.6 for the *why*; §4 nails the *how*.

## 4. Cached radiance — the splat field as universal scene query

> Added 2026-05-02. The architectural pattern that ties splats /
> NeRFs back into the rest of the renderer. An earlier draft of this
> PRD had a §3.1 covering only the bloom-replacement; once the broader
> pattern came into focus that subsection was promoted here, with the
> bloom replacement landing as one of several consumers (§4.3.1).

A 3D Gaussian Splat scene — and any neural-radiance-field equivalent —
is not just a rendering modality. It is a **pre-baked answer** to two
queries the rest of the rendering pipeline asks constantly:

- **`sampleRadiance(p, ω) → RGB`** — what colour and intensity arrive
  at point `p` from direction `ω`?
- **`sampleDensity(p) → α`** — how much occluding matter sits at `p`?

A splat capture *is* those two functions, evaluated densely throughout
the captured volume and compressed into a sparse representation
(gaussians + spherical-harmonic coefficients). Treating them as the
renderer's two fundamental primitives — and treating downstream passes
as *consumers* of those primitives — collapses a stack of bespoke
shaders, baking steps, and post-process passes into one queryable
scene representation with a small operator algebra applied to it.

Three properties make this a paradigm rather than a rendering trick:

1. **The query doesn't care how the answer is stored.** Whether the
   underlying representation is 3DGS, a NeRF MLP, a baked irradiance
   probe grid, or a fallback authored environment SH, downstream
   consumers see one interface. New radiance representations slot in
   without rewriting their consumers.
2. **Queries can be amortised at known points.** An avatar's bounding
   sphere, a door threshold, a sit-position — anywhere the renderer
   *will* sample, the radiance can be pre-baked once and re-read
   trivially. The fully-general per-fragment integration is reserved
   for cases that genuinely need it.
3. **Post-processing reduces to operators on radiance.** Tonemap,
   exposure, white balance, colour grade, time-of-day, mood/feel —
   all are matrix transforms (or learned MLPs) applied to the SH
   coefficients before evaluation. Five framebuffer passes collapse
   into one matmul applied at sample time. The operators are small
   and differentiable, which makes them naturally trainable with ML
   techniques without the protocol layer needing to know.

This section is the architectural counterpart to §5 (per-engine
concerns). Per-engine sections describe how each runtime *executes*
rendering; this section describes the cross-engine scene-query model
they all share.

### 4.1 The two primitives

Each rendering engine exposes the same shader-side interface, with
implementations matching its content modality:

```wgsl
// Shown in WGSL; engines lower to GLSL / HLSL / MSL as appropriate.
fn sampleRadiance(p: vec3<f32>, dir: vec3<f32>) -> vec3<f32>;
fn sampleDensity(p: vec3<f32>) -> f32;
```

| Backing representation | `sampleRadiance` impl | `sampleDensity` impl |
|---|---|---|
| 3D Gaussian splat | Spatial-hash gaussian lookup → sum SH-evaluated contributions weighted by density at `p` | Sum gaussian density at `p` |
| NeRF / neural field | Forward pass of the MLP at `(p, dir)` | MLP density head at `p` |
| HDRI / environment SH only | Direction-only lookup (constant in `p`) | `0` everywhere — no occlusion info |
| Mesh-only (no splat / NeRF) | Stub returning authored environment SH | `0` — consumers fall back to classical shaders |

The interface is engine-stable. The implementation is per-engine and
per-content-modality. A scene MAY layer multiple backings (splat for
a captured palace shell + HDRI for the ambient beyond the shell);
the renderer composes them additively at sample time.

### 4.2 Probe points — pre-baked queries at known anchors

Per-fragment `sampleRadiance` calls are cheap individually but
expensive in aggregate. Two amortisations matter:

1. **Object-bound probes.** Each mesh Dreamball placed into a splat
   field carries a small SH probe at its bounding-sphere centre,
   refreshed only when the object moves more than a tunable
   footprint-radius. The probe is a 3-band SH coefficient set
   sampled from the surrounding splat field; the object's PBR
   shader reads that probe as its IBL term. An avatar walking
   through a captured palace updates its probe at human pace; the
   GPU sees IBL coefficients, not continuous radiance integration.
2. **Field-declared anchors** *(sprint-002 reserved).* The
   `jelly.dreamball.field` envelope can declare query-point anchors
   — coordinates where future renderers will frequently sample
   (doorways, ritual centres, sit-positions, hero camera rigs). The
   renderer pre-bakes SH probes at those anchors at session start;
   runtime queries become a trilinear interpolation in probe space.

This is the moral equivalent of light probes in classical engines,
but sourced from the captured radiance field rather than from an
authored lighting pass — and the Dreamball authoring layer never has
to think about probe placement; the field declares its hero points
and the renderer bakes accordingly.

### 4.3 Consumers

Each of these classical pipeline stages becomes a thin wrapper over
the two primitives, often in a few shader lines:

| Classical stage | Cached-radiance consumer | Notes |
|---|---|---|
| Bloom postprocess | Radiance accumulator (§4.3.1, codename *sploom*) | Per-splat off-DC radiance written to a halo target during rasterisation, gathered with content-driven extent. Replaces screen-space bloom. |
| Image-based lighting (HDRI bake) | Probe sampling on inserted meshes | §4.2 probes feed avatar / inscription PBR shaders. No HDRI bake; mesh lighting matches the captured scene. |
| Screen-space reflections | Splat-field radiance lookup at hit-direction | Reflective material → `sampleRadiance(hit, reflectDir)`. Edge-artefact-free wherever the splat field has support. |
| Ambient occlusion / soft shadows | Density ray-march | `sampleDensity` along the normal cone gives soft AO; along the light direction gives soft shadows. One representation, two queries. |
| Camera collision / pathfinding | Density threshold | "Walkable" is `sampleDensity(p) < ε` over the footprint. Splat-captured palaces ship with a collider for free. |
| Volumetric fog | Density × scatter coefficient | Density is the fog field. |
| Inscription auto-contrast | Luminance probe behind glyph | Read radiance integrated over the camera-facing hemisphere; pick text colour automatically. Inscriptions stay legible across captured backgrounds. |
| Splat LOD | SH-band trim with distance | Bands 3 → 2 → 1 → 0 reduces work and memory; same machinery as σ derivation in §4.3.1. (See open Q2.) |

§4.3.1 documents the radiance accumulator — the bloom-replacement
consumer — as the first one to ship, chosen because it lands in
sprint-002 alongside the splat lens and demonstrates the pattern
end-to-end on PlayCanvas / WebGPU.

#### 4.3.1 Radiance accumulator (bloom-replacement, codename *sploom*)

> Added 2026-05-02. The first concrete consumer of the §4.1
> primitives. Replaces the bloom postprocess for the `splat` lens on
> WebGPU and WebGL2-with-MRT. WebGL1 / non-MRT GPUs keep classic
> bloom as fallback.

**Goal.** Use each gaussian's HDR magnitude, off-axis SH residual,
and projected footprint to spread radiance into neighbouring pixels
during splat rasterisation, instead of approximating that spread
with a screen-space gaussian blur over the final framebuffer.

**Per-splat sploominosity σ.** Derived at load time from data the
splat already carries:

- HDR magnitude of the DC band (band-0 SH) — how bright the splat is.
- L1 norm of higher SH bands (1–3) relative to DC — how much of the
  splat's appearance is direction-dependent.
- Projected gaussian footprint Σ — how much screen area it covers.

σ is a function of these three (the precise function is a tunable;
starting point is `σ = saturate(magnitude − threshold) × (1 + sh_ratio)
× footprint_scale`). σ governs both the *amount* of off-DC radiance
written to the halo target and the *radius* over which the
accumulator spreads it. **No wire-level extension** — σ is a derived
per-splat attribute, computed once at load via the same per-splat
texture-lookup pattern sprint-004-logavatar proved out for LBS
rigging.

**Pipeline (PlayCanvas / WebGPU).**

1. **Splat rasterisation pass** — multiple render targets:
   - `surface` (RGBA16F): conventional splat output, DC colour
     evaluated at the camera direction, alpha-blended over the scene.
   - `halo` (RGBA16F): RGB carries the off-DC residual scaled by σ;
     alpha carries the per-pixel gather radius (σ × Σ projected to
     screen).
2. **Accumulator pass** — single full-screen draw that gathers from
   `halo` using a per-pixel radius read from its alpha channel: a
   *content-driven* gather, not a fixed kernel. Sum into `surface`.
3. **Tonemap + present** — ACES (or a learned operator per §4.4) on
   the combined buffer. No separate bloom blur.

**Fallback.** When MRT or float render-targets are unavailable
(WebGL1, some older mobile GPUs), keep PlayCanvas's `frame.bloom`
postprocess. `SplatLens.svelte` exposes the choice via a feature
flag (`sploom: 'auto' | 'on' | 'off'`), defaulting to `auto` (sploom
on capable GPUs, classic bloom otherwise). The current
`frame.bloom.intensity = 0.02` line in `SplatLens.svelte` becomes
the fallback's tuning knob, not the primary glow source.

**Tradeoffs.**

- **+** Glows match the captured scene's actual lighting: a sunlit
  capture and a candlelit capture produce visibly different halos
  without authoring intervention.
- **+** One full-screen multi-tap blur is replaced by one MRT
  attachment + one content-driven gather. On tile-based mobile GPUs
  (Apple, Mali) MRT cost is small relative to a multi-pass blur.
- **−** PlayCanvas's GSplat fragment shader must be patched to write
  the halo target. Until PlayCanvas exposes a clean splat-shader
  customisation surface, this is a vendored shader — pinned to a
  PlayCanvas version, gated by a `scripts/sploom-smoke.sh` (TBD)
  golden-frame comparison.
- **−** σ derivation runs once per splat at load. A 5M-gaussian
  scene is measurable; likely runs in a Web Worker as part of the
  .sog → GPU upload step.

**Reference test (TBD).** `scripts/sploom-smoke.sh` renders a
fixture SOG known to contain bright HDR splats, compares against
`tests/golden/sploom-fixture.png` within a perceptual tolerance,
and asserts the bloom-fallback path produces a measurably
*different* output — proves the two paths are genuinely distinct,
not silently collapsing to the same shader.

### 4.4 Operators — post-effects as matrix transforms on radiance

A tonemap, a colour grade, an exposure adjustment, a time-of-day
shift, a feel-aspect modulation — all are *transformations of
radiance*. Because the cached radiance field stores its values as
SH coefficients (linear basis functions), these transformations
become linear operators applied to the SH vector before evaluation:

```
sampleRadiance(p, ω) = SH-eval(M · sh_coeffs[p], ω)
```

…where `M` is a matrix uniform per pass / per object / per
feel-state.

Concrete operators:

- **Exposure** — a single scalar applied to all bands. Trivial.
- **White balance** — a 3×3 matrix on the per-channel DC bands.
- **Tonemap** — a learned non-linear operator approximated by a
  per-band matrix or, at higher quality, a tiny MLP applied to the
  vectorised SH.
- **Colour grade / LUT** — a 3×3 (or 4×4 with offset) on DC + a
  band-1/2 operator to preserve directional consistency.
- **Time-of-day** — a learned matrix per sun-angle, interpolated at
  runtime.
- **Feel-aspect modulation** — vril, warmth, mythos-lantern feed a
  small MLP whose output is a per-region SH operator. *Vril flowing
  into a room* literally rotates and scales that room's splat
  radiance field, no per-shader lighting hack required. The feel
  axis becomes a physical signal in the renderer rather than a
  uniform tweak.

Two architectural payoffs:

1. **Compositional.** A chain of effects (exposure → WB → grade →
   feel → tonemap) is matrix multiplication, not a chain of
   framebuffer passes. Five passes collapse into one matmul at
   sample time. (Non-linear operators like ACES need a small
   dedicated step; everything linear absorbs upstream.)
2. **ML-friendly.** The operator matrix is small, differentiable,
   and trainable. Given a target appearance and the cached
   radiance field, the operator can be **learned** end-to-end —
   the same way LUT-fitting or photometric calibration is learned
   today, but applied to the renderer's universal primitive
   instead of to a post-process LUT. Dreamball's "look" controls
   become a trained set of matrices rather than a stack of bespoke
   shaders. The wire format stays unaware: the operator is a
   render-time uniform shipped alongside the lens, never on the
   protocol layer.

### 4.5 What this unifies

A non-exhaustive list of classical pipeline passes that collapse
into operator-on-radiance-field:

- Bloom postprocess
- Tonemap shader
- Colour LUT / grading pass
- HDRI / IBL bake
- Light probe placement
- Screen-space reflections
- Ambient occlusion pass
- Volumetric fog pre-pass
- Time-of-day blend
- Per-aspect mood shaders (palette shifts, lantern glows, vril warmth)

Each becomes either (a) a query against `sampleRadiance` /
`sampleDensity` or (b) a matrix operator applied before the query.
The Dreamball renderer, in this framing, is **a small operator
algebra applied to a cached radiance field, sampled at probe points
or per-fragment as the consumer demands.**

### 4.6 Tradeoffs and open work

- **Memory.** A bricked SH probe grid covering a captured palace at
  reasonable resolution costs O(volume × bands × channels × bytes).
  Coarse for ambient probes, fine for hero anchors. Sprint-002
  reserves the field envelope's anchor list for hero placement. (See
  open question 7 in §10 for brick-size / refresh-threshold tuning.)
- **Sample quality away from splat support.** SH evaluation outside
  the splat hull is lower fidelity. Either (a) extrapolate
  gracefully with falloff, (b) defer to a coarse environment SH
  baked once at session start, or (c) mark out-of-hull regions and
  have consumers fall back to classical shaders.
- **Operator algebra spec.** The matrix operators in §4.4 need a
  small specification — which compose linearly, which require
  non-linear glue, how feel-aspect MLPs serialise (or stay
  client-local). See open question 6 in §10.
- **PlayCanvas integration cost.** Exposing `sampleRadiance` /
  `sampleDensity` from inside the GSplat shader pipeline currently
  requires a vendored shader fork; same caveat as §4.3.1.
- **Mesh-only fallback path.** When no splat / NeRF is present the
  primitives stub out and consumers degrade to classical shaders.
  The architectural pattern still applies — it bottoms out at `0`
  density and an authored environment SH for radiance.

---

## 5. Per-engine concerns

### 5.1 Web (Threlte / Three.js) — sprint-001

- Threlte on Svelte 5, Three.js r160-ish. Bundle weight matters.
- Compositing: **multi-canvas CSS (Strategy C)** for splat-plus-mesh
  scenes, **same-pass depth-composited (Strategy A)** for mesh-only
  scenes. See [ADR 2026-04-24-renderer-compositing.md](decisions/2026-04-24-renderer-compositing.md).
- Splat path: gsplat.js / Spark / GaussianSplats3D evaluated; all WebGL-
  only today. WebGPU splat rendering requires PlayCanvas or Babylon.js
  adoption, or fork-a-research-renderer. **Deferred to Growth-tier.**
- Shader pack: 4 Threlte materials (`aqueduct-flow`, `room-pulse`,
  `mythos-lantern` stub, `dust-cobweb`) per NFR14.

### 5.2 Unreal (follow-up, reserved)

- UE5 lens implementation rendering the same envelopes. Nanite-splat
  bridge (or native UE5 Gaussian-splat plugin — several shipping in 2025)
  handles splat-scene. Niagara for particle flows. Materials via UE5 Material
  Editor, driven by the same semantic hints.
- Coordinate conversion: Y-up-right-handed (Dreamball canonical) → Z-up-
  left-handed (UE5). One line of linear algebra, lives in the lens shim.
- Lens names identical to Web (`PalaceLens`, `RoomLens`, …) even though
  the implementation is UE5 blueprints/C++ — keeps the architectural
  pattern legible.

### 5.3 Blender (follow-up, reserved)

- Offline / preview path. EEVEE or Cycles. Useful for: thumbnail
  generation, cinematic renders of a palace for presentation, authoring
  tooling.
- Blender consumes the same envelopes via a Python add-on that calls into
  `jelly.wasm` for decode, then builds a Blender scene graph: field →
  World Shader node-graph (ambient-palette + HDRI); rooms → collections;
  inscriptions → text objects + materials; splat-scene → the `io_scene_gsplat`
  extension ecosystem (multiple shipping 2025).
- Not a runtime — an export/import bridge. But the lens names still apply
  (a "Blender PalaceLens" is the add-on's palace importer).

### 5.4 Native MR/VR (follow-up, reserved)

- visionOS / Meta Quest / OpenXR. Lens names identical. Palace
  walk-through is the killer demo — the omnispherical-onion topology
  maps naturally to head-locked scrolling + room-gaze selection.

---

## 6. Coordinate convention

**Dreamball's protocol operates in two coordinate regimes:**

1. **Outermost / field layer — polar.** The `jelly.omnispherical-grid`
   defines pole-north, pole-south, camera-ring (radius/tilt/fov), and
   onion-shell layer depth. Positions on the shell are implicitly (r, θ, φ)
   by the grid's resolution. The dreamfield is a polar shell, not a box.

2. **Inner / placement layer — cartesian, local to parent.**
   `jelly.layout.placement.position: [x, y, z]` is a cartesian offset
   from the parent dreamball's origin. No global coords exist. Nested
   dreamballs compose as nested reference frames.

**Canonical convention (cartesian side):** right-handed, Y-up, meters.
Every rendering engine converts to its native convention at the lens
boundary:

| Engine | Native | Conversion from canonical |
|---|---|---|
| Three.js / Threlte | Y-up right-handed, meters | identity |
| Unreal 5 | Z-up left-handed, centimeters | swap Y↔Z, negate X, scale ×100 |
| Blender | Z-up right-handed, meters | swap Y↔Z, negate resulting Y |
| visionOS (RealityKit) | Y-up right-handed, meters | identity |

**Quaternions:** `[qx, qy, qz, qw]` order, right-handed rotation. The
glTF 2.0 convention. Lenses rewrite to their native order at the
boundary.

**Why wire cartesian at the inner layer (not polar everywhere):**
- GPUs, shaders, mesh libraries, physics engines all speak cartesian.
- Polar-to-cartesian at every draw call is free (one `vec3`).
- Cartesian-to-polar is lossy at the origin (undefined φ at r=0) —
  protocol bugs hide in that edge case.
- The *semantic* polar-ness of dreamballs is already captured at the
  outer layer by `jelly.omnispherical-grid` — inner placements don't
  need to re-litigate it.
- Nested reference frames give you the polar-ness for free: a room at
  radius 3, angle (30°, 60°) on the palace shell translates to a
  cartesian local origin for its contents, and that translation is
  cached once at load time.

See [ADR 2026-04-24-coord-frames.md](decisions/2026-04-24-coord-frames.md)
for the full reasoning and the cached-resolution algorithm.

---

## 7. Surface registry & fallback chain

`Inscription.surface` is an open enum (PROTOCOL.md §13.7 already says
`<open-enum>`). This PRD formalizes how lenses discover supported surfaces
and how authors write cross-engine inscriptions:

1. Each lens publishes a **surface registry**: the list of surfaces it
   natively renders. E.g. Web `InscriptionLens` registers `scroll`,
   `tablet`, `book-spread`, `etched-wall`, `floating-glyph`. Unreal
   `InscriptionLens` might register `scroll`, `tablet`, `rune-pillar`,
   `holo-panel`.
2. An inscription MAY carry an optional `fallback: [surface, surface, …]`
   attribute. On render, the lens walks: `surface → fallback[0] → fallback[1] → …`
   until one is supported, else falls back to the always-present
   `scroll` (canonical baseline).
3. **`scroll` is the canonical baseline.** Every lens MUST render
   `scroll`. This is the protocol's minimum rendering contract.

See [ADR 2026-04-24-surface-registry.md](decisions/2026-04-24-surface-registry.md).

---

## 8. What lives where — the cheatsheet

| Concern | Layer | Why |
|---|---|---|
| Ed25519 + ML-DSA signatures, envelope types, CAS hashes | Protocol | Integrity / identity |
| Surface hint (string, open enum) | Protocol | Authorial intent; renderer-neutral |
| Fallback chain | Protocol (optional attribute) | Cross-engine portability |
| Coord convention (polar field + cartesian placement) | Protocol | Wire-level determinism |
| Ambient-palette, omnispherical-grid, dream-field-id | Protocol (field envelope) | World-shader inputs |
| Freshness / conductance / phase formulas | Shared TS module (`aqueduct.ts`) | Bit-identity between oracle + renderer (R7) |
| Particle count, frame budget, shader uniforms | Lens / rendering engine | Per-platform tuning |
| Compositing strategy, depth-writes, alpha-mode | Rendering engine | Engine-native |
| Physical units (cm vs m), handedness, up-axis | Lens boundary (conversion) | Engine-native |
| Splat format conversion (SOG ↔ SPZ) | Lens pipeline / build step | Engine-native |

---

## 9. Reserved extension points (informational, not sprint-001 work)

| Point | Where | Purpose |
|---|---|---|
| `jelly.dreamball.field.splat-scene` | PROTOCOL.md §12.1.5 | Environmental splat capture |
| `jelly.dreamball.field.hdri-cubemap` | PROTOCOL.md §12.1.5 | Captured environment probe |
| `jelly.dreamball.field.worldshader-program` | PROTOCOL.md §12.1.5 | Parametric shader DSL |
| `jelly.inscription.fallback` | PROTOCOL.md §13.7 | Cross-engine surface degradation |
| `application/splat+sog` / `+spz` / `+ply` media-types | `jelly.asset` | Splat content modality |
| `application/worldshader+v1` media-type | `jelly.asset` | Procedural shader DSL |
| Real-space import pipeline | Tooling (not protocol) | Convert captured spaces (photogrammetry / LiDAR / splat) into `jelly.dreamball.field` bundles with splat-scene + layout | Offline tool; no wire change |

None of the wire-level entries require a format-version bump to land
(all optional attributes or new media-types on existing envelope
slots). The real-space import pipeline is tooling that emits
already-canonical envelopes — it adds capability without changing the
protocol.

---

## 10. Open questions

1. **Worldshader DSL.** Does it exist as a small purpose-built thing, or
   do we adopt an existing one (MaterialX? ShaderX? OSL subset)?
   Priority: low; no rendering engine needs it in sprint-001.
2. **Splat LoD streaming across engines.** PlayCanvas has a mature LoD
   story; Unreal plugins vary; Blender is offline only. A Dreamball-native
   LoD metadata attribute on splat assets could unify this, but it's
   renderer-adjacent — may not belong on the wire.
3. **Physics / interaction layer.** When inscriptions become interactive
   (click → aqueduct traversal, drag → layout edit), the interaction
   semantics need a home. Sprint-001 routes through store domain verbs
   (`recordTraversal`); Growth-tier may need a dedicated lens concern.
4. **Dynamic splats for movable objects.** Sprint-004-logavatar proved
   per-frame deformation works via CPU LBS + per-splat texture lookup.
   Worth revisiting if/when Dreamball needs rigged splat avatars inside a
   palace (FR15–FR17 Tier-2 territory).
5. **Sploom σ: derived or wire-level?** §4.3.1 derives σ at load time
   from data already in the splat. If σ-based decisions become common
   across engines (Unreal native splat plugins, Blender importers), a
   wire-level σ attribute on splat assets could save redundant
   computation — at the cost of a Dreamball-specific extension that
   breaks compatibility with vanilla SOG / PLY consumers. Defer until
   at least two engines need it.
6. **Operator algebra spec.** §4.4 sketches feel-aspect modulation,
   tonemap, exposure, white balance, and grade as matrix transforms
   on the SH coefficients of the cached radiance field. The set of
   operators that compose linearly vs. require non-linear glue, the
   serialisation of feel-aspect MLPs (or whether they stay
   client-local), and the priority order when multiple operators
   stack — all need a short spec. Land alongside the first
   non-trivial feel-aspect lighting work; not blocking sprint-002.
7. **Probe grid resolution and budget.** §4.2 introduces field-
   declared anchors and per-object SH probes. The default brick size,
   refresh threshold (when does an avatar's probe re-bake?), and
   memory budget for a typical palace need empirical tuning once a
   real captured palace is in hand.

---

## 11. Sprint-001 scope confirmation

Sprint-001 ships **Web engine only** with the four-shader pack
(`aqueduct-flow` + `room-pulse` + `mythos-lantern` stub + `dust-cobweb`)
and the five-surface inscription pack (`scroll`/`tablet`/`book-spread`/
`etched-wall`/`floating-glyph`). All reserved extension points in §9 are
deferred. Surface registry + fallback chain is adopted on the wire NOW
(cheap; prevents future protocol churn) but the web lens is the only
participant.

The rendering-engines structure in this PRD is not a sprint-001
deliverable — it's the **map** that keeps sprint-001's decisions
composable with future engines.
