# Tasks

- [x] Name Star Tamagotchi as the viewer-shell mesh in
      `docs/character-dreamball-rendering.md` (path, capsule, auto-fit,
      Blender provenance, stand-in until a dedicated container mesh)
- [x] Confirm `/characters/star-tamagotchi.glb` and
      `/characters/star-tamagotchi.ball` still load on `/demo/star`
      (existing path; no new route)
- [x] Close or update `Dreamball-5hs.2` once those notes land; leave
      `Dreamball-5hs.3` blocked only on this change being folded, not on
      a missing `.blend`

Findings (not boxes): repo GLB is already optimized (~1 MB / 18k tris,
webp textures). AvatarModel auto-fit is the scale contract — do not
retune for Star. `file(1)` reports `glTF binary model, version 2,
length 1047560 bytes` (magic `glTF`). Capsule still embeds
`/characters/star-tamagotchi.glb` at byte 3023. `/demo/star` still
fetches `/characters/star-tamagotchi.ball` with `lens="avatar"`. No
`static/shell/` copy. `Dreamball-5hs` / `5hs.2` / `5hs.3` are not in
this beads db (`bd show` → no issue found); nothing to close.
