# Epic 4 — Converse with the oracle who remembers

4 stories · MEDIUM-HIGH complexity · 1 smoke / 3 thorough

## Story 4.1 — Oracle mint bundle, personality seed, mythos-head prepend

**User Story**: As persona P2 (Oracle host), I want oracle Agent slots populated at mint with seed `personality-master-prompt`, empty `memory`/`knowledge-graph`, default `emotional-register` (curiosity/warmth/patience all 0.5), and an always-in-context mythos-head prepend, so every oracle turn sits under the current mythos head and the oracle is ready for conversation as soon as the palace mints.
**FRs**: FR5, FR11.
**Decisions**: D-011 (oracle `.key` read on-demand, marker), D-007 (`insertTriple`, `setMythosHead`, `mythosChainTriples`), D-016 (`MYTHOS_HEAD` edge); SEC10.
**Complexity**: small · **Test Tier**: smoke

### Acceptance Criteria
- **AC1** [oracle envelope all 5 slots at mint]: Given `jelly palace mint --mythos "first stone"` completes, When oracle envelope decoded, Then `personality-master-prompt` byte-identical to `src/memory-palace/seed/oracle-prompt.md`; `memory` present and empty; `knowledge-graph` zero triples; `emotional-register` carries axes `curiosity`, `warmth`, `patience` each at 0.5; `interaction-set` present and empty.
- **AC2** [`.oracle.key` 0600]: Given fresh mint, When stat `{palace-path}.oracle.key`, Then file exists; mode is 0600; bytes follow `src/key_file.zig` format; oracle Agent's hybrid identity fp derives from key-file contents.
- **AC3** [TODO-CRYPTO marker at every read site]: When grep `\.oracle\.key` under `src/` (excluding tests), Then every match site has `TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)` comment within 3 lines; CI fails marker-discipline lint on new read site without marker.
- **AC4** [`buildSystemPrompt` prepends head body verbatim]: Given palace minted with `--mythos "first stone"`, When `buildSystemPrompt(oracleFp)` runs, Then returned string begins with `first stone` verbatim; followed (after newline) by oracle's `personality-master-prompt` body verbatim; Vitest compares prefix byte-for-byte against mythos envelope's `body` decoded through `jelly.wasm`.
- **AC5** [MYTHOS_HEAD edge in both knowledge-graph + LadybugDB]: Given freshly minted palace, When oracle envelope's `knowledge-graph` queried, Then triple `(palace-fp, "mythos-head", current-mythos-fp)` present; Cypher `MATCH (p:Palace {fp: $palaceFp})-[:MYTHOS_HEAD]->(m:Mythos) RETURN m.fp` returns exactly one row equal to current-mythos-fp.
- **AC6** [head-move propagates after rename-mythos]: Given palace with head M1, When custodian runs `jelly palace rename-mythos --body "second stone"` (producing M2), Then `buildSystemPrompt(oracleFp)` after rename prefixes `second stone`; oracle's `knowledge-graph` contains `(palace-fp, "mythos-head", M2.fp)`; old triple may be retained via `PREDECESSOR` but MUST NOT be active `MYTHOS_HEAD`.
- **AC7** [seed asset bundled, not disk-read at runtime]: When oracle mint runs in any runtime (CLI, jelly-server, browser), Then seed prompt comes from compiled-in asset (`@embedFile` Zig / `Bun.file()` TS); removing `src/memory-palace/seed/oracle-prompt.md` after build does NOT affect runtime behaviour.

### Technical Notes
New: `src/memory-palace/oracle.ts` (`bootstrapOracleSlots`, `readOraclePrivateKey`, `buildSystemPrompt`), `src/memory-palace/seed/oracle-prompt.md`. Extend `src/cli/palace_mint.zig` (Epic 3 S3.2) — after oracle envelope mint, populate slots from seed asset and mirror MYTHOS_HEAD edge in same signed-action transaction.

