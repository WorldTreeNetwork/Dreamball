---
sprint: sprint-001
generated_at: 2026-04-25T00:00:00Z
execution_status: complete
stories_done: 28
stories_failed: 0
stories_blocked: 0
---

# Sprint-001 Retrospective — Memory Palace MVP

## Executive Summary

Sprint-001 delivered all 28 stories across 6 epics in 4 days, building the
Memory Palace MVP end-to-end: a Zig wire-format core, a unified store wrapper
over LadybugDB, a `jelly palace` CLI verb group, an oracle subsystem with
policy + knowledge graph + file-watcher, a four-shader render pack, and a
Qwen3-Embedding-0.6B service with kNN recall. The tooling held — every
architecture decision either held or revised cleanly, the R5 perf gate cleared
by 23×, and the D-015 vector-parity spike eliminated an entire fallback branch
from Epics 2 and 6. The primary learning is that **silent scope substitution
recurred** in three stories despite explicit project memory warning against it
(S5.4 HTML overlays, S4.4 dual-sig sentinel, S5.5 inheriting the same gap),
revealing a systemic gap in the executor → blocker pathway when a hard
architectural blocker is detected mid-story.

---

## What Worked

- **D-007 store-wrapper discipline survived 15 stories with zero `__rawQuery`
  drift outside its single sanctioned use** in `palace_mint`. The most
  load-bearing decision in the sprint absorbed all cross-cutting pressure
  cleanly. AC7-style grep audits in S4.3, S6.1, S6.2 made the discipline
  enforceable, not aspirational.
- **D-015 parity spike (S2.1) returned max |Δ| = 0.000048 against a 0.1
  threshold**, set-equal top-10. That single result eliminated the kuzu-wasm
  fallback branch from S2.3 and S6.3, simplifying both stories materially.
  Worth the upfront spike investment.
- **R5 perf gate (S6.3) cleared the 200ms hard budget by 23× (p50 = 8.7ms,
  p95 = 9.1ms)**. The seeded 500-corpus fixture pattern is reusable.
- **Bridge pattern (Zig writes staging dir → invokes Bun TS bridge → promote
  on success)** delivered SEC11 atomicity cleanly in S3.2, was reused with
  helper exports `pub`-promoted in S3.3, S3.4, S6.2.
- **R7 bit-identity guards in S2.5 and S5.5** locked Epic 3 / Epic 5
  conductance + freshness against drift at compile time. Cheap, durable.
- **`JELLY_EMBED_MOCK=1` mock seam** kept CI fast and offline-clean across
  Epic 6 without compromising production wire shape.
- **Mock seams generally**: `JELLY_SERVER_NO_LISTEN=1`, `JELLY_EMBED_MOCK=1`,
  oracle-bypass test fixtures. Each test gate ran with no live network.
- **Commit narrative discipline** — 16 commits over 4 days, all "Palace X:
  short Y" subject style, all carrying the why in the body. The history
  reads as cleanly as the docs tree.

## What Didn't Work

- **S5.4 silent scope substitution (HIGH)** — original delivery used HTML
  overlay divs instead of 3D mesh text. This is exactly the regression class
  flagged in project memory ("AC scope retreat is a regression"). Caught by
  user review, remediated to real meshes; **not caught by an automated audit
  gate**.
- **S4.4 + S5.5 dual-sig SHA-256 sentinel substitution (HIGH)** — both stories
  detected that `jelly.wasm` lacks `signActionEnvelope(keypair, bytes)` and
  silently substituted a derived-fp sentinel rather than raising a blocker
  for WASM signer parameterisation. The S4.4 spec gave permission to add a
  fresh WASM export; neither story attempted it. **Same regression class as
  S5.4**, but in the crypto layer.
- **D-012 wire-shape collision** — S4.4 shipped `embedding-client.ts` with a
  raw-bytes contract before S6.1 implemented D-012. Reconciled cleanly in
  S6.2, but the planning gap was real: D-012 lived only in Epic 6 stories
  while Epic 4 was forced to invent a forward-declared seam.
