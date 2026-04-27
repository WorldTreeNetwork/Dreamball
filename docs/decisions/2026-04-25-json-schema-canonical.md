# 2026-04-25 — JSON Schema as canonical source; codegen direction inverts

Sprint: sprint-002 · Significance: HIGH · Sibling decisions:
[archiform-registry](./2026-04-25-archiform-registry.md) ·
[action-manifest](./2026-04-25-action-manifest.md) ·
[wasm-runtime](./2026-04-25-wasm-runtime.md)

## Context

Today `tools/schema-gen/main.zig` is canonical for all field shapes
(root types and Memory-Palace types both), and emits
`src/lib/generated/{types,schemas,cbor}.ts`. The cross-runtime invariant
in CLAUDE.md is "the wire format lives in `src/*.zig`."

With archiforms federated via aspects.sh
([archiform-registry](./2026-04-25-archiform-registry.md)), the
canonical source for archiform field shapes must live in something
language-neutral that anyone can author without the Zig toolchain.
The Zig-as-source arrangement also calcifies field changes — adding a
field touches Zig, then regenerated TS, then Valibot, then CBOR, then
Cypher; in practice this turned hand-edits to `schema.cypher` into a
recurring drift risk.

## Decision

**JSON Schema is canonical for all field shapes** (root types and
archiform extensions). **The CBOR encoding algorithm stays canonical in
Zig**, with golden test vectors for cross-runtime conformance.

The wire-format invariant becomes more precise:

> All runtimes encode the same bytes for the same logical value
> (CBOR algorithm, in Zig + golden vectors), and all runtimes share
> field shapes via JSON Schema (vendored from aspects.sh).

### Codegen flow (new)

```
Pass 1 — root types
  schemas/root-2.0.0.json   →   Zig types  +  TS types  +  Valibot  +  CBOR codecs
  (vendored locally; mirror of dreamball/root@2.0.0 on aspects.sh)

Pass 2 — per-archiform
  schemas/<archiform>.json  →   Zig extensions  +  TS extensions  +  Valibot  +  Cypher DDL
  (vendored, pinned by fp; one pass per installed archiform)
```

Generators live in `tools/schema-gen/` but each becomes a JSON-Schema
*consumer* rather than a Zig *producer*.

### What JSON Schema covers

- Node and edge field shapes (types, optionality, ranges)
- Action manifest entries
  ([action-manifest](./2026-04-25-action-manifest.md))
- Decay-parameter shapes for archiform-specific edges

### What stays in Zig

- The CBOR canonicalization algorithm (map ordering, integer width
  rules, bytes vs text distinction, deterministic encoding)
- Golden test vectors: `(logical value, archiform fp) → expected
  bytes` pairs that every runtime MUST reproduce
- The cryptographic primitives (blake3, Ed25519, ML-DSA-87 verify)
  that the wasm core exposes

## Alternatives considered

1. **Keep Zig canonical; have aspects.sh wrap Zig outputs.** Rejected —
   couples archiform authoring to the Zig toolchain. Forces every
   community archiform author to learn Zig.
2. **CDDL** (CBOR Data Definition Language). Tempting because we are
   CBOR-native and CDDL is purpose-built for CBOR. Rejected — JSON
   Schema's tooling and ubiquity win; we already use Valibot, which
   round-trips with JSON Schema cleanly.
3. **Custom IDL.** Rejected — yet-another-schema-language tax.

## Consequences

- `tools/schema-gen/main.zig` flips role: from emitting `types.ts` to
  consuming `root-2.0.0.json` and emitting Zig + TS + Valibot + CBOR.
- Hand-maintained `src/memory-palace/schema.cypher` becomes generated.
  Closes a real drift risk surfaced in sprint-001.
- A future Rust, Go, or Swift jelly is tractable: take the JSON
  Schemas + the CBOR algorithm spec; no Zig dependency.
- Sprint-002 must include a **byte-equivalence gate**: regenerated
  outputs from the new JSON-Schema-driven flow MUST byte-match current
  Zig-generated outputs. Zero wire-format change is the gating
  constraint for the migration.
- Archiform schemas vendored locally with fp pinned. Updates are
  explicit (bump pin, regenerate, commit). No network at build time.
- The cross-runtime invariant is *strengthened*, not weakened: it
  factors into "encoding algorithm" (small, stable, Zig-canonical) and
  "field shapes" (evolves freely, JSON-Schema-canonical).

## Migration plan (sprint-002 candidate stories)

- **S-codegen-inversion** — extract root JSON Schema from current Zig
  types; build JSON Schema → Zig + TS + Valibot + CBOR generators;
  byte-equivalence-test against current outputs.
- **S-archiform-pinning** — author `dreamball/memory-palace@0.1.0`
  JSON Schema; vendor locally; regenerate `Inscription`/`Room`/
  `Aqueduct` from it across all five runtimes; verify no wire change
  via `zig build smoke` and `scripts/server-smoke.sh`.
