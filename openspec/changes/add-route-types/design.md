# add-route-types — design

Cross-cutting: golden partition + 2026-08-07 routing table.

## Core gate

`fixtures/goldens/manifest.json` is the only file that gates the Rust core.
After this change its entries are:

- `zero_seed`
- `action_v4_unsigned`
- `action_v4_signed`

`memory_connection` is not a core gate. It moves with the archiform set.

## Archiform holding pen

Until `Dreamball-h7s` exists, archiform-manifest.json is the address for
types the ADR (and steer) gave to that tier: existing `archiform` /
`object3d`, plus `memory_connection` and `layout`. Bytes stay pinned; this
is a filing change, not a re-encode.

## Trust observation

Steer 2B overrides the ADR row that listed TrustObservation under
archiform. It is offered to identikey-protocol as identity-layer. It is
not a core golden and not a palace golden. File it as
`fixtures/goldens/identikey-offered-manifest.json` (or equivalent named
holding pen) so contested-manifest.json can go empty or be deleted.

## Generator, not hand JSON

`tools/export-golden-fixtures/main.zig` writes the partition. Move the
`writeEntry` calls; keep `GoldenDrift` against `src/golden.zig`. Do not
edit `bytes_hex` / `blake3` by hand.

## What this does not decide

identikey-protocol may later accept TrustObservation. That is a later
crate membership choice (`y4t.25` is core-only). This change only stops
it from sitting in contested or leaking into the core gate.
