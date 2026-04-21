# Epic 1 — Speak palace on the wire

5 stories · LOW–MED complexity · 2 thorough / 2 smoke / 1 medium-mech

## Story 1.1 — WASM ML-DSA-87 verify gate

**User Story**: As a developer, I want the browser-side `jelly.wasm` binary to verify ML-DSA-87 signatures against a Zig-emitted golden fixture, so every downstream palace envelope can rely on hybrid signature verification end-to-end rather than a server subprocess.
**FRs**: NFR12 (primary), NFR17 (build-gate), TC5 (budget), Assumption A12 validation.
**Decisions**: D-010 (CRITICAL — dictates Option 1 test shape), TC5 (≤200KB raw / ≤64KB gzipped).
**Complexity**: medium · **Test Tier**: thorough

### Acceptance Criteria
- **AC1** [happy]: Given `zig build export-mldsa-fixture` writes `fixtures/ml_dsa_87_golden.json` with `{pk, msg, sig}` from `src/ml_dsa.zig`, When `bun run test:unit -- --run src/lib/wasm/verify.test.ts` runs, Then `verifyMlDsa87(fx.pk, fx.msg, fx.sig)` returns `true` in both Vitest+Node and Playwright+Chromium.
- **AC2** [edge — sig tamper]: Given a golden fixture, When `fx.sig` byte 0 is bit-flipped, Then `verifyMlDsa87` returns `false`; no exception escapes the WASM boundary.
- **AC3** [edge — msg tamper]: Given a golden fixture, When `fx.msg` byte 0 is bit-flipped (sig+pk unchanged), Then `verifyMlDsa87` returns `false`.
- **AC4** [budget]: Given fresh `zig build wasm` output, When `stat`+gzip inspected, Then raw ≤204800 bytes AND gzip ≤65536 bytes; CI fails commit on excess.
- **AC5** [cross-runtime invariant]: Given the produced `jelly.wasm`, When import table is dumped (`wasm-tools`), Then exactly one host import exists — `env.getRandomBytes`.
- **AC6** [failure-mode gate]: Given any of AC1–AC5 fail, Then commit is HARD BLOCK per D-010; `docs/known-gaps.md §1` reopened; `/replan` invoked before Story 1.2+.

### Technical Notes
Follow D-010 Option 1 exactly. Extend `src/lib/wasm/verify.test.ts` (no parallel test file). Emit fixture via new `zig build export-mldsa-fixture` step that reuses the known-answer test vector already inside `src/ml_dsa.zig`. Export `verifyMlDsa87(pk, msg, sig): boolean` through the same packed-ptr-len convention existing WASM exports use. Bundle-size assertion via `statSync` in the same test file — assertion travels with the verify coverage.

### Scope Boundaries
- DOES: ship WASM verify export, fixture emitter, 3 verify tests + bundle-size + import-shape assertions, close `docs/known-gaps.md §1` when AC1–AC5 green.
- Does NOT: touch `protocol_v2.zig` structs (Story 1.2), exercise `jelly.action` envelope round-trip (Story 1.3), lock palace-envelope golden bytes (Story 1.4), or wire codegen to TS (Story 1.5).

---

## Story 1.2 — Add 9 palace envelope structs + `field-kind` to `protocol_v2.zig`

**User Story**: As a developer, I want nine new Zig struct types (`Layout`, `Timeline`, `Action`, `Aqueduct`, `ElementTag`, `TrustObservation`, `Inscription`, `Mythos`, `Archiform`) plus a `field-kind` attribute on `Field` defined in `src/protocol_v2.zig` at correct `format-version`, so downstream encoders, codegen, and golden fixtures have a single authoritative type home.
**FRs**: Enables FR1, FR9, FR26 (wire shape only); prerequisite for Stories 1.3+1.4+1.5.
**Decisions**: TC14 (Timeline+Action at v3, others v2), TC7 (dCBOR ordering), D-016 (schema naming).
**Complexity**: small · **Test Tier**: smoke

