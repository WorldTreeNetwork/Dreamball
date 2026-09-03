# add-dreamball-shell-lens

> **ACTIVE BUILD**

## Why

The viewer needs a 3D container on screen. Duke named Star Tamagotchi as
that mesh (`add-dreamball-shell-mesh`). AvatarLens already draws it when
the *ball's* `look.asset` points at the GLB. The shell lens is the
container path: it always loads the canonical shell mesh, independent of
whatever Transmittable contents sit inside. Reuse AvatarModel, studio
lights, orbit controls, bloom, and the crystal fallback — do not fork
DreamBallViewer.

## What

- Capability `dreamball-shell`: add a `shell` lens.
- `ShellLens` loads `/characters/star-tamagotchi.glb` through
  AvatarModel auto-fit (fit = 2, base on y = 0).
- Register `shell` on `LensName` / `ALL_LENSES` and dispatch it from
  DreamBallViewer.
- Surfaces: Storybook `Lenses/ShellLens` and `/demo/shell`.
- Missing or failed mesh → existing crystal placeholder; do not hang.
- Existing `lens="avatar"` character path is unchanged (still reads
  `ball.look.asset`).
- OrbitControls + StudioEnvironment + BloomEffect as in AvatarLens.
- Idle auto-rotate is in; pokeball open/close and type-tinted materials
  are not (Star is not a split capsule).

## Impact

- Capabilities: ADDED requirements on `dreamball-shell` (mesh path
  already named by PENDING `add-dreamball-shell-mesh`)
- ADRs: none

## User journey & surfaces

An observer opens `/demo/shell` (or the ShellLens Storybook story).
Working: Star Tamagotchi is on screen, orbitable, auto-rotating, studio
lit. Empty / failed: crystal icosahedron placeholder and a mesh-failed
hint, same as AvatarLens. Off: `/demo/star` still renders Star via
`lens="avatar"` from the capsule's `look.asset`. The later viewer app
composes this shell with Transmittable contents.

## Out of scope

- Naming the mesh (`add-dreamball-shell-mesh`, PENDING; asset already in
  `static/characters/`)
- Transmittable locator/fetch and `/view?bucket=&filename=`
  (`add-transmittable-locator`, `add-transmittable-fetch`,
  `add-dreamball-viewer-app`)
- Type-tinted materials, peel/open animation, wearer input
- PlayCanvas splat path, palace/room/inscription lenses
- Replacing or restyling AvatarLens
