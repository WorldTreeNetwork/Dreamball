# Epic 2 — Remember the palace across runtimes

5 stories · HIGH complexity · all thorough

## Story 2.1 — Cross-runtime vector-parity spike (R2 gate, D-015)

**User Story**: As a developer, I want a parity harness running identical K-NN fixtures on `@ladybugdb/core` (Bun) and `kuzu-wasm@0.11.3` (Playwright Chromium), so cross-runtime vector behaviour is verified before Epic 6 commits and so a documented fallback exists if browser parity fails.
**FRs**: FR19 (consumer contract); NFR11 (gates local-first K-NN); NFR17 (green-on-commit).
**Decisions**: D-015 (primary); D-016 (consumer — `Inscription.embedding` column).
**Complexity**: medium · **Test Tier**: thorough · **Risk gate** — R2

### Acceptance Criteria
- **AC1** [fixture deterministic]: Given seed=42, When 100 vectors of dim 256 generated, Then Blake3 of concatenation matches documented constant; second invocation byte-identical.
- **AC2** [server ground truth]: Given fixture in `@ladybugdb/core` Inscription.embedding column, When `CALL QUERY_VECTOR_INDEX('inscription_emb', $q, 10)` runs with seed=43, Then 10 rows returned each with `fp` and `distance`; recorded as ground truth.
- **AC3** [browser parity]: Given identical fixture in `kuzu-wasm@0.11.3` (IDBFS lifecycle complete), When same Cypher runs in Chromium worker, Then 10 returned fps set-equal to server ground truth AND per-item cosine variance |Δ| ≤ 0.1.
- **AC4** [WARN path]: Given set-equality holds AND ≥1 |Δ| > 0.1, Then test passes with WARN marker; addendum file records max |Δ|; upstream issue reference appended.
- **AC5** [HARD BLOCK]: Given browser set-equality fails, Then test asserts failure with "HARD BLOCK: D-015 parity"; S2.2–S2.5 cannot proceed without `/replan` for server-only K-NN; `docs/known-gaps.md` gets NFR11 K-NN relaxation entry.
- **AC6** [CI]: Given parity test in `bun run test:unit -- --run` AND Playwright in `bun run test:e2e`, When CI runs, Then both halves execute; CI fails on HARD BLOCK, permits WARN with annotation.

### Technical Notes
New files: `src/memory-palace/parity.test.ts`, `src/memory-palace/fixtures/knn-parity.ts`, `playwright.config.ts` extension, `docs/sprints/001-memory-palace-mvp/addenda/S2.1-parity-result.md`. File LadybugDB upstream issue #399 reference if WARN/FAIL.

**Open questions**: (a) Does kuzu-wasm@0.11.3 expose `QUERY_VECTOR_INDEX` identically to `@ladybugdb/core`? Verify first. (b) Playwright vs vitest-browser-mode — follow existing pattern.

---

## Story 2.2 — `store.ts` server adapter: domain-verb API + close lifecycle

**User Story**: As a developer, I want `src/memory-palace/store.ts` as the TC12 swap boundary on the server side with `@ladybugdb/core` napi, exposing D-007 domain verbs and enforcing explicit `close()` lifecycle, so every downstream epic consumes a single typed contract and the Bun napi finalizer crash is mechanically prevented.
**FRs**: FR19 (primary); FR21 (`reembed` surface, impl in S2.5); NFR11/13/18.
**Decisions**: D-007 (primary — API shape), D-016 (consumer via S2.4), TC9 (explicit close), TC12 (swap boundary), TC13 (no CBOR in DB).
**Complexity**: large · **Test Tier**: thorough

