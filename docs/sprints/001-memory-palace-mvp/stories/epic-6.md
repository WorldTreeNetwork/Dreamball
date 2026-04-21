# Epic 6 — Recall by resonance

3 stories · MEDIUM complexity · 2 thorough / 1 smoke

## Story 6.1 — `jelly-server` `/embed` endpoint with Qwen3-Embedding-0.6B (256d MRL)

**User Story**: As a developer, I want `jelly-server` to expose a single `POST /embed` endpoint hosting Qwen3-Embedding-0.6B with MRL truncation to 256d, returning a `{vector, model, dimension, truncation}` response per D-012, so the sprint has exactly one sanctioned network exit and every consumer sees a stable contract.
**FRs**: FR20 (server side, primary); secondary FR13 (oracle K-NN consumer), FR21 (re-embedding consumer).
**NFRs**: NFR11 (sanctioned exit), NFR13 (no implicit exfiltration), NFR15 (markers), NFR17.
**Decisions**: D-012 (single POST wire shape), D-002 (Qwen3 256d MRL); SEC6, SEC7.
**Complexity**: medium · **Test Tier**: thorough · **R5 baseline measured here**

### Acceptance Criteria
- **AC1** [happy: markdown returns 256d vector]: Given jelly-server with Qwen3 loaded, When client POSTs `/embed` with `{ content: "hello palace", contentType: "text/markdown" }`, Then status 200; body matches D-012 schema `{ vector, model, dimension, truncation }`; `vector.length === 256`; every `vector[i]` finite (no NaN/Infinity); `model === "qwen3-embedding-0.6b"`; `dimension === 256`; `truncation === "mrl-256"`.
- **AC2** [determinism]: When same `{content, contentType}` POSTed twice in succession, Then two response vectors byte-identical (all 256 floats `===`); `model` + `dimension` stable.
- **AC3** [MRL truncation server-side, opaque]: Given Qwen3 natively produces 1024d, When client POSTs, Then `vector.length === 256` (not 1024); no response ever carries 1024d; `qwen3.ts` adapter unit test asserts 1024→256 truncation takes first 256 dims (MRL prefix semantics).
- **AC4** [rejects unsupported content-type]: When client POSTs with `contentType: "application/pdf"`, Then status 415; body names supported set; spy on `qwen3.embed` asserts zero calls.
- **AC5** [rejects oversize]: When client POSTs with `content` >1 MB, Then status 413; body names 1 MB limit; no inference run.
- **AC6** [no batch, no streaming (D-012 negative)]: Given route module inspected, When grep for `stream|batch|array|[]` in request/response types, Then request `content` is `string` (scalar) and response `vector` is only array-typed field; no `POST /embed/batch` or `POST /embed/stream` route exists in `jelly-server/src/routes/`.
- **AC7** [TODO-EMBEDDING markers]: When `grep -rn "TODO-EMBEDDING: bring-model-local-or-byo" jelly-server/src/`, Then matches in (a) `routes/embed.ts` route handler, (b) `embedding/qwen3.ts` model-load site; count ≥2; Vitest lint-style assertion fails if either marker removed.
- **AC8** [Storybook + Vitest mock backend]: Given Vitest + Storybook environment (no live jelly-server), When consumer imports `jelly-server/src/routes/embed.mock.ts`, Then `mockEmbed({content, contentType})` returns deterministic 256d vector derived from `blake3(content)` as float seeds; mock carries own `TODO-EMBEDDING` marker; mock NOT imported by `jelly-server/src/index.ts` (production never reaches it); `grep "embed.mock" jelly-server/src/index.ts` returns empty.
- **AC9** [server-smoke gate green]: Given fresh jelly-server boot, When `scripts/server-smoke.sh` runs, Then POST `/embed` with fixed markdown payload returns 200; `jq -e '.dimension == 256 and .model == "qwen3-embedding-0.6b"'` exits 0; smoke script total runtime within existing budget.
- **AC10** [model loads once at boot]: Given jelly-server booted and served one `/embed` request, When second request made, Then spy on `loadQwen3Model` confirms called exactly once across pair; p50 latency of second request measurably lower than first; Vitest asserts `loadQwen3Model.mock.calls.length === 1` after N consecutive requests.

