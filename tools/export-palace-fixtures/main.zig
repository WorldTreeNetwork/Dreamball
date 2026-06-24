//! export-palace-fixtures — regenerate the 6 negative-test palace fixtures.
//!
//! Run via:
//!   zig build export-palace-fixtures
//!
//! Background
//! ----------
//! `scripts/cli-smoke.sh` runs `jelly verify <bundle>` against six committed
//! palace fixtures under `tests/fixtures/`. Each fixture is a signed,
//! content-addressed palace bundle deliberately broken so that exactly ONE of
//! palace_verify's structural invariants (a)–(e) trips, with a specific stderr
//! substring asserted by the smoke script.
//!
//! The original fixtures were hand-rolled (throwaway python3 dCBOR + manual
//! Blake3) using the OLD `jelly.*` wire tags. After the clean-break rename to
//! `ball.*`, `jelly verify` no longer recognises their rooms/agents/etc., so it
//! stops at invariant (a) "no rooms" for ALL of them — producing false
//! coincidental passes and one hard failure (palace-two-agents AC6).
//!
//! This tool replaces the hand-rolled bytes with a PROPER, durable generator:
//! it mints a real valid `ball.*` palace in-process via the same `dreamball`
//! module encoders the CLI uses (envelope.encodeDreamBall / envelope_v2.encode*
//! / signer), then applies one targeted mutation per fixture. That guarantees
//! valid signatures and correct content-addressed Blake3 fingerprints, CAS
//! filenames, and cross-envelope references everywhere except the single
//! intentional break.
//!
//! Why a standalone tool (not the bun-bridged `palace mint`)?
//! ----------------------------------------------------------
//! The CLI `palace mint` spawns a bun bridge whose sole job is to MIRROR the
//! envelopes into LadybugDB; the CAS bytes + bundle are produced by Zig before
//! the bridge runs (see src/cli/internal/mint.zig). Fixtures need only the CAS +
//! bundle, so this tool replicates that Zig-side production directly — exactly
//! the pattern `tools/export-envelope-fixtures` uses to reach the encoders via
//! the `dreamball` module.
//!
//! Each fixture (and the invariant it trips)
//! -----------------------------------------
//!   palace-no-rooms          (a) "palace has no rooms"     — room field omitted
//!   palace-two-agents        (b) "multiple Agents"         — second agent added
//!   palace-orphan-action     (c) "unresolvable parent-hash"— action parent not in CAS
//!   palace-broken-mythos     (d) "unresolvable predecessor"— non-genesis mythos,
//!                                                            predecessor = sentinel
//!   palace-head-hashes-wrong (e) "not a leaf"              — timeline head points at
//!                                                            a non-leaf action
//!   palace-oracle-actor-mismatch  (AC10, skipped: no oracle.key) — valid ball.*
//!                                                            palace, kept consistent
//!
//! NOTE: ML-DSA-87 keypairs are generated with fresh randomness, so the exact
//! fixture bytes differ on each run. That is fine: the fixtures are committed
//! snapshots (the originals were too). What matters is structural validity and
//! the single intentional break — both reproduced deterministically by shape.

const std = @import("std");
const Allocator = std.mem.Allocator;

const dreamball = @import("dreamball");
const protocol = dreamball.protocol;
const v2 = dreamball.protocol_v2;
const envelope = dreamball.envelope;
const envelope_v2 = dreamball.envelope_v2;
const signer = dreamball.signer;
const Fingerprint = dreamball.fingerprint.Fingerprint;

// The archiform registry is read from disk at runtime (the generator runs with
// cwd = repo root via `zig build`). @embedFile cannot reach outside the tool's
// package path, and the registry bytes only need to be content-addressed into
// the palace's `contains` set — exact parity with the CLI mint snapshot is not
// required for a structural fixture.
const REGISTRY_PATH = "src/memory-palace/seed/archiform-registry.json";

const FIXTURES_ROOT = "tests/fixtures";

// A fixed clock value so action/timeline timestamps are stable in shape.
const NOW_MS: i64 = 1_700_000_000_000;

