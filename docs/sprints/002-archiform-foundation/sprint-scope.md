---
sprint: sprint-002
sprint_size: standard
created: 2026-04-28
total_frs: 15
in_scope_frs: 14
stretch_frs: 0
deferred_frs: 1
estimated_stories: 22
estimated_epics: 7
velocity_basis: sprint-001
velocity_stories_done: 28
velocity_completion_rate: 100
effective_capacity: 21
---

# Sprint-002 Scope

> Historical sprint record. JSON-Schema-canonical (D-018) was later
> superseded by Zig-canonical (2026-06-25) and then by
> [Rust-canonical (2026-08-06)](../../decisions/2026-08-06-rust-canonical.md).
> VISION form-independence is now §10, not §4.

## Sprint Size

**standard** (8-18 stories target; this sprint runs slightly above at ~22 IN). Sprint-001 velocity supports `ambitious` (~21 effective capacity) but sprint-002's binary gating constraint (NFR1 byte-equivalence — no partial credit) and architectural-reframing nature favor a tight, coherent scope over a stretched one. The four 2026-04-25 decision notes only land *together*; spreading them across two sprints loses the architectural coherence.

### Velocity Basis

Sprint-001: 28/28 stories done (100% completion), ~25% scope creep across 7 incidents (1 HIGH remediated, 2 HIGH silently substituted, 4 MEDIUM/LOW), 0 replans. Effective capacity ≈ 21 stories. Sprint-002 sits slightly above this; the carry-over Ed25519 migration (FR13 / Cluster G) absorbs the silent-substitution regression class so it doesn't recur.

---

## In-Scope Clusters

### Cluster A: Codegen Inversion (Foundation)

- **FRs**: FR1, FR2, FR3, FR14
- **Estimated stories**: 4-5
- **Complexity**: HIGH
- **Rationale**: Byte-equivalence (NFR1) is the binary gating constraint for the entire migration. Every other cluster assumes JSON-Schema-canonical generation works. Front-load this cluster: spike root JSON Schema authoring, build the Zig + TS + Valibot + CBOR generators, write the byte-equivalence test, run shadow-generator phase, cut over in a single commit.

### Cluster B: Memory Palace as Archiform

- **FRs**: FR4, FR5
- **Estimated stories**: 3
- **Complexity**: MEDIUM
- **Depends on**: Cluster A
- **Rationale**: Extract `Inscription`, `Room`, `Aqueduct`, traversal state, and decay parameters from current Zig + `schema.cypher` into pinned `dreamball/memory-palace@0.1.0` JSON Schema. Add `archiform_fp` to genesis envelope with implicit-binding back-compat for sprint-001 instances. Closes the "Memory Palace as one archiform among many" hypothesis at the wire layer.

### Cluster C: Action Manifest + CLI Projection (Full Verb Coverage)

- **FRs**: FR6, FR7
- **Estimated stories**: 5
- **Complexity**: MEDIUM-HIGH
- **Depends on**: Cluster B
- **Rationale**: Declare action-manifest shape inside the archiform JSON Schema; generate `jelly palace *` verbs as projections of the manifest rather than hand-written Zig. **Full verb coverage** per Q7: `mint`, `inscribe`, `add-room`, `rename-mythos`, `move`. Pure-transaction lint enforces no-prompts-in-action-bodies. Replaces the hand-written `src/cli/palace*.zig` with codegen output validated against `scripts/cli-smoke.sh`.

### Cluster D: Programmatic + MCP Projections

- **FRs**: FR8, FR9
- **Estimated stories**: 3
- **Complexity**: MEDIUM
- **Depends on**: Cluster C
- **Rationale**: D-NEW-A.3 §Consequences explicitly commits sprint-002 to CLI + programmatic + MCP. The TypeScript client makes manifest-defined actions callable from any bun script and from `jelly-server` route handlers. The MCP tool generator makes them callable by LLM agents. Both are mechanical projections of the manifest authored in Cluster C.

### Cluster E: Wasm Action Runtime

- **FRs**: FR10, FR11
- **Estimated stories**: 4-5
- **Complexity**: HIGH
- **Independent** (parallelisable with C/D once host is up)
- **Rationale**: Stand up the wasm action host inside `jelly` CLI under WASI; formally enumerate the `dreamball.*` import surface (no growing it ad-hoc per project memory `D-NEW-E`); content-address module loading via `blake3(wasm_bytes) == implementation.wasm` fp; verify-before-instantiate. The host code is reusable in browser/`jelly.wasm` for future renderer-projection work.

### Cluster G: Sprint-001 Carry-Over (Ed25519 Sentinel Migration)

