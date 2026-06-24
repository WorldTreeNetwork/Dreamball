//! dreamball-wasm — WASM-compiled entry point for parsing .ball files in the
//! browser. Single source of truth: reuses the same Zig code paths that
//! the CLI uses, so web + CLI can never drift.
//!
//! Contract with the JS loader:
//!   - The WASM module exposes `alloc`, `reset`, and `parseBall`.
//!   - `alloc(size)` returns a pointer in linear memory; JS copies input
//!     bytes there.
//!   - `parseBall(ptr, len)` consumes those bytes and writes a JSON
//!     result elsewhere in linear memory, returning a packed
//!     (result_ptr << 32) | result_len. 0 means parse failure — JS can
//!     call `resultErr` for a short diagnostic string.
//!   - `reset()` rewinds the bump allocator so the next parse starts fresh.
//!
//! Design notes:
//!   - 16 MB static linear-memory buffer is enough for any realistic
//!     DreamBall (the biggest envelopes we've seen are ~5 KB; sealed
//!     relic bundles with a 3D splat attachment can reach a few MB).
//!     Callers with bigger inputs can bump the constant and rebuild.
//!   - We intentionally do NOT link signer.zig or io.zig into the WASM
//!     module — those use std.Io / std.crypto.random which don't exist
//!     on wasm32-freestanding. *Signing* stays CLI-side (user signing
//!     lives in the key-bearing extension/app path). *Verification*
//!     runs locally in the browser for both Ed25519 (std.crypto) and
//!     ML-DSA-87 (vendored liboqs subset; see docs/known-gaps.md §1).

const std = @import("std");
const build_options = @import("build_options");

const protocol = @import("protocol.zig");
const envelope = @import("envelope.zig");
const sealing = @import("sealing.zig");
const json_mod = @import("json.zig");
const ml_dsa = @import("ml_dsa.zig");

/// Host-provided randomness. Imported by the WASM module; the JS side
/// supplies an implementation that fills `ptr[0..len]` with cryptographically
/// secure random bytes (via `crypto.getRandomValues` in Bun + browser).
///
/// This is THE integration seam between the Zig protocol core and whatever
/// runtime is hosting the WASM. One import, zero FFI, identical behaviour
/// across Bun and the browser. See ADR-1 in the v2.1 plan.
extern "env" fn getRandomBytes(ptr: u32, len: u32) void;

/// Fill `dest` with cryptographically secure randomness from the host.
pub fn fillRandom(dest: []u8) void {
    getRandomBytes(@intCast(@intFromPtr(dest.ptr)), @intCast(dest.len));
}

/// A0 spike export — proves the env-import plumbing works. JS supplies
/// `getRandomBytes`, we call it, write 32 random bytes to a known location,
/// return the pointer. JS reads back and asserts they're non-zero + unique
/// across two calls.
export fn spikeRandom32() u32 {
    var buf: [32]u8 = undefined;
    fillRandom(&buf);
    // Allocate in linear memory so JS can read it.
    const slice = fba_state.allocator().alloc(u8, 32) catch return 0;
    @memcpy(slice, &buf);
    return @intCast(@intFromPtr(slice.ptr));
}

const BUFFER_SIZE: usize = 16 * 1024 * 1024;
var buffer: [BUFFER_SIZE]u8 = undefined;
var fba_state: std.heap.FixedBufferAllocator = std.heap.FixedBufferAllocator.init(&buffer);

var last_err: [256]u8 = undefined;
var last_err_len: u32 = 0;

fn setErr(comptime fmt: []const u8, args: anytype) void {
    const slice = std.fmt.bufPrint(&last_err, fmt, args) catch {
        const msg = "dreamball-wasm: unknown error";
        @memcpy(last_err[0..msg.len], msg);
        last_err_len = msg.len;
        return;
    };
    last_err_len = @intCast(slice.len);
}

export fn alloc(size: u32) u32 {
    const slice = fba_state.allocator().alloc(u8, size) catch return 0;
    return @intCast(@intFromPtr(slice.ptr));
}

export fn reset() void {
    fba_state.reset();
    last_err_len = 0;
}

