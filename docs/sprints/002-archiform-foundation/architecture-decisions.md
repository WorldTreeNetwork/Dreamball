---
project: Dreamball
sprint: sprint-002
phase: 2A-architecture
created: 2026-04-28
mode: fast (single planner pass; no architect/critic review)
steering: GUIDED
numbering_basis: sprint-001 ended at D-016
---

# Sprint-002 Architecture Decisions

This file records all architecture decisions for sprint-002 (Archiform Foundation). Decisions D-017 through D-028 promote pre-existing standing decisions and dated ADR drafts into the numbered sequence with their canonical ADR-lite entry pointing back to the source. Decisions D-029 through D-036 are new sprint-002 decisions authored in this phase.

**Numbering scheme** (locked by orchestrator):
- D-017..D-020 — promotion of the four 2026-04-25 standing notes
- D-021..D-025 — promotion of D-NEW-A..D-NEW-E from sprint-001 retrospective
- D-026..D-028 — promotion of three already-drafted dated ADRs
- D-029..D-036 — new sprint-002 architecture decisions (Q4, Q8, Q9 user-elicitation candidates plus 5 sprint-002-specific decisions)

**HIGH/CRITICAL elicitation candidates** for Decision Steering: D-029, D-030, D-031, D-032, D-034. (Plus the four 2026-04-25 promotions D-017..D-020 are user-blessed standing decisions and require no further elicitation.)

---

## D-017: Archiform Registry — aspects.sh as the registry under a 3-layer model

**Date**: 2026-04-25 (promoted 2026-04-28)
**Sprint**: sprint-002
**Significance**: HIGH
**Decided by**: user (standing decision)
**Status**: accepted
**Source**: [docs/decisions/2026-04-25-archiform-registry.md](../../decisions/2026-04-25-archiform-registry.md)

**Context**: Sprint-001 conflated the DreamBall protocol with one specific archiform (Memory Palace). The retrospective surfaced that `Room`, `Aqueduct`, `Inscription`, `Oracle` should not be root protocol vocabulary. A registry mechanism is needed for federated archiform definitions. Drives all of Cluster B (FR4, FR5).

**Decision**: aspects.sh becomes the registry for DreamBall archiforms under a 3-layer model — Schema (aspects.sh `kind: "schema"` aspect), Manifestation (aspects.sh `kind: "personality"` extending a schema), Instance (Dreamforge git+LFS). Genesis envelope carries `archiform_fp`, immutable for the ball's lifetime. Schema-aspect not required at runtime to decode bytes; required for typed accessors, validation, rich rendering, codegen.

**Alternatives**: Parallel DreamBall-only registry (rejected — duplicates federation infra); embed all schemas in Dreamball repo (rejected — non-federated); mythos-mutable archiform pointer (rejected — archiform = species, not state).

**Consequences**: Drives FR4 (Memory Palace schema extraction), FR5 (genesis envelope `archiform_fp` field), IC1 (§13.7 surface registry stays as-is, `archiform_fp` is additive back-compat), TC6 (vendor-first contract). Unblocks community archiform authoring.

---

## D-018: JSON Schema as canonical source for field shapes

> **⛔ SUPERSEDED 2026-06-25** by
> [zig-canonical-supersedes-json-schema](../../decisions/2026-06-25-zig-canonical-supersedes-json-schema.md).
> Zig (`protocol.zig` + `protocol_v2.zig`) is canonical for field shapes;
> JSON Schema is a generated artifact. The federation premise was unbuilt
> and the inversion never shipped. Disregard the decision below.

**Date**: 2026-04-25 (promoted 2026-04-28)
**Sprint**: sprint-002
**Significance**: HIGH
**Decided by**: user (standing decision)
**Status**: SUPERSEDED 2026-06-25 (see banner above)
**Source**: [docs/decisions/2026-04-25-json-schema-canonical.md](../../decisions/2026-04-25-json-schema-canonical.md)

**Context**: Today `tools/schema-gen/main.zig` is canonical for all field shapes and emits TypeScript. With archiforms federated via aspects.sh (D-017), the canonical source must be language-neutral. Drives all of Cluster A (FR1, FR2, FR3, FR14).

**Decision**: JSON Schema (draft 2020-12) is canonical for all field shapes (root types and archiform extensions). The CBOR encoding algorithm stays canonical in Zig with golden test vectors. Codegen flow inverts: `schemas/<file>.json` → consumers emit Zig + TS + Valibot + CBOR codecs (root) and Zig + TS + Valibot + Cypher DDL (per-archiform). Cross-runtime invariant refines to "encoding algorithm in Zig + golden vectors; field shapes in JSON Schema."

**Alternatives**: Keep Zig canonical with aspects.sh wrapping outputs (rejected — couples archiform authoring to Zig); CDDL (rejected — JSON Schema tooling and Valibot round-trip win); custom IDL (rejected — yet-another-schema-language tax).

**Consequences**: Drives FR1, FR2, FR3, FR14 (codegen inversion + byte-equivalence gate). Mandates NFR1 (byte-equivalence as gating constraint), NFR9 (provenance headers), NFR10 (schema-gen logging). Blocks all of Cluster B/C/D/E until Cluster A ships green. Hand-maintained `schema.cypher` becomes generated.

---

## D-019: Action Manifest as universal action contract

**Date**: 2026-04-25 (promoted 2026-04-28)
**Sprint**: sprint-002
**Significance**: HIGH
**Decided by**: user (standing decision)
**Status**: accepted
**Source**: [docs/decisions/2026-04-25-action-manifest.md](../../decisions/2026-04-25-action-manifest.md)

**Context**: Sprint-001 hand-coded CLI verbs in `src/cli/palace*.zig`. With archiforms federated, each archiform must declare its actions, callable from CLI/REST/MCP/in-renderer/programmatic. Drives Cluster C (FR6, FR7) and Cluster D (FR8, FR9).

**Decision**: An archiform declares actions in its JSON Schema. CLI, REST, MCP, in-renderer, and programmatic clients are mechanical projections of one manifest. Actions are pure transactions; never interactive (no prompts in action body). Confirmation declared as attribute (`destructive`, `requiresConfirmation`, `confirmationMessage`); projection layer renders in its idiom. Sprint-002 ships CLI + programmatic + MCP; REST and in-renderer deferred to sprint-003.

**Alternatives**: Per-archiform CLI plugin (rejected — couples to one projection); hand-write per-projection (rejected — N×M problem); allow interactive prompts in action bodies (rejected — breaks agent-callability).

**Consequences**: Drives FR6 (action manifest schema with closed `attributes` + `effects.kind` enum + pure-transaction lint), FR7/FR8/FR9 (three projections), IC2 (signed-action envelope shape frozen — projections produce invocations whose payloads serialize to existing envelope shape). Cluster C blocks D. REST and in-renderer projections explicitly out of sprint-002 scope (Cluster L deferred).

---

## D-020: Wasm as runtime for all executable code in DreamBalls

**Date**: 2026-04-25 (promoted 2026-04-28)
**Sprint**: sprint-002
**Significance**: HIGH
**Decided by**: user (standing decision)
**Status**: accepted
**Source**: [docs/decisions/2026-04-25-wasm-runtime.md](../../decisions/2026-04-25-wasm-runtime.md)

