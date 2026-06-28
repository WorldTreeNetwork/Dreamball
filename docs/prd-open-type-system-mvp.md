---
title: DreamBall Open Type System — MVP
created: 2026-06-27
status: validated
scope_tier: mvp
---
# PRD: DreamBall Open Type System — MVP

> Seeded from [`docs/VISION.md` §17 "The open type system"](VISION.md). Scope is
> **DreamBall-the-protocol/type-system only** — not any consumer application.
> World-Tree's kanban CRDT is a validating probe, explicitly **not** the ideal
> use case (VISION.md §17 guardrail 3).

## Problem Statement

DreamBall is, today, a **closed** type system. The six-type taxonomy and the
Memory Palace / Wishing Tree compositions are all types *we* authored; the
schema, the renderers, and the action vocabulary are ours. The first real
external consumer (World-Tree `web/`) tried to store their own durable, signed,
typed state as DreamBalls and hit a wall immediately: DreamBall ships a raw
Ed25519 byte-signer (`signActionEnvelope`, which signs arbitrary bytes and sets
no envelope fields) and a closed `ball.action` (a fixed core map, a closed
9-value Memory-Palace `action-kind` enum, no payload field, no logical clock).
There is no way for a consumer to define their own data type or carry their own
typed payload as a first-class DreamBall. Until that gap closes, the
"universal verifiable typed-container" the rest of the vision assumes does not
actually exist for anyone but us.

## User Personas

**Consumer developer (primary) — "the builder on DreamBall."**
Represented by the World-Tree `web/` team (e.g. xibudojo). Building a
local-first multiplayer 3D social space in SvelteKit + embedded-Elysia (Bun).
Goals: define their own typed data (op-log entries, 3D-object transforms,
avatars), store it as signed verifiable DreamBalls, run the *same* WASM core in
the browser and on the Bun server, and never hand-roll CBOR. Pain points: the
authoring exports have no usable shape for their data; the only action type is
palace-specific; cross-peer `content_hash` agreement is unproven for their own
payloads. Technical level: high (TS / Bun / SvelteKit); **not** Zig authors.

**DreamBall maintainer — "the protocol owner."**
Represented by Duke. Goals: open the type system so third parties can define
types, without over-fitting the protocol to one consumer's needs or letting
DreamBall absorb networking/sync concerns. Pain points: every new type today
requires core changes; Memory Palace is monolithically woven into the codebase
rather than expressed as a type. Technical level: expert (Zig + TS).

## User Journeys

**Journey 1 — Consumer carries their own typed op (primary path).**
The World-Tree developer needs a durable, signed kanban op. They define their
op-payload shape in their own code (a Valibot schema on their side). They call a
DreamBall authoring API: `authorAction({ kind: "kanban-card.move", body: <their
typed payload>, hlc: [l, c], parentHashes: [...] }, secretKey)`. DreamBall
encodes it as a canonical `ball.action` envelope with an **open** kind string and
an opaque typed body, signs it Ed25519, and returns canonical bytes plus a
`content_hash`. A peer receives the bytes, verifies the signature against the
actor identity, and recomputes `content_hash` — which matches byte-for-byte
because both ran the same WASM. Outcome: a signed, causally-ordered op the
consumer authored without writing any CBOR.

**Journey 2 — A consumer type becomes first-class.**
A payload shape the consumer uses everywhere (say `object3d`) is promoted to a
first-class DreamBall type. The maintainer adds a Zig struct (`type_string`,
`format_version`, fields) and runs `zig build schemagen`; the TS type, Valibot
schema, `cbor.ts` codec, and JSON-Schema artifact regenerate from the Zig
source. The consumer now gets typed encode/decode/validation for `object3d`
DreamBalls in both runtimes, and the renderer can recognize it by field
presence. Outcome: the type system grew by one type with no hand-written
parallel codecs and no cross-runtime drift.

**Journey 3 — Cross-runtime determinism check (maintainer).**
The maintainer adds a golden vector: a fixed logical op → its exact canonical
bytes and `content_hash`. CI runs it under the Zig CLI and the WASM (browser-
and Bun-loaded) build. Any encoder change that would diverge `content_hash`
across runtimes fails the gate. Outcome: op identity and snapshot equality are
guaranteed portable, which is what makes the log usable across peers.

## Success Metrics