// ── Blake3 helpers (mirror src/cli/internal/mint.zig) ─────────────────────────

fn blake3Hash(bytes: []const u8) [32]u8 {
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(bytes);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

fn hexArray(bytes: *const [32]u8) [64]u8 {
    const charset = "0123456789abcdef";
    var result: [64]u8 = undefined;
    for (bytes, 0..) |b, i| {
        result[i * 2] = charset[b >> 4];
        result[i * 2 + 1] = charset[b & 0xF];
    }
    return result;
}

// ── Signed-action encoder (mirror src/cli/internal/mint.zig encodeSignedAction) ─
// v2.Action carries no signatures field, so we emit the "signed" attribute pairs
// directly. Byte-for-byte identical to the CLI path so fps match what verify
// would compute for a real minted action.
fn encodeSignedAction(
    allocator: Allocator,
    a: v2.Action,
    signatures: []const protocol.Signature,
) ![]u8 {
    const zbor = @import("zbor");
    const dcbor = dreamball.dcbor;

    var ai = std.Io.Writer.Allocating.init(allocator);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);

    var ac: u64 = a.deps.len + a.nacks.len + signatures.len;
    if (a.target_fp != null) ac += 1;
    if (a.timestamp != null) ac += 1;
    try zbor.builder.writeArray(w, 1 + ac);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 5);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.Action.type_string);
    try zbor.builder.writeTextString(w, "actor");
    try zbor.builder.writeByteString(w, &a.actor);
    try zbor.builder.writeTextString(w, "action-kind");
    try zbor.builder.writeTextString(w, a.action_kind.toWireString());
    try zbor.builder.writeTextString(w, "parent-hashes");
    try zbor.builder.writeArray(w, a.parent_hashes.len);
    for (a.parent_hashes) |ph| try zbor.builder.writeByteString(w, &ph);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(v2.Action.format_version));

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
    for (signatures) |s| {
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, "signed");
        try zbor.builder.writeArray(w, 2);
        try zbor.builder.writeTextString(w, s.alg);
        try zbor.builder.writeByteString(w, s.value);
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

// ── CAS entry / bundle accumulator ────────────────────────────────────────────

const Entry = struct {
    fp: [32]u8,
    bytes: []const u8, // gpa-owned
};