**Open questions**: OQ-S4.1-a — oracle's `signer` location: re-use Zig `signer.zig` (palace-side) parameterised over keypair, or separate Zig entry. Defer to S4.4 when signing emits.

---

## Story 4.2 — Oracle palace read-access bypass of Guild policy

**User Story**: As persona P2, I want a `requesterFp` parameter on every store read verb that consults the Guild-policy gate AND short-circuits to allow when the requester is the oracle fp, so the oracle has unconditional palace read access while non-oracle Guild members and strangers continue to hit the existing policy paths.
**FRs**: FR12.
**Decisions**: D-007 (Guild policy as store-layer concern), D-016 (`custodian-of-record` on Palace), D-011 (oracle fp from sibling `.key`); SEC4 (Guild default for non-oracle preserved), SEC5 (oracle bypass — primary), SEC6.
**Complexity**: medium · **Test Tier**: thorough

### Acceptance Criteria
- **AC1** [oracle requester reads Guild-restricted inscription]: Given palace with `jelly.inscription` avatar marked `guild-policy: any-admin` AND requester fp equals palace's oracle fp, When `store.getInscription(avatarFp, requesterFp=oracleFp)` called, Then returns full inscription; policy audit log records one entry `reason: 'oracle-bypass'`.
- **AC2** [non-oracle non-Guild denied]: Given same palace + avatar, requester fresh keypair NOT in Guild AND NOT oracle fp, When same call, Then throws/returns `{allow: false, reason: 'guild-policy-denied'}`; no inscription content returned; audit log `reason: 'guild-policy-denied'`.
- **AC3** [non-oracle Guild member passes without bypass branch]: Given same palace, requester IS Guild member, When read issued, Then returns inscription; audit log `reason: 'guild-member'` (NOT `oracle-bypass`) — proves bypass branch only fires for oracle fp.
- **AC4** [oracle fp spoofing un-challenged in MVP]: Given stranger knows oracle fp but doesn't hold `.oracle.key`, When they issue read with `requesterFp=oracleFp`, Then store accepts at face value (no signature challenge — documented MVP limitation); annotated with `TODO-CRYPTO: requester identity un-challenged in MVP; next sprint adds signed-query envelopes`; AC PASS if marker exists AND limitation noted in `docs/known-gaps.md`. *(Rationale: MVP threat model is local-first single-custodian; attacker reaching store in-process already has `.oracle.key` per D-011.)*
- **AC5** [bypass does NOT leak into mutation paths]: Given oracle fp is requester, When oracle attempts any write verb other than file-watcher path (e.g. `store.inscribeAvatar(…, requesterFp=oracleFp)`), Then store rejects with `reason: 'oracle-writes-restricted-to-file-watcher'`; bypass logic in read verbs has not changed write-path authorisation.
- **AC6** [canonical mythos chain remains public regardless of Guild policy (SEC3 sanity)]: Given any requester (oracle, Guild member, stranger), When `store.mythosChainTriples(palaceFp, requesterFp=anyFp)` called, Then full chain returned; audit log `reason: 'mythos-always-public'` (NOT `oracle-bypass`).

### Technical Notes
Extend `src/memory-palace/oracle.ts` with `isOracleRequester(palaceFp, requesterFp)`. Extend `src/memory-palace/store.ts` — every read verb accepts `requesterFp` and consults policy gate; gate short-circuits true on `isOracleRequester`. New/extend `src/memory-palace/policy.ts` — `evaluateGuildPolicy(slot, requesterFp, palaceFp) → {allow, reason}`. Audit log via `store.policyLog(…)` (in-memory ring buffer, MVP).

**Open questions**: OQ-S4.2-a — `requesterFp` default to `'anonymous'` sentinel, or required (no default)? Recommend required.

---

## Story 4.3 — Synchronous inscription-triple mirroring inside signed-action transaction