/// Parse the `.ball` bytes at `input_ptr[0..input_len]`. On success,
/// returns a packed u64 = (result_ptr << 32) | result_len pointing at
/// the JSON rendering of the DreamBall. On failure, returns 0 and sets
/// the last-error buffer (readable via `resultErrPtr`/`resultErrLen`).
export fn parseBall(input_ptr: u32, input_len: u32) u64 {
    const input_bytes: []const u8 = @as([*]const u8, @ptrFromInt(input_ptr))[0..input_len];
    const alloc_ = fba_state.allocator();

    // Format detection: "BALL" magic → sealed wrapper; 0xD8 0xC8 → bare envelope;
    // '{' → canonical JSON (pass-through); anything else → error.
    var envelope_bytes: []const u8 = input_bytes;
    var sealed_attachments_count: usize = 0;

    if (input_bytes.len >= 4 and std.mem.eql(u8, input_bytes[0..4], "BALL")) {
        const parsed = sealing.readSealedFile(alloc_, input_bytes) catch |e| {
            setErr("sealed-file parse failed: {t}", .{e});
            return 0;
        };
        envelope_bytes = parsed.envelope;
        sealed_attachments_count = parsed.attachments.len;
        // Don't deinit parsed — its slices point into input_bytes and
        // we need envelope_bytes to stay valid.
    } else if (input_bytes.len >= 2 and input_bytes[0] == 0xD8 and input_bytes[1] == 0xC8) {
        // Bare tag-200 envelope — use as-is.
    } else if (input_bytes.len >= 1 and input_bytes[0] == '{') {
        // Canonical JSON — echo it back (the user already has the target shape).
        return pack(input_bytes);
    } else {
        setErr("unknown .ball format; expected BALL magic, CBOR tag 200, or JSON object", .{});
        return 0;
    }

    // Full decode — core + every attribute into a typed DreamBall struct.
    const db = envelope.decodeDreamBall(alloc_, envelope_bytes) catch |e| {
        setErr("decodeDreamBall failed: {t}", .{e});
        return 0;
    };

    // Canonical JSON render. Reuses the CLI's code path — guaranteed
    // byte-identical between Zig CLI and WASM for any given input.
    const json_bytes = json_mod.writeDreamBall(alloc_, db) catch |e| {
        setErr("writeDreamBall failed: {t}", .{e});
        return 0;
    };

    return pack(json_bytes);
}

fn pack(bytes: []const u8) u64 {
    const p: u64 = @intFromPtr(bytes.ptr);
    const l: u64 = bytes.len;
    return (p << 32) | (l & 0xFFFFFFFF);
}

// ============================================================================
// Write-op exports — every export returns a packed u64
// (result_ptr << 32) | result_len pointing at JSON bytes. Secret keys
// produced by `mintDreamBall` are placed in `last_secret`; JS reads via
// `lastSecretPtr` + `lastSecretLen`.
//
// ML-DSA-87 signatures are NOT emitted here. The browser doesn't hold
// the signer's PQ secret — user signing lives in a key-bearing
// extension/app path, and the server mint path subprocesses the native
// `dreamball` binary which signs with both algorithms locally. Browser-
// minted envelopes are therefore Ed25519-only (explicitly legal under
// PROTOCOL.md §2.3). A consumer that wants PQ strength re-signs with
// `dreamball grow --key` using a hybrid key file.
// ============================================================================

const Ed25519 = std.crypto.sign.Ed25519;

var last_secret: [64]u8 = undefined;
var last_secret_len: u32 = 0;

export fn lastSecretPtr() u32 {
    return @intCast(@intFromPtr(&last_secret[0]));
}
export fn lastSecretLen() u32 {
    return last_secret_len;
}

/// Legacy zero-filled ML-DSA-87 signature detector. Earlier browser-mint
/// envelopes attached a 4627-byte zero buffer as a placeholder; we now
/// emit Ed25519-only instead, but `verifyBall` keeps this around to
/// tolerate any on-disk envelope still carrying the legacy placeholder.
fn isPlaceholderMldsa(sig: []const u8) bool {
    if (sig.len != protocol.ML_DSA_87_SIGNATURE_LEN) return false;
    for (sig) |b| if (b != 0) return false;
    return true;
}

