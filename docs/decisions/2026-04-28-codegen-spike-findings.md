# 2026-04-28 — Codegen Inversion Spike Findings (Story 1.1)

Sprint: sprint-002 · Significance: HIGH · Story: [1.1-codegen-spike-three-complex-types](../sprints/002-archiform-foundation/stories/1.1-codegen-spike-three-complex-types.md)

Sibling decisions: [json-schema-canonical](./2026-04-25-json-schema-canonical.md) ·
[archiform-registry](./2026-04-25-archiform-registry.md)

Related architecture decisions: D-018 (JSON Schema canonical for field shapes),
D-024 (spike-before-promote), D-030 (`tools/schema-gen/main.zig` disposition).

## Context

Story 1.1 runs the codegen-inversion spike against three Zig types named in the
Assumption #1 cell of `requirements.md`: **Envelope**, **SealedBody**,
**SignatureTierWrapper**. The spike asks: *can JSON Schema draft 2020-12, used
as the canonical source for field shapes, fully express these three Zig
constructs without expressivity loss?*

The spike sits at `tools/schema-gen/spike/` (siloed per D-024). It hand-authors
three JSON Schemas, runs a consumer that emits Zig + TS + Valibot + CBOR codec
fixtures, and byte-diffs them against a snapshot of what the legacy generator
emits for the same three types. Byte-equivalence (NFR1) is the gating
acceptance criterion.

The three target types map onto these source-of-truth Zig structs:

| Story-name              | Source struct                      | Why "expressively complex"                                                      |
| ----------------------- | ---------------------------------- | ------------------------------------------------------------------------------- |
| `Envelope`              | `src/protocol.zig DreamBall`       | Discriminated-union over `type` literal × 7 variants; format-version literal-union; identity bytes32; optional date strings (RFC3339 in JSON, tag-1 epoch-time in CBOR); optional signature list; per-variant attribute surface bleed-through (Relic-only `sealed-payload-hash`, etc.). |
| `SealedBody`            | `src/protocol.zig Relic`           | bytes32 + Fingerprint + open-string + optional epoch-time gate; the canonical "sealed payload" framing inlined on `jelly.dreamball.relic` envelopes. |
| `SignatureTierWrapper`  | `src/protocol.zig Signature` paired with `Stage` lifecycle tier | Closed-enum picklist for `alg` (`ed25519` | `ml-dsa-87`); opaque variable-length bytes; the `Stage` tier (`seed | dreamball | dragonball`) wraps the bag at envelope-level. |

## Spike outcome (AC1 + AC2 + NFR2)

- **AC1 (round-trip)**: green. The hand-authored JSON Schemas declare the same
  `required` core fields and the same set of optional properties as the
  corresponding Zig struct fields in `src/protocol.zig`. Round-trip tests in
  `tools/schema-gen/spike/main.zig` (run via `zig build schemagen-spike-test`)
  enforce this structural correspondence.
- **AC2 (byte-equivalence)**: green. `diff -r tools/schema-gen/spike/out/
  tools/schema-gen/legacy-spike-fixture/` returns empty. The spike consumer
  reproduces the legacy generator's output bytes for these three types
  exactly.
- **NFR2 (codegen runtime budget ≤ 5 s)**: green at spike scale. Wall-clock for
  `zig build schemagen-spike` after a warm cache: **0.17 s** on an M-series
  Mac. The full root + Memory Palace generation in Story 1.2/1.4 will be
  larger; this is the early signal that the JSON-Schema-driven flow is on
  budget.

## Expressivity gaps (AC3)

JSON Schema draft 2020-12 is *almost* sufficient, but four constructs in the
target Zig types do not have a 1:1 native JSON-Schema expression. Each is
recorded here with the chosen normalization and a Phase 3 follow-up note.

### Gap 1 — Discriminated union over a string literal × 7 variants

**Construct**: `DreamBall.type` is a string-literal type:
`'jelly.dreamball' | jelly.dreamball.${DreamBallType}` where `DreamBallType` is
itself an enum of 6 short tags (`avatar | agent | tool | relic | field | guild`).
The legacy TS emits this as a template-literal type
(`` `jelly.dreamball.${DreamBallType}` ``) and Valibot emits it as a
`v.variant('type', […])` over 7 distinct object schemas.

**JSON Schema 2020-12 native**: `enum` lists the 7 string values fine. What
JSON Schema does NOT natively express is the *per-variant attribute surface*
— e.g. only the `relic` variant carries `sealed-payload-hash`. The clean
expression would be a `oneOf` of 7 sub-schemas, each conditioning on `type`.
This works in 2020-12, but the legacy TS emits the variants flatly (all
optional fields on one shape), and the legacy Valibot emits a `v.variant` with
seven separate `v.object`s.

