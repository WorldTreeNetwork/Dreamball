---
id: C2
epic: C
title: Regenerate downstream targets from Zig type (schemagen)
status: ready
test_tier: thorough
decisions: [D-037, D-038, D-039, D-043]
frs: [FR3, FR5]
closes_beads: [Dreamball-wky]
---

# C2 — Regenerate downstream targets from Zig type (schemagen)

## Context

The canonical `src/protocol_v2.zig Action` struct (landed in A1) carries four v4
fields that do not yet appear in any downstream target:

| Zig field        | Wire key        | v3 state in targets                     |
|------------------|-----------------|------------------------------------------|
| `kind: []const u8` | `kind`         | absent; schema has closed `action-kind` |
| `hlc: [2]u64`    | `hlc`           | absent entirely                          |
| `body: ?[]const u8` | `body`       | absent                                   |
| `format_version` | `format-version`| schema/TS/Valibot still say `3`          |

The `root-schema-coverage` test (AC1, `tests/codegen/root-schema-coverage.test.ts`)
is currently failing with:

```
schemas/root-2.0.0.json is missing root field(s): Action.hlc (wire: hlc)
```

(`hlc` is the unique failure because `body` and `kind` happen to appear as property
names elsewhere in the schema; but all three are wrong in the `Action` def itself,
and types.ts / schemas.ts / cbor.ts are uniformly v3.)

**Transitional-status note (CLAUDE.md §cross-runtime-invariant).** The real
comptime generator (`m97.2`) is not built. Today every generator in
`tools/schema-gen/` emits a **hardcoded string body**. The generated files in
`src/lib/generated/` are what those hardcoded bodies produce. The correct
hand-propagation sequence is therefore:

1. Edit the hardcoded bodies in the generator `.zig` files (so `zig build schemagen`
   produces correct output).
2. Run `zig build schemagen`, which overwrites `src/lib/generated/*.ts` with the
   corrected bodies.
3. Edit `schemas/root-2.0.0.json` (the schema fixture) and update the blake3 pin.
4. Run the codegen and coverage tests until green.

Do **not** hand-edit `src/lib/generated/*.ts` independently of the generator
sources — running `zig build schemagen` will overwrite them.

## Acceptance Criteria

1. `tests/codegen/root-schema-coverage.test.ts` passes with zero failures:
   every field of every Zig struct in `protocol.zig` + `protocol_v2.zig` has a
   corresponding wire-name property somewhere in `schemas/root-2.0.0.json`.
2. The `Action` `$defs` entry in `schemas/root-2.0.0.json` reflects v4:
   - `x-format-version: 4`
   - Property `kind` present (open text string, not `$ref: ActionKind`)
   - Property `hlc` present (2-element uint array, required)
   - Property `body` present (optional byte string)
   - `required` list: `["kind", "hlc", "parent-hashes", "actor"]`
   - `action-kind` property removed (v3 closed-enum gone)
3. `src/lib/generated/types.ts` `Action` interface updated to v4:
   - `'format-version': 4`
   - `kind: string` (open, was `'action-kind': ActionKind`)
   - `hlc: [number, number]` (required)
   - `body?: string` (Base58-tagged byte string, optional)
4. `src/lib/generated/schemas.ts` `ActionSchema` updated to v4:
   - `'format-version': v.literal(4)`
   - `kind: v.string()` (was `'action-kind': ActionKindSchema`)
   - `hlc: v.tuple([v.number(), v.number()])` (required)
   - `body: v.optional(v.string())`
5. `src/lib/generated/cbor.ts` `decodeAction` updated with a v4 branch:
   - Reads `kind` (text string) and `hlc` ([uint, uint] array) from the v4 core map
   - Reads optional `body` from attributes as a byte string → Base58-tagged string
   - Emits the correct `Action` shape; byte-equivalent to what `encodeActionV4` produces
   - v3 decode path (reading `action-kind`) preserved for backward compat
6. No `x-cbor` / `x-zig` extension keys added on net-new properties in
   `schemas/root-2.0.0.json` (schema is now an output, not an authoring surface;
   the retired JSON-Schema-canonical authoring path — D-018, superseded — used those
   keys as the canonical source; see ADR `2026-06-25-zig-canonical-supersedes-json-schema.md`).