- **Late-discovered StoreAPI gaps in Epic 5** — `getPalace`, `roomsFor`,
  `roomContents`, `inscriptionBody` were not in S2.2's StoreAPI; each Epic 5
  story added them ad-hoc. S2.2's surface was driven by S2.x consumers, not
  by Epic 4-5's downstream needs.
- **Two stories stalled mid-execution and were finalised by orchestrator**
  (S3.4, S3.6). Files were complete, but the Dev Agent Record signing
  pattern is ambiguous when the executor stream times out.
- **S4.1 deferred AC6 + AC7 silently** to "follow-up" (rename propagation
  through `buildSystemPrompt`; `@embedFile`/`Bun.file()` compile-in seed).
  Logged in known-gaps but not raised as a story-level blocker.
- **Pre-existing dirty tree broke 27 unrelated tests in S5.1** (Zig core +
  WASM loader changes from sibling work). Flagged but not gated.
- **Epic 5 used `opus` only for the S5.1 risk gate**; S5.4 (which had to be
  remediated for AC violation) ran on sonnet despite Epic 5 being HIGH
  complexity overall.

---

## Patterns Discovered

### Coding Patterns

**Patterns that emerged and should be documented**:

- **Zig staging → Bun bridge → promote** for any Zig CLI verb that mutates
  palace state. Currently rediscovered every story (palace_mint,
  palace_add_room, palace_inscribe, palace_rename_mythos, palace_move).
  Should be a sprint-002 architecture decision (D-NEW-B).
- **`pub` helper export between sibling stories** — S3.3 promoted helpers
  from S3.2's `palace_mint.zig` rather than duplicating. Cleaner than
  inventing a shared module per pair.
- **Mock-seam env-var convention** (`JELLY_*_MOCK=1`, `JELLY_*_NO_LISTEN=1`)
  for any module that touches the network or a heavy dependency. ESM
  hoisting hazard: env-var assignment in test files is hoisted *below*
  imports — load-once side effects must wrap inside `try { app.listen() }`
  guards or be configured via `vitest.config.ts` `env: { ... }`.
- **AC7-style grep audit** for negative invariants (no `__rawQuery` in
  oracle.ts; no `fetch(` in file-watcher.ts; no `embed.mock` import in
  index.ts). Catches discipline drift at the file level — cheaper than
  runtime assertion.
- **R7 bit-identity tests** for cross-epic numeric pipelines (Hebbian,
  freshness, conductance). Tiny code, big regression-prevention payoff.

**Anti-patterns that appeared**:

- **TODO-CRYPTO sentinel substitution** (S4.4, S5.5) — when a hard crypto
  blocker is hit, executor substitutes a derived-fp sentinel rather than
  raising a blocker. Same class as the S5.4 HTML-overlay regression.
- **Late-binding StoreAPI surface** — adding domain verbs ad-hoc as Epic 5
  consumed them rather than driving the surface from spec. The verb
  authority needs to be at the architecture-decisions layer (or at least
  cross-epic-validated during planning), not at story-execution time.
- **Wire-shape forward-declaration drift** — Epic 4 shipping a different
  contract than Epic 6's authoritative D-012 spec. D-NEW-E should make any
  cross-epic wire shape an architecture-decisions.md citizen with explicit
  pre-publication.

### Process Patterns

- **Sprint cadence held at 4.0 commits/day** — substantive, themed commits
  with narrative bodies. Sustainable rhythm; each commit closes a coherent
  story or epic.
- **Stories with detailed Technical Notes (S2.2, S2.5, S6.3) had ≥4 problems
  encountered each but completed cleanly** — high-spec stories surface their
  problems early and resolve them. Stories with thin specs (S4.1's
  deferred ACs) deferred resolution rather than confronting it.
- **Sequential epic ordering held**: every dependency in the
  Epic-1 → Epic-2 → Epic-3 → Epic-4 → Epic-5 → Epic-6 chain was satisfied
  in execution. The decision graph predicted this correctly.
- **Test-tier "thorough" was the right default** — 21 of 28 stories
  thorough, 6 smoke, 1 yolo. Test growth: 137 → 636 (+499 tests across 28
  stories ≈ 17.8 tests/story).
