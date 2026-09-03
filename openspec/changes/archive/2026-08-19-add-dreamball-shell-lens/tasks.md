# Tasks

- [x] Add `shell` to `ALL_LENSES` / `LensName`
- [x] Add `ShellLens.svelte` that loads `/characters/star-tamagotchi.glb`
      via AvatarModel, with StudioEnvironment, OrbitControls, BloomEffect,
      and the crystal placeholder on missing/failed mesh
- [x] Dispatch `lens="shell"` from DreamBallViewer (do not fork the
      viewer)
- [x] Storybook `Lenses/ShellLens` — happy path + placeholder path
- [x] Route `/demo/shell` showing the orbitable shell
- [x] Confirm `/demo/star` with `lens="avatar"` is unchanged
- [x] `bun run check` clean; a Vitest or Storybook browser assertion
      that the shell canvas mounts
- [x] Run svelte-autofixer on new Svelte until clean
- [x] Update `Dreamball-5hs.3` when the lens is on screen

Findings (not boxes): mesh bytes already live at
`static/characters/star-tamagotchi.glb`. PENDING
`add-dreamball-shell-mesh` is the naming change; this change may load
that URL without waiting for fold. Type-tinted materials wait for a
later change.