**User Story**: As persona P2, I want every `inscribe` and `move` action to write `(doc-fp, lives-in, room-fp)` into both the oracle's `knowledge-graph` envelope AND LadybugDB synchronously inside the same signed-action transaction, so the oracle's view of the palace stays consistent with the signed timeline at all times and no half-written state survives any partial failure.
**FRs**: FR13.
**Decisions**: D-007, D-016, D-008 (4-step transaction discipline reused); SEC11 (action before effect), SEC1.
**Complexity**: medium · **Test Tier**: thorough

### Acceptance Criteria
- **AC1** [happy: inscribe mirrors triple to both]: Given palace with one room R, When `jelly palace inscribe <palace> --room R <file>` produces Avatar D, Then oracle envelope's `knowledge-graph` slot contains triple `(D.fp, "lives-in", R.fp)`; Cypher `MATCH (i:Inscription {fp: $dfp})-[:LIVES_IN]->(r:Room {fp: $rfp}) RETURN 1` returns exactly one row; `ActionLog` contains row with `action-kind = "inscribe"` and `target-fp = D.fp`; all three writes share one `tx.id`.
- **AC2** [happy: move updates triple]: Given Avatar D with existing `LIVES_IN R1`, When `jelly palace move <palace> --avatar D --to R2`, Then oracle's `knowledge-graph` contains `(D.fp, "lives-in", R2.fp)` and NOT old triple; Cypher returns exactly R2.fp; `ActionLog` row of `"move"`.
- **AC3** [count invariant after 3 inscribes across 2 rooms]: Given freshly minted palace with R1, R2, When 3 inscribes place D1, D2 in R1 and D3 in R2, Then Cypher `MATCH (:Inscription)-[:LIVES_IN]->(:Room) RETURN count(*) AS c` returns c=3; oracle `knowledge-graph` contains exactly three `"lives-in"` triples.
- **AC4** [fault: throw after triple-insert before action-record]: Given test harness injecting throw in `mirrorInscriptionToKnowledgeGraph` AFTER triple inserted but BEFORE `tx.recordAction`, When CLI retries inscribe, Then no `LIVES_IN` edge exists for that doc-fp; no `ActionLog` row for action; oracle `knowledge-graph` does NOT contain orphan triple; `jelly verify` passes; CLI retry succeeds cleanly.
- **AC5** [fault: SIGKILL between tx.begin and tx.commit]: Given test harness SIGKILL's `jelly-server` after `tx.begin` but before `tx.commit`, When server restarted and palace re-opened, Then replay-from-CAS reproduces pre-mutation state; no partial triple in LadybugDB; no half-written action in `ActionLog`; `jelly verify` passes.
- **AC6** [mirror is synchronous: action not observable before triple]: Given concurrent reader polling `store.actionsSince(lastActionFp)` AND `store.triplesFor(docFp)`, When new inscribe commits, Then NO observable instant where action appears in `ActionLog` without corresponding `LIVES_IN` edge in same query snapshot; inverse also holds; Vitest interleaved-reader test asserts over 100 iterations.
- **AC7** [only D-007 domain verbs; no raw Cypher in oracle.ts]: When grep `__rawQuery` or backtick-Cypher in `src/memory-palace/oracle.ts`, Then zero matches; all triple writes route through `store.insertTriple`/`updateTriple`/`deleteTriple`.

### Technical Notes
Extend `src/memory-palace/oracle.ts` with `mirrorInscriptionToKnowledgeGraph(inscribeAction, tx)` and `mirrorInscriptionMove(moveAction, tx)`. Extend `src/cli/palace_inscribe.zig` (and `palace_move` or renderer-bridge) — after custodian-signed action built, TS bridge runs ONE `store.transaction` recording action + writing inscription node + invoking mirror inside same `tx`. Rollback-on-throw covers all three.

**Open questions**: OQ-S4.3-a — does oracle envelope need re-signing on each triple append, or is `jelly.action` the sole signed artefact? Working assumption: oracle envelope revision bumps (custodian-authored); `jelly.action` carries authoritative signature.