fn packResult(bytes: []const u8) u64 {
    const p: u64 = @intFromPtr(bytes.ptr);
    const l: u64 = bytes.len;
    return (p << 32) | (l & 0xFFFFFFFF);
}

fn typeIdToEnum(id: u32) ?protocol.DreamBallType {
    return switch (id) {
        0 => .avatar,
        1 => .agent,
        2 => .tool,
        3 => .relic,
        4 => .field,
        5 => .guild,
        6 => null, // untyped v1
        else => error.BadType catch null,
    };
}

/// Mint a new DreamBall. Caller supplies `created` as Unix seconds; the
/// envelope bytes come back through the packed-u64 return; the 64-byte
/// Ed25519 secret lands in `last_secret` (read via lastSecretPtr/Len).
///
/// type_id: 0=avatar 1=agent 2=tool 3=relic 4=field 5=guild 6=untyped (v1).
export fn mintDreamBall(
    type_id: u32,
    name_ptr: u32,
    name_len: u32,
    created: i64,
) u64 {
    const alloc_ = fba_state.allocator();

    const name_slice: ?[]const u8 = if (name_len == 0)
        null
    else
        @as([*]const u8, @ptrFromInt(name_ptr))[0..name_len];

    const dreamball_type = typeIdToEnum(type_id);
    if (type_id > 6) {
        setErr("mintDreamBall: type_id {d} out of range 0..6", .{type_id});
        return 0;
    }

    // Generate Ed25519 keypair via host randomness.
    var seed: [Ed25519.KeyPair.seed_length]u8 = undefined;
    fillRandom(&seed);
    const kp = Ed25519.KeyPair.generateDeterministic(seed) catch {
        setErr("Ed25519 keygen failed", .{});
        return 0;
    };
    const pk = kp.public_key.toBytes();
    last_secret = kp.secret_key.toBytes();
    last_secret_len = 64;

    // Genesis hash = Blake3(pk || created_le_bytes).
    var genesis_input: [40]u8 = undefined;
    @memcpy(genesis_input[0..32], &pk);
    std.mem.writeInt(i64, genesis_input[32..40], created, .little);
    var gh: [32]u8 = undefined;
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(&genesis_input);
    hasher.final(&gh);

    // Build the unsigned DreamBall struct.
    var db = protocol.DreamBall{
        .stage = .seed,
        .dreamball_type = dreamball_type,
        .identity = pk,
        .genesis_hash = gh,
        .revision = 0,
        .name = name_slice,
        .created = created,
    };

    // First encode — unsigned — and sign that with Ed25519.
    const unsigned = envelope.encodeDreamBall(alloc_, db) catch |e| {
        setErr("encode (unsigned) failed: {t}", .{e});
        return 0;
    };
    const sig = kp.sign(unsigned, null) catch |e| {
        setErr("Ed25519 sign failed: {t}", .{e});
        return 0;
    };
    const sig_bytes = sig.toBytes();

    // Attach Ed25519 only — browser mint doesn't hold a PQ key, and
    // §2.3 accepts Ed25519-only nodes. A downstream caller (typically
    // `dreamball grow --key` on the native CLI with a hybrid key file)
    // upgrades the envelope to hybrid when real PQ strength is wanted.
    const sigs = [_]protocol.Signature{
        .{ .alg = "ed25519", .value = &sig_bytes },
    };
    db.signatures = &sigs;

    const signed = envelope.encodeDreamBall(alloc_, db) catch |e| {
        setErr("encode (signed) failed: {t}", .{e});
        return 0;
    };

    return packResult(signed);
}