7. `schemas/.pins/root-2.0.0.fp` updated to the blake3 of the edited
   `schemas/root-2.0.0.json`.

## Task Breakdown

### T1 — Edit `schemas/root-2.0.0.json`

Locate `$defs/Action` (currently around line 868 of the file).

**Remove** the `action-kind` property and its `$ref: ActionKind`.

**Add** the following three properties, matching the style of adjacent fields:

```jsonc
"kind": {
  "$comment": "Open kind string (D-037/D-038). Replaces the closed action-kind enum of v3. Palace authors use ActionKind.toWireString(); other consumers supply dot-namespaced verbs.",
  "type": "string"
},
"hlc": {
  "$comment": "Hybrid Logical Clock [l, c] (D-039). l = ms wall-clock, c = intra-l counter. Bare 2-element uint array in CBOR (no tag).",
  "type": "array",
  "minItems": 2,
  "maxItems": 2,
  "items": { "type": "integer", "minimum": 0 }
},
"body": {
  "$comment": "Opaque consumer CBOR payload (CBOR-in-CBOR, D-043). Absent when the action carries no payload.",
  "type": ["string", "null"],
  "x-optional": true
},
```

**Update** the `required` array: replace `["action-kind", "parent-hashes", "actor"]` with
`["kind", "hlc", "parent-hashes", "actor"]`.

**Update** `x-format-version: 3` → `x-format-version: 4`.

**Update** the `$comment` on `$defs/ActionKind` to read:
> "Convenience palette for palace authors (D-038). NOT the v4 wire type — Action.kind is an open string from v4 onward. This entry is kept as a documentation aid for palace-profile consumers."

Note on `x-` extension keys: the existing entries in root-2.0.0.json carry `x-cbor`,
`x-zig`, `x-zig-type` etc. as generator hints left over from the D-018 authoring
path. For the three new properties above, do not add these keys — Zig is now
canonical and the schema is an output. The x-optional key is kept for new optional
fields only because the generator reads it to decide whether to emit `v.optional(…)`.

### T2 — Update the blake3 pin

After editing `schemas/root-2.0.0.json`, compute the new blake3 digest and write
it to `schemas/.pins/root-2.0.0.fp`. The schemagen orchestrator verifies this pin
at the start of `zig build schemagen` and aborts if it doesn't match.

```bash
# Example using the b3sum tool; any blake3 hasher is fine
b3sum schemas/root-2.0.0.json --no-names > schemas/.pins/root-2.0.0.fp
```

### T3 — Update `tools/schema-gen/gen_ts.zig`

Find the hardcoded `Action` interface block (search for `ball.action` or
`action-kind` in this file; currently around line 479). Replace it:

```typescript
/** §13.3 ball.action — a single DAG node in a palace timeline. */
export interface Action {
  type: 'ball.action';
  'format-version': 4;
  /** Open kind string (D-037). Palace verbs via ActionKind; other consumers use dot-namespaced strings. */
  kind: string;
  actor: Bytes32;
  'parent-hashes': Bytes32[];
  /** Hybrid Logical Clock [l, c] (D-039): l = ms wall-clock, c = intra-l counter. */
  hlc: [number, number];
  /** Opaque consumer CBOR payload, Base58-tagged (CBOR-in-CBOR, D-043). */
  body?: string;
  'target-fp'?: Bytes32;
  timestamp?: number;
  deps?: Bytes32[];
  nacks?: Bytes32[];
}
```

Also update the `ActionKind` type comment to note it is a palace-profile
convenience, no longer the wire field on `Action`:

```typescript
/**
 * Palace-profile kind palette — convenience constants for the 9 known
 * palace verbs. From v4 onward the `Action.kind` wire field is an open
 * string; this union is a documentation aid, not an exhaustive type.
 */
export type ActionKind = ...;
```

### T4 — Update `tools/schema-gen/gen_valibot.zig`

Find the hardcoded `ActionSchema` block (currently around line 498). Replace it:

```typescript
export const ActionSchema = v.object({
  type: v.literal('ball.action'),
  'format-version': v.literal(4),
  kind: v.string(),
  actor: Base58Schema,
  'parent-hashes': v.array(Base58Schema),
  hlc: v.tuple([v.number(), v.number()]),
  body: v.optional(v.string()),
  'target-fp': v.optional(Base58Schema),
  timestamp: v.optional(v.number()),
  deps: v.optional(v.array(Base58Schema)),
  nacks: v.optional(v.array(Base58Schema))
});
```

`ActionKindSchema` stays in place (it remains useful for palace-specific validation
at higher layers); no change needed to its definition, only its comment if desired.

### T5 — Update `tools/schema-gen/gen_cbor.zig`

Find the hardcoded `decodeAction` function (currently around line 316). The existing
body reads `action-kind` from the core map and returns a v3 `Action`. Replace with a
version that branches on `format-version`:

**Core map reads for v4 (7-key map; 6-key when body absent):**
- `kind` — text string
- `hlc` — 2-element array; each element a CBOR uint read via `readAny()`
- `body` — (absent from core map; appears as an attribute byte string)
- `parent-hashes` — array of byte strings (same as v3)
- `actor` — byte string (same as v3)
- `type` — text string (same as v3)
- `format-version` — uint (read to branch)

**v3 backward-compat path:** if `format-version` is `3`, read `action-kind` from the
core map (closed palette) and return an `Action` with `'action-kind'` set — or, since
the `Action` TS type no longer has that field, return an `unknown`-typed object and
let the caller handle it. The cleanest approach: keep the existing v3 code as the
else-branch of a `formatVersion === 4` check.

**Byte-equivalence invariant:** the v4 decode path must round-trip with
`encodeActionV4` in Zig. Specifically:
- `hlc[0]` and `hlc[1]` are bare unsigned integers (no tag). The existing
  `CborReader.readAny()` returns them as `number` (or `bigint` for large u64). Cast
  to `number` before storing; note that `l` may be ~1.7 × 10¹² (ms epoch), which
  fits safely in a JS double.
- `body` is an attribute pair (`["body", <byte-string>]`) emitted after the core map
  by `encodeActionV4Signed`. Decode it via the existing attribute-scanning loop
  (same pattern as `decodeLayout`, `decodeMythos`, etc.), then Base58-tag the bytes.
- The `kind` attribute is in the core map, not an attribute pair. Read it in the
  core-map loop alongside `parent-hashes` and `actor`.

**Emit shape for v4:**
```typescript
const out: Action = {
  type: 'ball.action', 'format-version': 4,
  kind, actor, 'parent-hashes': parentHashes, hlc: [hlcL, hlcC]
};
if (body !== undefined) out.body = body;
if (targetFp !== undefined) out['target-fp'] = targetFp;
// ... timestamp, deps, nacks as before
return out;
```

### T6 — Run `zig build schemagen`

```bash
zig build schemagen
```

This reads the updated `schemas/root-2.0.0.json`, verifies the updated pin, and
re-emits `src/lib/generated/types.ts`, `schemas.ts`, and `cbor.ts` from the
updated hardcoded bodies. Verify the three files now contain the v4 shape.

### T7 — Run codegen coverage test

```bash
bun run test:unit -- --run tests/codegen/root-schema-coverage.test.ts
```

All sub-tests under `root schema coverage (AC1 + AC5)` and
`root schema metaschema validity (AC3)` must be green. Iterate on T1–T6
until they are.

## Files

| File | Change |
|------|--------|
| `schemas/root-2.0.0.json` | Update `$defs/Action` to v4 shape (T1) |
| `schemas/.pins/root-2.0.0.fp` | Recompute blake3 after JSON edit (T2) |
| `tools/schema-gen/gen_ts.zig` | Update hardcoded `Action` interface + comment (T3) |
| `tools/schema-gen/gen_valibot.zig` | Update hardcoded `ActionSchema` (T4) |
| `tools/schema-gen/gen_cbor.zig` | Update hardcoded `decodeAction` with v4 branch (T5) |
| `src/lib/generated/types.ts` | Regenerated by `zig build schemagen` (T6) |
| `src/lib/generated/schemas.ts` | Regenerated by `zig build schemagen` (T6) |
| `src/lib/generated/cbor.ts` | Regenerated by `zig build schemagen` (T6) |

## Do NOT Touch

