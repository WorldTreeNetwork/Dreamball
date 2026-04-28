//! Story 1.3 — JSON-Schema-canonical generator orchestrator.
//!
//! Repurpose of the legacy `tools/schema-gen/main.zig` (now at
//! `tools/schema-gen/legacy/main.zig` per D-030 Option A). This
//! orchestrator:
//!
//!   1. Reads `schemas/root-2.0.0.json` from disk.
//!   2. Verifies the pin file `schemas/.pins/root-2.0.0.fp` matches
//!      blake3 of the schema bytes (the upstream gate is also wired
//!      via `bun run codegen` → `scripts/schemas-verify.ts`; this
//!      orchestrator re-runs the check so the structured-log entry
//!      surfaces in `zig build schemagen` output as well).
//!   3. Dispatches to five per-target generators in deterministic
//!      order: gen_zig, gen_ts, gen_valibot, gen_cbor, gen_cypher.
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
//! Per AC1 the new generator surface is exactly:
//!   main.zig, gen_zig.zig, gen_ts.zig, gen_valibot.zig,
//!   gen_cbor.zig, gen_cypher.zig, legacy/.
//! Provenance helpers (NFR9) are intentionally folded into this file
//! rather than living in a sibling `provenance.zig` so the AC1 grep
//! audit succeeds.
//!
//! Run: `zig build schemagen` (typically via `bun run codegen`,
//! which also runs `scripts/schemas-verify.ts` first).

const std = @import("std");
const gen_zig = @import("gen_zig.zig");
const gen_ts = @import("gen_ts.zig");
const gen_valibot = @import("gen_valibot.zig");
const gen_cbor = @import("gen_cbor.zig");
const gen_cypher = @import("gen_cypher.zig");

const SCHEMA_PATH = "schemas/root-2.0.0.json";
const PIN_PATH = "schemas/.pins/root-2.0.0.fp";
const SCHEMA_VERSION = "2.0.0";
const TS_OUT_DIR = "src/lib/generated";
const CYPHER_OUT_DIR = "src/memory-palace";

// ── Per-archiform schema paths (Story 2.2) ────────────────────────────────────
const ARCHIFORM_SCHEMA_PATH = "schemas/memory-palace-0.1.0.json";
const ARCHIFORM_PIN_PATH = "schemas/.pins/memory-palace-0.1.0.fp";
const ARCHIFORM_SCHEMA_VERSION = "0.1.0";

/// Generator identity baked at compile time. Deterministic per-binary
/// per NFR9 — only the GENERATOR_COMMIT varies in provenance text.
pub const GENERATOR_ID = "tools/schema-gen@2026-04-28";
pub const GENERATOR_COMMIT = "story-1.3-initial";

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
    const schema_fp = blake3Hex(schema_bytes, &schema_fp_buf);
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

    // 4) Build provenance headers (NFR9). Two leaders so TS and
    //    Cypher outputs both lead with comment-syntax-correct text.
    const ts_header = try buildHeader(arena, "//", schema_fp);
    const cypher_header = try buildHeader(arena, "--", schema_fp);

    // 5) Dispatch generators in deterministic order.
    try ensureDir(io, TS_OUT_DIR);
    try ensureDir(io, CYPHER_OUT_DIR);

    const ctx = GeneratorCtx{
        .io = io,
        .arena = arena,
        .ts_header = ts_header,
        .cypher_header = cypher_header,
        .schema_fp = schema_fp,
        .stderr = &err_w,
    };

    try dispatch("gen_zig", &ctx, gen_zig.generate);
    try dispatch("gen_ts", &ctx, gen_ts.generate);
    try dispatch("gen_valibot", &ctx, gen_valibot.generate);
    try dispatch("gen_cbor", &ctx, gen_cbor.generate);
    try dispatch("gen_cypher", &ctx, gen_cypher.generate);

    // ── Per-archiform pass (Story 2.2) ────────────────────────────────────────
    // Walk non-root schemas (currently only memory-palace-0.1.0.json) and
    // dispatch the per-archiform generators. The archiform pass overwrites
    // `src/memory-palace/schema.cypher` with a provenance header naming the
    // archiform schema/pin as source (see gen_cypher.zig for the normalization
    // documented in tests/codegen/normalizations/cypher-header-source-schema.md).
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
    cypher_header: []const u8,
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
            .cypher => self.cypher_header,
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

