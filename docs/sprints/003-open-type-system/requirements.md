---
project: dreamball
sprint: sprint-003
product: null
created: 2026-06-27
steering_mode: GUIDED
previous_sprint: sprint-002
input_quality: existing-prd
source_prd: docs/prd-open-type-system-mvp.md
---

## Product Vision

Open DreamBall's closed type system: let a consumer carry their own typed,
signed state as first-class DreamBalls via a generic open-kind, typed-body action
envelope — with cross-runtime byte-identical `content_hash` — so the type system
(not a closed vocabulary) defines the wire format. (`docs/VISION.md §17`.)

## Success Metrics

- **M1 — Consumer self-sufficiency.** A consumer defines their own data-type
  schema(s) and authors → signs → verifies DreamBalls that satisfy them, with
  zero hand-rolled CBOR required on their side. Binary pass/fail.
- **M2 — Cross-runtime byte-identity.** Same logical value → byte-identical
  canonical bytes + `content_hash` across browser WASM, Bun WASM, native CLI.
  Golden-vector enforced; target 0 divergences.
- **M3 — Open vocabulary.** The op envelope's `kind` is an open string; a
  previously-unseen `kind` round-trips and verifies with no DreamBall-side enum
  change.

## Functional Requirements

> MVP scope for this sprint. Derived from PRD FR1–FR11 (PRD FR12–FR17 are
> Growth/Vision → Out of Scope). Renumbered sequentially here.

### FR1: Define a consumer data-type in the Zig-canonical pipeline
A new wire type can be defined as a Zig struct declaring `type_string` +
`format_version` + fields; envelopes bearing that `type_string` are treated as
first-class typed DreamBalls. (PRD FR1.)

### FR2: Generate downstream artifacts from the Zig type
`zig build schemagen` produces the TS type, Valibot schema, `cbor.ts` codec, and
JSON-Schema artifact for a Zig-defined type, with no hand-authored JSON Schema as
source. (PRD FR2; governed by Zig-canonical ADR / TC1.)

### FR3: Canonical dCBOR encode/decode for a typed DreamBall
A typed DreamBall round-trips through canonical dCBOR (length-first map ordering,
shortest-int, no floats in the payload common subset), producing byte-identical
output for the same logical value. (PRD FR3.)

### FR4: Schema-satisfaction + canonical-form validation
A decoded DreamBall is validated against its type's schema and rejected if it
does not satisfy it; any non-canonical CBOR is rejected on decode. (PRD FR4.)

### FR5: Generic open-kind action envelope
An action envelope whose `kind` is an open string (not a closed enum), carrying
an arbitrary typed `body` payload, a hybrid logical clock `[l, c]`, and
zero-or-more `parent_hashes`. (PRD FR5. Supersedes/extends the closed
`ball.action` — see Open Question Q1.)

### FR6: WASM authoring export — encode + sign the generic envelope
A WASM export encodes and Ed25519-signs a generic action envelope from
caller-supplied fields + a 64-byte secret key, returning canonical signed bytes
via the packed-`u64` convention (`0` on error → `resultErr*`). (PRD FR6.)

### FR7: TS loader wrapper (browser + Bun)
`src/lib/wasm/loader.ts` exposes generic-action authoring/signing + verification
to JS, producing byte-identical output and identical verification verdicts for
the same inputs in both the browser and under Bun. (PRD FR7.)

### FR8: content_hash + cross-runtime golden vector
`content_hash` = Blake3-256 of the canonical envelope bytes; a golden vector
asserts bytes + digest are identical across the Zig CLI and the WASM build (the
mechanism satisfying NFR1). (PRD FR8.)

### FR9: Verify the generic action envelope
Verification checks the Ed25519 signature against the envelope's actor identity
and enforces canonical form on decode, with distinct results for verified /
signature-failed / parse-or-canonical-error. (PRD FR9.)

### FR10: Native HLC carried in the envelope
The logical clock `[l, c]` is carried natively in the action envelope and covered
by `content_hash` (composes beads `Dreamball-fch`; depends on the HLC spec — Q4).
(PRD FR10.)

### FR11: All integration gates green
`zig build test`, `zig build smoke`, `scripts/server-smoke.sh`, Vitest, and
`svelte-check` remain green with the new type + export. (PRD FR11; TC4.)

## Non-Functional Requirements

### NFR1: Cross-runtime determinism
Canonical dCBOR encoding is byte-identical across browser WASM, Bun WASM, and
native CLI for any value in the supported subset; enforced by golden vectors in CI.

### NFR2: One binary, two runtimes
A single `dreamball.wasm` runs in browser + Bun via the sole `env.getRandomBytes`
host seam; no additional host imports.

### NFR3: Security
All present signatures verified (Ed25519 against `actor`/`identity`); malformed-
length or non-canonical input rejected. Browser/Bun authoring is Ed25519-only; PQ
signing is CLI-side this slice.

### NFR4: Zig-canonical maintainability
No second hand-maintained implementation of a wire type. Until the `@typeInfo`
generator lands, generated TS/Valibot/cbor.ts/JSON-Schema are hand-propagated and
held consistent by the byte-equivalence gate.

### NFR5: Size (relaxed)
The gzip budget is relaxed for this slice; resulting raw + gzip `dreamball.wasm`
sizes are recorded in build notes (measured, not gated). Soft 300 KB-gz drift
flag only.

## Technical Constraints

### TC1: Zig is the canonical source (D-018 superseded)
Per `docs/decisions/2026-06-25-zig-canonical-supersedes-json-schema.md`, wire
types are edited as Zig structs first and propagated downward. JSON Schema is a
generated artifact; never hand-authored; no `x-cbor`/`x-zig` keys.

