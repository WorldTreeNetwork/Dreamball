//! gen_cypher — Memory Palace graph DDL generator (graph-store owned).
//!
//! Relocated out of `tools/schema-gen/` in graph-store/1 (Dreamball-9dq)
//! to close the §2 leak: the protocol core's schema-gen must NOT know
//! about the graph store's DDL. This file is now compiled only by the
//! graph-store orchestrator (`tools/graphstore-schema/main.zig`), never
//! by the core `tools/schema-gen` exe.
//!
//! Per-archiform pass (generateArchiform):
//!   Emits `src/memory-palace/schema.cypher` with a provenance header
//!   naming `schemas/memory-palace-0.1.0.json` and its pin as source.
//!   The DDL body is the BODY constant below.
//!
//!   The schema is validated structurally before emission: every table
//!   name referenced in BODY must have a corresponding $defs entry in
//!   the memory-palace schema with the correct x-cypher-table value.
//!   This makes the per-archiform pass the AC6 drift gate: removing a
//!   table from the schema causes the validation step to fail before any
//!   output is written.
//!
//! Byte-equivalence note (AC2):
//!   The provenance header names the archiform schema as source; the DDL
//!   body is byte-identical to the pre-migration reference
//!   (tests/fixtures/pre-migration-schema.cypher). The 3-line header diff
//!   is registered in
//!   tests/codegen/normalizations/cypher-header-source-schema.md.
//!   Gated by tests/codegen/cypher-byte-equivalence.test.ts.

const std = @import("std");
const cc = @import("codegen_common");

const OUT_PATH = "src/memory-palace/schema.cypher";

// ── Per-archiform pass (Story 2.2) ────────────────────────────────────────────

/// Called by the graph-store orchestrator's per-archiform dispatch.
/// Validates the schema covers all tables declared in BODY, then emits
/// `src/memory-palace/schema.cypher` with an archiform provenance header.
pub fn generateArchiform(actx: *const cc.ArchiformCtx) !void {
    // Validate schema covers all expected tables before emitting.
    try validateSchemaCoverage(actx);

    const allocator = actx.arena;
    const header = try buildArchiformHeader(allocator, actx);

    var file = try std.Io.Dir.cwd().createFile(actx.io, OUT_PATH, .{ .truncate = true });
    defer file.close(actx.io);
    var file_buf: [4096]u8 = undefined;
    var fw = file.writer(actx.io, &file_buf);
    try fw.interface.writeAll(header);
    try fw.interface.writeAll(BODY);
    try fw.interface.flush();

    try cc.logKV(actx.stderr, .{
        .{ "phase", "output-written" },
        .{ "path", OUT_PATH },
        .{ "bytes", header.len + BODY.len },
        .{ "pass", "per-archiform" },
    });
}

// ── Schema validation (AC6 drift gate) ───────────────────────────────────────

/// Expected table names that BODY declares.
/// If any of these are absent from the schema, generation fails.
const EXPECTED_NODE_TABLES = [_][]const u8{
    "Palace", "Room", "Inscription", "Agent", "Triple",
    "Mythos", "Aqueduct", "ActionLog",
};

const EXPECTED_REL_TABLES = [_][]const u8{
    "CONTAINS",     "MYTHOS_HEAD",  "PREDECESSOR",
    "LIVES_IN",     "AQUEDUCT_FROM", "AQUEDUCT_TO",
    "KNOWS",        "HAS_KNOWLEDGE",
};