/// Accumulates envelopes + the ordered bundle fp list for one fixture, then
/// writes them to disk: `<dir>/palace.bundle` (newline-delimited hex fps, line 0
/// = palace fp) and `<dir>/palace.cas/<hexfp>` (raw envelope bytes).
const FixtureWriter = struct {
    gpa: Allocator,
    entries: std.ArrayList(Entry),
    bundle: std.ArrayList([32]u8),

    fn init(gpa: Allocator) FixtureWriter {
        return .{ .gpa = gpa, .entries = .empty, .bundle = .empty };
    }

    fn deinit(self: *FixtureWriter) void {
        for (self.entries.items) |e| self.gpa.free(e.bytes);
        self.entries.deinit(self.gpa);
        self.bundle.deinit(self.gpa);
    }

    /// Add an envelope to the CAS (deduplicated by fp). Takes ownership of bytes.
    fn cas(self: *FixtureWriter, fp: [32]u8, bytes: []const u8) !void {
        for (self.entries.items) |e| {
            if (std.mem.eql(u8, &e.fp, &fp)) {
                self.gpa.free(bytes);
                return;
            }
        }
        try self.entries.append(self.gpa, .{ .fp = fp, .bytes = bytes });
    }

    /// Append an fp to the ordered bundle manifest.
    fn bundleLine(self: *FixtureWriter, fp: [32]u8) !void {
        try self.bundle.append(self.gpa, fp);
    }

    fn write(self: *FixtureWriter, dir_name: []const u8) !void {
        const root = std.Io.Dir.cwd();
        const ioh = std.Io.Threaded.global_single_threaded.io();

        const dir_path = try std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ FIXTURES_ROOT, dir_name });
        defer self.gpa.free(dir_path);
        const cas_path = try std.fmt.allocPrint(self.gpa, "{s}/palace.cas", .{dir_path});
        defer self.gpa.free(cas_path);

        // Clean any stale CAS files so the directory reflects exactly this run.
        root.deleteTree(ioh, cas_path) catch {};
        root.createDirPath(ioh, cas_path) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };

        // Write CAS envelopes.
        var cas_dir = try root.openDir(ioh, cas_path, .{});
        defer cas_dir.close(ioh);
        for (self.entries.items) |e| {
            const name = hexArray(&e.fp);
            var f = try cas_dir.createFile(ioh, &name, .{ .truncate = true });
            defer f.close(ioh);
            var buf: [4096]u8 = undefined;
            var w = f.writer(ioh, &buf);
            try w.interface.writeAll(e.bytes);
            try w.interface.flush();
        }

        // Write bundle manifest.
        var bundle_bytes: std.ArrayList(u8) = .empty;
        defer bundle_bytes.deinit(self.gpa);
        for (self.bundle.items) |fp| {
            const h = hexArray(&fp);
            try bundle_bytes.appendSlice(self.gpa, &h);
            try bundle_bytes.append(self.gpa, '\n');
        }
        const bundle_path = try std.fmt.allocPrint(self.gpa, "{s}/palace.bundle", .{dir_path});
        defer self.gpa.free(bundle_path);
        var bf = try root.createFile(ioh, bundle_path, .{ .truncate = true });
        defer bf.close(ioh);
        var bbuf: [4096]u8 = undefined;
        var bw = bf.writer(ioh, &bbuf);
        try bw.interface.writeAll(bundle_bytes.items);
        try bw.interface.flush();
    }
};

// ── Envelope builders (return gpa-owned bytes + fp) ────────────────────────────

const Built = struct { fp: [32]u8, bytes: []u8 };

fn buildOracleAgent(gpa: Allocator, keys: signer.HybridSigningKeys) !Built {
    var genesis_input: [40]u8 = undefined;
    @memcpy(genesis_input[0..32], &keys.ed25519_public);
    std.mem.writeInt(i64, genesis_input[32..40], NOW_MS, .little);
    const genesis_hash = blake3Hash(&genesis_input);

    var db = protocol.DreamBall{
        .stage = .seed,
        .identity = keys.ed25519_public,
        .identity_pq = keys.mldsa_public,
        .genesis_hash = genesis_hash,
        .revision = 0,
        .dreamball_type = .agent,
        .created = NOW_MS,
    };
    return signDreamBall(gpa, &db, keys);
}

fn buildRoomField(gpa: Allocator, keys: signer.HybridSigningKeys, name: []const u8) !Built {
    var db = protocol.DreamBall{
        .stage = .seed,
        .identity = keys.ed25519_public,
        .identity_pq = keys.mldsa_public,
        .genesis_hash = blake3Hash(name),
        .revision = 0,
        .dreamball_type = .field,
        .field_kind = "room",
        .name = name,
        .created = NOW_MS,
    };
    return signDreamBall(gpa, &db, keys);
}

/// Sign a DreamBall (ed25519 + ml-dsa-87) and return its content-addressed bytes.
fn signDreamBall(gpa: Allocator, db: *protocol.DreamBall, keys: signer.HybridSigningKeys) !Built {
    const unsigned = try envelope.encodeDreamBall(gpa, db.*);
    defer gpa.free(unsigned);
    const ed_sig = try signer.signEd25519(unsigned, keys.classical());
    const mldsa_sig = try signer.signMlDsa(gpa, unsigned, keys);
    defer gpa.free(mldsa_sig);
    const sigs = [_]protocol.Signature{
        .{ .alg = "ed25519", .value = &ed_sig },
        .{ .alg = "ml-dsa-87", .value = mldsa_sig },
    };
    db.signatures = &sigs;
    const bytes = try envelope.encodeDreamBall(gpa, db.*);
    return .{ .fp = blake3Hash(bytes), .bytes = bytes };
}

