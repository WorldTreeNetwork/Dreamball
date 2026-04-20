# Decomposition: Embedded Graph DB Replacement for Dreamball Memory Palace

## Understanding

We need to replace KuzuDB in the Memory Palace composition — a local-first, Zig/Bun-embedded, property-graph store indexed by Blake3 fingerprints, rebuildable from a `.jelly` CAS, ideally WASM-targetable, ideally with bundled vector search. A good answer names one primary recommendation plus one fallback, grounded in 2026 maintenance reality, with explicit trade-offs across the hard requirements (embedded, local-first, property-graph, DAG traversal, fingerprint-keyed, WASM-friendly) and the soft tiebreakers (vectors, Bun bindings, license, footprint).

## Sub-Questions

1. Is KuzuDB actually dead in 2026, and if so what is the provenance/trajectory of its community forks (LadybugDB, Bighorn)?
2. Can DuckDB + duckpgq + VSS plausibly serve as a single-binary replacement for both the graph store and the vector store, in-process and ideally in WASM?
3. Is CozoDB (Datalog + built-in vectors + embedded Rust) a better fit than any Kuzu successor for our exact shape of work?
4. Which of the remaining 2026-relevant embedded graph DBs (Oxigraph, SurrealDB embedded, IndraDB, HelixDB, RocksDB/SQLite-custom) deserve serious consideration, and do any dominate the named candidates on our constraints?
5. Given rebuild-from-CAS and fingerprint-keyed semantics, does any candidate's bulk-load / idempotent-write / 32-byte-key index story decisively rule it in or out?

## Selected Hypotheses

1. **H1: KuzuDB upstream status + fork provenance** — foundational grounding
2. **H4: DuckDB + duckpgq + VSS as the unicorn** — highest info value
3. **H5: CozoDB as strong dark-horse** — best fit on requirements matrix
4. **H2+H3 merged: LadybugDB vs Bighorn comparative assessment** — fork viability
5. **H6+H7+H8 merged: Survey of remaining field** (Oxigraph, SurrealDB license, HelixDB, IndraDB, RocksDB fallback)

### Cross-cutting evaluation axes each investigator must report on:
- Rebuild-from-CAS bulk-load ergonomics (H9)
- Bun FFI / Node-API binding availability (H11)
- Vendor-and-freeze viability (H10) — folded into H1
