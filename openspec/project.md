# DreamBall — OpenSpec project

DreamBall is an open type system for verifiable, signed, lens-rendered
containers. Zig/Bun/Svelte live in this repo; wire format in
`docs/PROTOCOL.md`; runtime map in `docs/ARCHITECTURE.md`.

This tree records living capabilities and in-flight changes. It does not
replace beads (`bd`) for issue tracking, and it does not replace
`docs/PROTOCOL.md` as wire authority.

Capability ids are kebab-case directory names under `specs/`. Change ids
are verb-led (`add-`, `update-`, `remove-`, `refactor-`).
