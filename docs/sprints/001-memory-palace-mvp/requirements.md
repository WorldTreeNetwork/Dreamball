---
project: memory-palace
sprint: sprint-001
product: memory-palace
created: 2026-04-21
steering_mode: GUIDED
previous_sprint: null
input_quality: existing-prd
source_prd: docs/products/memory-palace/prd.md
scope_tier: mvp-only
---

# Sprint-001 Requirements — Memory Palace MVP

## Product Vision

The Memory Palace is the first *composed application* of DreamBall v2 —
a palace-as-topology built from Field-typed DreamBalls, nesting the six
v2 types, with an Agent-typed oracle at the zero point, a signed
timeline DAG, a hash-linked mythos chain, Vril-carrying aqueducts, and a
three-lens rendering pack. Sprint-001 ships the **MVP cut** (PRD §10.3):
mint a palace, inscribe documents, converse with an oracle whose every
turn sits under the current mythos head, rename the mythos, tag rooms
with archiforms, see aqueducts carry computed Vril flow, and have the
whole state persist and replay.

---

## Personas (inherited from PRD §3)

- **P0 — Wayfarer.** Walks their own palace. Medium technical.
- **P1 — Guest.** Opens a DragonBall-sealed palace or shared room. Low technical.
- **P2 — Oracle host.** Custodian of the palace's Agent-typed core. High technical.
- **P3 — Guild scribe.** Authors shared rooms that appear in multiple personal palaces. Medium technical.
- **P4 — Observer.** v2's P0 persona, sees only outermost public surface.

Sprint-001 primarily serves **P0** and **P2**. P1, P3, P4 are served only by
the v2 primitives the palace inherits unchanged.

---

## Functional Requirements (26 sprint-scoped FRs)

Every FR below maps to a PRD FR (see `## Traceability` table at the end
of this document). FRs are testable, non-overlapping, and scoped to
sprint-001 acceptance criteria.

### Palace composition & mythos chain

### FR1: Palace mint with required mythos
`jelly mint --type=palace` SHALL mint a `jelly.dreamball.field` envelope
with `field-kind: "palace"`, auto-create one default Agent DreamBall
(the oracle) as a `contains` child **with its own hybrid keypair** (see
FR11 and D5), emit an empty-but-rooted `jelly.timeline`, and attach a
required `jelly.mythos` captured interactively or via `--mythos <string>`.

**Acceptance:**
- Missing `--mythos` with no TTY: non-zero exit with helpful message.
- With `--mythos "test"`: produced bundle verifies, `field-kind == "palace"`,
  exactly one Agent child, timeline root with `parent-hashes` absent/empty.
- Oracle child has its own `.key` file alongside the palace's (FR11/D5).
- `head-hashes` is a 1-element set containing the mint action's Blake3.

### FR2: Append-only mythos chain
The first `jelly.mythos` carries `is-genesis: true` without `predecessor`;
every subsequent mythos carries `is-genesis: false` and
`predecessor = Blake3(prior_mythos_envelope_bytes)`. `jelly verify` walks
the chain to genesis; a break or fork is a hard failure.

**Acceptance:**
- Genesis-only palace: verify passes.
- Unresolvable predecessor: non-zero exit naming the break.
- Second `is-genesis: true` attempt: rejected at mint time.

### FR3: `jelly palace rename-mythos` command
`jelly palace rename-mythos <palace> --body <text> [--true-name <word>]
[--form <form>]` appends a new `jelly.mythos` to the canonical chain AND
emits a paired `jelly.action` of kind `"true-naming"` referenced by the
new mythos's `discovered-in`, and re-signs the palace.

**Acceptance:**
- After rename: new mythos's `predecessor` = Blake3(prior); `discovered-in`
  resolves to a timeline `jelly.action` with `action-kind == "true-naming"`.
- Palace revision bumps; both Ed25519 + ML-DSA-87 signatures attached (NFR12).
- `--form` preserved verbatim.

### FR4: Per-child mythos attachment
`jelly palace add-room` and `jelly palace inscribe` accept optional
`--mythos <string>` or `--mythos-file <path>`, attaching a genesis
`jelly.mythos` to the minted envelope. Absent: no attribute attached;
render-time inheritance resolves the nearest enclosing mythos.

**Acceptance:**
- No `--mythos`: no `jelly.mythos` attribute present.
- With `--mythos`: room/inscription carries `is-genesis: true` mythos.
- `--mythos-file` path missing: non-zero exit with clear error.
- `rename-mythos` scoped to room/inscription fingerprint also works.

### FR5: Oracle always-in-context on current mythos head
The oracle's conversation layer prepends the current mythos head's
`body` to every turn's system prompt. Oracle's LadybugDB knowledge-graph
mirrors the chain via triples `(palace-fp, mythos-head, current-mythos-fp)`
and `(current-mythos-fp, predecessor, prior-mythos-fp)`.

**Acceptance:**
- Oracle system-prompt preview contains the mythos `body` verbatim.
- Cypher `MATCH (:Palace {fp: $p})-[:MYTHOS_HEAD]->(:Mythos)` → exactly one.
- After rename-mythos, `MYTHOS_HEAD` moves to new mythos; prior reachable via `:PREDECESSOR`.

### Rooms, inscriptions, timeline, containment

### FR6: `jelly palace add-room`
`jelly palace add-room <palace> --name <room-name>` mints a
`jelly.dreamball.field` with `field-kind: "room"` and appends a
`contains` connection from palace to room.