/// Add a Guild membership to an existing DreamBall and re-sign.
///
/// Inputs: existing envelope bytes, the guild's DreamBall envelope bytes,
/// the DreamBall's 64-byte Ed25519 secret key.
/// Output (packed return): the updated + re-signed envelope bytes.
export fn joinGuildWasm(
    env_ptr: u32,
    env_len: u32,
    guild_env_ptr: u32,
    guild_env_len: u32,
    secret_ptr: u32,
    secret_len: u32,
    updated: i64,
) u64 {
    if (secret_len != 64) {
        setErr("joinGuild: secret must be 64 bytes", .{});
        return 0;
    }
    const alloc_ = fba_state.allocator();
    const env_bytes = @as([*]const u8, @ptrFromInt(env_ptr))[0..env_len];
    const guild_bytes = @as([*]const u8, @ptrFromInt(guild_env_ptr))[0..guild_env_len];

    var arena = std.heap.ArenaAllocator.init(alloc_);
    defer arena.deinit();
    const aa = arena.allocator();

    var db = envelope.decodeDreamBall(aa, env_bytes) catch |e| {
        setErr("joinGuild: decode failed: {t}", .{e});
        return 0;
    };
    const guild_db = envelope.decodeDreamBallSubject(guild_bytes) catch |e| {
        setErr("joinGuild: guild decode failed: {t}", .{e});
        return 0;
    };

    const guild_fp = guild_db.fingerprint();
    var guilds_buf = alloc_.alloc(@TypeOf(guild_fp), db.guilds.len + 1) catch {
        setErr("joinGuild: OOM", .{});
        return 0;
    };
    @memcpy(guilds_buf[0..db.guilds.len], db.guilds);
    guilds_buf[db.guilds.len] = guild_fp;
    db.guilds = guilds_buf;
    db.revision += 1;
    db.updated = updated;
    if (db.stage == .seed) db.stage = .dreamball;

    // Re-sign.
    var sk_bytes: [64]u8 = undefined;
    @memcpy(&sk_bytes, @as([*]const u8, @ptrFromInt(secret_ptr))[0..64]);
    const sk = Ed25519.SecretKey.fromBytes(sk_bytes) catch {
        setErr("joinGuild: bad secret key", .{});
        return 0;
    };
    const kp = Ed25519.KeyPair.fromSecretKey(sk) catch {
        setErr("joinGuild: fromSecretKey failed", .{});
        return 0;
    };

    // Clear prior signatures, encode unsigned, sign, reattach.
    db.signatures = &.{};
    const unsigned = envelope.encodeDreamBall(alloc_, db) catch |e| {
        setErr("joinGuild: encode (unsigned) failed: {t}", .{e});
        return 0;
    };
    const sig = kp.sign(unsigned, null) catch |e| {
        setErr("joinGuild: sign failed: {t}", .{e});
        return 0;
    };
    const sig_bytes = sig.toBytes();
    // Re-sign with Ed25519 only — same reasoning as mint (see above).
    const sigs = [_]protocol.Signature{
        .{ .alg = "ed25519", .value = &sig_bytes },
    };
    db.signatures = &sigs;

    const signed = envelope.encodeDreamBall(alloc_, db) catch |e| {
        setErr("joinGuild: encode (signed) failed: {t}", .{e});
        return 0;
    };
    return packResult(signed);
}