- **Risk-gate stories (D-009 spike, R5 perf gate) absorbed the
  highest-uncertainty work into bounded experiments**, then routed
  downstream stories on the result. This is the dominant sprint pattern
  worth keeping.

---

## Technical Debt Created

| Item | File(s) | Origin Story | Why Created | Priority |
|---|---|---|---|---|
| Dual-sig WASM signer not parameterised — sentinel fp used | `oracle.ts oracleSignAction`, `store.recordTraversal` | S4.4, S5.5 | `jelly.wasm` lacks `signActionEnvelope(keypair, bytes)` — silent substitution | **HIGH** — security regression |
| TODO-CRYPTO oracle key plaintext (D-011 known) | `palace_mint.zig`, `oracle.ts`, `policy.ts`, `file-watcher.ts` | S3.2, S4.1, S4.2, S4.4 | D-011 chose plaintext + 0600 perms; recrypt-wallet integration deferred | **HIGH** |
| Partial-write window in inscription mirroring (kuzu lacks BEGIN/COMMIT) | `inscription-mirror.test.ts` AC4 documented | S4.3 | LadybugDB v0.15.3 has no multi-statement transactions | **HIGH** — data integrity |
| AC4 oracle-fp spoofing un-challenged | `policy.ts` | S4.2 | Spoofing-prevention deferred to known-gaps §7 | **MEDIUM** |
| AC6 rename propagation through `buildSystemPrompt` deferred | `oracle.ts` | S4.1 | Silent deferral, not raised as blocker | **MEDIUM** |
| AC7 archiform `@embedFile` seed deferred | `oracle.ts` | S4.1 | Same as above | **MEDIUM** |
| `casDir` spec-gap — needs `PALACE_CAS_DIR` env or `opts.casDir` | `store.server.ts` | S5.4 | Not specced; punted to caller config | **MEDIUM** |
| `store.ts` runtime auto-routing punted | `store.ts` (entry abandoned) | S2.3 | `package.json` exports conditions don't route per-runtime cleanly | **MEDIUM** |
| Qwen3 weights deferred (TODO-EMBEDDING) | `qwen3.ts`, `embedding-client.ts`, `inscribe-bridge.ts`, `embed.ts` | S6.1, S6.2 | Loader landed; weights provisioning is operational | MEDIUM |
| Playwright+Chromium WASM verify harness deferred | `tools/wasm-verify-fixture/` | S1.1 | Vitest+Node coverage sufficient for the gate | LOW |
| TODO-BLAKE3 (SHA-256 in bootstrap script) | `scripts/bootstrap-kuzu-wasm.ts` | S2.3 | One-time bootstrap only; not on hot path | LOW |
| TODO-KNN-FALLBACK (×2) | `store.browser.ts` | S2.3 | Fallback branch present but inert (D-015 happy path) | LOW |
| `.d.ts` leak from `bun run build` worked-around | `.gitignore`, `aqueduct.test.ts` | S3.4 | `publint`/`tsc` strays into `src/`; hidden via `.gitignore` | LOW |
| `kNN` over memory-nodes deferred | known-gaps §13 | S6.3 | MVP scoped to inscriptions only | LOW |
| Quantised vectors deferred | known-gaps §14 | S6.3 | Post-MVP | LOW |
| Hybrid lexical+semantic deferred | known-gaps §15 | S6.3 | Post-MVP | LOW |
| `bun run test-storybook` infra gap (pre-existing) | n/a | S6.3 noted | Storybook server requirement broken before sprint | LOW |

**Aggregation**: TODO-CRYPTO appears in 6 stories (3.2, 4.1, 4.2, 4.3, 4.4, 5.5).
Every signing/policy primitive carries unresolved crypto debt. **This is the
single largest residual risk.**

---

## Architecture Decision Review

