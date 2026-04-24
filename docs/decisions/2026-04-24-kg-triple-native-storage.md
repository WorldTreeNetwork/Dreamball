# ADR 2026-04-24 — Native Triple storage replaces `Agent.knowledge_graph` JSON

## Context

Prior to the 2026-04-24 hardening pass the oracle Agent's knowledge graph
lived in a single `Agent.knowledge_graph STRING DEFAULT '[]'` column, populated
with a JSON array of `{subject, predicate, object}` triples. Every
`insertTriple` call read the entire JSON blob, parsed it, checked for
duplicates, appended, re-serialised, and wrote back. Code review flagged three
problems:

1. **Not CBOR-native on disk.** The rest of the Memory Palace on-disk shape is
   generated from Zig (`tools/schema-gen/main.zig`) so the wire format lives in
   exactly one place (`src/*.zig`). `knowledge_graph` violated that invariant
   by existing only in `schema.cypher` / TS, with no Zig-side representation.
2. **O(n²) on replay.** Replaying a palace's ActionLog calls `insertTriple`
   once per `avatar-inscribed` / `move` action. Read-modify-write on the
   growing JSON string made replay cost quadratic in the number of triples.
3. **No versioning story.** Any future schema change to triple shape (adding
   `created_at`, reified relations, etc.) would require a new JSON migrator —
   a class of migration the rest of the system doesn't have because every
   other column round-trips through the Zig-generated schema.

## Decision

Store triples as native graph rows.

```cypher
CREATE NODE TABLE Triple(
  fp STRING PRIMARY KEY,
  agent_fp STRING,
  subject STRING,
  predicate STRING,
  object STRING,
  created_at INT64
);

CREATE REL TABLE HAS_KNOWLEDGE(
  FROM Agent TO Triple
);
```

`Triple.fp = blake3(agent_fp || '\0' || subject || '\0' || predicate || '\0' || object)`
(implemented in `cypher-utils.deriveTripleFp`). `fp` is the MERGE key —
`insertTriple` becomes an idempotent existence check keyed on fp + a
single-row CREATE + a single CREATE edge. Duplicate writes no-op.

`Agent.knowledge_graph STRING` is removed from `schema.cypher`.

## Consequences

- Triple reads/writes are native Cypher:
  `(Agent)-[:HAS_KNOWLEDGE]->(Triple)`, indexable by `subject` when kuzu
  gains secondary indexes on string columns.
- CBOR remains the wire format on ActionLog envelopes; the `Triple` row is
  derived state (can always be replayed from ActionLog). JSON is now only an
  optional export format, not the source of truth.
- Fixtures that baked in the JSON-shaped KG move from
  `src/memory-palace/seed/palace-*/` to `tests/fixtures/palace/` so the
  production seed directory only holds artefacts that ship
  (`archiform-registry.json`, `oracle-prompt.md`).
- `mirrorInscriptionToKnowledgeGraph` / `mirrorInscriptionMove` keep the same
  TS signatures and therefore callers (palace-inscribe, palace-move bridges)
  are unchanged.

## Status

Accepted 2026-04-24. Implemented in the same pass that landed the
`cypher-utils` validator seam, the `oracleActionStub` env gate, and the
`policy` / `revision` columns on `Inscription`.
