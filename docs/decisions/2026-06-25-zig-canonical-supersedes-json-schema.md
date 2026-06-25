# 2026-06-25 — Zig is canonical; generate every representation from it (supersedes D-018)

Sprint: sprint-002 (course-correction) · Significance: HIGH ·
**Supersedes:** D-018
([json-schema-canonical](./2026-04-25-json-schema-canonical.md)) and the
codegen-direction portions of D-029/D-030 (sprint-002
`architecture-decisions.md`) ·
Related: [codegen-spike-findings](./2026-04-28-codegen-spike-findings.md) ·
[archiform-registry](./2026-04-25-archiform-registry.md)

## Context — what changed since D-018

D-018 (2026-04-25) inverted the codegen direction: JSON Schema became
canonical for field shapes, Zig a derived output. The **sole**
justification in D-018's "alternatives considered" for rejecting
Zig-canonical was federation — archiforms published via aspects.sh need
a language-neutral source so community authors needn't learn Zig.

Two facts have since become clear, and together they invert the
conclusion:

1. **aspects.sh integration is unbuilt.** It exists only as prospective
   design in [archiform-registry](./2026-04-25-archiform-registry.md),
   entirely in the future tense ("aspects.sh *becomes* the registry",
   "*adds* a `kind` discriminator", the `dreamball/*` namespace is
   "*reserved*"). Schemas are local vendored files with blake3 pins,
   explicitly "no network at build time." Nothing is served, fetched, or
   authored externally. **The federation use-case that justified the
   inversion does not yet exist.**

2. **The inversion never actually shipped.** No generator emits from the
   schema: `gen_ts` / `gen_valibot` / `gen_cbor` write hardcoded string
   bodies (lifted from the deleted legacy generator) and read the schema
   only to verify its pin; `gen_zig` is a deliberate no-op. The
   "JSON-Schema-canonical pipeline" is scaffolding — vendored schema,
   pins, provenance headers, dispatch — with **no schema→output wiring**.
   Outputs stay correct via a byte-equivalence gate, not via
   schema-driven generation.

Meanwhile the codegen-inversion spike
([codegen-spike-findings](./2026-04-28-codegen-spike-findings.md))
surfaced the structural problem: JSON Schema cannot natively express the
CBOR/Zig wire semantics, requiring a growing set of `x-` extension keys
(`x-cbor`, `x-zig`, `x-cbor-attribute-encoding`, …) — a CBOR IDL
smuggled inside JSON Schema. The attempt to turn on `gen_zig`
(Dreamball-m97.1) hit the same wall from the Zig side: Zig structs carry
**defaults** (`strength: f64 = 1.0`), **field-name casing**
(`last-updated` → `last_updated`), **memory-layout types** (`[16]u8`,
enums), **helper types** (`MemoryNode.LookupEntry`), and **methods**
(`toWireString`, `isFullySigned`) that JSON Schema cannot hold. These
are not edge cases; they are most of what a wire type *is*.

## The principle

**The canonical source must be the most expressive representation, so
that generation flows lossy-*downward*.** Information flows cleanly from
Zig → JSON Schema (drop the defaults, methods, exact types). It does not
flow up: JSON Schema cannot reconstruct them. Forcing the expressive
medium (Zig) to sit *downstream* of the less-expressive one (JSON
Schema) is fighting the gradient — and the `x-` extension-key tax was
the symptom of that fight.

Zig is already the center of gravity. D-018 itself keeps the CBOR
encoding algorithm canonical in Zig; the decoders are Zig; the WASM core
is Zig. The schema is the lone artifact that was *copied out of* Zig by
hand. The fix is to make the original canonical and the copies derived.

## Decision

**Zig (`src/protocol.zig` + `src/protocol_v2.zig`) is the single
canonical source for both the CBOR encoding algorithm and the field
shapes.** Every other representation — TypeScript types, Valibot
validators, the CBOR codec / `cbor.ts`, JSON Schema, and Cypher DDL — is
**generated from the Zig types via comptime reflection (`@typeInfo`)**.

- **JSON Schema is reclassified from canonical source to generated
  artifact.** `schemas/root-*.json` and `schemas/<archiform>-*.json`
  become outputs — published to aspects.sh if/when federation is built,
  and golden test fixtures in the meantime.
- **The `x-` extension-key vocabulary is retired as an authoring
  concern.** Any wire-layer hints the JSON-Schema *output* needs are
  derived from the Zig types directly (or attached via Zig doc-comment
  conventions on the canonical side), not hand-authored into JSON.