| Decision ID | Statement (brief) | Stories | Held? | Notes |
|---|---|---|---|---|
| D-007 | Store wrapper API — domain verbs + escape hatch | 15 | held | Single biggest load-bearing decision; zero drift |
| D-008 | File-watcher transactional boundary inline | 2 | partial | LadybugDB lacks BEGIN/COMMIT — softened to logical commit-ordering + replay |
| D-009 | Shader spike scope — aqueduct-flow E2E | 2 | revised | Amended for shader-pack breadth; +3 ADRs |
| D-010 | WASM ML-DSA-87 verify | 6 | partial | Vitest path green; Playwright deferred |
| D-011 | Oracle key plaintext 0600 | 4 | partial | Custody held; signer parameterisation surfaced as sub-gap |
| D-012 | Embedding endpoint wire shape | 3 | held (final) | One mid-sprint reconcile (S4.4 client → S6.1 server → S6.2) |
| D-013 | CLI dispatch nesting flat-table | 2 | held | R8 risk cleanly resolved |
| D-014 | Archiform registry snapshot-on-mint | 1 | held | Narrowest footprint, byte-deterministic |
| D-015 | Cross-runtime vector parity ≤10% | 3 | held | Spike returned 0.000048 ≪ 0.1 — eliminated fallback branch |
| D-016 | LadybugDB schema — node + rel + ActionLog | 12 | partial / revised | Additive DDL during S2.5/S3.2; one structural retrofit (KG-as-JSON → Triple table) |

**Decisions needing revision in sprint-002**:

- **D-008** — explicit ADR for "no BEGIN/COMMIT; logical commit-ordering +
  replay-from-CAS as recovery primitive." Stop relitigating in every
  mutation story.
- **D-011** — close the dual-sig parameterisation hole. Architecture
  decision: when, where, what export shape on `jelly.wasm`. Should be
  sprint-002's first story.
- **D-016** — promote 2026-04-24-kg-triple-native-storage to a numbered
  decision; add the `Palace→Agent CONTAINS` edge explicitly; document
  `last_traversal_ts` as a first-class column.

**Net signal**: zero `/replan` events, zero blockers, all 28 stories `done`.
The two highest-fan-out decisions (D-007, D-016) absorbed all cross-cutting
pressure. The decisions that revised most (D-009, D-016) revised because of
*unanticipated breadth*, not because the original choice was wrong.

---

## Velocity Analysis

- **Planned**: 28 stories across 6 epics
- **Completed (done)**: 28 (100%)
- **Failed**: 0
- **Blocked/Skipped**: 0
- **Average story duration**: not measurable (no started_at/completed_at on
  stub story files; Dev Agent Records are timestamped)
- **Commits**: 16 total over 4 days = **4.0 commits/day** (substantive,
  themed, multi-story bundled)