**Context**: Action Manifest (D-019) needs a runtime. The DreamBall ecosystem will ship executable code in several places: action implementations, lens shaders, derivation rules, policy evaluators, mythos validators. Drives Cluster E (FR10, FR11).

**Decision**: Wasm is the runtime for all executable code in DreamBalls. Modules run with WASI for filesystem/network capability brokering. Imports limited to `dreamball.*` namespace. Modules content-addressed by `blake3(wasm_bytes)`; action manifest's `implementation.wasm` is an fp pointer. Default per-instance memory: 16 MiB initial, configurable per projection, hard ceiling 64 MiB. Bun-script fallback for early authoring documented (deferred per Q3 to sprint-003+ — Cluster F).

**Alternatives**: Bun script as primary (rejected — host dependency, less sandboxed); native binaries per platform (rejected — multiplies release matrix); per-purpose runtimes (rejected — fragments authoring story).

**Consequences**: Drives FR10 (wasm action host inside `jelly` CLI), FR11 (`dreamball.*` import namespace), TC4 (WASI + `dreamball.*` only), TC5 (jelly.wasm budget unchanged; archiform module soft target <1 MB), TC8 (content-addressing), SEC1 (host-import whitelist), SEC2 (host-mediated signing), SEC4 (verify-before-instantiate), SEC5 (per-projection permission grants — sprint-002 trusted-by-default), NFR3/NFR4/NFR7/NFR11 (perf + sandbox + observability budgets).

---

## D-021: LadybugDB transactional model — logical-commit + replay-from-CAS

**Date**: 2026-04-21 (revision pending; promoted 2026-04-28)
**Sprint**: sprint-002
**Significance**: HIGH
**Decided by**: auto-decided (formalizes sprint-001 retrospective lesson)
**Status**: accepted; **revises D-008**
**Source**: was D-NEW-A in retrospective; this ADR is the canonical text.

**Context**: D-008 ("file-watcher transactional boundary = inline synchronous") was a partial decision. LadybugDB v0.15.3 lacks `BEGIN`/`COMMIT` (TC7); sprint-001 addressed the gap via logical commit-ordering and replay-from-CAS on recovery. This pattern was rediscovered in every mutation story and needs to stop being relitigated. Drives every story that mutates state in Clusters B, C, D, E.

**Decision**: The LadybugDB transactional model for sprint-002 is **logical commit-ordering + replay-from-CAS**. There is no multi-statement transaction. Every mutation:
1. Stages its writes as a content-addressed bundle to the CAS (the `staging-dir → promote-on-success` pattern that becomes D-022).
2. Appends a single ActionLog row (the logical commit) once the bundle is durable.
3. On replay/recovery, the ActionLog is the truth; rows derived from it can be regenerated by replaying envelopes from CAS.

Idempotency keys (e.g., `Triple.fp = blake3(agent_fp || subject || predicate || object)`) ensure replay is no-op for already-applied state. Partial-write windows are documented as "retry-is-idempotent."

**Alternatives**: Ship a transactional shim layered on top of LadybugDB (rejected — premature; LadybugDB roadmap may add native transactions; shim creates two transactional models in flight); block sprint-002 on LadybugDB upgrade (rejected — TC7 pins v0.15.3, no upgrade in sprint-002 scope).

**Consequences**: All mutation stories in Clusters B, C, D, E inherit the pattern via D-022. Closes the relitigation in mutation stories. Carries forward sprint-001's "partial-write window in inscription mirroring" risk explicitly — flagged as MEDIUM data-integrity follow-up in Cluster K (sprint-003). Generated TS client (FR8) calls into store wrapper (D-007), whose mutations follow this pattern.

---

## D-022: Bridge pattern — Zig staging → Bun bridge → promote-on-success

**Date**: 2026-04-21 (formalized 2026-04-28)
**Sprint**: sprint-002
**Significance**: HIGH
**Decided by**: auto-decided (formalizes sprint-001 pattern proven across 5 stories)
**Status**: accepted
**Source**: was D-NEW-B in retrospective; this ADR is the canonical text.

**Context**: Sprint-001 rediscovered a mutation pattern in 5 stories (palace-mint, palace-add-room, palace-inscribe, palace-move, palace-rename-mythos): Zig stages writes to a temp directory; Bun bridge invokes Zig + transforms; on success, promote staging-dir into the live CAS path. Without this pattern, a crashed mutation leaves the CAS in an inconsistent state. Action manifest implementations (FR7, FR10) inherit this concern.

**Decision**: The bridge pattern is the canonical mutation primitive for sprint-002. Implementation:
1. Bun-side caller computes intended write set.
2. Calls Zig CLI with `--staging-dir=<tmp>` flag (or equivalent for wasm action via host import).
3. Zig writes envelopes to staging dir; emits success/failure.
4. On success, Bun atomically renames staging into live CAS path (`fs.renameSync(stagingDir, livePath)`); on failure, removes staging.
5. ActionLog append happens after promote (not before) — replay-from-CAS (D-021) is consistent.

Wasm actions (FR10) compose the same primitive: the host's `dreamball.emit_action_envelope` writes to a per-invocation staging area; the host promotes after the action returns successfully.

**Alternatives**: Direct write into live CAS with rollback log (rejected — adds a second durability mechanism); skip staging and rely on idempotent replay alone (rejected — partial writes at crash boundaries leak observable inconsistent state to readers); LadybugDB-native transaction (rejected — D-021/TC7 — not available).

**Consequences**: All Cluster C, D, E mutation paths use the bridge pattern. The wasm action host (FR10) brokers it via `dreamball.emit_action_envelope`. Bun-side bridges in `src/lib/bridge/*` are the canonical examples; new actions follow the same template. Failure mode: orphan staging directories on hard crash — documented as periodic-cleanup follow-up (sprint-003). Reusable across action implementations means D-022 is load-bearing for FR10 just as much as it is for FR7.

---

## D-023: Dual-sig parameterisation through `jelly.wasm` `signActionEnvelope` export

**Date**: 2026-04-21 (revised 2026-04-28; PQ deferred per 2026-04-25 steering)
**Sprint**: sprint-002
**Significance**: HIGH
**Decided by**: auto-decided (formalizes sprint-001 S4.4/S5.5 silent-substitution remediation)
**Status**: accepted; **revises D-011** (signer parameterisation portion only; key custody portion of D-011 unchanged)
**Source**: was D-NEW-C in retrospective; this ADR is the canonical text.

**Context**: Sprint-001 stories S4.4 and S5.5 silently substituted derived-fp sentinels for real signatures because `jelly.wasm` lacked a `signActionEnvelope(keypair_bytes, payload_bytes)` export. This was a HIGH regression class (silent scope substitution) that sprint-002 must close. **Per 2026-04-25 steering, sprint-002 ships Ed25519-only single signatures**; PQ dual-sig parameterisation is explicitly deferred to the security pass (project memory `project_dreamball_pq_deferred`).

**Decision**: `jelly.wasm` exports `signActionEnvelope(keypair_bytes, payload_bytes) → ed25519_sig_bytes` for sprint-002 (Ed25519 single signature only). Both sentinel call sites (`oracle.ts oracleSignAction`, `store.recordTraversal`) migrate to consume this export. The export is the single seam through which signatures are produced; no other code path emits or substitutes signatures. **PQ dual-sig parameterisation (ML-DSA-87 in addition to Ed25519) is deferred to the security pass.**