- **`tools/schema-gen/main.zig` flips again**: from "read schema → emit
  (hardcoded) outputs" to "reflect Zig types → emit outputs (including
  JSON Schema)." The reusable scaffolding — orchestrator, provenance
  headers, structured logging, `codegen_common` — stays.

### What stays unchanged

- The cross-runtime invariant's *substance*: every runtime reproduces
  identical bytes for the same logical value, enforced by golden test
  vectors. Both halves — encoding algorithm *and* field shapes — are now
  Zig-canonical, which strengthens the invariant rather than weakening
  it.
- The browser and server share one `dreamball.wasm`; `cbor.ts` remains
  generated — now from Zig, not from the schema.

## The federation escape hatch (deferred until aspects.sh authoring is real)

If/when third parties must *author* a new archiform without the Zig
toolchain, adopt a **two-direction split that maps onto the existing two
codegen passes**:

- **Root types** — Zig-canonical → generate JSON Schema *out*.
- **Community archiform extensions** — JSON-Schema-authored → generate
  Zig *in*.

The expressive core stays in Zig; lossy JSON authoring is accepted only
at the federation boundary where outsiders actually write. This is
deferred until that need exists (YAGNI) and is recorded here only so the
revert does not read as foreclosing federation.

## Alternatives considered

1. **Finish the JSON-Schema-canonical inversion (D-018's intent).**
   Rejected — pays the `x-`extension-key tax and the upward-expressivity
   gap permanently, in exchange for a federation benefit that is
   unbuilt. The spike and the `gen_zig` attempt both confirmed the gap
   is structural, not incidental.
2. **Keep JSON Schema canonical but hand-maintain Zig alongside.**
   Rejected — that is exactly today's drift-prone half-state: two
   sources of truth for the same types.
3. **CDDL as canonical.** Rejected as canonical — domain-native
   (Blockchain Commons / Gordian use it) but immature TS tooling, *not*
   used by sibling recrypt, and still less expressive than Zig (no
   methods/defaults). CDDL stays attractive only as a generated
   conformance artifact — the same status JSON Schema now holds.
4. **Protobuf/buf (recrypt's API-layer choice).** Rejected for the
   envelope layer — recrypt itself chose Gordian Envelope *over*
   protobuf for the wire; protobuf fits the RPC surface, not canonical
   dCBOR envelopes.

## Consequences

- D-018 superseded;
  [json-schema-canonical](./2026-04-25-json-schema-canonical.md) gets a
  superseded-by banner. The codegen-direction portions of D-029/D-030 in
  the sprint-002 `architecture-decisions.md` are superseded.
- `root-2.0.0.json` / `memory-palace-0.1.0.json` become generated
  outputs + fixtures. The hand-authoring is **not wasted**: it defines
  the expected JSON-Schema emission and becomes the byte-equivalence
  target for the Zig→JSON-Schema generator.
- The real codegen story becomes **"Zig `@typeInfo` → {TS, Valibot, CBOR
  codec, JSON Schema, Cypher}"** — the comptime-reflection generator that
  `src/lib/generated/README.md` always anticipated ("a Zig program so it
  can introspect the actual `src/protocol.zig` structs via comptime
  reflection").
- The nested-envelope decode work (Dreamball-m97) simplifies to
  **"complete the decoders in Zig"** (matching the existing
  `encodeMemory` encoders) — no `gen_zig` prerequisite, no schema
  round-trip. The comptime generator then emits the downstream
  representations.
- **Timing:** reverting now is cheap precisely because nothing is
  generated from the schema yet. Every story that finishes the inversion
  first raises the cost of this correction.

## Migration plan

1. This ADR + superseded-by banners on D-018 and the sprint-002
   `architecture-decisions.md` codegen sections.
2. Re-scope Dreamball-m97: drop "via JSON-Schema codegen"; (a) complete
   nested decoders in Zig; (b) new story — build the Zig→targets
   comptime generator; (c) JSON Schema becomes a generation target with
   the current hand-authored files as the equivalence fixture.
3. Update the CLAUDE.md "cross-runtime invariant" section: Zig canonical
   for the encoding algorithm **and** field shapes; JSON Schema a
   generated artifact.
4. Leave the vendored schemas + pins in place until the comptime
   generator can reproduce them, then flip them to generated outputs
   under a regen gate.
