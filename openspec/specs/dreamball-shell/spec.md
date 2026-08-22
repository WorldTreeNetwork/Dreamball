# dreamball-shell

Living capability. Folded from `add-dreamball-shell-lens` on 2026-08-19
and `add-dreamball-shell-mesh` on 2026-08-21.

## Requirements

### Requirement: Shell lens renders the canonical mesh, not look.asset

The system SHALL provide a `shell` lens that loads the canonical
viewer-shell glTF (`/characters/star-tamagotchi.glb`) through AvatarModel
auto-fit. The shell mesh SHALL NOT be taken from the current ball's
`look.asset`. `lens="avatar"` SHALL keep reading `look.asset`.

#### Scenario: Shell ignores inner look

- GIVEN a DreamBall whose `look.asset` is missing or points at some
  other mesh
- WHEN DreamBallViewer renders with `lens="shell"`
- THEN Star Tamagotchi is on screen (canonical URL), not that other
  mesh

#### Scenario: Avatar path unchanged

- GIVEN `/demo/star` with `lens="avatar"`
- WHEN the page loads the signed capsule
- THEN AvatarLens still loads `look.asset[0].url` and the shell lens is
  not involved

### Requirement: Shell is dispatched from DreamBallViewer

`shell` SHALL be a `LensName`. DreamBallViewer SHALL render ShellLens
when `lens="shell"`. Callers SHALL NOT mount a second viewer stack.

#### Scenario: Named lens

- GIVEN `import { DreamBallViewer } from '$lib'`
- WHEN a page sets `lens="shell"`
- THEN ShellLens mounts inside the existing viewer and no second Canvas
  host is required of the caller

### Requirement: Orbitable studio framing with crystal fallback

ShellLens SHALL reuse AvatarLens studio lighting (StudioEnvironment,
three-point lights, BloomEffect) and OrbitControls with damping and
auto-rotate. If the canonical GLB is missing or the load fails, it
SHALL show the crystal icosahedron placeholder and MUST NOT block on
the network.

#### Scenario: Happy path on /demo/shell

- GIVEN `/characters/star-tamagotchi.glb` is served
- WHEN an observer opens `/demo/shell`
- THEN they see an orbitable, auto-rotating Star Tamagotchi in the
  studio frame

#### Scenario: Failed mesh

- GIVEN the GLB URL 404s or the loader errors
- WHEN ShellLens renders
- THEN the crystal placeholder is visible and a mesh-failed hint is
  shown

#### Scenario: Storybook

- GIVEN Storybook `Lenses/ShellLens`
- WHEN the happy-path story loads
- THEN the canvas mounts without a WebGL exception

### Requirement: Canonical viewer-shell mesh is Star Tamagotchi

The DreamBall viewer shell mesh SHALL be the Star Tamagotchi glTF at
`static/characters/star-tamagotchi.glb`, served at
`/characters/star-tamagotchi.glb`. The signed capsule
`static/characters/star-tamagotchi.ball` SHALL remain the envelope that
points at that asset via `look.asset` (site-relative URL plus Blake3
hash). The system SHALL NOT duplicate the GLB under `static/shell/` or
another alias path.

#### Scenario: Served fixture is the shell

- GIVEN a checkout that includes `static/characters/star-tamagotchi.glb`
- WHEN a consumer fetches `/characters/star-tamagotchi.glb`
- THEN they receive that glTF binary — the same file AvatarLens already
  renders on `/demo/star`

#### Scenario: Envelope still owns the pointer

- GIVEN `static/characters/star-tamagotchi.ball`
- WHEN `dreamball.wasm` verifies and parses it
- THEN `look.asset` names `/characters/star-tamagotchi.glb` (or the
  existing site-relative URL) and a Blake3 hash, and the renderer does
  not hand-parse the capsule

### Requirement: Frame via existing AvatarModel auto-fit

The shell mesh SHALL be framed by AvatarModel auto-fit: recentre on the
origin, uniformly scale so the largest axis-aligned bounding-box
dimension equals `fit` (default 2 world units), then lift so the base
sits on `y = 0`. Star Tamagotchi SHALL NOT receive a special scale or
origin override.

#### Scenario: Same camera as the character demo

- GIVEN the Star Tamagotchi GLB loaded through AvatarModel with default
  `fit`
- WHEN the viewer shell uses that mesh
- THEN the object is centred, about 2 world-units on its longest axis,
  standing on `y = 0`

#### Scenario: Missing or failed mesh still falls back

- GIVEN the GLB URL is absent or the load fails
- WHEN AvatarLens (or a later shell lens that reuses it) renders
- THEN the existing crystal placeholder is shown and the surface does
  not hang on the network

### Requirement: Blender file is provenance, not the runtime asset

The Blender source
`/Users/dukejones/work/Family/StarTamagotchi/Star Tomagatchi.blend`
SHALL be treated as authoring provenance outside this repository.
Runtime load SHALL use the optimized GLB already in
`static/characters/`. This change SHALL NOT re-export from Blender.

#### Scenario: Clean checkout does not need Blender

- GIVEN a clean clone with no `.blend` files
- WHEN the viewer loads the shell mesh
- THEN it succeeds from `static/characters/star-tamagotchi.glb` without
  Blender or a network fetch of the blend