pub const HeaderKind = enum { ts, cypher };

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

fn blake3Hex(bytes: []const u8, out: *[64]u8) []const u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &hash, .{});
    const hex_alphabet = "0123456789abcdef";
    for (hash, 0..) |b, i| {
        out[i * 2] = hex_alphabet[b >> 4];
        out[i * 2 + 1] = hex_alphabet[b & 0x0f];
    }
    return out[0..64];
}

/// Build the provenance header (NFR9). `comment_prefix` selects
/// TS-style (`//`) vs Cypher-style (`--`).
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

/// Public re-export of logKV for use by per-archiform generators (e.g. gen_cypher.zig).
pub fn logKVPub(w: *std.Io.File.Writer, pairs: anytype) !void {
    try logKV(w, pairs);
}

/// Per-archiform pass (Story 2.2).
/// Reads `schemas/memory-palace-0.1.0.json`, verifies its pin, parses it,
/// then dispatches per-archiform generators for TS, Valibot, Zig, and Cypher.
fn runArchiformPass(io: std.Io, arena: std.mem.Allocator, err_w: *std.Io.File.Writer) !void {
    try logKV(err_w, .{
        .{ "phase", "archiform-pass-start" },
        .{ "schema", ARCHIFORM_SCHEMA_PATH },
    });

    // 1) Read archiform schema.
    const schema_bytes = std.Io.Dir.cwd().readFileAlloc(io, ARCHIFORM_SCHEMA_PATH, arena, .limited(1 << 22)) catch |e| {
        try logErr(err_w, "archiform-schema-read-failed", ARCHIFORM_SCHEMA_PATH, @errorName(e));
        return e;
    };
    var schema_fp_buf: [64]u8 = undefined;
    const schema_fp = blake3Hex(schema_bytes, &schema_fp_buf);
    try logKV(err_w, .{
        .{ "phase", "archiform-schema-read" },
        .{ "path", ARCHIFORM_SCHEMA_PATH },
        .{ "fp", schema_fp },
        .{ "bytes", schema_bytes.len },
    });

    // 2) Pin verify.
    const pin_bytes = std.Io.Dir.cwd().readFileAlloc(io, ARCHIFORM_PIN_PATH, arena, .limited(128)) catch |e| {
        try logErr(err_w, "archiform-pin-verify", ARCHIFORM_PIN_PATH, @errorName(e));
        return e;
    };
    const pin_text = std.mem.trim(u8, pin_bytes, &std.ascii.whitespace);
    if (!std.mem.eql(u8, pin_text, schema_fp)) {
        try logKV(err_w, .{
            .{ "phase", "archiform-pin-verify" },
            .{ "status", "mismatch" },
            .{ "expected", pin_text },
            .{ "actual", schema_fp },
            .{ "schema", ARCHIFORM_SCHEMA_PATH },
        });
        return error.ArchiformSchemaPinMismatch;
    }
    try logKV(err_w, .{
        .{ "phase", "archiform-pin-verify" },
        .{ "status", "match" },
        .{ "fp", schema_fp },
    });

    // 3) Parse schema.
    const schema_value = std.json.parseFromSliceLeaky(std.json.Value, arena, schema_bytes, .{}) catch |e| {
        try logErr(err_w, "archiform-schema-parse-failed", ARCHIFORM_SCHEMA_PATH, @errorName(e));
        return e;
    };

    // 4) Build ArchiformCtx and dispatch per-archiform generators.
    const actx = gen_cypher.ArchiformCtx{
        .io = io,
        .arena = arena,
        .schema_path = ARCHIFORM_SCHEMA_PATH,
        .schema_fp = schema_fp,
        .schema_version = ARCHIFORM_SCHEMA_VERSION,
        .pin_path = ARCHIFORM_PIN_PATH,
        .schema_value = schema_value,
        .stderr = err_w,
        .generator_id = GENERATOR_ID,
        .generator_commit = GENERATOR_COMMIT,
    };

    try logKV(err_w, .{
        .{ "phase", "archiform-generator-dispatch" },
        .{ "target", "gen_cypher" },
        .{ "schema_fp", schema_fp },
    });
    try gen_cypher.generateArchiform(&actx);

    try logKV(err_w, .{
        .{ "phase", "archiform-generator-dispatch" },
        .{ "target", "gen_ts" },
        .{ "schema_fp", schema_fp },
    });
    try gen_ts.generateArchiform(&actx);

    try logKV(err_w, .{
        .{ "phase", "archiform-generator-dispatch" },
        .{ "target", "gen_valibot" },
        .{ "schema_fp", schema_fp },
    });
    try gen_valibot.generateArchiform(&actx);

    try logKV(err_w, .{
        .{ "phase", "archiform-generator-dispatch" },
        .{ "target", "gen_zig" },
        .{ "schema_fp", schema_fp },
    });
    try gen_zig.generateArchiform(&actx);

    try logKV(err_w, .{
        .{ "phase", "archiform-pass-done" },
        .{ "schema", ARCHIFORM_SCHEMA_PATH },
    });
}