**Chosen normalization**: emit `type` as a closed `enum` of 7 strings in the
schema (this is what `envelope-2.0.0.json` does). Per-variant attribute
narrowing is encoded by listing the attribute as `["string", "null"]` (or
similar) at the top level with an `x-cbor-section: attribute` extension; the
generator-side post-pass walks the `type` enum × per-variant `oneOf` to emit
`v.variant` and the TS template-literal. The schema's authoring shape stays
flat (one schema, one type discriminator); the TS/Valibot emitters know how
to expand it.

Marker: `$comment: "Discriminator. Closed enum of 7 variants. Per AC3 spike
report: discriminated-union via JSON Schema string-literal enum is the chosen
normalization."` on `properties.type`.

**Phase 3 follow-up**: When Story 1.2 authors the full `schemas/root-2.0.0.json`,
add a `oneOf` block alongside the flat `properties` so JSON Schema validators
catch per-variant violations (Relic without `sealed-payload-hash`, Field
without `omnispherical-grid`, etc.) at validate-on-publish boundaries (NFR8).
Production generators (Story 1.3) consume the `oneOf` to emit the typed
`v.variant`.

### Gap 2 — Template-literal types in TypeScript output

**Construct**: TS emits `type: 'jelly.dreamball' | `jelly.dreamball.${DreamBallType}`
` so the compiler narrows on `type === 'jelly.dreamball.avatar'`. JSON Schema
has no native template-literal concept.

**JSON Schema 2020-12 native**: a closed `enum` lists all 7 strings.

**Chosen normalization**: closed `enum` in the schema. The TS emitter
post-processes the enum + the discriminator's relationship to a parent
`DreamBallType` enum to reconstruct the template-literal. The CBOR codec
emitter doesn't care — it sees a text-string at wire layer either way.

**Phase 3 follow-up**: TS emitter (Story 1.3 `gen_ts.zig`) needs an emit-mode
flag: `template-literal` vs `flat-enum`. Default to template-literal for
DreamBall-style discriminators where the parent enum already has a name.

### Gap 3 — RFC3339 string at JSON layer ⇄ tag-1 epoch-time at CBOR layer

**Construct**: `created`, `updated`, `sealed-until` are `?i64` in Zig (epoch
seconds), encoded as CBOR tag-1 (`epoch-time`). The legacy TS types model them
as `?: string` (RFC3339), and the Valibot validator uses `Rfc3339Schema`. The
legacy CBOR decoder auto-bridges by recognizing `__cborTag === 1`.

**JSON Schema 2020-12 native**: `format: "date-time"` exists, but does NOT
imply the CBOR tag-1 wire shape. The dual-layer mapping (string-at-JSON,
tagged-int-at-CBOR) is custom.

**Chosen normalization**: extension keys
`x-cbor: "tag-1-epoch-time"` and `x-zig: "?i64"` on each date-time property,
with `type: ["string", "null"]` at the JSON layer. The CBOR codec emitter
reads `x-cbor` to know to wrap/unwrap the tag-1 encoding; the TS / Valibot
emitters read `type` and `format` for the JSON-side surface.

**Phase 3 follow-up**: document the `x-cbor` enumeration formally in
`docs/decisions/2026-04-28-x-extension-keys.md` (or fold into FR15 protocol
refresh). The full set surfaced by the spike: `byte-string-32`,
`byte-string-variable`, `text-string`, `tag-1-epoch-time`, `smallest-uint`,
`smallest-float`, `attribute-pair-keyed-signed`,
`attribute-pair-position-{0,1}`. These become the canonical `x-cbor`
vocabulary for Story 1.2's full root schema.

### Gap 4 — `signed` attribute as a 2-array, not an object

