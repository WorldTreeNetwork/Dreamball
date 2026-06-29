---
id: D1
epic: D
title: Second worked type (ball.object3d) via the Zig-canonical pipeline
status: ready
test_tier: smoke
decisions: [D-040]
frs: [FR1, FR2]
nfrs: [NFR1]
closes_beads: [Dreamball-shr]
stretch: true
---

# D1 — Second worked type (`ball.object3d`) via the Zig-canonical pipeline

## Context

The whole sprint argues that the maintainer authoring path —
**Zig struct → `zig build schemagen` → golden vector** — is a *general*
pipeline, not a one-off carved around `ball.action`. Epics A–C only ever
exercise it on a single type (`Action`/`ball.action` v4). D1 is the STRETCH
that discharges that claim: add **one** new maintainer-authored type the same
way and watch the same machinery (schema `$defs`, generated TS type, generated
Valibot schema, generated `cbor.ts` decoder, a pinned golden vector) light up
with zero new infrastructure. This is exactly the Cluster D demonstration that
[D-040](../architecture-decisions.md) promises:

> **Cluster D (stretch)**: proves the first-class pipeline by adding a second
> Zig-defined type (e.g. `object3d`) through the same codegen path. This is
> maintainer-authored, not consumer-authored.

D1 satisfies **FR1** ("define a consumer data-type in the Zig-canonical
pipeline") and **FR2** ("generate downstream artifacts from the Zig type") for a
*second* type, and proves the generated artifacts actually consume canonical
bytes (the real FR2 payoff, not just "files were emitted"). It is the SMALLEST
credible demonstration — **not** a full second envelope subsystem.

### The chosen type — `ball.object3d`

A minimal 3D-transform record. Justification for this choice over alternatives:

- **Realistic for the first consumer.** World-Tree's stated payloads are "kanban
  ops, 3D transforms" (D-040 rationale §1). A transform type is the obvious
  second maintainer type and reads as a real deliverable, not a toy.
- **Maximises reuse, minimises new surface.** It reuses the existing
  `Quaternion` struct (already has a Zig struct, a `$defs/Quaternion`, and a
  proven encode block in `Placement.facing`) and the `[3]f32` position/scale
  encode pattern lifted verbatim from `encodeLayout`'s placement block
  (`src/envelope_v2.zig:318-338`). The TS float-decode path is *already proven*
  by `decodeLayout` in `src/lib/generated/cbor.ts:257` (it reads `position`/
  `facing` float arrays via `CborReader.readAny()`), so the generated
  `decodeObject3d` is a near-copy with no new primitive work.
- **Simplest possible envelope shape.** All fields live in the **core leaf map**
  with **no attributes and no optionals** — the encoder is
  `[tag-envelope] array(1) [tag-leaf] map(N){…}` with no attribute loop. That is
  strictly simpler than `Layout`/`Action` (which have attribute runs), so it
  exercises the *general* pipeline while being the least code that can.

**Struct shape** (matches the §13.x family: `format_version` + `type_string`
consts, like `Archiform`/`ElementTag`):

```zig
pub const Object3d = struct {
    pub const format_version: u32 = 2;
    /// Wire type string: `"ball.object3d"`.
    pub const type_string: []const u8 = "ball.object3d";

    /// Open-enum mesh/asset identifier (e.g. "glb:tree-01", "primitive:cube").
    mesh: []const u8,
    /// Local-frame translation [x, y, z].
    position: [3]f32,
    /// Orientation (reuses the existing Quaternion type).
    rotation: Quaternion,
    /// Per-axis scale [x, y, z].
    scale: [3]f32,
};
```

Core-map keys in dCBOR length-first order (lex within equal length):
`"mesh"(4) · "type"(4) · "scale"(5) · "position"(8) · "rotation"(8) ·
"format-version"(14)`. Among length-4: `"mesh" < "type"`; among length-8:
`"position" < "rotation"`. `position`/`scale` are 3-element arrays of
`writeSmallestFloat`; `rotation` is the 4-element quaternion array exactly as
`Placement.facing` emits it. Use `assertCanonicalAllowFloats` on the decode/golden
side (floats), matching `decodeLayout`.

## Scope (the key judgment)

### IN scope (the smallest credible FR1/FR2 generalization proof)

1. **Zig struct** `Object3d` in `src/protocol_v2.zig` (+ a `"struct shape:
   Object3d"` unit test matching the existing struct-shape tests). — *FR1.*
2. **`encodeObject3d`** in `src/envelope_v2.zig` (core-map-only encoder; mirrors
   `encodeLayout`'s placement float block + `Quaternion` encode). Needed to
   produce the golden bytes.
3. **Schema `$defs/Object3d`** in `schemas/root-2.0.0.json` (referencing the
   existing `$defs/Quaternion` for `rotation`) **+ recomputed
   `schemas/.pins/root-2.0.0.fp`**. The `root-schema-coverage` test mechanically
   *forces* this: any `pub const Object3d = struct` requires a matching `$defs`
   entry and every kebab-cased field name present in the schema. — *FR2.*
4. **`gen_ts.zig` + `gen_valibot.zig`** hardcoded bodies emit the `Object3d` TS
   interface and `Object3dSchema`; then `zig build schemagen` regenerates
   `src/lib/generated/{types,schemas}.ts`. — *FR2.*
5. **Golden vector** in `src/golden.zig`: `GOLDEN_OBJECT3D_BYTES_HEX` (canonical
   bytes) + `GOLDEN_OBJECT3D_BLAKE3`, with a test that **reuses C1's
   `expectHexEql` + the existing `goldenCheck` helpers** (no new harness).
6. **Cross-runtime byte check (the FR2 payoff).** `gen_cbor.zig` emits a hardcoded
   `decodeObject3d`; `zig build schemagen` regenerates `src/lib/generated/cbor.ts`.
   A Vitest (`src/lib/object3d-codegen.test.ts`) reads a TS fixture mirroring the
   Zig golden bytes hex, decodes via the **generated** `decodeObject3d`, and
   validates via the **generated** `Object3dSchema`, asserting the decoded values
   equal the fixture. This proves the generated TS artifacts actually consume the
   canonical Zig-encoded bytes — reusing **C2's codegen path** and **C1's
   golden-fixture mirroring discipline**.

### Explicitly DEFERRED (out of scope for this stretch)

- **No WASM export** (`authorObject3d`) and **no WASM round-trip**. The
  cross-runtime proof (#6) runs the *generated `cbor.ts`* over Zig-encoded
  canonical bytes — it does not link a new encode/decode path into
  `dreamball.wasm`. Adding a WASM export is the only thing here that could touch
  the binary's size budget; it is deliberately omitted.
- **No Zig `decodeObject3d` / Zig round-trip test.** FR1/FR2 are proven by
  Zig-encode → golden → TS-decode+validate. A Zig decoder is a trivial later
  copy of `decodeLayout` but is not needed to prove generalization; leave it for
  a follow-on.
- **No `content_hash` for `object3d`.** `content_hash` is an `Action`/op-log
  concept (D-043); a transform record is not an op.
- **No other projections.** `gen_cli`, `gen_mcp_tools`, `gen_ts_client`,
  `gen_capabilities`, and the Cypher/graphstore schema are NOT extended for
  `object3d`. (If the schemagen orchestrator's per-type passes error on an
  unknown type, scope the `Object3d` $defs so those passes skip it — it carries
  no `x-actions`, so the archiform/MCP/client passes ignore it by construction.)
- **No CLI subcommand** for authoring/printing `object3d`.
- **No consumer-authored path** (FR13 Growth) — D-040 keeps first-class types
  maintainer-only.

### WASM size note

The committed `src/lib/wasm/dreamball.wasm` need not be rebuilt for D1.
`encodeObject3d` is referenced only by Zig tests/golden, never by a WASM export,
so ReleaseSmall dead-code elimination drops it from the binary. If the binary is
rebuilt incidentally, confirm its size is unchanged and restore the pinned
artifact to HEAD (same discipline C2 used). The budget is generous post-C3
(soft 300 KB raw / 150 KB gz) and D1 links no new decode paths regardless.

## Acceptance Criteria

1. `src/protocol_v2.zig` defines `pub const Object3d = struct { … }` with
   `format_version = 2`, `type_string = "ball.object3d"`, and fields
   `mesh`, `position`, `rotation` (`Quaternion`), `scale`. A
   `"struct shape: Object3d"` test asserts the consts and field defaults.
2. `src/envelope_v2.zig` `encodeObject3d` emits a canonical dCBOR envelope:
   single-element outer array, one leaf core map with the six keys in
   length-first canonical order, `position`/`scale` as 3× `writeSmallestFloat`,
   `rotation` as the 4-element quaternion array. No attributes.
3. `schemas/root-2.0.0.json` gains `$defs/Object3d` (`x-wire-type:
   ball.object3d`, `x-format-version: 2`, `required: ["mesh","position",
   "rotation","scale"]`, `rotation` via `$ref: #/$defs/Quaternion`), and
   `schemas/.pins/root-2.0.0.fp` is updated to its new blake3.
4. `tests/codegen/root-schema-coverage.test.ts` is green: `Object3d` has a
   `$defs` entry and every field's wire name (`mesh`, `position`, `rotation`,
   `scale`) is present; metaschema validity holds. **No `x-cbor`/`x-zig` keys on
   the new `Object3d` properties** (Zig is canonical, schema is an output — same
   rule C2 followed for the new `Action` properties; AC6 there).
5. `zig build schemagen` regenerates `src/lib/generated/{types,schemas,cbor}.ts`
   containing an `Object3d` interface, an `Object3dSchema` (Valibot), and a
   `decodeObject3d`. Re-running schemagen is idempotent (no diff).
6. `src/golden.zig` pins `GOLDEN_OBJECT3D_BYTES_HEX` and `GOLDEN_OBJECT3D_BLAKE3`
   for one fixed `Object3d` value; a Zig test asserts the encoder reproduces both
   (reusing `expectHexEql` + `goldenCheck`).
7. A Vitest (`src/lib/object3d-codegen.test.ts`) decodes the golden bytes via the
   generated `decodeObject3d` and validates the result with `Object3dSchema`,
   asserting the decoded `mesh`/`position`/`rotation`/`scale` equal the fixture
   (`src/lib/__fixtures__/object3d.golden.json`, a hex mirror of
   `GOLDEN_OBJECT3D_BYTES_HEX`). Zig and TS golden copies must agree.
8. All existing gates stay green; no existing golden vector, type, or schema
   `$defs` entry is modified (Object3d is purely additive).

## Task Breakdown

1. **Zig struct (T1).** Add `Object3d` to `src/protocol_v2.zig` near the other
   §13.x types; add the `"struct shape: Object3d"` test.
2. **Encoder (T2).** Add `encodeObject3d` to `src/envelope_v2.zig`. Copy the
   float blocks from `encodeLayout` (position/scale = `position` block;
   `rotation` = `facing` block). Verify key ordering by length-first/lex.
3. **Golden (T3).** Run the encoder for a fixed value (e.g.
   `mesh = "glb:tree-01"`, `position = .{1.0, 2.0, 3.0}`,
   `rotation = .{ .qx=0, .qy=0, .qz=0, .qw=1 }`, `scale = .{1.0, 1.0, 1.0}`),
   capture the bytes hex + blake3 from the first-run `GoldenRecompute` print,
   pin them in `src/golden.zig`, and add the golden test.
4. **Schema + pin (T4).** Add `$defs/Object3d` to `schemas/root-2.0.0.json`
   (template off `$defs/Archiform` for the wrapper keys and `$defs/Placement`
   for the float-array shape; `rotation` → `$ref: #/$defs/Quaternion`).
   Recompute `schemas/.pins/root-2.0.0.fp` (capture from the schemagen
   pin-verify mismatch log if no local blake3 hasher, as C2 did).
5. **Generators (T5).** Add hardcoded `Object3d` interface to `gen_ts.zig`,
   `Object3dSchema` to `gen_valibot.zig`, `decodeObject3d` to `gen_cbor.zig`
   (model on the `Layout`/`decodeLayout` blocks). Run `zig build schemagen`;
   confirm the three generated files contain the new symbols and regen is
   idempotent.
6. **TS fixture + Vitest (T6).** Write `src/lib/__fixtures__/object3d.golden.json`
   (mirror `GOLDEN_OBJECT3D_BYTES_HEX` + the logical field values) and
   `src/lib/object3d-codegen.test.ts` (decode → validate → assert shape).

## Test Plan

- `zig build test` — `"struct shape: Object3d"` + the Object3d golden test green;
  no existing golden disturbed.
- `bun run test:unit -- --run tests/codegen/root-schema-coverage.test.ts` —
  green (Object3d `$defs` + field coverage + metaschema validity).
- `bun run test:unit -- --run src/lib/object3d-codegen.test.ts` — decode +
  validate green.
- `zig build schemagen` — exits 0 (pin verified), regen idempotent.
- `bun run check` — 0 errors.
- Regression: `zig build smoke`, `scripts/cli-smoke.sh`, `scripts/server-smoke.sh`,
  `tests/e2e-cryptography.sh` (mock) all still green. (D1 adds an isolated new
  type with no CLI/server/WASM surface, so these cannot plausibly regress, but
  per CLAUDE.md they are run before D1 is marked done.)

**test_tier: smoke** — justification: D1 is additive and stretch. It introduces
no CLI verb, no server route, and no WASM export, so the heavy integration gates
exercise nothing new; they run only as regression. The load-bearing checks are
narrow and targeted (the Zig golden, the codegen-coverage test, and the one TS
decode/validate Vitest), all reusing C1's golden harness and C2's codegen path.

## Files

| File | Change |
|------|--------|
| `src/protocol_v2.zig` | Add `Object3d` struct + struct-shape test (T1) |
| `src/envelope_v2.zig` | Add `encodeObject3d` (T2) |
| `src/golden.zig` | Add `GOLDEN_OBJECT3D_*` consts + golden test (T3) |
| `schemas/root-2.0.0.json` | Add `$defs/Object3d` (T4) |
| `schemas/.pins/root-2.0.0.fp` | Recompute blake3 pin (T4) |
| `tools/schema-gen/gen_ts.zig` | Hardcoded `Object3d` interface (T5) |
| `tools/schema-gen/gen_valibot.zig` | Hardcoded `Object3dSchema` (T5) |
| `tools/schema-gen/gen_cbor.zig` | Hardcoded `decodeObject3d` (T5) |
| `src/lib/generated/types.ts` | Regenerated by schemagen (T5) |
| `src/lib/generated/schemas.ts` | Regenerated by schemagen (T5) |
| `src/lib/generated/cbor.ts` | Regenerated by schemagen (T5) |
| `src/lib/__fixtures__/object3d.golden.json` | TS golden mirror (T6) |
| `src/lib/object3d-codegen.test.ts` | Decode + validate Vitest (T6) |

## Do NOT touch

- `src/lib/wasm/dreamball.wasm` — not rebuilt for D1; restore to HEAD if a build
  touches it.
- The `Action`/`ball.action` pipeline, any existing `$defs`, any existing golden
  vector — D1 is purely additive.
- `gen_cli.zig`, `gen_mcp_tools.zig`, `gen_ts_client.zig`, `gen_capabilities.zig`,
  `tools/graphstore-schema/gen_cypher.zig` — no `object3d` projection (deferred).

## Dependencies

- **C2** (Dreamball-wky, done) — proved the schemagen hand-propagation sequence
  (edit generator bodies → `zig build schemagen` → edit schema + pin → coverage
  green) that D1 repeats for a second type.
- **C1** (Dreamball, done) — supplies the reusable golden harness
  (`expectHexEql`, `goldenCheck`) and the Zig↔TS golden-mirror discipline D1's
  cross-runtime check copies.

Closes bead **Dreamball-shr**.

## Dev Agent Record

### Status
Done (implementation + all smoke-tier gates green). Bead NOT closed, no commit (per dispatch).

### Completion notes

Purely additive second maintainer-authored type `ball.object3d` through the
Zig-canonical pipeline — zero new infrastructure, every artifact reuses the
existing `Action`/`Layout` machinery.

- **Struct (T1).** `Object3d` added at `src/protocol_v2.zig` §13.10 (after
  Archiform), reusing the existing `Quaternion` for `rotation`. `format_version
  = 2`, `type_string = "ball.object3d"`. `"struct shape: Object3d"` test mirrors
  the existing struct-shape tests.
- **Encoder (T2).** `encodeObject3d` at `src/envelope_v2.zig` §13.10 — core-map
  only, single-element outer array, no attribute loop. Float blocks copied
  verbatim from `encodeLayout`'s placement block (`writeSmallestFloat` ×3 for
  position/scale, 4-elem quaternion array for rotation). Canonical key order
  (len asc, lex): `mesh(4) · type(4) · scale(5) · position(8) · rotation(8) ·
  format-version(14)`.
- **Golden (T3).** `GOLDEN_OBJECT3D_BYTES_HEX` + `GOLDEN_OBJECT3D_BLAKE3` pinned
  in `src/golden.zig`; test reuses C1's `expectHexEql` + `goldenCheck` + `blake3Hex`.
- **Schema (T4).** `$defs/Object3d` in `schemas/root-2.0.0.json` (templated off
  Archiform wrapper keys + Placement float-array shape; `rotation` → `$ref
  #/$defs/Quaternion`). NO `x-cbor`/`x-zig` on the new properties (Zig canonical;
  same rule C2 followed). Pin `schemas/.pins/root-2.0.0.fp` recomputed from the
  schemagen pin-verify mismatch log.
- **Generators (T5).** Hardcoded bodies added to `gen_ts.zig` (`Object3d`
  interface), `gen_valibot.zig` (`Object3dSchema`), `gen_cbor.zig`
  (`decodeObject3d`, core-map-only, + `Object3d` added to the `import type`
  list). `zig build schemagen` regenerated `types.ts` / `schemas.ts` /
  `cbor.ts`; regen is idempotent (verified: second run produced no diff).
- **Cross-runtime check (T6).** `src/lib/__fixtures__/object3d.golden.json`
  mirrors the Zig golden bytes + logical values; `src/lib/object3d-codegen.test.ts`
  decodes via generated `decodeObject3d`, validates via generated `Object3dSchema`,
  asserts decoded mesh/position/rotation/scale equal the fixture — proving the
  generated TS artifacts consume the canonical Zig bytes (the real FR2 payoff).

### Pinned golden values

- `GOLDEN_OBJECT3D_BYTES_HEX` =
  `d8c881d8c9a6646d6573686b676c623a747265652d303164747970656d62616c6c2e6f626a6563743364657363616c6583f93c00f93c00f93c0068706f736974696f6e83f93c00f94000f9420068726f746174696f6e84f90000f90000f90000f93c006e666f726d61742d76657273696f6e02`
- `GOLDEN_OBJECT3D_BLAKE3` =
  `eec27f4c4e8cb4306e7ab74290fe37b8ad891bb2716f1e02d3bb703a9039feba`
- Recomputed schema pin `schemas/.pins/root-2.0.0.fp` =
  `ec3e2f02159c5ff7a0426c2a1db96741f00336af0d34f7d778a950e8704b35b4`
  (was `ebd8553cd13da1928fc196e746834671b2bd76e4773164eaaa31dfe8509295b3`)

### Gate results

- `zig build` — exit 0.
- `zig build schemagen` then re-run — exit 0; idempotent (second run no diff);
  generated `types.ts`/`schemas.ts`/`cbor.ts` contain `Object3d` /
  `Object3dSchema` / `decodeObject3d`.
- `zig build test --summary all` — **224/224 passed** (was 222; +2:
  `"struct shape: Object3d"` and `"D1 golden: ball.object3d …"`).
- `zig build smoke` — exit 0, all smoke checks passed.
- `bun run test:unit -- --run tests/codegen/root-schema-coverage.test.ts
  src/lib/object3d-codegen.test.ts` — 2 files, 43 tests passed (coverage stays
  green WITH the new `Object3d` $defs; new cross-runtime test passes).
- `bun run check` — 0 errors (1 pre-existing unrelated a11y warning in
  BallroomEasterEgg.svelte).

### Additive / WASM confirmation

- Purely additive: `git diff` shows no `-` lines in `src/golden.zig`,
  `schemas/root-2.0.0.json`, `src/protocol_v2.zig`, `src/envelope_v2.zig`. The
  only generated `-` lines are the provenance `source-schema-fp` header (fp
  changed) and the `import type` line that gained `, Object3d`. No existing
  golden vector, type, or `$defs` entry modified.
- `src/lib/wasm/dreamball.wasm` unchanged (no git diff). `encodeObject3d` is
  referenced only by Zig tests/golden, never a WASM export, so ReleaseSmall DCE
  keeps it out of the binary — no rebuild needed.

### Blocker Type
None.

### Blocker Detail
None.

### File List

- `src/protocol_v2.zig` (Object3d struct + struct-shape test)
- `src/envelope_v2.zig` (encodeObject3d)
- `src/golden.zig` (GOLDEN_OBJECT3D_* consts + golden test)
- `schemas/root-2.0.0.json` ($defs/Object3d)
- `schemas/.pins/root-2.0.0.fp` (recomputed pin)
- `tools/schema-gen/gen_ts.zig` (Object3d interface)
- `tools/schema-gen/gen_valibot.zig` (Object3dSchema)
- `tools/schema-gen/gen_cbor.zig` (decodeObject3d + import)
- `src/lib/generated/types.ts` (regenerated)
- `src/lib/generated/schemas.ts` (regenerated)
- `src/lib/generated/cbor.ts` (regenerated)
- `src/lib/generated/cbor.test.ts` (regenerated — fp header only)
- `src/lib/__fixtures__/object3d.golden.json` (TS golden mirror)
- `src/lib/object3d-codegen.test.ts` (cross-runtime Vitest)
