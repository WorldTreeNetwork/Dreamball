# Epic 3 — Mint, grow, and name the palace from the CLI

6 stories · MEDIUM complexity · 3 thorough / 2 smoke / 1 yolo

## Story 3.1 — CLI dispatch scaffold + 5 stubbed palace subverbs

**User Story**: As the dispatch layer of `jelly`, I want a single `palace` entry in `src/cli/dispatch.zig` that routes to a new `src/cli/palace.zig` SubCommand table covering `mint`, `add-room`, `inscribe`, `open`, `rename-mythos`, so subsequent Epic 3 stories land in the nested file (palace.zig) without further dispatch changes (D-013 / R8 validation).
**FRs**: FR22 (verb-group + `--help`).
**Decisions**: D-013. **Risk gate** — R8 (validates A3 on-branch).
**Complexity**: small · **Test Tier**: smoke

### Acceptance Criteria
- **AC1** [top-level dispatch lists palace]: When `jelly --help`, Then output contains exactly one line matching `/^\s*palace\b/` with summary `palace verb group (see jelly palace --help)`.
- **AC2** [`palace --help`]: When `jelly palace --help`, Then exit 0; stdout lists `mint`, `add-room`, `inscribe`, `open`, `rename-mythos` in order; contains `(Growth; unimplemented)` note for `layout`, `share`, `rewind`, `observe` (per FR22 + D-013 consequence).
- **AC3** [no args]: When `jelly palace` with zero args, Then exit non-zero; stdout matches AC2.
- **AC4** [stub subverbs]: When `jelly palace <subverb>` for each MVP subverb, Then exit non-zero; stderr contains `not yet implemented`.
- **AC5** [unknown subverb]: When `jelly palace bogus`, Then exit non-zero; stdout contains usage from AC2.
- **AC6** [smoke extended]: Given `scripts/cli-smoke.sh`, When CI runs, Then asserts AC1, AC2, AC5; fails build on regression (NFR17).

### Technical Notes
New: `src/cli/palace.zig` (SubCommand table + `run` + `printPalaceUsage`); `palace_mint.zig`, `palace_add_room.zig`, `palace_inscribe.zig`, `palace_open.zig`, `palace_rename_mythos.zig` (stubs). Extend `src/cli/dispatch.zig` with one entry, `scripts/cli-smoke.sh`.

### Scope Boundaries
- DOES: dispatch wiring + 5 stubs + smoke test for help output.
- Does NOT: any real mint/add-room/inscribe/open/rename-mythos logic.

---

## Story 3.2 — `jelly palace mint` with mythos genesis + oracle keypair + seed registry

