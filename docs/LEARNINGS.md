# Learnings

- 2026-09-03 tracker hygiene: `Dreamball-m97.2` was still *open* six weeks after ADR 2026-08-06 dissolved it; `Dreamball-y4t` was cited in CLAUDE.md / PROTOCOL / ARCHITECTURE but missing from this beads db; `Dreamball-nvg` (disk-full) had already noted it was superseded by `8k4`. Close dissolved generators, materialize cited epics, and treat a bead's own "close me if X" note as a close trigger.
- 2026-08-19 `add-dreamball-shell-lens`: a source grep for `look.asset` matched the component's own comment; strip comments or phrase the test around `look?.asset` if the contract is "do not read the look slot for the mesh URL."
- 2026-08-19 campaign: this worktree had no `node_modules`; `bun install` succeeded at 99% disk. Playwright still skipped (known hang / disk bead `Dreamball-8k4`).
- 2026-08-21 `add-dreamball-shell-mesh`: `Dreamball-5hs` / `5hs.2` / `5hs.3` are cited in the change but are not in this beads db — naming notes landed with nothing to `bd close`.