### Acceptance Criteria
- **AC1** [no caller outside store.ts imports `@ladybugdb/core`]: When `grep -R "@ladybugdb/core" src/ jelly-server/` excludes `src/memory-palace/store*.ts`, Then zero matches.
- **AC2** [containment verbs]: Given opened store, When `ensurePalace` then `addRoom` then `inscribeAvatar` called in order, Then `__rawQuery("MATCH (:Palace)-[:CONTAINS]->(:Room)-[:CONTAINS]->(:Inscription) RETURN count(*)")` returns 1.
- **AC3** [mythos-head verbs satisfy FR5]: Given palace with genesis mythos via `setMythosHead`, When `appendMythos(newFp, predFp)` then `setMythosHead(palaceFp, newFp)`, Then `MATCH (:Palace {fp: $p})-[:MYTHOS_HEAD]->(m:Mythos)` returns one row with new fp; `(:Mythos {fp: $new})-[:PREDECESSOR]->(:Mythos {fp: $prior})` returns 1.
- **AC4** [ActionLog as commit-log table]: Given schema initialised, When `recordAction({fp, palaceFp, actionKind: "mint-room", actorFp, targetFp, parentHashes: [], timestamp})` called, Then row exists in `ActionLog` node table; no `Action` node label exists; `headHashes(palaceFp)` returns set containing new fp.
- **AC5** [explicit close]: Given spy wrapping `Connection.query` and `QueryResult.close`, When 50 verbs invoked random sequence, Then every `query()` paired with `close()` before verb returns; no Bun napi finalizer warnings at process exit.
- **AC6** [escape-hatch underscored]: Given exported API, Then only function matching `/raw|cypher/i` is `__rawQuery`; TSDoc marks `@deprecated-for-new-callers; diagnostic-only`.
- **AC7** [syncfs no-op on server]: When `syncfs('in')` or `syncfs('out')` called, Then returns within 1ms; no FS or IDB side effect.
- **AC8** [server smoke round-trip]: When `scripts/server-smoke.sh` runs, Then store round-trip block (open→mint→addRoom→inscribe→close→reopen→verify) sees prior data; exits 0.
- **AC9** [replay-from-CAS]: Given populated store fully serialised via recorded actions, When `.lbug` files deleted and every action replayed, Then resulting node-label histogram equals pre-delete histogram.