- **FRs**: FR13
- **Estimated stories**: 1-2
- **Complexity**: LOW
- **Independent**
- **Rationale**: Migrate the two derived-fp sentinel call sites in `oracle.ts oracleSignAction` and `store.recordTraversal` to real Ed25519 single signatures. Closes the sprint-001 "scope substitution" finding (S4.4 / S5.5) without re-opening dual-sig parameterisation (deferred to security pass per 2026-04-25 steering). Small lift; high regression-prevention value.

### Cluster H: Documentation Refresh

- **FRs**: FR15
- **Estimated stories**: 1-2
- **Complexity**: LOW
- **Cross-cutting** (final pass after E lands)
- **Rationale**: The architectural pivot has to land in `docs/ARCHITECTURE.md`, `docs/PROTOCOL.md`, and a new `docs/dreamball-imports.md` — not just decision notes — or future agents drift. CLAUDE.md's cross-runtime invariant section was already refined pre-sprint; this cluster brings the rest of the docs tree into alignment.

---

## Stretch Goals

### Cluster I: Sample Second Archiform (Federation Proof)

- **FRs**: (none — purely additive; exercises the manifold)
- **Estimated stories**: 2-3
- **Include if**: Clusters A, B, C, E complete cleanly with margin
- **Rationale**: Author a tiny second archiform end-to-end (e.g., `dreamball/guestbook@0.1.0`) — JSON Schema → action manifest → wasm action → CLI projection. Without it, sprint-002 ships infrastructure that hasn't been exercised by anything other than Memory Palace, leaving the federation hypothesis ("anyone can author a new archiform") untested. Highest-value optional in the sprint.

---

## Deferred to Future Sprints

### Cluster F: Bun-Script Fallback Implementation Path

- **FRs**: FR12
- **Estimated stories**: 2
- **Suggested pickup**: Sprint-003 or when the first archiform author asks for it
- **Rationale**: Per Q3 user decision — sprint-002 is wasm-only. Wasm is the production target; bun-script as fast-iteration fallback can land when an actual archiform author needs faster authoring loops. Today's archiform authors are us, working in-tree, with the wasm toolchain already at hand.
- **Risk of deferral**: None — bun-script is purely additive to the manifest's `implementation` shape; deferring it doesn't constrain the wasm path.

### Cluster J: Asset Envelopes (`jelly.asset` for glTF / splats / HDRI / images)

