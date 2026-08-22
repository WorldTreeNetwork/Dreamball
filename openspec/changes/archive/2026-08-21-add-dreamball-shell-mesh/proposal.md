# add-dreamball-shell-mesh

> **ACTIVE BUILD**
Human activated it.

## Why

The viewer DAG (`Dreamball-5hs`) needed a canonical 3D mesh for the
DreamBall container. A pokeball-style Blender file was not on disk.
Duke named Star Tamagotchi as the stand-in — the character glTF already
in this repo, already framed by AvatarLens. This change records that
choice so later shell-lens and viewer-app work load a known path instead
of hunting for a missing `.blend`.

## What

- Capability `dreamball-shell`: the viewer-shell mesh is Star Tamagotchi.
- Runtime asset: `static/characters/star-tamagotchi.glb`, served at
  `/characters/star-tamagotchi.glb`.
- Envelope: `static/characters/star-tamagotchi.ball` still holds the
  `look.asset` pointer + Blake3 hash; wasm parse/verify is unchanged.
- Framing: existing AvatarModel auto-fit (largest AABB axis = 2, base on
  y = 0). No Star-specific scale.
- Provenance: `/Users/dukejones/work/Family/StarTamagotchi/Star Tomagatchi.blend`
  stays outside the repo. Do not re-export. Do not copy the GLB to
  `static/shell/`.
- Note in `docs/character-dreamball-rendering.md` that this mesh is also
  the viewer-shell stand-in until a dedicated container mesh exists
  (`add-dreamball-shell-lens` / `Dreamball-5hs.3`).

## Impact

- Capabilities: ADDED `dreamball-shell`
- ADRs: none

## User journey & surfaces

No new UI because `/demo/star` already fetches the signed capsule, runs
`verifyBall` / `parseBall`, and renders this glTF through AvatarLens.
This change only names that mesh as the canonical viewer shell. Empty /
failed / off states stay the crystal placeholder AvatarLens already
shows. New viewer chrome is `add-dreamball-shell-lens` and
`add-dreamball-viewer-app`.

## Out of scope

- Shell lens, lighting, idle motion, type-tinted materials (`add-dreamball-shell-lens`, `Dreamball-5hs.3`)
- Viewer webapp route and bucket/filename fetch (`add-dreamball-viewer-app`, `add-transmittable-fetch`)
- Transmittable type pin (`Dreamball-5hs.1`)
- Re-export from Blender or a pokeball-style replacement mesh
- Duplicating the GLB under `static/shell/`
- Changing `look.asset`, hashes, or the wasm parse path
