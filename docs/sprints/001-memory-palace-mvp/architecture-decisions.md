---
sprint: sprint-001
product: memory-palace
phase: 2A — Architecture Decisions
mode: default
steering: GUIDED
created: 2026-04-21
author: planner (OMC)
decisions_count: 10
starts_at: D-007
---

# Sprint-001 — Architecture Decisions

These decisions extend the six steering decisions already logged in
`phase-state.json` (D-001 through D-006, all from `requirements.md §Decision
Steering`) with the architecture-level choices Epics A–F need locked before
story decomposition.

Every decision below traces back to concrete FRs, NFRs, TCs, SECs, or scope
risks from `sprint-scope.md` and `requirements.md`.

Decisions already made and **not re-opened** in this phase:

- Graph + vector store: LadybugDB server / `kuzu-wasm@0.11.3` browser
  (ADR 2026-04-21-ladybugdb-selection.md).
- Signature policy: hybrid Ed25519 + ML-DSA-87; "all present sigs verify,
  no minimum count" (`PROTOCOL.md §2.3, §8`).
- Wire format: palace envelopes at `PROTOCOL.md §13`; timeline + action
  at `format-version: 3`, others at `2` (TC14).
- Dream-field model: palace embeds, does not become one
  (ADR 2026-04-21-dream-field-embedding.md; TC19).
- Vril flow: monotone `strength` on wire; freshness is renderer-side
  (ADR 2026-04-21-vril-flow-model.md; TC17).
- CRDT compatibility: `head-hashes` as a set; stacked `'signed'` quorum
  (ADR 2026-04-21-nextgraph-crdt-review.md; TC15, SEC8).
- Embedding model: Qwen3-Embedding-0.6B, 256d MRL-truncated, server-hosted
  (D-002).
- Oracle identity: separate hybrid keypair (D-005; TC21; SEC10).
- Aqueduct lifecycle: lazy on first traversal (D-003).
- Aqueduct formulas: Hebbian saturating + Ebbinghaus decay (D-004).
- FR14 file-watcher: MVP scope (D-001).
- WASM budget: ≤200 KB raw / ≤64 KB gzipped; ships ML-DSA-87 verify
  (CLAUDE.md 2026-04-21; TC5).

---

## Significance Summary

| Significance | Count | Decision IDs |
|--------------|-------|--------------|
| **CRITICAL** | 3     | D-007, D-010, D-016 |
| **HIGH**     | 4     | D-008, D-009, D-014, D-016*prior-listed* — counted once |
| **MEDIUM**   | 3     | D-011, D-012, D-013, D-015 — see note |

*Note on counts:* 10 proposed decisions by severity:

| Significance | Count |
|--------------|-------|
| **CRITICAL** | 3 (D-007, D-010, D-016) |
| **HIGH**     | 4 (D-008, D-009, D-014, D-015) |
| **MEDIUM**   | 3 (D-011, D-012, D-013) |

The three CRITICAL decisions (Store wrapper API, WASM ML-DSA-87 verify
validation path, LadybugDB schema) gate nearly every other epic; these
are the ones the orchestrator should surface for user confirmation
first.

---

## Sections

1. **Data & Storage** — D-007 (Store API), D-016 (Schema)
2. **Cross-Runtime Crypto** — D-010 (WASM ML-DSA-87 verify)
3. **Transactional Integrity** — D-008 (File-watcher boundary)
4. **Rendering** — D-009 (Shader spike gate)
5. **Security & Custody** — D-011 (Oracle secret-key custody)
6. **Service Surfaces** — D-012 (Embedding endpoint), D-015 (Vector parity)
7. **CLI Shape** — D-013 (Dispatch nesting)
8. **Content Integrity** — D-014 (Archiform registry cache)

(Infra section empty — no net-new infrastructure this sprint.)

---

# 1. Data & Storage

---

## D-007: Store wrapper API surface — domain verbs over raw Cypher

- **Date**: 2026-04-21
- **Sprint**: sprint-001
- **Significance**: CRITICAL
- **Epics affected**: B (primary), C, D, E, F

### Context

TC12 mandates that **all palace state mirrors through a single swap
boundary `src/memory-palace/store.ts`** — `grep` for `@ladybugdb/core`
or `kuzu-wasm` outside this file must return empty (FR19 acceptance).
The ADR 2026-04-21-ladybugdb-selection.md has already pinned the
close-lifecycle pattern:

```ts
async function query<T>(cypher: string, params?: unknown): Promise<T[]> {
  const qr = await conn.query(cypher, params);
  try { return await qr.getAll() as T[]; }
  finally { await qr.close(); }
}
```

The open architectural question is **what the public surface above
that internal `query<T>` looks like**. Three options:

1. **Raw Cypher passthrough.** Export `query<T>(cypher, params)` and
   let every caller write Cypher directly.
2. **Domain verbs.** Export `addRoom(palaceFp, roomFp)`, `inscribe(roomFp,
   docFp, embedding)`, `recordTraversal(from, to)`, `aqueductAt(from, to)`,
   `kNearestInscriptions(vec, k)`, etc. Internal `query<T>` is private.
3. **Hybrid.** Domain verbs for the common path; a narrow escape-hatch
   `query<T>` for advanced oracle/diagnostic work.

### Decision

**Adopt option 3 — hybrid: domain verbs as the contract, narrow
`query<T>` escape-hatch.**

The public surface is a named-verb API shaped around the palace domain:

| Verb group | Signatures (illustrative) |
|------------|----------------------------|
| Containment | `ensurePalace(fp, mythosHeadFp)`, `addRoom(palaceFp, roomFp, archiform?)`, `inscribeAvatar(roomFp, avatarFp, srcBlake3, embedding?)` |
| Mythos chain | `setMythosHead(palaceFp, mythosFp)`, `appendMythos(mythosFp, predecessorFp)` |
| Timeline + actions | `recordAction(action)`, `headHashes(palaceFp)`, `walkAncestors(actionFp)` |
| Aqueducts | `getOrCreateAqueduct(fromFp, toFp, kindDefault)`, `updateAqueductStrength(fp, nowMs)`, `aqueductsForRoom(roomFp)` |
| Oracle KG | `insertTriple(subjectFp, predicate, objectFp)`, `triplesFor(fp)`, `mythosChainTriples(palaceFp)` |
| Vector / K-NN | `upsertEmbedding(fp, v: Float32Array)`, `deleteEmbedding(fp)`, `kNN(v: Float32Array, k: number, filter?)` |
| Re-embedding | `reembed(fp, newBytes: Uint8Array, newVec: Float32Array)` — FR21's delete-then-insert in one transaction |
| Lifecycle | `open()`, `close()`, `syncfs(direction: 'in'|'out')` (browser-only; no-op on server) |
| Escape-hatch | `__rawQuery<T>(cypher, params)` — underscored name makes call-sites self-auditing |

**Why domain verbs**:

- TC12's swap-boundary promise only holds if callers stop writing
  Cypher. Raw passthrough would push Cypher strings into Epic C
  (`palace_inscribe.zig → TS bridge`), Epic D (oracle mirroring), and
  Epic F (K-NN) — three epics each of which could freeze query
  idioms that a future swap would have to reproduce.
- FR21's delete-then-insert invariant ("`DELETE … CREATE` is sole
  vector-write code path") is enforceable at the API surface, not at
  a coding-convention level — `reembed()` is the only way for any
  caller to mutate the vector index.
- FR26 aqueduct formulas live in `src/memory-palace/aqueduct.ts`
  (cross-epic coupling table). `getOrCreateAqueduct` + `updateAqueductStrength`
  compose cleanly with the formula module: the formulas compute
  values, the store persists them.
- The escape hatch (`__rawQuery`) absorbs one-off diagnostics and
  future work without breaking the boundary for the MVP surface.

**Why not raw Cypher passthrough**:

- Every call-site becomes a mini-schema-inventor. Risk R7 (FR26
  formula home cross-cutting) becomes a test discipline instead of a
  compile-time guarantee.
- A future swap (per the ADR quarterly-review gate) would have to
  re-implement every ad-hoc Cypher query. With verbs, the swap
  rewrites one file and every caller continues working.

**Why not pure domain verbs**:

- The oracle will want to run diagnostic queries the MVP cannot
  anticipate (`MATCH (r:Room)<-[:LIVES_IN]-(i:Inscription) WHERE …`).
  Hiding raw Cypher entirely forces a thrash of API-surface additions.
  Underscore-prefixed escape-hatch is the pragmatic middle.

### Alternatives considered

- **Raw Cypher passthrough** — rejected. Breaks TC12's swap-boundary
  promise in practice (Cypher strings become the boundary).
- **Pure domain verbs, no escape hatch** — rejected. Forces API
  additions for every diagnostic; drag on oracle development.
- **Auto-generated verbs from a Zig schema** — rejected. Zig
  codegen already generates `src/lib/generated/*.ts` types and
  Valibot schemas; adding a third generation path (store verbs) is
  premature. Revisit after MVP if verb count exceeds ~30.

### Aligned with existing pattern

Aligned with existing pattern: **`JellyBackend` interface in
`src/lib/backend/JellyBackend.ts`** — defines the typed verb surface
that both `MockBackend` and `HttpBackend` implement. `store.ts` is a
parallel abstraction for palace state; `JellyBackend` is already the
proof that this shape is ergonomic.

