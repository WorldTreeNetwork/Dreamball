# `src/lib/generated/`

Every file in this directory is **generated** by `tools/schema-gen`.
Do not edit by hand — changes will be overwritten by
`bun run codegen` or `zig build schemagen`.

## What lives here

- `types.ts` — TypeScript interfaces mirroring the Zig protocol
  surface (`src/protocol.zig` + `src/protocol_v2.zig`). These drive
  the renderer library and the showcase app's type-safety story.
- `cbor.ts` — minimal dCBOR decoder + base58 helpers for consuming
  `.jelly` bytes when the lib receives them directly (vs. going
  through the `jelly-server` HTTP shim which returns JSON).

## Why it's generated, not hand-written

The Zig side is the canonical source of truth for the wire format.
Hand-maintaining a parallel TypeScript schema drifts the moment the
protocol ships a new envelope — see the MTG-style type taxonomy
in `docs/VISION.md §10`, which added six types in a single sprint.

The generator is a Zig program so it can (in future) introspect
the actual `src/protocol.zig` structs via comptime reflection.
For this first cut the schema is hard-coded inside
`tools/schema-gen/main.zig` — change it there, re-run `bun run
codegen`, commit the updated outputs.

## Why types.ts uses string literals for `type` discriminants

The CBOR subject carries `type: "jelly.dreamball.avatar"` (etc.).
Mirroring that as a string literal type in TypeScript means the
compiler can narrow on `ball.type === 'jelly.dreamball.avatar'`
and give you the right assertion surface for that variant. The
short-tag form (`'avatar' | 'agent' | ...`) also appears as
`DreamBallType` for CLI-adjacent UIs.

## Why floats show up in cbor.ts

v1's protocol disallows floats. v2 carves out one exception for
spatial data (omnispherical grids, emotional axes) — see
`docs/PROTOCOL.md §12.2`. The CBOR decoder must handle
IEEE-754 float64 values (major type 7, info 27) so that these
envelopes round-trip.