**Acceptance:**
- Room carries `field-kind == "room"` and the `--name` value.
- Palace's containment graph includes new room fp.
- `jelly verify` passes.

### FR7: `jelly palace inscribe`
`jelly palace inscribe <palace> --room <room-fp> <file>` mints an Avatar
DreamBall with a `jelly.inscription` attribute whose `source` is a
`jelly.asset` referring to `<file>` by Blake3 hash, placed in the named
room via `contains`.

**Acceptance:**
- Avatar carries `jelly.inscription`; `source` asset Blake3 equals `blake3(<file>)`.
- Room contains the Avatar fp.
- `<room-fp>` not in palace: non-zero exit "room not in palace".
- Default `--surface = "scroll"`, default `--placement = "auto"`.

### FR8: `jelly palace open`
`jelly palace open <palace>` launches the showcase app (Bun/Vite) with
the palace fp deep-linked to the omnispherical palace lens.

**Acceptance:**
- Exits 0 once app is reachable on a known port.
- Opening the URL renders topology (FR14).
- Unknown palace fp: exits non-zero without starting the server.

### FR9: State-changes emit signed timeline actions
Every mutating palace CLI operation (`mint-room`, `inscribe`, `move`,
`unlock`, `rename-mythos`, `aqueduct-traversal`, `create-aqueduct` per D3)
emits a signed `jelly.action` appended to `jelly.timeline`, dual Ed25519
+ ML-DSA-87 signed. `head-hashes` updates to the new leaf's Blake3.

**Acceptance:**
- After each mutating command: `head-hashes` = {new-leaf-hash}.
- Every action carries both signatures; stripping either fails verify.
- Action's `parent-hashes` resolves to an ancestor action (or empty for root).

### FR10: Containment cycle enforcement
Palace mint and mutation paths reject any operation producing a
containment cycle.

**Acceptance:**
- `add-room` with ancestor fp of target: non-zero exit citing "cycle".
- Unit test: A→B→A mint fails on the closing edge.

### Oracle

### FR11: Oracle mint as Agent DreamBall with own keypair
The default oracle is a `jelly.dreamball.agent` with:
- a **separate hybrid keypair** (Ed25519 + ML-DSA-87), stored in a
  sibling `.key` file to the palace's key (per D5);
- seed `personality-master-prompt` from a template asset (per D8);
- empty `memory`, empty `knowledge-graph`;
- default `emotional-register` with axes `curiosity`, `warmth`,
  `patience`, each initialised to 0.5.

**Acceptance:**
- Oracle envelope carries `personality-master-prompt` sourced from
  `src/memory-palace/seed/oracle-prompt.md`.
- Oracle's signature verifies under its own keypair, not the custodian's.
- `knowledge-graph` has 0 triples; `emotional-register` has 3 axes.

### FR12: Oracle unconditional palace read access
The oracle has read access to every slot in the palace (including
`guild-only`) regardless of Guild policy. Palace query layer bypasses
Guild-policy checks when requester == oracle fp.

**Acceptance:**
- Guild-only inscription: oracle-identity query returns contents.
- Same query as non-oracle, non-Guild visitor: policy-denied.

### FR13: Inscription triples in oracle knowledge-graph
Every `jelly palace inscribe` writes `(doc-fp, lives-in, room-fp)` into
the oracle's `knowledge-graph`, mirrored into LadybugDB. Mirroring is
**synchronous** with the action signing transaction (per assumption A8).

**Acceptance:**
- After 3 inscribes across 2 rooms: Cypher `MATCH (:Inscription)-[:LIVES_IN]->(:Room) RETURN count(*)` = 3.
- Oracle's `knowledge-graph` envelope contains matching triples.
- `move` action updates triple to new room fp.

### FR14: Oracle file-watcher
**(PRD FR72 — confirmed MVP per D1.)**
The oracle has a file-watcher skill that:
- detects inscription source-file changes on disk;
- updates the inscription's `jelly.asset` hash;
- bumps the Avatar's revision and re-signs;
- triggers FR20 re-embedding (delete-then-insert).

**Acceptance:**
- Editing an inscribed file: within 2s the Avatar's revision bumps and a
  `jelly.action` of kind `"inscription-updated"` lands on the timeline.
- Vector row is deleted-then-inserted (FR20 path exercised).
- File deletion on disk: Avatar is quarantined (not hard-deleted), a
  `jelly.action` of kind `"inscription-orphaned"` emitted, the renderer
  shows the Avatar dimmed.

### Rendering

### FR15: `palace` lens
Omnispherical navigable view of palace rooms. New Svelte component in
`src/lib/lenses/palace/` consuming `jelly.wasm`-decoded envelopes.

**Acceptance:**
- Storybook story with ≥3 rooms: each room positioned per `jelly.layout`.
- Clicking a room node fires a navigation event consumed by FR16.
- Registers alongside existing v2 lenses; no renumbering.

### FR16: `room` lens
Interior layout per the room's `jelly.layout` attribute; deterministic
grid fallback if unset.

**Acceptance:**
- Storybook story for a room with 2 inscriptions places them at
  `placement.position` with `placement.facing` quaternion.
- Unset layout: deterministic grid, no crash.
- Reads through the `src/memory-palace/store.ts` backend (FR19).

### FR17: `inscription` lens
Text-in-3D per the inscription's `surface` field: `scroll`, `tablet`,
`book-spread`, `etched-wall`, `floating-glyph`.

**Acceptance:**
- Storybook stories for each of the 5 documented surfaces render.
- Text content is full body of the `jelly.asset` source.
- Unknown surface: falls back to `scroll`, logs warning (non-crashing).