### Technical Notes
New: `src/memory-palace/store.ts`, `src/memory-palace/store.server.ts`, `src/memory-palace/store-types.ts`, `src/memory-palace/store.server.test.ts`. Belt-and-braces `process.exit(0)` on CLI success path (ADR step-1 mitigation #1) documented but deferred to Epic 3.

**Open questions**: `StoreAPI` interface in `store-types.ts` (preferred — shared) vs inferred from `store.server.ts`? Prefer explicit interface.

---

## Story 2.3 — `store.ts` browser adapter: kuzu-wasm@0.11.3 + IDBFS lifecycle

**User Story**: As a developer, I want `src/memory-palace/store.browser.ts` implementing the same `StoreAPI` as the server, backed by `kuzu-wasm@0.11.3` with `mountIdbfs` + `syncfs` bidirectional lifecycle exactly per the ADR, so the browser palace persists across page reloads and the API surface is symmetric across runtimes.
**FRs**: FR19 (browser half); NFR11 (offline reads); NFR13.
**Decisions**: D-007 (consumer — identical verbs), D-015 (consumer — kNN per S2.1 outcome), TC8/10/12.
**Complexity**: large · **Test Tier**: thorough · **Chromium-only for MVP per OQ3** (R1 risk)

### Acceptance Criteria
- **AC1** [bootstrap copies worker]: Given fresh `bun install`, When `bun run bootstrap` completes, Then `static/kuzu_wasm_worker.js` exists with Blake3 matching `node_modules/kuzu-wasm/kuzu_wasm_worker.js`.
- **AC2** [worker path set once]: Given `store.browser.ts` imported N times in single page, Then `kuzu.setWorkerPath('/kuzu_wasm_worker.js')` invoked exactly once.
- **AC3** [open lifecycle]: Given browser context with no prior IDB, When `open()` called, Then `FS.mkdir('/data')` succeeds or recovers; `FS.mountIdbfs('/data')` resolves; `FS.syncfs(true)` resolves before `new Database('/data/palace.kz')`; usable Connection returned.
- **AC4** [close lifecycle]: Given opened store with pending writes, When `close()` called, Then `conn.close()` then `db.close()` resolve in order; `FS.syncfs(false)` resolves before `FS.unmount('/data')`; IndexedDB inspection shows `.kz` bytes flushed.
- **AC5** [round-trip across page reload]: Given opened store in Playwright Chromium, When mutations + `close()` then page reload + `open()` + `__rawQuery("MATCH (:Palace)-[:CONTAINS]->(:Room) RETURN count(*)")`, Then query returns 1.
- **AC6** [API symmetry]: Given `store-types.ts` declares `StoreAPI`, When `store.browser.ts` type-checked against it, Then `bun run check` reports zero errors; every verb from S2.2 exists on browser adapter.
- **AC7** [kNN per S2.1 outcome]: Given S2.1 passed, When `kNN(query, 10)` called in browser, Then local kuzu-wasm vector ext serves query (no HTTP); results match S2.1 parity contract.
- **AC8** [kNN HTTP fallback if S2.1 degraded]: Given ADR addendum marks S2.1 fallback-active, When `kNN` called in browser, Then routes to HTTP endpoint (Epic 6 replan); `TODO-KNN-FALLBACK` marker preserved.
- **AC9** [non-Chromium warning]: Given Playwright Firefox or Safari context, When `open()` called, Then console warning emitted: "kuzu-wasm@0.11.3 validated on Chromium only; expect failures"; rest of API still invoked.
- **AC10** [double-open safety]: Given store already open, When `open()` called second time without `close()`, Then either returns existing handle or throws typed `StoreAlreadyOpen`; no zombie IDBFS mount.

### Technical Notes
New: `src/memory-palace/store.browser.ts`, `scripts/bootstrap-kuzu-wasm.ts`, Playwright config extension, `static/kuzu_wasm_worker.js` (gitignored, emitted by bootstrap), `.gitignore` extension.

**Open questions**: (a) SvelteKit `static/` maps to `/`? Per ADR yes — verify `svelte.config.js`. (b) `postinstall` hook for `bun run bootstrap` vs manual? Prefer postinstall.

---

## Story 2.4 — `schema.cypher` + action-mirror: canonical DDL + sync ingestion

**User Story**: As a developer, I want a single-file `src/memory-palace/schema.cypher` per D-016 plus an `action-mirror.ts` that synchronously mirrors every signed `jelly.action` into the corresponding LadybugDB rows within one transaction, so the palace's queryable view stays consistent with the signed timeline at all times.
**FRs**: FR19 (primary); NFR18 (replay-from-CAS); NFR13 (no bytes in DB).
**Decisions**: D-016 (primary — IS this story), D-007 (consumer — mirror via verbs), TC13.
**Complexity**: medium · **Test Tier**: thorough

### Acceptance Criteria
- **AC1** [schema completeness]: Given `schema.cypher` parsed, Then node-table set is exactly `{Palace, Room, Inscription, Agent, Mythos, Aqueduct, ActionLog}`; `Inscription.embedding FLOAT[256]`; `ActionLog.parent_hashes STRING[]`; no `Action` node label exists.
- **AC2** [relationships]: Given parsed, Then rel-table set exactly `{CONTAINS, MYTHOS_HEAD, PREDECESSOR, LIVES_IN, AQUEDUCT_FROM, AQUEDUCT_TO, KNOWS}`; `DISCOVERED_IN` appears only as `Mythos.discovered_in_action_fp STRING` property (NOT a relationship).
- **AC3** [DDL idempotent]: Given fresh `.lbug`, When `open()` called first time, Then every table per schema exists; second `open()` succeeds; no duplicate-table error.
- **AC4** [vector index]: Given fresh open, When DDL executes, Then `CALL SHOW_INDEXES()` includes `inscription_emb`; subsequent opens don't re-create.
- **AC5** [action-mirror correctness]: Given decoded `add-room` action with target roomFp, When `mirrorAction(palaceFp, action)` runs in transaction, Then `ActionLog` row exists with matching fields; `(:Palace)-[:CONTAINS]->(:Room {fp: roomFp})` edge exists; both writes committed atomically.
- **AC6** [rollback on failure]: Given decoded action whose target fp refers to non-existent palace, When `mirrorAction` runs, Then transaction rolls back; neither `ActionLog` row nor edge visible post-error.
- **AC7** [rename-mythos mirror]: Given palace with current head M1, When `"true-naming"` action with new mythos M2 mirrored, Then exactly one `MYTHOS_HEAD` edge from palace pointing M2; `(M2)-[:PREDECESSOR]->(M1)` edge exists; `M2.discovered_in_action_fp` equals action fp.
- **AC8** [inscribe sync mirror]: Given decoded inscribe action with docFp + roomFp, When `mirrorAction` runs, Then within same transaction: Inscription row inserted, `CONTAINS` edge from room, `LIVES_IN` edge to room — all visible together; `orphaned: false`.
- **AC9** [aqueduct-created mirror]: Given decoded `aqueduct-created` action with aqueductFp + fromFp + toFp, Then `(:Aqueduct {fp})-[:AQUEDUCT_FROM]->(:Room {fromFp})` and `(:Aqueduct {fp})-[:AQUEDUCT_TO]->(:Room {toFp})` exist; Aqueduct row carries default `resistance: 0.3`, `capacitance: 0.5` (per D3).
- **AC10** [replay-from-CAS NFR18]: Given populated store with N mutations recorded as signed actions, When `.lbug` deleted and mirror replayed in timestamp order, Then node-label histogram + edge-type histogram equal pre-delete; every `ActionLog` row present with byte-identical `cbor_bytes_blake3`.
- **AC11** [TC13 no CBOR in DB]: Given any store after arbitrary mutation, When every column inspected, Then no column stores raw CBOR; every envelope reference is Blake3 fp.

### Technical Notes
New: `src/memory-palace/schema.cypher`, `src/memory-palace/action-mirror.ts`, tests. Extend store.server.ts + store.browser.ts to execute DDL on `open()`.

**Open questions**: (a) Does kuzu-wasm@0.11.3 support `CREATE VECTOR INDEX` identically? Gated by S2.1; if fallback triggered, `inscription_emb` index server-side only. (b) `action-mirror.ts` flat or nested under `src/memory-palace/mirror/`? Prefer flat.

---

## Story 2.5 — `aqueduct.ts`: canonical FR26 formula home + `reembed` verb

**User Story**: As a developer, I want `src/memory-palace/aqueduct.ts` as the **sole canonical home** for the FR26 Hebbian + Ebbinghaus formulas + a `reembed(fp, newBytes, newVec)` verb implementing FR21's delete-then-insert as the only vector-write code path, so Epic 3 (save-time compute) and Epic 5 (renderer freshness uniform) produce bit-identical conductance values from one tested module.
**FRs**: FR21 (primary — reembed); FR26 (primary — canonical home); NFR16; D-007 (consumer); D-016 (Aqueduct schema row); TC16 (conductance optional); TC17 (strength monotone).
**Complexity**: medium · **Test Tier**: thorough · **R7 mitigation**

### Acceptance Criteria
- **AC1** [formula block at top]: Given `aqueduct.ts`, When first non-import statement inspected, Then single `/** ... */` block documents three formulas (strength, conductance, phase); carries date `2026-04-21` and "tunable; in flux" marker; cites D4 + Vril ADR.
- **AC2** [updateStrength saturates]: Given strength=0, α=0.1, When updateStrength applied 100 times iteratively, Then final strength > 0.9999 AND ≤ 1.0.
- **AC3** [updateStrength pure]: Given same inputs, When called 1000 times from parallel workers, Then every call returns byte-identical Float64; no side effects.
- **AC4** [conductance at t=0]: Given resistance=0.3, strength=0.8, t=0, When computeConductance called, Then result within 1e-12 of 0.56.
- **AC5** [conductance at t=τ]: Given same with τ=30 days, t=30 days, Then result within 1e-12 of 0.56 × exp(-1) ≈ 0.2060.
- **AC6** [derivePhase classification]: Given window of N out-direction events, Then "out"; in-events → "in"; symmetric window above resonance threshold → "resonant"; otherwise → "standing".
- **AC7** [Epic 3 + Epic 5 parity (R7)]: Given fixture aqueduct state, When Epic 3 save-time path AND Epic 5 renderer uniform path both call computeConductance, Then both return byte-identical Float64; unit test locks bit-identity.
- **AC8** [reembed delete-then-insert sole vector-write path (FR21)]: Given store with embedding for fp X, When `reembed(X, newBytes, newVec)` runs, Then within single transaction `deleteEmbedding(X)` then `upsertEmbedding(X, newVec)`; static analysis: `grep "SET.*embedding|UPDATE.*embedding"` returns only reembed body; `MATCH (:Inscription {fp: X}) RETURN count(*)` returns 1.
- **AC9** [reembed short-circuit on unchanged hash]: Given existing Inscription with `source_blake3 = hash_a`, When reembed called with newBytes whose hash equals hash_a, Then embedder spy records zero calls; transaction commits with no vector-write observed.
- **AC10** [updateAqueductStrength bumps revision]: Given store with Aqueduct at revision R, When `"move"` action traverses + mirror runs, Then `strength` updates per Hebbian; `conductance` per Ebbinghaus; `revision` = R+1; `resistance` + `capacitance` byte-identical (runtime MUST NOT overwrite); envelope re-signed.
- **AC11** [freshnessForRender monotone]: Given strength-fixed aqueduct, When sampled at t = 0, 1d, 10d, 30d, 90d, Then values strictly monotone-decreasing; t=0 returns 1.0.

### Technical Notes
New: `src/memory-palace/aqueduct.ts`, `src/memory-palace/aqueduct.test.ts`. Extend `store.server.ts` + `store.browser.ts` to implement `reembed`, `updateAqueductStrength`, `getOrCreateAqueduct` using aqueduct.ts. Extend action-mirror.ts to wire `move` action.

**Open questions**: (a) `TraversalWindow` defined here or shared from Epic 3? Define here; Epic 3 imports. (b) Resonance-count threshold for "resonant" — propose `count >= 4 AND symmetry_ratio ∈ [0.4, 0.6]`; document in formula block.

---

## Epic 2 Health Metrics
- **Story count**: 5 (target 2–6) ✓
- **Complexity**: HIGH overall. Story sizes M, L, L, M, M.
- **Test tier**: 5/5 thorough. Justified — single swap boundary; data-integrity critical; R2 + R7 mitigations.
- **FR coverage**: FR19 → 2.2, 2.3, 2.4. FR21 → 2.5. FR26 → 2.5. NFR11 → 2.1, 2.3. NFR13 → 2.2, 2.3. NFR18 → 2.4.
- **Cross-epic deps**: forward — none. Consumed by Epics 3, 4, 5, 6.
- **Risk gates**: R2 → 2.1 (HARD BLOCK on set inequality). R1 → 2.3 (Chromium-only MVP per OQ3). R7 → 2.5 (bit-identical test between Epic 3 + Epic 5 call sites).
- **Build-gate coverage**: `bun run check`, `bun run test:unit -- --run`, `bun run test:e2e` (Playwright Chromium), `scripts/server-smoke.sh`. No new golden fixtures (Epic 1's surface).
