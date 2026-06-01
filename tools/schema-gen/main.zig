//! JSON-Schema-canonical generator orchestrator (D-030 Option A).
//!
//! Introduced in Story 1.3. Legacy static-text generator deleted in
//! Story 1.5 (cutover). This orchestrator:
//!
//!   1. Reads `schemas/root-2.0.0.json` from disk.
//!   2. Verifies the pin file `schemas/.pins/root-2.0.0.fp` matches
//!      blake3 of the schema bytes (the upstream gate is also wired
//!      via `bun run codegen` → `scripts/schemas-verify.ts`; this
//!      orchestrator re-runs the check so the structured-log entry
//!      surfaces in `zig build schemagen` output as well).
//!   3. Dispatches to the per-target generators (root pass) and then
//!      the per-archiform generators in deterministic order.
//!   4. Each generator emits provenance-headed output (NFR9). The
//!      orchestrator emits one structured-log JSON line per phase to
//!      stderr (NFR10): `schema-read`, `pin-verify`,
//!      `generator-dispatch`, `output-written`, `done`.
//!
//! Per D-018 the CBOR encoding algorithm stays canonical in Zig +
//! WASM (`encode_cbor` / wire-tag constants). `gen_cbor.zig` emits
//! TS shims that delegate to those primitives; it does NOT
//! re-implement CBOR semantics in TypeScript.
//!
//! Per NFR8 (validate-on-publish, not validate-on-decode): the
//! generated TS in `src/lib/generated/` does NOT call `Valibot.parse`
//! / `safeParse` at decode-time. The `schemas.ts` file exports
//! validators for use at publish boundaries (jelly-server ingest,
//! mint-time authoring); decode paths take the raw CBOR-derived
//! object directly.
//!
//! graph-store/1 (Dreamball-9dq): this core orchestrator no longer
//! emits `src/memory-palace/schema.cypher`. The Memory Palace graph
//! DDL is owned by the graph-store orchestrator
//! (`tools/graphstore-schema`, run via `zig build graphstore-schema`)
//! — the core protocol schema-gen must not know about the graph
//! store's DDL (the §2 leak). The shared `ArchiformCtx`, the
//! schema-read/pin-verify helper, and the blake3 + structured-log
//! primitives live in the neutral `codegen_common` module
//! (`tools/codegen-common/codegen_common.zig`), imported by both
//! orchestrators and every per-archiform generator.
//!
//! Run: `zig build schemagen` (typically via `bun run codegen`,
//! which also runs `scripts/schemas-verify.ts` first, then
//! `zig build graphstore-schema`).

const std = @import("std");
const cc = @import("codegen_common");
const gen_zig = @import("gen_zig.zig");
const gen_ts = @import("gen_ts.zig");
const gen_valibot = @import("gen_valibot.zig");
const gen_cbor = @import("gen_cbor.zig");
const gen_cli = @import("gen_cli.zig");
const gen_ts_client = @import("gen_ts_client.zig");
const gen_mcp_tools = @import("gen_mcp_tools.zig");
const gen_capabilities = @import("gen_capabilities.zig");

const SCHEMA_PATH = "schemas/root-2.0.0.json";
const PIN_PATH = "schemas/.pins/root-2.0.0.fp";
const SCHEMA_VERSION = "2.0.0";
const TS_OUT_DIR = "src/lib/generated";

// ── Per-archiform schema paths (Story 2.2) ────────────────────────────────────
const ARCHIFORM_SCHEMA_PATH = "schemas/memory-palace-0.1.0.json";
const ARCHIFORM_PIN_PATH = "schemas/.pins/memory-palace-0.1.0.fp";
const ARCHIFORM_SCHEMA_VERSION = "0.1.0";

// ── Shared codegen primitives (codegen_common) ────────────────────────────────
// Generator identity + the structured-log/blake3 helpers live in the neutral
// `codegen_common` module so the graph-store orchestrator can share them
// without importing this file (graph-store/1 §2 decoupling). Re-exported as
// `pub` here so the per-archiform generators keep referencing them via
// `main_mod.*`.
pub const GENERATOR_ID = cc.GENERATOR_ID;
pub const GENERATOR_COMMIT = cc.GENERATOR_COMMIT;
pub const logKVPub = cc.logKV;

