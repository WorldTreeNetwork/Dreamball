//! Legacy v3 `ball.action` wire-string constants + encoder — retained ONLY
//! for the palace CLI verbs (mint / add-room / move / rename-mythos /
//! inscribe) that still author format-version-3 palace actions.
//!
//! WHY THIS FILE EXISTS (Dreamball-y4t.15, 2026-08-07): the core substrate
//! (`src/protocol_v2.zig`, `src/envelope_v2.zig`) dropped v3 `ball.action`
//! support entirely — `ActionKind` and the v3 `encodeAction` were deleted.
//! The owner's decision: Memory Palace is being extracted to its own repo
//! (Dreamball-etk) and v3 is the CLOSED palace profile, not a substrate
//! concern, so it does not belong in the shared protocol/envelope core.
//!
//! The five palace CLI verbs in this directory still mint v3 envelopes today
//! (no v4-authoring migration has landed for them — that is separate work,
//! tracked alongside the A2 CLI-encoder story). Until the palace extraction
//! lands, SOMETHING has to keep producing the v3 wire bytes these verbs
//! already emit, or `zig build` breaks outright. This module is a verbatim
//! copy of what was deleted from `envelope_v2.zig`, narrowed to exactly the
//! 5 wire strings the CLI uses. It produces byte-identical output to the old
//! `envelope_v2.encodeAction` / `v2.ActionKind` pair.
//!
//! When Dreamball-etk extracts the palace CLI, this file moves with it
//! unchanged — it was written to be lift-and-shift-able.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const v2 = dreamball.protocol_v2;
const zbor = @import("zbor");
const dcbor = dreamball.dcbor;

/// The subset of the old 9-value `ActionKind` enum's wire strings that the
/// palace CLI verbs actually construct. (The other 4 — "aqueduct-created",
/// "inscription-orphaned", "inscription-pending-embedding" — had no CLI
/// caller and are not reproduced here; they lived only in
/// `src/protocol_v2.zig`'s enum and its own unit test.)
pub const Kind = struct {
    pub const palace_minted: []const u8 = "palace-minted";
    pub const room_added: []const u8 = "room-added";
    pub const avatar_inscribed: []const u8 = "avatar-inscribed";
    pub const move: []const u8 = "move";
    pub const true_naming: []const u8 = "true-naming";
};

/// v3 `ball.action` encoder — the closed palace profile (5-key core map,
/// `format-version` pinned to the literal 3). Verbatim copy of the deleted
/// `envelope_v2.encodeAction`; see that function's former doc comment
/// (git history) for the full core/attribute key-ordering rationale.
pub fn encodeActionV3(allocator: Allocator, a: v2.Action) ![]u8 {
    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    // parent_hashes is in the core map, not attributes
    var ac: u64 = a.deps.len + a.nacks.len;
    if (a.target_fp != null) ac += 1;
    if (a.timestamp != null) ac += 1;
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    // v3 wire shape (5-key core map). `a.kind` must be one of the `Kind.*`
    // wire strings above.
    // Core keys sorted (len asc, lex):
    //   "type"(4), "actor"(5), "action-kind"(11), "parent-hashes"(13), "format-version"(14)
    try zbor.builder.writeMap(w, 5);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.Action.type_string);
    try zbor.builder.writeTextString(w, "actor");
    try zbor.builder.writeByteString(w, &a.actor);
    try zbor.builder.writeTextString(w, "action-kind");
    try zbor.builder.writeTextString(w, a.kind);
    try zbor.builder.writeTextString(w, "parent-hashes");
    try zbor.builder.writeArray(w, a.parent_hashes.len);
    for (a.parent_hashes) |ph| try zbor.builder.writeByteString(w, &ph);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, 3);

    // Attributes sorted: "deps"(4), "nacks"(5), "target-fp"(9), "timestamp"(9)
    // At len 9: "target-fp" < "timestamp" lex
    for (a.deps) |d| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "deps");
        try zbor.builder.writeByteString(w, &d);
    }
    for (a.nacks) |n| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "nacks");
        try zbor.builder.writeByteString(w, &n);
    }
    if (a.target_fp) |tfp| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "target-fp");
        try zbor.builder.writeByteString(w, &tfp);
    }
    if (a.timestamp) |ts| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "timestamp");
        try zbor.builder.writeTag(w, dcbor.Tag.epoch_time);
        try zbor.builder.writeInt(w, @intCast(ts));
    }
    return ai.toOwnedSlice();
}