fn readFileAlloc(gpa: Allocator, path: []const u8) ![]u8 {
    const ioh = std.Io.Threaded.global_single_threaded.io();
    var file = try std.Io.Dir.cwd().openFile(ioh, path, .{});
    defer file.close(ioh);
    const stat = try file.stat(ioh);
    const size: usize = @intCast(stat.size);
    const bytes = try gpa.alloc(u8, size);
    errdefer gpa.free(bytes);
    var buf: [4096]u8 = undefined;
    var r = file.reader(ioh, &buf);
    try r.interface.readSliceAll(bytes);
    return bytes;
}

fn buildRegistryAsset(gpa: Allocator) !Built {
    const registry_data = try readFileAlloc(gpa, REGISTRY_PATH);
    defer gpa.free(registry_data);
    const registry_hash = blake3Hash(registry_data);
    const asset = protocol.Asset{
        .media_type = "application/vnd.palace.archiform-registry+json",
        .hash = registry_hash,
        .embedded = registry_data,
    };
    const bytes = try envelope.encodeAsset(gpa, asset);
    return .{ .fp = blake3Hash(bytes), .bytes = bytes };
}

fn buildMythos(gpa: Allocator, m: v2.Mythos) !Built {
    const bytes = try envelope_v2.encodeMythos(gpa, m);
    return .{ .fp = blake3Hash(bytes), .bytes = bytes };
}

fn buildTimeline(gpa: Allocator, palace_fp: [32]u8, heads: [][32]u8) !Built {
    const t = v2.Timeline{ .palace_fp = palace_fp, .head_hashes = heads };
    const bytes = try envelope_v2.encodeTimeline(gpa, t);
    return .{ .fp = blake3Hash(bytes), .bytes = bytes };
}

/// Build a ball.timeline whose `head-hashes` attribute carries an ARRAY of
/// byte-strings (rather than the canonical repeated `[label, bstr]` attribute
/// pairs `encodeTimeline` emits).
///
/// palace_verify.zig's `parseTimelineHeadHashes` expects the array shape; it is
/// the only shape from which invariant (e) ("head-hashes are timeline leaves")
/// can read a non-empty head set and therefore trip. The head we pass is a
/// NON-leaf action (referenced as a parent by another action), so verify's leaf
/// check fires with "not a leaf". This is a deliberately adversarial fixture —
/// the whole point of palace-head-hashes-wrong is a malformed timeline.
fn buildTimelineHeadsAsArray(gpa: Allocator, palace_fp: [32]u8, heads: []const [32]u8) !Built {
    const zbor = @import("zbor");
    const dcbor = dreamball.dcbor;

    var ai = std.Io.Writer.Allocating.init(gpa);
    errdefer ai.deinit();
    const w = &ai.writer;
    try zbor.builder.writeTag(w, dcbor.Tag.envelope);
    // outer array: leaf-map + 1 head-hashes attribute pair
    try zbor.builder.writeArray(w, 2);

    try zbor.builder.writeTag(w, dcbor.Tag.leaf);
    try zbor.builder.writeMap(w, 3);
    try zbor.builder.writeTextString(w, "type");
    try zbor.builder.writeTextString(w, v2.Timeline.type_string);
    try zbor.builder.writeTextString(w, "palace-fp");
    try zbor.builder.writeByteString(w, &palace_fp);
    try zbor.builder.writeTextString(w, "format-version");
    try zbor.builder.writeInt(w, @intCast(v2.Timeline.format_version));

    // Single attribute: ["head-hashes", [<bstr32>...]]
    try zbor.builder.writeArray(w, 2);
    try zbor.builder.writeTextString(w, "head-hashes");
    try zbor.builder.writeArray(w, heads.len);
    for (heads) |hh| try zbor.builder.writeByteString(w, &hh);

    const bytes = try ai.toOwnedSlice();
    return .{ .fp = blake3Hash(bytes), .bytes = bytes };
}