### Acceptance Criteria
- **AC1**: Given 9 struct definitions per PROTOCOL.md §13.2–13.9, When `zig build` runs, Then build succeeds zero errors; each struct has `format_version` constant matching TC14.
- **AC2** [field-kind]: Given existing `Field` struct, When `field_kind: ?[]const u8` attribute slot added, Then "palace" and "room" round-trip through existing Field encoder/decoder without bumping format-version (attribute-level addition per PROTOCOL.md §13.1).
- **AC3** [edge — unknown field-kind]: Given a Field decoded with `field-kind: "sanctuary"`, Then value preserved verbatim (open-enum rule).
- **AC4** [error — palace-without-mythos detection primitive]: Given a Field tagged `field-kind: "palace"` without `jelly.mythos`, When a `palaceInvariants` helper processes it, Then helper returns explicit error naming PROTOCOL.md §13.11 fixture 1 (full `jelly verify` enforcement is Epic 3).
- **AC5** [compile-gate]: Given all 9 types declared, When `grep -R '"jelly\.\(layout\|timeline\|action\|aqueduct\|element-tag\|trust-observation\|inscription\|mythos\|archiform\)"' src/protocol_v2.zig` runs, Then all 9 type-name string literals present exactly once.

### Technical Notes
Follow existing v2 pattern in `src/protocol_v2.zig` (`Memory`, `KnowledgeGraph`, `EmotionalRegister`, `GuildPolicy`, `QuorumPolicy`, `SecretRef` precedents). Timeline's `head-hashes` is `[][32]u8` set; Action's `parent-hashes` likewise multi-valued. Use `u32` for `format_version`. Do NOT add encoder functions here (Story 1.3). Do NOT touch codegen (Story 1.5). Struct fields snake-case; dCBOR keys stay kebab-case.

### Scope Boundaries
- DOES: define 9 structs + `field-kind` slot + `format_version` constants + minimal struct-shape unit tests.
- Does NOT: encode/decode CBOR (Story 1.3), produce golden bytes (Story 1.4), regenerate TS (Story 1.5), implement verify invariants (Epic 3 FR10/FR2/FR24), or write aqueduct formulas (Epic 2 owns `aqueduct.ts`).

---

## Story 1.3 — Add 9 envelope encoders + decoders + inline round-trip tests

**User Story**: As a developer, I want `encodeLayout`/`encodeTimeline`/`encodeAction`/`encodeAqueduct`/`encodeElementTag`/`encodeTrustObservation`/`encodeInscription`/`encodeMythos`/`encodeArchiform` plus matching decoders in `src/envelope_v2.zig`, so every palace envelope type can materialise to canonical dCBOR bytes and read back bit-identically.
**FRs**: FR1, FR9, FR26 (primary wire shape canonical home), supports FR2/3/4/6/7/14/18/25/27.
**Decisions**: TC7 (dCBOR ordering), TC20 (`#7.25` vs `#7.26` float discipline), TC14 (per-envelope format-version), TC16 (conductance optional accept), TC17 (strength MUST NOT clamp).
**Complexity**: medium · **Test Tier**: thorough

### Acceptance Criteria
- **AC1** [round-trip per type]: Given each of 9 envelope structs, When `encode<Type>(allocator, value)` then matching decoder, Then resulting struct field-for-field equal (9 inline `test "encode<Type> round-trip"` blocks; ≥5 assertions per envelope per NFR16).
- **AC2** [dCBOR ordering]: Given two encodings with attributes inserted in different source-order, When bytes compared, Then identical (canonical ordering per TC7).
- **AC3** [Timeline concurrent heads]: Given `Timeline` with `head-hashes` cardinality ≥2 (PROTOCOL.md §13.11 fixture 3a), When round-tripped, Then all heads preserved as set membership.
- **AC4** [Action multi-parent + deps/nacks]: Given an `Action` with `parent-hashes` cardinality 2 + non-empty `deps` and `nacks`, When encoded then decoded, Then all three multi-valued fields survive bit-identically.
- **AC5** [Aqueduct float discipline]: Given `Aqueduct` with `resistance: 0.3`, `conductance: 0.368`, When encoded, Then numerics use `#7.25` (half) where lossless, `#7.26` (single) otherwise; CBOR major-type byte asserted.
- **AC6** [malformed decode]: Given truncated bytes, When passed to any of 9 decoders, Then returns Zig error (no panic, no silent empty).

### Technical Notes
Clone `encodeMemory` (`src/envelope_v2.zig:286`), `encodeKnowledgeGraph` (`:398`), `encodeEmotionalRegister` (`:430`) — same `(allocator, value)` signature, same tag-201 wrapping, same attribute-sorting. Timeline+Action carry `format-version: 3`; rest carry `2`. Mythos `discovered-in` is opaque `[32]u8`; verify-time resolution is Epic 3. TC16: encoder MUST accept absent `conductance` (`?f32`). TC17: no clamp on `strength`. Each envelope ≥5 inline tests per NFR16.