**Alternatives**: Ship dual-sig (Ed25519 + ML-DSA-87) parameterisation in sprint-002 (rejected — explicit 2026-04-25 steering deferral; out of scope per SEC6); leave sentinels in place with a TODO (rejected — same regression class as the original substitution; sprint-002 must close it); implement Ed25519 signing in TS without going through wasm (rejected — violates cross-runtime invariant; signature primitives belong in the Zig core / wasm export surface).

**Consequences**: Drives FR13/SEC3 (Ed25519 sentinel migration). Closes sprint-001 "scope substitution" debt for the signature emission path. Adds one export to `jelly.wasm`; size budget (TC5: ≤200 KB raw / ≤64 KB gzipped) must verify. The wasm action host's `dreamball.emit_action_envelope` (FR11/SEC2) uses this same export internally — guests cannot forge signatures because they have no access to private key material; the host calls `signActionEnvelope` after the action returns. Updates `docs/known-gaps.md` "scope substitution" entry to closed; PQ dual-sig debt remains open under security-pass section.

---

## D-024: Spike-before-promote default for new shaders/materials/lenses

**Date**: 2026-04-21 (formalized 2026-04-28)
**Sprint**: sprint-002
**Significance**: MEDIUM
**Decided by**: auto-decided (formalizes sprint-001 D-009 revision lesson)
**Status**: accepted
**Source**: was D-NEW-D in retrospective.

**Context**: Sprint-001 D-009 ("aqueduct-flow E2E spike") was originally one shader spike, broadened mid-sprint to a 4-shader pack with 3 follow-up stories. The spike-then-promote pattern was the right shape; it just wasn't formalized as the default for new visual surfaces. Sprint-002 has minimal new visual surface (it's a tools/protocol sprint), but the rule applies symmetrically to wasm actions and `dreamball.*` imports.

**Decision**: For any new shader, material, lens, or wasm action that introduces an unfamiliar host or API surface: ship a spike story first (proof-of-concept on one minimal end-to-end case) before scaling to N occurrences. The spike's deliverable is the architectural commitment that the follow-up stories inherit; it MUST land green before follow-ups dispatch.

For sprint-002 specifically, this rule applies to:
- The first wasm action implementation (Cluster E spike: minimal `mint.wasm` → `dreamball.*` host → emit envelope → smoke pass) before scaling to all 5 verbs.
- The root JSON Schema codegen (Cluster A spike: round-trip the three most expressively complex Zig types — envelope, sealed body, signature tier wrapper — before generating from the full root schema).
- The CBOR golden vector authoring (FR3 spike before scaling to all root + Memory Palace types).

**Alternatives**: Skip the spike and ship N implementations in parallel (rejected — sprint-001 D-009 demonstrated the cost; debugging N failures simultaneously is much more expensive than catching the architectural mismatch in one); make spike-before-promote optional per-team-judgment (rejected — sprint-001 showed even D-009-style spike-aware planning got broadened; the default needs to be explicit).

**Consequences**: Cluster A, Cluster C (first action manifest), Cluster E (first wasm action) each lead with a spike story. Phase 3 story decomposition must front-load these. Test-tier defaults (D-036) should mark the spike stories as `thorough`.

---

## D-025: Forward-declare consumer seam contracts in `architecture-decisions.md`

**Date**: 2026-04-21 (formalized 2026-04-28)
**Sprint**: sprint-002
**Significance**: MEDIUM
**Decided by**: auto-decided (formalizes sprint-001 D-012 lesson)
**Status**: accepted
**Source**: was D-NEW-E in retrospective.

**Context**: Sprint-001 D-012 (embedding endpoint shape) had to be reconciled across 3 stories (S4.4 → S6.1 → S6.2) because the contract was authored in the first consuming story rather than as an architecture decision. Sprint-002 has multiple cross-epic seams: the `dreamball.*` import surface, the action manifest shape, the generated TS client interface, the bridge pattern signature. Each must be declared as architecture, not as a story-execution emergent.

**Decision**: Cross-epic contracts (i.e., wire shapes consumed by ≥2 epics or clusters) MUST be authored in `architecture-decisions.md` before the producing story dispatches. Adding a new entry to such a contract during story execution is an architecture-decision event (require ADR amendment), not a story-execution decision.

For sprint-002, the contracts subject to this discipline:
1. **`dreamball.*` import surface** — see D-030. Locked to 5 imports for sprint-002; any addition is a new ADR.
2. **Action manifest shape** — see D-019/FR6. Closed `attributes` set + closed `effects.kind` enum (D-035); validator rejects unknown.
3. **Generated TS client API surface** — see D-031. Integrates with D-007 store wrapper; relationship locked.
4. **Bridge pattern signature** — see D-022. Single canonical template; new mutations follow it.
5. **Pin file format** — see D-029. Locked structure; refresh path optional and documented.
6. **Wasm host import contract** — see D-032. Single shared host code targeting CLI + browser.

**Alternatives**: Allow contracts to emerge during story execution and reconcile late (rejected — sprint-001 D-012 demonstrated the cost); require every wire shape to be an ADR even if only one story consumes it (rejected — over-burdens authoring; the rule is ≥2 consumers).

**Consequences**: Phase 3 story decomposition must check that every cross-epic contract referenced by a story has a corresponding architecture decision. Stories that introduce contracts ad-hoc are rejected at story-spec review. Reduces mid-sprint reconciliation cost.

---

## D-026: Surface registry + fallback chain

**Date**: 2026-04-24 (promoted 2026-04-28)
**Sprint**: sprint-002 (originated sprint-001)
**Significance**: MEDIUM
**Decided by**: auto-decided (already drafted ADR; this entry is the promotion record)
**Status**: accepted
**Source**: [docs/decisions/2026-04-24-surface-registry.md](../../decisions/2026-04-24-surface-registry.md)

**Context**: `jelly.inscription.surface` is `<open-enum>` in PROTOCOL.md §13.7. Sprint-001's `InscriptionLens.svelte` hard-codes dispatch on the five canonical surfaces with `scroll` fallback. Cross-engine story (Unreal/Blender/MR-VR lenses adding their own surfaces) needed formalization.

**Decision**: Surfaces stay open strings on the wire. Each lens implementation publishes a registry of natively-rendered surfaces. `scroll` is the canonical baseline (every lens MUST render it). Authors MAY attach an optional `fallback` ordered-array attribute. On render: walk `surface → fallback[0] → ... → "scroll"`, stopping at first registered. Cycles emit `surface-fallback-cycle` event and break to `scroll`. One additive `fallback` field on `jelly.inscription`; old readers ignore (no format-version bump).

**Alternatives**: See source ADR (closed union; nested envelope; lens-only registry without fallback).

**Consequences**: Renderer projection (deferred to sprint-003 / Cluster L) inherits this contract. Sprint-002 scope: no immediate consequence — the contract is already on the wire. Documentation refresh (FR15) should ensure PROTOCOL.md §13.7 reflects this ADR.

---

## D-027: Coord-frames composition — polar field, cartesian placements, nested reference frames

