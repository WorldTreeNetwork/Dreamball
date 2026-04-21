---
sprint: sprint-001
sprint_size: ambitious
created: 2026-04-21
total_frs: 26
in_scope_frs: 26
deferred_frs: 0
stretch_frs: 0
estimated_stories: 28
estimated_epics: 6
velocity_basis: null
---

# Sprint-001 Scope

## Sprint Size

**Ambitious** (15–30 stories, 4–6 epics). 28 stories across 6 epics — sits comfortably in the upper-middle of the band. Scope was user-narrowed in Phase 1 (26 MVP FRs distilled from PRD §10.3); no further cuts justified.

No prior sprint velocity. Sprint-001 establishes the baseline.

---

## In-Scope Clusters

### Epic A — Palace wire format + codegen
- **FRs**: FR1 (wire-level), FR9 (envelope shape), FR26 (wire fields); supports FR2, FR3, FR4, FR6, FR7, FR14, FR18, FR25, FR27
- **NFRs**: NFR12 (wire support), NFR16 (golden fixtures), NFR18 (round-trip)
- **TCs**: TC1, TC6, TC7, TC14, TC18, TC20
- **Estimated stories**: 5
- **Complexity**: LOW–MED (breadth > depth — 9 envelopes × 13 fixtures)
- **Primary modules**: `src/envelope_v2.zig`, `src/protocol_v2.zig`, `src/golden.zig`, `tools/schema-gen/main.zig`, `src/lib/generated/*.ts`
- **Depends on**: nothing
- **Blocks**: B, C, E, F
- **Rationale**: Nine new envelopes + `field-kind` attribute + golden fixtures. Foundation every other epic consumes. Sequenced first because it unblocks everything and because its first story also probes Risk R3 (WASM ML-DSA-87 verify functional per CLAUDE.md 2026-04-21) — the highest-leverage early signal in the sprint.

### Epic B — Store wrapper + graph mirroring
- **FRs**: FR19, FR21; supports FR5, FR13, FR18, FR20, FR26
- **NFRs**: NFR11 (local graph paths), NFR13 (local reads), NFR18 (replay)
- **TCs**: TC8, TC9, TC10, TC12, TC13
- **SECs**: SEC6 (local paths)
- **Estimated stories**: 5
- **Complexity**: HIGH (A1 cross-browser IDBFS, A5 vector-extension parity, A2 napi soak)
- **Primary modules**: `src/memory-palace/store.ts` (new), `src/memory-palace/aqueduct.ts` (new), `src/lib/backend/` (extend)
- **Depends on**: A
- **Blocks**: C, D, F
- **Rationale**: `src/memory-palace/store.ts` is the single swap-boundary (TC12). Dual-runtime (server `@ladybugdb/core` + browser `kuzu-wasm@0.11.3` IDBFS) with explicit close-lifecycle and bidirectional syncfs. Canonical home for FR26 aqueduct formulas (`aqueduct.ts`). Delete-then-insert re-embedding helper centralises Epic F's wire into the store contract.

### Epic C — Palace CLI + mythos chain + aqueduct lifecycle
- **FRs**: FR1, FR2, FR3, FR4, FR6, FR7, FR8, FR9, FR10, FR18 (CLI half), FR22, FR23, FR24, FR25, FR27
- **NFRs**: NFR12, NFR17
- **TCs**: TC1, TC15, TC17, TC21
- **SECs**: SEC1, SEC3, SEC7, SEC10, SEC11
- **Estimated stories**: 6
- **Complexity**: MEDIUM (depends on A3 dispatch extension — LOW–MED; largest epic by FR count)
- **Primary modules**: `src/cli/palace_{mint,add_room,inscribe,open,rename_mythos,show,verify}.zig`, `src/cli/dispatch.zig`, `scripts/cli-smoke.sh`
- **Depends on**: A, B
- **Blocks**: D, E
- **Rationale**: `jelly palace` verb group (mint / add-room / inscribe / open / rename-mythos) + `jelly show --as-palace` + `jelly verify` palace invariants + `--archiform` flag + seed registry. Lazy aqueduct creation (per D3) lives here. Append-only mythos-chain enforcement lives here.