// Internal aliases so this file's call sites stay terse.
const logKV = cc.logKV;
const logErr = cc.logErr;
const blake3Hex = cc.blake3Hex;

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const io = std.Io.Threaded.global_single_threaded.io();
    const stderr = std.Io.File.stderr();
    var err_buf: [1024]u8 = undefined;
    var err_w = stderr.writer(io, &err_buf);

    const t_start = std.Io.Clock.now(.real, io);

    // 1) Read schema.
    const schema_bytes = std.Io.Dir.cwd().readFileAlloc(io, SCHEMA_PATH, arena, .limited(1 << 22)) catch |e| {
        try logErr(&err_w, "schema-read-failed", SCHEMA_PATH, @errorName(e));
        return e;
    };
    var schema_fp_buf: [64]u8 = undefined;
    // Dupe into the arena so the fp outlives the stack buffer — matches the
    // convention in codegen_common.loadArchiform (the fp is stored into
    // GeneratorCtx, so it must not alias a stack-local).
    const schema_fp = try arena.dupe(u8, blake3Hex(schema_bytes, &schema_fp_buf));
    try logKV(&err_w, .{
        .{ "phase", "schema-read" },
        .{ "path", SCHEMA_PATH },
        .{ "fp", schema_fp },
        .{ "bytes", schema_bytes.len },
    });

    // 2) Pin verify (AC6: emit structured log; exit non-zero on mismatch).
    const pin_bytes = std.Io.Dir.cwd().readFileAlloc(io, PIN_PATH, arena, .limited(128)) catch |e| {
        try logErr(&err_w, "pin-verify", PIN_PATH, @errorName(e));
        return e;
    };
    const pin_text = std.mem.trim(u8, pin_bytes, &std.ascii.whitespace);
    if (!std.mem.eql(u8, pin_text, schema_fp)) {
        try logKV(&err_w, .{
            .{ "phase", "pin-verify" },
            .{ "status", "mismatch" },
            .{ "expected", pin_text },
            .{ "actual", schema_fp },
            .{ "schema", SCHEMA_PATH },
        });
        return error.SchemaPinMismatch;
    }
    try logKV(&err_w, .{
        .{ "phase", "pin-verify" },
        .{ "status", "match" },
        .{ "fp", schema_fp },
    });

    // 3) Parse schema. The structural value isn't consumed by every
    //    generator yet (per D-030 Option A the per-target generators
    //    embed the canonical text bodies during the shadow phase) but
    //    parsing here proves the schema is well-formed JSON before any
    //    generator runs and surfaces failure in the structured log.
    _ = std.json.parseFromSliceLeaky(std.json.Value, arena, schema_bytes, .{}) catch |e| {
        try logErr(&err_w, "schema-parse-failed", SCHEMA_PATH, @errorName(e));
        return e;
    };

    // 4) Build provenance header (NFR9). TS-style comment leader; the
    //    Cypher leader moved out with the graph-store DDL generator.
    const ts_header = try buildHeader(arena, "//", schema_fp);

    // 5) Dispatch generators in deterministic order.
    try ensureDir(io, TS_OUT_DIR);

    const ctx = GeneratorCtx{
        .io = io,
        .arena = arena,
        .ts_header = ts_header,
        .schema_fp = schema_fp,
        .stderr = &err_w,
    };

    try dispatch("gen_zig", &ctx, gen_zig.generate);
    try dispatch("gen_ts", &ctx, gen_ts.generate);
    try dispatch("gen_valibot", &ctx, gen_valibot.generate);
    try dispatch("gen_cbor", &ctx, gen_cbor.generate);

    // ── Per-archiform pass (Story 2.2) ────────────────────────────────────────
    // Walk non-root schemas (currently only memory-palace-0.1.0.json) and
    // dispatch the per-archiform generators. graph-store/1: gen_cypher is no
    // longer dispatched here — `src/memory-palace/schema.cypher` is regenerated
    // by the graph-store orchestrator (`zig build graphstore-schema`).
    try runArchiformPass(io, arena, &err_w);

    const t_end = std.Io.Clock.now(.real, io);
    const duration_ns: i96 = t_start.durationTo(t_end).nanoseconds;
    const duration_ms: i64 = @intCast(@divTrunc(duration_ns, std.time.ns_per_ms));
    try logKV(&err_w, .{
        .{ "phase", "done" },
        .{ "duration_ms", duration_ms },
        .{ "schema_fp", schema_fp },
    });
    try err_w.interface.flush();
}