fn buildSignedAction(
    gpa: Allocator,
    keys: signer.HybridSigningKeys,
    a: v2.Action,
) !Built {
    const unsigned = try envelope_v2.encodeAction(gpa, a);
    defer gpa.free(unsigned);
    const ed_sig = try signer.signEd25519(unsigned, keys.classical());
    const mldsa_sig = try signer.signMlDsa(gpa, unsigned, keys);
    defer gpa.free(mldsa_sig);
    const bytes = try encodeSignedAction(gpa, a, &[_]protocol.Signature{
        .{ .alg = "ed25519", .value = &ed_sig },
        .{ .alg = "ml-dsa-87", .value = mldsa_sig },
    });
    return .{ .fp = blake3Hash(bytes), .bytes = bytes };
}

fn buildPalaceField(
    gpa: Allocator,
    keys: signer.HybridSigningKeys,
    contains: []const Fingerprint,
) !Built {
    var genesis_input: [40]u8 = undefined;
    @memcpy(genesis_input[0..32], &keys.ed25519_public);
    std.mem.writeInt(i64, genesis_input[32..40], NOW_MS, .little);
    const genesis_hash = blake3Hash(&genesis_input);

    var db = protocol.DreamBall{
        .stage = .seed,
        .identity = keys.ed25519_public,
        .identity_pq = keys.mldsa_public,
        .genesis_hash = genesis_hash,
        .revision = 0,
        .dreamball_type = .field,
        .field_kind = "palace",
        .created = NOW_MS,
        .contains = contains,
        .archiform_fp = dreamball.archiform.MEMORY_PALACE_IMPLICIT_FP,
    };
    return signDreamBall(gpa, &db, keys);
}

// ── Per-fixture generators ─────────────────────────────────────────────────────

/// A complete in-memory minted palace (all envelopes, fps, and the key material).
/// Mirrors the CLI mint + one add-room so verify sees a fully valid palace.
const Palace = struct {
    custodian: signer.HybridSigningKeys,
    oracle: signer.HybridSigningKeys,
    palace_fp: [32]u8,
    oracle_fp: [32]u8,
    mythos_fp: [32]u8,
    registry_fp: [32]u8,
    mint_action_fp: [32]u8,
    timeline_fp: [32]u8,
    room_fp: [32]u8,
    room_action_fp: [32]u8,
};

/// Mint a valid palace into `fw` and return the fp bundle. The `mutate` config
/// selects which intentional break (if any) to apply.
const Mutation = enum {
    none, // valid palace (used by oracle-actor-mismatch baseline)
    no_room, // omit room field + room-added action → invariant (a)
    two_agents, // add a second agent envelope → invariant (b)
    orphan_action, // room-added action parent-hash not in CAS → invariant (c)
    head_not_leaf, // timeline head points at a non-leaf action → invariant (e)
    oracle_mismatch, // room-added action actor = oracle envelope fp (not key fp)
};