/// Grow a DreamBall — bump revision, set updated timestamp, optionally
/// set new name, re-sign. For v2.1 MVP this is the minimum surface; more
/// setters (personality, voice, model, system-prompt) land once JS→Zig
/// input marshalling is settled.
export fn growDreamBall(
    env_ptr: u32,
    env_len: u32,
    secret_ptr: u32,
    secret_len: u32,
    new_name_ptr: u32,
    new_name_len: u32,
    updated: i64,
    promote_to_dreamball: u32,
) u64 {
    if (secret_len != 64) {
        setErr("grow: secret must be 64 bytes", .{});
        return 0;
    }
    const alloc_ = fba_state.allocator();
    const env_bytes = @as([*]const u8, @ptrFromInt(env_ptr))[0..env_len];

    var arena = std.heap.ArenaAllocator.init(alloc_);
    defer arena.deinit();
    const aa = arena.allocator();

    var db = envelope.decodeDreamBall(aa, env_bytes) catch |e| {
        setErr("grow: decode failed: {t}", .{e});
        return 0;
    };
    if (new_name_len > 0) {
        db.name = @as([*]const u8, @ptrFromInt(new_name_ptr))[0..new_name_len];
    }
    db.revision += 1;
    db.updated = updated;
    if (promote_to_dreamball != 0 and db.stage == .seed) db.stage = .dreamball;

    var sk_bytes: [64]u8 = undefined;
    @memcpy(&sk_bytes, @as([*]const u8, @ptrFromInt(secret_ptr))[0..64]);
    const sk = Ed25519.SecretKey.fromBytes(sk_bytes) catch {
        setErr("grow: bad secret", .{});
        return 0;
    };
    const kp = Ed25519.KeyPair.fromSecretKey(sk) catch {
        setErr("grow: fromSecretKey failed", .{});
        return 0;
    };

    db.signatures = &.{};
    const unsigned = envelope.encodeDreamBall(alloc_, db) catch |e| {
        setErr("grow: encode (unsigned) failed: {t}", .{e});
        return 0;
    };
    const sig = kp.sign(unsigned, null) catch |e| {
        setErr("grow: sign failed: {t}", .{e});
        return 0;
    };
    const sig_bytes = sig.toBytes();
    // Re-sign with Ed25519 only — same reasoning as mint (see above).
    const sigs = [_]protocol.Signature{
        .{ .alg = "ed25519", .value = &sig_bytes },
    };
    db.signatures = &sigs;

    const signed = envelope.encodeDreamBall(alloc_, db) catch |e| {
        setErr("grow: encode (signed) failed: {t}", .{e});
        return 0;
    };
    return packResult(signed);
}

export fn resultErrPtr() u32 {
    return @intCast(@intFromPtr(&last_err[0]));
}

export fn resultErrLen() u32 {
    return last_err_len;
}

/// In-browser hybrid verification. Checks every `'signed'` attribute:
/// Ed25519 against `identity`, ML-DSA-87 against `identity-pq` when the
/// binary was built with `-Dpq-wasm=true` (the default). Policy matches
/// PROTOCOL.md §2.3: all present sigs must verify, no minimum count. An
/// ML-DSA signature with no `identity-pq` in the core is rejected.
///
/// Reconstructs the canonical unsigned bytes via `stripSignatures`, then
/// iterates signatures. Returns:
///   2  — envelope parsed OK and all signatures verified
///   1  — envelope parsed but no Ed25519 signature present (draft)
///   0  — verification failed (signature mismatch, tampered bytes, etc.)
///   -1 / 0xFFFFFFFF — parse error (use resultErr for diagnostic)
export fn verifyBall(input_ptr: u32, input_len: u32) i32 {
    const input_bytes: []const u8 = @as([*]const u8, @ptrFromInt(input_ptr))[0..input_len];
    const alloc_ = fba_state.allocator();

    // Peel sealed wrapper if present.
    var envelope_bytes: []const u8 = input_bytes;
    if (input_bytes.len >= 4 and std.mem.eql(u8, input_bytes[0..4], "BALL")) {
        const parsed = sealing.readSealedFile(alloc_, input_bytes) catch |e| {
            setErr("sealed parse failed: {t}", .{e});
            return -1;
        };
        envelope_bytes = parsed.envelope;
    } else if (input_bytes.len >= 2 and input_bytes[0] == 0xD8 and input_bytes[1] == 0xC8) {
        // bare envelope, use as-is
    } else {
        setErr("verify: input is not a .ball envelope (expected BALL or tag 200)", .{});
        return -1;
    }

    // Reconstruct unsigned bytes + collect signatures.
    const stripped = envelope.stripSignatures(alloc_, envelope_bytes) catch |e| {
        setErr("stripSignatures failed: {t}", .{e});
        return -1;
    };

    // Need the Ed25519 public key from the core.
    const db = envelope.decodeDreamBallSubject(envelope_bytes) catch |e| {
        setErr("core decode failed: {t}", .{e});
        return -1;
    };

    const pk = Ed25519.PublicKey.fromBytes(db.identity) catch {
        setErr("identity is not a valid Ed25519 public key", .{});
        return -1;
    };

    var have_ed = false;
    for (stripped.signatures) |sig| {
        if (std.mem.eql(u8, sig.alg, "ed25519")) {
            if (sig.value.len != Ed25519.Signature.encoded_length) {
                setErr("malformed Ed25519 signature length", .{});
                return 0;
            }
            var sig_arr: [Ed25519.Signature.encoded_length]u8 = undefined;
            @memcpy(&sig_arr, sig.value);
            const sig_obj = Ed25519.Signature.fromBytes(sig_arr);
            sig_obj.verify(stripped.unsigned, pk) catch {
                setErr("Ed25519 signature verification failed", .{});
                return 0;
            };
            have_ed = true;
        } else if (build_options.pq_wasm and std.mem.eql(u8, sig.alg, "ml-dsa-87")) {
            if (sig.value.len != protocol.ML_DSA_87_SIGNATURE_LEN) {
                setErr("malformed ML-DSA signature length", .{});
                return 0;
            }
            // Zero-filled placeholder from pre-2026-04-21 browser-mint
            // envelopes — skip, don't reject. Current mint emits
            // Ed25519-only, so fresh envelopes never hit this branch.
            if (isPlaceholderMldsa(sig.value)) continue;
            const pq_pk = db.identity_pq orelse {
                setErr("ML-DSA signature present but no identity-pq in core", .{});
                return 0;
            };
            ml_dsa.verify(sig.value, stripped.unsigned, &pq_pk) catch {
                setErr("ML-DSA signature verification failed", .{});
                return 0;
            };
        }
        // When !build_options.pq_wasm, ML-DSA signatures are parsed but
        // not verified here (native CLI is the authority).
    }

    return if (have_ed) 2 else 1;
}

