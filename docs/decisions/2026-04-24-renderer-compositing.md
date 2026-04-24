# 2026-04-24 — Web rendering-engine compositing strategy

Sprint: sprint-001 · Epic: 5 · Significance: MEDIUM · Related:
[PRD §4.1](../prd-rendering-engines.md) · web3d-space research
(`docs/research/gaussian-splat-web-tools/synthesis.md`)

## Context

Epic 5 ships four Threlte GLSL shader materials on a single canvas.
Sprint-001 does not render splats. **But** the protocol reserves
`application/splat+sog`/`+spz` media types and a `splat-scene` surface
(see [ADR 2026-04-24-surface-registry.md](2026-04-24-surface-registry.md)
and [PRD §4.1](../prd-rendering-engines.md)), and the web3d-space
gaussian-splat research documents an **architectural wall**: no
WebGL/WebGPU splat library today accepts an externally-supplied
`GPUDevice`. Adding splats later without an intentional compositing
strategy forces a rewrite of `PalaceLens.svelte`.

Four compositing strategies surfaced in the web3d-space research
(`synthesis.md` §"Integration Architecture"):

| Strategy | Shape | Depth handling | Cost |
|---|---|---|---|
| A — Same-pass, splats first | One renderer, splats drawn with `depthWriteEnabled: false`, then meshes with depth on | No interpenetration | Lowest — zero extra resources |
| B — Offscreen texture | Splats render to a GPUTexture; composited as fullscreen quad background | No interpenetration | One viewport-size RGBA texture |
| C — Multi-canvas CSS | Two stacked `<canvas>`, splat canvas below, Threlte canvas above, `z-index` layering | Per-canvas depth only | Extra DOM element; CSS alpha compositing |
| D — Depth pre-pass | Mesh depth drawn to shared depth texture, splats read depth via `DEPTH_TEST` | Full interpenetration | Mesh drawn twice |

## Decision

**Sprint-001 ships Strategy A for mesh-only rendering (today's shader
pack). The architecture PRE-COMMITS to Strategy C (multi-canvas CSS) as
the chosen path when splats land in a follow-up sprint.** Rationale for
pinning Strategy C now even though splats are not in scope:

- **Minimum rewrite risk.** Strategy C is additive — a new `<canvas>`
  element below the Threlte canvas. No change to the Threlte render
  loop, no WebGPU device-sharing needed, no depth-texture plumbing.
- **Compatible with existing `alphaMode: 'premultiplied'`.** Web3d-
  space's existing boids codebase already uses premultiplied alpha on
  its canvas; Threlte defaults are the same. Two stacked canvases
  composite correctly with no shader changes.
- **Engine-independent.** Splat library choice (gsplat.js / Spark /
  GaussianSplats3D / PlayCanvas-as-splat-only) can change later without
  touching the mesh-rendering canvas.
- **Honest about the WebGPU gap.** Strategy D would need a shared
  GPUDevice — the one thing the web splat ecosystem doesn't offer
  today. Strategy C sidesteps the gap entirely.
- **Trade-off accepted.** No interpenetration between splats and
  meshes (a splat-captured room and a floating inscription can't
  occlude each other in 3D). Mitigation: put the splat capture on the
  *outer* canvas (world-shader / field background) and meshes/text on
  the *inner* canvas. This matches the semantic layering already in
  the protocol (field shell outside, placements inside).

## Sprint-001 deliverable

No code change from current Epic 5 plan. Strategy A is what Threlte
already does for a single-canvas multi-material scene. The ADR is
forward-looking.

## Follow-up deliverable (Growth-tier, when splats land)

- `PalaceLens.svelte` gains an optional `<SplatCanvas>` child rendered
  as a second `<canvas>` under the Threlte canvas, CSS-positioned with
  `position: absolute; inset: 0; z-index: 0`.
- Threlte canvas gets `z-index: 1` and `background: transparent`.
- The splat canvas loads a splat library (choice deferred — PlayCanvas
  standalone mode or a lightweight WebGL option).

## Alternatives considered

- **Commit to Strategy B (offscreen texture).** Rejected — requires
  shader plumbing to blit the texture into the Threlte render target;
  couples the mesh renderer to the splat renderer's timing.
- **Commit to Strategy D (depth pre-pass).** Rejected — requires a
  shared GPUDevice, which today's WebGL splat libraries don't expose;
  would force PlayCanvas engine adoption as a prerequisite.
- **Defer the decision.** Rejected — web3d-space's retrospective
  documents exactly this failure mode: "compass-not-map" — deferring
  compositing until splats land risks a mid-sprint wall identical to
  sprint-004-logavatar's D-002 v1.

## Consequences

- Epic 5 stories unchanged; no sprint-001 implementation impact.
- A future "splats in the palace" story can proceed without replanning
  the renderer architecture.
- When splats enter scope, [ADR 2026-04-24-surface-registry.md]'s
  fallback chain ensures lenses that can't render splats degrade
  gracefully to tablet/scroll.

## Aligned with existing pattern

Aligned with sprint-004-logavatar retrospective's **"spike before
promote"** pattern: this ADR is the architectural version of a spike —
it pins the compositing choice against an unverified future library
choice so the decision isn't coupled to the library decision.