### Consequences

- **Epic B** gets a concrete API-first story (Story B1: define
  `StoreAPI` interface + server + browser adapters; subsequent
  stories implement each verb group).
- **Epic C** CLI work calls verbs via a thin TS bridge invoked from
  Zig; no Cypher in `src/cli/palace_*.zig`.
- **Epic D** oracle knowledge-graph mirroring uses `insertTriple` +
  `triplesFor` exclusively. No Cypher leaks.
- **Epic E** lens components use `aqueductsForRoom` and
  `kNearestInscriptions`, never raw Cypher.
- **Epic F** `jelly-server/src/routes/embed.ts` returns a vector; the
  CLI then calls `upsertEmbedding` through the store — embedder
  never touches the graph directly.
- **Constraint imposed**: every new Cypher query introduced during
  sprint-001 MUST land as a named verb in `store.ts`. If a story
  finds it needs raw Cypher in a hot-path (not diagnostic), escalate
  in `replan` — the verb surface is the boundary, not a bureaucratic
  hurdle.

---

## D-016: LadybugDB schema — node labels, relationship types, and "timeline as commit log"

- **Date**: 2026-04-21
- **Sprint**: sprint-001
- **Significance**: CRITICAL
- **Epics affected**: B (primary), C, D, F

### Context

FR19 requires Cypher `MATCH (:Palace)-[:CONTAINS]->(:Room)-[:CONTAINS]->
(:Inscription)` to work; FR5 requires `MATCH (:Palace {fp: $p})-[:
MYTHOS_HEAD]->(:Mythos)`; FR13 requires
`MATCH (:Inscription)-[:LIVES_IN]->(:Room)`. These dictate *some* of
the schema but leave open: where do `jelly.action` / `jelly.timeline`
entries live? How are Oracle/Agent nodes labeled? Where does
`jelly.archiform` live (attribute on other nodes vs. own node)?
What property keys does each node/edge carry? The schema shapes
every query that callers ever write.

### Decision

**Canonical Cypher schema for the palace graph:**

#### Node labels

| Label | Purpose | Mandatory properties | Optional properties |
|-------|---------|----------------------|---------------------|
| `Palace` | Field-kind=palace root | `fp: STRING` (PK), `format_version: INT`, `revision: INT`, `created_at: TIMESTAMP` | `archiform: STRING` |
| `Room` | Field-kind=room | `fp: STRING` (PK), `name: STRING`, `revision: INT` | `archiform: STRING`, `layout_fp: STRING` |
| `Inscription` | Avatar-with-inscription attribute | `fp: STRING` (PK), `source_blake3: STRING`, `surface: STRING`, `revision: INT`, `orphaned: BOOLEAN` default `false` | `archiform: STRING`, `placement_position: STRING` (CBOR-hex triple), `placement_facing: STRING` (CBOR-hex quat), `embedding: FLOAT[256]` |
| `Agent` | Agent DreamBall (oracle; future: other agents) | `fp: STRING` (PK), `revision: INT`, `is_oracle: BOOLEAN` | `archiform: STRING` |
| `Mythos` | Mythos attribute envelope | `fp: STRING` (PK), `is_genesis: BOOLEAN`, `body_hash: STRING` (Blake3 of body bytes, not body itself — avoids duplicating bytes held in CAS) | `true_name: STRING`, `form: STRING` |
| `Aqueduct` | Vril-carrying directed connection | `fp: STRING` (PK), `kind: STRING`, `resistance: FLOAT`, `capacitance: FLOAT`, `strength: FLOAT`, `conductance: FLOAT`, `phase: STRING`, `last_traversed: TIMESTAMP`, `revision: INT` | (none) |

#### Relationship types