**Date**: 2026-04-24 (promoted 2026-04-28)
**Sprint**: sprint-002 (originated sprint-001)
**Significance**: MEDIUM
**Decided by**: auto-decided (already drafted ADR; this entry is the promotion record)
**Status**: accepted
**Source**: [docs/decisions/2026-04-24-coord-frames.md](../../decisions/2026-04-24-coord-frames.md)

**Context**: Dreamballs are nested spheres (PROTOCOL.md §12.2, VISION.md §10). Polar at the field layer matches semantic intent; cartesian everywhere else matches GPU/library reality. The ADR formalizes the two-regime composition.

**Decision**: Two coordinate regimes — polar at the omnispherical-grid (field) layer, cartesian (right-handed, Y-up, meters, glTF-2.0 quaternion order) for placements local to parent dreamball. Nested reference frames compose via cached world matrices (`resolveWorldMatrices`); GPU consumes `worldMatrix × localPosition` (zero polar math in shader). Sprint-001 simplified path documented; `polarShellToCartesian` and full multi-frame resolution are Growth-tier work.

**Alternatives**: See source ADR (polar everywhere; global cartesian with no nesting; defer the decision).

**Consequences**: Renderer projection (sprint-003 / Cluster L) inherits this contract. Sprint-002 scope: no immediate consequence — already on the wire. Documentation refresh (FR15) should cite this ADR alongside §13.2 in PROTOCOL.md.

---

## D-028: Triple-native KG storage

**Date**: 2026-04-24 (promoted 2026-04-28)
**Sprint**: sprint-002 (originated sprint-001 hardening pass)
**Significance**: HIGH
**Decided by**: auto-decided (already drafted ADR; this entry is the promotion record)
**Status**: accepted; **revises D-016**
**Source**: [docs/decisions/2026-04-24-kg-triple-native-storage.md](../../decisions/2026-04-24-kg-triple-native-storage.md)

**Context**: Pre-2026-04-24 the oracle Agent's KG lived in `Agent.knowledge_graph STRING` (JSON array of triples). Three problems: not CBOR-native on disk; O(n²) replay cost; no versioning story.

**Decision**: Native graph storage — `Triple` node table (`fp` MERGE key derived as `blake3(agent_fp || \0 || subject || \0 || predicate || \0 || object)`), `HAS_KNOWLEDGE` rel from `Agent` to `Triple`. `Agent.knowledge_graph` removed. Idempotent insert via fp existence check. CBOR remains wire format on ActionLog envelopes; Triple rows are derived state replayable from ActionLog.

**Alternatives**: See source ADR.

**Consequences**: Drives FR4 (Memory Palace schema extraction) — the generated Cypher DDL must include the `Triple` table and `HAS_KNOWLEDGE` rel as schema citizens. Codifies `Palace→Agent CONTAINS` edge and `Aqueduct.last_traversal_ts` as schema citizens (per retrospective). The generated `schema.cypher` must match the post-2026-04-24 hardened shape byte-for-byte (or with documented semantic-equivalent diffs per FR4 acceptance).

---

## D-029: aspects.sh contract — vendor-first with deterministic local pin file format

> **⚠️ PARTIALLY SUPERSEDED 2026-06-25** by
> [zig-canonical-supersedes-json-schema](../../decisions/2026-06-25-zig-canonical-supersedes-json-schema.md).
> The vendor-first + pin-file mechanism stands, but its *direction* flips:
> `schemas/*.json` are now **generated outputs** (and golden fixtures),
> not authored inputs. Pins gate that the generated schema matches the
> committed fixture, not that an external source matches a vendored copy.

**Date**: 2026-04-28
**Sprint**: sprint-002
**Significance**: HIGH
**Decided by**: user (elicitation candidate — recommended in sprint-scope; canonicalize here)
**Status**: accepted (recommended; user confirmation requested)

**Context**: Q4 from Phase 1B. aspects.sh is built by a parallel agent; sprint-002 must function fully against locally-vendored schemas regardless of that agent's status (TC6). The vendor-first recommendation needs an architectural commitment for: (a) where schemas live, (b) where fp pins live, (c) how the optional refresh path is structured, (d) how fp verification wires into the build. Drives Cluster A (FR1, FR4) and Cluster H (FR15 doc refresh).

### Options

**Option A: Pin file beside schema, refresh as Bun script (RECOMMENDED)**
- Approach: Schemas live at `schemas/<archiform>-<version>.json`. Pin files live at `schemas/.pins/<archiform>-<version>.fp` (one file per schema, plain-text blake3 hex). Refresh path = `bun run schemas:refresh` (Bun script that fetches from aspects.sh, verifies fp matches pin, swaps in if matched, errors if mismatched). Build-time verification: `zig build schemagen` reads pin file, computes blake3 of vendored schema, fails build if mismatch.
- Pros: Pin files visible in git diff per archiform; refresh script is plain Bun (no Zig dep); build verification cheap; natural place for `bun run schemas:list` future tooling.
- Cons: Adds a `.pins/` directory; pin file is a separate file per schema (small file count growth).
- Downstream impact: Cluster A: `zig build schemagen` reads pin alongside schema; FR1 acceptance includes pin-verification step. Cluster H: `docs/PROTOCOL.md` cites pin file format.

**Option B: Pin embedded in schema file as `$id` URI suffix or comment**
- Approach: Pin lives in the JSON Schema document itself (e.g., as `"$comment": "fp:blake3:..."` or as an `$id` URI suffix). No separate file.
- Pros: Single file per schema; can't drift between pin and schema (they ship together).
- Cons: Pin is part of the file it identifies (chicken-and-egg: blake3 of the file with the pin embedded ≠ blake3 of the canonical schema); requires "pin computed over canonicalized form excluding the pin field"; harder to git-diff a pin update.
- Downstream impact: Generators must canonicalize the schema (strip the pin field) before computing blake3. More complex than Option A.

**Option C: Block sprint-002 on aspects.sh shipping `kind: "schema"` first**
- Approach: Wait for parallel agent to ship aspects.sh schema-aspect support, then fetch from there at codegen time.
- Pros: Single source of truth (aspects.sh).
- Cons: External dependency on parallel agent's velocity; violates TC6 (vendor-first contract); makes CI depend on aspects.sh availability; no path forward if parallel agent slips.
- Downstream impact: Cluster A blocks on parallel agent. Sprint-002 schedule risk increases significantly.

### Recommendation
**Option A**. Aligns with TC6 (vendor-first); pin file format is straightforward; refresh path is optional and documentable; CI gates only need a local file read + blake3 compute. Pin format: plain text, one line, hex-encoded blake3 of the canonical JSON Schema (LF line endings, no trailing newline normalization considerations because the pin computes blake3 over the file as-vendored, which IS the canonical form).

### Consequences
- Drives FR4 acceptance (`schemas/.pins/memory-palace-0.1.0.fp` records blake3).
- New build-time verification step: every `bun run codegen` recomputes pin and fails on mismatch (this is also how D-033 validate-on-codegen integrates).
- Refresh path `bun run schemas:refresh <archiform>` documented as optional; not a CI gate.
- Documentation: `docs/PROTOCOL.md` adds a §"Schema vendoring and pin format" subsection (FR15).
- New file pattern: `schemas/.pins/*.fp` files in repo, lifecycle = bump-on-schema-update.

---

## D-030: `tools/schema-gen/main.zig` disposition — repurpose as JSON-Schema consumer entry point with shadow-generator phase