- **`src/lib/wasm/__fixtures__/action-v4.golden.json`** — intentionally outside
  `src/lib/generated/`; it is a static WASM test fixture, not a codegen output.
- **`src/envelope_v2.zig`** — `encodeActionV4` and `decodeAction` are already correct
  (A2 story). C2 is purely downstream propagation.
- **`src/protocol_v2.zig`** — canonical Zig source (A1). Do not touch.
- **`tools/graphstore-schema/gen_cypher.zig`** — the `ActionLog` Cypher node uses
  `action_kind STRING` as a graph-layer convention. Aligning the graph schema with
  the v4 open kind is a separate concern; leave it for a follow-on story and note
  the divergence in `docs/known-gaps.md`.

## contentHash note (from C1 handoff)

`contentHash` (in `src/envelope_v2.zig`) is a hand-written helper that hashes
`encodeActionV4` bytes. It is not a generated artifact and is not touched by C2.
The comptime reflection generator (`m97.2`) will own generated hash helpers when
it ships; until then `contentHash` stays as-is.

## Test Plan

- `bun run test:unit -- --run tests/codegen/root-schema-coverage.test.ts` → all
  `Zig struct Action: every field appears in schemas/root-2.0.0.json` assertions
  pass; `every struct is represented as a $defs type` passes; metaschema validity
  passes.
- `bun run check` (svelte-check) → 0 errors (the `Action` type is imported
  transitively; verify no type breakage in downstream consumers).
- `zig build schemagen` exits 0 (pin verified, all files written).
- `zig build test` + `zig build smoke` green (Zig side unchanged, just regression
  confirmation).

The full integration gates (`scripts/cli-smoke.sh`, `scripts/server-smoke.sh`,
`tests/e2e-cryptography.sh`) must remain green — run them before marking C2 done.

## Dependencies

A1 (struct shape), A2 (encodeActionV4), C1 (contentHash context).
Blocks: any TS consumer of `Action` that needs the v4 type surface (e.g.,
`authorAction` WASM bridge in B1, the v4 verification path in B2).

## Dev Agent Record

### Status
Done — all acceptance criteria met, all gates green.

### Completion Notes

**Generators edited (hand-propagation per CLAUDE.md transitional status; the
real comptime generator `m97.2` is not built yet):**
- `tools/schema-gen/gen_ts.zig` — `Action` interface → v4 (`'format-version': 4`,
  `kind: string`, `hlc: [number, number]`, `body?: string`; dropped
  `'action-kind': ActionKind`). Added the palace-profile docstring on
  `ActionKind` noting it is no longer the wire type.
- `tools/schema-gen/gen_valibot.zig` — `ActionSchema` → v4 (`v.literal(4)`,
  `kind: v.string()`, `hlc: v.tuple([v.number(), v.number()])`,
  `body: v.optional(v.string())`). `ActionKindSchema` retained (palace-layer use).
- `tools/schema-gen/gen_cbor.zig` — `decodeAction` now branches on the core
  map's `format-version`: v4 reads `kind`, `hlc`, and `body` **from the core
  leaf map** (see byte-equivalence note below); v3 backward-compat path reads
  `action-kind` and is cast through `unknown` since the v4 `Action` type no
  longer carries that field.
- `zig build schemagen` then regenerated `src/lib/generated/{types,schemas,cbor,cbor.test}.ts`.
  Regen is idempotent (re-running produces no further diff).

**Schema fixture (T1/T2):**
- `schemas/root-2.0.0.json` `$defs/Action` → v4: added `kind` (open text),
  `hlc` (2-element uint array, required), `body` (optional `["string","null"]`
  with `x-optional`); removed `action-kind`; `required` →
  `["kind","hlc","parent-hashes","actor"]`; `x-format-version` 3→4. Updated the
  `$defs/ActionKind` `$comment` to mark it a palace-profile documentation aid.
  No `x-cbor`/`x-zig` keys added on the three new properties (AC6).
- `schemas/.pins/root-2.0.0.fp` recomputed to the blake3 the schemagen
  orchestrator reports for the edited JSON:
  `ebd8553cd13da1928fc196e746834671b2bd76e4773164eaaa31dfe8509295b3`
  (b3sum unavailable locally; captured from the pin-verify mismatch log, which
  prints the actual digest, then re-verified clean).

