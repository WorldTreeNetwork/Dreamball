---
project: Dreamball
sprint: sprint-002
product: dreamball-protocol
created: 2026-04-28
steering_mode: GUIDED
previous_sprint: sprint-001
input_quality: existing-prd
source_prd: docs/decisions/2026-04-25-{archiform-registry,json-schema-canonical,action-manifest,wasm-runtime}.md
---

# Sprint-002 Requirements — Archiform Foundation

## Product Vision

Sprint-002 pivots Dreamball from a single-archiform application (Memory Palace MVP) into a federated protocol platform. The four 2026-04-25 decision notes commit to: aspects.sh as an archiform registry under a 3-layer model (schema/manifestation/instance); JSON Schema as the canonical source for all field shapes; a universal action manifest projecting to CLI/programmatic/MCP (REST+renderer deferred to sprint-003); and wasm as the runtime for all executable code in DreamBalls. The sprint must land this foundation while preserving zero wire-format change against sprint-001 readers (byte-equivalence is the gating constraint), and close the sprint-001 carry-over Ed25519 sentinel substitution debt.

---

## Functional Requirements

### FR1 — Codegen Direction Inversion (root schema)

The `tools/schema-gen/` toolchain MUST flip from a Zig-canonical TypeScript emitter to a JSON-Schema consumer that reads `schemas/root-2.0.0.json` and emits Zig types, TypeScript types, Valibot validators, and CBOR codecs.

**Acceptance:**
- `bun run codegen` (alias for `zig build schemagen`) reads `schemas/root-2.0.0.json` and produces every artifact previously produced from Zig source.
- Byte-equivalence test (`tests/codegen/byte-equivalence.test.ts` or Zig equivalent) compares regenerated outputs in `src/lib/generated/` against frozen snapshot fixtures; any byte diff fails.
- `zig build smoke`, `scripts/server-smoke.sh`, `tests/e2e-cryptography.sh` remain green.

### FR2 — Root JSON Schema authoring

A `schemas/root-2.0.0.json` document MUST exist that fully expresses the current Zig root type system (envelopes, signatures, sealed bodies, fingerprints) such that round-trip is bit-equivalent.

**Acceptance:**
- Schema validates against JSON Schema draft 2020-12.
- A snapshot test verifies no field in current Zig types lacks a corresponding entry in the schema.
- `docs/PROTOCOL.md` updated to point to `schemas/root-2.0.0.json` as the authoritative shape source.

### FR3 — CBOR algorithm stays Zig-canonical with golden vectors

CBOR encoding/decoding rules (map ordering, integer width, bytes-vs-text, deterministic encoding) remain in Zig. A golden-vector fixture set MUST cover every root type and the Memory Palace types.

**Acceptance:**
- `tests/golden/` contains `(logical_value, archiform_fp) → expected_bytes` pairs for every root type and `dreamball/memory-palace@0.1.0` types.
- Zig and TypeScript runtimes both pass the golden-vector test in CI.

### FR4 — Memory Palace schema extraction

Memory Palace types (`Inscription`, `Room`, `Aqueduct`, traversal state, decay parameters) MUST be extracted from current Zig source and `src/memory-palace/schema.cypher` into `schemas/memory-palace-0.1.0.json`, vendored locally with its blake3 fp recorded in a pin file.

**Acceptance:**
- `schemas/memory-palace-0.1.0.json` exists; `schemas/.pins/memory-palace-0.1.0.fp` records the blake3.
- Per-archiform codegen pass produces Zig extensions, TS extensions, Valibot validators, and Cypher DDL from the pinned schema.
- Generated Cypher DDL matches pre-migration `schema.cypher` byte-for-byte (or with documented, justified semantically-equivalent diffs).
- `zig build smoke` passes against regenerated types.

### FR5 — Genesis envelope `archiform_fp` field

The genesis envelope CBOR shape MUST carry an `archiform_fp` field. New genesis envelopes emit it; envelopes lacking the field decode by implicitly binding to `dreamball/memory-palace@0.1.0` (back-compat for sprint-001 instances).

**Acceptance:**
- Round-trip: encode genesis with `archiform_fp = blake3(memory-palace-0.1.0)` → decode → field equals input.
- Round-trip: a sprint-001 genesis envelope (without the field) decodes successfully and yields the implicit Memory Palace fp.
- `archiform_fp` documented as immutable for the ball's lifetime in `docs/PROTOCOL.md`.

### FR6 — Action manifest schema in JSON Schema

Each archiform's JSON Schema MUST be capable of declaring an `actions` map with entries containing `summary`, `inputs`, `outputs`, `effects`, `idempotency`, `streaming`, `attributes` (`destructive`, `requiresConfirmation`, `confirmationMessage`), and `implementation` (`wasm` | `bunScript`, `export`).