### FR18: Aqueduct traversal events + lazy creation
Each renderer traversal event between two rooms emits a signed
`jelly.action` of kind `move` on the timeline AND:
- **If a `jelly.aqueduct` between `(from, to)` does not yet exist**:
  materialises a new one with author-declared defaults
  (`resistance: 0.3`, `capacitance: 0.5`) and emits a paired
  `jelly.action` of kind `"aqueduct-created"` (per D3). Kind defaults
  to `"visit"`.
- **Updates** the aqueduct's `strength` via the Hebbian rule (per D4).
- Re-signs the aqueduct envelope.

**Acceptance:**
- First traversal between novel `(from, to)`: new aqueduct envelope + two actions on timeline.
- Subsequent traversal: only a `move` action; strength increments per D4 rule.
- Integration test: walk a 3-step path, verify strengths accumulate.

### Backing stores

### FR19: LadybugDB integration via single wrapper
All graph and vector state funnels through `src/memory-palace/store.ts`:
- **Server** (Bun): `@ladybugdb/core` with explicit `close()` on every
  `QueryResult` / `Connection` / `Database` (per TC9).
- **Browser**: `kuzu-wasm@0.11.3` with `mountIdbfs` + `syncfs`
  bidirectional lifecycle (per TC10).
- Containment, aqueducts, timeline actions, and knowledge-graph triples
  mirror on every state change; CAS remains source-of-truth.

**Acceptance:**
- `grep` for `@ladybugdb/core` or `kuzu-wasm` outside `store.ts` returns empty.
- After mint + add-room + inscribe: Cypher
  `MATCH (:Palace)-[:CONTAINS]->(:Room)-[:CONTAINS]->(:Inscription) RETURN count(*)` = 1.
- Dropping `.lbug`/`.kz` and replaying ingestion reproduces same graph shape.
- Every `QueryResult` closed (enforced by wrapper type).
- Server smoke hits native; browser smoke hits kuzu-wasm.

### FR20: Vector extension via LadybugDB
Semantic embeddings over inscriptions and memory-nodes use LadybugDB's
bundled `vector` extension (disk-HNSW, `simsimd` SIMD, cosine distance
over `ARRAY(FLOAT, N)`). Embedding via **Qwen3-Embedding-0.6B, 1024d
native with MRL-truncation to 256d** (per D2).

Embedding is computed in `jelly-server` (not in browser, not in WASM)
and returned as a vector blob on ingestion. This is an **interim
sanctioned network exit** — NFR11 (offline) relaxes for
embedding-creation only, with a `TODO-EMBEDDING: bring-model-local-or-byo`
marker on every call site.

**Acceptance:**
- Inscribing a document: vector persisted in inscription node's
  `embedding: ARRAY(FLOAT, 256)` property.
- K-NN Cypher `CALL QUERY_VECTOR_INDEX('inscription_emb', $q, 10) YIELD ...`
  returns the inscribed document for a related prompt.
- Dimension 256 is a single constant (`EMBEDDING_DIM`) declared once.
- 500 inscriptions × top-10 K-NN query: <200 ms.
- Network-disabled: palace still works for everything except ingestion
  (which queues or errors with a clear "embedding service unreachable").

### FR21: Delete-then-insert re-embedding
On inscription revision bump, recompute vector iff content hash changed;
emit delete-then-insert within a single transaction via a single
ingestion helper.

**Acceptance:**
- Content-hash changed: prior row deleted, new inserted; `MATCH (:Inscription {fp})` still returns 1.
- Content-hash unchanged: no re-embedding (spy on embedder asserts zero calls).
- `DELETE ... CREATE` is sole vector-write code path.

### CLI

### FR22: `jelly palace` verb group
MVP subcommands: `mint` (aliased from `jelly mint --type=palace`),
`add-room`, `inscribe`, `open`, `rename-mythos`. Growth subcommands
(`layout`, `share`, `rewind`, `observe`) are OUT.

**Acceptance:**
- `jelly palace --help` lists MVP subcommands plus note on Growth ones.
- Each subcommand's `--help` shows usage, required flags, example.
- Unknown subcommand: non-zero with `--help` suggestion.

### FR23: `jelly show --as-palace`
Pretty-prints palace topology: mythos head (body + true-name), room
tree with counts, item counts per room, timeline head hashes, oracle fp.

**Acceptance:**
- Golden-file test for human-readable output.
- Non-palace fp: non-zero with "not a palace" message.
- `--json` returns structured equivalent.

### FR24: `jelly verify` palace invariants
Extends `jelly verify` with palace checks: (a) ≥1 direct room,
(b) oracle is only Agent directly contained, (c) every action's
`parent-hashes` resolves to ancestors, (d) mythos chain resolves to
single genesis, (e) `head-hashes` refers to timeline leaves.

**Acceptance:**
- Synthetic fixtures for each failure mode exist in `tests/` or
  `scripts/cli-smoke.sh`.
- Each fixture's verify fails citing its invariant.

### Archiforms + aqueduct computation

### FR25: `--archiform` flag
`jelly palace add-room`, `jelly palace inscribe`, and
`jelly mint --type=agent` accept `--archiform <form>`. Attached as
`jelly.archiform` attribute. Absent: renderer applies defaults
(`room → chamber`, `inscription → scroll`, `agent → muse`).

**Acceptance:**
- `--archiform library`: room carries `jelly.archiform` with `form == "library"`.
- Absent flag: no attribute; renderer default applies (assertable in
  lens tests).
