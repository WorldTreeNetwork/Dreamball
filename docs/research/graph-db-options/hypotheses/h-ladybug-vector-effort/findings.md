# Hypothesis: LadybugDB Vector Search — State and Effort to Add/Improve

## Summary

LadybugDB (v0.15.3, April 2026) ships a **fully functional, disk-based HNSW vector index** inherited directly from Kuzu v0.11.3 and actively maintained in a separate submodule (`ladybugdb/extensions`). The implementation supports **cosine, L2, L2-squared, and dot-product** metrics over `FLOAT[N]` or `DOUBLE[N]` fixed-size arrays, uses SIMD-accelerated distance functions via vendored `simsimd`, and is **pre-loaded in v0.11.3+** (no `INSTALL` required). No fork-patching or sidecar is needed for the Memory Palace use case (10K–100K inscriptions, 1536-dim embeddings, K-NN queries). One open limitation: in-place updates to indexed columns fail (must delete-then-insert), filed as open issue #377 on 2026-04-12.

**Effort to add vector search: 0 engineer-days** — already present.

---

## Evidence

### 1. Kuzu v0.11.3 Vector Extension — Confirmed Present and Pre-Loaded

Kuzu v0.11.3 bundles four pre-loaded extensions: `algo`, `fts`, `json`, **`vector`**. No `INSTALL` required.

Source tree at `extension/vector/`:
```
extension/vector/
  CMakeLists.txt          — links simsimd
  src/
    catalog/              — hnsw_index_catalog_entry.cpp
    function/             — create_hnsw_index.cpp (20K),
                            drop_hnsw_index.cpp (4K),
                            query_hnsw_index.cpp (19K)
    index/                — hnsw_config.cpp (8K), hnsw_graph.cpp (16K),
                            hnsw_index.cpp (54K), hnsw_index_utils.cpp (4.5K),
                            hnsw_rel_batch_insert.cpp (7K)
    main/                 — vector_extension.cpp — entry point
```

Total ~138,571 bytes, ~2,770 LOC of C++. **Native HNSW implementation** — no hnswlib or usearch vendored. Distance functions delegate to `simsimd` (vendored in `third_party/simsimd/`), providing SIMD-accelerated `simsimd_cos_f32/f64`, `simsimd_dot_f32/f64`, `simsimd_l2_f32/f64`, `simsimd_l2sq_f32/f64`.

Entry point (clean plugin API):
```cpp
void VectorExtension::load(main::ClientContext* context) {
    auto& db = *context->getDatabase();
    extension::ExtensionUtils::addTableFunc<QueryVectorIndexFunction>(db);
    extension::ExtensionUtils::addStandaloneTableFunc<CreateVectorIndexFunction>(db);
    extension::ExtensionUtils::addStandaloneTableFunc<DropVectorIndexFunction>(db);
    extension::ExtensionUtils::registerIndexType(db, OnDiskHNSWIndex::getIndexType());
    initHNSWEntries(context);
}
```

### 2. Algorithm and Distance Metrics

**Algorithm**: Disk-based HNSW. Two-layer structure: sparse upper layer for coarse navigation, dense lower layer for precise search. Tunable via `mu`, `ml`, `pu`, `efc`, `efs`, `alpha`, `cache_embeddings`.

**Distance metrics** (from `hnsw_config.cpp` lines 43–50):
- `cosine` (default)
- `l2`
- `l2sq` (L2 squared — same ranking, avoids sqrt)
- `dotproduct` (alias: `dot_product`)

All dispatch through `simsimd` for both `FLOAT` (f32) and `DOUBLE` (f64).

### 3. Data Type and Dimension Handling

Vectors must be `ARRAY(FLOAT, N)` or `ARRAY(DOUBLE, N)` node properties. Validator in `hnsw_index_utils.cpp`:

```cpp
void HNSWIndexUtils::validateColumnType(const common::LogicalType& type) {
    if (type.getLogicalTypeID() == common::LogicalTypeID::ARRAY) {
        auto& childType = ...->getChildType();
        if (childType.getLogicalTypeID() == common::LogicalTypeID::FLOAT ||
            childType.getLogicalTypeID() == common::LogicalTypeID::DOUBLE) {
            return;
        }
    }
    throw common::BinderException("VECTOR_INDEX only supports FLOAT/DOUBLE ARRAY columns.");
}
```

**Dimension limit**: No hard-coded upper bound found. Dimension read at runtime from `ArrayTypeInfo::getNumElements()` as `uint64_t`. 1536 dimensions (OpenAI ada-002 / text-embedding-3-small) well within range.

### 4. LadybugDB Preservation and Active Development

LadybugDB moved extensions to `https://github.com/ladybugdb/extensions.git` (confirmed in `.gitmodules`). Byte-level comparison against Kuzu v0.11.3:

| File | Kuzu v0.11.3 | LadybugDB current | Delta |
|---|---|---|---|
| `hnsw_index.cpp` | 54,427 | 54,582 | +155 |
| `hnsw_config.cpp` | 8,336 | 9,308 | +972 |
| `hnsw_graph.cpp` | 16,057 | 16,019 | −38 |
| `hnsw_index_utils.cpp` | 4,470 | 5,600 | +1,130 |
| `hnsw_rel_batch_insert.cpp` | 7,006 | 6,966 | −40 |
| `create_hnsw_index.cpp` | 20,165 | 20,806 | +641 |
| `drop_hnsw_index.cpp` | 4,021 | 4,841 | +820 |
| `query_hnsw_index.cpp` | 19,444 | 19,710 | +266 |
| `vector_extension.cpp` | 2,669 | 2,669 | 0 |

**Total LadybugDB**: ~140,501 bytes, ~2,810 LOC. Namespace changed from `kuzu` to `lbug`; structure identical. The `+972` in `hnsw_config.cpp` and `+1,130` in `hnsw_index_utils.cpp` indicate **active maintenance**.

### 5. Known Limitation: In-Place Update of Indexed Columns

Open issue **#377** (filed 2026-04-12, still open): setting an embedding column with a HNSW index throws:
```
RuntimeError: Cannot set property vec in table embeddings because it is used
in one or more indexes. Try delete and then insert.
```

For the Memory Palace use case, inscriptions are largely write-once. Re-embedding requires a delete-then-insert cycle rather than `MATCH ... SET`. A real operational constraint but not a blocker.

### 6. Repo Size and Shape

- **LadybugDB core**: 973 stars, ~61 MB, C++ 74.5% (~7.3 MB), active as of 2026-04-19, 72 open issues.
- **LadybugDB extensions submodule**: ~925 KB of C++. Vector is one of 16 peers sharing the same plugin API boundary.
- **`simsimd`** vendored in `third_party/simsimd/` — distance computations SIMD-accelerated out of the box.

### 7. Query Surface

Official API — usable without modification:

```cypher
// Create the index
CALL CREATE_VECTOR_INDEX(
  'inscriptions', 'embedding_idx', 'embedding',
  metric := 'cosine', efc := 128, ml := 30
);

// Query
CALL QUERY_VECTOR_INDEX(
  'inscriptions', 'embedding_idx',
  [0.1, 0.2, ...]::FLOAT[1536],
  10,  // K
  efs := 64
)
WITH node AS inscr, distance
MATCH (inscr)-[:LIVES_IN]->(room:Room)
RETURN inscr.id, room.name, distance
ORDER BY distance;
```

The graph-join pattern is first-class. A sidecar (usearch, sqlite-vec) would *lose* this integration.

### 8. Sidecar Alternative Assessment (for completeness)