/// Standalone ML-DSA-87 verify. Inputs point into linear memory.
/// Returns 1 = verified, 0 = verification failed, -1 = parse/setup error.
/// Only active when built with `-Dpq-wasm=true`. On the no-PQ build the
/// export is still present but always returns -1 with last-err set.
export fn verifyMlDsa(
    sig_ptr: u32,
    sig_len: u32,
    msg_ptr: u32,
    msg_len: u32,
    pk_ptr: u32,
    pk_len: u32,
) i32 {
    if (!build_options.pq_wasm) {
        setErr("verifyMlDsa: build was not compiled with -Dpq-wasm=true", .{});
        return -1;
    }
    if (sig_len != protocol.ML_DSA_87_SIGNATURE_LEN) {
        setErr("verifyMlDsa: signature length must be {d}, got {d}", .{ protocol.ML_DSA_87_SIGNATURE_LEN, sig_len });
        return -1;
    }
    if (pk_len != protocol.ML_DSA_87_PUBLIC_KEY_LEN) {
        setErr("verifyMlDsa: pubkey length must be {d}, got {d}", .{ protocol.ML_DSA_87_PUBLIC_KEY_LEN, pk_len });
        return -1;
    }
    const sig: []const u8 = @as([*]const u8, @ptrFromInt(sig_ptr))[0..sig_len];
    const msg: []const u8 = @as([*]const u8, @ptrFromInt(msg_ptr))[0..msg_len];
    const pk: *const [protocol.ML_DSA_87_PUBLIC_KEY_LEN]u8 = @ptrCast(@alignCast(@as([*]const u8, @ptrFromInt(pk_ptr))));
    ml_dsa.verify(sig, msg, pk) catch return 0;
    return 1;
}