- Unknown form: accepted (open enum), logged "unknown archiform" warning.

### FR26: Compute aqueduct electrical properties per Hebbian + Ebbinghaus (D4)
On palace load (and on each `move` action), the runtime computes
`strength`, `conductance`, `phase` for every aqueduct, persists them,
and re-signs the envelope. `resistance` and `capacitance` are
author-declared priors; the runtime MUST NOT overwrite them.

**Formulas (D4 — MVP defaults, explicitly in flux):**
- **`strength` — Hebbian / Rescorla-Wagner saturating update.** On each
  traversal of aqueduct *(from, to)*, update:
  `strength ← strength + α × (1 - strength)`
  where `α = 0.1` (learning rate). Saturates toward 1.0.
- **`conductance` — (1 - resistance) × strength × forgetting-decay.**
  `conductance = (1 - resistance) × strength × exp(-t / τ)`
  where `t = now - last-traversed` (seconds), `τ = 30 days` (MVP
  forgetting time-constant; freshness dim threshold from Vril ADR).
  This is the MVP approximation; the full iterative neighbour-flow
  (EigenTrust-like) is Vision (FR98).
- **`phase`** — qualitative direction:
  - If recent-traversal dominant direction matches `from → to`: `"out"`.
  - If matches `to → from`: `"in"`.
  - If symmetric within window and count > threshold: `"resonant"`.
  - Otherwise: `"standing"`.

**Acceptance:**
- Formulas documented in ONE code comment block at the top of
  `src/memory-palace/aqueduct.ts` (canonical location).
- `resistance` / `capacitance` byte-identical across palace load/save.
- Re-signing bumps aqueduct revision.
- Unit test: simulate 100 traversals of an aqueduct, strength approaches
  but does not exceed 1.0.
- Unit test: conductance at t=0 equals `(1 - R) × strength`; at t=τ
  equals `(1 - R) × strength × e⁻¹ ≈ 0.368 × (1-R) × strength`.
- Unit test: phase symmetry classification correctness on synthetic inputs.

### FR27: Seed archiform registry
19 seed forms (`library`, `forge`, `throne-room`, `garden`, `courtyard`,
`lab`, `crypt`, `portal`, `atrium`, `cell`, `scroll`, `lantern`, `vessel`,
`compass`, `seed`, `muse`, `judge`, `midwife`, `trickster`) ship as a
`jelly.asset` of media-type `application/vnd.palace.archiform-registry+json`
on every freshly minted palace. JSON schema documented in
PROTOCOL.md §13.9.

**Acceptance:**
- Fresh palace contains the seed registry asset.
- `jelly palace show <palace> --archiforms` lists all 19 forms.
- Registry bytes identical across fresh mints (deterministic).
- Schema captures `form`, `parent-form` (optional), `tradition` (optional).

---

## Non-Functional Requirements

### NFR10: Latency
Opening a palace of ≤500 rooms × ≤50 inscriptions each renders the
first lit room in <2s on a mid-range laptop. (Inherits PRD §8.)

### NFR11: Offline-first with one sanctioned exit
Every palace operation except **Guild transmission**, **ML-DSA
signing** (server-delegated until the WASM ML-DSA ship lands per
CLAUDE.md update 2026-04-21 — see TC5), and **embedding creation**
(per FR20 / D2) works fully offline. LadybugDB (graph + vector) and
`jelly.wasm` are local.

Embedding creation is explicitly a **TODO-EMBEDDING** sanctioned exit
with a path to local-first in a later sprint.

### NFR12: Dual-signature authorship
Every `jelly.action` and every `jelly.trust-observation` carries both
Ed25519 and ML-DSA-87 signatures. No unsigned timeline writes.
Browser verify of both algorithms is now available under the updated
WASM budget (CLAUDE.md 2026-04-21: ≤200 KB raw / ≤64 KB gzipped,
ships ML-DSA-87 verify) — trust symmetry holds end-to-end.

### NFR13: Privacy — no implicit exfiltration
No palace state leaves the user's machine without explicit user action.
Resonance kernel, graph queries, and re-embedding all run locally;
embedding ingestion is the sanctioned exit (NFR11 / FR20) and carries a
per-call opt-in on the CLI (`--embed-via <url>` default to local jelly-server).

### NFR14: Mythos fidelity — warm architectural render
Palace renderer honours the opening image (PRD §1): warm architectural,
aqueducts visibly carrying Vril as flowing light, cilia-like motion,
room pulse on high capacitance, ambient glow per mythos emotional
register. Shader budget: ≤4 new materials:
1. **aqueduct-flow** — particles along path; speed ∝ conductance; freshness uniform dims toward floor.
2. **room-pulse** — pulse period ∝ capacitance; freshness uniform tints color.
3. **mythos-lantern** — lantern ring around fountain (stub in MVP; full lantern-ring visualisation is Growth FR60f).
4. **ley-line-ghost** — unused in MVP; reserve material slot for Growth.

The fourth slot is **`dust-cobweb`** overlay per Vril ADR (2026-04-21)
— visual decay at freshness floor. `ley-line-ghost` moves to Growth.

### NFR15: Crypto + CAS hygiene markers
Every mocked crypto site carries `TODO-CRYPTO: replace before prod`;
every CAS site carries `TODO-CAS: confirm indexer path`; every
embedding call carries `TODO-EMBEDDING: bring-model-local-or-byo`.

