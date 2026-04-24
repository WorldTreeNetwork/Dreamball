# 2026-04-22 — schema.cypher and action-mirror.ts design decisions

Sprint: sprint-001 · Story: S2.4

## Decision 1: CONTAINS is a single multi-pair rel table

`schema.cypher` defines `CREATE REL TABLE CONTAINS(FROM Palace TO Room, FROM Room TO Inscription, FROM Palace TO Inscription)` as a single multi-pair table rather than three separate tables. The S2.1 spike confirmed that kuzu-wasm@0.11.3 and @ladybugdb/core 0.15.3 run the same Kuzu engine, which supports multi-pair rel tables in this version. A single CONTAINS table simplifies queries (`MATCH (:Palace)-[:CONTAINS*]->(:Inscription)` traverses the whole chain) and avoids proliferating rel-table names. If a future kuzu version drops multi-pair support, splitting is a mechanical migration.

## Decision 2: CREATE_VECTOR_INDEX in adapters, not schema.cypher

`schema.cypher` contains only `CREATE NODE TABLE` and `CREATE REL TABLE` statements. The `CREATE_VECTOR_INDEX` call is issued by each adapter in its `open()` method, guarded by `CALL SHOW_INDEXES()`. Rationale: (a) the server adapter requires `INSTALL VECTOR; LOAD EXTENSION VECTOR` before index creation — those are extension-load commands, not DDL, and do not belong in schema.cypher; (b) it is unknown whether kuzu-wasm@0.11.3's wasm build exposes `CREATE_VECTOR_INDEX` — the browser adapter wraps the call in a try/catch and logs a warning rather than hard-failing, so kNN via `QUERY_VECTOR_INDEX` (confirmed working in S2.1) continues to function even if the index was created server-side and is present in the persisted `.kz` file. Both adapters follow the same guard pattern.

## Decision 3: INT64 ms-epoch timestamps throughout

`schema.cypher` uses `INT64` for all timestamp columns (Palace.created_at, Room.created_at, etc.) and ActionLog.timestamp. The S2.2 inline DDL used LadybugDB `TIMESTAMP` type and string literals in `'YYYY-MM-DD HH:MM:SS'` format. That format was fragile (timezone/precision issues) and not portable to kuzu-wasm where `TIMESTAMP('...')` literal parsing behaves slightly differently. INT64 ms-epoch is unambiguous, trivially comparable for ORDER BY, and matches what JavaScript's `Date.now()` returns. The only cost is human-readability of raw DB dumps, which is acceptable.

## Decision 4: mirrorAction injected exec pattern

`action-mirror.ts` receives an `exec: (cypher: string) => Promise<Array<Record<string, unknown>>>` function injected by the store adapter, rather than importing a DB directly. This keeps `action-mirror.ts` adapter-agnostic — the same module works for both `ServerStore` (@ladybugdb/core) and `BrowserStore` (kuzu-wasm). Each adapter binds its internal `runQuery` to `exec`. The cost is one extra function-call indirection per Cypher statement; the benefit is that `action-mirror.ts` has no DB imports and is fully unit-testable with a mock exec function.