fn generatePalace(gpa: Allocator, fw: *FixtureWriter, mutation: Mutation) !void {
    const custodian = try signer.HybridSigningKeys.generate();
    const oracle = try signer.HybridSigningKeys.generate();
    const custodian_fp = Fingerprint.fromEd25519(custodian.ed25519_public).bytes;
    const oracle_fp_key = Fingerprint.fromEd25519(oracle.ed25519_public).bytes;

    // Oracle agent.
    const oracle_agent = try buildOracleAgent(gpa, oracle);
    // Genesis mythos.
    const mythos = try buildMythos(gpa, .{
        .is_genesis = true,
        .predecessor = null,
        .body = "the palace remembers",
        .authored_at = NOW_MS,
    });
    // Registry asset.
    const registry = try buildRegistryAsset(gpa);

    // Mint action (genesis; empty parents).
    const empty_parents: [][32]u8 = &.{};
    const mint_action = try buildSignedAction(gpa, custodian, .{
        .action_kind = .palace_minted,
        .parent_hashes = empty_parents,
        .actor = custodian_fp,
        .target_fp = custodian_fp,
        .timestamp = NOW_MS,
    });

    // Room field (omitted for no_room).
    const include_room = mutation != .no_room;
    var room: Built = undefined;
    if (include_room) room = try buildRoomField(gpa, custodian, "library");

    // Room-added action. Its parent is the mint action (linear chain), unless
    // the orphan mutation points it at an fp absent from the CAS.
    const orphan_parent = [_]u8{0xDE} ** 32; // not present in CAS
    var room_parents_buf = [_][32]u8{mint_action.fp};
    var orphan_parents_buf = [_][32]u8{orphan_parent};
    const room_parents: [][32]u8 = if (mutation == .orphan_action)
        orphan_parents_buf[0..]
    else
        room_parents_buf[0..];

    // For oracle_mismatch, the action claims the oracle ENVELOPE fp as actor
    // while the loaded oracle.key (if any) derives a different fp. (No oracle.key
    // is shipped, so AC10 is skipped — this keeps the structural demonstration.)
    const room_actor: [32]u8 = if (mutation == .oracle_mismatch)
        oracle_agent.fp
    else
        custodian_fp;

    var room_action: Built = undefined;
    var have_room_action = false;
    if (include_room) {
        room_action = try buildSignedAction(gpa, custodian, .{
            .action_kind = .room_added,
            .parent_hashes = room_parents,
            .actor = room_actor,
            .target_fp = room.fp,
            .timestamp = NOW_MS + 1000,
        });
        have_room_action = true;
    }

    // Timeline head-hashes: the current leaf action(s).
    //   - valid / most mutations → the room-added action (or mint action if no room)
    //   - head_not_leaf → the MINT action, which is referenced as a parent by the
    //     room-added action, hence NOT a leaf → invariant (e).
    var heads_buf: [1][32]u8 = undefined;
    if (mutation == .head_not_leaf) {
        heads_buf[0] = mint_action.fp; // referenced as parent → not a leaf
    } else if (have_room_action) {
        heads_buf[0] = room_action.fp;
    } else {
        heads_buf[0] = mint_action.fp;
    }
    // palace_fp is needed inside the timeline; compute palace field last, so use a
    // placeholder palace_fp here (verify does not cross-check timeline.palace_fp).
    //
    // For head_not_leaf the timeline must use the ARRAY-form head-hashes encoding
    // (see buildTimelineHeadsAsArray) — the only shape palace_verify's
    // parseTimelineHeadHashes reads non-empty, hence the only shape from which
    // invariant (e) can trip. Other fixtures use the canonical encoder.
    const timeline = if (mutation == .head_not_leaf)
        try buildTimelineHeadsAsArray(gpa, [_]u8{0} ** 32, heads_buf[0..])
    else
        try buildTimeline(gpa, [_]u8{0} ** 32, heads_buf[0..]);

    // Optional second agent (two_agents mutation).
    var second_agent: Built = undefined;
    var have_second_agent = false;
    if (mutation == .two_agents) {
        const oracle2 = try signer.HybridSigningKeys.generate();
        second_agent = try buildOracleAgent(gpa, oracle2);
        have_second_agent = true;
    }

    // Palace field "contains" — the direct children.
    var contains: std.ArrayList(Fingerprint) = .empty;
    defer contains.deinit(gpa);
    try contains.append(gpa, .{ .bytes = oracle_agent.fp });
    try contains.append(gpa, .{ .bytes = mythos.fp });
    try contains.append(gpa, .{ .bytes = registry.fp });
    try contains.append(gpa, .{ .bytes = timeline.fp });
    if (include_room) try contains.append(gpa, .{ .bytes = room.fp });
    if (have_second_agent) try contains.append(gpa, .{ .bytes = second_agent.fp });

    const palace = try buildPalaceField(gpa, custodian, contains.items);

    _ = oracle_fp_key;

    // ── Assemble CAS + bundle ──────────────────────────────────────────────────
    // Bundle line 0 MUST be the palace fp (verify roots on it).
    try fw.bundleLine(palace.fp);
    try fw.cas(palace.fp, palace.bytes);

    try fw.bundleLine(oracle_agent.fp);
    try fw.cas(oracle_agent.fp, oracle_agent.bytes);

    // Mythos on bundle line 3 (index 2) to satisfy the broken-mythos `sed -n '3p'`
    // contract; harmless ordering for the other fixtures.
    try fw.bundleLine(mythos.fp);
    try fw.cas(mythos.fp, mythos.bytes);

    try fw.bundleLine(registry.fp);
    try fw.cas(registry.fp, registry.bytes);

    try fw.bundleLine(mint_action.fp);
    try fw.cas(mint_action.fp, mint_action.bytes);

    try fw.bundleLine(timeline.fp);
    try fw.cas(timeline.fp, timeline.bytes);

    if (include_room) {
        try fw.bundleLine(room.fp);
        try fw.cas(room.fp, room.bytes);
        try fw.bundleLine(room_action.fp);
        try fw.cas(room_action.fp, room_action.bytes);
    }
    if (have_second_agent) {
        try fw.bundleLine(second_agent.fp);
        try fw.cas(second_agent.fp, second_agent.bytes);
    }
}