### Epic D — Oracle + knowledge-graph + file-watcher
- **FRs**: FR5, FR11, FR12, FR13, FR14
- **NFRs**: NFR13, NFR15
- **TCs**: TC21
- **SECs**: SEC4, SEC5, SEC10, SEC11
- **Estimated stories**: 4
- **Complexity**: MEDIUM (FR14 file-watcher spans D+B+F; A7 sync-mirroring must be fault-injected)
- **Primary modules**: `src/memory-palace/oracle.ts` (new), `src/memory-palace/file-watcher.ts` (new), `src/memory-palace/seed/oracle-prompt.md` (new), `src/memory-palace/store.ts` (consumer)
- **Depends on**: A, B, C
- **Blocks**: nothing
- **Rationale**: Oracle mint with separate hybrid keypair (per D5) + sibling `.key` file. Unconditional palace read access. Synchronous inscription-triple mirroring. Mythos-head always-in-context prepend. File-watcher skill (per D1) with orphan quarantine + re-embedding trigger.

### Epic E — Rendering pack (three lenses + four shaders)
- **FRs**: FR15, FR16, FR17, FR18 (renderer half), FR26 (freshness uniform)
- **NFRs**: NFR10, NFR14
- **TCs**: TC3, TC4
- **Estimated stories**: 5
- **Complexity**: HIGH (Threlte shader work is new territory; NFR10 aggressive latency budget)
- **Primary modules**: `src/lib/lenses/PalaceLens.svelte`, `RoomLens.svelte`, `InscriptionLens.svelte`, `src/lib/components/DreamBallViewer.svelte` (extend), `src/lib/shaders/` (new or extend)
- **Depends on**: A, B, C
- **Blocks**: nothing
- **Rationale**: Three new Svelte lenses + four new Threlte materials (aqueduct-flow, room-pulse, mythos-lantern stub, dust-cobweb per Vril ADR). First story is a **shader spike** (aqueduct-flow end-to-end) — go/no-go before committing to the other three.

### Epic F — Embedding service + vector index
- **FRs**: FR20; supports FR13, FR21
- **NFRs**: NFR11 (sanctioned exit), NFR13 (opt-in), NFR15
- **SECs**: SEC6 (sanctioned exit), SEC7
- **Estimated stories**: 3
- **Complexity**: MEDIUM (A6 latency; A12 WASM ML-DSA verify; single sanctioned network exit)
- **Primary modules**: `jelly-server/src/routes/embed.ts` (new), `src/memory-palace/store.ts` (K-NN helper), `src/cli/palace_inscribe.zig` (`--embed-via` flag)
- **Depends on**: A, B
- **Blocks**: nothing
- **Rationale**: Qwen3-Embedding-0.6B endpoint in jelly-server (per D2), 1024d native / 256d MRL-truncated. K-NN via LadybugDB vector extension. Offline graceful-degradation when embedding service unreachable. Every call-site marked `TODO-EMBEDDING: bring-model-local-or-byo`.

---

## Stretch Goals

**None.**

Every stretch candidate surveyed coupled to a critical-path acceptance criterion:

- **Epic F mocked-vector path** — rejected; FR20's K-NN latency requirement wants a real vector index.
- **FR27 seed archiform registry** — rejected; FR1 determinism depends on its bytes.
- **Shader pack trimming** — rejected; NFR14 names four materials explicitly.

If Epic E's shader spike blows NFR10, `dust-cobweb` and `mythos-lantern-stub` become mid-sprint replan candidates (not pre-negotiated stretch).

---

## Deferred to Future Sprints

**None newly deferred this phase.**

All Phase-1 out-of-scope FRs (PRD FR60e/60f-full/60g, FR66–68, FR73, FR78–79, FR83–87, FR91–92, FR96–98, plus marketplace / mobile-native / federation / recrypt-wallet custody) were excluded in `requirements.md § Scope Boundaries > Out of Scope`. That list is the canonical defer record for sprint-001.

---

## Cross-Epic Coupling (explicit contracts)

| Concern | Canonical Home | Consumers | Contract |
|---------|----------------|-----------|----------|
| FR26 aqueduct formulas | B — `src/memory-palace/aqueduct.ts` | C (save-time compute), E (renderer freshness uniform) | One code block at top of file; both call sites import; bit-identical unit test |
| FR14 file-watcher | D — `src/memory-palace/file-watcher.ts` | B (store mutation), C (action emission), F (re-embedding) | Thin skill composing B+C+F primitives; no new primitives introduced |
| NFR12 dual-signature | A (wire) + C (CLI signs) | B (verify on load), D (oracle signs with own key) | Reuse `src/signer.zig` + `src/ml_dsa.zig`; oracle gets sibling `.key` file |
| NFR11 offline graceful-degradation | F (embedding-unreachable path) | B (read paths local), D (oracle reads local) | Only ingestion hits network; test with network disabled in Phase 5 |

