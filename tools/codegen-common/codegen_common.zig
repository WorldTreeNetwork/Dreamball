//! Neutral shared codegen primitives (graph-store/1, Dreamball-9dq).
//!
//! WHY THIS MODULE EXISTS — closing the §2 DDL leak.
//!
//! Before this module, `ArchiformCtx` (the parsed-schema + provenance
//! context every per-archiform generator consumes) lived inside
//! `gen_cypher.zig`, and the structured-log + blake3 + schema-read
//! helpers lived inside the core orchestrator `tools/schema-gen/main.zig`.
//! That coupled two things that must not be coupled:
//!
//!   1. The core protocol schema-gen (`tools/schema-gen`) imported
//!      `gen_cypher` — so the protocol core "knew about" the graph
//!      store's DDL. That is the §2 leak.
//!   2. Every other per-archiform generator imported `gen_cypher` just
//!      to name the `ArchiformCtx` type — a dependency on the graph
//!      store for an unrelated reason.
//!
//! This module is the neutral seam both sides depend on instead. It owns:
//!   - `ArchiformCtx` — the per-archiform generator context.
//!   - `loadArchiform` — read schema + verify pin + parse, returning a
//!     ready `ArchiformCtx`. Shared by the core orchestrator's archiform
//!     pass AND the graph-store orchestrator (`tools/graphstore-schema`).
//!   - `logKV` / `logErr` — the NFR10 structured-log emitters.
//!   - `blake3Hex` — the provenance fingerprint helper (NFR9).
//!   - `GENERATOR_ID` / `GENERATOR_COMMIT` — deterministic generator
//!     identity baked into every provenance header.
//!
//! Neither the core schema-gen nor the graph-store schema-gen imports the
//! other; both import this module. `gen_cypher.zig` now lives under
//! `tools/graphstore-schema/` and imports only this module.
//!
//! See docs/decisions/2026-05-31-capability-provider-model.md (graph-store
//! §2) and CLAUDE.md "The cross-runtime invariant".

const std = @import("std");

/// Generator identity baked at compile time. Deterministic per-binary
/// per NFR9 — only the GENERATOR_COMMIT varies in provenance text.
/// Canonical home: this module. The core orchestrator and the
/// graph-store orchestrator both read these so the provenance headers
/// they emit stay identical (preserving cypher byte-equivalence).
pub const GENERATOR_ID = "tools/schema-gen@2026-04-28";
pub const GENERATOR_COMMIT = "story-1.3-initial";

// ── Per-archiform generator context ───────────────────────────────────────────

/// ArchiformCtx carries the parsed schema JSON and per-archiform
/// provenance strings needed by the per-archiform generators
/// (gen_cypher, gen_ts, gen_valibot, gen_zig, gen_cli, gen_ts_client,
/// gen_mcp_tools, gen_capabilities).
///
/// Previously defined in gen_cypher.zig; relocated here so the type does
/// not drag a dependency on the graph-store DDL generator into every
/// consumer (graph-store/1 §2 decoupling).
pub const ArchiformCtx = struct {
    io: std.Io,
    arena: std.mem.Allocator,
    schema_path: []const u8,
    schema_fp: []const u8,
    schema_version: []const u8,
    pin_path: []const u8,
    schema_value: std.json.Value,
    stderr: *std.Io.File.Writer,
    generator_id: []const u8,
    generator_commit: []const u8,
};

/// Read an archiform schema, verify its pin against the blake3 of the
/// schema bytes, parse it, and return a ready `ArchiformCtx`.
///
/// This is the shared "read helper" extracted from the core
/// orchestrator's archiform pass so the graph-store orchestrator can
/// reproduce the exact same context without importing core `main.zig`.
/// Emits `archiform-schema-read` and `archiform-pin-verify` structured-log
/// lines (NFR10) to `stderr`.
///
/// The returned `schema_fp` is duped into `arena` so it outlives the
/// stack buffer used to compute it.
pub fn loadArchiform(
    io: std.Io,
    arena: std.mem.Allocator,
    schema_path: []const u8,
    pin_path: []const u8,
    schema_version: []const u8,
    stderr: *std.Io.File.Writer,
) !ArchiformCtx {
    // 1) Read archiform schema.
    const schema_bytes = std.Io.Dir.cwd().readFileAlloc(io, schema_path, arena, .limited(1 << 22)) catch |e| {
        try logErr(stderr, "archiform-schema-read-failed", schema_path, @errorName(e));
        return e;
    };
    var schema_fp_buf: [64]u8 = undefined;
    const schema_fp = try arena.dupe(u8, blake3Hex(schema_bytes, &schema_fp_buf));
    try logKV(stderr, .{
        .{ "phase", "archiform-schema-read" },
        .{ "path", schema_path },
        .{ "fp", schema_fp },
        .{ "bytes", schema_bytes.len },
    });

    // 2) Pin verify.
    const pin_bytes = std.Io.Dir.cwd().readFileAlloc(io, pin_path, arena, .limited(128)) catch |e| {
        try logErr(stderr, "archiform-pin-verify", pin_path, @errorName(e));
        return e;
    };
    const pin_text = std.mem.trim(u8, pin_bytes, &std.ascii.whitespace);
    if (!std.mem.eql(u8, pin_text, schema_fp)) {
        try logKV(stderr, .{
            .{ "phase", "archiform-pin-verify" },
            .{ "status", "mismatch" },
            .{ "expected", pin_text },
            .{ "actual", schema_fp },
            .{ "schema", schema_path },
        });
        return error.ArchiformSchemaPinMismatch;
    }
    try logKV(stderr, .{
        .{ "phase", "archiform-pin-verify" },
        .{ "status", "match" },
        .{ "fp", schema_fp },
    });

    // 3) Parse schema.
    const schema_value = std.json.parseFromSliceLeaky(std.json.Value, arena, schema_bytes, .{}) catch |e| {
        try logErr(stderr, "archiform-schema-parse-failed", schema_path, @errorName(e));
        return e;
    };

    return ArchiformCtx{
        .io = io,
        .arena = arena,
        .schema_path = schema_path,
        .schema_fp = schema_fp,
        .schema_version = schema_version,
        .pin_path = pin_path,
        .schema_value = schema_value,
        .stderr = stderr,
        .generator_id = GENERATOR_ID,
        .generator_commit = GENERATOR_COMMIT,
    };
}

// ── Provenance fingerprint (NFR9) ─────────────────────────────────────────────

/// Render the lowercase-hex blake3 of `bytes` into `out` and return the
/// 64-byte slice. Caller owns the buffer's lifetime.
pub fn blake3Hex(bytes: []const u8, out: *[64]u8) []const u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &hash, .{});
    const hex_alphabet = "0123456789abcdef";
    for (hash, 0..) |b, i| {
        out[i * 2] = hex_alphabet[b >> 4];
        out[i * 2 + 1] = hex_alphabet[b & 0x0f];
    }
    return out[0..64];
}

// ── Structured logging (NFR10) ────────────────────────────────────────────────

/// Emit one JSON line to stderr. Tuple of (key, value) pairs; values are
/// rendered with std.json escaping. Numbers render numerically.
pub fn logKV(w: *std.Io.File.Writer, pairs: anytype) !void {
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

pub fn logErr(w: *std.Io.File.Writer, phase: []const u8, path: []const u8, err: []const u8) !void {
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