> **⛔ SUPERSEDED 2026-06-25** by
> [zig-canonical-supersedes-json-schema](../../decisions/2026-06-25-zig-canonical-supersedes-json-schema.md).
> The codegen direction reverts: `main.zig` consumes the **Zig types**
> (comptime `@typeInfo` reflection) and emits every other representation
> including JSON Schema — it does not consume JSON Schema. Disregard the
> "JSON-Schema consumer" framing below.

**Date**: 2026-04-28
**Sprint**: sprint-002
**Significance**: HIGH
**Decided by**: user (elicitation candidate — recommended; canonicalize here)
**Status**: accepted (recommended; user confirmation requested)

**Context**: Q8 from Phase 1B. Today `tools/schema-gen/main.zig` is the Zig-canonical schema generator (1,480 lines). Sprint-002 inverts it to consume JSON Schema. The structural disposition affects file layout, build wiring, and how the FR14 shadow-generator phase is achieved. Drives Cluster A (FR1, FR2, FR3, FR14).

### Options

**Option A: Repurpose `main.zig` as JSON-Schema consumer entry point; per-target generators alongside (RECOMMENDED)**
- Approach: Rename old `main.zig` to `tools/schema-gen/legacy/main.zig` for shadow phase. New `tools/schema-gen/main.zig` is the JSON-Schema consumer entry point. Per-target generators live as siblings: `tools/schema-gen/gen_zig.zig`, `gen_ts.zig`, `gen_valibot.zig`, `gen_cbor.zig`, `gen_cypher.zig`. Shadow-generator phase: `zig build schemagen` runs both legacy and new in parallel, emits to `src/lib/generated/` (new) and `src/lib/generated.legacy/` (old), byte-equivalence test diffs them. Cutover: delete `legacy/` directory in its own commit.
- Pros: Single entry point per build target; legacy code preserved for byte-diff during shadow phase; cutover is one commit (delete dir); per-target files keep each generator small and focused.
- Cons: Adds a `legacy/` directory temporarily; build must wire two binaries during shadow phase.
- Downstream impact: Cluster A: clean file structure; FR14 shadow phase has natural location (`src/lib/generated.legacy/`); cutover commit is small (delete dir + flip build).

**Option B: Feature-flag inside existing `main.zig`**
- Approach: Keep one `main.zig` file; `--mode=legacy|json-schema` flag selects path. Shadow phase: build runs `main.zig --mode=legacy` and `main.zig --mode=json-schema` and diffs. Cutover: remove flag and legacy code from `main.zig`.
- Pros: One file; one binary.
- Cons: `main.zig` becomes ~2,500 lines for the duration of the shadow phase; cutover requires careful surgery within one file rather than a clean directory delete; legacy code intermingled with new code increases regression risk.
- Downstream impact: FR14 shadow phase is harder to reason about; cutover is riskier.

**Option C: Branch-then-merge (delete legacy first, then build new)**
- Approach: Delete `main.zig` legacy code at start of Cluster A. Build new generator from scratch. No shadow phase.
- Pros: Clean slate; no two-implementations-in-flight cost.
- Cons: Violates FR14 (shadow-generator phase is an explicit acceptance criterion; byte-equivalence requires a reference to compare against); breaks NFR1 verification (no live Zig generator to byte-diff against during development); high regression risk because there's no fallback during the migration.
- Downstream impact: Sprint-002 schedule risk significantly higher; NFR1 acceptance can't be verified incrementally.

### Recommendation
**Option A**. Cleanest separation; FR14 shadow-generator phase has natural file structure; cutover commit is small and reversible. The `legacy/` subdirectory naming makes intent obvious.

### Consequences
- Drives FR1 (root JSON Schema consumer entry point at `tools/schema-gen/main.zig`).
- Drives FR2 (`tools/schema-gen/gen_zig.zig` is the generator that produces `src/protocol_v2.zig` extensions).
- Drives FR14 (shadow phase: `src/lib/generated.legacy/` exists during shadow, deleted at cutover).
- New file structure: `tools/schema-gen/{main,gen_zig,gen_ts,gen_valibot,gen_cbor,gen_cypher}.zig` + `tools/schema-gen/legacy/main.zig` (deleted post-cutover).
- Build wiring: `build.zig schemagen` step runs new generator; shadow phase adds a `schemagen-legacy` step; cutover removes the legacy step.
- Provenance headers (NFR9) generated by each per-target generator.
- Structured logging (NFR10) is `main.zig`'s concern (which schemas read, which generators dispatched, which outputs written).

---

## D-031: Wasm module signing — signed schema body + content-addressed wasm (transitive authentication)

**Date**: 2026-04-28
**Sprint**: sprint-002
**Significance**: HIGH
**Decided by**: user (elicitation candidate — recommended; canonicalize here)
**Status**: accepted (recommended; user confirmation requested)

**Context**: Q9 from Phase 1B. SEC4 mandates blake3 verify-before-instantiate for wasm modules. The trust model needs explicit choice: is the wasm module body itself signed (each module carries its own detached signature), or is the schema-aspect body signed and the wasm fp inside the action manifest is transitively authenticated by the schema signature? Drives Cluster E (FR10, FR11) and Cluster B (FR4 — schema is the unit of signing).

### Options