---

## Scope Risks

| ID | Severity | Epic(s) | Description | Mitigation |
|----|----------|---------|-------------|------------|
| R1 | HIGH | B | Cross-browser IDBFS parity for `kuzu-wasm@0.11.3` Chromium-only validated | Playwright smoke on FF+Safari in Phase 5; HTTP-fallback as follow-up if fails |
| R2 | MED-HIGH | B, F | LadybugDB vector-extension graph-join parity across runtimes unverified | Run identical K-NN fixture on both runtimes as Epic B story 1; document server-only vector path as NFR11 relaxation if browser lacks |
| R3 | HIGH | A, C, E | WASM ML-DSA-87 verify assumed functional per CLAUDE.md; no test evidence cited | Epic A story 1 verifies `src/lib/wasm/verify.test.ts` exercises ML-DSA-87 on golden fixture; fallback to server-subprocess path with documented degradation |
| R4 | HIGH | E | Threlte custom-shader work is new territory; NFR10 latency budget aggressive | Epic E story 1 is shader spike (aqueduct-flow end-to-end) before committing to other three; replan if budget breaks |
| R5 | MEDIUM | F | Qwen3 server-hop latency untested on representative hardware | Load-test in Phase 5; if >200ms document as acceptable-for-MVP |
| R6 | MEDIUM | D, B, F | FR14 file-watcher spans three epics | File-watcher contract in Epic D: "call B and F primitives in this order within one signed-action transaction"; fault-inject test |
| R7 | MEDIUM | B, C, E | FR26 formula home is cross-cutting | Canonical: `src/memory-palace/aqueduct.ts` (Epic B); bit-identical-output unit test enforces contract |
| R8 | LOW-MED | C | `src/cli/dispatch.zig` nested subgroup is a first | Architect validates extension pattern in Phase 2A before Epic C story 1 |

---

## FR Disposition Summary

| FR | Epic | Status | Notes |
|----|------|--------|-------|
| FR1 | A, C | IN | Wire shape in A; CLI in C |
| FR2 | C | IN | Append-only chain enforcement |
| FR3 | C | IN | `rename-mythos` command |
| FR4 | C | IN | Per-child mythos attachment |
| FR5 | D | IN | Oracle mythos-head prepend |
| FR6 | C | IN | `add-room` |
| FR7 | C | IN | `inscribe` |
| FR8 | C | IN | `open` |
| FR9 | A, C | IN | Action envelope in A; emission in C |
| FR10 | C | IN | Cycle enforcement |
| FR11 | D | IN | Oracle mint w/ own keypair |
| FR12 | D | IN | Oracle read access |
| FR13 | D | IN | Sync triple mirroring |
| FR14 | D | IN | File-watcher (promoted MVP per D1) |
| FR15 | E | IN | `palace` lens |
| FR16 | E | IN | `room` lens |
| FR17 | E | IN | `inscription` lens |
| FR18 | C, E | IN | Traversal emits action + lazy aqueduct create |
| FR19 | B | IN | LadybugDB wrapper |
| FR20 | F | IN | Qwen3 embedding + vector index |
| FR21 | B | IN | Delete-then-insert helper |
| FR22 | C | IN | `jelly palace` verb group |
| FR23 | C | IN | `jelly show --as-palace` |
| FR24 | C | IN | `jelly verify` palace invariants |
| FR25 | C | IN | `--archiform` flag |
| FR26 | B | IN | Aqueduct formulas in `aqueduct.ts` |
| FR27 | C | IN | Seed archiform registry |

---

## Recommended Phase 2A Sequencing

Start architecture with **Epic A** — its first story probes Risk R3 (WASM ML-DSA-87 verify) before any dependent epic has committed. If R3 resolves cleanly, Epic A proceeds and B/C/E/F sequence normally. If R3 blocks, we catch it early and fall back to a documented server-subprocess path without mid-sprint replan.

Architect's Phase 2A should especially weigh:

1. **R3 verify-path architecture** — server-subprocess vs WASM-native; decide concretely.
2. **Epic B store-wrapper public API** — this is TC12's single swap-boundary; get it right.
3. **Epic E shader spike scope** — what counts as "spike success" vs "commit to all four materials"?
4. **FR14 file-watcher transactional boundary** — inline-sync with action signing vs queued-async?
