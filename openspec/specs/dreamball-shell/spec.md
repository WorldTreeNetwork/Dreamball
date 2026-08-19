# dreamball-shell

Living capability. Folded from `add-dreamball-shell-lens` on 2026-08-19.
Canonical mesh naming (`add-dreamball-shell-mesh`) is still PENDING.

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