---

## Story 4.4 — Oracle file-watcher skill: inline-sync transaction + orphan emission

**User Story**: As persona P2, I want the oracle's file-watcher skill to detect inscription source changes and deletions on disk, sign actions with the oracle's own keypair (per D5), re-embed via `embedding-client` from Epic 6, and write the result inside one synchronous signed-action transaction with full rollback on any failure step (per D-008), so the palace's view of inscribed sources stays current without breaking auditability.
**FRs**: FR14; secondary FR9, FR21, FR20.
**Decisions**: D-008 (PRIMARY — inline synchronous, per-palace mutex, 4-step, full rollback), D-011, D-007, D-016; SEC11, SEC1, SEC10, SEC6.
**Complexity**: large · **Test Tier**: thorough · **R6 mitigation**

### Acceptance Criteria
- **AC1** [happy: file edit produces `inscription-updated` action + re-embedded vector within 2s]: Given palace with inscribed `note.md` whose Avatar fp is D, When `echo "new content" >> note.md` on disk, Then within 2000ms a `jelly.action` of kind `"inscription-updated"` lands in `ActionLog` with `target-fp = D.fp`; action carries BOTH `ed25519-signed` and `mldsa-signed` whose signer-fp equals **oracle fp** (NOT custodian fp); Inscription node for D has NEW embedding vector (delete-then-insert; cypher `RETURN i.embedding[0]` differs from pre-edit value); Avatar revision bumped by 1.
- **AC2** [no-op when content hash unchanged (FR21 spy)]: Given watched file whose touch-time changes but bytes identical (e.g. `touch note.md`), When watcher fires, Then embedding-client spy records zero `computeEmbedding` calls; no `jelly.action` emitted; Avatar revision does NOT bump.
- **AC3** [delete (orphan) path]: Given inscribed D as AC1, When `rm note.md` on disk, Then within 2000ms `jelly.action` of kind `"inscription-orphaned"` lands in `ActionLog` oracle-signed; Cypher `MATCH (i:Inscription {fp: $dfp}) RETURN i.orphaned` returns true; embedding vector NOT deleted (quarantine); `LIVES_IN` edge NOT removed.
- **AC4** [fault: embedding server down]: Given `/embed` returns HTTP 503, When file edit fires watcher, Then no `jelly.action` emitted; Avatar revision does not bump; embedding vector unchanged; user-visible error logged containing `"embedding service unreachable"`; mutex released (subsequent edits not wedged).
- **AC5** [fault: tx throws mid-commit]: Given test harness injecting throw inside `store.transaction` after `tx.reembed` succeeds but before `tx.recordAction`, When watcher fires on file edit, Then post-edit state byte-identical to pre-edit in LadybugDB (vector unchanged, no action row); oracle `knowledge-graph` unchanged; replay-from-CAS reproduces same state; `jelly verify` passes.
- **AC6** [fault: SIGKILL between signAction and tx.begin]: Given harness SIGKILL'ing immediately after `oracleSignAction` returns but before `store.transaction` opens, When process restarted and palace re-opened, Then action bytes (memory-only) lost; no action in `ActionLog`; Avatar unchanged; `jelly verify` passes; watcher re-detects unchanged file on next cycle (if user re-saves) and retries cleanly.
- **AC7** [per-palace mutex: two palaces don't block each other]: Given palaces P1 and P2 both open, When simultaneous file edits fire for avatars in both, Then both transactions commit independently; neither waits on other's mutex; both actions land within 2000ms.
- **AC8** [burst of edits within one palace serialises, doesn't drop]: Given watched file receives 10 rapid edits within 500ms, When burst settles, Then exactly 10 `inscription-updated` actions land (no drops, no merges); final Avatar revision = `initial + 10`; each action's `parent-hashes` resolves to predecessor. *(Note: debounce out of scope for MVP; un-debounced is correct.)*
- **AC9** [TODO-EMBEDDING + TODO-CRYPTO markers]: Given repo state, When grep `src/memory-palace/file-watcher.ts` and `oracle.ts`, Then `computeEmbedding(…)` site carries `TODO-EMBEDDING: bring-model-local-or-byo`; oracle key-read site carries `TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)`.
- **AC10** [signed-action-before-effect (SEC11)]: Given concurrent reader observing `ActionLog` and `Inscription.embedding`, When happy-path edit commits, Then `inscription-updated` action appears in same query snapshot as new embedding (both after commit; neither before); no observable instant has new embedding without authorising action; Vitest interleaved-reader test asserts over 100 iterations.

### Technical Notes
New: `src/memory-palace/file-watcher.ts` (D-008 skill — `onFileChange(avatarFp, newPath)`, `onFileDelete(avatarFp)`, per-palace mutex via `acquirePalaceMutex(palaceFp)` from store.ts). Extend `oracle.ts` with `oracleSignAction(kind, targetFp, parentHashes)` — uses S4.1 `.key` reader to produce dual-signed `jelly.action`. Extend store.ts with `transaction`, `reembed`, `recordAction`, `updateInscription`, `markOrphaned`. No new Zig surface — file-watching is TS-only; oracle signing goes through Zig-compiled sign helper (existing `signer.zig` + `ml_dsa.zig` parameterised over keypair).

Renderer coupling note (Epic 5): `Inscription.orphaned = true` is the flag Epic 5's `InscriptionLens` reads to dim the Avatar. This story emits the flag; visual is Epic 5's acceptance.

**Open questions**: OQ-S4.4-a — debounce policy (defer; document as known-gap follow-up). OQ-S4.4-b — server-unreachable UX (defer to renderer Epic 5). OQ-S4.4-c — file-watcher scope on `jelly-server` vs `jelly palace open` showcase vs CLI-only. Working assumption: runs wherever palace is `open()`ed.

---

## Epic 4 Health Metrics
- **Story count**: 4 (target 2–6) ✓
- **Complexity**: MEDIUM-HIGH overall. S4.1 LOW, S4.2 MEDIUM, S4.3 HIGH, S4.4 HIGH.
- **Test tier**: 1 smoke (S4.1), 3 thorough (S4.2/3/4).
- **AC count**: S4.1=7, S4.2=6, S4.3=7, S4.4=10. Total 30.
- **FR coverage**: FR11 → S4.1; FR5 → S4.1; FR12 → S4.2; FR13 → S4.3; FR14 → S4.4. Each canonical FR assigned to exactly one story.
- **SEC distribution**: SEC4 → S4.2 (Guild default for non-oracle); SEC5 → S4.2 (oracle bypass); SEC10 → S4.1+S4.4 (`.key` custody marker); SEC11 → S4.3+S4.4 (signed-action-before-effect); SEC1 → S4.4 (oracle dual-sig); SEC3 → S4.2 AC-6 (canonical mythos public).
- **TC coverage**: TC13 (CAS source-of-truth — S4.3, S4.4 replay); TC21 (separate oracle keypair — S4.1, S4.4); TC12 (all reads through store.ts — all four).
- **Cross-epic deps**: Epic 1 (envelopes), Epic 2 (store wrapper, transaction, reembed, schema DDL), Epic 3 (palace mint, sign-action primitive, inscribe + move). File-watcher consumes Epic 6 (`computeEmbedding`); Epic 6 doesn't depend back (acyclic).
- **Intra-epic sequencing**: S4.1 → S4.2 → S4.3 → S4.4. Linear; no parallel within epic.
- **Risk gates**: R6 (file-watcher cross-epic HIGH) → S4.4 fault-injection matrix.
- **Open questions persisted** (5): OQ-S4.1-a, OQ-S4.2-a, OQ-S4.3-a, OQ-S4.4-a/b/c.