### Technical Notes
New: `jelly-server/src/routes/embed.ts` (Elysia route with strict TypeBox per D-012), `jelly-server/src/embedding/qwen3.ts` (model adapter; single `embed(content): Promise<Float32Array>` surface; MRL truncation), `jelly-server/src/routes/embed.mock.ts` (harness-only seam). Extend `jelly-server/src/index.ts` (register route; load Qwen3 once at boot), `scripts/server-smoke.sh`.

Qwen3 weights load from pinned local asset path; "download from HF" vs "user-provided" left to `TODO-EMBEDDING` follow-up. Server boot MUST fail fast with `embedding model not found at <path>` if absent. MRL truncation takes **first** 256 dims per Qwen3-Embedding-0.6B's fine-tuning (prefix property). Endpoint does NOT normalize vectors.

### Scope Boundaries
- DOES: server endpoint + Qwen3 hosting + MRL truncation + mock backend + smoke gate.
- Does NOT: client-side `embedding-client.ts` and CLI `--embed-via` flag (S6.2). K-NN + ingestion `upsertEmbedding` wiring (S6.3). Batch/streaming/pooling. Local WASM/ONNX (post-MVP). Caching in endpoint (callers handle via Epic 2 `reembed`). Auth/rate-limiting beyond existing routes.

---

## Story 6.2 — `embedding-client.ts` + CLI `--embed-via` flag + ingestion path

**User Story**: As persona P0, I want `jelly palace inscribe --embed-via <url>` to call the embedding service, route the vector into `store.upsertEmbedding` within the same signed-action transaction that creates the inscription node, AND fail loudly with `inscription-pending-embedding` audit trail when the service is unreachable, so my inscriptions get embedded inline when online and stay verifiable when offline.
**FRs**: FR20 (CLI + client side); secondary FR21, FR7.
**NFRs**: NFR11 (graceful offline), NFR13 (opt-in `--embed-via`), NFR15, NFR17.
**Decisions**: D-012 (consumes wire shape from S6.1), D-007 (ingestion uses domain verb only); SEC6, SEC7, SEC11.
**Complexity**: small-medium · **Test Tier**: smoke

### Acceptance Criteria
- **AC1** [happy: inscribe against local server embeds inline]: Given jelly-server running on localhost:9808 with `/embed` live AND palace P with room R, When user runs `jelly palace inscribe P --room R ./note.md`, Then CLI exits 0; timeline carries `jelly.action` of kind `inscribe` (no `inscription-pending-embedding`); inscription node has `embedding: ARRAY(FLOAT, 256)`; 256 floats equal those returned by `/embed` for file content; inscribe action and embedding upsert in same transaction (asserted via wrapper spy).
- **AC2** [`--embed-via` defaults to local jelly-server]: Given jelly-server running on localhost:9808, When user runs without `--embed-via` flag, Then client POSTs to exactly `http://localhost:9808/embed`; request visible in jelly-server access logs with file's Content-Length.
- **AC3** [`--embed-via <custom-url>` routes to user-specified]: Given user-hosted service at `http://gpu-box.local:7777/embed`, When user runs with `--embed-via http://gpu-box.local:7777/embed`, Then client POSTs exactly that URL; no request to localhost:9808; returned vector lands on inscription as AC1.
- **AC4** [offline: service unreachable yields clean exit + signed audit]: Given jelly-server NOT running (or `--embed-via` URL unreachable), When user runs `jelly palace inscribe P --room R ./note.md`, Then CLI exits with non-zero code distinct from crash (suggested: 2); stderr contains `embedding service unreachable at <url>`; `jelly.action` of kind `inscription-pending-embedding` appended; action dual-signed (Ed25519 + ML-DSA-87) before inscription node commits; inscription node committed WITHOUT `embedding` property (null/absent); palace verifies clean (`jelly verify P` exits 0); `jelly palace open P` still renders the inscription (dimmed/untagged — renderer handles null).
- **AC5** [offline path emits action BEFORE effect (SEC11)]: Given offline scenario, When spy placed on `timeline.recordAction` and `store.createInscription`, Then `recordAction` called before `createInscription`; if `recordAction` throws, `createInscription` never invoked (rollback leaves store in pre-inscribe state).
- **AC6** [TODO-EMBEDDING markers]: When `grep -rn "TODO-EMBEDDING: bring-model-local-or-byo"` over `src/cli/`, `src/memory-palace/embedding-client.ts`, `src/memory-palace/inscribe-bridge.ts`, Then matches in (a) `palace_inscribe.zig` flag handler, (b) `embedding-client.ts` HTTP call site, (c) `inscribe-bridge.ts` orchestration site; total ≥3.
- **AC7** [help text advertises sanctioned exit]: When user runs `jelly palace inscribe --help`, Then output documents `--embed-via <url>` with default `http://localhost:9808/embed`; carries one-line note "Embedding is the single sanctioned network exit (NFR11)."; `jelly palace --help` lists `inscribe` among MVP subcommands (Epic 3 S3.1 scaffold).
- **AC8** [content-type inferred from file extension]: Given files `note.md`, `note.txt`, `note.adoc`, `note.xyz`, When each inscribed, Then `.md` → `text/markdown`; `.txt` → `text/plain`; `.adoc` → `text/asciidoc`; `.xyz` → `text/plain` fallback (warning on stderr; no error); unsupported-content-type 415 from server propagates as user-visible error, not crash.
- **AC9** [Epic 4 file-watcher reuses this client (cross-epic contract)]: Given Epic 4 S4.4 file-watcher module `src/memory-palace/file-watcher.ts`, When imports inspected, Then imports `embedFor` (or equivalent) from `src/memory-palace/embedding-client.ts`; does NOT re-implement HTTP calling logic; grep `fetch(` in `file-watcher.ts` returns zero.
- **AC10** [cli-smoke.sh gate green for both online + offline]: Given `scripts/cli-smoke.sh` extended with palace-inscribe block, When smoke runs with jelly-server up, Then inscribe succeeds and inscription carries embedding; with jelly-server killed, inscribe exits non-zero with `inscription-pending-embedding` action on timeline; both branches exit smoke script cleanly.