- **M1 — Consumer self-sufficiency (primary).** A consumer defines their own
  data-type schema(s) and authors → signs → verifies DreamBalls that *satisfy*
  those schemas end-to-end, using that schema consistently across all of an
  app's calls, with **zero** hand-rolled CBOR on the consumer side. Measured
  (binary, pass/fail): the consumer's op path requires no `@ipld/dag-cbor` or
  manual CBOR — authoring and verification go entirely through DreamBall APIs
  (the consumer *may* still use dag-cbor, but is not forced to). Target: 100%
  of the World-Tree kanban op path on DreamBall APIs. (Schedule expectation —
  within the MVP sprint — is tracked separately from this outcome metric.)
- **M2 — Cross-runtime byte-identity.** For a fixed logical value, the canonical
  envelope bytes and `content_hash` are byte-identical across browser WASM, Bun
  WASM, and native CLI. Measured: a golden-vector test asserts equality across
  all three; target 100% pass in CI, 0 divergences.
- **M3 — Open vocabulary.** The generic op envelope's `kind` is an open string
  with **no** DreamBall-side enum a consumer must petition us to extend.
  Measured binary: a consumer can author an action with a previously-unseen
  `kind` value and it round-trips + verifies. Target: pass.

> Size budget is **explicitly relaxed** for this slice (the gzip ceiling is not a
> success bar this sprint); the resulting `dreamball.wasm` size is recorded, not
> gated.

## Functional Requirements

FR1. [MVP] The system shall allow a new wire type to be defined as a Zig struct declaring a `type_string` and `format_version`, and shall treat envelopes bearing that `type_string` as first-class typed DreamBalls.
FR2. [MVP] The system shall generate the downstream artifacts (TS types, Valibot schema, `cbor.ts` codec, JSON-Schema) for a Zig-defined type via `zig build schemagen`, with no hand-authored JSON Schema serving as a source.
FR3. [MVP] The system shall encode and decode a typed DreamBall through canonical dCBOR (length-first map-key ordering, shortest-form integers, no floats in the payload common subset), producing byte-identical output for the same logical value.
FR4. [MVP] The system shall validate a decoded DreamBall against its type's schema and reject any instance that does not satisfy it, and shall reject any envelope whose CBOR is not in canonical form.
FR5. [MVP] The system shall provide a generic action envelope whose `kind` is an open string (not a closed enum), carrying an arbitrary typed `body` payload, a hybrid logical clock `[l, c]`, and zero-or-more `parent_hashes`.
FR6. [MVP] The system shall expose a WASM authoring export that encodes and Ed25519-signs a generic action envelope from caller-supplied fields plus a 64-byte secret key, returning the canonical signed bytes via the packed-`u64` (`ptr<<32 | len`, `0`-on-error) convention.
FR7. [MVP] The system shall provide a TypeScript loader wrapper (`src/lib/wasm/loader.ts`) exposing generic-action authoring/signing and verification to JavaScript, producing byte-identical output and identical verification verdicts for the same inputs whether the WASM is loaded in the browser or under Bun.
FR8. [MVP] The system shall compute `content_hash` as the Blake3-256 digest of the canonical envelope bytes, and shall enforce a golden vector asserting that the bytes and digest are identical across the Zig CLI and the WASM build (this is the concrete mechanism that satisfies NFR1).
FR9. [MVP] The system shall verify a generic action envelope by checking the Ed25519 signature against the envelope's actor identity and by enforcing canonical form on decode, returning a distinct result for "verified", "signature failed", and "parse/canonical error".
FR10. [MVP] The system shall carry the logical clock `[l, c]` natively within the action envelope such that it is covered by `content_hash` (composes beads `Dreamball-fch`).
FR11. [MVP] The system shall keep every integration gate green with the new type and export: `zig build test`, `zig build smoke`, `scripts/server-smoke.sh`, Vitest, and `svelte-check`.
FR12. [Growth] The system shall define renderer dispatch by field-presence as a named contract, in which a renderer declares the fields it requires and dispatch selects renderers whose required fields are present.
FR13. [Growth] The system shall provide a documented path for a consumer to introduce their own type without modifying core protocol code, including for authors who do not write Zig.
FR14. [Growth] The system shall guarantee that a consumer op encoded via `@ipld/dag-cbor` and the same op encoded through the native export produce byte-identical output on the documented common value subset.
FR15. [Vision] The system shall express Memory Palace's Room / Aqueduct / Inscription / Mythos as DreamBall types through the same open type+renderer mechanism a third party uses, removing their monolithic special-casing.
FR16. [Vision] The system shall emit all downstream artifacts automatically from the Zig types via a `@typeInfo` comptime generator (beads `Dreamball-m97.2`), replacing hand-maintained generated bodies.
FR17. [Vision] The system shall support ML-DSA-87 (PQ) dual-signature authoring of the action envelope in the WASM path (currently CLI-only).