### Scope Boundaries
- DOES: 9 encoders + 9 decoders, ≥5 inline Zig tests per envelope, use existing `src/cbor.zig`/`src/dcbor.zig` primitives.
- Does NOT: lock golden Blake3 (Story 1.4), emit TS types (Story 1.5), compute aqueduct values (Epic 2 `aqueduct.ts`), enforce mythos chain walks (Epic 3 FR2/FR24), or sign anything (Epic 3 CLI emission sites).

---

## Story 1.4 — Lock golden-fixture Blake3 constants in `src/golden.zig`

**User Story**: As a developer, I want `GOLDEN_*_BLAKE3` hex constants plus matching `test "golden bytes: …"` blocks pinning canonical encodings for every palace envelope shape per PROTOCOL.md §13.11, so any inadvertent change to dCBOR output surfaces as CI failure before corrupting cross-runtime wire compatibility.
**FRs**: NFR16 (primary — golden bytes-lock), NFR18 (round-trip parity anchor).
**Decisions**: PROTOCOL.md §13.11 fixture list (authoritative), TC7, TC14, TC18 (mythos canonical vs poetic split), TC20 (float discipline).
**Complexity**: medium · **Test Tier**: thorough

### Acceptance Criteria
- **AC1** [13–14 fixtures locked]: Given `src/golden.zig` extended with `GOLDEN_PALACE_FIELD_BLAKE3`, `GOLDEN_LAYOUT_BLAKE3`, `GOLDEN_TIMELINE_QUIESCENT_BLAKE3`, `GOLDEN_TIMELINE_CONCURRENT_BLAKE3`, `GOLDEN_ACTION_SINGLE_PARENT_BLAKE3`, `GOLDEN_ACTION_MULTI_PARENT_BLAKE3`, `GOLDEN_ACTION_DEPS_NACKS_BLAKE3`, `GOLDEN_AQUEDUCT_BLAKE3`, `GOLDEN_ELEMENT_TAG_BLAKE3`, `GOLDEN_TRUST_OBSERVATION_BLAKE3`, `GOLDEN_INSCRIPTION_BLAKE3`, `GOLDEN_MYTHOS_CANONICAL_GENESIS_BLAKE3`, `GOLDEN_MYTHOS_CANONICAL_SUCCESSOR_BLAKE3`, `GOLDEN_MYTHOS_POETIC_BLAKE3`, `GOLDEN_ARCHIFORM_BLAKE3`, When `zig build test` runs, Then all golden tests pass.
- **AC2** [first-run bootstrap]: Given fresh clone with `__RECOMPUTE_ON_FIRST_RUN__` sentinel, When test runs, Then prints observed hex per pattern in existing `GOLDEN_MEMORY_CONNECTION_BLAKE3` test (`src/golden.zig:75`) and exits non-zero.
- **AC3** [drift detection]: Given any single byte change in any encoder, When test runs, Then affected golden test fails with "GOLDEN MISMATCH" diff.
- **AC4** [count integrity]: Given fixture count, When grepped, Then count is exactly `2 (pre-existing) + N (new) = N+2`. Reconcile fixture count (13 vs 14) against PROTOCOL.md §13.11 lines 1156–1181 at story kickoff.
- **AC5** [canonical vs poetic mythos]: Given canonical-genesis and poetic mythos fixtures, Then differ in attribute(s) per PROTOCOL.md §13.8 / TC18; lock distinct Blake3 hashes.

### Technical Notes
Extend `src/golden.zig`. Reuse pattern from `GOLDEN_ZERO_SEED_BLAKE3` (line 16) and `GOLDEN_MEMORY_CONNECTION_BLAKE3` (line 35): constant at module top, test calls `blake3Hex(bytes)` and compares, `__RECOMPUTE_ON_FIRST_RUN__` bootstrap branch (lines 68–76). Each fixture's source struct comes from PROTOCOL.md §13.11; ambiguous bytes get deterministic padding documented inline. Reconcile count (13 vs 14) at kickoff — open question.

### Scope Boundaries
- DOES: 13–14 Blake3 hex constants + matching tests, run on every commit via `zig build test`, reconcile count with PROTOCOL.md.
- Does NOT: change PROTOCOL.md §13 text unless count requires, ship TS round-trip (Story 1.5), implement encoders (Story 1.3), test WASM verify (Story 1.1).

---

## Story 1.5 — Regenerate TS codegen + Vitest round-trip parity