/// palace-broken-mythos: a full valid palace whose genesis mythos is replaced by
/// a NON-genesis mythos pointing at an unresolvable predecessor sentinel
/// (0xDEADBEEF × 8). verify's invariant (d) walkToGenesis returns
/// `unresolvable_predecessor`. The mythos fp lands on bundle line 3 so the
/// smoke `sed -n '3p'` (S3.4 AC4) still resolves it in the CAS. Also writes the
/// standalone `broken-mythos.cbor` raw bytes (README contract).
fn generateBrokenMythos(gpa: Allocator, fw: *FixtureWriter) ![32]u8 {
    const custodian = try signer.HybridSigningKeys.generate();
    const oracle = try signer.HybridSigningKeys.generate();
    const custodian_fp = Fingerprint.fromEd25519(custodian.ed25519_public).bytes;

    const oracle_agent = try buildOracleAgent(gpa, oracle);
    const registry = try buildRegistryAsset(gpa);

    // The break: non-genesis mythos, predecessor = sentinel not in CAS.
    const sentinel = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF } ** 8;
    const broken_mythos = try buildMythos(gpa, .{
        .is_genesis = false,
        .predecessor = sentinel,
        .body = "a memory with no origin",
        .authored_at = NOW_MS,
    });

    const empty_parents: [][32]u8 = &.{};
    const mint_action = try buildSignedAction(gpa, custodian, .{
        .action_kind = .palace_minted,
        .parent_hashes = empty_parents,
        .actor = custodian_fp,
        .target_fp = custodian_fp,
        .timestamp = NOW_MS,
    });
    const room = try buildRoomField(gpa, custodian, "library");
    var room_parents = [_][32]u8{mint_action.fp};
    const room_action = try buildSignedAction(gpa, custodian, .{
        .action_kind = .room_added,
        .parent_hashes = room_parents[0..],
        .actor = custodian_fp,
        .target_fp = room.fp,
        .timestamp = NOW_MS + 1000,
    });
    var heads = [_][32]u8{room_action.fp};
    const timeline = try buildTimeline(gpa, [_]u8{0} ** 32, heads[0..]);

    var contains: std.ArrayList(Fingerprint) = .empty;
    defer contains.deinit(gpa);
    try contains.append(gpa, .{ .bytes = oracle_agent.fp });
    try contains.append(gpa, .{ .bytes = broken_mythos.fp });
    try contains.append(gpa, .{ .bytes = registry.fp });
    try contains.append(gpa, .{ .bytes = timeline.fp });
    try contains.append(gpa, .{ .bytes = room.fp });
    const palace = try buildPalaceField(gpa, custodian, contains.items);

    // Bundle: palace, oracle, MYTHOS(line 3), registry, mint-action, timeline,
    // room, room-action.
    try fw.bundleLine(palace.fp);
    try fw.cas(palace.fp, palace.bytes);
    try fw.bundleLine(oracle_agent.fp);
    try fw.cas(oracle_agent.fp, oracle_agent.bytes);
    try fw.bundleLine(broken_mythos.fp);
    try fw.cas(broken_mythos.fp, broken_mythos.bytes);
    try fw.bundleLine(registry.fp);
    try fw.cas(registry.fp, registry.bytes);
    try fw.bundleLine(mint_action.fp);
    try fw.cas(mint_action.fp, mint_action.bytes);
    try fw.bundleLine(timeline.fp);
    try fw.cas(timeline.fp, timeline.bytes);
    try fw.bundleLine(room.fp);
    try fw.cas(room.fp, room.bytes);
    try fw.bundleLine(room_action.fp);
    try fw.cas(room_action.fp, room_action.bytes);

    return broken_mythos.fp;
}

