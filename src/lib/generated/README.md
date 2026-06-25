# `src/lib/generated/`

Every file in this directory is **generated** by `tools/schema-gen`.
Do not edit by hand — changes will be overwritten by
`bun run codegen` (alias for `zig build schemagen`). Each file carries a
provenance header pinning it to the source schema's blake3 fingerprint.

## What lives here

- `types.ts` — TypeScript interfaces for the root protocol surface.
- `schemas.ts` — Valibot validators (used at publish boundaries, not at
  decode time — see NFR8 note below).
- `cbor.ts` — dCBOR decoder + base58 helpers for consuming `.ball` bytes
  when the lib receives them directly (vs. going through the
  `dreamball-server` HTTP shim, which returns JSON).
- `palace-client.ts` / `palace-mcp-tools.ts` / `palace-capabilities.ts`
  and the `memory-palace.*` files — the per-archiform surfaces generated
  from the Memory Palace archiform schema.

## Why it's generated, not hand-written

These outputs are derived from **canonical JSON Schema**, vendored from
aspects.sh and pinned locally:

- `schemas/root-2.0.0.json` — root DreamBall field shapes.
- `schemas/<archiform>-X.Y.Z.json` — per-archiform extensions
  (e.g. `memory-palace-0.1.0.json`).

`tools/schema-gen/main.zig` is a JSON-Schema **consumer**: it reads the
schema, verifies the pin in `schemas/.pins/`, and dispatches to the
per-target generators (`gen_zig`, `gen_ts`, `gen_valibot`, `gen_cbor`,
`gen_cli`, `gen_ts_client`, `gen_mcp_tools`, `gen_capabilities`). One
schema in, every runtime surface out. Hand-maintaining parallel
TypeScript/Valibot/Zig/CBOR definitions drifts the moment the protocol
ships a new envelope — see the MTG-style type taxonomy in
`docs/VISION.md §10`, which added six types in a single sprint.

This is the JSON-Schema-canonical inversion: the legacy static-text
generator (which hard-coded the schema as Zig constant strings) was
deleted at sprint-002 cutover. See
[`docs/decisions/2026-04-25-json-schema-canonical.md`](../../../docs/decisions/2026-04-25-json-schema-canonical.md)
(D-018) and
[`docs/decisions/2026-04-28-codegen-spike-findings.md`](../../../docs/decisions/2026-04-28-codegen-spike-findings.md).

The split that makes this safe: **JSON Schema owns field shapes**; the
**CBOR encoding algorithm stays canonical in Zig + WASM** with golden
test vectors. Wire-layer semantics JSON Schema can't express natively
(tag-1 epoch-time, the `[alg, value]` signature 2-array, bytes32 vs
variable bytes) ride on `x-cbor` / `x-zig` extension keys that schema
validators ignore but the generators consume.

## Why types.ts uses string literals for `type` discriminants

The CBOR core carries `type: "ball.dreamball.avatar"` (etc.).
Mirroring that as a string-literal type in TypeScript means the
compiler can narrow on `ball.type === 'ball.dreamball.avatar'`
and give you the right attribute surface for that variant. The
short-tag form (`'avatar' | 'agent' | ...`) also appears as
`DreamBallType` for CLI-adjacent UIs.

## Why floats show up in cbor.ts

v1's protocol disallows floats. v2 carves out one exception for
spatial data (omnispherical grids, emotional axes) — see
`docs/PROTOCOL.md §12.2`. The CBOR decoder must handle
IEEE-754 float values (major type 7) so that these envelopes
round-trip.

## NFR8 — validate at publish, not at decode

`cbor.ts` decode paths take the raw CBOR-derived object directly and do
**not** call Valibot. The validators in `schemas.ts` are for publish
boundaries (dreamball-server ingest, mint-time authoring), where input
is untrusted.