**User Story**: As personas P0 (Wayfarer) and P2 (Oracle host), I want `jelly mint --type=palace` (and alias `jelly palace mint`) to produce a verifying palace bundle with `field-kind: "palace"`, a genesis `jelly.mythos`, an oracle Agent child with own `.oracle.key`, an empty-but-rooted `jelly.timeline`, and the bundled seed archiform registry, so every downstream Epic 3 verb has a verifying palace to mutate.
**FRs**: FR1 (primary), FR2, FR4 (palace's own genesis mythos), FR27, FR9, FR11 (secondary — oracle keypair seeding).
**Decisions**: D-011 (plaintext `.oracle.key` 0600), D-014 (`@embedFile` registry), D-007 (consumer); TC1, TC13, TC14, TC21; SEC1, SEC7, SEC10, SEC11.
**Complexity**: medium-high · **Test Tier**: thorough

### Acceptance Criteria
- **AC1** [`--mythos`]: Given writable dir + no TTY, When `jelly mint --type=palace --out ./p --mythos "test mythos body"`, Then exit 0; `jelly verify ./p.bundle` returns 0; envelope carries `field-kind == "palace"`; exactly one `jelly.mythos` with `is-genesis: true` no `predecessor`; mythos body round-trips byte-exact through WASM decoder (NFR18).
- **AC2** [missing mythos no TTY = hard fail]: Given non-TTY, no `--mythos`, When `jelly mint --type=palace --out ./p`, Then exit non-zero; stderr `mythos required` mentions `--mythos <string>` or `--mythos-file <path>`.
- **AC3** [oracle Agent + own keypair]: Given AC1, Then palace `contains` graph has exactly one direct child of type `jelly.dreamball.agent`; sibling `./p.oracle.key` exists with mode 0600 (verified by `stat -f %Lp` macOS / `stat -c %a` Linux); oracle envelope's signer fp derives from that key; custodian `.key` and oracle `.key` are byte-distinct files (FR11 + D5 independence).
- **AC4** [timeline rooted, head-hashes singleton]: Given AC1, Then bundle contains `jelly.timeline` with exactly one action whose `parent-hashes` absent/empty; that action is dual-signed (Ed25519 + ML-DSA-87) `jelly.action` of `action-kind: "palace-minted"` (NFR12); palace's `head-hashes` is 1-element set `{Blake3(mintActionBytes)}`.
- **AC5** [seed registry deterministic]: Given AC1 executed twice (./p1, ./p2), Then each palace carries `jelly.asset` of media-type `application/vnd.palace.archiform-registry+json`; two assets' Blake3 byte-identical; asset decodes to exactly 19 seed forms (library, forge, throne-room, garden, courtyard, lab, crypt, portal, atrium, cell, scroll, lantern, vessel, compass, seed, muse, judge, midwife, trickster).
- **AC6** [`TODO-CRYPTO` marker]: Given source tree, When grep `src/cli/palace_mint.zig` for `TODO-CRYPTO: oracle key is plaintext`, Then ≥1 match adjacent to `.oracle.key` write site (SEC7 + D-011 + NFR15).
- **AC7** [CAS-before-store atomicity (TC13 + SEC11)]: Given AC1, Then CAS contains palace, mythos, oracle-agent, timeline, mint-action, registry-asset CBOR bytes; LadybugDB has `(:Palace)-[:CONTAINS]->(:Agent)` matching those fps; injecting store-write failure → CAS bytes written but palace rolls back cleanly with non-zero exit.
- **AC8** [Zig test coverage NFR16]: ≥5 new `test "..."` blocks in `src/cli/palace_mint.zig` covering happy + missing-mythos + key-perms + registry-determinism + rollback.

### Technical Notes
New: `src/cli/palace_mint.zig`, `src/memory-palace/seed/archiform-registry.json`, `src/lib/bridge/palace-mint.ts`. Extend `src/cli/palace.zig`, `scripts/cli-smoke.sh`.

### Scope Boundaries
- DOES: real palace mint + oracle keypair + mythos genesis + registry + atomic CAS-then-store.
- Does NOT: `--archiform` on mint (FR25 applies to add-room/inscribe/mint-agent). Oracle runtime (Epic 4). Embedding (Epic 6).

---

## Story 3.3 — `jelly palace add-room` + `jelly palace inscribe` + `--archiform` + `--mythos` + cycle enforcement

**User Story**: As persona P0 (Wayfarer), I want `jelly palace add-room <palace> --name <n> [--archiform <f>] [--mythos <s>]` and `jelly palace inscribe <palace> --room <room-fp> <file> [--archiform <f>] [--mythos <s>]` to mutate a minted palace — growing containment graph, minting Avatar with `jelly.inscription` (Blake3-hashed `jelly.asset`), emitting dual-signed `jelly.action` per mutation, rejecting cycles — so wayfarers populate palaces from CLI alone.
**FRs**: FR6, FR7, FR4, FR10, FR25, FR9, FR18 (CLI half — lazy aqueduct on inscribe→room edges).
**Decisions**: D-007 (consumer), D-016 (schema writes); TC12, TC13, TC14, TC16; SEC1, SEC11.
**Complexity**: medium · **Test Tier**: smoke

### Acceptance Criteria
- **AC1** [add-room happy]: Given minted palace at `./p`, When `jelly palace add-room ./p --name "library"`, Then exit 0; verify returns 0; room envelope has `field-kind == "room"` and `name == "library"`.
- **AC2** [inscribe happy]: Given `./p` has room with fp R; file `./doc.md` has Blake3 H, When `jelly palace inscribe ./p --room <R> ./doc.md`, Then exit 0; minted Avatar has `jelly.inscription.source` = `jelly.asset` whose Blake3 equals H; Avatar contained by R; default `--surface = "scroll"`, `--placement = "auto"`.
- **AC3** [unknown room]: When `jelly palace inscribe ./p --room <fp-not-in-palace> ./doc.md`, Then exit non-zero; stderr `room not in palace`.
- **AC4** [per-child `--mythos`]: When add-room with `--mythos "old bones"`, Then room carries `jelly.mythos` `is-genesis: true` body `"old bones"`; absent → no attribute; missing `--mythos-file` path → exit non-zero.
- **AC5** [`--archiform` (FR25)]: When add-room with `--archiform library`, Then room carries `jelly.archiform` with `form == "library"`; absent → no attribute; unknown form (e.g. `frobnicator`) → exit 0 + stderr `unknown archiform` warning.
- **AC6** [cycle rejection (FR10)]: Given palace P with room A containing sub-room B, When attempting cycle-closing edge, Then exit non-zero; stderr `cycle`; Zig unit test exercises minimal A→B→A closing-edge.
- **AC7** [every mutation emits dual-signed action]: When add-room or inscribe completes, Then timeline grows by exactly one leaf with `action-kind` `"room-added"` or `"avatar-inscribed"`; palace `head-hashes` = `{Blake3(newLeaf)}`; stripping either signature fails `jelly verify`.
- **AC8** [lazy aqueduct on inscribe-into-room (FR18 CLI half)]: Given inscribe against room where no aqueduct between (palace-fp, room-fp) or (prior-inscription, new-inscription) exists, When `store.ensureAqueductLazy(from, to)` returns "created", Then `jelly.aqueduct` envelope with defaults `resistance: 0.3`, `capacitance: 0.5`, `kind: "visit"` lands in CAS (D-003); paired `jelly.action` of kind `"aqueduct-created"` lands; aqueduct `strength` updated via `aqueduct.ts.updateAqueductStrength` (FR26 invocation).
- **AC9** [`--embed-via` graceful (FR20 secondary)]: When inscribe with `--embed-via http://127.0.0.1:1` (unreachable), Then exit non-zero; stderr `embedding service unreachable — palace otherwise operational`; palace unchanged (SEC11 atomicity).

### Technical Notes
New: `src/cli/palace_add_room.zig`, `src/cli/palace_inscribe.zig`, `src/lib/bridge/palace-mutate.ts` (shared dual-sig emission helper). Extend `src/cli/palace.zig`, `scripts/cli-smoke.sh`.

### Scope Boundaries
- DOES: add-room + inscribe + cycle reject + archiform flag + per-child mythos + lazy-aqueduct on inscribe.
- Does NOT: renderer traversal events / room↔room lazy aqueducts (Epic 5 emits via same helper). Embedding compute (Epic 6). FR26 formula bodies (Epic 2 `aqueduct.ts`).

---

## Story 3.4 — `jelly palace rename-mythos` with append-only chain enforcement

**User Story**: As persona P0 (Wayfarer), I want `jelly palace rename-mythos <palace> --body <text> [--true-name <word>] [--form <form>]` to append a new `jelly.mythos` with `predecessor = Blake3(prior)`, emit a paired `"true-naming"` `jelly.action` referenced by `discovered-in`, bump revision, re-sign with both signatures, and reject second-genesis attempts, so the palace's true-name history is a single verifiable append-only line.
**FRs**: FR3 (primary), FR2; secondary FR9, FR24 (verifier export).
**Decisions**: D-007, D-016; TC14, TC18; SEC1, SEC3, SEC11.
**Complexity**: medium-high · **Test Tier**: thorough

### Acceptance Criteria
- **AC1** [rename appends correct predecessor (FR3+FR2)]: Given palace `./p` with genesis mythos M0, When `jelly palace rename-mythos ./p --body "the library remembers" --true-name "rememberer" --form library`, Then exit 0; new mythos M1 with `is-genesis: false`, `predecessor == M0`; `M1.form == "library"` verbatim; `M1.true-name == "rememberer"`.
- **AC2** [paired `true-naming` action (FR3+FR9)]: Given AC1, Then timeline grows one leaf `action-kind == "true-naming"`; `M1.discovered-in` resolves to that action's Blake3; action carries both signatures (NFR12); revision incremented by 1.
- **AC3** [second genesis rejected (FR2)]: Given existing genesis mythos, When code path attempts new `is-genesis: true` mythos, Then operation rejected with exit non-zero; stderr `second genesis rejected`; Zig unit test covers internal API.
- **AC4** [unresolvable predecessor fails verify]: Given synthetic palace fixture where M1.predecessor points at unresolvable Blake3, When `jelly verify <fixture>`, Then exit non-zero; stderr names break; fixture lives `tests/fixtures/palace-broken-mythos/` exercised by smoke.
- **AC5** [genesis-only verifies]: Given freshly minted palace (no renames), When `jelly verify ./p.bundle`, Then exit 0.
- **AC6** [walk-to-genesis verifier exported (FR24 enabler)]: Given `src/memory-palace/mythos-chain.zig`, Then exposes `walkToGenesis(cas, head_fp) !GenesisResult`; ≥3 Zig tests cover (a) single-genesis happy, (b) unresolvable predecessor, (c) two-genesis-in-chain (TC18 split); Story 3.6's `palace_verify.zig` imports this — not a copy.
- **AC7** [`store.ts` updates MYTHOS_HEAD + prepends PREDECESSOR (D-016)]: Given AC1, Then Cypher `MATCH (:Palace {fp: $p})-[:MYTHOS_HEAD]->(m:Mythos) RETURN m.fp` returns M1 exactly; `(M1)-[:PREDECESSOR]->(M0)` returns 1.
- **AC8** [SEC3 canonical mythos public]: Given palace with `guild-only` quorum on some other slot, When non-oracle reader with no Guild role queries canonical chain, Then chain readable; `palace_rename_mythos.zig` never attaches `guild-only` to canonical chain mythos (guard + Zig test).

### Technical Notes
New: `src/cli/palace_rename_mythos.zig`, `src/memory-palace/mythos-chain.zig` (pure walk-to-genesis verifier), `src/lib/bridge/palace-rename-mythos.ts`. Extend `src/cli/palace.zig`, `scripts/cli-smoke.sh`.

### Scope Boundaries
- DOES: rename + chain enforcement + paired action + verifier-utility export.
- Does NOT: oracle consumption of new head (Epic 4 / FR5). Renderer re-render on head-move (Epic 5). Mythos-scoped-to-room renames work too (FR4 path); render consequences live in Epic 5.

---

## Story 3.5 — `jelly palace open` deep-linking showcase to omnispherical lens

**User Story**: As persona P0, I want `jelly palace open <palace>` to launch the showcase app (Bun/Vite) and exit 0 once a known port is reachable with the palace fp deep-linked to the omnispherical palace lens, so walking my palace in 3D is one command away.
**FRs**: FR8.
**Decisions**: D-013 (consumer); TC1, TC2; SEC6 (no network beyond localhost).
**Complexity**: small · **Test Tier**: yolo

### Acceptance Criteria
- **AC1** [open exits 0 once reachable]: Given minted palace `./p` + available localhost port, When `jelly palace open ./p` (test harness detects reachability + sends SIGTERM), Then command reports URL to stdout; waits until `GET <url>` returns 200; exits 0.
- **AC2** [URL carries fp]: Given AC1 running, Then URL on stdout matches `http://localhost:<port>/demo/palace/<fp>` where `<fp>` is palace's Blake3.
- **AC3** [unknown palace fp]: When `jelly palace open ./does-not-exist`, Then exit non-zero; stderr `unknown palace`; no Bun/Vite child process spawned (verified by process-tree snapshot).
- **AC4** [port already in use]: Given port N held, When `jelly palace open ./p --port N`, Then exit non-zero; stderr `port <N> in use`; do NOT silently re-use holder.

### Technical Notes
New: `src/cli/palace_open.zig`. Extend `src/cli/palace.zig`, `src/routes/demo/palace/[fp]/+page.svelte` (deep-link handler), `scripts/cli-smoke.sh`.

### Scope Boundaries
- DOES: process orchestration + deep-link URL + reachability poll.
- Does NOT: `PalaceLens` rendering (Epic 5). Auth / palace-locked access (Growth FR66). Any change to jelly-server routes.

---

## Story 3.6 — `jelly show --as-palace` + `jelly verify` palace invariants + smoke close

**User Story**: As persona P2 + auditor, I want `jelly show --as-palace <palace>` to pretty-print palace topology with `--json` structured output AND `jelly verify` to validate five palace invariants (≥1 direct room, oracle is sole Agent direct child, action `parent-hashes` resolve, mythos chain to single genesis, `head-hashes` are timeline leaves), so palace is auditable from CLI and `scripts/cli-smoke.sh` green-gates every Epic 3 mutation path end-to-end.
**FRs**: FR22 (final help), FR23, FR24; secondary FR1/FR9/FR18/FR27.
**Decisions**: D-007, D-016; TC14, TC18; SEC11.
**Complexity**: medium · **Test Tier**: thorough

### Acceptance Criteria
- **AC1** [`show --as-palace` human (FR23)]: Given palace from S3.3 with ≥2 rooms + ≥3 inscriptions, When `jelly show --as-palace ./p`, Then exit 0; stdout contains mythos head body verbatim, true-name if set, room tree with item counts per room, timeline head hashes hex, oracle fp; output matches golden `tests/fixtures/palace-show-golden.txt` byte-for-byte for deterministic fixture.
- **AC2** [`--json` structured (FR23)]: When `jelly show --as-palace ./p --json`, Then exit 0; valid JSON with keys `mythosHeadBody`, `trueName`, `rooms[]`, `timelineHeadHashes[]`, `oracleFp`.
- **AC3** [`show --as-palace` non-palace fp]: When invoked on non-palace fp, Then exit non-zero; stderr `not a palace`.
- **AC4** [`--archiforms` listing (FR27)]: When `jelly palace show ./p --archiforms`, Then exit 0; stdout lists all 19 seed forms.
- **AC5** [verify invariant (a) ≥1 direct room]: Given synthetic fixture with **zero** direct rooms (only oracle), Then verify exit non-zero; stderr cites `palace has no rooms`.
- **AC6** [verify (b) oracle sole direct Agent]: Given fixture with **second** Agent directly contained, Then verify fails citing `multiple Agents directly contained; exactly one (oracle) permitted`.
- **AC7** [verify (c) action parent-hashes resolve]: Given fixture with `jelly.action` whose `parent-hashes` contains unresolvable Blake3, Then verify fails citing invariant (c) naming orphan action.
- **AC8** [verify (d) mythos chain to single genesis]: Given broken-mythos fixture from S3.4 AC4, Then verify fails citing invariant (d); `palace_verify.zig` calls `mythos-chain.zig.walkToGenesis` directly (no copy).
- **AC9** [verify (e) head-hashes are timeline leaves]: Given fixture where `head-hashes` contains non-leaf or non-action fp, Then verify fails citing invariant (e).
- **AC10** [oracle actor-fp invariant (D-011 consequence)]: Given fixture where oracle-originated action's `actor` fp does not match oracle fp from sibling `.oracle.key`, Then verify fails citing `oracle actor fp mismatch` (SEC11 provenance).
- **AC11** [`cli-smoke.sh` palace section closes NFR17]: Given `scripts/cli-smoke.sh`, Then contains palace section in order: mint (S3.2) → add-room happy + cycle-reject (S3.3) → inscribe happy + unknown-room + `--archiform` + `--mythos` (S3.3) → rename-mythos happy + second-genesis-reject (S3.4) → open mocked (S3.5) → show --as-palace golden + --json (this story) → verify happy + 5 invariant-failure fixtures (this story); exit 0 on clean tree; CI fails on regression.
- **AC12** [Zig + Vitest coverage NFR16+18]: ≥5 `test` blocks per new file; ≥3 Vitest tests cover `--json` output and round-trip through codegen TS decoder.

### Technical Notes
New: `src/cli/palace_show.zig`, `src/cli/palace_verify.zig` (imports `mythos-chain.zig` from S3.4). Extend `src/cli/dispatch.zig` (`show --as-palace` flag routes; `verify` auto-detects palace), `scripts/cli-smoke.sh`. New fixtures `tests/fixtures/palace-*/` (5 invariant-failure modes), `tests/fixtures/palace-show-golden.txt`.

### Scope Boundaries
- DOES: show + verify + 5 invariant fixtures + smoke close.
- Does NOT: renderer-side verify UI (Epic 5). Oracle-aware show (Epic 4). `jelly palace trace`/`gc`/`reflect` (Growth).

---

## Epic 3 Health Metrics
- **Story count**: 6 (target 2–6) ✓ at upper bound
- **Complexity**: MEDIUM overall. S3.1 LOW; S3.2 MEDIUM-HIGH; S3.3 MEDIUM; S3.4 MEDIUM-HIGH; S3.5 LOW; S3.6 MEDIUM.
- **Test tier**: 1 yolo (S3.5), 2 smoke (S3.1, S3.3), 3 thorough (S3.2, S3.4, S3.6).
- **FR coverage**: All 15 primary FRs assigned to ≥1 story. FR1→S3.2+S3.6; FR2→S3.4+S3.6; FR3→S3.4; FR4→S3.2+S3.3; FR6→S3.3; FR7→S3.3; FR8→S3.5; FR9→S3.2+S3.3+S3.4+S3.6; FR10→S3.3; FR18 (CLI half)→S3.3; FR22→S3.1+S3.6; FR23→S3.6; FR24→S3.6; FR25→S3.3; FR27→S3.2+S3.6.
- **Cross-epic deps**: depends Epic 1 (envelopes round-trip; ML-DSA verify), Epic 2 (store domain verbs + aqueduct.ts). Blocks Epic 4 (oracle consumes `.oracle.key` from S3.2; mythos-head reads from S3.4), Epic 5 (renderer reuses S3.3 emission helper; PalaceLens is S3.5 deep-link target).
- **Risk gates**: R8 (CLI dispatch nesting first) → S3.1 validates A3. D-010 (ML-DSA WASM verify) gates S3.2 dual-sig wiring; failure → server-subprocess fallback with `TODO-CRYPTO: mldsa-wasm-verify-blocked`. R7-analogue (shared-code drift): walk-to-genesis utility from S3.4 imported (not copied) by S3.6.
- **Open questions**: One carry-forward — does `inscribe` create lazy aqueducts only between (room, avatar), or also (prior-avatar, new-avatar) within same room? Default: (room, avatar) only.