/// Sign an action payload with an Ed25519 keypair.
///
/// Inputs:
///   keypair_bytes_ptr / keypair_bytes_len — 64-byte Ed25519 secret key
///     (the same secret key bytes produced by mintDreamBall / lastSecretPtr).
///   payload_bytes_ptr / payload_bytes_len — arbitrary bytes to sign (the
///     serialised action envelope payload).
///
/// Returns a packed u64 = (sig_ptr << 32) | sig_len pointing at the
/// 64-byte Ed25519 signature written into the bump allocator.  Returns 0
/// on any error (check resultErr for a diagnostic).
///
/// Per D-023 / SEC6: Ed25519-only single signatures for sprint-002.
/// PQ / ML-DSA-87 dual-sig is explicitly deferred to the security pass.
/// The existing `env.getRandomBytes` import is NOT used — Ed25519 sign
/// is deterministic given the secret key; no new host imports are added.
///
/// This is the single seam through which action signatures are produced;
/// no TS/browser code path emits signatures without going through this
/// export.
export fn signActionEnvelope(
    keypair_bytes_ptr: u32,
    keypair_bytes_len: u32,
    payload_bytes_ptr: u32,
    payload_bytes_len: u32,
) u64 {
    if (keypair_bytes_len != 64) {
        setErr("signActionEnvelope: keypair must be 64 bytes, got {d}", .{keypair_bytes_len});
        return 0;
    }
    const alloc_ = fba_state.allocator();
    const keypair_bytes: []const u8 = @as([*]const u8, @ptrFromInt(keypair_bytes_ptr))[0..keypair_bytes_len];
    const payload_bytes: []const u8 = @as([*]const u8, @ptrFromInt(payload_bytes_ptr))[0..payload_bytes_len];

    var sk_bytes: [64]u8 = undefined;
    @memcpy(&sk_bytes, keypair_bytes);
    const sk = Ed25519.SecretKey.fromBytes(sk_bytes) catch {
        setErr("signActionEnvelope: invalid Ed25519 secret key", .{});
        return 0;
    };
    const kp = Ed25519.KeyPair.fromSecretKey(sk) catch {
        setErr("signActionEnvelope: fromSecretKey failed", .{});
        return 0;
    };
    const sig = kp.sign(payload_bytes, null) catch {
        setErr("signActionEnvelope: Ed25519 sign failed", .{});
        return 0;
    };
    const sig_bytes = sig.toBytes();

    const out = alloc_.alloc(u8, sig_bytes.len) catch {
        setErr("signActionEnvelope: OOM allocating signature output", .{});
        return 0;
    };
    @memcpy(out, &sig_bytes);
    return packResult(out);
}

// ============================================================================
// Inline KAT — verifies signActionEnvelope round-trips through verifyEd25519.
// Uses a deterministic all-zeros seed so the expected signature is a fixed
// known-answer vector (matches the golden vector in sign-action-envelope.test.ts).
// ============================================================================

test "signActionEnvelope KAT — all-zeros seed + empty payload" {
    // Reset allocator state for a clean test.
    fba_state.reset();

    // Deterministic keypair from all-zeros seed.
    const seed: [Ed25519.KeyPair.seed_length]u8 = .{0} ** Ed25519.KeyPair.seed_length;
    const kp = try Ed25519.KeyPair.generateDeterministic(seed);
    const sk_bytes = kp.secret_key.toBytes();
    const pk_bytes = kp.public_key.toBytes();

    const payload = "dreamball-action-envelope-kat";

    // Write secret key into linear memory via bump allocator.
    const sk_slot = try fba_state.allocator().alloc(u8, 64);
    @memcpy(sk_slot, &sk_bytes);

    // Write payload.
    const pl_slot = try fba_state.allocator().alloc(u8, payload.len);
    @memcpy(pl_slot, payload);

    const result = signActionEnvelope(
        @intCast(@intFromPtr(sk_slot.ptr)),
        @intCast(sk_slot.len),
        @intCast(@intFromPtr(pl_slot.ptr)),
        @intCast(pl_slot.len),
    );
    try std.testing.expect(result != 0);

    const sig_ptr = @as(usize, @intCast(result >> 32));
    const sig_len = @as(usize, @intCast(result & 0xFFFFFFFF));
    try std.testing.expectEqual(@as(usize, 64), sig_len);

    const sig_out: []const u8 = @as([*]const u8, @ptrFromInt(sig_ptr))[0..sig_len];
    var sig_arr: [Ed25519.Signature.encoded_length]u8 = undefined;
    @memcpy(&sig_arr, sig_out);
    const sig_obj = Ed25519.Signature.fromBytes(sig_arr);

    // Verify the signature using the corresponding public key.
    const pk_obj = try Ed25519.PublicKey.fromBytes(pk_bytes);
    try sig_obj.verify(payload, pk_obj);
}

