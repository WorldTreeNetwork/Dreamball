# 2026-04-25 — Archiform registry: aspects.sh and the 3-layer model

Sprint: sprint-002 · Significance: HIGH · Sibling decisions:
[json-schema-canonical](./2026-04-25-json-schema-canonical.md) ·
[action-manifest](./2026-04-25-action-manifest.md) ·
[wasm-runtime](./2026-04-25-wasm-runtime.md)

## Context

Sprint-001 built Memory Palace as if `Room`, `Aqueduct`, `Inscription`,
and `Oracle` were root DreamBall protocol. The retrospective surfaced
that this conflates the protocol with one specific *kind* of ball. A
journaling ball, a study-group ball, or a guild ball shouldn't inherit
Memory-Palace vocabulary; equally, the protocol shouldn't grow new
node-type names every time someone invents a new kind of ball.

DreamBall needs a way to define new *kinds* of balls without modifying
core code, and a registry where those definitions can be discovered,
verified, and composed.

## Decision

**aspects.sh becomes the registry for DreamBall archiforms,** under a
3-layer model:

| Layer | Lives at | What it is |
|---|---|---|
| **Schema** | aspects.sh, new `kind: "schema"` aspect | The shape of a kind of ball — node/edge subtypes, decay parameters, action manifest, lens-pack pointer |
| **Manifestation** | aspects.sh, today's `kind: "personality"` aspect with `extendsSchema` pointer | A particular dressing of a schema — mythos defaults, oracle persona, wallet config |
| **Instance** | Dreamforge (git + LFS) | The actual living DreamBall data — rooms, inscriptions, traversal state |

A DreamBall declares its `archiform_fp` in the **genesis envelope**
(immutable for the ball's lifetime — archiform = species, not state).

A schema-aspect is *not* required at runtime to decode bytes
(CBOR + root primitives are sufficient for a generic view, like a
generic XML parser handling any document). It IS required for typed
accessors, validation, rich rendering, and codegen.

## What aspects.sh already provides

- Blake3 content-addressing of aspect bodies
- Anonymous share-by-hash (`name-7kYx3abc12`) and authenticated publish
- Registry index with versioning, GitHub source support, trust levels
- `sets` — already a primitive for compositions of aspects
- Zod-validated schema kept narrow and stable

Only one new thing needed: a second aspect *kind* (`kind: "schema"`)
whose body is a JSON Schema document instead of a personality prompt.
Existing aspects (Alaric, Default) stay valid unchanged.

## Naming

- `dreamball/memory-palace@0.1.0` — schema-aspect (this is the
  archiform identity Memory Palace instances declare in their genesis
  envelope)
- `worldtree/oracle-palace@1.0.0` — manifestation-aspect (extends the
  schema, supplies mythos template + oracle persona reference)
- The `dreamball/*` publisher namespace on aspects.sh is reserved for
  schema-aspects of canonical DreamBall archiforms.

## Alternatives considered

1. **Parallel registry just for DreamBall types.** Rejected —
   duplicates the federation, hashing, distribution, and trust
   infrastructure aspects.sh already runs; fragments a community that's
   already publishing personality-aspects which manifestations want to
   compose with.
2. **Embed all archiform schemas in the Dreamball repo.** Rejected —
   non-federated, doesn't scale to community archiforms, makes Dreamball
   the bottleneck for every new ball type.
3. **Mythos-mutable archiform pointer** (let a ball change its
   archiform over its lifetime). Rejected for now — archiform = species,
   not state. A genesis-immutable pointer keeps "what kind of thing is
   this" stable across the ball's life. Reconsider if real use cases
   appear.

## Consequences

- Memory Palace's current node/edge schema (in
  `src/memory-palace/schema.cypher` and `tools/schema-gen/main.zig`)
  gets extracted into `dreamball/memory-palace@0.1.0` on aspects.sh.
- Dreamball repo vendors a pinned copy locally
  (`schemas/memory-palace-0.1.0.json`) with its fp recorded; codegen
  pulls from the local pin (deterministic, no network at build time).
- Genesis envelope gains an `archiform_fp` field. Older instances
  without it implicitly bind to `dreamball/memory-palace@0.1.0` for
  back-compat (sprint-001 instances are pre-aspects-system).
- aspects.sh adds a `kind` discriminator and a `schema`-kind body
  shape to its Zod aspect schema. Personality aspects unaffected.
- New archiforms can be authored without touching Dreamball core code.
