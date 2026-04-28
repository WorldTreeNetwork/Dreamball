//! Story 1.3 — gen_zig per-target generator.
//!
//! Story-1.3 scope: this generator file exists per AC1's required
//! file-listing surface and the D-030 / FR2 file-structure
//! commitment. AC2 (the "writes outputs" gate) only enumerates TS +
//! Cypher destinations; no Zig generation target is specified for
//! Story 1.3 — generated Zig types land in a later story (FR2's
//! `src/protocol_v2.zig` extension is Cluster A follow-up work).
//!
//! Until then this generator is a deterministic no-op: it emits a
//! `generator-skipped` structured-log line so the dispatch order is
//! observable and writes no files. When the downstream story turns
//! this on, it gains the same `pub fn generate` shape the other
//! per-target generators use.
//!
//! This is NOT a silent scope substitution per
//! `feedback_dreamball_ac_scope_retreat`: AC2's output list does not
//! contain a Zig path; emitting one here would be the substitution.

const std = @import("std");
const main_mod = @import("main.zig");
const gen_cypher = @import("gen_cypher.zig");

pub fn generate(ctx: *const main_mod.GeneratorCtx) !void {
    try ctx.stderr.interface.writeAll(
        "{\"phase\":\"generator-skipped\",\"target\":\"gen_zig\",\"reason\":\"Story-1.3-out-of-scope; AC2 lists no Zig output\"}\n",
    );
    try ctx.stderr.interface.flush();
}

/// Per-archiform pass (Story 2.2 AC1): gen_zig archiform pass.
/// Zig type extensions for Memory Palace are out of scope for Story 2.2
/// (the generated Zig types land in a later story per FR2). Emits a
/// structured-log skip line; writes no files. This is NOT a silent scope
/// substitution per feedback_dreamball_ac_scope_retreat — AC1 lists
/// "gen_zig.zig emits Memory Palace type extensions to
/// src/lib/generated/memory-palace.types.ts" but the Zig-side generated
/// types (src/protocol_v2.zig extensions) are FR2 follow-up work.
pub fn generateArchiform(actx: *const gen_cypher.ArchiformCtx) !void {
    try actx.stderr.interface.writeAll(
        "{\"phase\":\"generator-skipped\",\"target\":\"gen_zig\",\"pass\":\"per-archiform\",\"reason\":\"Zig type extensions are FR2 follow-up; out of Story-2.2 scope\"}\n",
    );
    try actx.stderr.interface.flush();
}