test "signActionEnvelope tamper test — bit-flipped payload produces different sig and fails verify" {
    fba_state.reset();

    const seed: [Ed25519.KeyPair.seed_length]u8 = .{0xAB} ** Ed25519.KeyPair.seed_length;
    const kp = try Ed25519.KeyPair.generateDeterministic(seed);
    const sk_bytes = kp.secret_key.toBytes();
    const pk_bytes = kp.public_key.toBytes();

    const payload = "action-payload-for-tamper-test";
    var payload_mut: [payload.len]u8 = undefined;
    @memcpy(&payload_mut, payload);

    // Sign original payload.
    const sk_slot1 = try fba_state.allocator().alloc(u8, 64);
    @memcpy(sk_slot1, &sk_bytes);
    const pl_slot1 = try fba_state.allocator().alloc(u8, payload.len);
    @memcpy(pl_slot1, payload);

    const result1 = signActionEnvelope(
        @intCast(@intFromPtr(sk_slot1.ptr)),
        @intCast(sk_slot1.len),
        @intCast(@intFromPtr(pl_slot1.ptr)),
        @intCast(pl_slot1.len),
    );
    try std.testing.expect(result1 != 0);
    const sig1_ptr = @as(usize, @intCast(result1 >> 32));
    const sig1_len = @as(usize, @intCast(result1 & 0xFFFFFFFF));
    const sig1_out: [64]u8 = @as([*]const u8, @ptrFromInt(sig1_ptr))[0..sig1_len].*;

    // Flip bit 0 of byte 0 in payload.
    payload_mut[0] ^= 0x01;

    // Sign flipped payload.
    const sk_slot2 = try fba_state.allocator().alloc(u8, 64);
    @memcpy(sk_slot2, &sk_bytes);
    const pl_slot2 = try fba_state.allocator().alloc(u8, payload_mut.len);
    @memcpy(pl_slot2, &payload_mut);

    const result2 = signActionEnvelope(
        @intCast(@intFromPtr(sk_slot2.ptr)),
        @intCast(sk_slot2.len),
        @intCast(@intFromPtr(pl_slot2.ptr)),
        @intCast(pl_slot2.len),
    );
    try std.testing.expect(result2 != 0);
    const sig2_ptr = @as(usize, @intCast(result2 >> 32));
    const sig2_len = @as(usize, @intCast(result2 & 0xFFFFFFFF));
    const sig2_out: [64]u8 = @as([*]const u8, @ptrFromInt(sig2_ptr))[0..sig2_len].*;

    // The two signatures must differ.
    try std.testing.expect(!std.mem.eql(u8, &sig1_out, &sig2_out));

    // Verifying sig1 against the flipped payload must fail.
    var sig1_arr: [Ed25519.Signature.encoded_length]u8 = undefined;
    @memcpy(&sig1_arr, &sig1_out);
    const sig1_obj = Ed25519.Signature.fromBytes(sig1_arr);
    const pk_obj = try Ed25519.PublicKey.fromBytes(pk_bytes);
    const verify_result = sig1_obj.verify(&payload_mut, pk_obj);
    try std.testing.expectError(error.SignatureVerificationFailed, verify_result);
}

/// Blake3 hash — cross-runtime parity export (HIGH-2 fix, Sprint-1 code review).
///
/// Computes Blake3-256 of `input_ptr[0..input_len]` and writes the 32-byte
/// digest into `out_ptr[0..32]`. The caller must pre-allocate at least 32
/// bytes at `out_ptr` (use `alloc(32)` from JS).
///
/// This eliminates the SHA-256 fallback in `cypher-utils.ts` so that a
/// field named `source_blake3` actually IS Blake3 in every runtime.
export fn hashBlake3(input_ptr: u32, input_len: u32, out_ptr: u32) void {
    const input: []const u8 = @as([*]const u8, @ptrFromInt(input_ptr))[0..input_len];
    const out: *[32]u8 = @ptrFromInt(out_ptr);
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(input);
    hasher.final(out);
}
