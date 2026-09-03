# Normalization: Cypher provenance header source-schema field

**Normalization ID**: cypher-header-source-schema
**Story**: 2.2
**Status**: documented, semantically equivalent

## What differs

The `diff tests/fixtures/pre-migration-schema.cypher src/memory-palace/schema.cypher`
produces exactly 3 lines of diff, all in the provenance header block:

```
< --   source-schema:     schemas/root-2.0.0.json
< --   source-schema-fp:  blake3:724658c2cae421b27754d118d4fad7c53bf0a75347201c5bf6b6ef0c507f1adc
< --   schema-version:    2.0.0
---
> --   source-schema:     schemas/memory-palace-0.1.0.json
> --   source-schema-fp:  blake3:6678ddf42f383a054181d17f090f2b59eb1be693f0e61c1c4fe4bdd62c1c5885
> --   schema-version:    0.1.0
```

## Why this differs

Before Story 2.2 landed, `gen_cypher.zig`'s root pass was the only pass that
emitted `src/memory-palace/schema.cypher`. Its provenance header named the root
schema (`schemas/root-2.0.0.json`) as the source — a placeholder because the
per-archiform codegen pipeline did not yet exist.

Story 2.2 adds the per-archiform pass. After it runs, the provenance header
correctly names the **archiform** schema (`schemas/memory-palace-0.1.0.json`)
as the source. This is the semantically correct attribution: the Memory Palace
DDL is defined by the Memory Palace schema, not the root DreamBall schema.

## Semantic equivalence justification

The provenance header is a comment block. It is:
- Not executed by KuzuDB when the DDL is applied.
- Not read by any runtime code path (store.server.ts, store.browser.ts).
- Not part of the CBOR wire format (D-018: encoding algorithm stays in Zig).
- Not load-bearing for replay-from-CAS (D-021): ActionLog rows reference
  envelope fps, not the schema provenance header.

The DDL body (all `CREATE NODE TABLE` and `CREATE REL TABLE` statements) is
byte-identical between the pre-migration file and the Story 2.2 generated file.
No column names, column types, DEFAULT values, or relationship pair definitions
changed.

## Column order note (D-021 replay-from-CAS)

D-021 requires that if a normalization changes column order, ladybugdb migration
semantics must be flagged as a blocker. This normalization does NOT change column
order — only the comment header differs. No blocker.

## Drift detection (AC6)

The byte-equivalence test (`tests/codegen/cypher-byte-equivalence.test.ts`) allows
exactly the 3-line header diff described above and fails on any body diff. If a
required field (e.g. `Aqueduct.last_traversal_ts`) is removed from the schema,
either the `validateSchemaCoverage` step in `gen_cypher.zig` fails the build
(no output written → empty diff test fails) or Story 2.1's coverage test
(`tests/codegen/memory-palace-schema-coverage.test.ts`) fails at the Vitest level.
Neither path allows a silent drift.