- **sqlite-vec** (7,454 stars): Brute-force flat scan, no HNSW. O(N) query. Insufficient at 100K vectors.
- **usearch** (~3K SLOC header-only C++): HNSW + SIMD. Could wrap as extension in ~1–2 engineer-weeks. **Unnecessary — existing implementation covers this.**

### 9. Disambiguation: `AdaWorldAPI/ladybugdb` is NOT LadybugDB

A separate Python/DuckDB/LanceDB wrapper shares the name. Real project is `LadybugDB/ladybug`.

---

## Confidence

**Level**: high

Direct GitHub API inspection of source files with byte-level comparison between Kuzu v0.11.3 and LadybugDB's extension submodule; source reading of `hnsw_config.cpp` (metrics, tuning) and `hnsw_index_utils.cpp` (simsimd dispatch, type validation); official documentation; March 2026 production tutorial; open issue tracker. Medium-confidence only on maximum tested dimension — no explicit cap found in code.

---

## Sources

- [1] https://github.com/kuzudb/kuzu/releases/tag/v0.11.3
- [2] https://raw.githubusercontent.com/kuzudb/kuzu/v0.11.3/extension/vector/src/main/vector_extension.cpp
- [3] https://raw.githubusercontent.com/ladybugdb/extensions/main/vector/src/index/hnsw_config.cpp
- [4] https://raw.githubusercontent.com/ladybugdb/extensions/main/vector/src/index/hnsw_index_utils.cpp
- [5] https://github.com/LadybugDB/ladybug — `.gitmodules` pointing to `ladybugdb/extensions`
- [6] https://api.github.com/repos/ladybugdb/extensions/contents/vector/src/index
- [7] https://docs.ladybugdb.com/extensions/vector — `CREATE_VECTOR_INDEX` / `QUERY_VECTOR_INDEX`
- [8] https://volodymyrpavlyshyn.substack.com/p/vector-search-in-ladybugdb (March 2026) — production tutorial
- [9] https://github.com/LadybugDB/ladybug/issues/377 — write-to-indexed-column limitation (filed 2026-04-12)
- [10] https://github.com/LadybugDB/ladybug — repo stats
- [11] https://github.com/unum-cloud/usearch (sidecar baseline)
- [12] https://github.com/asg017/sqlite-vec (sidecar baseline)

---

## Open Questions

1. **Maximum tested dimension**: No hard cap found. 1,536 expected fine; 3,072 (text-embedding-3-large) untested.
2. **Write performance at scale**: Delete-then-insert workaround may bottleneck if embeddings are frequently re-computed.
3. **WASM build inclusion**: v0.15.3 mentions "statically linked extensions." Whether vector is included in WASM build is unclear — server-side native binary is unaffected.
4. **Third-party extension precedent**: Kuzu extension API self-labelled "still in development." LadybugDB actively diverging. Net-new third-party extension would track `lbug` internals, not upstream Kuzu.

---

## Verdict

**(a) Already-present — use it.**

LadybugDB v0.15.3 ships a production-quality, disk-based HNSW vector index with cosine/L2/L2sq/dot-product metrics, SIMD-accelerated, supporting `FLOAT[N]` / `DOUBLE[N]` arrays at arbitrary dimension. ~2,800 LOC of native C++ (no third-party HNSW library beyond `simsimd` for distance), actively maintained in `ladybugdb/extensions`.

**Effort sizing:**
- **Add vector search to Memory Palace**: **0 engineer-days** — already present.
- **Operational workaround for write limitation (issue #377)**: ~0.5 engineer-days (helper for delete-then-insert in ingestion).
- **If write limitation blocks** (high-frequency re-embedding): patch vector extension for in-place index updates — ~3–5 engineer-days for someone familiar with LadybugDB internals.
- **Sidecar (sqlite-vec, usearch wrapper)**: ~1–2 engineer-weeks, loses graph-join integration, unnecessary.
- **Fork-patch or native HNSW from scratch**: ~2–3 engineer-weeks minimum, not warranted.
