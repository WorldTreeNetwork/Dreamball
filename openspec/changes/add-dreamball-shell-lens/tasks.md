# Tasks

- [ ] Add `shell` to `ALL_LENSES` / `LensName`
- [ ] Add `ShellLens.svelte` that loads `/characters/star-tamagotchi.glb`
      via AvatarModel, with StudioEnvironment, OrbitControls, BloomEffect,
      and the crystal placeholder on missing/failed mesh
- [ ] Dispatch `lens="shell"` from DreamBallViewer (do not fork the
      viewer)
- [ ] Storybook `Lenses/ShellLens` — happy path + placeholder path
- [ ] Route `/demo/shell` showing the orbitable shell
- [ ] Confirm `/demo/star` with `lens="avatar"` is unchanged
- [ ] `bun run check` clean; a Vitest or Storybook browser assertion
      that the shell canvas mounts
- [ ] Run svelte-autofixer on new Svelte until clean
- [ ] Update `Dreamball-5hs.3` when the lens is on screen

Findings (not boxes): mesh bytes already live at
`static/characters/star-tamagotchi.glb`. PENDING
`add-dreamball-shell-mesh` is the naming change; this change may load
that URL without waiting for fold. Type-tinted materials wait for a
later change.