| Type | From → To | Purpose | Properties |
|------|-----------|---------|------------|
| `CONTAINS` | `Palace|Room` → `Room|Inscription|Agent` | FR6/FR7/FR11 containment graph | `since: TIMESTAMP` |
| `MYTHOS_HEAD` | `Palace|Room|Inscription|Agent` → `Mythos` | FR5 current mythos head — exactly one per node that carries a mythos | `set_by_action_fp: STRING` |
| `PREDECESSOR` | `Mythos` → `Mythos` | FR2 append-only chain; null only for genesis | (none) |
| `DISCOVERED_IN` | `Mythos` → (action-fp string — no `Action` node; see below) | Logical pointer from canonical mythos extension to its `true-naming` action | stored as property `discovered_in_action_fp` on `Mythos`, **not** as a relationship |
| `LIVES_IN` | `Inscription` → `Room` | FR13 inscription triple | `since: TIMESTAMP` |
| `AQUEDUCT_FROM` | `Aqueduct` → `Room|Inscription|Agent` | Directed from-endpoint | (none) |
| `AQUEDUCT_TO` | `Aqueduct` → `Room|Inscription|Agent` | Directed to-endpoint | (none) |
| `KNOWS` | `Agent` → `Inscription|Room` | Oracle knowledge-graph triple fallout (FR13's `(doc-fp, lives-in, room-fp)` is already `LIVES_IN`; `KNOWS` is for cross-edges the oracle observes beyond inscription-living) | `predicate: STRING`, `since: TIMESTAMP` |

#### Timeline + actions: **commit-log table, not graph nodes**

`jelly.action` envelopes are **not** graph nodes. Instead:

```cypher
CREATE NODE TABLE ActionLog(
  fp STRING PRIMARY KEY,            -- Blake3 of canonical action bytes
  palace_fp STRING,
  action_kind STRING,
  actor_fp STRING,
  target_fp STRING,                 -- null if action has no target
  parent_hashes STRING[],            -- ACKS
  deps STRING[],                     -- optional logical deps
  nacks STRING[],                    -- optional invalidations
  timestamp TIMESTAMP,
  cbor_bytes_blake3 STRING           -- pointer back to CAS (TC13)
);
```

**Why a commit-log table, not nodes:**

- Timeline reads are overwhelmingly **walk-from-head** (`parent_hashes`
  resolution, linear ancestor chains), not graph-pattern queries.
  LadybugDB handles set-valued columns (`STRING[]`) natively; this is
  the correct idiom for "DAG stored as records."
- Actions do not form the same kind of queryable topology as rooms
  and aqueducts. Storing them as nodes would multiply the graph's node
  count by an order of magnitude (one per mutation), without adding
  queryable structure Epic D or E exploits.
- `DISCOVERED_IN` resolution becomes a single-column lookup, not a
  graph traversal: `MATCH (m:Mythos {fp:$fp}) RETURN m.discovered_in_action_fp`
  then `MATCH (a:ActionLog {fp:$actionFp}) RETURN a`.
- TC13 ("CAS source-of-truth; LadybugDB never holds CBOR bytes") is
  honoured: the `ActionLog` row is a pointer, not the envelope itself.

**Why Archiform is a property, not a node**:

- `jelly.archiform` is an attribute (OQ2 settled in requirements.md:
  "archiform is an attribute whose value is a small inline envelope,
  not a separately addressable DreamBall"). Storing it as a property
  keeps wire-spec alignment.
- FR27 seed archiform registry is a `jelly.asset` carried on the
  palace itself — one blob — so there's no need for 19 `Archiform`
  nodes. The registry is a CAS asset and a lookup table in code, not a
  graph subgraph.

**Why Mythos body is a hash, not the text**:

- TC13. Mythos body lives in CAS (the mythos envelope itself). The
  graph carries `body_hash` so the oracle can dedupe / detect changes
  without reproducing the text in LadybugDB.

### Alternatives considered

- **Actions as nodes with `PARENT_HASH` relationships** — rejected.
  Multiplies node count; walks become `MATCH (a:Action)-[:PARENT_HASH*]->(b:Action)`
  variable-length patterns, which are slower than column scans over
  a log table. Adds no queryable value.
- **Archiform as a separate node connected by `HAS_FORM`** — rejected.
  No queries in the MVP need "give me all rooms of form 'library'";
  if that becomes useful post-MVP, add an index on the property or
  promote to a node then. OQ2 settled archiform as an attribute.
- **Embedding stored in separate `Embedding` node related by
  `EMBEDS` edge** — rejected. LadybugDB vector extension operates on
  `ARRAY(FLOAT, N)` columns directly; separating the embedding into its
  own node forces a join on every K-NN result. Keeping it as a column
  on `Inscription` is the canonical pattern.
- **`Oracle` as a dedicated node label separate from `Agent`** —
  rejected. The oracle is a `jelly.dreamball.agent` (FR11); at the wire
  level it's a typical Agent. Use `Agent {is_oracle: true}` as a
  boolean flag; future non-oracle agents slot in cleanly.

### Aligned with existing pattern

Aligned with existing pattern: **`src/protocol_v2.zig` struct naming**
— every schema label mirrors a Zig struct field. `Palace.fp` is
`palace.fingerprint` in Zig; `Room.name` is `room.name`. Cross-runtime
invariant holds at the graph layer too.

Aligned with existing pattern: **Kuzu's LPG + Cypher idioms** as
validated in the v0.11.3 spike. No bespoke index machinery.

### Consequences

- **Epic B story 1 (after the vector-parity spike) creates the
  schema DDL** as `src/memory-palace/schema.cypher` (a single-file
  init script). `store.ts` executes it on `open()` if tables don't
  exist.
- **Epic D's oracle mirroring** writes to exactly three tables:
  `Inscription` rows (updated on `inscribe`/`move`), `LIVES_IN` edges
  (created on `inscribe`, re-pointed on `move`), and `Mythos` /
  `MYTHOS_HEAD` (managed via D-007 domain verbs).
- **Epic F's K-NN** query is:
  ```
  CALL QUERY_VECTOR_INDEX('inscription_emb', $q, $k)
  YIELD node AS i, distance
  MATCH (i:Inscription)-[:LIVES_IN]->(r:Room)
  RETURN i.fp, r.fp, distance
  ORDER BY distance;
  ```
  — single query, graph-join-on-vector-result works per A5.
- **Constraint imposed**: any new wire envelope introduced post-MVP
  that merits queryability gets a new node label; any that is a
  pure signed-record (like `jelly.action` is today) gets a commit-log
  table. This is the rule for future expansion.

---

# 2. Cross-Runtime Crypto

---

## D-010: WASM ML-DSA-87 verify validation path — minimal golden-fixture round-trip

- **Date**: 2026-04-21
- **Sprint**: sprint-001
- **Significance**: CRITICAL (if it fails, Epic A story 1 blocks entire sprint)
- **Epics affected**: A (primary), C, E, F

### Context

Risk R3 says: "WASM ML-DSA-87 verify assumed functional per CLAUDE.md
2026-04-21; no test evidence cited." TC5 says the budget has been
relaxed to 200 KB raw / 64 KB gzipped specifically to accommodate
ML-DSA-87 verify. Assumption A12 flags this as HIGH-risk validation
blocker: "if still stubbed, reopen known-gaps §1 for sprint-001
completion."

The Epic A story 1 spec calls this out as the sprint's first go/no-go
signal. The architectural question is: **what is the concrete test
shape that proves WASM ML-DSA-87 verify works?**

Three options:

1. **Existing fixture + WASM roundtrip.** Use a golden signature
   already in `src/ml_dsa.zig` tests, pipe it through the WASM
   module's verify export, expect `true`.
2. **New golden action fixture.** Mint a fresh `jelly.action` in Zig
   with ML-DSA-87 sig, serialize, verify in WASM. Requires the action
   envelope shape — not shipping until Epic A story 2.
3. **Full palace mint-and-verify in browser.** End-to-end via
   Playwright; palace envelope + timeline + oracle all PQ-verified.

### Decision

**Option 1 — existing fixture + WASM roundtrip, executed as Epic A
story 1's first acceptance criterion.**

Concrete shape:

```ts
// src/lib/wasm/verify.test.ts — new test block
import { describe, expect, it } from 'vitest';
import { verifyMlDsa87 } from './index.js';

// Fixture: re-use src/ml_dsa.zig test vector. The zig test already
// produces (public_key, message, signature) as hex strings; we copy
// those three constants into a test fixture file
// (fixtures/ml_dsa_87_golden.json) emitted by a new
// `zig build export-mldsa-fixture` step.

describe('ML-DSA-87 WASM verify', () => {
  it('accepts the golden signature', async () => {
    const fx = await loadFixture('ml_dsa_87_golden.json');
    const ok = await verifyMlDsa87(fx.pk, fx.msg, fx.sig);
    expect(ok).toBe(true);
  });

  it('rejects a one-bit-flipped signature', async () => {
    const fx = await loadFixture('ml_dsa_87_golden.json');
    const bad = flipBit(fx.sig, 0);
    const ok = await verifyMlDsa87(fx.pk, fx.msg, bad);
    expect(ok).toBe(false);
  });

  it('rejects a one-bit-flipped message', async () => {
    const fx = await loadFixture('ml_dsa_87_golden.json');
    const bad = flipBit(fx.msg, 0);
    const ok = await verifyMlDsa87(fx.pk, fx.msg, fx.sig);
    expect(ok).toBe(true);        // sanity — unchanged inputs still pass
    const ok2 = await verifyMlDsa87(fx.pk, bad, fx.sig);
    expect(ok2).toBe(false);
  });
});
```

**Why option 1:**

- It's the smallest increment that resolves R3 definitively.
  Signature bytes → verify call → boolean. No wire format, no
  envelope plumbing, no browser rendering — just the cryptographic
  primitive. If this fails, everything downstream is already blocked.
- It's mechanically reusable: the same fixture feeds Epic A story 2
  (envelope round-trip) and Epic C story 2 (palace mint verify).
- It runs in `bun run test:unit -- --run`, which is already a build
  gate (NFR17). R3 resolution is tied to the existing green-on-commit
  contract.

**Spike success gate (explicit):**

1. All three test cases above pass in Chromium (Playwright) and in
   Node (Vitest headless).
2. `jelly.wasm` is ≤200 KB raw and ≤64 KB gzipped (TC5). If verify
   works but the budget is blown, **this is a known-gaps §1 regression
   and blocks Epic A story 1 acceptance.**
3. The `env.getRandomBytes` import is the only host import
   (cross-runtime invariant).

**Fallback path (documented but not pre-executed):** If any of the
three tests fails, fall back to "ML-DSA-87 signing via server
subprocess; WASM verify path remains a known gap; NFR12 dual-sig
browser verify is degraded to Ed25519-only." This is NOT a sprint-001
acceptable outcome for CRITICAL epics (A, C); it's a Growth-tier
degradation. If triggered, convene `/oh-my-claudecode:planner --replan`
before any of Epic A stories 2+ start.

### Alternatives considered

- **Option 2 — new golden action fixture.** Rejected: the action
  envelope isn't implemented until Epic A story 2, so story 1 can't
  produce one. Would tightly couple R3 resolution with wire-format
  delivery. Story 2 already asserts round-trip via golden fixtures
  (NFR16, NFR18); the WASM verify layer below it needs to be green
  first.
- **Option 3 — full palace mint-and-verify in browser.** Rejected
  for story 1: pulls in Epics B, C, D, E dependencies to exercise
  one crypto primitive. Useful for Phase 5 end-to-end validation;
  not the right shape for the R3 go/no-go gate.
- **Skip validation; trust CLAUDE.md update.** Rejected per R3
  mitigation. The CLAUDE.md entry is a *claim* of functionality, not
  *evidence* — A12 flags this.

### Aligned with existing pattern

Aligned with existing pattern: **`src/lib/wasm/verify.test.ts`
already exists** per discovery.md Svelte lib inventory. Extend
the existing file; the pattern of "test each WASM export with
happy-path + one bit flip" is already the idiom.

Aligned with existing pattern: **`src/ml_dsa.zig` test blocks**
produce known-answer test vectors; a new `zig build export-mldsa-fixture`
step serializes one to JSON.

### Consequences

- **Epic A story 1 acceptance criterion added:** test block in
  `src/lib/wasm/verify.test.ts` green; `jelly.wasm` stat-checked ≤
  200 KB raw / 64 KB gzipped.
- **Epic A story 2 gated on story 1 passing.** If story 1 fails,
  `/replan` is invoked before any other epic starts.
- **Known-gaps.md §1 closure deferred** until R3 passes — the
  entry is removed from `docs/known-gaps.md` in the same commit as
  story 1's merge.
- **Constraint imposed**: no other epic's acceptance depends on WASM
  ML-DSA-87 **until Epic A story 1 is green.** If the test fails,
  Epic C, D, E, F stories that signed actions land as Ed25519-only
  temporarily and are patched on story 1 resolution — but this is
  the escape path, not the plan.

---

# 3. Transactional Integrity

---

## D-008: File-watcher transactional boundary — inline, synchronous with signed action

- **Date**: 2026-04-21
- **Sprint**: sprint-001
- **Significance**: HIGH
- **Epics affected**: D (primary), B, F

### Context

FR14 promotes the oracle file-watcher to MVP (D-001). Risk R6 flags
"FR14 spans three epics (D owns, B mutates store, F re-embeds)" and
mitigation calls for "call B and F primitives in this order within
one signed-action transaction; fault-inject test."

Assumption A7 asserts oracle-knowledge-graph mirroring is synchronous
within each signed-action transaction. The question: **does the
file-watcher honour A7, or does it queue asynchronously and catch
up?**

Two architectures:

1. **Inline synchronous.** File-watcher handler executes:
   `(a)` compute new content hash, `(b)` bump Avatar revision and
   re-sign, `(c)` emit `"inscription-updated"` `jelly.action`,
   `(d)` call `store.reembed(fp, newBytes, newVec)` — all under one
   transaction. Any failure rolls back to pre-change state; the
   `jelly.action` is only committed if all of (a)–(d) succeed.
2. **Async queue.** File-watcher enqueues a change event; a worker
   drains the queue, performs (a)–(d) asynchronously; the `jelly.action`
   lands eventually. The user's 2-second SLA is softer; fault
   tolerance is easier.

### Decision

**Option 1 — inline synchronous. File-watcher holds a mutex during
the four-step sequence and rolls back on any failure.**

Concrete shape:

```ts
// src/memory-palace/file-watcher.ts (new; Epic D)
import { acquirePalaceMutex } from './store.js';
import { reembed } from './store.js';
import { emitAction } from './timeline.js';
import { computeEmbedding } from './embedding-client.js';

async function onFileChange(avatarFp: Fp, newPath: string): Promise<void> {
  const release = await acquirePalaceMutex(avatarFp);
  try {
    const newBytes = await readFile(newPath);
    const newBlake = await blake3(newBytes);
    if (newBlake === store.getInscription(avatarFp).sourceBlake3) {
      return; // no-op; FR21 spy on embedder asserts zero calls
    }
    const newVec = await computeEmbedding(newBytes);
    const updatedEnvelope = await zig.bumpAvatarRevision(avatarFp, newBlake);
    const action = await zig.signAction({
      kind: 'inscription-updated',
      targetFp: avatarFp,
      parentHashes: await store.headHashes(palaceFp),
    });
    // Atomic:
    await store.transaction(async (tx) => {
      await tx.reembed(avatarFp, newBytes, newVec);
      await tx.recordAction(action);
      await tx.updateInscription(avatarFp, { sourceBlake3: newBlake });
    });
  } finally {
    release();
  }
}
```

**Why inline synchronous:**

- **FR14 acceptance criterion is 2 seconds.** Queued-async defers
  the 2-second clock onto a queue-drain scheduler — any back-pressure
  pushes past the budget. Inline sync either hits the budget or
  fails cleanly.
- **A7 explicitly says "synchronous within each signed-action
  transaction."** Queued-async breaks this assumption and would
  force a phase-state revision.
- **FR21 "delete-then-insert within a single transaction" is
  precisely the shape.** Queued-async would require a compensating
  transaction if the re-embedding succeeds but the action signing
  fails — additional failure modes, additional invariant checks.
- **Fault-injection test (R6 mitigation) becomes tractable:** inject
  a failure at each step (file-read, embed-call, sign, store-write),
  assert the palace state is identical to pre-change. With async,
  the fault surface is a queue + worker lifecycle and the test
  matrix explodes.

**Fault scenarios and expected behaviour:**

| Injected failure | Expected behaviour | Acceptance |
|------------------|--------------------|------------|
| File unreadable | Action not emitted; avatar unchanged; log warning | `head-hashes` unchanged; `jelly verify` passes |
| Embed server down | Action not emitted; avatar unchanged; user error "embedding service unreachable" (NFR11 allows) | Same as above |
| ML-DSA sign fails | Action not emitted; avatar unchanged; log error | Same as above |
| Store write fails mid-transaction | Transaction rollback; avatar unchanged | Verified by replay from CAS |
| File deleted (orphan case) | Separate path: emit `"inscription-orphaned"` action, mark `orphaned=true` on Inscription node, do NOT re-embed | FR14 acceptance: renderer shows dimmed |

**Throughput consideration:** The mutex is per-palace-fp, not global.
Multiple palaces open in multiple tabs/processes can watch files
independently. Within a single palace, a burst of file changes
serializes — acceptable for MVP (author is typing; not a
high-concurrency write workload).

### Alternatives considered

- **Queued async with eventual consistency.** Rejected. Breaks A7,
  complicates rollback, expands fault matrix. Consider post-MVP if
  profiling shows inline path blocks UI during large-file saves.
- **Inline sync with per-field optimistic concurrency (no mutex).**
  Rejected. Adds retry loop + stale-read recovery machinery for a
  workload that doesn't benefit. Mutex is simpler and correct.
- **Coarse-grained global mutex.** Rejected. Would serialize all
  palaces across a single Bun process; jelly-server hosts multiple,
  breaks demo throughput.

### Aligned with existing pattern

Aligned with existing pattern: **Zig `src/signer.zig` sign-then-emit
sequence** in `src/cli/mint.zig` and `grow.zig` — both use a linear,
fail-early shape. The file-watcher extends this to the oracle side
without inventing a new concurrency model.

Aligned with existing pattern: **LadybugDB's transaction API** —
the store wrapper D-007 exposes `transaction(async (tx) => …)`
directly.

### Consequences

- **Epic D story for file-watcher** includes the fault-injection
  test matrix above as an acceptance criterion.
- **Epic B store API** MUST expose `transaction<T>(fn: (tx) => Promise<T>):
  Promise<T>` with rollback on throw. D-007 domain verbs are available on the
  `tx` handle.
- **Epic F embedding client** MUST expose a synchronous-to-caller
  `computeEmbedding(bytes): Promise<Float32Array>` that either
  resolves with a vector or rejects with a clear error (no partial
  success, no swallowed network failure).
- **NFR10 latency unaffected.** File-watcher runs off the render
  path; 2-second budget is generous.
- **Constraint imposed**: file-watcher is the only MVP background
  process. Any future "fire and forget" work introduced in later
  sprints MUST be argued against this pattern; silent async queues
  are the default-no for palace state changes.

---

# 4. Rendering

---

## D-009: Shader spike scope — aqueduct-flow end-to-end on one live traversal

- **Date**: 2026-04-21
- **Sprint**: sprint-001
- **Significance**: HIGH
- **Epics affected**: E (primary)

### Context

Risk R4: "Threlte custom-shader work is new territory; NFR10 latency
budget aggressive" — mitigation is "Epic E story 1 is shader spike
(aqueduct-flow end-to-end) before committing to other three; replan
if budget breaks." NFR14 names four materials: `aqueduct-flow`,
`room-pulse`, `mythos-lantern` stub, `dust-cobweb`. The question:
**what counts as "spike success" concretely?**

Three gate shapes:

1. **aqueduct-flow shader on one live traversal.** One signed
   aqueduct, one traversal event, particles flow along the path;
   `conductance` uniform live from the store; `freshness` uniform
   live from renderer-local clock.
2. **All four materials rendering static.** All four shaders compile,
   apply to placeholder geometry, no live data binding. Early
   integration signal; weak aesthetic signal.
3. **aqueduct-flow + room-pulse.** Both flow and pulse live; covers
   two of the four, leaves stubs for the other two.

### Decision

**Option 1 — aqueduct-flow shader on one live traversal. The spike
succeeds iff all of the following are demonstrably true in Storybook:**

1. **Storybook scene**: one palace fixture (`mockBall('palace')`
   extended with one room, two inscriptions, one aqueduct between
   them) renders via `PalaceLens.svelte` → `RoomLens.svelte`.
2. **Particle flow**: the aqueduct is drawn with the `aqueduct-flow`
   Threlte material; particles move from `from → to`.
3. **Conductance-speed link**: particle velocity is proportional to
   the `conductance` uniform, sourced from the aqueduct envelope.
   Changing the fixture's conductance from 0.2 → 0.8 visibly speeds
   the flow (recorded as a Playwright screenshot diff or story play
   assertion).
4. **Freshness-dim link**: mocking `last_traversed` to 60 days ago
   visibly dims the flow to the freshness floor; mocking it to "now"
   restores full brightness. Freshness uniform is a pure function of
   `now - last_traversed` per TC17 + ADR 2026-04-21-vril-flow-model.md.
5. **Latency**: first particle render completes within 200 ms of
   lens mount (measured via Storybook performance capture; NFR10 is
   2 s for the full palace, so 200 ms for one aqueduct is generous).
6. **Fallback**: WebGPU opt-in path is verified to fall back to WebGL
   cleanly (TC4). If WebGPU unavailable, the WebGL path runs the
   same shader.

**Gate decision after story 1:**

- **All 6 pass** → commit to `room-pulse`, `mythos-lantern` stub,
  `dust-cobweb` in stories 2–4. Ship NFR14's full pack.
- **aqueduct-flow passes but 2+ link fails** → convene `/replan`.
  Option: ship aqueduct-flow + 3 simpler materials (no
  `mythos-lantern` live parameterisation; `dust-cobweb` as a 2D
  overlay instead of shader).
- **aqueduct-flow does not compile or renders blank** → HARD BLOCK.
  Replan the rendering epic; consider deferring custom shader work
  to sprint-002 and shipping MVP with instanced-line aqueducts
  (Three.js `Line2` + per-vertex colour ramp) as a non-shader
  fallback.

**Why option 1:**

- It's the **minimum cut that exercises every new concern**: custom
  GLSL, uniform binding to store data, renderer-local clock for
  freshness, Threlte custom-material integration, fallback path. If
  it works, each subsequent material is a smaller incremental piece
  of the same machine. If it fails, we know exactly which layer to
  push on.
- It honours the ADR's rendering contract — freshness lives in the
  renderer, not on the wire. The spike is the first place that
  contract is enforced in code.
- NFR10 ("open palace of 500 rooms × 50 inscriptions in <2 s") is
  about aggregate, not one aqueduct. Story 1's 200 ms budget for
  one aqueduct is a conservative leading indicator.

**Why not option 2 (all four static):**

- Four blank-geometry shaders say nothing about whether live data
  binds correctly. The risk is data-flow + freshness computation,
  not shader compilation.
- Creates four low-quality materials that each need rework before
  shipping — negative work.

**Why not option 3 (flow + pulse):**

- Doubles story 1's scope. If `aqueduct-flow` fails, doing pulse
  alongside just doubles the diagnostic surface. Prefer one shader
  thoroughly exercised.

### Alternatives considered

- Listed above.
- **Skip spike; build all four in parallel.** Rejected. R4 is
  explicitly labelled HIGH.
- **Spike as a bare Three.js prototype outside Threlte.** Rejected.
  The Threlte integration IS part of the risk — skipping it
  sidesteps the question.

### Aligned with existing pattern

Aligned with existing pattern: **existing lens Storybook stories**
(`omnispherical`, `cylindrical`, etc.) — story 1's aqueduct-flow
fixture follows the same fixture-loading convention. Non-palace
lenses are untouched.

Aligned with existing pattern: **`bun run build-storybook` CI gate
(NFR17)** — story 1's scene runs on every commit automatically.

### Consequences

- **Epic E story 1 scope nailed to the six checkboxes above.** No
  other lens work ships in story 1.
- **Epic E stories 2–4 gated on story 1 PASS.** Replan on partial
  pass.
- **Shader library structure**: `src/lib/shaders/aqueduct-flow.glsl`
  is the first file under a new `shaders/` subdir. Story 1 establishes
  the convention (shader file + Svelte material wrapper + Threlte
  integration + fixture).
- **Constraint imposed**: no epic other than E (story 1 only) depends
  on the shader pack being complete. Epic E stories 2–4 are
  independently releasable; so are lens components that don't use
  these materials (PalaceLens, RoomLens, InscriptionLens basic
  geometry).

### Revision 2026-04-24 — version pin + per-shader micro-spike

Per web3d-space sprint-004-logavatar retrospective (the
"compass-not-map" learning): research-backed decisions that cite library
internals are only valid against a pinned library version. D-002 in
that sprint cited PlayCanvas 2.13–2.16's `gsplat-manager.js`, but
node_modules shipped 2.17 with a fully-rewritten pipeline; the
mismatch cost ~2 days before a spike surfaced it.

Two concrete amendments to D-009:

1. **Pin the library versions S5.1's spike validates against.** Story
   5.1 MUST record in its success report: `three@<version>`,
   `threlte@<version>`, `svelte@<version>` as resolved in the
   committed `bun.lock` at the time of spike PASS. If a major version
   of any of these three bumps before S5.5, the spike is re-run.

2. **Per-shader micro-spikes for S5.5.** Stories S5.5's three remaining
   shaders (`room-pulse`, `dust-cobweb`, `mythos-lantern` stub) each
   get a ≤60-minute micro-spike inside a single dedicated Storybook
   scene, proving one compile + one live-uniform binding before the
   shader promotes into its production lens. Spikes are kept (not
   deleted) under `src/lib/stories/spikes/` as reference
   implementations, matching sprint-004-logavatar's
   `/spike/splat-{anim,perframe,lbs}` pattern.

Neither amendment changes S5.1's six-checkbox shape — both tighten
downstream story risk.

### Revision 2026-04-24 — renderer-agnostic structure (Epic 5 deep-dive)

During Epic 5 `/refine --epic=5` deep-dive, three cross-cutting
decisions were pulled out into standalone ADRs so Epic 5 stays focused
on the sprint-001 Web engine while the protocol reserves composability
with future rendering engines (Unreal, Blender, MR/VR):

- [2026-04-24 surface registry](../../decisions/2026-04-24-surface-registry.md)
  — formalizes `Inscription.surface` as open string + optional
  `fallback` chain + per-lens registry. Amends S5.4 AC2 (see
  epic-5.md).
- [2026-04-24 renderer compositing](../../decisions/2026-04-24-renderer-compositing.md)
  — sprint-001 ships Strategy A (same-pass), pre-commits Strategy C
  (multi-canvas CSS) for the follow-up splat path. No S5 code change;
  prevents mid-sprint wall when splats land.
- [2026-04-24 coord frames](../../decisions/2026-04-24-coord-frames.md)
  — polar at the field layer (`omnispherical-grid`), cartesian at the
  placement layer (`layout.placement.position`), nested reference
  frames composed as cached world matrices. Affirms §12.2 and §13.2
  already carry the right shape.

See also [`docs/prd-rendering-engines.md`](../../prd-rendering-engines.md)
for the integrating narrative across all three.

---

# 5. Security & Custody

---

## D-011: Oracle secret-key custody — plaintext `.key` file, 0600 permissions, MVP compromise

- **Date**: 2026-04-21
- **Sprint**: sprint-001
- **Significance**: MEDIUM (MVP compromise accepted; SEC10 already documents as follow-up gap)
- **Epics affected**: C (mint writes key file), D (oracle reads key file)

### Context

D-005 mandates a separate hybrid keypair for the oracle, stored in a
sibling `.key` file. FR11 codifies "oracle's signature verifies under
its own keypair, not the custodian's." SEC10 explicitly documents
"Oracle's secret key custody is a sprint-001 compromise — local `.key`
file alongside palace's. Follow-up gap: recrypt wallet format (DCYW
shell + Argon2id + XChaCha20-Poly1305 per known-gaps §6)."

Three concrete MVP shapes:

1. **Plaintext `.key` file, `0600` permissions.** Simplest; uses
   existing `src/key_file.zig` format as-is; relies on OS permission
   model.
2. **Argon2id-wrapped, passphrase at mint-time.** User supplies a
   passphrase at `jelly mint --type=palace`; oracle key wrapped with
   Argon2id-derived key. File on disk is encrypted.
3. **Env-var passphrase.** Wrap key with a passphrase supplied via
   `JELLY_ORACLE_PASSPHRASE` env-var at CLI invocation. File on disk
   encrypted; unwrap at each oracle operation.

### Decision

**Option 1 — plaintext `.key` file with `0600` permissions, MVP
compromise. Every oracle key-touching call-site carries
`TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet
DCYW shell post-MVP (known-gaps §6).`**

Concrete shape:

- Mint-time: `jelly palace mint` generates oracle hybrid keypair,
  writes to `{palace-path}.oracle.key` using the same format as
  `src/key_file.zig` today (whatever it is for the palace key).
  Explicit `chmod 0600` after write.
- On-disk: identical format to the palace's own `.key` file. Two
  files on disk, unrelated content, same permissions.
- Read-time: `src/memory-palace/oracle.ts` invokes a Zig-compiled
  function (`oracleSignAction`) that reads the `.key` file on demand.
  No caching in long-lived memory beyond the immediate syscall scope.
- Markers: every read site in Zig and TS carries
  `// TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6).`

**Why option 1:**

- **SEC10 explicitly documents this compromise as acceptable for
  MVP.** The follow-up path (recrypt wallet) is already planned.
- **MVP velocity matters.** Argon2id-wrapped keys introduce a
  passphrase-entry UX flow we have no time to design, no existing
  component for, and that complicates the file-watcher
  (`JELLY_ORACLE_PASSPHRASE` env-var for long-running daemons is
  itself a credential-leak risk — Docker layer inspection, systemd
  env dumps, process-list visibility).
- **The existing `src/key_file.zig`** pattern is already in use for
  the palace key. Consistency with the existing idiom keeps the
  surface small. When recrypt wallet integration lands, both keys
  migrate together.
- **NFR15 marker discipline** ensures no silent upgrade: every
  call-site carries the `TODO-CRYPTO` that will be removed when
  DCYW lands.

**Why not option 2 (Argon2id-wrapped):**

- Adds passphrase-entry UX (CLI prompt + CI-friendly flag + Storybook
  mock + file-watcher handling). Each of those is a story in its own
  right, pulling MVP scope.
- Partial coverage: protects against stolen-disk attacks but not
  runtime-memory or process-inspection attacks. MVP threat model (SEC6:
  "no palace state emitted over network") is disk-plus-OS; encrypted
  at-rest adds little.
- Argon2id is not in `src/ml_dsa.zig` or `src/signer.zig` today —
  pulls a new crypto dep in for a non-critical-path concern.

**Why not option 3 (env-var passphrase):**

- Env-vars leak easily (process listings, Docker metadata, CI logs,
  systemd environment). For a local-first tool this is worse than
  `0600` on disk.
- Makes the file-watcher (D-008) weird: long-running daemon needs
  the passphrase resident in memory indefinitely.

### Alternatives considered

- Options 2 + 3 above.
- **Derive oracle key from palace key (HKDF).** Rejected. Violates
  D-005 ("separate hybrid keypair") — they'd be cryptographically
  linked, not independent. Defeats the principle that oracle-signed
  actions are distinguishable from custodian-signed actions.
- **Use macOS Keychain / Windows Credential Manager / etc.**
  Rejected. Platform-specific, breaks CLI portability, out of scope
  for MVP.

### Aligned with existing pattern

Aligned with existing pattern: **`src/key_file.zig` + the palace's
own `.key` file** — the oracle's key file is a literal copy of the
pattern. No new format, no new loader, no new permissions dance.

Diverges from existing pattern: **none** — this IS the existing
pattern.

### Consequences

- **Epic C `palace_mint.zig`** generates + writes two hybrid
  keypairs, not one.
- **Epic D `oracle.ts`** knows to read `{palacePath}.oracle.key`
  (sibling naming convention) when preparing to sign.
- **`jelly verify` palace invariants (FR24)** extends to check:
  oracle actions' `actor` fp matches oracle fp (which itself matches
  what the sibling `.key` file derives). Stripping the `.key` file
  means actions can still be verified (signatures are self-contained)
  but new oracle actions can't be emitted.