**Construct**: At CBOR-wire layer, the `signed` attribute on an envelope
encodes as `[label, [alg, value]]` — i.e. the value position is itself a
2-array (`[alg-text-string, value-byte-string]`), NOT a CBOR map. This is the
recrypt-inherited convention; see `src/envelope_v2.zig` lines 88-94
(`encodeGuild`'s `signed` attribute pair).

JSON Schema's `properties` describe a JSON object with named keys. There is no
direct way to say "this property serializes to a positional 2-array at the
CBOR layer."

**Chosen normalization**: extension key
`x-cbor-attribute-encoding: "v2-attribute-pair-signed-with-2-array-alg-value"` at
the schema root, plus `x-cbor-section: "attribute-pair-position-0"` /
`"attribute-pair-position-1"` on the two object properties. The CBOR codec
emitter reads these to lay out the 2-array; the TS/Valibot emitters ignore
them and emit a flat object as before.

Marker: `$comment` on `signature-tier-wrapper-2.0.0.json` explains the wrapper
semantics; `x-cbor-attribute-encoding` carries the wire-layer rule.

**Phase 3 follow-up**: enumerate the full set of attribute-pair encoding
modes (the spike surfaced two:
`v2-tag-200-envelope-with-tag-201-leaf-and-attribute-pairs` for envelope-shaped
records, and `v2-attribute-pair-signed-with-2-array-alg-value` for signed
attribute pairs). Story 1.2 root schema needs the canonical list.

## Spike-scope omissions (NOT gaps — deliberate scope cuts)

The Envelope schema in this spike covers the core fields plus the signature
list and the Relic-variant attribute bleed-through. The following `DreamBall`
fields are NOT covered by the spike — they belong to Story 1.2's full
`schemas/root-2.0.0.json`:

- `look`, `feel`, `act`, `memory`, `knowledge-graph`, `emotional-register`,
  `interaction-set` (per-variant attribute surfaces)
- `contains`, `derived-from`, `guilds`, `dreamball-type` (graph edges +
  short-tag enum)
- `identity-pq`, `field-kind` (PQ pubkey + open-enum field kind)

Each of these is a routine extension of patterns the spike already validates
(repeated optional + open-enum + bytes32). None require new expressivity.
Recording them here so reviewers don't read the spike scope as the full root
schema.

## Spike-implementation note: the legacy generator is a static text emitter

The legacy `tools/schema-gen/main.zig` is not a JSON-Schema-aware generator —
it is a Zig program with hardcoded `TYPES_SRC` / `SCHEMAS_SRC` / `CBOR_SRC`
constant strings. The byte-equivalence baseline at
`tools/schema-gen/legacy-spike-fixture/` is a hand-extracted snapshot of the
lines the legacy generator's static strings emit for `DreamBall`, `Relic`,
`Signature`, and `Stage`. This is an authoring artefact: in Story 1.4's shadow
phase the legacy generator runs in full and the new generator runs against
the full root schema; their full outputs diff. The spike's scope-restricted
fixture is sufficient to prove Assumption #1 against the three named types
without rebuilding the whole generator pipeline.

## Spike outcome → architecture commitment (AC4)

**D-018 + D-030 are sufficient. No amendment proposed.**

JSON Schema draft 2020-12 fully expresses the three target Zig constructs
(`Envelope`, `SealedBody`, `SignatureTierWrapper`) given a small, bounded set
of `x-` extension keys (`x-zig`, `x-zig-type`, `x-cbor`,
`x-cbor-section`, `x-cbor-attribute-encoding`, `x-format-version`,
`x-wire-type`, `x-wire-attribute`, `x-optional`, `x-ts-type`). These
extensions live entirely outside the JSON Schema `properties`/`required`
core — schema validators ignore them, but the per-target generators
(`gen_zig.zig`, `gen_ts.zig`, `gen_valibot.zig`, `gen_cbor.zig` per D-030)
consume them to emit the legacy bytes.

The three normalizations that JSON Schema 2020-12 cannot natively express
(discriminator → flat enum + per-variant `oneOf`; template-literal TS →
closed `enum` + emitter post-pass; tag-1 epoch-time dual layer →
`x-cbor: "tag-1-epoch-time"`; signed attribute 2-array →
`x-cbor-attribute-encoding`) are all expressible via these extension keys
without losing schema validity. Validators that don't know the extensions
still validate the JSON layer correctly; generators that do know them produce
the exact CBOR/Zig surface the legacy generator does today.

This confirms the architectural commitment landed in D-018 (JSON Schema
canonical for field shapes; CBOR algorithm canonical in Zig with golden
vectors) and D-030 (repurpose `tools/schema-gen/main.zig` as the
JSON-Schema-consumer entry point with per-target generators alongside;
`legacy/` shadow phase). Story 1.2 (full root schema) and Story 1.4 (shadow
phase + cutover) inherit these commitments unchanged.

The spike's NFR2 timing (0.17 s for three schemas) makes the 5 s budget
plausible at full root scale: Story 1.2's `schemas/root-2.0.0.json` will
contain ~25 types but the per-schema parse + emit cost is dominated by file
I/O and Zig template-string assembly, both of which scale linearly with line
count.

**Open follow-up for Story 1.2**: enumerate the full `x-cbor` vocabulary in a
dedicated subsection of `docs/decisions/2026-04-28-x-extension-keys.md` (or
fold into FR15 PROTOCOL.md refresh). The spike surfaced enough vocabulary to
suggest the closed set is small (≤ 8 wire-layer modes); confirming this
during Story 1.2 authoring closes the last open question on the codegen
direction.

## Cross-references

- Spike code: `tools/schema-gen/spike/main.zig`
- Spike schemas: `tools/schema-gen/spike/schemas/{envelope,sealed-body,signature-tier-wrapper}-2.0.0.json`
- Byte-equivalence baseline: `tools/schema-gen/legacy-spike-fixture/`
- Build commands: `zig build schemagen-spike` (run consumer);
  `zig build schemagen-spike-test` (round-trip tests);
  `diff -r tools/schema-gen/spike/out/ tools/schema-gen/legacy-spike-fixture/`
  (byte-equivalence verification, AC2)
- Story file: `docs/sprints/002-archiform-foundation/stories/1.1-codegen-spike-three-complex-types.md`