### Technical Notes
New: `src/memory-palace/embedding-client.ts` (HTTP client with graceful-degradation), `src/memory-palace/inscribe-bridge.ts` (orchestrates call-embed + upsert-within-transaction). Extend `src/cli/palace_inscribe.zig` (`--embed-via <url>` flag + TS bridge invocation), `src/lib/generated/actions.ts` (regenerated — `inscription-pending-embedding` added to action-kind enum via `format-version: 3` envelope in Epic 1), `scripts/cli-smoke.sh`.

`inscription-pending-embedding` action kind is added to `jelly.action` envelope's `action-kind` enum in Epic 1 Story 3 (timeline + action at v3). Confirm enum value present before Story 2 begins; if absent, raise cross-epic blocker. Exit code 2 suggested for offline path so shells can `if [ $? -eq 2 ]; then ...retry-later...; fi`. Do not reuse 1 (generic) or 130 (SIGINT). TS bridge transaction boundary: store verb call and inscribe action emission MUST be in one `store.transaction(() => ...)`; if embedding service returns vector but store write fails, signed action MUST NOT land — pair atomic.

### Scope Boundaries
- DOES: HTTP client + CLI flag + ingestion atomicity + offline graceful-degradation + cross-epic contract with Epic 4.
- Does NOT: K-NN Cypher helper (S6.3). Oracle file-watcher re-embedding invocation (Epic 4 S4.4 — consumes `embedding-client.ts` but implements own mutex window). 200ms K-NN budget (S6.3). Retry/backoff for `inscription-pending-embedding`. `--embed-via` on `add-room`.

---

## Story 6.3 — K-NN query path + 200ms budget + offline graceful-degradation

**User Story**: As persona P2 (oracle host), I want `store.kNN(query, k)` to return top-k nearest inscriptions by cosine distance in <200ms on 500-inscription corpus with a typed `OfflineKnnError` when the embedding service is unreachable, so the oracle's resonance recall meets the latency budget for sprint-001 and degrades cleanly when offline.
**FRs**: FR20 (K-NN side); secondary FR13.
**NFRs**: NFR10 (<200ms latency budget), NFR11 (offline graceful-degradation), NFR13, NFR15, NFR17.
**Decisions**: D-007 (`kNN` domain verb), D-015 (cross-runtime parity consumer), D-016 (K-NN Cypher pattern), D-012 (consumes S6.1 wire); SEC6, SEC7.
**Complexity**: medium · **Test Tier**: thorough · **R5 mitigation IS this story's perf test**