**Option A: Signed schema body + content-addressed wasm (transitive authentication) (RECOMMENDED)**
- Approach: The schema-aspect body (the JSON Schema document) is signed by its publisher (using aspects.sh's existing aspect-signing mechanism). The schema body contains the action manifest, which contains `implementation.wasm` fps. Wasm modules are content-addressed by `blake3(wasm_bytes)`. Trust chain: trust the publisher's signature on the schema → trust the wasm fps inside the schema → wasm bytes verified by blake3 match before instantiation (SEC4).
- Pros: One signature per archiform schema, not one per module; aligns with aspects.sh's existing signing model; no per-module signature management; clear trust boundary (the schema author authorizes the wasm fps).
- Cons: A wasm bug fix requires reissuing the schema (with new wasm fp + new signature); wasm and schema lifecycles are coupled.
- Downstream impact: Cluster E: SEC4 verification reduces to blake3 match; no per-module signature verify code needed. Cluster B: FR4 (schema authoring) is also where wasm fps are pinned; updating any wasm requires updating the schema. Aspects.sh integration: rely on aspects.sh's signature verification (no new code).

**Option B: Each wasm module carries its own detached signature**
- Approach: Each wasm module has a sibling `.sig` file (or signature bytes prepended/appended to the module). Host verifies signature before instantiation in addition to blake3 fp match.
- Pros: Wasm bug fixes can ship independently of schema reissuance; per-module signatures carry per-module provenance.
- Cons: Two signatures to manage per module (the publisher's signature + the schema-pin signature); more complex trust model; doesn't align with aspects.sh's aspect-signs-the-whole-body model; what does the per-module signature say beyond what the schema's fp pin already says?
- Downstream impact: Adds signature-verification code to the wasm host; introduces a separate signature lifecycle; weakens "the schema is the unit of trust" simplicity.

**Option C: No signatures on wasm; rely entirely on blake3 content-addressing**
- Approach: SEC4 (blake3 verify-before-instantiate) is the only check. The fp pin in the action manifest is the only thing connecting the wasm to "trusted code." If you trust the schema, you trust the wasm by transitively trusting the fp.
- Pros: Simplest possible model.
- Cons: Implicitly Option A but without the schema being signed; if the schema isn't signed, anyone who can produce a colliding fp (computationally infeasible with blake3, so this is essentially a non-issue) can substitute wasm. The actual missing piece is "is the schema signed at all?" If yes, this collapses to Option A; if no, the trust model has a gap.
- Downstream impact: Same as Option A IF aspects.sh signs schemas. Becomes a security gap if aspects.sh doesn't.

### Recommendation
**Option A**. Aligns with aspects.sh's existing aspect-signing model; minimizes per-module signature ceremony; wasm-and-schema-lifecycle coupling is the right semantics (the schema declares the action surface; the wasm is the implementation; they evolve together).

### Consequences
- Drives FR10 (verify-before-instantiate via blake3 only — no per-module signature check needed in sprint-002).
- Drives SEC4 trust-model documentation: trust chain is "publisher signs schema body (via aspects.sh signing primitive) → schema body contains action manifest with wasm fps → wasm verified by blake3 before instantiation."
- Schema reissuance is required for any wasm body change. Documented in FR15 (PROTOCOL.md §"Wasm module signing and trust model").
- Aspects.sh schema-aspect type (D-017) inherits aspects.sh's existing publisher-signature semantics; no new signing code in sprint-002 wasm host.
- The "wasm body changes require schema reissue" lifecycle coupling is intentional: it forces archiform authors to think of "schema + actions" as one versioned unit, which matches the manifest-as-contract framing (D-019/D-025).

---

## D-032: Wasm host architecture — single shared host code targeting both CLI (Zig+WASI) and browser (WebAssembly without WASI)

**Date**: 2026-04-28
**Sprint**: sprint-002
**Significance**: HIGH
**Decided by**: auto-decided (sprint-scope-derived; recommendation from D-020 §Consequences)
**Status**: accepted

**Context**: The CLI host (Zig + WASI for filesystem/network), the browser host (jelly.wasm-style; WebAssembly without WASI), and the jelly-server host all need to load action wasm modules. The 2026-04-25 wasm-runtime ADR §Consequences says "the same host code is reused for lens-side derivations" — implying single shared host code. Drives Cluster E (FR10) and the cross-runtime invariant (CLAUDE.md).

### Options

**Option A: Single shared Zig host code; WASI imports broker through `dreamball.*` only (RECOMMENDED)**
- Approach: One Zig codebase implements the wasm host. Compiles to two targets: (i) `jelly` CLI binary (Zig + WASI runtime linked in, broker WASI capabilities through `dreamball.*`); (ii) `jelly.wasm` (WebAssembly module that itself loads guest wasm via the WebAssembly JS API, no WASI). Both expose the same `dreamball.*` import contract to guests. The host code that handles `dreamball.*` calls (compute fp, encode CBOR, read node, emit envelope, get time) is identical across targets; only the platform-shim layer (file I/O, network) differs.
- Pros: Cross-runtime invariant strengthened — host behavior identical; FR11 surface is one contract for two hosts; jelly-server and browser hosts share the bug-fix lifecycle; renderer projection (sprint-003) inherits the same host with no new code.
- Cons: WASI-on-darwin/linux quirks must be handled in CLI host shim; browser host needs JS-side glue for filesystem-equivalents (nothing for sprint-002, since browser wasm host isn't shipping in sprint-002 — but the contract is locked).
- Downstream impact: Cluster E: one host implementation, two compile targets; FR11 imports identical across both. CLAUDE.md cross-runtime invariant: refined to "host code identical, platform shims differ."

**Option B: Separate per-runtime hosts with shared `dreamball.*` import contract spec**
- Approach: CLI host in Zig, browser host in TypeScript (or Zig→wasm), jelly-server host in TypeScript. Shared spec document for the `dreamball.*` import contract; each host implements the spec independently.
- Pros: Each host can use its native runtime idioms; no cross-target compilation complexity.
- Cons: Three implementations to keep in sync; spec drift becomes a real risk; bug fixes triplicated; violates the cross-runtime invariant in spirit (multiple sources of truth for behavior).
- Downstream impact: Triple maintenance burden; FR15 documentation must explicitly call out the three implementations and how they're kept in sync.

### Recommendation
**Option A**. Aligns with cross-runtime invariant (CLAUDE.md). FR10 acceptance ("Wasm host code reusable in the browser/`jelly.wasm` host context without source divergence") explicitly mandates this. Sprint-002 ships only the CLI side; browser/jelly-server inherit at sprint-003 with no new host code.

### Consequences
- Drives FR10 acceptance (host code reusable in browser without source divergence).
- Sprint-002 ships CLI host only (`jelly` binary loads action wasm via Zig's wasm runtime + WASI). Browser host is a sprint-003 deliverable but uses the same Zig source.
- Cross-runtime invariant (CLAUDE.md) refined: "host code identical across CLI/browser/jelly-server; platform shims differ."
- Cluster E story decomposition: build host once, compile twice (test cross-compilation in CI as part of FR10 acceptance).
- Implementation note: Zig has good wasm-host support via `wasm` runtime in std lib OR by linking against `wasmtime`/`wasmer` C ABIs. Sprint-002 spike chooses (Assumption #2 in requirements.md mandates this spike).
- The `dreamball.*` import surface (D-030, FR11) is one spec, one Zig implementation, two compile targets. No spec-drift risk.

---

## D-033: `dreamball.*` import surface locked to 5 imports for sprint-002; any addition is a new ADR

**Date**: 2026-04-28
**Sprint**: sprint-002
**Significance**: MEDIUM
**Decided by**: auto-decided (formalizes D-025 forward-declare discipline)
**Status**: accepted

**Context**: FR11 names 5 imports for sprint-002 (`dreamball.fp`, `encode_cbor`, `read_node`, `emit_action_envelope`, `now_ms`). Per D-025 (forward-declare consumer seam contracts), the surface needs explicit lock: is this the complete sprint-002 surface, or is the surface evolved per-action-need? Drives Cluster E (FR11) and prevents D-NEW-E recurrence (sprint-001 D-012 ad-hoc evolution lesson).

### Options

**Option A: Lock the 5 for sprint-002; any addition is a new ADR (RECOMMENDED)**
- Approach: The `dreamball.*` import surface for sprint-002 is exactly 5 imports. If a story discovers it needs another import, the story is paused, an architecture-decision amendment is opened (new ADR D-NNN documenting the new import), and the story resumes after the ADR lands. No silent additions.
- Pros: Honors D-025 discipline; prevents the D-012 reconciliation pattern; forces architectural thought before surface growth; `docs/dreamball-imports.md` is a complete reference at sprint end.
- Cons: Slight overhead per addition; requires architecture-amendment process during sprint execution.
- Downstream impact: Cluster E: FR11's `docs/dreamball-imports.md` is the locked reference. Phase 3 story decomposition: stories that need new imports must call them out at planning time, not execution time.

**Option B: Surface evolves per-action-need; document additions in story Dev Agent Record**
- Approach: If a story needs a new import, add it; document in the story's Dev Agent Record; reconcile at sprint end.
- Pros: Less ceremony.
- Cons: Reproduces D-012 reconciliation pattern; surface grows ad-hoc; `docs/dreamball-imports.md` becomes inconsistent with code mid-sprint.
- Downstream impact: Sprint-001 D-012 lesson re-learned the hard way.

### Recommendation
**Option A**. The whole point of D-025 is to prevent this pattern. Locking the surface is cheap; evolving it is the cost we pay only when we actually need to.

### Consequences
- Drives FR11 acceptance (`docs/dreamball-imports.md` enumerates exactly 5 imports for sprint-002).
- Phase 3 story decomposition: each story that calls a `dreamball.*` import names which one(s); stories needing a new import are flagged at planning.
- Mid-sprint discovery of a missing import = blocker per `feedback_dreamball_ac_scope_retreat` (raise blocker, don't silently substitute); resolution = architecture amendment.
- Sprint-end deliverable: `docs/dreamball-imports.md` with 5 imports, each documented with arity, types, error semantics, host-trust notes (per FR11 acceptance).

---

## D-034: Generated TS client integration — generated client wraps existing D-007 store wrapper (D-007 unchanged)

**Date**: 2026-04-28
**Sprint**: sprint-002
**Significance**: HIGH
**Decided by**: user (elicitation candidate — recommended; canonicalize here)
**Status**: accepted (recommended; user confirmation requested)

**Context**: The action manifest projection produces a generated `@dreamball/palace-client` TS module (FR8). How does it integrate with the existing `src/memory-palace/store.ts` wrapper (D-007)? Two paths: (a) generated client IS the new store wrapper boundary (D-007 evolves; domain verbs become manifest-derived); (b) generated client wraps the existing store wrapper (D-007 stays unchanged; client calls store verbs internally). Drives Cluster D (FR8), affects FR7, IC6.

### Options

**Option A: Generated client wraps existing D-007 store wrapper; D-007 unchanged (RECOMMENDED)**
- Approach: The generated `@dreamball/palace-client` exposes typed action functions (`mint`, `inscribe`, `add-room`, etc.). Each function calls into the existing `store.ts` domain verbs to perform mutations. Generated client is the *external* (callsite) API; store wrapper remains the *internal* (mutation primitive) API. AC7-style grep audits carry forward unchanged: `__rawQuery` still only allowed where D-007 says it is.
- Pros: D-007 (the most load-bearing decision per active-decisions.md, "zero `__rawQuery` drift across 15 stories") stays exactly as is; no migration; AC7 audits unchanged; clear separation of concerns (client = projection, store = mutation primitive).
- Cons: Two layers of abstraction (client → store → ladybugdb). Slight indirection cost.
- Downstream impact: Cluster D: FR8 generates client; FR8 acceptance tests the bridge migration site; D-007 audits unchanged. IC6 satisfied (store API shape unchanged).

**Option B: Generated client IS the new store wrapper boundary; D-007 evolves to be manifest-derived**
- Approach: The generated client replaces the hand-written `store.ts` domain verbs. Manifest-derived functions become the only sanctioned mutation path. AC7 audits move from "no `__rawQuery` outside `store.ts`" to "no `__rawQuery` outside the generated client."
- Pros: Single layer of abstraction; the manifest is truly the source of truth for the mutation surface.
- Cons: Violates IC6 (store API shape unchanged) and the "DO NOT propose architectural changes to D-007" prompt constraint; D-007 is the most load-bearing sprint-001 decision and changing it has risk; AC7 audits must be rewritten; existing call sites must migrate.
- Downstream impact: Significantly larger sprint-002 footprint; touches every store-consumer; high regression risk.

### Recommendation
**Option A**. IC6 mandates store API shape stays unchanged. D-007 is load-bearing; the generated client is additive (a new caller of D-007), not a replacement. The client is the manifest projection; D-007 is the mutation primitive; both can be true simultaneously without conflict.

### Consequences
- Drives FR8 acceptance: existing `src/lib/bridge/*` mutation site migrates to call the generated client; client internally calls D-007 store verbs; existing Vitest coverage continues to pass.
- IC6 satisfied (store API shape unchanged).
- D-007 AC7-style grep audits unchanged (still: `no __rawQuery in oracle.ts; no fetch( in file-watcher.ts`; D-007's sanctioned use stays as the only exception).
- Generated client lives at `@dreamball/palace-client` (package or path alias TBD by Phase 3).
- Bridge pattern (D-022) continues to be how mutations cross Zig↔TS; generated client is one of its callers.
- New AC suggestion for FR8 stories: grep audit that generated client never imports LadybugDB primitives directly (always goes through `store.ts`).

---

## D-035: Action manifest `attributes` is a closed set; `effects.kind` is a closed enum; validator rejects unknown

**Date**: 2026-04-28
**Sprint**: sprint-002
**Significance**: MEDIUM
**Decided by**: auto-decided (formalizes Missing Guardrail #3 + #10 + Q-derived recommendation)
**Status**: accepted

**Context**: FR6 + Missing Guardrails #3 (`attributes` closed set) and #10 (`effects.kind` closed enum: `ActionEnvelope`, `Read`, `Derived`) need explicit closure-vs-open decision. Phase 1B Open Question said "closed for sprint-002 + `x-` prefix reserved for sprint-003+ experimental work." Drives Cluster C (FR6) and Cluster D (validator must reject unknown attributes/kinds).

### Decision

**Closed sets for sprint-002:**

- **`attributes`** field — exactly four keys allowed: `destructive: bool`, `requiresConfirmation: bool`, `confirmationMessage: string`, `agentVisible: bool`. Validator rejects any other key.
- **`effects.kind`** enum — exactly three values: `ActionEnvelope`, `Read`, `Derived`. Validator rejects any other value.
- **`x-` prefix experimental convention** — reserved for sprint-003+; not active in sprint-002. Validator rejects `x-*` keys in sprint-002 to prevent accidental drift.
- **`idempotency`** enum — sprint-001's recognized values inherited (`creates`, `updates`, `idempotent`); validator rejects unknown.

### Alternatives

- Open `attributes` with `x-` prefix convention enabled (rejected — sprint-002 needs exact validator behavior; experimental convention is sprint-003+ scope).
- Open `effects.kind` with `kind` registry (rejected — registry is overhead for 3 values; closed enum is simpler).

### Consequences

- Drives FR6 acceptance: generated Valibot validator rejects malformed manifests including unknown attributes, unknown `effects.kind` values, unknown `idempotency` values.
- Drives Cluster D (FR8/FR9): generated TS client and MCP tool spec inherit the closed set (typed accordingly).
- Sprint-003 expansion path documented: opening `x-` prefix is a new ADR; adding new `attributes` keys or `effects.kind` values is a new ADR.
- FR6 "pure-transaction" lint composes with this: lint rejects manifests where `inputs.properties.*` is named `prompt`/`confirm` or has `format: "tty-interactive"`; validator rejects malformed `attributes`/`effects`. Two layers, both mechanical.

---

## D-036: Test-tier defaults per cluster — Cluster A/E thorough; Cluster B/C/D/G/H smoke; nothing yolo

**Date**: 2026-04-28
**Sprint**: sprint-002
**Significance**: MEDIUM
**Decided by**: auto-decided (formalizes Phase 3 input)
**Status**: accepted

**Context**: Sprint-001 used yolo/smoke/thorough test tiers. Sprint-002 should set defaults per cluster so Phase 3 story decomposition picks up the right tiers without per-story negotiation. Drives Phase 3 (story decomposition) and Phase 4 (execution).

### Decision

**Default test tier per cluster:**

| Cluster | Default tier | Rationale |
|---|---|---|
| **A — Codegen Inversion** | thorough | NFR1 byte-equivalence is the binary gating constraint; this is the highest-stakes cluster; full gate set required |
| **B — Memory Palace as Archiform** | smoke | FR4 acceptance includes byte-equivalence via Cluster A's gates; smoke captures the rest |
| **C — Action Manifest + CLI** | smoke | CLI smoke (`scripts/cli-smoke.sh`) is the existing gate; pure-transaction lint is the only new test surface |
| **D — Programmatic + MCP** | smoke | Vitest + bridge migration test cover the surface; MCP elicitation tested against pinned MCP SDK version |
| **E — Wasm Action Runtime** | thorough | New runtime surface; FR10/FR11 acceptance includes verify-before-instantiate failures, import-violation failures, memory-limit failures, cross-platform (darwin+linux) WASI parity (Assumption #2 spike) |
| **G — Sprint-001 Carry-Over (FR13)** | smoke | Small lift; existing crypto test infra covers Ed25519 paths; full-gate verification per `feedback_full_gate_verification` is mandatory |
| **H — Documentation Refresh** | smoke | Markdown lint + link checker + manual review; no functional test surface |

**Stretch Cluster I (Federation Proof)** — if pulled in: `thorough` (it's the integration test of the entire sprint per scope-risks #3).

**No cluster gets `yolo` tier in sprint-002.** Sprint-001 retrospective showed that even "small" stories benefit from the smoke gate; the binary nature of NFR1 and the cross-runtime invariant make yolo unsafe.

### Alternatives

- All clusters thorough (rejected — overkill; would balloon sprint duration).
- Per-story negotiation in Phase 3 (rejected — wastes Phase 3 cycles; cluster-level default is sufficient with story-level escalation if needed).

### Consequences

- Drives Phase 3 story decomposition: each story inherits its cluster's tier default; stories may escalate (smoke → thorough) with rationale; no story may de-escalate below smoke.
- Drives Phase 4 execution dispatch: thorough-tier stories run all 7 gates (zig build test + smoke; bun run check; bun run test:unit -- --run; scripts/cli-smoke.sh; scripts/server-smoke.sh; tests/e2e-cryptography.sh) before being reported done.
- Cluster A and E carry the highest test budget; this aligns with their highest-risk classification.
- Per-story escalation suggestions for Phase 3: any story authoring a new `dreamball.*` import (D-033) escalates to thorough; any story modifying signed-envelope shape escalates to thorough; spike stories (D-024) are thorough by default.

---

## Summary

**Total decisions authored**: 20 (D-017 through D-036)

**Breakdown by origin:**
- Promotions of standing 2026-04-25 notes: 4 (D-017..D-020) — HIGH significance, user-blessed
- Promotions of D-NEW-A..D-NEW-E (sprint-001 retrospective emergent): 5 (D-021..D-025) — HIGH (3) + MEDIUM (2)
- Promotions of already-drafted dated ADRs: 3 (D-026..D-028) — MEDIUM (2) + HIGH (1)
- New sprint-002 architecture decisions: 8 (D-029..D-036) — HIGH (4) + MEDIUM (4)

**Significance distribution (all 20):**
- CRITICAL: 0
- HIGH: 11 (D-017, D-018, D-019, D-020, D-021, D-022, D-023, D-028, D-029, D-030, D-031, D-032, D-034)
- MEDIUM: 7 (D-024, D-025, D-026, D-027, D-033, D-035, D-036)

**HIGH/CRITICAL needing user elicitation (Decision Steering candidates):**
- D-029 (Q4 — aspects.sh contract / pin file format) — RECOMMENDED Option A
- D-030 (Q8 — schema-gen disposition / file structure) — RECOMMENDED Option A
- D-031 (Q9 — wasm signing / trust model) — RECOMMENDED Option A
- D-032 (Wasm host architecture / single shared host) — RECOMMENDED Option A (auto-decided per FR10 acceptance text; flag for confirmation)
- D-034 (Generated TS client / store wrapper integration) — RECOMMENDED Option A (auto-decided per IC6; flag for confirmation)

**MEDIUM auto-decided (no elicitation):**
- D-024 (spike-before-promote)
- D-025 (forward-declare contracts)
- D-033 (lock dreamball.* surface to 5)
- D-035 (closed `attributes` + `effects.kind`)
- D-036 (test-tier defaults per cluster)
- D-026, D-027 (drafted ADR promotions; no new content)

**Promoted standing decisions (no elicitation needed; user already blessed):**
- D-017, D-018, D-019, D-020 (the four 2026-04-25 notes)
- D-021, D-022, D-023 (D-NEW-A/B/C from retrospective; revisions documented)
- D-028 (D-NEW-H from retrospective; revises D-016)

---

## Requirements Conflicts

After authoring D-017..D-036, the following potential conflicts with `requirements.md` were checked:

### No new requirements created

All 20 decisions either (a) implement existing FR/NFR/TC/SEC/IC, or (b) constrain HOW existing requirements are satisfied without adding new requirements. Specifically:

- D-029 (pin file format) constrains FR4 acceptance ("`schemas/.pins/memory-palace-0.1.0.fp` records blake3") — already in FR4 AC.
- D-030 (schema-gen file structure) constrains FR1, FR14 — implementation detail of existing acceptance criteria.
- D-031 (wasm signing trust model) implements SEC4 — adds clarity, not new requirement.
- D-032 (single shared host) implements FR10 acceptance ("host code reusable in browser without source divergence") — already in FR10 AC.
- D-033 (lock dreamball.* to 5) implements FR11 — names the 5 already enumerated.
- D-034 (client wraps store) implements IC6 + FR8 — preserves IC6, documents how.
- D-035 (closed attributes/effects.kind) implements FR6 + Missing Guardrails #3, #10 — already in requirements.
- D-036 (test-tier defaults) is a process artifact for Phase 3, not a requirement.

### One soft constraint surfaced for Phase 3 attention

**D-031 + FR4 lifecycle coupling implication:** The trust model in D-031 (signed schema + content-addressed wasm) means that any sprint-002 wasm bug fix in an action implementation requires reissuing the schema with a new signature. For sprint-002, the only schema is `dreamball/memory-palace@0.1.0` and the only wasm authors are the team. This is acceptable for sprint-002. **Phase 3 attention:** if Cluster I (federation proof / second archiform) is pulled in as stretch, the lifecycle coupling needs explicit acknowledgment in the second archiform's authoring story so the author understands the schema-reissue requirement.

### One open question carried to `.omc/plans/open-questions.md`

**Open question:** Cluster A spike (per D-024) needs to confirm Assumption #2 (WASI works inside `jelly` CLI on darwin AND linux without runtime divergence) before D-032's "single shared Zig host code" commitment is fully validated. If WASI cross-platform parity fails, D-032 may need amendment to allow per-platform CLI host shims. This is a spike outcome, not a Phase 2A unknown — but Phase 3 story decomposition should sequence the spike first.

(This open question will also be appended to `.omc/plans/open-questions.md`.)

---

*End of architecture-decisions.md for sprint-002.*