## Non-Functional Requirements

NFR1. [determinism] Canonical dCBOR encoding shall be byte-identical across the browser WASM, Bun WASM, and native CLI for any logical value in the supported subset; this invariant is enforced by golden vectors in CI.
NFR2. [compatibility] A single `dreamball.wasm` binary shall load and run in both the browser and Bun, with host randomness supplied through the single `env.getRandomBytes` import and no other host seam.
NFR3. [security] All present signatures shall be verified (Ed25519 against `actor`/`identity`); malformed-length or non-canonical input shall be rejected rather than accepted. Browser/Bun authoring is Ed25519-only; PQ signing is CLI-side this slice.
NFR4. [maintainability] Zig types are the canonical source; no second hand-maintained implementation of a wire type may be introduced. Until the `@typeInfo` generator lands, generated TS/Valibot/`cbor.ts`/JSON-Schema are propagated by hand and kept consistent by the byte-equivalence gate.
NFR5. [size] The gzip size budget is relaxed for this slice; the resulting raw and gzipped `dreamball.wasm` sizes shall be recorded in the build notes (measured, not gated). A soft ceiling of 300 KB gzip is recorded only to catch silent drift — exceeding it flags the size for future attention, it does not fail the build this slice.

## Scope Boundaries

### In Scope
- A generic, open-kind, typed-body action envelope with native HLC + `parent_hashes`.
- WASM authoring export(s) + a TS loader wrapper for authoring/signing/verifying it.
- The Zig-canonical pipeline for defining a new type and generating downstream artifacts.
- Schema-satisfaction validation on the TS side + canonical-form enforcement on decode.
- Cross-runtime `content_hash` byte-identity with golden vectors.
- Keeping all integration gates green.

### Out of Scope
- Renderer-dispatch-by-field-presence contract (FR12 — Growth).
- Self-serve type registration for non-Zig authors (FR13 — Growth).
- dag-cbor ↔ native byte-parity guarantee (FR14 — Growth).
- Memory Palace extraction (FR15 — Vision) and the `@typeInfo` generator (FR16 — Vision).
- PQ/ML-DSA-87 WASM authoring (FR17 — Vision).
- **Anything networking/sync/CRDT-merge** — DreamBall is a wire-format container, not transport (VISION.md §8, §17 guardrail 1). Merge rules, conflict resolution, and peer sync are the consumer's.
- Kanban-specific semantics — the envelope stays domain-neutral (§17 guardrail 3).

## MVP / Growth / Vision Tiers

### MVP
- FR1–FR4: define a type in Zig-canonical pipeline; generate downstream; canonical encode/decode; schema + canonical-form validation.
- FR5: generic open-kind, typed-body, HLC, `parent_hashes` action envelope.
- FR6–FR7: WASM authoring export + TS loader wrapper (browser + Bun).
- FR8–FR10: `content_hash` Blake3 + cross-runtime golden vector; verify; native HLC.
- FR11: all gates green.

### Growth
- FR12: renderer-dispatch-by-field-presence as a named contract.
- FR13: consumer type-registration ergonomics (incl. non-Zig authors).
- FR14: dag-cbor ↔ native byte-parity on the common subset.

### Vision
- FR15: extract Memory Palace into a first-class type + renderer module.
- FR16: `@typeInfo` Zig→targets comptime generator (m97.2).
- FR17: PQ dual-sig authoring in WASM.

## Constraints

- **Zig-canonical (2026-06-25 ADR).** New/changed wire types are edited as Zig structs first, then propagated to generated TS/Valibot/`cbor.ts`/JSON-Schema. The `@typeInfo` generator (m97.2) is not built yet, so this propagation is **manual** this slice, guarded by the byte-equivalence gate.
- **Canonical dCBOR determinism** (length-first map ordering, shortest-int, no floats in the common subset) must hold so `content_hash` is portable.
- **Ed25519-only** authoring in browser/Bun; PQ is CLI-side (deferred).
- **One binary, two runtimes**; network-agnostic.
- **Every commit keeps all gates green** (`zig build test` / `smoke`, `server-smoke.sh`, Vitest, `svelte-check`) — and "verified" requires `zig build smoke`, not just narrow tests (per CLAUDE.md).
- Extension surfaces: `src/wasm_main.zig` (packed-`u64` exports), `src/protocol_v2.zig` / `src/envelope_v2.zig` (type structs + `encodeX`/`decodeX`), `src/dcbor.zig` (canonical helpers), `src/lib/wasm/loader.ts`, `src/lib/generated/*`.

