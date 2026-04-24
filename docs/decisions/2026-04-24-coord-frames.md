# 2026-04-24 — Coordinate frames: polar field, cartesian placements, nested reference frames

Sprint: sprint-001 · Epic: 5 · Significance: MEDIUM · Related:
[PRD §5](../prd-rendering-engines.md) · PROTOCOL.md §12.2 (omnispherical-grid),
§13.2 (layout)

## Context

Dreamballs are philosophically *nested spheres* — a palace is an
omnispherical onion-shell (PROTOCOL.md §12.2, VISION.md §4), rooms are
nodes on the shell, inscriptions live inside rooms. A pure protocol
would use **polar coordinates** throughout: everything is (r, θ, φ)
relative to the nearest reference-frame origin. This matches the
semantic intent (dreamballs ARE reference frames) and avoids implying a
global cartesian space that doesn't exist.

But every GPU, mesh library, physics engine, and 3D runtime speaks
**cartesian**. Polar-to-cartesian conversion at every draw call is
trivial (one `vec3`); cartesian-to-polar is lossy at the origin
(undefined φ at r=0) and adds noise to what are supposed to be exact
positions. The protocol's float exception (§12.2, §13.2) already
carves out cartesian floats; introducing polar would require either a
second float carve-out or lossy conversions at the wire.

## Decision

**Two coordinate regimes, composed via nested reference frames:**

1. **Outermost / field layer — polar.**
   `jelly.omnispherical-grid` already defines `pole-north`,
   `pole-south`, `camera-ring` (radius/tilt/fov), and `layer-depth`
   (onion shells). Positions on the shell are naturally polar: a room
   at (r=3, θ=30°, φ=60°) on the palace shell. This is the
   **world-shader topology** — the outer skin of the field.

2. **Inner / placement layer — cartesian, local to the parent dreamball.**
   `jelly.layout.placement.position: [x, y, z]` (PROTOCOL.md §13.2) is a
   cartesian offset **from the parent dreamball's origin**. No global
   world coordinates exist. An inscription at [0.5, 1.2, -0.3] inside
   a room at shell-position (r=3, θ=30°, φ=60°) has an *effective*
   world position only after reference-frame resolution.

3. **Canonical cartesian convention:** right-handed, Y-up, meters,
   quaternions in `[qx, qy, qz, qw]` order (glTF 2.0). Each rendering
   engine converts to its native convention at the lens boundary (see
   [PRD §5](../prd-rendering-engines.md) table).

4. **Nested reference frames compose as cached transforms.**
   - Load time: walk the envelope tree (field → rooms → inscriptions
     → nested children) and compute each dreamball's world matrix once.
     Cache on the decoded DTO: `room.worldMatrix`, `inscription.worldMatrix`.
   - Render time: GPU consumes `worldMatrix × localPosition` — O(1) per
     object, zero polar math in the shader.
   - Re-walk only when the envelope tree changes (rare — palace shifts
     per VISION §15.7 trigger a cache invalidation for affected subtrees).

## Algorithm — world-matrix resolution

```ts
// Called once per load, or on layout-shift invalidation.
function resolveWorldMatrices(field: Field): Map<Fp, Mat4> {
  const cache = new Map<Fp, Mat4>()
  const fieldMat = polarShellToCartesian(field.omnisphericalGrid)
  cache.set(field.fp, fieldMat)

  for (const room of field.rooms) {
    const localMat = room.layout   // cartesian in field frame
      ? mat4FromPosQuat(room.layout.position, room.layout.facing)
      : deterministicGridFallback(room.fp, field.rooms.length)
    cache.set(room.fp, mat4Mul(fieldMat, localMat))

    for (const inscription of room.contents) {
      const insMat = mat4FromPosQuat(
        inscription.placement.position,
        inscription.placement.facing,
      )
      cache.set(inscription.fp, mat4Mul(cache.get(room.fp)!, insMat))
    }
  }
  return cache
}
```