**Acceptance:**
- `schemas/memory-palace-0.1.0.json` declares actions for every existing sprint-001 verb (per FR-set decided in Phase 1B Open Question #7).
- Generated Valibot validator rejects malformed manifests (missing `inputs`, unknown `idempotency` enum, non-fp `implementation.wasm`).
- "Pure-transaction" lint: rejects manifests where any `inputs.properties.*` is named `prompt` / `confirm` or has `format: "tty-interactive"`.

### FR7 — CLI projection from action manifest

The `jelly palace <verb>` CLI surface MUST be mechanically derived from the Memory Palace action manifest rather than hand-written in `src/cli/palace*.zig`.

**Acceptance:**
- Removing a hand-written verb stub and regenerating produces a working CLI verb whose `--help`, flag mapping (from `inputs`), and JSON-output shape (from `outputs`) match pre-migration behavior verified by `scripts/cli-smoke.sh`.
- Actions with both `attributes.requiresConfirmation: true` and `attributes.destructive: true` trigger a TTY confirmation prompt unless `--yes` / `--no-confirm` is passed.
- `scripts/cli-smoke.sh` passes against the generated dispatcher with no behavioral regressions.

### FR8 — Programmatic projection (TypeScript client)

A TypeScript client MUST be generated from the action manifest, exposing each action as a typed function callable from any bun script and from `jelly-server` route handlers.

**Acceptance:**
- A bun script `import { mint } from '@dreamball/palace-client'` calls `mint({ name, mythosTemplate })` and receives a typed `{ palaceFp }` response.
- Type errors at compile time when input/output shapes drift from the manifest.
- At least one existing `src/lib/bridge/*` mutation site is migrated to call the generated client and continues to satisfy its existing Vitest coverage.

### FR9 — MCP projection from action manifest

An MCP tool spec MUST be generated from the action manifest such that each action becomes one MCP tool (name from action key, description from `summary`, input schema from action's `inputs`, confirmation routed through MCP elicitation).

**Acceptance:**
- A generated MCP server exposes Memory Palace actions as MCP tools when invoked under `bun run mcp` (or equivalent entrypoint).
- MCP tool input schemas validate against the same Valibot validator the CLI uses.
- `attributes.requiresConfirmation` actions surface MCP elicitation rather than executing on first call.

### FR10 — Wasm action host inside `jelly` CLI

A wasm action host MUST run inside the `jelly` CLI, capable of loading content-addressed wasm action modules (resolved by `blake3(wasm_bytes) == implementation.wasm` fp) under WASI with a default per-instance memory limit.

**Acceptance:**
- `jelly` loads a sample `mint.wasm` whose fp matches the manifest, executes the `mint` export, and produces an envelope-shaped output.
- A wasm module whose hash does NOT match the declared fp is rejected with a clear error before execution.
- Default memory limit 16 MiB initial, configurable via `--wasm-mem-mib`.
- Wasm host code reusable in the browser/`jelly.wasm` host context without source divergence.

### FR11 — `dreamball.*` import namespace

The wasm host MUST expose a `dreamball.*` import namespace as the sole seam between guest archiform wasm modules and host services. Sprint-002 surface MUST include at minimum: `dreamball.fp(bytes_ptr, bytes_len)`, `dreamball.encode_cbor(value_ptr) → bytes`, `dreamball.read_node(fp_ptr) → node_value`, `dreamball.emit_action_envelope(value_ptr) → envelope_bytes`, `dreamball.now_ms() → u64`.

**Acceptance:**
- New `docs/dreamball-imports.md` (or fold into `PROTOCOL.md`) enumerates each import with arity, types, error semantics, host-trust notes.
- A guest module importing a name outside `dreamball.*` fails to instantiate with a clear error.
- Each enumerated import exercised by at least one test.

### FR12 — Bun-script fallback implementation path

The action manifest MUST support a `bun-script` fallback shape `"implementation": { "bunScript": "actions/<name>.ts", "export": "<name>" }`. Hosts with bun on PATH execute these directly; hosts without bun MUST refuse with a `requires-bun` error.

**Acceptance:** *(scope conditional on Phase 1B Open Question #3)*
- A sample action with a `bunScript` implementation runs end-to-end via `jelly` CLI when bun is on PATH.
- Test simulating absent bun yields a `requires-bun` error and does NOT silently degrade.
- Action declarations that specify both wasm and bunScript prefer wasm; fallback documented as "early-authoring only".

### FR13 — Sprint-001 carry-over: Ed25519 sentinel migration

The two derived-fp sentinel call sites in `oracle.ts oracleSignAction` and `store.recordTraversal` MUST be migrated to real Ed25519 single signatures over the canonical action payload, using the keypair already in scope. PQ dual-sig + secure key custody remain explicitly deferred per 2026-04-25 steering.

**Acceptance:**
- Both call sites compute Ed25519 signatures via existing primitives; no `sentinel`, `derived-fp`, or placeholder bytes remain.
- Negative test: forged signature on a recorded traversal fails verification.
- Full-gate verification (zig build smoke + scripts/server-smoke.sh + scripts/e2e-cryptography.sh + bun run check + bun run test:unit) all pass.
- `docs/known-gaps.md` "scope substitution" entry updated to mark this debt closed; PQ dual-sig debt remains open under the security-pass section.

### FR14 — Migration rollout without breaking sprint-001 smoke gates

The codegen-inversion migration (FR1, FR4) MUST land in a sequence that keeps every CI gate green at every commit boundary, not only at the end.

**Acceptance:**
- Each commit in the FR1 → FR4 sequence passes `zig build test`, `zig build smoke`, `scripts/server-smoke.sh`, `bun run check`, `bun run test:unit -- --run` locally before push.
- A "shadow generator" phase exists where the new JSON-Schema-driven generator runs in parallel with the legacy Zig generator and the byte-equivalence test gates every PR until cutover.
- Cutover (delete legacy) is its own commit with all gates green.

### FR15 — Documentation refresh of refined cross-runtime invariant

`CLAUDE.md` and `docs/ARCHITECTURE.md` reflect the two-part invariant; `docs/PROTOCOL.md` points to the JSON Schema files; `docs/dreamball-imports.md` (or PROTOCOL.md addendum) enumerates the wasm import surface.

**Acceptance:**
- `CLAUDE.md` cross-runtime invariant section already reflects the two-part formulation (landed pre-sprint).
- `docs/ARCHITECTURE.md` adds (or updates an ADR for) the wasm action host, `dreamball.*` import seam, and codegen flow diagram.
- `docs/PROTOCOL.md` adds pointer to JSON Schema files; "no hand-written schemas anywhere" wording preserved (now: "no hand-written schemas; JSON Schema vendored, generators consume it").

---

## Non-Functional Requirements

### NFR1 — Codegen byte-equivalence (gating)

Regenerated outputs from the new JSON-Schema-driven flow MUST byte-match the current `src/lib/generated/types.ts`, `schemas.ts`, `cbor.ts`, `cbor.test.ts` and any Cypher DDL produced today. Verification: `diff -r` returns empty over the generated tree against a frozen reference snapshot. **Highest-priority NFR for sprint-002.**

### NFR2 — Codegen runtime budget

`bun run codegen` completes in ≤ 5 s on a developer laptop (M-series Mac baseline). Regression here directly damages developer iteration loop.

### NFR3 — Wasm action invocation latency

Trivial action invocation (load cached module + invoke entry + emit one signed envelope) under 50 ms p95 on a developer laptop. Excludes first-time module instantiation.

### NFR4 — Wasm module first-time instantiation

Cold-path module load + instantiation (verify fp, compile, link `dreamball.*` host imports) under 100 ms for a sub-1 MB module on a developer laptop.

### NFR5 — kNN recall perf gate (R5) — no regression

Sprint-001's R5 perf gate (kNN recall < 200 ms; sprint-001 measured p50 = 8.7 ms / p95 = 9.1 ms over a 500-corpus fixture) MUST hold or improve. Codegen inversion or wasm host introduction must not perturb this hot path.

### NFR6 — CI total runtime — no material regression

Total CI time (all gates per TC2) must not regress materially against sprint-001 baseline. "Material" = > 25% slowdown.

### NFR7 — Wasm sandbox memory budget

Default per-module instance: 16 MiB initial linear memory, configurable per projection. Renderer projection MAY tighten further; CLI MAY relax for batch flows. Hard ceiling per instance: 64 MiB.

### NFR8 — Schema validation is validate-on-publish, not validate-on-decode

Generic CBOR decode of nodes/edges with extra (schema-unknown) fields MUST work without the JSON Schema present at runtime. Schema validation is opt-in at publish boundaries (manifest authoring tools, registry submissions). Hot read paths (palace recall, traversal) MUST NOT take a schema-validation hit.

### NFR9 — Generated-file provenance headers

Every codegen-produced file carries a header comment naming source JSON Schema fp, schema semantic version, generator version (Zig schema-gen tool fp or commit SHA), and a `DO NOT EDIT — generated` banner.

### NFR10 — Schema-gen tool logging

`tools/schema-gen/` (post-inversion) emits structured logging tracing which JSON Schema files were read, which target generators were dispatched, which output files were written and their byte-lengths, and any byte-equivalence diff against a reference snapshot when run in verify mode.

### NFR11 — Wasm action invocation structured events

Each wasm action invocation emits a structured log event containing: action name, actor fp, archiform fp, module fp, invocation duration (ms), emit count, outcome (`ok` / `trap` / `import_violation` / `fp_mismatch`).

---

## Technical Constraints

### TC1 — Cross-runtime invariant: zero wire-format change

CBOR algorithm + golden vectors stay canonical in `src/*.zig`. Regenerated TS / Valibot / CBOR codecs / Cypher DDL MUST byte-match current outputs. Byte equivalence is the gating constraint — not "functionally equivalent," not "passes the same tests," but exact byte-match.

### TC2 — All CI gates must stay green end-to-end

Every change in sprint-002 keeps the full gate set green locally before being reported "done": `zig build test`, `zig build smoke`, `bun run check`, `bun run test:unit -- --run`, `scripts/cli-smoke.sh`, `scripts/server-smoke.sh`, `tests/e2e-cryptography.sh`.

### TC3 — JSON Schema draft 2020-12 as canonical dialect

JSON Schema dialect for both `schemas/root-2.0.0.json` and per-archiform schemas is **draft 2020-12**. Generators consume only this dialect. Vendored `dreamball/memory-palace@0.1.0` is fp-pinned in-tree until aspects.sh refresh path lands.

### TC4 — Wasm action runtime: WASI + `dreamball.*` imports only

Archiform action implementations execute under WASI for filesystem/network capability brokering. Host-import surface bounded to `dreamball.*` namespace. Default per-instance memory: 16 MiB initial, configurable per projection. Each projection layer declares its own permission grant subset of `dreamball.*`.

### TC5 — Wasm module size budgets

`jelly.wasm` (root primitive host): unchanged budget — ≤ 200 KB raw, ≤ 64 KB gzipped, ships ML-DSA-87 verify. Archiform action modules (guest): soft target < 1 MB per module for the foundation sprint.

### TC6 — aspects.sh schema-aspect contract: vendor-first

A parallel agent is implementing the aspects.sh deployment; sprint-002 MUST function fully against locally-vendored schemas regardless of that deployment's status. Network refresh from aspects.sh is an *optional* code path with fp-pinned verification. No silent network fetches at runtime.

### TC7 — Pinned dependency floor

Zig 0.16.0 (core, CLI, schema-gen, wasm); Bun 1.x (TS/JS package manager + runtime); LadybugDB v0.15.3 — lacks `BEGIN`/`COMMIT`; logical-ordering + replay-from-CAS is the only transactional model available (D-008 revision pending); kuzu-wasm 0.11.3 (Cypher in browser); valibot 1.3.1 + @valibot/to-json-schema (TS validation surface; consumed by generated artefacts).

### TC8 — Runtime determinism via content addressing

`archiform_fp = blake3(canonical bundle manifest bytes)` — genesis-immutable. Wasm modules content-addressed by `blake3(wasm_bytes)`. Action manifest's `implementation.wasm` field MUST be an fp pointer (not an inlined blob, not a URL).

### TC9 — Recrypt naming inheritance

All envelope, signature, fingerprint, and stage terminology must remain verbatim-aligned with `../recrypt/docs/wire-protocol.md`. New action-manifest concepts must check recrypt before introducing novel vocabulary.

---

## Security Requirements

### SEC1 — Wasm sandbox: host-import whitelist

Third-party archiform code MUST run in the wasm sandbox with **only** `dreamball.*` imports available. No raw WASI filesystem/network/clock imports leak through to guest modules; the host brokers them through `dreamball.*` with permission checks. Imports statically validated at module load; modules importing outside `dreamball.*` rejected before instantiation.

### SEC2 — Action envelope signing: host-mediated only

Actions emit signed envelopes via `dreamball.emit_action_envelope(value)`. The **host** signs using the actor keypair; the wasm body **cannot forge signatures** because it has no access to private key material. This is the single trust boundary between guest action code and the actor identity.

### SEC3 — Replace dual-sig sentinels with real Ed25519 single signatures (carry-over)

The derived-fp sentinel substitutions in `oracle.ts oracleSignAction` and `store.recordTraversal` MUST be replaced with real Ed25519 single signatures over the canonical action payload. Closes the "scope substitution" finding from sprint-001 S4.4 / S5.5 without re-opening dual-sig parameterisation. No `_sentinelFp` / derived-fp substitution may remain in any signature-emitting path after sprint-002. *(See FR13 for the FR-side AC bundle.)*

### SEC4 — Archiform integrity: verify-before-instantiate

Before instantiating any archiform wasm module, the runtime MUST verify `blake3(wasm_bytes) == declared implementation.wasm fp`. Mismatched bytes-vs-fp MUST abort instantiation and emit a structured failure event. Applies symmetrically to CLI, jelly-server, and in-renderer hosts.

### SEC5 — Per-projection permission grants

Each projection layer (CLI, REST, MCP, in-renderer, programmatic) declares the **subset** of `dreamball.*` imports it grants. Renderer projection grants the most restrictive set; CLI grants the broadest. Granted permissions computed at projection-boot, not negotiated per call. *(Sprint-002 ships trusted-by-default per Open Question #10; explicit per-projection registry is sprint-003.)*

### SEC6 — Cryptographic deferrals (explicitly out of scope)

Per steering decision 2026-04-25, the following are explicitly out of scope for sprint-002 and bundled for the deferred security pass: post-quantum dual-sig parameterisation (verify-only is OK); secure key custody / recrypt-wallet (plaintext + 0600 perms remain acceptable); oracle-fp spoofing prevention; chained proxy-recryption (Tier 3 sealed paths). Per project memory: do NOT flag dual-sig sentinel substitutions as regressions; substitution with real Ed25519 single sigs (FR13/SEC3) is the sanctioned target.

---

## Integration Constraints

### IC1 — PROTOCOL.md §13.7 surface registry stays as-is

The §13.7 surface registry, open-enum convention, and fallback chain are unchanged. Archiform-fp extension to the genesis envelope is **additive** and back-compat (older instances bind implicitly to `dreamball/memory-palace@0.1.0`).

### IC2 — Signed action envelope shape frozen

Existing signed-action envelope field set is frozen. Action-manifest projections produce action **invocations** whose payloads serialise to the existing envelope shape; no new top-level fields or signature-bag changes.

### IC3 — Recrypt sibling wire protocol alignment

`../recrypt/docs/wire-protocol.md` remains the authoritative cross-reference for shared concepts. Any new sprint-002 concept that overlaps must reuse recrypt's term verbatim.

### IC4 — Memory Palace sprint-001 instance compatibility

Per user steering (2026-04-27): sprint-001 instances are throwaway; **no migration code required**. However, byte-equivalence (NFR1) ensures *new* instances written by sprint-002 readers/writers remain interchangeable with sprint-001 readers — i.e., a sprint-001 `jelly` build must still decode a sprint-002-produced canonical envelope.

### IC5 — aspects.sh read-vendored-first contract

When the parallel aspects.sh agent ships, our local pinning code reads the vendored copy first, with an optional `--refresh` path that fetches from aspects.sh and verifies the fp before swap-in.

### IC6 — Store API (D-007) unchanged

The store wrapper API (D-007 — domain verbs + sanctioned `__rawQuery` escape hatch) is **unchanged in shape**. Codegen surface expands (new node/edge types from archiform extensions), but the wrapper's domain verbs remain the only sanctioned mutation path. AC7-style grep audits carry forward.

---

## Open Questions

These need user resolution in Phase 1B (Sprint Scoping):

- **Q1 (CRITICAL — sprint scope):** Archiform foundation (this requirements set) vs asset-envelope ingestion (sprint-001 retrospective recommendation: `jelly.asset` for glTF / splats / HDRI / images)? Both paths are valid; sprint capacity does not credibly support both. Phase 1B negotiates.
- **Q2 (HIGH — federation proof):** Sprint-002 ships only Memory Palace extracted to JSON Schema, OR also publishes a sample second archiform (e.g., a tiny "guestbook" or "journal") to prove the multi-archiform claim? Without a second archiform, the federation hypothesis stays untested.
- **Q3 (HIGH — runtime scope):** Wasm-only in sprint-002 with bun-script deferred to sprint-003, OR ship both runtime paths (FR12)? ~2-3 stories of difference.
- **Q4 (HIGH — aspects.sh contract):** Vendor `dreamball/memory-palace@0.1.0` JSON Schema *as if* it had been published (deterministic local pin, no network) and write the publish/fetch path against a stub, OR block sprint-002 on aspects.sh `kind: "schema"` shipping first? Recommendation: vendor-locally; needs confirmation.
- **Q5 (HIGH — carry-over scope):** Ed25519 sentinel migration (FR13) is in. What about: AC6 rename propagation through `buildSystemPrompt`, AC7 archiform `@embedFile` compile-in seed, inscription-mirroring partial-write window (HIGH data-integrity), `casDir` plumbing? Bundle into one "oracle hardening + sprint-001 debt" story or punt to sprint-003?
- **Q6 (MEDIUM — projection scope):** REST and renderer projections deferred to sprint-003 per D-NEW-A.3 §Consequences — confirm no last-minute pull-in?
- **Q7 (HIGH — verb coverage):** Action-manifest authoring covers every sprint-001 verb (`mint`, `inscribe`, `add-room`, `rename-mythos`, `move`, plus traversal recording), OR a representative subset (e.g., `mint` + `inscribe`) with the rest as sprint-003 follow-on? Full coverage is ~4 more stories.
- **Q8 (MEDIUM — codegen disposition):** What happens to `tools/schema-gen/main.zig`? Deleted, repurposed as the JSON-Schema consumer entry point, or kept temporarily for shadow-generator phase then removed?
- **Q9 (MEDIUM — wasm signing):** Is wasm module integrity sufficient via blake3 content-addressing (per SEC4), or is the wasm ALSO signed (e.g., the archiform schema body is signed and contains the wasm fp, transitively authenticating)?
- **Q10 (MEDIUM — permissions model):** Sprint-002 ships trusted-by-default (CLI-only host, archiforms vendored locally, no third-party install path yet) and defers per-projection permissions registry to sprint-003 — confirm?
- **Q11 (LOW — Qwen3 weights):** Carries from sprint-001. Close `TODO-EMBEDDING` in sprint-002 (local script / cache mount / Runpod canonical) or punt to sprint-003?

---

## Scope Boundaries

### In Scope (sprint-002)

- Codegen direction inversion (root JSON Schema → Zig + TS + Valibot + CBOR generators)
- Byte-equivalence gate as the migration-cutover guard
- `dreamball/memory-palace@0.1.0` JSON Schema extraction + local vendor pin
- Genesis envelope `archiform_fp` field with implicit-binding back-compat
- Action manifest shape declared in JSON Schema; pure-transaction discipline enforced via lint/validator
- CLI + programmatic + MCP projections from manifest
- Wasm action host inside `jelly` CLI; `dreamball.*` import namespace; content-addressing of action modules
- Bun-script fallback runtime path (pending Q3 confirmation)
- Sprint-001 carry-over: Ed25519 sentinel migration (FR13)
- Documentation refresh (CLAUDE.md cross-runtime invariant, ARCHITECTURE.md, PROTOCOL.md, dreamball-imports.md)
- Promotion of D-NEW-A through D-NEW-H to numbered ADRs as part of sprint planning artifacts

### Out of Scope (sprint-002 — deferred)

- **REST projection** — deferred to sprint-003 per D-NEW-A.3
- **In-renderer (Svelte) projection** — deferred to sprint-003 per D-NEW-A.3
- **Post-quantum dual-sig signer parameterisation** — deferred to security/cryptography pass
- **Recrypt-wallet / secure key custody** — deferred to security pass
- **AC4 oracle-fp spoofing prevention** — deferred to security pass
- **aspects.sh-side work** (the `kind: "schema"` aspect type, registry publish flow) — owned by parallel agent
- **Dreamforge instance hosting** — separate system, out of frame
- **Asset-envelope ingestion (`jelly.asset`)** — moved to sprint-003 if archiform-foundation is chosen as primary scope (Q1)
- **kNN over memory-nodes** (sprint-001 known-gaps §13) — sprint-003 candidate
- **Quantised vectors / hybrid lexical+semantic** — post-MVP backlog
- **`store.ts` runtime auto-routing reattempt** — sprint-003
- **Storybook test-infra repair** — sprint-003 unless trivially folded in
- **Per-projection permissions registry** — sprint-003 (per Q10 default)

---

## Assumptions

| Assumption | Validation Method | Impact if Wrong |
|---|---|---|
| JSON Schema draft 2020-12 can fully express the current Zig type system without expressivity loss | Spike — round-trip the three most expressively complex Zig types (envelope, sealed body, signature tier wrapper). First sprint-002 spike. | Foundation FRs (1-4) require IDL augmentation or a different schema dialect; sprint scope needs re-derivation |
| WASI works inside `jelly` CLI on darwin AND linux without runtime divergence | Bounded one-day spike: minimal wasm host + hello-world guest on both platforms | FR10 needs a non-WASI shim or per-platform host code |
| Byte-equivalence between current Zig-generated outputs and JSON-Schema-driven regenerated outputs is achievable on first pass, with at most cosmetic diffs (whitespace, comment ordering) requiring deterministic-formatter normalization | Implement FR14 shadow-generator pattern; the byte-equivalence test IS the validation | Structural diffs in CBOR map ordering or Cypher DDL layout require unanticipated normalization work; scope expands |
| Existing sprint-001 instances on disk implicitly bind to `dreamball/memory-palace@0.1.0` without genesis-envelope rewrite | Decode test against three real sprint-001 `.jelly` files | (Per IC4: instances are throwaway, so the impact is documentation-only) |
| `jelly.wasm` already has the primitives needed to host `dreamball.*` imports (CBOR encode, blake3, ML-DSA-87 verify, Ed25519 sign for FR13) | Inventory `src/wasm_main.zig` exports before story dispatch | If a primitive is missing, raise as a blocker (per project memory `feedback_dreamball_ac_scope_retreat`), do NOT silently substitute |
| Action manifest's `effects` declaration is sufficient to drive envelope emission without per-action host code | Implement `mint` end-to-end via manifest only; spike before scaling | Per-action host code re-introduces hand-written dispatch; FR7 acceptance softens |
| Bun-script fallback can be sandboxed to the same security level as wasm-via-WASI OR is acceptable as an unsandboxed early-authoring affordance documented as such | Decision-level — D-NEW-A.4 implies "less sandboxed... full access to host process"; confirm in Phase 1B | If unacceptable, FR12 collapses; sprint scope tightens to wasm-only |
| The aspects.sh-side `kind: "schema"` aspect can be vendored against a known-stable contract even though aspects.sh is parallel-developed | Treat schema-aspect body shape as a sprint-002-internal commitment; document the assumed contract | If aspects.sh diverges, sprint-003 reconciles |
| MCP elicitation is implemented in the host MCP runtime the way D-NEW-A.3 §Projection mapping assumes | Spike against current MCP SDK; confirm elicitation supported in pinned version | Action confirmation in MCP downgrades to a different idiom (e.g., two-call preview/commit) |

---

## Missing Guardrails (analyst-identified)

1. **Migration rollout strategy** — encoded in FR14 (shadow-generator + byte-equivalence-gated cutover commit).
2. **Disposition of `tools/schema-gen/main.zig`** — Q8 needs explicit decision in Phase 2A.
3. **Action manifest `attributes` field shape** — closed set: `destructive: bool`, `requiresConfirmation: bool`, `confirmationMessage: string`, `agentVisible: bool`, plus reservation for future. Validator rejects unknown attributes (unless `x-` prefix convention adopted). Encoded in FR6.
4. **`dreamball.*` import namespace surface** — FR11 requires `docs/dreamball-imports.md` with complete sprint-002 surface: function signatures, trap/error semantics, host-trust level, stability tier.
5. **Wasm module signing within an archiform bundle** — Q9 needs decision (recommend signed schema + content-addressed wasm).
6. **Wasm host memory limit upper bound and OOM behavior** — encoded in NFR7 (16 MiB default, 64 MiB hard ceiling, OOM → trap → projection-layer error).
7. **Permissions model for `dreamball.*` imports** — Q10 default: trusted-by-default in sprint-002; per-projection registry deferred to sprint-003 with forward-pointer.
8. **"No interactive prompts in actions" mechanical enforcement** — encoded in FR6 lint (rejects input fields named `prompt`/`confirm`, formats `tty-interactive`).
9. **Protocol-version negotiation when archiform schema fp changes** — `archiform_fp` in genesis is immutable (per D-NEW-A.1 alternative-3); local pin updates are a re-codegen + byte-equivalence event, NOT a per-instance migration. Document in PROTOCOL.md as part of FR15.
10. **`effects` `kind` enumeration** — sprint-002's recognized kinds: `ActionEnvelope`, `Read`, `Derived`. Validator rejects unknown kinds. Encoded in FR6.

---

## Scope Risks (analyst-identified)

1. **Codegen inversion touching every generated file blows the sprint.** *Containment:* Lead with a spike (FR1 against root types only); shadow-generator phase (FR14) gates one surface at a time; do NOT cutover until all surfaces byte-equivalent.
2. **Action-manifest projection generators expand to all five surfaces under "completeness pressure".** *Containment:* REST and renderer explicit out-of-scope (Q6); flag any story attempting them as scope creep at planning review.
3. **Wasm host security model creep.** *Containment:* Sprint-002 trusted-by-default, locally-vendored archiforms only; permissions registry, capability tokens, third-party install path are explicit sprint-003+ items.
4. **`dreamball.*` import surface grows ad-hoc as actions need new primitives.** *Containment:* FR11 requires the surface formally enumerated *before* any action wasm module is authored. Adding an import is an architecture-decision event (D-NEW-E lesson), not a story-execution event.
5. **Sprint-001 carry-over cluster expands to absorb every retrospective §Technical Debt Priority item.** *Containment:* Q5 — pull all carry-over into one explicit "oracle hardening" story with bounded ACs, OR defer everything except FR13 to sprint-003 explicitly.
6. **Byte-equivalence test failures send the team into a normalization rabbit hole.** *Containment:* Spike FR3 golden-vector coverage first; if normalization is complex, treat it as a story (not as overhead inside FR1).
7. **Bun-script fallback widens the security/portability story unnecessarily.** *Containment:* Q3 resolves to wasm-only OR documents wasm as conformance target with bun-script as best-effort fast-iteration.
8. **Action manifest authoring for sprint-001 verbs becomes a re-spec-everything exercise.** *Containment:* Q7 — pick representative subset OR full set explicitly at planning time.

---

## Previous Sprint Intelligence

Sprint-001 delivered all 28 stories across 6 epics (100% done, 0 failed, 0 blocked) over 4 days, 16 substantive commits, +499 tests. Active decisions D-001 through D-016 are summarized in `.omc/sprint-plan/decisions/active-decisions.md` along with eight emergent ADRs (D-NEW-A through D-NEW-H) awaiting promotion in sprint-002.

Key carry-forward signals shaping sprint-002:

- **D-007 store-wrapper discipline survived 15 stories with zero `__rawQuery` drift** outside its single sanctioned use. Sprint-002 must respect this boundary as the codegen surface expands. (See IC6.)
- **D-015 cross-runtime vector parity** held within max |Δ| = 0.000048 against a 0.1 threshold; the kuzu-wasm fallback branch is dead code (TODO-KNN-FALLBACK markers can be removed in sprint-002 if scope allows).
- **R5 perf gate cleared by 23×** (p50 = 8.7 ms vs 200 ms budget); sprint-002 must hold the line. (See NFR5.)
- **Bridge pattern (Zig staging → Bun bridge → promote)** rediscovered in 5 stories; promote to numbered ADR as D-NEW-B in sprint-002 deliverables.
- **Three regressions of the same class** (S5.4 HTML overlay, S4.4/S5.5 dual-sig sentinels) — silent scope substitution when an executor hits a hard primitive blocker. Sprint-002 should adopt a "scope substitution audit gate" at story close (per retrospective Learning #1).
- **Steering decision 2026-04-25:** post-quantum dual-sig + secure-key-custody deferred to a later cryptography/security pass. Ed25519-only with plaintext-0600 keys is acceptable. (See SEC6, FR13, project memory `project_dreamball_pq_deferred`.)
- **Retrospective recommended sprint-002 focus** was asset-envelope ingestion. The four 2026-04-25 decision notes pivot away from this toward archiform-foundation work. Q1 negotiates this conflict.

---

## Existing Codebase Inventory

(Condensed from `discovery.md` and Phase 1 explore-agent output. See those documents for full file paths and line numbers.)

**Codegen pipeline (will be inverted):**
- `tools/schema-gen/main.zig` (1,480 L) — current Zig-canonical generator
- `src/lib/generated/{types,schemas,cbor,cbor.test,palace-round-trip.test}.ts` — current outputs
- `bun run codegen` / `zig build schemagen` — entry points
- `src/memory-palace/schema.cypher` (178 L) — hand-maintained Cypher DDL, becomes generated

**Memory Palace types (will be extracted to archiform schema):**
- `src/protocol_v2.zig` (700 L) — `Inscription`, `Mythos`, `Triple`, `MemoryNode`, `MemoryConnection`, `Memory`, `KnowledgeGraph`
- LadybugDB tables in `schema.cypher`: Palace, Room, Inscription, Agent, Triple, Mythos, Aqueduct, ActionLog + 8 relationship tables
- Aqueduct properties: `resistance`, `capacitance`, `strength`, `conductance`, `phase`, `last_traversal_ts`
- Agent properties: `personality_master_prompt`, `memory`, `emotional_register`, `interaction_set`

**CLI verb structure (will become action-manifest projections):**
- `src/cli/palace.zig` (80 L) — flat-table dispatch (D-013)
- `src/cli/palace_{mint,add_room,inscribe,move,open,rename_mythos,show}.zig` — per-verb handlers

**Bridge pattern (load-bearing for atomicity):**
- `src/lib/bridge/palace-{mint,add-room,inscribe,move,rename-mythos}.ts` — Zig staging → bun bridge → promote, 5 existing examples (D-NEW-B promotion candidate)

**Signed-action envelope plumbing (FR13 / SEC3 sites):**
- `src/lib/oracle.ts oracleSignAction` — current sentinel substitution
- `src/lib/store/*.ts recordTraversal` — current sentinel substitution
- No `signActionEnvelope(keypair_bytes, payload_bytes)` export in `jelly.wasm` yet (sprint-002 must add for FR13)

**WASM host infrastructure (precedent for archiform host):**
- `src/wasm_main.zig` (577 L) — current root primitive host; single import seam `extern "env" fn getRandomBytes(ptr, len)`
- `src/lib/wasm/jelly.wasm` (172.7 KB raw, well under 200 KB budget)
- `src/lib/wasm/loader.ts` (10.7 KB) — WASM module loader

**Store API (D-007 — unchanged in shape):**
- `src/memory-palace/store.ts` (router, 1.2 KB)
- `src/memory-palace/store.server.ts` (25.3 KB) — `@ladybugdb/core` 0.15.3
- `src/memory-palace/store.browser.ts` (42.6 KB) — kuzu-wasm 0.11.3

**Test infrastructure:**
- 28 `.test.ts` files (Vitest 4.1.3 + @vitest/browser-playwright)
- 45 `.zig` files with inline tests (≥ 51 passing)
- `scripts/cli-smoke.sh` (23.8 KB), `scripts/server-smoke.sh` (15.0 KB), `tests/e2e-cryptography.sh` — integration gates
- Mock seams: `JELLY_BRIDGE_DEBUG=1`, `JELLY_EMBED_MOCK=1`, `JELLY_SERVER_NO_LISTEN=1`

**CI configuration (`.github/workflows/ci.yml`):**
- Zig job → Bun job → Guard job (no-todo-crypto-leak grep) → Deploy (Pages, main only)
- WASM size verification fail-fast in Zig job

---

## Cross-Agent Notes

- **No analyst/architect contradiction surfaced.** The architect's "no prompts in actions" rule and the analyst's FR6 lint are mutually reinforcing.
- **The renderer projection's wasm host** is a deliberate non-requirement for sprint-002: in-browser hosts may use a non-WASI shim that exposes the same `dreamball.*` namespace. Phase 2A decides whether sprint-002 ships one host or two.
- **Architect TC4 + SEC2** (WASI imports + host-mediated signing) are correlated; Phase 2A should treat them as a single architectural surface (the "host-import contract") rather than two independent concerns.