### NFR16: Test coverage per envelope
≥5 new Zig tests per palace envelope type; ≥3 Vitest integration tests
per new lens; golden-fixture bytes-lock for every new envelope per
PROTOCOL.md §13.11 (13 fixtures).

### NFR17: Build-gate green on every commit
`zig build test`, `zig build smoke`, `bun run check`,
`bun run test:unit -- --run` all green on every commit.
`scripts/cli-smoke.sh` and `scripts/server-smoke.sh` extend with palace
verbs; `tests/e2e-cryptography.sh` continues to pass.

### NFR18: Round-trip parity
Palace envelopes created via CLI round-trip byte-identically through the
codegen TypeScript decoder. Every new envelope gets a Vitest test
asserting this.

---

## Technical Constraints

Inherits all v2 constraints from `docs/products/dreamball-v2/prd.md
§Constraints`. Sprint-001-specific:

### TC1: Zig 0.16.0 pinned for all protocol/CLI work.
(PRD §11.)

### TC2: Bun + TypeScript for all JS; no npm/yarn/pnpm.
(CLAUDE.md project config.)

### TC3: Svelte 5 runes only.
(Existing pack idiom.)

### TC4: Threlte (WebGL default); WebGPU opt-in; WebGL fallback mandatory.
(NFR10 budget.)

### TC5: `jelly.wasm` ≤200 KB raw / ≤64 KB gzipped; ships ML-DSA-87 verify; single host import `env.getRandomBytes`.
**Updated 2026-04-21 per CLAUDE.md.** Previous ≤150 KB budget bumped to
≤200 KB to accommodate ML-DSA-87 verify. Browser now verifies hybrid
signatures end-to-end; server ML-DSA-87 subprocess path remains
available but is no longer the only option. Closes known-gaps §1.

### TC6: Zig ↔ TS only through generated code + HTTP.
(`tools/schema-gen/main.zig` is the single gate.)

### TC7: dCBOR canonical ordering; floats scoped to omnispherical-grid family + aqueduct numeric fields.
(PROTOCOL.md §2, §12.2, §13.2, §13.4.)

### TC8: LadybugDB v0.15.3 + vector extension (server) + kuzu-wasm@0.11.3 (browser).
(ADR 2026-04-21-ladybugdb-selection.md.)

### TC9: Explicit `close()` on every LadybugDB handle under Bun.
(ADR Step 1 mitigation.)

### TC10: Browser persistence uses `mountIdbfs` + bidirectional `syncfs` lifecycle.
(ADR Step 2b.)

### TC11: Archiform registry resolves through `aspects.sh` at load time with air-gap `jelly.asset` fallback.
(PROTOCOL.md §13.9; FR27.)

### TC12: All palace state mirrors through single swap boundary `src/memory-palace/store.ts`.
(ADR; PRD §6.2.1.)

### TC13: CAS source-of-truth; LadybugDB never holds CBOR bytes.
(ARCHITECTURE.md; PRD §6.2.)

### TC14: Timeline/action envelopes at `format-version: 3`; other palace envelopes at `format-version: 2`.
(PROTOCOL.md §13.3, §13.4, §13.12.)

### TC15: `jelly.quorum-policy` wire shape lands pre-FR68; MVP default = any-admin.
(ADR 2026-04-21-nextgraph-crdt-review.md §3 Option A.)

### TC16: `conductance` is an intermediate accumulator; verifiers MUST NOT reject on mismatch.
(PROTOCOL.md §13.4; PRD §5.4.)

### TC17: Vril `strength` is monotone on the signed chain; freshness is renderer-side only.
(ADR 2026-04-21-vril-flow-model.md.)

### TC18: `jelly.mythos` canonical vs. poetic chain-split rules enforced at verify.
(PROTOCOL.md §13.8.)

### TC19: Dream-field is omnipresent substrate; no new MVP wire envelope.
(ADR 2026-04-21-dream-field-embedding.md.)

### TC20: Float encoding via `#7.25` half-float where precision permits, `#7.26` single-float otherwise.
(PROTOCOL.md §12.2, §13.4.)

### TC21: Separate hybrid keypair for the oracle (per D5).
Stored in sibling `.key` file to the palace's; oracle signs its own
actions with its own key. Custody story for oracle secret tracked as a
known-gap follow-up (recrypt wallet integration is the long-term home).

---

## Security Requirements

### SEC1: Every `jelly.action` and `jelly.trust-observation` dual-signed (Ed25519 + ML-DSA-87).
(NFR12; PROTOCOL.md §13.3, §13.6. Native liboqs path via `src/ml_dsa.zig`.)

### SEC2: Hybrid signature policy = "all present signatures verify, no minimum count".
(PROTOCOL.md §2.3, §8.)

### SEC3: Canonical mythos chain MUST always be public regardless of Guild policy.
(PROTOCOL.md §13.8; FR2.)

### SEC4: Agent interiority (`personality-master-prompt`, `memory`, `knowledge-graph`, `emotional-register`, `interaction-set`) default Guild-restricted.
(v2 FR50; PROTOCOL.md §12.7.)

### SEC5: Oracle has read access to all palace slots regardless of Guild policy.
(FR12.)

### SEC6: No palace state emitted over network without explicit user action.
(NFR13.) Sanctioned exits: Guild transmission, ML-DSA signing (legacy
server path), embedding creation (FR20).

### SEC7: Every `TODO-CRYPTO` / `TODO-CAS` / `TODO-EMBEDDING` marker preserved; no silent upgrade of mocks.
(NFR15; known-gaps §5.)