- **FRs**: (sprint-002 set doesn't formally include them)
- **Estimated stories**: 6-8
- **Suggested pickup**: Sprint-003
- **Rationale**: Per Q1 user decision — archiform foundation chosen as primary scope over the sprint-001 retrospective's recommendation of asset-envelope ingestion. Asset work cleanly lands on top of the new codegen flow (manifest declares `inscribe-asset` actions; wire format extension is additive); doing it before the inversion would double the work.
- **Risk of deferral**: None — asset envelopes are purely additive to the wire format; the §13.7 surface registry already supports their addition without breaking changes.

### Cluster K: Expanded Sprint-001 Carry-Over

- **FRs**: (sprint-001 known-gaps cluster; not in sprint-002 FR set)
- **Estimated stories**: 3-5
- **Items**: AC6 rename propagation through `buildSystemPrompt`, AC7 archiform `@embedFile` compile-in seed, inscription-mirroring partial-write window (HIGH data integrity), `casDir` plumbing
- **Suggested pickup**: Sprint-003 (oracle hardening epic)
- **Rationale**: Per Q5 user decision — keep G tight to FR13 only; bundle the rest into a sprint-003 oracle-hardening story. Avoids the carry-over cluster expanding to absorb every retro §Tech Debt Priority item (Risk #5 from requirements).
- **Risk of deferral**: MEDIUM — inscription-mirroring partial-write window is HIGH data-integrity risk per retrospective. Sprint-003 should include it as an early story.

### Cluster L: REST + In-Renderer Projections

- **FRs**: (subset of action manifest projections; D-NEW-A.3 explicit deferral)
- **Estimated stories**: 4-6
- **Suggested pickup**: Sprint-003
- **Rationale**: Per D-NEW-A.3 §Consequences and Q6 user confirmation — REST and in-renderer derivation follow in sprint-003 once CLI + programmatic + MCP have been used in anger and friction is observed. Premature projection multiplies coupling without informing design.
- **Risk of deferral**: None — projections are independent; sprint-002 ships the manifest contract that makes them mechanical follow-ons.

### Other Deferred Items (sprint-001 carry-overs not in any cluster)

- **kNN over memory-nodes** (sprint-001 known-gaps §13) — sprint-003 candidate
- **Quantised vectors / hybrid lexical+semantic** — post-MVP backlog
- **`store.ts` runtime auto-routing reattempt** — sprint-003
- **Storybook test-infra repair** — sprint-003 unless trivially folded in
- **Per-projection permissions registry** — sprint-003 (Q10 default: trusted-by-default in sprint-002)
- **Qwen3 weights provisioning (TODO-EMBEDDING)** — sprint-003 (per Q11; LOW priority)
- **Cryptography/security pass** — explicit deferred bundle: post-quantum dual-sig, recrypt-wallet key custody, oracle-fp spoofing prevention, chained proxy-recryption

---

## Backlog Items Included

None — sprint-002 has no backlog promotions. Deferred clusters above seed sprint-003 candidates.

---

## Scope Risks

1. **Cluster A byte-equivalence (NFR1) is binary** — partial credit doesn't exist. *Mitigation*: spike root schema first; shadow-generator phase ensures byte-equivalence is verified at every commit; cutover is its own commit only after every surface is byte-equivalent. Risk affects: Cluster A primarily, B/C/D/E downstream.
2. **Cluster E wasm host depth** — wasm hosts historically ship later than estimated. *Mitigation*: spike WASI on darwin + linux first (per Assumption #2); enumerate `dreamball.*` import surface as a pre-implementation architecture deliverable (per FR11 and D-NEW-E discipline). Risk affects: Cluster E.
3. **Cluster I federation proof** is the integration test of the entire sprint — without it, "did we build the right thing?" stays unanswered. *Mitigation*: keep I in stretch but treat it as the canary for whether sprint-002 actually delivered the foundation. If A/B/C/E land but I doesn't fit, sprint-003 must lead with it.
4. **Three open questions carry forward to Phase 2A architecture**: Q4 (aspects.sh contract — vendor-locally vs block-on-aspects.sh), Q8 (`tools/schema-gen/main.zig` disposition — delete vs repurpose), Q9 (wasm module signing — content-addressing-only vs signed-schema-transitively). All three are HIGH-significance architectural decisions.
5. **Sprint sits at upper edge of `standard`** (~22 IN stories vs 8-18 target). Velocity supports it but leaves no slack. *Mitigation*: Cluster G and H are small and absorb most of any overage; if a HIGH-complexity cluster (A or E) blows estimates, drop Cluster D's MCP projection to stretch first.

---

## FR Disposition Summary

| FR | Cluster | Status | Rationale |
|----|---------|--------|-----------|
| FR1  | A | IN | Foundation: codegen inversion |
| FR2  | A | IN | Foundation: root JSON Schema authoring |
| FR3  | A | IN | Foundation: golden vectors stay Zig-canonical |
| FR4  | B | IN | Memory Palace schema extraction |
| FR5  | B | IN | Genesis envelope `archiform_fp` field |
| FR6  | C | IN | Action manifest schema |
| FR7  | C | IN | CLI projection (full verb coverage) |
| FR8  | D | IN | Programmatic projection |
| FR9  | D | IN | MCP projection |
| FR10 | E | IN | Wasm action host inside `jelly` |
| FR11 | E | IN | `dreamball.*` import namespace |
| FR12 | F | DEFER | Bun-script fallback (sprint-003+; wasm-only sprint per Q3) |
| FR13 | G | IN | Ed25519 sentinel migration (sprint-001 carry-over) |
| FR14 | A | IN | Migration rollout discipline (shadow-generator + byte-equivalence cutover) |
| FR15 | H | IN | Documentation refresh |

---

## Open Questions Carried to Phase 2A (Architecture)

- **Q4 — aspects.sh contract:** vendor-locally (recommended) vs block-on-aspects.sh-shipping. Architecture decision: how the local pin format is structured (file path conventions, fp file format, refresh path).
- **Q8 — `tools/schema-gen/main.zig` disposition:** delete vs repurpose-as-consumer-entry-point vs keep-temporarily-for-shadow-generator-phase-then-remove. Architecture decision: file structure for the inverted toolchain.
- **Q9 — wasm module signing:** content-addressing-only (per SEC4) vs signed-schema-transitively-authenticates-wasm. Architecture decision: trust model for archiform bundles.

These are MAX-ACTIVE steering decisions for Phase 2A.

---

## Open Questions Resolved in Phase 1B

- ✅ **Q1 — Sprint scope:** Archiform foundation chosen; asset envelopes deferred to sprint-003 (Cluster J).
- ✅ **Q2 — Federation proof:** STRETCH (Cluster I).
- ✅ **Q3 — Wasm-only or +bun-script:** Wasm-only sprint; bun-script fallback deferred (Cluster F).
- ✅ **Q5 — Carry-over scope:** FR13 only IN (Cluster G); expanded carry-over deferred (Cluster K).
- ✅ **Q6 — REST + renderer projections:** Confirmed deferred to sprint-003 (Cluster L).
- ✅ **Q7 — Verb coverage:** Full 5 verbs (mint/inscribe/add-room/rename-mythos/move) in Cluster C.
- ✅ **Q10 — Permissions model:** Trusted-by-default in sprint-002; per-projection registry deferred to sprint-003.
- ✅ **Q11 — Qwen3 weights:** Deferred (LOW priority).