/// Emit one JSON line to stderr. Tuple of (key, value) pairs; values are
/// rendered with std.json escaping. Numbers render numerically.
fn logKV(w: *std.Io.File.Writer, pairs: anytype) !void {
    try w.interface.writeAll("{");
    inline for (pairs, 0..) |pair, i| {
        if (i > 0) try w.interface.writeAll(",");
        try writeJsonString(w, pair[0]);
        try w.interface.writeAll(":");
        try writeJsonValue(w, pair[1]);
    }
    try w.interface.writeAll("}\n");
    try w.interface.flush();
}

fn logErr(w: *std.Io.File.Writer, phase: []const u8, path: []const u8, err: []const u8) !void {
    try logKV(w, .{
        .{ "phase", phase },
        .{ "path", path },
        .{ "error", err },
    });
}

fn writeJsonString(w: *std.Io.File.Writer, s: []const u8) !void {
    try w.interface.writeAll("\"");
    for (s) |c| {
        switch (c) {
            '"' => try w.interface.writeAll("\\\""),
            '\\' => try w.interface.writeAll("\\\\"),
            '\n' => try w.interface.writeAll("\\n"),
            '\r' => try w.interface.writeAll("\\r"),
            '\t' => try w.interface.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    var buf: [8]u8 = undefined;
                    const slice = try std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c});
                    try w.interface.writeAll(slice);
                } else {
                    try w.interface.writeAll(&[_]u8{c});
                }
            },
        }
    }
    try w.interface.writeAll("\"");
}

fn writeJsonValue(w: *std.Io.File.Writer, v: anytype) !void {
    const T = @TypeOf(v);
    const info = @typeInfo(T);
    switch (info) {
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) {
                try writeJsonString(w, v);
                return;
            }
            // String literal *const [N:0]u8 — coerce via std.mem.span.
            try writeJsonString(w, std.mem.span(@as([*:0]const u8, @ptrCast(v))));
        },
        .array => |a| {
            if (a.child == u8) {
                try writeJsonString(w, &v);
                return;
            }
            @compileError("logKV value: only string + numeric scalars supported");
        },
        .int, .comptime_int => {
            var buf: [32]u8 = undefined;
            const slice = try std.fmt.bufPrint(&buf, "{d}", .{v});
            try w.interface.writeAll(slice);
        },
        .float, .comptime_float => {
            var buf: [32]u8 = undefined;
            const slice = try std.fmt.bufPrint(&buf, "{d}", .{v});
            try w.interface.writeAll(slice);
        },
        else => @compileError("logKV value: unsupported type " ++ @typeName(T)),
    }
}
