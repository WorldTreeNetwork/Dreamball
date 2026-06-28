---
sprint: sprint-003
phase: 2A
created: 2026-06-27
decisions: D-037..D-043
steering_mode: GUIDED
status: accepted (all approved by user 2026-06-27)
---

# Architecture Decisions — Sprint 003: Open Type System

## D-037: Wire-type strategy — extend `ball.action` with open kind + typed body + HLC (Q1)

**Date**: 2026-06-27  **Sprint**: sprint-003  **Significance**: CRITICAL  **Decided by**: user  **Status**: accepted

**Context**: The closed `ball.action` (`protocol_v2.zig:231`, `ActionKind` enum at :188, `encodeAction` at `envelope_v2.zig:544`) carries a fixed 5-key core map (`type`, `actor`, `action-kind`, `parent-hashes`, `format-version`) with no payload field and no logical clock. FR5 requires a generic action envelope with open kind, typed body, HLC, and parent_hashes. Q1 asks: extend `ball.action` (open its kind, add body + HLC, bump format_version 3→4) or introduce a new type (e.g. `ball.op`)?

**Decision (recommended)**: **Extend `ball.action`** — bump `format_version` 3→4, replace the closed `ActionKind` enum with an open `kind: []const u8` string, add `body: ?[]const u8` (opaque CBOR bytes) and `hlc: [2]u64` fields. The new core map gains three keys (`body`, `hlc`, `kind` replaces `action-kind`) and the total goes from 5 to 7 core keys. The existing 9 palace `action-kind` values become a constrained profile — they remain valid `kind` strings (e.g. `"palace-minted"`) but are no longer the only legal values.

Rationale:
1. **One type to rule, one decode path.** A new `ball.op` would fork the decode dispatch in `envelope_v2.zig`, `wasm_main.zig`, `loader.ts`, and every consumer. Extending `ball.action` keeps a single envelope type and a single WASM export.
2. **D-019 (action manifest) is already the universal action contract.** It speaks of "actions" — not "ops" and "actions." Introducing `ball.op` would force every manifest projection (CLI, REST, MCP, renderer) to handle two envelope shapes.
3. **Precedent: Aqueduct already uses an open `kind: []const u8` string** (`protocol_v2.zig:279`). Opening `ball.action`'s kind follows the same pattern.
4. **`format_version` is the backward-compat mechanism.** Decoders already branch on `format_version` (`decodeAction` reads it at :569); version 4 signals the new shape, version 3 signals the old. Old envelopes remain valid — the decoder treats `format_version == 3` as the palace profile (closed enum, no body, no HLC).
5. **The `type_string` stays `"ball.action"`.** Type dispatch in the envelope layer routes on the string; keeping it avoids a second decode branch.

**Alternatives**:
1. **Introduce `ball.op` as a new generic type.** Steelman: cleanly separates the palace's constrained vocabulary from the open-world semantics; avoids any risk of breaking existing `ball.action` golden vectors. Rejected because: (a) it forks the decode path in every consumer (WASM, TS, CLI); (b) `ball.action` becomes a dead-end type nobody extends, while `ball.op` duplicates 80% of its structure; (c) D-019's action manifest unifies actions — two types undermines that unity; (d) `format_version` already handles the backward-compat concern cleanly.
2. **Make `ball.action` fully backward-compatible (no format_version bump, body/HLC optional).** Rejected: changing the `action-kind` from a closed enum to an open string is a semantic break — existing decoders that pattern-match on the 9 known values would reject unknown kinds. A clean version bump is honest and lets decoders branch explicitly.

**Consequences**:
- **Cluster A**: all stories build on the extended `ball.action` (format_version 4). The Zig `Action` struct in `protocol_v2.zig` gains `body`, `hlc`, and changes `action_kind: ActionKind` to `kind: []const u8`. `ActionKind` stays as a convenience enum for palace consumers but is no longer the wire type.
- **Cluster B**: the WASM export encodes the v4 `ball.action`, not a new type. One export, one TS wrapper.
- **Cluster C**: golden vectors for format_version 3 remain unchanged (regression gate). New golden vectors cover format_version 4.
- **FR5, FR6, FR7, FR9, FR10**: all satisfied by the extended `ball.action`.
- **Existing palace code**: continues to author format_version 3 envelopes (or migrates to 4 with palace-specific kind strings). No breaking change to existing data.

