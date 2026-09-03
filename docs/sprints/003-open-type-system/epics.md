---
sprint: sprint-003
created: 2026-06-27
epics: 3 in-scope + 1 stretch
stories_total: 13 (12 in-scope + 1 stretch)
---

# Epics — Sprint 003: Open Type System

Decisions in force: D-037 (extend `ball.action`→v4), D-038 (bare-string kind +
dot convention), D-039 (HLC `[l,c]` two uint64, mandatory), D-040 (open-kind+body
for consumers), D-041 (Zig validation authority), D-042 (`authorAction` export),
D-043 (opaque CBOR-in-CBOR body, no hash domain-sep). Gate discipline: every story
keeps `zig build test`/`smoke`, `server-smoke.sh`, Vitest, `svelte-check` green
(TC4); "verified" requires `zig build smoke`.

Story flags: ⚑ = expand to a full story before execution (large / ≥3 decisions /
protocol-commitment). `test_tier`: smoke (default) / thorough / yolo.

---

## Epic A — `ball.action` v4: the generic typed envelope
**Cluster A · FR1, FR3, FR4, FR5, FR10 · Decisions D-037/D-038/D-039/D-041/D-043**
Foundation: open the closed action type into the generic, typed, clocked envelope
every other epic encodes/signs/verifies. Zig-canonical (TC1) — edit Zig structs
first, propagate downstream in Epic C.

- **A1 ⚑** — Extend the `Action` struct to v4 (`protocol_v2.zig`). `format_version`
  3→4; replace `action_kind: ActionKind` with `kind: []const u8`; add
  `body: ?[]const u8` and `hlc: [2]u64`. Keep `ActionKind` as a convenience enum
  (palace profile), not the wire type. *Refs D-037, D-039, D-043. test_tier: thorough.*
- **A2 ⚑** — Extend `encodeAction`/`decodeAction` (`envelope_v2.zig`) for v4: emit/read
  the 7-key core map in dCBOR length-first order (`hlc`(3), `body`(4), `kind`(4),
  `type`(4), `actor`(5), `parent-hashes`(13), `format-version`(14)); `body` as a
  CBOR byte-string wrapping the consumer's canonical CBOR; `hlc` as a 2-int array.
  Preserve the v3 decode path unchanged (regression). *Refs D-037, D-043, D-039.
  test_tier: thorough.*
- **A3** — Validation on decode (D-041): `assertCanonical` over envelope *and* body
  bytes; reject v4 envelopes missing `hlc`/`kind`; reject zero-length `kind`; v4
  with no `body` is legal (`?`). *Refs FR4, D-041. test_tier: thorough.*
- **A4 ⚑** — Protocol spec: add `docs/PROTOCOL.md` "HLC Specification" (shape `[l,c]`,
  ordering, v4 mandate) and "Kind Namespace Convention" (dot convention) sections;
  document the v3→v4 wire change (`action-kind`→`kind`, +`body`,+`hlc`). Resolves
  beads `Dreamball-fch`. *Refs D-038, D-039, FR10. test_tier: smoke (doc).*
- **A5** — Zig unit tests: v4 encode/decode round-trip (with/without body), v3
  regression, canonical-rejection + tamper, kind/HLC edge cases. *Refs FR3/FR4.
  test_tier: thorough.*

## Epic B — WASM authoring + JS surface
**Cluster B · FR6, FR7, FR9 · Decisions D-042**
Expose v4 authoring/verification through the WASM ABI and the TS loader, browser
+ Bun, with no consumer-side CBOR.

- **B1 ⚑** — Link `envelope_v2` into `wasm_main.zig`; add the `authorAction` export
  (packed-u64): `authorAction(kind_ptr,kind_len, body_ptr,body_len,
  parent_hashes_ptr,parent_hashes_count, hlc_l,hlc_c, secret_ptr)` → encode v4 +
  Ed25519 sign; actor = `secret[32..64]`. Keep `signActionEnvelope` (raw signer,
  D-023). Record wasm size delta (NFR5). *Refs FR6, D-042, TC6. test_tier: thorough.*
- **B2** — v4 action verification: ensure `verifyBall`/decode verifies a v4 action
  (Ed25519 vs actor; canonical-form), distinct verified / sig-failed / parse-error
  results. *Refs FR9. test_tier: thorough.*
- **B3** — `loader.ts` `authorAction(opts)` + verify wrappers: marshal JS args
  (kind string, body Uint8Array, parent_hashes `Uint8Array[]`, hlc `[number,number]`,
  64-byte secret) to WASM pointers; return signed bytes + `content_hash`. *Refs FR7,
  D-042. test_tier: smoke.*
- **B4** — Vitest: `authorAction` round-trip → verify → tamper-fails, run under Bun
  (and jsdom browser-mode) to assert identical verdicts both runtimes. *Refs FR7,
  NFR2. test_tier: thorough.*

## Epic C — Determinism, codegen & gates
**Cluster C · FR2, FR8, FR11 · Decisions D-041/D-043**
Lock cross-runtime identity, regenerate downstream targets from the Zig type, keep
every gate green.

- **C1 ⚑** — `content_hash` = Blake3 of canonical v4 envelope bytes; add golden
  vectors (`golden.zig`) and a cross-runtime assertion that bytes + digest are
  byte-identical across the Zig CLI and the WASM build (incl. a body + HLC). *Refs
  FR8, NFR1, D-043. test_tier: thorough.*
- **C2** — Regenerate downstream targets from the extended Zig type via
  `zig build schemagen`: TS types, Valibot schema, `cbor.ts`, JSON-Schema; manual
  propagation (TC5); byte-equivalence gate green. TS HLC type = `[number,number]`,
  body = `Uint8Array`, kind = `string`. *Refs FR2, TC1, TC5. test_tier: smoke.*
- **C3** — Green-gate + housekeeping: run all gates (`zig build test`/`smoke`,
  `server-smoke.sh`, Vitest, `svelte-check`); record raw+gz wasm size (NFR5, soft
  300 KB-gz flag); fix the stale D-018/JSON-Schema-canonical reference in
  `PROTOCOL.md §14` (Requirements Conflict #1). *Refs FR11, TC4. test_tier: smoke.*

## Epic D (STRETCH) — Second worked type
**Cluster D · FR1/FR2 generality**
Include only if A–C land clean.

- **D1** — Add a second maintainer-authored type (e.g. `object3d`) through the
  Zig-canonical pipeline (struct → schemagen → golden vector) to prove FR1/FR2
  generalize beyond the op envelope. *Stretch. test_tier: smoke.*

---

## Story summary
12 in-scope stories (Epics A–C) + 1 stretch (D1). Flagged for full story-writing
(⚑): **A1, A2, A4, B1, C1** (5) — core wire-type changes, the WASM export, the
HLC protocol commitment, and the cross-runtime golden gate. Remainder ship as
stubs unless promoted.

## Dependency order
A1 → A2 → {A3, A5} ; A4 parallel to A1–A3 (doc, but freeze HLC before A2 lands its
encoding). B1 depends on A2 (encoder) ; B2/B3/B4 depend on B1. C1 depends on A2 +
B1 (needs both CLI and WASM encoders). C2 depends on A1 (type shape). C3 last
(gates + housekeeping). D1 depends on C2 (pipeline proven).