- **known-gaps.md** gains an entry (or updates the existing §6) with
  explicit reference to sprint-001 as the sprint that deferred the
  wrap. When the recrypt-wallet-wrap work lands in a future sprint,
  all `TODO-CRYPTO: oracle key is plaintext` markers are removed in
  the same commit.
- **Constraint imposed**: any commit that touches the oracle key
  read/write path MUST either keep the marker or remove it as part of
  the wrap work — no silent upgrade.

---

# 6. Service Surfaces

---

## D-012: Embedding endpoint wire shape — single POST, no batch, no streaming

- **Date**: 2026-04-21
- **Sprint**: sprint-001
- **Significance**: MEDIUM
- **Epics affected**: F (primary), B (store consumes result), D (file-watcher consumes via B)

### Context

FR20 requires jelly-server to host a Qwen3-Embedding-0.6B endpoint
returning 256d MRL-truncated vectors. D-002 locks the model choice.
The question: **what is the HTTP schema?**

Three options:

1. **Single POST /embed** → one content, one vector.
2. **Batch endpoint** → array-in, array-out.
3. **Streaming endpoint** (WebSocket or SSE) → push content, stream
   vectors as they're computed.

### Decision

**Option 1 — single POST /embed, one content in, one vector out.**

Concrete shape (Elysia route):