**Aligned with existing pattern**: `type_string` + `format_version` + fields (the section 13 type pattern); `Aqueduct.kind: []const u8` (open string kind precedent); D-019 action manifest (single action contract).

---

## D-038: Open-kind wire representation — bare string with a recommended namespace convention (Q2)

**Date**: 2026-06-27  **Sprint**: sprint-003  **Significance**: HIGH  **Decided by**: user  **Status**: accepted

**Context**: Q2 asks whether the open `kind` field is a bare string or a namespaced/authority-prefixed string (e.g. `"worldtree/kanban-card.move"`). Affects collision safety and future renderer dispatch (FR12, Growth).

**Decision (recommended)**: **Bare `[]const u8` on the wire with a RECOMMENDED (not enforced) dot-namespaced convention.** The wire type is `text` (CBOR major type 3) — any valid UTF-8 string. The protocol specifies a convention: `<namespace>.<noun>.<verb>` (e.g. `"worldtree.kanban-card.move"`, `"palace.room.add"`), documented in PROTOCOL.md. The convention uses dots (not slashes) to avoid URI-path confusion. The existing 9 palace kinds are aliased as `"palace.minted"`, `"palace.room-added"`, etc., with the old bare names (`"palace-minted"`, `"room-added"`) remaining valid for format_version 3 envelopes.

Rationale:
1. **Bare string is simplest and matches the existing pattern.** `Aqueduct.kind` (`protocol_v2.zig:279`) is already a bare `[]const u8` with documented conventional values (`"gaze"`, `"visit"`, `"transmit"`). Enforcing a namespace at the wire layer adds validation complexity for zero MVP benefit.
2. **Convention over enforcement.** The namespace dot convention gives collision safety without a validation gate. Consumers who ignore it get a working but collision-prone string; consumers who follow it get safe dispatch. This is the DNS/reverse-DNS pattern (Java packages, Android intents) applied minimally.
3. **dCBOR text encoding is already deterministic.** Any UTF-8 text string round-trips through canonical dCBOR with no special handling. No new CBOR machinery needed.
4. **Renderer dispatch (FR12, Growth) needs the convention but not enforcement.** When renderers key on kind, the namespace disambiguates. But FR12 is Growth — enforcement can wait.

**Alternatives**:
1. **Enforce a namespace at the protocol layer (reject un-namespaced strings).** Steelman: guarantees collision-free kinds globally; prevents ad-hoc naming. Rejected because: (a) the existing 9 palace kinds are un-namespaced bare strings — enforcing would break backward compat or require a special exemption list; (b) validation complexity in the Zig decoder for zero MVP benefit; (c) convention + documentation achieves the same goal for cooperative consumers.
2. **Use forward-slash namespacing (`"worldtree/kanban-card.move"`).** Rejected because: (a) slash reads as a path separator, inviting URI-path confusion; (b) dots are the established convention in Java/Android/protobuf namespace patterns and compose naturally with the existing palace kind strings.

**Consequences**:
- **Cluster A**: `kind` is `[]const u8` in the Zig struct. No validation beyond non-empty (zero-length kind is an error).
- **Cluster C**: PROTOCOL.md gains a "Kind Namespace Convention" section documenting the dot convention.
- **FR5**: satisfied — open string, no enum.
- **FR12 (Growth)**: the convention provides the dispatch key when renderer dispatch lands.
- **Backward compat**: format_version 3 palace envelopes keep their bare `"palace-minted"` etc. Format_version 4 palace actions use `"palace.minted"` by convention but the wire accepts both.

**Aligned with existing pattern**: `Aqueduct.kind: []const u8` (bare string, conventional values); dCBOR text determinism (`dcbor.zig`).

---

## D-039: HLC representation — `[l, c]` as CBOR array of two unsigned integers (Q4)

**Date**: 2026-06-27  **Sprint**: sprint-003  **Significance**: HIGH  **Decided by**: user  **Status**: accepted