### SEC8: Quorum wire shape = stacked `'signed'` attributes (Option A), not threshold-aggregate.
(ADR NextGraph §3.)

### SEC9: Trust observations decentralised; no protocol-level aggregation.
(PROTOCOL.md §13.6.)

### SEC10: Oracle's secret key custody is a sprint-001 compromise — local `.key` file alongside palace's.
A follow-up gap (tracked in known-gaps) will migrate to recrypt wallet
format (`DCYW` shell + Argon2id + XChaCha20-Poly1305 per known-gaps §6).

### SEC11: Every state-changing palace action emits a signed `jelly.action` before effect is visible.
(FR9.) No auditable gaps.

---

## Open Questions

Most Phase 1 open questions resolved in Decision Steering below. Remaining
questions are implementation-level nits that planner/architect can
default-answer in Phase 2:

- **OQ1** — Mythos body length bounds. Default for MVP: warn on >16 KB,
  hard-reject on >256 KB (envelope size concern). Can tighten later.
- **OQ2** — `jelly.archiform` attribute-vs-envelope. Per PROTOCOL.md
  §13.9, archiform is an **attribute** whose value is a small inline
  envelope (`{form, parent-form?, tradition?, note?}`), not a separately
  addressable DreamBall. Lock in Phase 2A.
- **OQ3** — Cross-browser persistence spike (Firefox + Safari for
  `kuzu-wasm@0.11.3`). Defer to a Growth-tier smoke test; if the spike
  fails post-MVP, open a fallback HTTP-only browser path. For sprint-001:
  Chromium is the validated browser target.

---

## Decision Steering — Resolutions (user-confirmed 2026-04-21)

### D1: FR72 (Oracle file-watcher) status — **MVP**
**Significance:** HIGH. Adds 1–2 stories to Epic 2 (Oracle + knowledge graph).
**Decision:** MVP. Implemented as FR14 above. File-watcher detects source
changes, bumps inscription revision, re-signs, triggers re-embedding.
Orphan case (source deleted) emits `"inscription-orphaned"` action and
dims the avatar in the renderer.

### D2: Embedding model — **Qwen3-Embedding-0.6B, 256d MRL-truncated, via server API (interim)**
**Significance:** HIGH. Affects NFR11 (offline), bundle budget, privacy.
**Decision:** Qwen3-Embedding-0.6B (Apache 2.0), 1024d native with MRL
truncation to 256d after fine-tuning. Embedding is computed server-side
(jelly-server or external API) — browser VRAM budget is too low for a
0.6B-param model in today's consumer hardware.
- Interim: jelly-server hosts the embedding endpoint; FR20 calls out to
  it at ingestion time.
- Every call-site marked `TODO-EMBEDDING: bring-model-local-or-byo` so a
  later sprint can collapse to WASM-local (ONNX or candle-wasm) or a
  user-brought model without ambiguity.
- NFR11 explicitly relaxes for embedding creation; all other palace
  operations (read, render, reason) stay offline.
- Opens the door for users with GPU VRAM to self-host the endpoint
  (`--embed-via http://localhost:XXXX`).

### D3: Aqueduct creation — **lazy, on first traversal**
**Significance:** MEDIUM. Affects FR18 (traversal), FR26 (compute).
**Decision:** No explicit aqueduct command. The first `move` action
between a novel `(from_fp, to_fp)` pair materialises a
`jelly.aqueduct` envelope with defaults (`resistance: 0.3`,
`capacitance: 0.5`, `kind: "visit"`) and emits a paired
`jelly.action` of kind `"aqueduct-created"`. Subsequent traversals
update `strength` only. This matches the Hebbian "connections
emerge from use" mental model without requiring a second UX path.

### D4: Aqueduct formulas — **Hebbian + Ebbinghaus, explicitly in flux**
**Significance:** HIGH. Wire values are computed, author-facing, and
visible in the renderer. Formulas will tune during Growth/Vision.
**Decision:** MVP formulas grounded in human-brain research:
- `strength` — Rescorla-Wagner / Hebbian saturating update:
  `strength ← strength + α × (1 - strength)` with `α = 0.1`.
- `conductance` — `(1 - resistance) × strength × exp(-t/τ)` with
  `τ = 30 days`. Combines Hebbian strength with Ebbinghaus forgetting.
- `phase` — qualitative enum derived from recent-traversal direction
  and symmetry (`out`, `in`, `standing`, `resonant`).
- All three formulas live as MVP constants in one code block
  (`src/memory-palace/aqueduct.ts`), explicitly marked as tunable.
- Documenting the neurobiological grounding in a VISION §15 addendum is
  a small follow-up (not blocking).

### D5: Oracle write identity — **separate hybrid keypair**
**Significance:** HIGH. Affects FR9 dual-sig story + SEC11 action-provenance.
**Decision:** The oracle has its own hybrid keypair (Ed25519 + ML-DSA-87),
generated at `jelly mint --type=palace` and persisted in a sibling
`.key` file to the palace's. Oracle-originated actions are signed with
the oracle's key; palace-originated actions are signed with the
custodian's. Each signer's identity is attached to every action via its
`signed` attribute.
- MVP storage: local `.key` file alongside palace key.
- Follow-up: recrypt wallet integration (known-gaps §6 path).
- Security: `SEC10` above documents the custody compromise.