### Acceptance Criteria
- **AC1** [happy: query returns top-k nearest]: Given palace with 3 inscriptions A, B, C where A is semantically closest to `"palace of memory"` AND jelly-server with `/embed` live AND all 3 carry valid embeddings, When `store.kNN("palace of memory", 2)` called, Then result is `KnnHit[]` of length 2; `result[0].fp === A.fp`; `result[0].distance < result[1].distance`; every hit carries resolved `roomFp` (graph-join returned `LIVES_IN`); no hit has `distance: null` or `NaN`.
- **AC2** [Cypher matches D-016 exactly]: Given `store.ts` inspected, When `grep "QUERY_VECTOR_INDEX" src/memory-palace/store.ts`, Then exactly one match; surrounding Cypher uses `YIELD node AS i, distance`; subsequent `MATCH (i:Inscription)-[:LIVES_IN]->(r:Room)` clause; `RETURN` emits `fp`, `roomFp`, `distance` in order; `ORDER BY distance` ascending.
- **AC3** [500-inscription perf budget — top-10 K-NN <200ms (R5)]: Given deterministic 500-inscription corpus generated by `perf-fixtures.ts` + each carries valid 256d embedding (pre-populated, no runtime embed during setup) + jelly-server local on 9808, When `store.kNN("query text", 10)` called 10 times consecutively, Then every call returns exactly 10 hits; p50 end-to-end <200ms; p95 <400ms (soft ceiling — breach → warn + ADR addendum, do not fail); `scripts/perf/embedding.sh` reports `budget-met` OR `warn-threshold-near-budget`; measurement explicitly includes `/embed` query-embed round-trip.
- **AC4** [offline: /embed unreachable yields typed `OfflineKnnError`]: Given jelly-server NOT running, When `store.kNN("anything", 10)` called, Then call rejects with `OfflineKnnError`; `error.reason === "embedding-service-unreachable"`; `error.cached` is empty array `[]`; store remains readable for all other verbs (e.g. `store.getRoom(fp)` still works); no process crash; `jelly palace open` after failure still renders palace; renderer handles error gracefully (palace lens doesn't blank-screen; resonance-search UI shows "offline" indicator).
- **AC5** [offline fallback contract explicit (not silent)]: Given graceful-degradation requirement of NFR11, When `store.kNN` encounters unreachable service, Then NEVER returns resolved Promise with stale-but-reasonable results; ALWAYS rejects with `OfflineKnnError`; typed error exported from `store.ts` so Epic 4 + Epic 5 can catch; Vitest test asserts offline branch is `throw`, not `return`.
- **AC6** [cross-runtime routing per D-015 outcome]: Given parity-spike result recorded in `docs/decisions/2026-04-21-vector-parity.md`, When `store.kNN` called in server test (Bun + `@ladybugdb/core`), Then uses local native runtime; in browser test (Playwright + kuzu-wasm), IF parity passed → uses local kuzu-wasm; IF parity degraded → routes through HttpBackend with one-time `console.warn` naming NFR11 relaxation; branch matches ADR outcome (runtime, not compile-time toggle).
- **AC7** [TODO-EMBEDDING marker at query-embed call site]: Given `src/memory-palace/store.ts`, When `grep -B2 -A2 "TODO-EMBEDDING: bring-model-local-or-byo"` over file, Then marker appears directly above query-embedding call (`embeddingClient.embedFor(query, ...)`) inside `kNN`; does NOT appear at vector-index lookup site (that's local — no exit to mark).
- **AC8** [re-embedding round-trip via Epic 2 `reembed`]: Given inscription I with embedding E1 from content C1, When content changes to C2 and file-watcher (or CLI retry) triggers re-embedding, Then `embedding-client.embedFor(C2)` returns E2; `store.reembed(I.fp, E2)` executes as single transaction (delete-then-insert per FR21); subsequent `kNN` query closest to E1 returns updated ordering based on E2; zero orphan rows in vector index for `I.fp`.
- **AC9** [server-smoke.sh round-trip green]: Given `scripts/server-smoke.sh` extended with K-NN block, When runs end-to-end (mint palace → add room → inscribe 3 docs → query kNN), Then query returns 3 hits; top-1 is one of 3 inserted docs; smoke total runtime within existing budget.
- **AC10** [Storybook coverage online + offline]: Given Storybook story for K-NN-driven UI (oracle search or resonance browser), When story runs with jelly-server mock returning valid vectors, Then top-k results render as inscription cards with distance badges; when story runs with mock throwing `OfflineKnnError`, Then UI shows "offline — cached-only" indicator; no console error past catch boundary; play-test passes for both.

### Technical Notes
Extend `src/memory-palace/store.ts` (`kNN` implementation; `OfflineKnnError`), `src/memory-palace/embedding-client.ts` (consumer reused from S6.2; no fork). New: `src/memory-palace/perf-fixtures.ts` (deterministic 500-inscription corpus generator), `scripts/perf/embedding.sh`. Extend `scripts/server-smoke.sh`.

500-inscription corpus generator deterministic (seeded). Embeddings pre-computed and pickled into fixture file so perf test doesn't cold-start Qwen3 mid-measurement. Perf test measures QUERY embedding call, not N=500 setup. `ORDER BY distance` is cosine distance (lower = closer); reconfirm against LadybugDB v0.15.3 vector-extension docs during implementation. Offline `cached: []` design deliberately punts "what to show when offline" to consumer epics — Epic 4 may want knowledge-graph triples, Epic 5 may want dim search UI. The typed error is the seam; do not add fallback logic inside `store.kNN`. If Epic 2 S2.1 HARD-BLOCKS, this story runs on server-only routing with runtime warning; documented NFR11 relaxation, not failure.

### Scope Boundaries
- DOES: `kNN` verb implementation + offline error + perf budget + cross-runtime routing + `reembed` round-trip + Storybook coverage.
- Does NOT: Oracle K-NN result mirroring (Epic 4 S4.3). File-watcher re-embedding mutex (Epic 4 S4.4 consumes `kNN` and `reembed`). Quantised vectors (PRD FR83 deferred). Hybrid lexical+semantic (post-MVP). K-NN over memory-nodes (FR20 names them; MVP scope inscriptions only — known-gap). Dimension-tuning UX (`EMBEDDING_DIM` fixed at 256).

---

## Epic 6 Health Metrics
- **Story count**: 3 (target 2–6) ✓
- **Complexity**: MEDIUM overall — S6.1 medium (single network exit, wire-shape discipline); S6.2 small-medium (flag wiring + graceful-degradation); S6.3 medium (perf budget + routing branch on D-015 outcome).
- **Test tier**: thorough (S6.1) — smoke (S6.2) — thorough (S6.3). S6.2 rides on Epic 2 thorough ingestion-path testing + Epic 3 thorough CLI dispatch testing.
- **AC count**: S6.1=10, S6.2=10, S6.3=10. Total 30.
- **FR coverage**: FR20 → S6.1 (server) + S6.2 (CLI) + S6.3 (kNN). NFR11 → S6.1 (sanctioned exit), S6.2 (offline ingestion), S6.3 (offline reads). NFR13 → S6.2 (opt-in `--embed-via`). NFR15 → all 3. SEC6 → S6.1; SEC7 → all 3; SEC11 → S6.2 (`inscription-pending-embedding` action-before-effect).
- **Cross-epic deps**: Upstream — Epic 1 (envelope baseline; `inscription-pending-embedding` action-kind in Story 3), Epic 2 (store ingestion + `kNN` verb sig + `reembed` + D-015 parity outcome + schema DDL for `inscription_emb`), Epic 3 (`jelly palace inscribe` consumes `--embed-via`). Downstream consumers — Epic 4 S4.3 (oracle K-NN consumes `store.kNN` + `OfflineKnnError`), Epic 4 S4.4 (file-watcher re-embedding reuses `embedding-client.ts` and calls `reembed`).
- **Risk gates**: R5 (Qwen3 latency on representative hardware) → S6.3 AC3 (500-corpus, p50 <200ms); `scripts/perf/embedding.sh` IS the R5 mitigation; warn-threshold path with ADR addendum acceptable; HARD BLOCK only if <400ms p95 breached. R2 (vector-extension parity) → S6.3 AC6 (runtime routing branches on D-015 outcome). R6 (file-watcher cross-epic) → S6.2 AC9 (Epic 4 reuses `embedding-client.ts`).
- **Build-gate coverage**: `bun run test:unit -- --run`, `bun run check`, `bun run test-storybook`, `scripts/server-smoke.sh`, `scripts/cli-smoke.sh`, `scripts/perf/embedding.sh` (new). No new Zig surface (CLI flag thin; payloads via TS bridge).
- **Open questions**: OQ-E6-1 — Offline `cached: []` may surface knowledge-graph-triple fallback or last-opened-neighbour fallback in future. OQ-E6-2 — K-NN over memory-nodes (FR20 names them) MVP-scoped to inscriptions only; post-MVP follow-up. OQ-E6-3 — Retry mechanism for `inscription-pending-embedding` is a follow-up.
