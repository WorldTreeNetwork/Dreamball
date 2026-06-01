//! graph-store schema-gen orchestrator (graph-store/1, Dreamball-9dq).
//!
//! Regenerates `src/memory-palace/schema.cypher` — the Memory Palace
//! graph DDL — from the archiform schema `schemas/memory-palace-0.1.0.json`.
//!
//! WHY THIS EXISTS SEPARATELY from `tools/schema-gen`:
//!   The protocol core's schema-gen must not know about the graph store's
//!   DDL (the §2 leak). gen_cypher used to be dispatched by the core
//!   orchestrator, which meant the core exe compiled the graph DDL. That
//!   dependency is severed here: gen_cypher lives next to this file and is
//!   compiled only by this graph-store-owned exe. The core exe no longer
//!   emits schema.cypher.
//!
//! Run: `zig build graphstore-schema` (via `bun run codegen`, which runs
//! `zig build schemagen` first for the TS/Valibot/CBOR outputs, then this
//! step for the Cypher DDL).
//!
//! The shared schema-read + pin-verify + structured-log helpers live in
//! `tools/codegen-common/codegen_common.zig` (the `codegen_common`
//! module), shared with the core orchestrator so both produce identical
//! provenance headers — preserving cypher byte-equivalence (AC2).

const std = @import("std");
const cc = @import("codegen_common");
const gen_cypher = @import("gen_cypher.zig");

const ARCHIFORM_SCHEMA_PATH = "schemas/memory-palace-0.1.0.json";
const ARCHIFORM_PIN_PATH = "schemas/.pins/memory-palace-0.1.0.fp";
const ARCHIFORM_SCHEMA_VERSION = "0.1.0";
const OUT_DIR = "src/memory-palace";

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

    try cc.logKV(&err_w, .{
        .{ "phase", "graphstore-pass-start" },
        .{ "schema", ARCHIFORM_SCHEMA_PATH },
    });

    // Ensure the output directory exists (it is committed in-repo, but
    // guard so a fresh checkout / clean tree still works).
    std.Io.Dir.cwd().createDirPath(io, OUT_DIR) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    // Read + pin-verify + parse the archiform schema (shared helper).
    const actx = try cc.loadArchiform(
        io,
        arena,
        ARCHIFORM_SCHEMA_PATH,
        ARCHIFORM_PIN_PATH,
        ARCHIFORM_SCHEMA_VERSION,
        &err_w,
    );

    try cc.logKV(&err_w, .{
        .{ "phase", "generator-dispatch" },
        .{ "target", "gen_cypher" },
        .{ "schema_fp", actx.schema_fp },
    });
    try gen_cypher.generateArchiform(&actx);

    const t_end = std.Io.Clock.now(.real, io);
    const duration_ns: i96 = t_start.durationTo(t_end).nanoseconds;
    const duration_ms: i64 = @intCast(@divTrunc(duration_ns, std.time.ns_per_ms));
    try cc.logKV(&err_w, .{
        .{ "phase", "done" },
        .{ "duration_ms", duration_ms },
        .{ "schema_fp", actx.schema_fp },
    });
    try err_w.interface.flush();
}