`polarShellToCartesian` converts the omnispherical-grid's (pole-north,
pole-south, camera-ring) into a cartesian basis for the field's
origin — runs once per field load.

## Why not polar all the way

1. **GPU cost.** Cartesian is the GPU-native format. Converting at
   every vertex shader invocation is free (one `vec3`), but the
   conversion code has to exist; preferring cartesian at the
   placement layer keeps shaders identical across engines.
2. **Float exception scope.** Today PROTOCOL.md §12.2 and §13.2 carve
   out `[x,y,z]` cartesian floats. Adding polar would need a second
   carve-out OR lossy conversions at the wire.
3. **Library interoperability.** glTF, USD, FBX, OBJ — every 3D
   format the ecosystem cares about is cartesian. Polar would force
   conversion bugs at every export path.
4. **Origin singularity.** Polar φ is undefined at r=0. Cartesian has
   no such singularity. The protocol should prefer the
   mathematically clean representation.
5. **Nested frames already give polar its due.** A room's local
   cartesian origin sits at the shell position (r=3, θ=30°, φ=60°)
   inherited from the field's polar grid. The *semantic* polar-ness
   is preserved through the reference-frame chain; the wire just
   spells out cartesian offsets.

## Why not global cartesian

1. **Wrong ontology.** Dreamballs ARE reference frames. A global world
   coordinate implies a containing space that pre-exists the
   dreamballs, which contradicts VISION §4 (the field IS the
   space, not a view onto one).
2. **Composition.** Nested reference frames let a palace be nested
   inside a guild room inside another palace — each layer is a
   local cartesian + a position-in-parent. Global coords break
   composition.
3. **Editability.** Shifting a palace's autumn arrangement
   (VISION §15.7) only changes the palace's layout; all inscriptions
   inside move with it, because their positions are LOCAL. A global
   system would require rewriting every position.

## Consequences

- PROTOCOL.md §13.2 already has the right shape. Add one clarifying
  sentence: "Coordinates are local to the parent dreamball's origin;
  world positions are resolved by composing reference frames from
  the field outward."
- PROTOCOL.md §12.2 already has the right shape (polar at the field
  layer).
- Lens implementations cache resolved world matrices at load time.
- Engine adapters (Three.js / Threlte / Unreal / Blender) convert
  the canonical Y-up-right-handed to their native convention at the
  lens boundary. Per-engine conversion matrices listed in
  [PRD §5](../prd-rendering-engines.md).
- Renderer-side math for freshness, conductance, particle flow
  operates in the lens's native convention (Y-up in Web) — the
  canonical-to-native convert happens once per object on load.

## Alternatives considered

1. **Polar everywhere.** Rejected — cost, singularities, ecosystem
   friction (above).
2. **Global cartesian with no nesting.** Rejected — wrong ontology;
   breaks composition; breaks layout-shift ergonomics.
3. **Defer the decision.** Rejected — the choice is load-bearing on
   every lens, every renderer, every codegen output. Cheap to pin
   now; expensive to reconcile later.

## Aligned with existing pattern

- Aligned with `jelly.omnispherical-grid` (§12.2) — polar at the field
  layer is already in the protocol.
- Aligned with `jelly.layout.placement.position` (§13.2) — cartesian
  local positions are already in the protocol.
- The only new thing this ADR adds: the explicit statement that these
  are two regimes composed as nested reference frames, with a
  canonical cartesian convention and a per-engine conversion policy.

## Open questions

1. **Non-euclidean lenses.** A future "hyperbolic palace" lens (think:
   Escher stair-cases, M. C. Infinite spaces) would need non-euclidean
   local geometry. Reserved as a `placement.kind: "euclidean"` default
   with optional future kinds (`"hyperbolic"`, `"toroidal"`). Out of
   sprint-001 scope; mentioned here so the optional attribute is
   reserved.
2. **Scale.** Canonical meters works for room-scale; galactic-scale
   dreamballs might want parsecs. Reserved: a future optional
   `jelly.dreamball.field.scale` attribute could declare "this field's
   unit is meters × 10^N". No wire change; no current use case.
