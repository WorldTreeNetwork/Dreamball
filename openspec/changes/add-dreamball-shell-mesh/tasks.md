# Tasks

- [ ] Name Star Tamagotchi as the viewer-shell mesh in
      `docs/character-dreamball-rendering.md` (path, capsule, auto-fit,
      Blender provenance, stand-in until a dedicated container mesh)
- [ ] Confirm `/characters/star-tamagotchi.glb` and
      `/characters/star-tamagotchi.ball` still load on `/demo/star`
      (existing path; no new route)
- [ ] Close or update `Dreamball-5hs.2` once those notes land; leave
      `Dreamball-5hs.3` blocked only on this change being folded, not on
      a missing `.blend`

Findings (not boxes): repo GLB is already optimized (~1 MB / 18k tris,
webp textures). AvatarModel auto-fit is the scale contract — do not
retune for Star.