### TC2: Canonical dCBOR determinism must hold
Length-first map-key ordering + shortest-int + no floats (common subset) so
`content_hash` is portable (`dcbor.zig:44`, `assertCanonical`).

### TC3: Ed25519-only authoring in WASM
Browser/Bun authoring signs Ed25519 only; ML-DSA-87 dual-sig is CLI-side
(deferred). `signActionEnvelope` is a raw byte-signer (D-023).

### TC4: Every commit keeps all gates green
"Verified" requires `zig build smoke`, not just narrow tests (CLAUDE.md).

### TC5: `@typeInfo` generator not built
New/changed types require manual propagation to generated targets, guarded by the
byte-equivalence gate (beads `Dreamball-m97.2` deferred).

### TC6: envelope_v2 not yet linked into the WASM
`wasm_main.zig` imports v1 `envelope.zig`; the v2 encode path (`envelope_v2`) is
not in the WASM today. Linking it is net-new code in the binary (size relaxed —
NFR5).

## Open Questions

- **Q1 (Phase 2A, CRITICAL):** Does the generic op envelope **extend `ball.action`**
  (open the `kind`, add `body` + HLC, bump `format_version`) or introduce a **new
  generic type** (e.g. `ball.op`), leaving `ball.action` as a constrained palace
  profile? Shapes the whole implementation.
- **Q2 (Phase 2A, HIGH):** Open-kind wire representation — bare string vs
  namespaced/authority-prefixed (e.g. `"worldtree/kanban-card.move"`)? Affects
  collision-safety + future renderer dispatch.
- **Q3 (Phase 2A, HIGH):** MVP authoring boundary — does "define your own type"
  mean (a) open-kind + typed **body** only, first-class Zig types added by the
  maintainer, or (b) a self-serve path for consumer-authored Zig types? (Leaning
  a; b is Growth.) Determines how much of FR1–FR2 lands this sprint.
- **Q4 (Phase 2A, HIGH):** HLC `[l, c]` exact shape + tie-break semantics
  (resolve `Dreamball-fch`) before freezing it into `content_hash`.
- **Q5 (Phase 2A, MEDIUM):** Canonical validation authority — Zig decode /
  `assertCanonical` as the gate of record, Valibot mirroring it (generated)?

## Scope Boundaries

### In Scope
- Generic open-kind, typed-body action envelope (+ native HLC + `parent_hashes`).
- WASM authoring export + TS loader wrapper (browser + Bun) for it.
- Zig-canonical pipeline for defining a type + generating downstream artifacts.
- Schema-satisfaction + canonical-form validation.
- Cross-runtime `content_hash` byte-identity with golden vectors.
- Keeping all integration gates green.

### Out of Scope
- Renderer-dispatch-by-field-presence contract (PRD FR12 — Growth).
- Self-serve type registration for non-Zig authors (PRD FR13 — Growth; see Q3).
- dag-cbor ↔ native byte-parity guarantee (PRD FR14 — Growth).
- Memory Palace extraction (PRD FR15 — Vision); `@typeInfo` generator (FR16 — Vision).
- PQ/ML-DSA-87 WASM authoring (PRD FR17 — Vision).
- **Networking / sync / CRDT-merge** — wire format only, not transport
  (VISION.md §8, §17 guardrail 1). Merge rules are the consumer's.
- Kanban-specific semantics — the envelope stays domain-neutral (§17 guardrail 3).

## Assumptions

| Assumption | Validation Method | Impact if Wrong |
|---|---|---|
| Consumers are not Zig authors; the generic open-kind/typed-body envelope is the real "define your own data" mechanism for MVP | Confirm with World-Tree that body+open-kind unblocks the kanban slice | If they need self-serve Zig types in MVP, scope grows (Q3 → pull FR from Growth) |
| Extending `ball.action` (vs a new type) is preferable | Phase 2A architecture decision (Q1) | Wrong choice forks the protocol or over-constrains the palace action |
| HLC `[l,c]` can be specified now and frozen into content_hash | Resolve `Dreamball-fch`; write PROTOCOL.md note (Q4) | Premature freeze → breaking change later |
| Manual codegen propagation is tractable for one new type | Byte-equivalence gate + golden vectors stay green | Drift between Zig and generated targets across runtimes |
| Linking envelope_v2 into the WASM is acceptable on size | Build + record gz size (NFR5 relaxed) | If size matters again later, needs size work |

## Previous Sprint Intelligence (sprint N>1)
D-018 (JSON-Schema-canonical) is **superseded** by the 2026-06-25 Zig-canonical
ADR — the governing constraint for FR1–FR2/TC1. D-023 (Ed25519 `signActionEnvelope`)
and D-019 (action manifest) directly shape FR5–FR6. D-007's "typed API over a thin
primitive" pattern is the model for the loader wrapper (FR7). The `@typeInfo`
generator (m97.2) is unbuilt → manual-propagation burden (TC5).

## Existing Codebase Inventory
Constraining elements: closed `ball.action` (`protocol_v2.zig` `Action` +
`ActionKind` enum; `envelope_v2.zig:544` `encodeAction`), packed-u64 authoring
exports (`wasm_main.zig`), canonical dCBOR (`dcbor.zig`), golden vectors
(`golden.zig`), the loader (`src/lib/wasm/loader.ts`), generated targets
(`src/lib/generated/*`), codegen (`tools/schema-gen`). envelope_v2 is not yet
linked into the WASM (TC6). Consumer ABI documented in
`docs/abi/wasm-authoring-abi.md`.
