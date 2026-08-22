## ADDED Requirements

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