// ── main ───────────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    // Provide a real allocator for the threaded Io used by signMlDsa / file IO.
    std.Io.Threaded.global_single_threaded.allocator = gpa;
    const ioh = std.Io.Threaded.global_single_threaded.io();

    // palace-no-rooms — invariant (a)
    {
        var fw = FixtureWriter.init(gpa);
        defer fw.deinit();
        try generatePalace(gpa, &fw, .no_room);
        try fw.write("palace-no-rooms");
    }

    // palace-two-agents — invariant (b)
    {
        var fw = FixtureWriter.init(gpa);
        defer fw.deinit();
        try generatePalace(gpa, &fw, .two_agents);
        try fw.write("palace-two-agents");
    }

    // palace-orphan-action — invariant (c)
    {
        var fw = FixtureWriter.init(gpa);
        defer fw.deinit();
        try generatePalace(gpa, &fw, .orphan_action);
        try fw.write("palace-orphan-action");
    }

    // palace-head-hashes-wrong — invariant (e)
    {
        var fw = FixtureWriter.init(gpa);
        defer fw.deinit();
        try generatePalace(gpa, &fw, .head_not_leaf);
        try fw.write("palace-head-hashes-wrong");
    }

    // palace-oracle-actor-mismatch — AC10 (skipped without oracle.key); kept
    // structurally consistent with ball.* so it never trips another invariant.
    {
        var fw = FixtureWriter.init(gpa);
        defer fw.deinit();
        try generatePalace(gpa, &fw, .oracle_mismatch);
        try fw.write("palace-oracle-actor-mismatch");
    }

    // palace-broken-mythos — invariant (d) + standalone broken-mythos.cbor
    var broken_mythos_fp: [32]u8 = undefined;
    {
        var fw = FixtureWriter.init(gpa);
        defer fw.deinit();
        broken_mythos_fp = try generateBrokenMythos(gpa, &fw);
        // Locate the broken mythos bytes to also write the standalone .cbor.
        var mythos_bytes: []const u8 = &.{};
        for (fw.entries.items) |e| {
            if (std.mem.eql(u8, &e.fp, &broken_mythos_fp)) {
                mythos_bytes = e.bytes;
                break;
            }
        }
        try fw.write("palace-broken-mythos");

        // Standalone raw bytes (README contract: ball.mythos, is-genesis:false,
        // predecessor = 0xDEADBEEF × 8 sentinel).
        const cbor_path = FIXTURES_ROOT ++ "/palace-broken-mythos/broken-mythos.cbor";
        var f = try std.Io.Dir.cwd().createFile(ioh, cbor_path, .{ .truncate = true });
        defer f.close(ioh);
        var buf: [4096]u8 = undefined;
        var w = f.writer(ioh, &buf);
        try w.interface.writeAll(mythos_bytes);
        try w.interface.flush();
    }

    const stdout = std.Io.File.stdout();
    var obuf: [256]u8 = undefined;
    var ow = stdout.writer(ioh, &obuf);
    try ow.interface.print(
        "export-palace-fixtures: wrote 6 palace fixtures under {s}/\n",
        .{FIXTURES_ROOT},
    );
    try ow.interface.flush();
}