/// Validate that every table name BODY declares has a matching $defs entry
/// in the archiform schema. Returns error.SchemaTableMissing if any is absent.
fn validateSchemaCoverage(actx: *const cc.ArchiformCtx) !void {
    const defs = switch (actx.schema_value) {
        .object => |obj| blk: {
            const defs_val = obj.get("$defs") orelse {
                try cc.logKV(actx.stderr, .{
                    .{ "phase", "schema-validate" },
                    .{ "status", "error" },
                    .{ "detail", "missing $defs" },
                    .{ "schema", actx.schema_path },
                });
                return error.SchemaMissingDefs;
            };
            break :blk switch (defs_val) {
                .object => |d| d,
                else => return error.SchemaDefsNotObject,
            };
        },
        else => return error.SchemaNotObject,
    };

    // Check all expected node tables.
    for (EXPECTED_NODE_TABLES) |table_name| {
        if (!hasTableDef(defs, table_name)) {
            try cc.logKV(actx.stderr, .{
                .{ "phase", "schema-validate" },
                .{ "status", "missing-table" },
                .{ "table", table_name },
                .{ "kind", "node" },
                .{ "schema", actx.schema_path },
            });
            return error.SchemaTableMissing;
        }
    }

    // Check all expected rel tables.
    for (EXPECTED_REL_TABLES) |table_name| {
        if (!hasTableDef(defs, table_name)) {
            try cc.logKV(actx.stderr, .{
                .{ "phase", "schema-validate" },
                .{ "status", "missing-table" },
                .{ "table", table_name },
                .{ "kind", "rel" },
                .{ "schema", actx.schema_path },
            });
            return error.SchemaTableMissing;
        }
    }

    // Also verify Triple.fp MERGE key is declared (D-028 requirement).
    if (!hasFpMergeKey(defs, "Triple")) {
        try cc.logKV(actx.stderr, .{
            .{ "phase", "schema-validate" },
            .{ "status", "missing-merge-key" },
            .{ "table", "Triple" },
            .{ "schema", actx.schema_path },
        });
        return error.SchemaMissingMergeKey;
    }

    try cc.logKV(actx.stderr, .{
        .{ "phase", "schema-validate" },
        .{ "status", "ok" },
        .{ "schema", actx.schema_path },
    });
}

/// Returns true if `defs` contains an entry with x-cypher-table == table_name.
fn hasTableDef(defs: std.json.ObjectMap, table_name: []const u8) bool {
    var iter = defs.iterator();
    while (iter.next()) |entry| {
        const def_obj = switch (entry.value_ptr.*) {
            .object => |o| o,
            else => continue,
        };
        const tv = def_obj.get("x-cypher-table") orelse continue;
        const ts = switch (tv) {
            .string => |s| s,
            else => continue,
        };
        if (std.mem.eql(u8, ts, table_name)) return true;
    }
    return false;
}

/// Returns true if the $defs entry for `table_name` has a properties.fp entry
/// (required for the MERGE key per D-028).
fn hasFpMergeKey(defs: std.json.ObjectMap, table_name: []const u8) bool {
    var iter = defs.iterator();
    while (iter.next()) |entry| {
        const def_obj = switch (entry.value_ptr.*) {
            .object => |o| o,
            else => continue,
        };
        const tv = def_obj.get("x-cypher-table") orelse continue;
        const ts = switch (tv) {
            .string => |s| s,
            else => continue,
        };
        if (!std.mem.eql(u8, ts, table_name)) continue;
        const props_v = def_obj.get("properties") orelse return false;
        const props_obj = switch (props_v) {
            .object => |o| o,
            else => return false,
        };
        return props_obj.get("fp") != null;
    }
    return false;
}

// ── Provenance header ────────────────────────────────────────────────────────

fn buildArchiformHeader(allocator: std.mem.Allocator, actx: *const cc.ArchiformCtx) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        \\-- DO NOT EDIT — generated by tools/schema-gen.
        \\-- Provenance:
        \\--   source-schema:     {0s}
        \\--   source-schema-fp:  blake3:{1s}
        \\--   schema-version:    {2s}
        \\--   generator-id:      {3s}
        \\--   generator-commit:  {4s}
        \\-- Regenerate via `bun run codegen`. Hand-edits will be overwritten.
        \\-- See docs/decisions/2026-04-25-json-schema-canonical.md (D-018) and
        \\-- docs/sprints/002-archiform-foundation/architecture-decisions.md (D-030).
        \\
        \\
    ,
        .{
            actx.schema_path,
            actx.schema_fp,
            actx.schema_version,
            actx.generator_id,
            actx.generator_commit,
        },
    );
}

// ── Canonical DDL body ───────────────────────────────────────────────────────