```ts
// jelly-server/src/routes/embed.ts (new)
import { Elysia, t } from 'elysia';

export const embed = new Elysia({ prefix: '/embed' })
  .post(
    '/',
    async ({ body }) => {
      const vec = await qwen3Embed(body.content, body.contentType);
      return {
        vector: Array.from(vec),
        model: 'qwen3-embedding-0.6b',
        dimension: 256,
        truncation: 'mrl-256',
      };
    },
    {
      body: t.Object({
        content: t.String({ minLength: 1, maxLength: 1_048_576 }),  // 1 MB
        contentType: t.Union([
          t.Literal('text/markdown'),
          t.Literal('text/plain'),
          t.Literal('text/asciidoc'),
        ]),
      }),
      response: t.Object({
        vector: t.Array(t.Number(), { minItems: 256, maxItems: 256 }),
        model: t.Literal('qwen3-embedding-0.6b'),
        dimension: t.Literal(256),
        truncation: t.Literal('mrl-256'),
      }),
    },
  );
```

**Why option 1:**

- **MVP ingestion is one-at-a-time.** `jelly palace inscribe`
  processes one file; file-watcher processes one change event. Batch
  offers no throughput gain for the current call pattern.
- **`jelly palace inscribe` is CLI-blocking.** A single synchronous
  HTTP call matches the CLI's "succeed or fail cleanly" idiom. Batch
  + partial-failure handling = new error paths.