### D6: Head-hashes pluralization verified (spec-present, no code yet)
**Significance:** HIGH (wire correctness).
**Status:** ✅ **Confirmed via grep (2026-04-21).** PROTOCOL.md §13.3,
§13.11 fixture 3a all use plural `head-hashes`. No Zig encoder/decoder
exists yet for `jelly.timeline` (the envelope hasn't been implemented),
so sprint-001 implements v3 from the spec directly. **No migration
hazard exists** because there is no prior v2 code to rewrite.

---

## Scope Boundaries

### In Scope (sprint-001 MVP)

**Protocol:**
- New envelope types (nine): `jelly.layout`, `jelly.timeline`,
  `jelly.action`, `jelly.aqueduct`, `jelly.element-tag`,
  `jelly.trust-observation`, `jelly.inscription`, `jelly.mythos`,
  `jelly.archiform` — all per PROTOCOL.md §13.
- New attribute on Field: `field-kind`.
- `format-version: 3` for timeline + action; `format-version: 2` for the
  other seven.
- `jelly.quorum-policy` wire shape lands (Option A), enforcement is v1.1.

**CLI:**
- `jelly palace` verb group: `mint`, `add-room`, `inscribe`, `open`,
  `rename-mythos`.
- `jelly show --as-palace`, `jelly verify` palace invariants.
- `--archiform` flag on `add-room`, `inscribe`, `mint --type=agent`.

**Oracle:**
- Mint-time bundle: prompt seed, empty memory + graph, seed emotional
  register, separate hybrid keypair.
- File-watcher skill for inscription source-change tracking.
- Unconditional palace read access.
- Mythos-head always prepended to conversation context.
- Knowledge-graph mirroring of inscriptions.

**Rendering:**
- Three new Svelte lenses: `palace`, `room`, `inscription`.
- NFR14 shader pack extended by 4 materials (aqueduct-flow, room-pulse,
  mythos-lantern stub, dust-cobweb).

**Storage:**
- LadybugDB integration via `src/memory-palace/store.ts` (single swap boundary).
- `kuzu-wasm@0.11.3` in browser; `@ladybugdb/core` on server.
- Vector index via bundled `vector` extension; Qwen3-Embedding-0.6B@256d.
- Delete-then-insert re-embedding.

**Docs:**
- Updates to `docs/PROTOCOL.md §13` and `docs/VISION.md §15` (ongoing).
- New ADRs if aqueduct formula research surfaces anything Vision-worthy.

### Out of Scope (explicit)

- **PRD FR60e** — `jelly palace reflect` ritual.
- **PRD FR60f** — Mythos lantern-ring full visualisation (MVP ships a stub).
- **PRD FR60g** — Mythos divergence resolution.
- **PRD FR66** — `jelly palace share --room`.
- **PRD FR67** — `jelly palace rewind`.
- **PRD FR68** — Multi-writer CRDT shared rooms.
- **PRD FR73** — Resonance kernel biasing (full).
- **PRD FR78** — Peripheral ghost visualisation.
- **PRD FR79** — Shared-palace interference patterns.
- **PRD FR83** — Quantised low-precision vectors.
- **PRD FR84** — Rebuild-from-CAS full guarantee.
- **PRD FR85–87** — Trust observations (emit, aggregate, transmit).
- **PRD FR91** — `jelly palace trace`.
- **PRD FR92** — `jelly palace gc`.
- **PRD FR96** — Vril particle-flow visuals on aqueducts (beyond the
  single `aqueduct-flow` shader in NFR14 — MVP ships the shader with
  flat params; Growth ties it to per-aqueduct live values).
- **PRD FR97** — Oracle archiform-aware placement suggestions.
- **PRD FR98** — Vril bottleneck diagnostics.
- **Palace marketplace / discovery.**
- **Mobile-native renderer.**
- **Element-tag palette/audio bindings.**
- **Chained proxy-recryption transmission** (recrypt dependency).
- **Federation / cross-palace visuals.**
- **Recrypt-wallet oracle-key custody** (follow-up gap).

---

## Assumptions

| # | Assumption | Risk | Validation |
|---|------------|------|------------|
| A1 | `kuzu-wasm@0.11.3` IDBFS validated on Chromium; Firefox + Safari untested. | HIGH | Add Playwright smoke on Firefox + Safari during Phase 5 validation; if fails, open HTTP-fallback browser story (not blocking MVP, but a known risk). |
| A2 | Bun napi `close()` mitigation holds in long-running `jelly-server` (hours). | MEDIUM | Soak-test server with scripted load ≥1hr in `scripts/server-smoke.sh` during Phase 5. |
| A3 | `src/cli/dispatch.zig` extends cleanly with nested `palace` subgroup. | LOW–MED | Explore confirmed existing pattern; Phase 2A architect validates before Epic 1 stories. |
| A4 | `zig build schemagen` regenerates `src/lib/generated/*.ts` cleanly for new envelopes. | LOW | Run codegen on branch; diff + `bun run check`. |
| A5 | LadybugDB vector-extension graph-join works identically on server + browser (`kuzu-wasm@0.11.3`). | MEDIUM | Run identical K-NN fixture on both runtimes; if browser lacks, server-only vector path (breaks NFR11 offline locally — known follow-up). |
| A6 | Qwen3-Embedding-0.6B server hop maintains <200ms K-NN latency for 500 inscriptions. | MEDIUM | Load test on representative hardware in Phase 5. |
| A7 | Oracle-knowledge-graph mirroring is synchronous within each signed-action transaction. | MEDIUM | Specify in FR13 story; fault-injection test. |
| A8 | Three new lenses plug into `src/lib/lenses/` without refactoring the dispatch registry. | LOW | Follow `omnispherical` lens template; architect confirms Phase 2A. |
| A9 | FR26 MVP formulas (D4) are acceptable as in-flux code defaults. | LOW | Tracked explicitly; tune via follow-up research note, not a v2 spec change. |
| A10 | Single-author/single-custodian use cases dominate MVP; multi-head timelines tested via spec fixture only. | LOW | `head-hashes` cardinality = 1 in all happy-path tests; multi-head golden §13.11 fixture 3a is spec-only. |
| A11 | All MVP FRs implementable without protocol wire-format change beyond PROTOCOL §13. | LOW | Architect cross-walks each FR against §13 in Phase 2A. |
| A12 | CLAUDE.md 2026-04-21 WASM budget bump (200KB raw / 64KB gzip / ML-DSA verify) has landed and ML-DSA verify is functional in `jelly.wasm`. | HIGH | Verify via `bun run test:unit -- --run` against `src/lib/wasm/verify.test.ts`; if still stubbed, reopen known-gaps §1 for sprint-001 completion. |

---

## Traceability — Sprint FR ↔ PRD FR

| Sprint FR | PRD FR | Scope |
|-----------|--------|-------|
| FR1 | FR60 | MVP |
| FR2 | FR60a | MVP |
| FR3 | FR60b | MVP |
| FR4 | FR60c | MVP |
| FR5 | FR60d | MVP |
| FR6 | FR61 | MVP |
| FR7 | FR62 | MVP |
| FR8 | FR63 | MVP |
| FR9 | FR64 | MVP |
| FR10 | FR65 | MVP |
| FR11 | FR69 | MVP |
| FR12 | FR70 | MVP |
| FR13 | FR71 | MVP |
| FR14 | **FR72** | MVP (promoted from Growth per D1) |
| FR15 | FR74 | MVP |
| FR16 | FR75 | MVP |
| FR17 | FR76 | MVP |
| FR18 | FR77 | MVP (extended per D3 to include lazy creation) |
| FR19 | FR80 | MVP |
| FR20 | FR81 | MVP |
| FR21 | FR82 | MVP |
| FR22 | FR88 | MVP |
| FR23 | FR89 | MVP |
| FR24 | FR90 | MVP |
| FR25 | FR93 | MVP |
| FR26 | FR94 | MVP (formulas per D4) |
| FR27 | FR95 | MVP |

---

## Existing Codebase Inventory (for Phase 2A)

Extension points identified by the explore agent (Phase 1):

**Zig protocol core:**
- `src/envelope_v2.zig` — add 9 new `encode<Type>(allocator, ...fields)`
  functions; each follows the Guild/Memory/KnowledgeGraph pattern.
- `src/protocol_v2.zig` — add 9 new struct types matching the envelope
  shapes from PROTOCOL.md §13.
- `src/golden.zig` — add 13 `GOLDEN_*_BLAKE3` constants + tests
  (per PROTOCOL.md §13.11).
- `src/signer.zig` + `src/ml_dsa.zig` — reuse as-is for palace actions.
- `src/key_file.zig` — reuse; oracle's key is a second hybrid file
  alongside the palace's.

**Zig CLI:**
- `src/cli/dispatch.zig` — extend command table with `palace` subgroup
  entries.
- New files: `src/cli/palace_mint.zig`, `palace_add_room.zig`,
  `palace_inscribe.zig`, `palace_open.zig`, `palace_rename_mythos.zig`,
  `palace_show.zig`, `palace_verify.zig`.

**Codegen:**
- `tools/schema-gen/main.zig` — regenerates `src/lib/generated/*.ts`
  after adding palace structs to `protocol_v2.zig`.

**Svelte lib:**
- `src/lib/lenses/` — add `PalaceLens.svelte`, `RoomLens.svelte`,
  `InscriptionLens.svelte` alongside 8 existing lenses.
- `src/lib/components/DreamBallViewer.svelte` — extend lens dispatch
  map with three new entries.
- `src/lib/backend/` — new `src/memory-palace/store.ts` as a fresh
  backend surface; HttpBackend + MockBackend untouched.

**Showcase + server:**
- `jelly-server/src/routes/` — new `palace.ts` routes following
  existing mint/grow/verify pattern.
- `jelly-server` — hosts the Qwen3 embedding endpoint (per D2).
- `src/routes/demo/` — add `/demo/palace` walkthrough.

**WASM:**
- `src/lib/wasm/jelly.wasm` — extend with `mintPalace`, `addRoom`,
  `inscribeAvatar`, etc. exports; follow existing packed-ptr-len
  convention. **Now ships ML-DSA-87 verify** per TC5.

**Tests:**
- Zig inline `test "…"` per encoder; golden-bytes lock per envelope.
- `scripts/cli-smoke.sh` extended with palace verbs.
- `scripts/server-smoke.sh` extended with embedding endpoint smoke.
- Vitest round-trip tests per envelope.
- Storybook stories per lens × type × layout combo.

---

## Changelog

- 2026-04-21 — Initial requirements.md from Phase 1 three-agent merge
  (analyst opus, architect opus, explore haiku). All six HIGH/CRITICAL
  Decision Steering elicitations resolved by user: FR72 → MVP (D1),
  Qwen3 embedding via server API (D2), lazy aqueduct creation (D3),
  Hebbian + Ebbinghaus formulas (D4), separate oracle keypair (D5),
  head-hashes pluralization verified (D6). CLAUDE.md 2026-04-21 WASM
  budget bump to 200KB raw / 64KB gzipped shipping ML-DSA-87 verify
  reflected in TC5, NFR11, NFR12.
