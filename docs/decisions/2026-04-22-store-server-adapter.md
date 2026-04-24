# 2026-04-22 — Store server adapter (S2.2) non-obvious decisions

## MERGE semantics via existence-check + conditional CREATE

LadybugDB (kuzu 0.15.x) does not support Cypher `MERGE`. All "upsert"
operations in `store.server.ts` are implemented as: MATCH for the
primary key → if zero rows returned, issue CREATE. This is safe because
the server adapter is single-connection and non-concurrent at MVP scope.
If concurrent access becomes a requirement, the pattern must be replaced
with a transaction-wrapped MERGE equivalent or an ON CONFLICT clause once
LadybugDB supports it.

## SHOW_TABLES for idempotent DDL

To make `open()` safe to call on an already-initialised database (AC3
in S2.4 terms, idempotency requirement in S2.2 open()), `runDDL()`
calls `CALL SHOW_TABLES()` first and skips CREATE statements for tables
that already exist. This avoids a "table already exists" runtime error
from LadybugDB. The table list is fetched once per `open()` call.

## headHashes computed in process, not in Cypher

LadybugDB does not support list-unnesting joins in the version available
at sprint-001 (no `UNWIND` equivalent on array columns in Cypher). The
`headHashes()` verb fetches all `(fp, parent_hashes)` rows for the
palace and computes the set difference in JavaScript. This is acceptable
for MVP palace sizes (expected < 10k actions). If action counts grow,
S2.4 or a later sprint should add a dedicated `HeadRef` node or a
materialised column.

## _mirrorAction placement (temporary)

AC9 requires replay from ActionLog. Since S2.4 (action-mirror.ts) has
not shipped, `_mirrorAction` is a private method on `ServerStore`. It
supports only the four action kinds needed for S2.2 test fixtures:
`palace-minted`, `room-added`, `avatar-inscribed`, `true-naming`. S2.4
will extract this to `action-mirror.ts` and wire all store verbs to call
through it — at that point `_mirrorAction` on the class is deleted.

## VECTOR extension load in open()

`@ladybugdb/core` 0.15.3 bundles the VECTOR extension but does not
auto-load it. `open()` must call `INSTALL VECTOR` then `LOAD EXTENSION
VECTOR` before any `CREATE_VECTOR_INDEX` or `QUERY_VECTOR_INDEX` call.
This was discovered in the S2.1 spike and is documented in the S2.1 Dev
Agent Record. S2.2 perpetuates the pattern in `open()`.