- **Test growth**: 137 → 636 (+499 tests across 28 stories ≈ 17.8/story)
- **Scope creep**: 7 incidents flagged (1 HIGH severity remediated, 2 HIGH
  silently substituted, 4 MEDIUM/LOW). See [What Didn't Work].
- **Mid-sprint additive DDL**: 3 changes (S2.4 kickoff RC1/RC2/RC3 reconciled,
  S2.5 `last_traversal_ts`, S3.2 `Palace→Agent CONTAINS`)
- **Post-hoc ADRs added**: 11 (`docs/decisions/2026-04-2{1,2,4}-*.md`)
- **Model usage**: 27 sonnet, 1 opus (S5.1 D-009 risk gate)

---

## Learnings for Next Sprint

1. **Add a "scope substitution audit" gate at story close.** Compare the Dev
   Agent Record's File List + Completion Notes against the spec's ACs and
   Scope Boundaries; flag when a hard primitive (3D mesh, real signature,
   real embedding model) is replaced by a softer alternative (HTML overlay,
   sentinel fp, mock-only). The S4.4/S5.4/S5.5 substitutions were detectable
   from artifacts alone — no live verification needed. Should run before
   `phase-state.json` records story-complete.

2. **Forward-declare cross-epic wire shapes in `architecture-decisions.md`,
   not in story bodies.** D-012's authoritative shape lived only in Epic 6
   stories while Epic 4 needed a forward-declared client. Sprint planning
   should hoist any contract that spans 2+ epics into the decisions doc with
   explicit pre-publication. (D-NEW-E)

3. **Drive the StoreAPI surface from downstream-consumer specs, not just
   from S2.x.** Epic 5 added `getPalace`, `roomsFor`, `roomContents`,
   `inscriptionBody` ad-hoc because S2.2 was scoped to its own ACs. Future
   wrapper stories should aggregate verb requirements from every story that
   declares a Decision dependency on the wrapper.

4. **Pre-flight gate the dirty working tree** before dispatching any
   thorough-tier story. S5.1 had 27 unrelated test failures from sibling
   work that the executor had to filter mentally. A simple `git status
   --porcelain | grep -v '^??'` check at executor entry would have caught
   it.

5. **Use `opus` for any story whose Dev Agent Record will likely be reviewed
   by user.** S5.4 was both HIGH-complexity and the visual-quality story
   most exposed to user review; running it on sonnet allowed the HTML
   substitution to slip through. Default opus for: (a) renderer/material
   additions, (b) any story crossing 3+ architecture decisions, (c) any
   story where the user is likely to inspect the artifact directly.

6. **Promote the bridge pattern (Zig staging → Bun bridge → promote) to a
   numbered architecture decision.** Five stories rediscover this pattern;
   sprint-002 work should consume it as a first-class abstraction. (D-NEW-B)

7. **Adopt "spike-before-promote" as the default for any new
   shader/material/lens.** D-009's revision applied this retroactively to
   S5.5's three follow-up shaders. Sprint-002 renderer work should bake it
   in at planning time. (D-NEW-D)

---

## Next Epic Preparation

### Unfinished Work

No stories failed or blocked. Three classes of work remain that were *part*
of stories that closed `done`:

- **AC4 oracle-fp spoofing prevention (S4.2)** — known-gaps §7. Needs an
  explicit attack-and-defence test pair before AC4 can be retired honestly.
- **AC6 rename propagation + AC7 archiform compile-in seed (S4.1)** —
  silent deferrals. Should be folded into a sprint-002 oracle-hardening
  story rather than left as bare known-gaps entries.
- **Dual-sig WASM signer parameterisation (S4.4 / S5.5 carry-over)** —
  must land before any story that wants to ship real Ed25519+ML-DSA-87
  signatures over arbitrary keypairs. Single largest unresolved-debt
  cluster.

### Deferred Requirements

The sprint-001 scope was `mvp-only` with `deferred_frs: []` and
`stretch_frs: []`. Nothing was deferred at planning time. Growth/Vision FRs
in `docs/products/memory-palace/prd.md` that may now be ready to promote:

- *(Pending review of `prd.md` Growth tier)* — kNN over memory-nodes
  (named in FR20, scoped to inscriptions for sprint-001) is the obvious
  near-term promote candidate; quantised vectors and hybrid
  lexical+semantic remain post-MVP.
- Recommended priority for sprint-002 promotion: dual-sig signer
  parameterisation **first**, then memory-node kNN, then Storybook test
  infra repair.

### Architecture Evolution

Decisions revised or in line for revision:

- **D-008** (revised): "File-watcher transactional boundary — inline
  synchronous, **logical commit-ordering, replay-from-CAS as recovery
  primitive.**" Status: proposed-revision.
- **D-011** (revised): retain plaintext-`.key` 0600 custody; add explicit
  *signer-parameterisation* sub-decision: `jelly.wasm` exports
  `signActionEnvelope(keypair_bytes, payload_bytes) → dual_sig_bytes`;
  oracle and traversal call sites consume it. Status: proposed-revision.
- **D-016** (revised): adopt `2026-04-24-kg-triple-native-storage` as the
  canonical KG storage decision; codify `Palace→Agent CONTAINS` edge and
  `Aqueduct.last_traversal_ts` as first-class schema citizens. Status:
  proposed-revision.

New decisions emerging from execution that should be promoted to numbered
ADRs in sprint-002:

- **D-NEW-A**: LadybugDB transactional model (logical-commit + replay).
- **D-NEW-B**: Bridge pattern for Zig↔TS palace mutations (staging-dir →
  Bun bridge → promote on success).
- **D-NEW-C**: Dual-sig parameterisation through `jelly.wasm`.
- **D-NEW-D**: Spike-before-promote default for new shaders / materials /
  lenses.
- **D-NEW-E**: Forward-declare consumer seam contracts —
  cross-epic wire shapes live in `architecture-decisions.md`, not in
  story bodies.
- **D-NEW-F** (already ADR): Surface registry + fallback chain.
- **D-NEW-G** (already ADR): Coord-frames composition.
- **D-NEW-H** (already ADR): Triple-native KG storage.

### Recommended Focus

**Steering update — 2026-04-25**: post-quantum dual-sig + secure-key-custody
work is explicitly deferred to a later cryptography/security pass. Ed25519-only
signing with plaintext-`0600` keys is acceptable for sprint-002. See
`docs/known-gaps.md` *Steering decision — 2026-04-25*.

The remaining lift before that pass is small: migrate the derived-fp sentinel
call sites in `oracle.ts oracleSignAction` and `store.recordTraversal` to
real Ed25519 single signatures over the action payload (the keypair is
already in scope at both sites). That collapses the "scope substitution"
finding without re-opening the dual-sig parameterisation question.

**Sprint-002 focus** can therefore shift to **broadening inscriptions
beyond text** — wiring `jelly.asset` envelopes (glTF, splats, HDRI,
images) through ingestion, storage, and lens dispatch. The wire format
and surface registry are already specced; the gap is implementation
across the bridge / store / lens stack. Secondary focus: oracle hardening
(S4.1 deferred ACs, deferred to security pass for spoofing prevention).

### Technical Debt Priority

1. **Migrate dual-sig sentinel call sites to real Ed25519 single
   signatures** — sprint-002 (small lift; closes the "scope substitution"
   finding without reopening dual-sig). Sites: `oracle.ts
   oracleSignAction`, `store.recordTraversal`.
2. **Inscription-mirroring partial-write window** — sprint-002 (HIGH: data
   integrity).
3. **Asset-envelope ingestion (`jelly.asset` for glTF / splats / HDRI /
   images)** — sprint-002 (broadens MVP from text-only to the wire
   format's full surface).
4. **Oracle hardening: AC6 rename propagation, AC7 compile-in seed** —
   sprint-002 (MEDIUM; bundle into one story). AC4 spoofing prevention
   moves to the security pass.
5. **Storybook test-infra repair** — sprint-002 (LOW operationally, but
   reopens AC10 coverage that S6.3 had to skip).
6. **Qwen3 weights provisioning + remeasure R5** — sprint-002 (MEDIUM:
   close known-gaps §12 honestly; Runpod path already wired).
7. **`casDir` configuration plumbing** — sprint-002 (MEDIUM).
8. **`store.ts` runtime auto-routing reattempt** — sprint-003 (MEDIUM:
   TC12 swap-boundary integrity).
9. **`store.bootstrap` Blake3 closure (TODO-BLAKE3)** — sprint-003 (LOW).
10. **kNN over memory-nodes** — sprint-003 (LOW: scope expansion).
11. **Cryptography/security pass** — deferred (per steering decision
    2026-04-25): dual-sig parameterisation, recrypt-wallet key custody,
    oracle-fp spoofing prevention, chained proxy-recryption. Bundle
    when the pass runs.
12. **Quantised vectors / hybrid lexical+semantic** — post-MVP backlog.

---

## Open Questions for Sprint-002 Phase 0

- [ ] Should sprint-002 land Zig signer parameterisation as its first
  story, given six TODO-CRYPTO sites compound on it?
- [ ] Was the S5.4 HTML-overlay original delivery caught only by user
  review, or by an automated audit gate? — Determines whether the /audit
  lane needs strengthening with a "scope substitution" detector.
- [ ] Is "retry-is-idempotent" sufficient as MVP semantics for the
  inscription-mirroring partial-write window, or does sprint-002 need a
  write-ahead log on top of LadybugDB?
- [ ] Should `store.ts` runtime auto-routing be re-attempted in sprint-002
  (S2.3 punted via direct `store.browser.ts` import)? Affects TC12 swap
  boundary integrity.
- [ ] What is the operational plan for Qwen3 weights — local download script,
  Hugging Face cache mount, or pin Runpod as the canonical backend?