**User Story**: As a developer, I want `bun run codegen` to emit 9 new envelope types into `src/lib/generated/types.ts` + `schemas.ts` + `cbor.ts` and Vitest round-trip parity tests to prove CLI-minted Zig CBOR decodes through TS decoder and re-encodes byte-identically, so NFR18's cross-runtime parity is mechanised into build-gate and the single-source-of-truth invariant holds.
**FRs**: NFR18 (primary), FR1/FR9/FR26 (TS surface), supports every FR carrying a palace envelope through Svelte lib.
**Decisions**: TC6 (Zig↔TS only through codegen+HTTP), CLAUDE.md cross-runtime invariant, NFR17.
**Complexity**: medium · **Test Tier**: smoke

### Acceptance Criteria
- **AC1** [codegen emission]: Given Story 1.2's 9 structs in `src/protocol_v2.zig`, When `bun run codegen` runs, Then `types.ts` exports 9 new TypeScript types, `schemas.ts` exports 9 Valibot schemas, `cbor.ts` exports 9 decoders — without hand edits.
- **AC2** [round-trip parity with CLI]: Given a Zig test or CLI path that mints each envelope type and writes CBOR to a temp file, When Vitest reads bytes, decodes via `cbor.ts`, and re-encodes via WASM module, Then resulting bytes byte-identical (one test per envelope with CLI mint path: `Mythos`, `Timeline`, `Action`, `Aqueduct`; others get TS-decode-only assertions).
- **AC3** [Valibot validation]: Given each generated schema, When passed well-formed envelope, Then `safeParse` returns success; malformed returns typed error.
- **AC4** [no hand-written schemas]: Given post-codegen state, When grepped, Then zero hand edits (codegen footer `// DO NOT EDIT — generated by tools/schema-gen/main.zig` preserved).
- **AC5** [build gate]: Given AC1–AC4 pass, When `bun run check` then `bun run test:unit -- --run` execute, Then both green (NFR17).
- **AC6** [drift alarm]: Given a Zig struct field renamed after codegen, When `bun run check` runs without re-codegen, Then svelte-check surfaces type error citing the renamed field.

### Technical Notes
Extend `tools/schema-gen/main.zig` with 9 new emitters following existing `Memory`/`KnowledgeGraph` pattern. Generated files MUST NOT be hand-edited (CLAUDE.md cross-runtime invariant load-bearing). Round-trip tests live in `src/lib/generated/__tests__/` or inline. For envelopes whose CLI path lands in Epic 3 (`Layout`/`ElementTag`/`TrustObservation`/`Archiform`/`Inscription`), AC2 ships TS-decode-only assertion now; full CLI→TS round-trip added in Epic 3 consumer story.

### Scope Boundaries
- DOES: extend `tools/schema-gen/main.zig`, regenerate TS, add Vitest round-trip parity (≥1 per envelope), ensure `bun run check` + `test:unit` green.
- Does NOT: implement CLI mint verbs (Epic 3), ship lens components (Epic 5), ship `store.ts` integration (Epic 2), exercise WASM ML-DSA-87 verify through TS decoder (Story 1.1 already proved primitive).

---

## Epic 1 Health Metrics
- **Story count**: 5 (target 2–6) ✓
- **Complexity**: 1 small, 4 medium, 0 large
- **Test tier**: 0 yolo, 2 smoke, 3 thorough
- **FR coverage**: FR1/FR9/FR26 (wire shape) → Stories 1.2, 1.3, 1.4. NFR12 → 1.1. NFR16 → 1.3+1.4. NFR18 → 1.5. NFR17 → 1.1, 1.3, 1.4, 1.5. TC5 → 1.1. TC14 → 1.2. TC7 → 1.3. TC20 → 1.3. TC18 → 1.4. TC6 → 1.5.
- **Cross-epic deps**: none (Epic 1 = foundation). Consumed by Epic 2 (FR26 numeric fields), Epic 3 (CLI emits via Story 1.3 encoders + Story 1.5 TS), Epic 5 (renderer consumes Story 1.5 codegen), Epic 6 (embedding-client serialises over Story 1.5 types).
- **Risk gates**: R3 (WASM ML-DSA verify) → Story 1.1; HARD BLOCK on failure per D-010.
- **Open questions**: (1) Story 1.4 fixture count reconciliation (13 vs 14) — read PROTOCOL.md §13.11 lines 1156–1181 at kickoff. (2) Story 1.5 CLI-mint coverage split — confirm which envelopes ship CLI mint path in Epic 3.