pub const GeneratorCtx = struct {
    io: std.Io,
    arena: std.mem.Allocator,
    ts_header: []const u8,
    schema_fp: []const u8,
    stderr: *std.Io.File.Writer,

    /// Write a generated output file with provenance prepended. The
    /// header_kind selects the comment-leader style; the body is the
    /// generator's canonical text. Emits an `output-written` log.
    pub fn writeOutput(
        self: *const GeneratorCtx,
        path: []const u8,
        body: []const u8,
        header_kind: HeaderKind,
    ) !void {
        const header = switch (header_kind) {
            .ts => self.ts_header,
        };
        var file = try std.Io.Dir.cwd().createFile(self.io, path, .{ .truncate = true });
        defer file.close(self.io);
        var buf: [4096]u8 = undefined;
        var w = file.writer(self.io, &buf);
        try w.interface.writeAll(header);
        try w.interface.writeAll(body);
        try w.interface.flush();
        try logKV(self.stderr, .{
            .{ "phase", "output-written" },
            .{ "path", path },
            .{ "bytes", header.len + body.len },
        });
    }
};

/// Comment-leader style for generated output headers. graph-store/1 removed
/// the `.cypher` variant when the DDL generator moved to the graph-store
/// orchestrator; this core orchestrator only emits TS-style outputs.
pub const HeaderKind = enum { ts };

fn dispatch(
    name: []const u8,
    ctx: *const GeneratorCtx,
    gen_fn: *const fn (*const GeneratorCtx) anyerror!void,
) !void {
    try logKV(ctx.stderr, .{
        .{ "phase", "generator-dispatch" },
        .{ "target", name },
        .{ "schema_fp", ctx.schema_fp },
    });
    try gen_fn(ctx);
}

fn ensureDir(io: std.Io, path: []const u8) !void {
    std.Io.Dir.cwd().createDirPath(io, path) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
}

/// Build the provenance header (NFR9). `comment_prefix` selects the
/// comment-leader style (TS uses `//`).
fn buildHeader(allocator: std.mem.Allocator, comment_prefix: []const u8, schema_fp: []const u8) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        \\{0s} DO NOT EDIT — generated by tools/schema-gen.
        \\{0s} Provenance:
        \\{0s}   source-schema:     {1s}
        \\{0s}   source-schema-fp:  blake3:{2s}
        \\{0s}   schema-version:    {3s}
        \\{0s}   generator-id:      {4s}
        \\{0s}   generator-commit:  {5s}
        \\{0s} Regenerate via `bun run codegen`. Hand-edits will be overwritten.
        \\{0s} See docs/decisions/2026-04-25-json-schema-canonical.md (D-018) and
        \\{0s} docs/sprints/002-archiform-foundation/architecture-decisions.md (D-030).
        \\
        \\
    ,
        .{
            comment_prefix,
            SCHEMA_PATH,
            schema_fp,
            SCHEMA_VERSION,
            GENERATOR_ID,
            GENERATOR_COMMIT,
        },
    );
}