**Context**: Q4 asks for the exact HLC shape, wire encoding, tie-break ordering, and whether it is covered by `content_hash`. This resolves beads `Dreamball-fch`. FR10 requires the HLC to be carried natively in the envelope.

**Decision (recommended)**: The HLC is a **CBOR array of two unsigned integers `[l, c]`**:

- **`l`** (logical physical): `uint64` — millisecond-resolution wall-clock timestamp, advanced on every local event to `max(local_wall_ms, last_l) + 1`. This is the "physical" component in Lamport's hybrid construction.
- **`c`** (counter): `uint64` — a monotonically increasing counter within the same `l` value, starting at 0. Incremented when a new event has the same `l` as the previous event. Reset to 0 when `l` advances.
- **Wire encoding**: CBOR array (major type 4, length 2) containing two CBOR unsigned integers (major type 0). No CBOR tags. Shortest-int encoding per dCBOR rules (`dcbor.zig:44`).
- **Zig type**: `hlc: [2]u64` in the `Action` struct (index 0 = `l`, index 1 = `c`).
- **Wire key**: `"hlc"` (3 bytes) in the core map. In dCBOR length-first ordering, `"hlc"` sorts before `"body"` (same length 3 < 4) — wait, `"hlc"` is 3 chars, `"body"` is 4. So the 7-key core map in length-first order is: `"hlc"(3), "kind"(4), "body"(4), "type"(4), "actor"(5), "parent-hashes"(13), "format-version"(14)`. Among equal-length keys: `"body" < "kind" < "type"` lexicographically.
- **Tie-break ordering**: `(l1, c1) < (l2, c2)` iff `l1 < l2`, or `l1 == l2 && c1 < c2`. This is standard HLC ordering. When `l` and `c` are equal, the events are concurrent — the consumer's merge rule breaks the tie (DreamBall does not impose a merge strategy per VISION.md §17 guardrail 1).
- **Covered by `content_hash`**: Yes. The HLC is part of the core map, which is part of the canonical envelope bytes. `content_hash = Blake3(canonical_envelope_bytes)` therefore covers it. Changing the HLC changes the hash.
- **Mandatory in format_version 4**: The HLC field is required (not optional) in v4 envelopes. A v4 envelope without an HLC is a decode error. This is a protocol commitment — the clock is structural, not decorative.

Rationale:
1. **Two-integer array is the simplest representation that captures HLC semantics.** No custom CBOR tags, no nested maps, no string encoding. It composes with dCBOR determinism trivially.
2. **Millisecond resolution matches JS `Date.now()` and Bun's clock**, which is the primary authoring environment (browser + Bun). Sub-millisecond precision is unnecessary for causal ordering — the counter handles intra-millisecond events.
3. **`uint64` is future-proof.** A `uint64` millisecond timestamp overflows in the year 584 million. The counter is unbounded within a tick.
4. **No CBOR tag avoids complexity.** `Tag.epoch_time` (tag 1) is used for `timestamp` in the existing `ball.action` attributes (`envelope_v2.zig:592`), but the HLC is not a plain epoch — it is a logical-physical pair. A bare array is cleaner than inventing a new tag.