const BODY =
    \\-- schema.cypher — canonical DDL for the Memory Palace graph
    \\--
    \\-- Single source of truth per D-016. Executed identically on:
    \\--   server: @ladybugdb/core napi (store.server.ts)
    \\--   browser: kuzu-wasm@0.11.3 (store.browser.ts)
    \\--
    \\-- Idempotency: each CREATE statement is guarded in the adapter code via
    \\-- CALL SHOW_TABLES() — tables that already exist are skipped.
    \\--
    \\-- Vector index: CREATE_VECTOR_INDEX is issued by the adapter after DDL,
    \\-- gated by CALL SHOW_INDEXES() to skip if already present.
    \\-- Server adapter: runs INSTALL VECTOR; LOAD EXTENSION VECTOR first.
    \\-- Browser adapter: VECTOR extension is bundled — no install/load needed.
    \\--
    \\-- RC1: Inscription.orphaned BOOL DEFAULT false (S4.4 file-watcher writes here)
    \\-- RC2: ActionLog.action_kind STRING accepts all 9 known action kinds
    \\-- RC3: Inscription.source_blake3 STRING (not body_hash)
    \\--
    \\-- CONTAINS: single multi-pair rel table covering Palace→Room, Room→Inscription,
    \\-- Palace→Inscription, Palace→Agent. kuzu-wasm@0.11.3 supports multi-pair rel tables
    \\-- (confirmed by S2.1 spike — same engine version as @ladybugdb/core 0.15.3).
    \\--
    \\-- DISCOVERED_IN: NOT a relationship. Stored as Mythos.discovered_in_action_fp
    \\-- STRING property per AC2 / D-016 decision.
    \\--
    \\-- TRIPLE node table + HAS_KNOWLEDGE REL:
    \\-- The oracle Agent's knowledge graph is stored as native graph nodes (Triple)
    \\-- with HAS_KNOWLEDGE edges from Agent to each Triple it owns. Previously the KG
    \\-- was a JSON STRING column on Agent — that was (1) not CBOR-on-the-wire-native,
    \\-- (2) re-parsed and re-serialised on every insert (O(n²) on replay), (3) an
    \\-- on-disk format owned by TS outside the Zig-generated schema story. Native
    \\-- nodes give us idempotent MERGE via fp = blake3(agent||s||p||o), indexable
    \\-- subject lookups, and a versioning path that mirrors every other schema change.
    \\-- See docs/decisions/2026-04-24-kg-triple-native-storage.md for the rationale.
    \\
    \\-- ── Node tables (8) ────────────────────────────────────────────────────────────
    \\
    \\CREATE NODE TABLE Palace(
    \\  fp STRING PRIMARY KEY,
    \\  created_at INT64,
    \\  mythos_head_fp STRING,
    \\  guild_fps STRING[] DEFAULT []
    \\);
    \\
    \\CREATE NODE TABLE Room(
    \\  fp STRING PRIMARY KEY,
    \\  created_at INT64
    \\);
    \\
    \\-- Inscription carries a policy + revision column so S4.2 getInscription can
    \\-- actually read the gate (previously the code hardcoded 'any-admin' and no
    \\-- column existed to read), and so S4.4 file-watcher revision-bumps persist
    \\-- across the reembed delete/recreate round-trip instead of being silently
    \\-- reset to zero. Default policy is 'public' to keep the MVP readable.
    \\CREATE NODE TABLE Inscription(
    \\  fp STRING PRIMARY KEY,
    \\  source_blake3 STRING,
    \\  orphaned BOOL DEFAULT false,
    \\  embedding FLOAT[256],
    \\  created_at INT64,
    \\  policy STRING DEFAULT 'public',
    \\  revision INT64 DEFAULT 0
    \\);
    \\
    \\-- S4.1: oracle Agent carries 4 slot columns (stored as JSON strings) plus
    \\-- knowledge graph now stored as native Triple nodes via HAS_KNOWLEDGE (below).
    \\-- personality_master_prompt: seed asset bytes (oracle-prompt.md)
    \\-- memory: JSON array (empty at mint)
    \\-- emotional_register: JSON object {curiosity,warmth,patience} at 0.5 each
    \\-- interaction_set: JSON array (empty at mint)
    \\CREATE NODE TABLE Agent(
    \\  fp STRING PRIMARY KEY,
    \\  created_at INT64,
    \\  personality_master_prompt STRING DEFAULT '',
    \\  memory STRING DEFAULT '[]',
    \\  emotional_register STRING DEFAULT '{"curiosity":0.5,"warmth":0.5,"patience":0.5}',
    \\  interaction_set STRING DEFAULT '[]'
    \\);
    \\
    \\-- Native KG triple row, one per (agent, subject, predicate, object) tuple.
    \\-- fp is deterministic: blake3(agent_fp || '\0' || subject || '\0' || predicate || '\0' || object).
    \\-- Replaces the prior Agent.knowledge_graph STRING DEFAULT '[]' JSON blob.
    \\CREATE NODE TABLE Triple(
    \\  fp STRING PRIMARY KEY,
    \\  agent_fp STRING,
    \\  subject STRING,
    \\  predicate STRING,
    \\  object STRING,
    \\  created_at INT64
    \\);
    \\
    \\CREATE NODE TABLE Mythos(
    \\  fp STRING PRIMARY KEY,
    \\  body STRING,
    \\  canonicality STRING,
    \\  discovered_in_action_fp STRING,
    \\  created_at INT64
    \\);
    \\
    \\CREATE NODE TABLE Aqueduct(
    \\  fp STRING PRIMARY KEY,
    \\  from_fp STRING,
    \\  to_fp STRING,
    \\  resistance DOUBLE DEFAULT 0.3,
    \\  capacitance DOUBLE DEFAULT 0.5,
    \\  strength DOUBLE DEFAULT 0.0,
    \\  conductance DOUBLE DEFAULT 0.0,
    \\  phase STRING DEFAULT 'standing',
    \\  revision INT64 DEFAULT 0,
    \\  last_traversal_ts INT64 DEFAULT 0
    \\);
    \\
    \\CREATE NODE TABLE ActionLog(
    \\  fp STRING PRIMARY KEY,
    \\  palace_fp STRING,
    \\  action_kind STRING,
    \\  actor_fp STRING,
    \\  target_fp STRING,
    \\  parent_hashes STRING[],
    \\  timestamp INT64,
    \\  cbor_bytes_blake3 STRING
    \\);
    \\
    \\-- ── Relationship tables (8) ────────────────────────────────────────────────────
    \\
    \\-- CONTAINS: multi-pair covering all containment edges in one table.
    \\-- Pairs: Palace→Room, Room→Inscription, Palace→Inscription, Palace→Agent (S3.2 oracle child)
    \\CREATE REL TABLE CONTAINS(
    \\  FROM Palace TO Room,
    \\  FROM Room TO Inscription,
    \\  FROM Palace TO Inscription,
    \\  FROM Palace TO Agent
    \\);
    \\
    \\-- MYTHOS_HEAD: unique 1-edge pointer from Palace to its current head Mythos.
    \\CREATE REL TABLE MYTHOS_HEAD(
    \\  FROM Palace TO Mythos
    \\);
    \\
    \\-- PREDECESSOR: mythos chain — each Mythos points to its predecessor.
    \\CREATE REL TABLE PREDECESSOR(
    \\  FROM Mythos TO Mythos
    \\);
    \\
    \\-- LIVES_IN: Inscription lives in a Room (complement to CONTAINS Room→Inscription).
    \\CREATE REL TABLE LIVES_IN(
    \\  FROM Inscription TO Room
    \\);
    \\
    \\-- AQUEDUCT_FROM: Aqueduct originates from a Room.
    \\CREATE REL TABLE AQUEDUCT_FROM(
    \\  FROM Aqueduct TO Room
    \\);
    \\
    \\-- AQUEDUCT_TO: Aqueduct terminates at a Room.
    \\CREATE REL TABLE AQUEDUCT_TO(
    \\  FROM Aqueduct TO Room
    \\);
    \\
    \\-- KNOWS: reserved for oracle/quorum graph — Agent→Agent knowledge edges.
    \\-- Defined upfront even if unused in Epic 2.
    \\CREATE REL TABLE KNOWS(
    \\  FROM Agent TO Agent
    \\);
    \\
    \\-- HAS_KNOWLEDGE: Agent owns a set of Triple nodes in its knowledge graph.
    \\-- Replaces the prior Agent.knowledge_graph JSON STRING column.
    \\CREATE REL TABLE HAS_KNOWLEDGE(
    \\  FROM Agent TO Triple
    \\);
    \\
    \\-- ── Vector index ───────────────────────────────────────────────────────────────
    \\-- NOTE: CREATE_VECTOR_INDEX is NOT in this file.
    \\-- It is issued by each adapter after DDL execution, gated by SHOW_INDEXES().
    \\-- Server: requires INSTALL VECTOR + LOAD EXTENSION VECTOR first.
    \\-- Browser: VECTOR extension bundled — no install/load step.
    \\-- See store.server.ts and store.browser.ts open() for the actual call.
    \\
;