## Assumptions & Risks

- **[Technical] The `@typeInfo` generator is not built (m97.2).** Impact: every new/changed type needs hand-maintained TS/Valibot/`cbor.ts`/JSON-Schema, raising drift risk. Mitigation: lean on the byte-equivalence gate + golden vectors; keep the MVP type surface small (one generic action type).
- **[Ambiguous] "Open kind" wire representation is unspecified.** Bare string vs namespaced (e.g. `"worldtree/kanban-card.move"`)? Impact: affects collision-safety and renderer dispatch. Mitigation: decide in design; default to a namespaced open string. (Open Question.)
- **[Ambiguous] HLC semantics are not yet specified (`Dreamball-fch`).** `[l, c]` types, tick rules, and tie-break ordering need a protocol note before encoding. Impact: encoding HLC into `content_hash` prematurely risks a breaking change. Mitigation: specify HLC in PROTOCOL.md as part of this slice or carry it provisionally and freeze before GA.
- **[Assumption] Consumers are not Zig authors, yet the canonical pipeline is Zig.** Impact: true self-serve third-party type authoring may not be reachable in MVP; the realistic MVP mechanism is the **generic open-kind, typed-body envelope** (consumer defines+validates their payload shape on their side), with first-class Zig types added by the maintainer. Mitigation: state this boundary explicitly; full non-Zig authoring is FR13 (Growth). (Open Question.)
- **[Ambiguous] Validation authority — Zig decode vs Valibot.** Which is canonical for "satisfies schema"? Impact: divergent accept/reject between runtimes. Mitigation: define Zig canonical-form + decode as the gate of record; Valibot mirrors it (generated from the same source).
- **[Technical] Does the generic op envelope supersede or coexist with the closed `ball.action`?** Impact: two action types, or a `format_version` bump of `ball.action` to add open-kind/body/HLC. Mitigation: decide in design — preferred direction is to extend `ball.action` (open the kind, add `body` + HLC) rather than fork a new type, preserving the palace action as a constrained profile.
- **[Technical] Size-budget relaxation.** Impact: `dreamball.wasm` may exceed the prior 64 KB gzip ceiling once the v2 encode path is linked into the WASM (it is currently v1-only). Mitigation: relaxation is approved for this slice; record the new size; revisit size work later.

## Open Questions

1. Open-kind wire format: bare string vs namespaced/authority-prefixed?
2. HLC exact shape and tie-break semantics (resolve `Dreamball-fch` before freezing `content_hash`).
3. MVP authoring boundary: does "define your own type" in MVP mean (a) open-kind + typed body only, with first-class Zig types added by us, or (b) a self-serve path for consumer-defined types? (Leaning a; b is FR13/Growth.)
4. Extend `ball.action` (version bump) vs introduce a new generic action type?
5. Canonical validation authority: Zig decode as the gate of record, Valibot mirroring it?

## Existing System Context

- **Closed `ball.action`** lives in `src/protocol_v2.zig` (`Action` struct, format_version 3; `ActionKind` closed 9-value enum) and `src/envelope_v2.zig` (`encodeAction`/`decodeAction`, ~line 544) — a fixed 5-key core map, no payload/body, no HLC. This is what the generic envelope extends or supersedes.
- **Authoring exports** in `src/wasm_main.zig` follow the packed-`u64` convention with a `lastSecret` side-channel (`mintDreamBall`, `growDreamBall`, `signActionEnvelope`); the v2 encode path (`envelope_v2`) is **not yet linked into the WASM** (it imports v1 `envelope.zig`).
- **Canonical CBOR** machinery is in `src/dcbor.zig` (length-first key ordering at `:44`; `assertCanonical`); golden vectors in `src/golden.zig`.
- **Codegen** flows Zig → `src/lib/generated/*` via `zig build schemagen` (`tools/schema-gen/`); the `@typeInfo` comptime generator (m97.2) is not built — generated bodies are currently hand-maintained against a byte-equivalence gate.
- **TS surface**: `src/lib/wasm/loader.ts` (wraps `parseBall`/`verifyBall`/`signActionEnvelope`/`blake3`), `src/lib/parse.ts`, generated Valibot schemas.
- **Consumer-facing ABI** already documented this session in [`docs/abi/wasm-authoring-abi.md`](abi/wasm-authoring-abi.md).
- Related beads: `Dreamball-hp6` (generic op export — re-scoped from "wire the closed encoder"), `Dreamball-fch` (HLC), `Dreamball-t2d` (loader wrappers), `Dreamball-m97` (nested decoders + Zig→targets generator).