**Alternatives**:
1. **CBOR map `{"l": uint64, "c": uint64}`**. Steelman: self-describing, extensible (could add a node-id field later). Rejected because: (a) maps are heavier (key strings + ordering overhead); (b) the HLC is a fixed-arity tuple, not a variable-structure record; (c) extensibility is handled by `format_version` bumps, not by HLC field additions.
2. **Single packed `uint64` (48-bit physical + 16-bit counter)`**. Steelman: single integer, no array overhead. Rejected because: (a) 16-bit counter limits to 65535 events per millisecond — tight for batch imports; (b) 48-bit physical overflows in year 10889 (fine) but requires bit-manipulation in JS which is awkward with BigInt; (c) two separate integers are more debuggable and the CBOR overhead is 3 bytes (array header + two int headers for small values).
3. **Microsecond or nanosecond resolution.** Rejected because: JS `Date.now()` is millisecond; higher resolution would require `performance.now()` (not monotonic across tabs) or a server clock. The counter handles sub-millisecond events.

**Consequences**:
- **Cluster A**: `Action` struct gains `hlc: [2]u64`. `encodeAction` emits `"hlc"` → `[l, c]` in the core map. `decodeAction` reads it back.
- **Cluster C**: golden vectors include the HLC. `content_hash` covers it.
- **FR10**: satisfied — native HLC in the envelope, covered by content_hash.
- **PROTOCOL.md**: gains an "HLC Specification" section documenting the shape, ordering, and mandate.
- **Consumer impact**: the consumer calls `authorAction({ ..., hlc: [Date.now(), 0] })`. The TS type for HLC is `[number, number]` (both within safe integer range for practical values).

**Aligned with existing pattern**: CBOR array of integers (same as `parent-hashes` array of byte strings); dCBOR shortest-int encoding; no custom tags for data that is not an epoch timestamp.

---

## D-040: MVP authoring boundary — open kind + typed body; first-class Zig types by maintainer only (Q3)

**Date**: 2026-06-27  **Sprint**: sprint-003  **Significance**: HIGH  **Decided by**: user  **Status**: accepted

**Context**: Q3 asks whether MVP "define your own type" means (a) open-kind + typed body where consumers define their payload shape on their side and the Zig pipeline adds first-class types by the maintainer, or (b) a self-serve path for consumer-authored Zig types.

**Decision (recommended)**: **(a) Open kind + typed body for consumers; first-class Zig types added by the maintainer only.** The MVP mechanism for consumer-defined data is the generic `ball.action` v4 envelope: the consumer provides an open `kind` string and an opaque `body` (CBOR bytes they encode themselves using their own schema, e.g. Valibot on their side). The DreamBall protocol encodes, signs, and verifies the envelope — it does not validate the body contents beyond checking that the body is well-formed CBOR. For a consumer type to get typed decode/validation/codegen (FR1-FR2), the maintainer adds a Zig struct and runs `zig build schemagen`. Self-serve non-Zig type authoring is FR13 (Growth).

Rationale:
1. **This is exactly what unblocks World-Tree.** They need to carry their own typed payload (kanban ops, 3D transforms) as signed DreamBalls. The open-kind + opaque body envelope lets them do this today with zero Zig knowledge.
2. **The `@typeInfo` generator is not built (TC5).** Without it, adding a first-class Zig type requires hand-propagation to TS/Valibot/cbor.ts/JSON-Schema. Making this self-serve for non-Zig authors is premature — the pipeline is not automated enough.
3. **Scope discipline.** The sprint is "standard" (8-18 stories). Building a self-serve type-registration path would push it to "ambitious" and diffuse focus from the core deliverable (the generic envelope + WASM surface).

**Alternatives**:
1. **(b) Self-serve consumer-authored Zig types.** Steelman: truly opens the type system — any consumer can add a first-class type without waiting on the maintainer. Rejected because: (a) the codegen pipeline is manual (TC5); (b) Zig is not a language consumers know (the PRD persona says "not Zig authors"); (c) the generic body envelope already covers the consumer's immediate need; (d) FR13 (Growth) is the right home for this.

**Consequences**:
- **Cluster A**: the body field in `ball.action` v4 is `?[]const u8` — optional opaque CBOR bytes. The protocol validates that body bytes are well-formed CBOR (via `assertCanonical`) but does not validate their schema.
- **Cluster B**: the WASM export accepts body bytes from the caller. The TS wrapper passes them through.
- **Cluster D (stretch)**: proves the first-class pipeline by adding a second Zig-defined type (e.g. `object3d`) through the same codegen path. This is maintainer-authored, not consumer-authored.
- **FR1-FR2**: satisfied for maintainer-authored types. Consumer types use the opaque body path.
- **FR13 (Growth)**: explicitly deferred. The stretch goal (Cluster D) de-risks it.

**Aligned with existing pattern**: D-007 (domain verbs + narrow raw escape-hatch) — the generic body is the "raw escape-hatch" for consumer types; first-class Zig types are the "domain verbs."

---

## D-041: Canonical validation authority — Zig decode as gate of record; Valibot mirrors (Q5)

**Date**: 2026-06-27  **Sprint**: sprint-003  **Significance**: MEDIUM  **Decided by**: auto-decided  **Status**: accepted

**Context**: Q5 asks which layer is the canonical validation authority — Zig decode/`assertCanonical` or the generated Valibot schemas. Divergent accept/reject between runtimes would break NFR1 (cross-runtime determinism).

**Decision (recommended)**: **Zig `decodeAction` + `assertCanonical` (`dcbor.zig`) is the canonical validation gate.** Every envelope passes through the WASM decode path in both browser and Bun (same binary, NFR2), so the Zig decoder is the single point of enforcement. Valibot schemas (generated from the Zig types per TC1) provide a **convenience mirror** for TS-side pre-validation and developer ergonomics but are not authoritative. If Valibot accepts something that Zig rejects, the Zig verdict wins. The byte-equivalence gate (golden vectors) detects drift between the two.

Rationale:
1. **The WASM binary is the same in both runtimes.** Browser and Bun load the same `dreamball.wasm` (NFR2). Zig decode is therefore automatically cross-runtime consistent — there is no second implementation to diverge.
2. **`assertCanonical` already enforces dCBOR determinism.** It is called at the top of every decode path (`envelope_v2.zig:604`). Adding schema-satisfaction to the Zig decoder keeps validation co-located with canonicality.
3. **Valibot cannot enforce CBOR-layer invariants** (map-key ordering, shortest-int, tag structure). It validates the *decoded* JS object, not the *wire bytes*. The canonical gate must operate on bytes, which is Zig's domain.

**Alternatives**:
1. **Valibot as co-authoritative (both must accept).** Steelman: belt-and-suspenders; catches bugs in either layer. Rejected because: (a) two authorities means two failure modes and confusing diagnostics ("Zig accepted but Valibot rejected"); (b) Valibot cannot inspect CBOR wire bytes; (c) the golden-vector gate already catches drift between the two.

**Consequences**:
- **Cluster A**: `decodeAction` returns a typed `Action` struct or an error. Schema-satisfaction (FR4) is enforced by the Zig decoder (required fields present, correct types, valid kind string).
- **Cluster C**: Valibot schema is generated from the Zig type and used for TS-side convenience. The byte-equivalence gate asserts that Valibot and Zig agree on the test corpus.
- **FR4**: satisfied — validation is in the decode path.
- **NFR1**: strengthened — single implementation, single binary, no divergence possible.

**Aligned with existing pattern**: Zig-canonical ADR (2026-06-25); `assertCanonical` as the existing decode-time gate; one-binary-two-runtimes (NFR2).

---

## D-042: envelope_v2 WASM linkage — `authorAction` export with packed-u64 convention (TC6)

**Date**: 2026-06-27  **Sprint**: sprint-003  **Significance**: HIGH  **Decided by**: user  **Status**: accepted

**Context**: TC6 notes that `wasm_main.zig` currently imports v1 `envelope.zig` (line 33), not `envelope_v2.zig`. The v2 encode path (`encodeAction`) is not available in the WASM. FR6 requires a WASM export that encodes AND signs a generic action envelope. The existing `signActionEnvelope` is a raw byte-signer (documented in `docs/abi/wasm-authoring-abi.md`) — it does not build an envelope.

**Decision (recommended)**: Add a **new WASM export `authorAction`** that encodes a `ball.action` v4 envelope from caller-supplied fields and Ed25519-signs it in one call. Keep `signActionEnvelope` as the raw byte-signer (backward compat; D-023). The new export follows the packed-u64 convention.

**Export signature** (Zig):
```zig
export fn authorAction(
    kind_ptr: u32, kind_len: u32,           // open kind string (UTF-8)
    body_ptr: u32, body_len: u32,           // opaque CBOR body bytes (0/0 if no body)
    parent_hashes_ptr: u32,                 // ptr to concatenated 32-byte hashes
    parent_hashes_count: u32,               // number of 32-byte hashes (not byte length)
    hlc_l: u64, hlc_c: u64,                // HLC [l, c]
    actor_fp_ptr: u32,                      // 32-byte actor fingerprint
    secret_ptr: u32,                        // 64-byte Ed25519 secret key
) u64                                       // packed (ptr << 32 | len) of signed envelope bytes; 0 on error
```

Behavior:
1. Constructs a `v2.Action` with format_version 4, the open kind, body, parent_hashes, hlc, and actor.
2. Calls `envelope_v2.encodeAction` (extended for v4) to produce canonical dCBOR bytes.
3. Signs the canonical bytes with Ed25519 (same path as `mintDreamBall`).
4. Wraps the signed envelope (core + `signed` attribute) and returns packed bytes.

Implementation:
- Add `@import("envelope_v2.zig")` to `wasm_main.zig` alongside the existing `envelope.zig` import.
- `envelope_v2.encodeAction` is extended to handle the v4 fields (body, hlc, open kind).
- The `lastSecret` side-channel is NOT used — the caller provides their secret key explicitly (same as `signActionEnvelope`).
- `actor_fp_ptr` points to the 32-byte actor fingerprint (the public key half of the identity). This is explicit rather than derived from the secret key to keep the export simple and allow the caller to use a pre-computed fingerprint.

**Alternatives**:
1. **Repurpose `signActionEnvelope` to also build the envelope.** Rejected: breaks the existing ABI contract (D-023); consumers already depend on the raw-signer behavior (World-Tree's worked example in `docs/abi/wasm-authoring-abi.md`).
2. **Pass all fields as a single CBOR-encoded struct.** Steelman: single pointer, extensible. Rejected: (a) requires the caller to CBOR-encode the input, which is what we are trying to avoid (the whole point is the consumer does NOT hand-roll CBOR); (b) parsing CBOR input in the WASM adds complexity and attack surface.
3. **Derive actor from the secret key (skip `actor_fp_ptr`).** Rejected on second thought — actually this is cleaner. Revised: derive the Ed25519 public key from the 64-byte secret (it is `secret[32..64]`), compute the fingerprint, and use it as actor. This saves one parameter. **Revised export**: drop `actor_fp_ptr`; derive actor from `secret_ptr`.

**Revised export signature**:
```zig
export fn authorAction(
    kind_ptr: u32, kind_len: u32,           // open kind string (UTF-8)
    body_ptr: u32, body_len: u32,           // opaque CBOR body bytes (0/0 if no body)
    parent_hashes_ptr: u32,                 // ptr to concatenated 32-byte hashes
    parent_hashes_count: u32,               // number of 32-byte hashes
    hlc_l: u64, hlc_c: u64,                // HLC [l, c]
    secret_ptr: u32,                        // 64-byte Ed25519 secret [seed(32)||pub(32)]
) u64                                       // packed signed envelope bytes; 0 on error
```

Actor = `secret[32..64]` (the Ed25519 public key), which is already the convention in `mintDreamBall` (line 231: `const pk = kp.public_key.toBytes()`).

**Consequences**:
- **Cluster B**: `authorAction` is the primary new export. `signActionEnvelope` retained for backward compat.
- **Cluster B**: `loader.ts` gains an `authorAction(opts)` wrapper that marshals JS arguments to WASM pointers.
- **Size**: linking `envelope_v2.zig` into the WASM adds code. NFR5 is relaxed; measure and record.
- **FR6**: satisfied — WASM export that encodes + signs a generic action envelope.
- **FR7**: satisfied — TS wrapper exposes it to browser + Bun.
- **TC6**: resolved — `envelope_v2` is now linked into the WASM.

**Aligned with existing pattern**: packed-u64 convention (`mintDreamBall`, `growDreamBall`); explicit secret-key parameter (same as `signActionEnvelope`); actor derived from secret (same as `mintDreamBall`).

---

## D-043: Body opacity and content_hash domain separation

**Date**: 2026-06-27  **Sprint**: sprint-003  **Significance**: HIGH  **Decided by**: user  **Status**: accepted

**Context**: The `body` field in the v4 envelope carries consumer-defined CBOR. Two questions arise: (1) Is the body opaque to the protocol (pass-through bytes) or does the protocol parse it? (2) Does `content_hash` need domain separation (prefix/context) or is `Blake3(canonical_envelope_bytes)` sufficient?

**Decision (recommended)**:

**Body opacity**: The body is **opaque CBOR bytes** from the protocol's perspective. The `authorAction` export and `encodeAction` encoder treat it as a `CBOR byte string` (major type 2) embedded in the core map. The protocol validates that the body is well-formed CBOR (via `assertCanonical` on the body bytes) but does NOT validate the body's internal schema — that is the consumer's responsibility (they validate on their side with their own Valibot/Zod/etc. schema). On decode, the body is returned as raw bytes that the consumer parses.

Rationale for opacity: (a) the protocol cannot know every consumer's schema; (b) validating the body would require a schema registry, which is FR13 (Growth); (c) opacity lets the envelope stay domain-neutral (VISION.md §17 guardrail 3).

**Body wire encoding**: The body is encoded as a CBOR byte string wrapping the consumer's canonical CBOR. This is "CBOR-in-CBOR" — the outer byte string is the envelope field, the inner bytes are the consumer's payload. This preserves the body's canonical form through encode/decode round-trips (the envelope encoder does not need to understand the body's internal structure).

**content_hash domain separation**: **Not needed for MVP.** `content_hash = Blake3(canonical_envelope_bytes)` is sufficient because:
1. The envelope bytes are self-describing — they start with CBOR tag 200 and contain the `type` field (`"ball.action"`) and `format-version` (4). There is no ambiguity about what is being hashed.
2. Blake3 is not vulnerable to length-extension attacks (unlike SHA-256), so domain separation adds no security benefit.
3. Adding a domain prefix (e.g. `Blake3("ball.action.v4:" || bytes)`) would diverge from the existing `content_hash` computation for other types, requiring per-type hash logic. Keeping `Blake3(bytes)` uniform is simpler and already the pattern.

If domain separation is needed in the future (e.g., for cross-protocol hash collision avoidance), it can be added as a `format_version` bump — but there is no indication it is needed now.

**Alternatives**:
1. **Protocol validates body against a registered schema.** Rejected: requires a schema registry (FR13, Growth); the protocol stays domain-neutral.
2. **Body as CBOR map (not byte string).** Steelman: avoids CBOR-in-CBOR nesting; body fields are directly in the envelope map. Rejected because: (a) body fields would need to be distinguished from envelope fields by namespace (collision risk); (b) the canonical form of the body would depend on the envelope's map ordering, coupling body and envelope encoding; (c) opacity is lost — the protocol must parse the body to encode/decode the envelope.
3. **Domain-separated content_hash.** Deferred — no current need; can be added via format_version bump if needed.

**Consequences**:
- **Cluster A**: body encoded as CBOR byte string in the core map under key `"body"`. `encodeAction` calls `assertCanonical` on the body bytes before embedding. `decodeAction` returns body as `[]const u8`.
- **Cluster C**: `content_hash` computation is unchanged (`Blake3(canonical_envelope_bytes)`). Golden vectors include bodies.
- **FR3**: satisfied — the body round-trips through canonical dCBOR.
- **FR4**: satisfied for the envelope; body-internal validation is the consumer's.
- **FR8**: satisfied — same hash computation, body included.

**Aligned with existing pattern**: CBOR byte-string embedding (signatures are already byte strings in attributes); `assertCanonical` as the well-formedness gate; `Blake3(envelope_bytes)` as the uniform hash.

---

## Requirements Conflicts

1. **PROTOCOL.md §14 header needs update.** The current header (line 7) says "No hand-written schemas exist anywhere; JSON Schema is vendored locally and all generators consume it" — this reflects the superseded D-018. The Zig-canonical ADR (2026-06-25) already supersedes this but PROTOCOL.md has not been updated. This is not a *new* conflict from sprint-003 decisions, but sprint-003 stories that touch PROTOCOL.md should fix this stale reference.

2. **`action-kind` → `kind` key rename in the core map.** The existing wire key is `"action-kind"` (11 chars). D-037 proposes `"kind"` (4 chars) for v4 envelopes. This changes the dCBOR length-first sort position of the field. No conflict with requirements, but the rename must be reflected in any golden vector update, and documented as a v3→v4 wire change.

3. **No other conflicts identified.** All D-037..D-043 decisions are consistent with FR1-FR11, NFR1-NFR5, TC1-TC6, and the scope boundaries in `requirements.md`.