**Byte-equivalence verification (AC5) — important correction to the spec prose.**
T5 of this spec describes `body` as a trailing *attribute* pair. The canonical
Zig encoder (`src/envelope_v2.zig encodeActionV4Signed`, lines ~678-707) and the
C1 golden (`action-v4.golden.json unsignedBytesHex`) both place `body`, `kind`,
and `hlc` **inside the core leaf map** (6-key map, or 7-key when `body` is
present) — only `deps`/`nacks`/`signed`/`target-fp`/`timestamp` are attributes.
Per CLAUDE.md the Zig encoder + golden are canonical, so `decodeAction` reads
those three fields from `core`, not `attrs`. Confirmed by regenerating the
round-trip fixture: `fixtures/envelope_golden/action.cbor` is now
`d8c8 81 d8c9 a7 | hlc[1700000000000,7] | body 0x820102 | kind "worldtree.kanban-card.move" | type | actor | parent-hashes | format-version 04` —
byte-structurally identical to the golden's `unsignedBytesHex`. `hlc[0]`
(~1.7e12 ms) is read via `readAny()` as a bigint and coerced to `number`.

**Downstream consumer reconciliation (out of the generators, required for green
gates):**
- `tools/export-envelope-fixtures/main.zig` — the `action.cbor` round-trip
  fixture used the v3 `encodeAction`; switched it to `encodeActionV4` with a
  representative `kind`/`hlc`/`body` so the round-trip test exercises the v4
  wire path and validates against the v4 `ActionSchema`. (`encodeActionV4`
  already existed from A2; the canonical encoder was not modified.)
- `src/lib/palace-round-trip.test.ts` — updated the "decodes and validates
  ball.action" assertions to v4 (`format-version` 4, `kind`, `hlc`, `body`),
  and replaced the now-stale "rejects unknown action-kind" negative test with a
  meaningful v4 one (rejects an action missing the mandatory `hlc`).

### Blocker Type
None.

### Blocker Detail
N/A.

### Gate Results (test_tier: thorough)
- `zig build` → exit 0.
- `zig build schemagen` then `zig build` → clean, regen idempotent (no diff on re-run).
- `zig build test --summary all` → 217/217 tests passed.
- `bun run test:unit -- --run` → 737/737 tests passed, 0 failed. (One Errors=1
  entry is the pre-existing Playwright browser-mode project failing to launch
  because the chromium binary is not installed locally — environmental, present
  before this story, unrelated to C2.)
  - `tests/codegen/root-schema-coverage.test.ts` → 40/40 PASS (was failing:
    "root-2.0.0.json is missing root field(s): Action.hlc (wire: hlc)").
  - `src/lib/generated/cbor.test.ts` → pass; `src/lib/palace-round-trip.test.ts`
    → 18/18 pass.
- `bun run check` (svelte-check) → 0 errors (1 pre-existing a11y warning in
  `BallroomEasterEgg.svelte`, unrelated).
- `zig build smoke` → all smoke checks passed.
- `scripts/cli-smoke.sh` → exit 0; `scripts/server-smoke.sh` → 34 PASS / 0 FAIL;
  `tests/e2e-cryptography.sh` (mock mode) → all checks passed.

Note: `zig build` regenerates `src/lib/wasm/dreamball.wasm` from the already-landed
v4 Zig as a side effect; that binary is the pinned committed artifact and is
outside C2 scope, so it was restored to HEAD after each build (its gzip budget
overrun is a separate, already-tracked concern).

### File List
- `schemas/root-2.0.0.json`
- `schemas/.pins/root-2.0.0.fp`
- `tools/schema-gen/gen_ts.zig`
- `tools/schema-gen/gen_valibot.zig`
- `tools/schema-gen/gen_cbor.zig`
- `tools/export-envelope-fixtures/main.zig`
- `src/lib/generated/types.ts` (regenerated)
- `src/lib/generated/schemas.ts` (regenerated)
- `src/lib/generated/cbor.ts` (regenerated)
- `src/lib/generated/cbor.test.ts` (regenerated — provenance fp header only)
- `fixtures/envelope_golden/action.cbor` (regenerated to v4)
- `src/lib/palace-round-trip.test.ts`