- **File-watcher latency budget is 2 seconds per change.** Single
  POST easily fits; batch would require coalescing events with a
  debounce window, adding UX surprise ("why didn't my edit register
  right away?").
- **Response echoes model/dimension/truncation** so the caller can
  sanity-check before `store.upsertEmbedding`. Also future-proofs
  the `store.ts` side: if D-002 is ever revised, callers can reject
  stale vectors gracefully.
- **Content-type whitelist is narrow on purpose.** Widens in a later
  sprint when non-text inscriptions (image, audio) land; MVP only
  inscribes text surfaces per FR17.

**Why not option 2 (batch):**

- No caller wants batch in MVP. Adds partial-failure semantics and
  an order-preservation contract the callers don't need.
- If post-MVP profiling shows throughput pressure (e.g., bulk
  inscribe of 1000 docs), add POST /embed/batch as a non-breaking
  additive endpoint. Don't pre-optimize.

**Why not option 3 (streaming):**

- Qwen3-Embedding-0.6B is a compute-once-per-document model — there's
  no per-token streaming signal to surface. Streaming adds
  infrastructure cost (WS/SSE handling, client-side reassembly) for
  zero user-visible benefit.

**Sanctioned exit gating (per NFR11, SEC6):**

- The endpoint is invoked only by a `jelly palace inscribe` or
  `file-watcher → store.reembed` call-path, both of which are
  explicit user actions (D-001 + NFR13).
- `--embed-via <url>` CLI flag (per NFR13) overrides the default
  `http://localhost:9808/embed` to point at a user-supplied URL.
  Default MVP: jelly-server at localhost.
- Server-unreachable behaviour (FR20 acceptance): `fetch` throws →
  CLI exits with "embedding service unreachable — palace otherwise
  operational (NFR11 sanctioned exit)".

### Alternatives considered

- Options 2 + 3.
- **gRPC instead of HTTP.** Rejected. jelly-server stack is Elysia +
  Eden; no gRPC anywhere. Would pull in protoc + codegen for one
  route.
- **Return raw `Float32Array` bytes instead of JSON.** Rejected for
  MVP. JSON's 256-float overhead is ~3 KB — tolerable at MVP
  throughput; simplifies debugging with `curl | jq`.

### Aligned with existing pattern

Aligned with existing pattern: **existing Elysia routes in
`jelly-server/src/routes/`** — mint, grow, seal-relic, etc., all
use Elysia's `.post()` with `t.Object()` body/response validation.
`/embed` is a direct copy of the idiom.

Aligned with existing pattern: **Eden type-safe client** — Svelte lib
+ Zig CLI can both consume the endpoint through the generated Eden
client without schema drift.

### Consequences

- **Epic F story 1** implements `jelly-server/src/routes/embed.ts`
  with a mocked Qwen3 runner (ONNX or TGI-client) for spike; story 2
  connects the real model.
- **Store wrapper D-007** gains a `store.upsertEmbedding(fp,
  Float32Array)` verb; caller supplies the vector, store writes the
  column.
- **CLI flag `--embed-via <url>`** on `jelly palace inscribe`
  defaults to `http://localhost:9808/embed` and accepts any URL
  (including external services per D-002's "user-brought model"
  note).
- **Constraint imposed**: the `/embed` route is the only sanctioned
  network exit for ingestion (SEC6). Any other route that emits
  palace content over the wire requires its own explicit ADR +
  `TODO-EMBEDDING` or `TODO-EXIT` marker.

---

## D-015: Cross-runtime vector-extension parity — identical Cypher, ordinal top-K with ≤10% variance

- **Date**: 2026-04-21
- **Sprint**: sprint-001
- **Significance**: HIGH
- **Epics affected**: B (primary — Epic B story 1 is the parity spike), F

### Context

Risk R2: "LadybugDB vector-extension graph-join parity across
runtimes unverified. Mitigation: run identical K-NN fixture on both
runtimes as Epic B story 1." Assumption A5 echoes: "if browser
lacks, server-only vector path (breaks NFR11 offline locally — known
follow-up)." FR20 acceptance: "K-NN Cypher …YIELD… returns the
inscribed document for a related prompt."

The kuzu-wasm@0.11.3 IDBFS path is proven (ADR step 2b). What is NOT
proven: whether the bundled vector extension works **identically** on
`@ladybugdb/core` (native, Rust) and `kuzu-wasm@0.11.3` (WASM,
v0.11.3's vector extension). Three acceptance shapes:

1. **Byte-identical top-K.** Same fixture, same query, identical
   vector bytes in identical row order.
2. **Ordinal top-K with ≤10% variance.** Same fixture, same query,
   top-K results are the same **set** (order may vary within
   epsilon; per-item distance may vary by ≤10%).
3. **Server-side fallback if browser lacks.** Browser always queries
   server over HTTP; drops NFR11 offline commitment for K-NN only.

### Decision

**Option 2 — ordinal top-K with ≤10% variance. Acceptance contract
for Epic B story 1 parity spike:**

Concrete shape (Epic B story 1 / "vector parity spike"):

1. **Fixture**: 100 deterministically-generated 256d vectors (seed
   = 42, uniform random in [-1, 1], unit-normalized). Plus one
   query vector (seed = 43).
2. **Both runtimes**: load fixture into `Inscription.embedding`
   column, run
   ```cypher
   CALL QUERY_VECTOR_INDEX('inscription_emb', $q, 10)
   YIELD node, distance
   RETURN node.fp, distance
   ORDER BY distance;
   ```
3. **Acceptance**:
   - **Server result set** (from `@ladybugdb/core`) is ground truth.
   - **Browser result set** (from `kuzu-wasm@0.11.3`) must contain
     the same **10 fp values** (set equality; order not required).
   - Per-item cosine distance must agree within **|Δ| ≤ 0.1** (since
     vectors are unit-norm in [-1,1], distances are in [0, 2]; 0.1
     is ~5% of the range).
4. **If set inequality occurs** (one runtime returns a different
   document): HARD BLOCK. Replan to server-only vector path (Option
   3 below). NFR11 gains a documented relaxation for K-NN queries.
5. **If |Δ| > 0.1** but set equality holds: WARN + document in ADR
   addendum. Ship; file upstream at LadybugDB issue tracker.

**Why option 2:**

- **Byte-identical is too strict.** LadybugDB's vector extension
  uses `simsimd` SIMD on the server; kuzu-wasm uses scalar / SSE
  approximations. Float-level differences are expected; set-level
  differences are not.
- **Fallback (option 3) is a degradation**, not an acceptance —
  invoke only if option 2 fails.
- **FR20 acceptance ("returns the inscribed document for a related
  prompt") is a set-membership claim**, not a byte-level one. Option 2
  matches the user-facing contract.
- **MVP K-NN queries are always top-10 at most.** A 10% distance
  variance at k=10 does not change the oracle's "which inscriptions
  are relevant?" answer in any user-visible way (the oracle gets
  10 inscriptions either way).

**Test shape (story 1 of Epic B):**

```ts
// src/memory-palace/parity.test.ts (new; runs on both runtimes via Vitest
// + Playwright config split)
describe.each(['server', 'browser'])('K-NN parity on %s', (runtime) => {
  it('top-10 is a subset equality to the server ground-truth', async () => {
    const fixture = generateFixture(100, 256, 42);
    const query = generateQueryVector(256, 43);
    const store = await openStore(runtime);
    for (const row of fixture) await store.upsertEmbedding(row.fp, row.vec);
    const results = await store.kNN(query, 10);
    if (runtime === 'server') {
      globalThis.__serverGroundTruth = results;
    } else {
      const serverFps = new Set(globalThis.__serverGroundTruth.map(r => r.fp));
      const browserFps = new Set(results.map(r => r.fp));
      expect(browserFps).toEqual(serverFps);
      for (const br of results) {
        const sr = globalThis.__serverGroundTruth.find(r => r.fp === br.fp);
        expect(Math.abs(br.distance - sr.distance)).toBeLessThanOrEqual(0.1);
      }
    }
  });
});
```

### Alternatives considered

- Options 1 + 3 above.
- **Server-only vector path as default; browser delegates.** Rejected
  for MVP default. NFR11 is load-bearing for offline operation. If
  option 2 passes, we preserve local-first K-NN. Only fall back on
  failure.

### Aligned with existing pattern

Aligned with existing pattern: **`tests/e2e-cryptography.sh` parity
tests** between Zig CLI and WASM — same test idiom: "same fixture,
two runtimes, assert equivalence." Crypto parity ≡ vector parity.

Diverges from existing pattern: **none**. Extending a proven testing
approach.

### Consequences

- **Epic B story 1 is the parity spike.** If it fails, Epic B
  stories 2+ are replanned.
- **Epic F** assumes server-side K-NN works (already validated);
  its browser consumption path depends on Epic B story 1 passing.
- **Oracle (Epic D)** reads K-NN through `store.kNN` — unaffected
  by the runtime split; D-007 store verb hides the divergence.
- **If option 3 fallback triggered**: NFR11 gains a documented
  K-NN-only relaxation; `store.kNN` in browser delegates to jelly-server
  via an additional HTTP route. This is the planned replan path,
  not a sprint-001 failure — but it IS a scope impact (Epic F gets a
  `/kNN` endpoint, not just `/embed`).
- **Constraint imposed**: no Epic story depends on byte-identical
  vectors across runtimes. All K-NN assertions at the user-facing
  level are set-membership assertions. If that contract can't hold,
  the fallback is server-only.

---

# 7. CLI Shape

---

## D-013: CLI dispatch nesting — `palace` as a flat table entry routing internally

- **Date**: 2026-04-21
- **Sprint**: sprint-001
- **Significance**: MEDIUM
- **Epics affected**: C (primary)

### Context

Risk R8: "`src/cli/dispatch.zig` nested subgroup is a first.
Architect validates extension pattern in Phase 2A before Epic C
story 1." A3 assumption says the dispatch extends cleanly. FR22
lists MVP subcommands: `palace mint` / `palace add-room` / `palace
inscribe` / `palace open` / `palace rename-mythos`. Three options:

1. **Single `palace` entry routing internally.** Add one new
   `Command { .name = "palace", .run = cmd_palace.run }` entry;
   inside `cmd_palace.run`, peel the second token and dispatch to
   `palace_add_room.run` etc.
2. **Flat entries per subverb.** Add five entries:
   `palace-mint`, `palace-add-room`, etc. (dash-separated; no
   second-level parsing).
3. **Subgroup table primitive.** Introduce a `CommandGroup` struct
   alongside `Command`; `commands` becomes a mixed list.

### Decision

**Option 1 — single `palace` entry routes internally.**

Concrete shape:

```zig
// src/cli/dispatch.zig (extend)
const cmd_palace = @import("palace.zig");

pub const commands: []const Command = &.{
    // ... existing commands ...
    .{ .name = "palace", .summary = "palace verb group (see `jelly palace --help`)", .run = cmd_palace.run },
};

// src/cli/palace.zig (new; single file routing palace subverbs)
const cmd_palace_mint = @import("palace_mint.zig");
const cmd_palace_add_room = @import("palace_add_room.zig");
const cmd_palace_inscribe = @import("palace_inscribe.zig");
const cmd_palace_open = @import("palace_open.zig");
const cmd_palace_rename_mythos = @import("palace_rename_mythos.zig");

const SubCommand = struct {
    name: []const u8,
    summary: []const u8,
    run: *const fn (Allocator, [][:0]const u8) anyerror!u8,
};

const subcommands: []const SubCommand = &.{
    .{ .name = "mint", ..., .run = cmd_palace_mint.run },
    .{ .name = "add-room", ..., .run = cmd_palace_add_room.run },
    .{ .name = "inscribe", ..., .run = cmd_palace_inscribe.run },
    .{ .name = "open", ..., .run = cmd_palace_open.run },
    .{ .name = "rename-mythos", ..., .run = cmd_palace_rename_mythos.run },
};

pub fn run(gpa: Allocator, args: [][:0]const u8) !u8 {
    if (args.len < 1) return printPalaceUsage();
    const sub = args[0];
    if (std.mem.eql(u8, sub, "--help") or std.mem.eql(u8, sub, "-h")) return printPalaceUsage();
    for (subcommands) |s| {
        if (std.mem.eql(u8, s.name, sub)) return s.run(gpa, args[1..]);
    }
    // unknown subcommand
    return printPalaceUsage();
}
```

**Why option 1:**

- **Minimal diff to `dispatch.zig`.** One entry added; the nested
  dispatch lives in its own file (`palace.zig`). The top-level
  table remains a flat list of twelve+ commands.
- **Growth-tier subcommands (`layout`, `share`, `rewind`,
  `observe`) drop into `palace.zig`'s `subcommands` array with
  zero changes to `dispatch.zig`.** The sprint-001 MVP set stays
  clean.
- **`jelly palace --help` is natural**: route to the nested usage
  printer. `jelly palace <bad-subcommand>` lists MVP subcommands +
  note on Growth ones (per FR22 acceptance).
- **The `palace_*.zig` files still exist one-per-subcommand.**
  Each is self-contained; `palace.zig` is a thin router, not a
  monolith.
- **Existing mental model preserved.** A new contributor reading
  `dispatch.zig` sees one new entry (`palace`) — that's the whole
  footprint. They click through to `palace.zig` only if they're
  working on palace commands.

**Why not option 2 (flat `palace-mint` entries):**

- Pollutes the top-level command list. Ship with 5, grow to 9+
  post-MVP; bloats every `--help` output.
- Breaks the PRD UX expectation: FR22 specifies
  `jelly palace mint`, not `jelly palace-mint`. Option 2 would
  require either hiding the real command name from the user, or
  accepting `jelly palace-mint` as the canonical form — both are
  user-hostile.

**Why not option 3 (subgroup table primitive):**

- Premature abstraction. We have exactly one subgroup today
  (`palace`). Future ones (`guild`, `relic`) are speculative.
- Touches `dispatch.zig`'s core type system for a one-use case.
- If a second subgroup emerges (say sprint-003 introduces `guild`),
  promote option 1's pattern to a primitive at that time — the
  refactor from "two `*.zig` dispatchers" to "one table-driven
  subgroup primitive" is mechanical and low-risk.

### Alternatives considered

- Options 2 + 3.
- **No top-level `palace` entry; alias `jelly mint --type=palace`
  as the only entry, shadow the subverbs as top-level.** Rejected.
  FR22 is explicit about the `jelly palace` verb group.

### Aligned with existing pattern

Aligned with existing pattern: **`dispatch.zig`'s `Command` struct
+ table idiom** — option 1 reuses it verbatim at the top level; the
second level mirrors it inside `palace.zig`. No new primitive.

Diverges from existing pattern: minor — `palace.zig` introduces a
local `SubCommand` type that shadows `Command` in shape. Acceptable:
the top-level and nested tables have different summary-text prefix
conventions (nested ones don't need to repeat "palace") and
different `--help` printers.

### Consequences

- **Epic C story 1 is the scaffold story**: add `cmd_palace` entry
  to `dispatch.zig`, create `palace.zig` with subcommand table and
  `printPalaceUsage`, stub all five `palace_*.zig` files returning
  non-zero "not yet implemented." Subsequent stories implement one
  subverb at a time.
- **`jelly palace --help` acceptance criterion** (FR22) runs through
  `cmd_palace.run` → `printPalaceUsage`. Golden test possible.
- **`cli-smoke.sh`** gets a `jelly palace --help` smoke as the first
  palace assertion; subsequent story smokes exercise each subverb.
- **Growth-tier subverbs** (`share`, `rewind`, `observe`, `layout`)
  are documented in `printPalaceUsage` as "(Growth; unimplemented)"
  so users know the roadmap without seeing half-baked commands.
- **Constraint imposed**: any future subgroup (e.g. `jelly guild`,
  `jelly relic`) uses this same pattern until a second subgroup lands
  and justifies promotion to a primitive.

---

# 8. Content Integrity

---

## D-014: Archiform registry cache — snapshot-on-mint, no revalidation at runtime

- **Date**: 2026-04-21
- **Sprint**: sprint-001
- **Significance**: MEDIUM
- **Epics affected**: C (primary)

### Context

FR27 + TC11: "19 seed forms ship as a `jelly.asset` of media-type
`application/vnd.palace.archiform-registry+json` on every freshly
minted palace. Registry resolves through `aspects.sh` at load time
with air-gap `jelly.asset` fallback." PROTOCOL.md §13.9 documents the
registry as a CAS asset attached to the palace. The question: **how
is the cache TTL governed?**

Three options:

1. **Stale-while-revalidate with 1h TTL.** Runtime fetches
   `aspects.sh` when palace loads; if fresh copy available and
   differs, updates local snapshot. Network on every load.
2. **Snapshot-on-mint only, no runtime revalidation.** Palace mint
   fetches (or bundles) the 19 seed forms once; they're attached as
   a `jelly.asset` on the palace at `jelly mint --type=palace`
   time. Runtime NEVER hits the network for archiforms.
3. **Fetch fresh on every palace load.** Always-network.

### Decision

**Option 2 — snapshot-on-mint only, no runtime revalidation. The
19 seed forms are bundled as a static `jelly.asset` attached at
mint.**

Concrete shape:

- `src/memory-palace/seed/archiform-registry.json` is a
  **compiled-in** JSON file shipped with `jelly` (Zig
  `@embedFile`). Contents: the 19 seed forms per FR27.
- `jelly palace mint` attaches this bundled asset to the palace
  envelope at mint-time. Asset hash is deterministic — same bytes
  for every freshly-minted palace (FR27 acceptance: "Registry bytes
  identical across fresh mints — deterministic").
- Runtime `aspects.sh` resolution: NEVER hit the network during
  palace open, render, verify, or inscribe. The attached asset IS
  the registry. If the palace was minted with registry v1 and v2
  ships tomorrow, the palace stays on v1 until the user explicitly
  mints a new palace or runs a hypothetical (post-MVP) `jelly palace
  refresh-archiforms` command.
- TC11 "aspects.sh at load with air-gap fallback" is honoured by
  **always taking the fallback path** — the registry always lives as
  a `jelly.asset` attached to the palace; network never attempted at
  load.
- `--archiform <unknown-form>` acceptance (FR25): the renderer logs
  "unknown archiform" warning and applies the room/inscription
  default. No runtime registry check against `aspects.sh`.

**Why option 2:**

- **Offline-first (NFR11).** MVP palace operations MUST work
  offline. Option 1 (runtime fetch) breaks this for the first load
  after being offline for a while. Option 2 works identically online
  and offline.
- **Determinism (FR27 acceptance).** "Registry bytes identical
  across fresh mints" means mint-time bytes are canonical. Runtime
  revalidation would mean "every palace has its own archiform
  registry version" which is a maintenance nightmare.
- **Air-gap fallback is the always-path.** TC11's phrasing
  ("`aspects.sh` at load time with air-gap `jelly.asset` fallback")
  permits option 2 — "air-gap" is the worst case, but there's
  nothing forbidding it as the default case. Option 2 makes the
  worst case the only case; the cost is that archiform registry
  updates don't propagate to existing palaces without user action.
- **MVP has 19 fixed forms.** They're not going to change in
  sprint-001's lifetime. Runtime revalidation solves a problem that
  doesn't exist at MVP timescale.
- **Simpler security model.** No network source to mock in tests;
  no cache-poisoning attack vector; no "did we fetch recently?"
  state.

**Why not option 1 (SWR 1h TTL):**

- Breaks offline-first for cold loads.
- Adds network failure modes to `jelly palace open` (NFR10 latency
  budget tightens).
- Requires a cache-invalidation test matrix (cache hit fresh, cache
  hit stale, cache miss online, cache miss offline, SWR revalidation
  race) none of which yields MVP user value.

**Why not option 3 (always-fresh):**

- Obvious failure mode on plane / subway / air-gapped host.

**Post-MVP extension:** A `jelly palace refresh-archiforms` command
can explicitly re-fetch and re-attach; a `jelly palace add-archiform`
can append a custom form. Both are Growth-tier.

### Alternatives considered

- Options 1 + 3.
- **No registry asset; hardcode the 19 forms in renderer + CLI.**
  Rejected. Violates FR27's "ship as a `jelly.asset`" and TC11's
  "attached to palace" contracts. Also breaks the principle that the
  palace's topology is self-contained.

### Aligned with existing pattern

Aligned with existing pattern: **Zig `@embedFile`** — other
compile-time constants in the codebase use this (e.g. any seed
templates shipped with the CLI). The archiform registry joins them.

Aligned with existing pattern: **content-addressed asset
attachment** — the `jelly.asset` envelope is already the vehicle for
attaching binary blobs to DreamBalls; this is another instance.

### Consequences

- **Epic C mint story** reads `@embedFile("../memory-palace/seed/archiform-registry.json")`
  and attaches it as a `jelly.asset` at mint. FR27 acceptance ("bytes
  identical across mints") follows.
- **`aspects.sh` is NOT imported** by any runtime code path in
  sprint-001. TC11's spec language is honoured; runtime behaviour is
  "always use fallback path."
- **Epic E renderer** looks up archiforms via the in-palace
  `jelly.asset` only. No HTTP fetch on lens render.
- **Epic D oracle** reads archiforms from the same in-palace asset
  when considering placement (e.g. "this is a library — suggest
  library-appropriate arrangements"). No HTTP.
- **Constraint imposed**: no runtime code in sprint-001 hits
  `aspects.sh` over the network. A post-MVP `refresh-archiforms`
  command is the sanctioned path for pulling updates; building it
  explicitly requires an ADR revising D-014.

---

## Requirements Conflicts

None — all decisions consistent with `requirements.md`.

**Annotations for reviewer**:

- **D-007 (store verbs)**: tightens TC12 from "single swap boundary"
  to "single verb-surface swap boundary" — a strengthening, not a
  conflict.
- **D-008 (inline sync file-watcher)**: explicitly honours A7
  (synchronous mirroring) and FR14 (2-second budget).
- **D-010 (WASM ML-DSA-87 verify)**: validates A12 before Epic A
  proceeds; validation path is non-conflicting, is in fact the
  explicit A12 mitigation shape.
- **D-011 (plaintext oracle key)**: explicitly documented compromise
  in SEC10; this decision names the MVP shape without extending
  SEC10's risk surface.
- **D-012 (single POST /embed)**: subset of FR20's "computed in
  jelly-server" — the decision locks the HTTP shape without altering
  FR20's semantics.
- **D-013 (palace routing)**: A3 assumption validated; no FR
  disturbed. FR22's "MVP subcommands" list drives option 1.
- **D-014 (archiform registry snapshot-on-mint)**: TC11's language
  ("with air-gap fallback") is preserved by making fallback the
  always-path. Arguably a *narrowing* of TC11, but no FR requires
  runtime fetch.
- **D-015 (vector parity)**: A5 validated; R2 mitigation concretized.
  NFR11 preserved in the happy path; option-3 degradation is a
  documented fallback, not an MVP default.
- **D-016 (LadybugDB schema)**: FR5, FR13, FR19, FR26 all trace to
  concrete node labels and relationship types in the schema. Fully
  consistent.
- **D-009 (shader spike)**: R4 mitigation concretized; NFR10
  unaffected; NFR14's four materials are all still in scope under
  option 1's gate.

---

## Cross-Epic Summary (for orchestrator routing)

| Decision | CRITICAL? | First-touched epic | Other epics consuming |
|----------|-----------|--------------------|-----------------------|
| D-007 Store API | Yes | B | C, D, E, F |
| D-008 Watcher txn | No (HIGH) | D | B (tx API), F (embed client) |
| D-009 Shader gate | No (HIGH) | E | — |
| D-010 WASM verify | Yes | A (story 1) | C, E, F (consume result) |
| D-011 Oracle key | No (MED) | C (mint) | D (read) |
| D-012 /embed shape | No (MED) | F | B (consume vec), D (via file-watcher) |
| D-013 CLI dispatch | No (MED) | C (story 1) | — |
| D-014 Archiform cache | No (MED) | C (mint) | D, E (read) |
| D-015 Vector parity | No (HIGH) | B (story 1) | F |
| D-016 LadybugDB schema | Yes | B (story 1+) | C, D, F |

Orchestrator user-elicitation priority (CRITICAL first):

1. **D-007** — store API surface (single biggest lock-in downstream)
2. **D-010** — WASM verify validation shape
3. **D-016** — LadybugDB schema

HIGH follow-ups (elicit if user bandwidth permits):

4. **D-008** — file-watcher transactional boundary
5. **D-009** — shader spike gate
6. **D-015** — vector-parity acceptance shape

MEDIUM can proceed default unless user objects.

---

## Changelog

- 2026-04-21 — Initial Phase 2A decisions (D-007 through D-016).
  Authored by planner (Opus 4.7). Ten decisions across data,
  rendering, security, services, CLI, and storage domains. Three
  CRITICAL (D-007, D-010, D-016) surface for user confirmation
  first.
