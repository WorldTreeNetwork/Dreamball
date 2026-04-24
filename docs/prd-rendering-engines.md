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
  (see §8 "real-space import pipeline") — the protocol just reserves the
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
hybrid rendering (see §4.3).

**Dynamic objects are harder to splat.** Static captures are the sweet
spot. When objects move inside a scene, the splat's viewpoint-conditional
color tensor drifts; today the workflow is re-capture or per-instance
LBS-rigged Gaussians (sprint-004-logavatar proved this path). For
Dreamball: static room-shell splats + mesh-based movable objects is the
pragmatic hybrid.

---

## 4. Per-engine concerns

### 4.1 Web (Threlte / Three.js) — sprint-001

- Threlte on Svelte 5, Three.js r160-ish. Bundle weight matters.
- Compositing: **multi-canvas CSS (Strategy C)** for splat-plus-mesh
  scenes, **same-pass depth-composited (Strategy A)** for mesh-only
  scenes. See [ADR 2026-04-24-renderer-compositing.md](decisions/2026-04-24-renderer-compositing.md).
- Splat path: gsplat.js / Spark / GaussianSplats3D evaluated; all WebGL-
  only today. WebGPU splat rendering requires PlayCanvas or Babylon.js
  adoption, or fork-a-research-renderer. **Deferred to Growth-tier.**
- Shader pack: 4 Threlte materials (`aqueduct-flow`, `room-pulse`,
  `mythos-lantern` stub, `dust-cobweb`) per NFR14.

### 4.2 Unreal (follow-up, reserved)

- UE5 lens implementation rendering the same envelopes. Nanite-splat
  bridge (or native UE5 Gaussian-splat plugin — several shipping in 2025)
  handles splat-scene. Niagara for particle flows. Materials via UE5 Material
  Editor, driven by the same semantic hints.
- Coordinate conversion: Y-up-right-handed (Dreamball canonical) → Z-up-
  left-handed (UE5). One line of linear algebra, lives in the lens shim.
- Lens names identical to Web (`PalaceLens`, `RoomLens`, …) even though
  the implementation is UE5 blueprints/C++ — keeps the architectural
  pattern legible.

### 4.3 Blender (follow-up, reserved)

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

### 4.4 Native MR/VR (follow-up, reserved)

- visionOS / Meta Quest / OpenXR. Lens names identical. Palace
  walk-through is the killer demo — the omnispherical-onion topology
  maps naturally to head-locked scrolling + room-gaze selection.

---

## 5. Coordinate convention

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

## 6. Surface registry & fallback chain

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

## 7. What lives where — the cheatsheet

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

## 8. Reserved extension points (informational, not sprint-001 work)

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

## 9. Open questions

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

---

## 10. Sprint-001 scope confirmation

Sprint-001 ships **Web engine only** with the four-shader pack
(`aqueduct-flow` + `room-pulse` + `mythos-lantern` stub + `dust-cobweb`)
and the five-surface inscription pack (`scroll`/`tablet`/`book-spread`/
`etched-wall`/`floating-glyph`). All reserved extension points in §8 are
deferred. Surface registry + fallback chain is adopted on the wire NOW
(cheap; prevents future protocol churn) but the web lens is the only
participant.

The rendering-engines structure in this PRD is not a sprint-001
deliverable — it's the **map** that keeps sprint-001's decisions
composable with future engines.