/// Per-archiform pass (Story 2.2).
/// Reads `schemas/memory-palace-0.1.0.json`, verifies its pin, parses it
/// (via the shared `codegen_common.loadArchiform` helper), then dispatches
/// the per-archiform generators for TS, Valibot, Zig, CLI, TS-client,
/// MCP-tools, and capabilities. graph-store/1: gen_cypher is NOT dispatched
/// here — schema.cypher is owned by the graph-store orchestrator.
fn runArchiformPass(io: std.Io, arena: std.mem.Allocator, err_w: *std.Io.File.Writer) !void {
    try logKV(err_w, .{
        .{ "phase", "archiform-pass-start" },
        .{ "schema", ARCHIFORM_SCHEMA_PATH },
    });

    // Read + pin-verify + parse the archiform schema (shared helper).
    const actx = try cc.loadArchiform(
        io,
        arena,
        ARCHIFORM_SCHEMA_PATH,
        ARCHIFORM_PIN_PATH,
        ARCHIFORM_SCHEMA_VERSION,
        err_w,
    );

    try logKV(err_w, .{
        .{ "phase", "archiform-generator-dispatch" },
        .{ "target", "gen_ts" },
        .{ "schema_fp", actx.schema_fp },
    });
    try gen_ts.generateArchiform(&actx);

    try logKV(err_w, .{
        .{ "phase", "archiform-generator-dispatch" },
        .{ "target", "gen_valibot" },
        .{ "schema_fp", actx.schema_fp },
    });
    try gen_valibot.generateArchiform(&actx);

    try logKV(err_w, .{
        .{ "phase", "archiform-generator-dispatch" },
        .{ "target", "gen_zig" },
        .{ "schema_fp", actx.schema_fp },
    });
    try gen_zig.generateArchiform(&actx);

    // Story 3.2 — gen_cli per-archiform pass (CLI projection spike).
    // Reads `x-actions` from the archiform schema and emits per-verb
    // dispatchers under `src/cli/generated/`. Currently scoped to the
    // `mint` verb (D-024 spike); Stories 3.3–3.4 expand the whitelist.
    try logKV(err_w, .{
        .{ "phase", "archiform-generator-dispatch" },
        .{ "target", "gen_cli" },
        .{ "schema_fp", actx.schema_fp },
    });
    try gen_cli.generateArchiform(&actx);

    // Story 4.1 — gen_ts_client per-archiform pass (TS client projection).
    // Reads `x-actions` from the archiform schema and emits a typed async
    // function per verb to `src/lib/generated/palace-client.ts`. Per D-034
    // the client wraps the D-007 store wrapper at one remove (via the
    // manifest-derived CLI + existing bridge subprocesses). Client never
    // imports @ladybugdb or kuzu directly (AC5) and never calls __rawQuery
    // (AC4 — D-007 audit invariant unchanged).
    try logKV(err_w, .{
        .{ "phase", "archiform-generator-dispatch" },
        .{ "target", "gen_ts_client" },
        .{ "schema_fp", actx.schema_fp },
    });
    try gen_ts_client.generateArchiform(&actx);

    // Story 4.2 — gen_mcp_tools per-archiform pass (MCP tool spec projection).
    // Reads `x-actions` from the archiform schema and emits one MCP tool spec
    // per verb to `src/lib/generated/palace-mcp-tools.ts`. Per AC6 the file
    // imports ONLY from `./palace-client.js` (Story 4.1) — never from the
    // store directly. Per AC4 actions whose `attributes.requiresConfirmation`
    // is true surface MCP elicitation (`server.elicitInput` form-mode) rather
    // than executing on first call.
    try logKV(err_w, .{
        .{ "phase", "archiform-generator-dispatch" },
        .{ "target", "gen_mcp_tools" },
        .{ "schema_fp", actx.schema_fp },
    });
    try gen_mcp_tools.generateArchiform(&actx);

    // gen_capabilities per-archiform pass — projects `x-capabilities` (if
    // present) into a typed requirements manifest the resolver consumes. No-op
    // (logs skip) when the schema declares no capability block, so wiring it in
    // is additive. Spec: docs/decisions/2026-05-31-capabilities-schema-vocabulary.md.
    try logKV(err_w, .{
        .{ "phase", "archiform-generator-dispatch" },
        .{ "target", "gen_capabilities" },
        .{ "schema_fp", actx.schema_fp },
    });
    try gen_capabilities.generateArchiform(&actx);

    try logKV(err_w, .{
        .{ "phase", "archiform-pass-done" },
        .{ "schema", ARCHIFORM_SCHEMA_PATH },
    });
}
