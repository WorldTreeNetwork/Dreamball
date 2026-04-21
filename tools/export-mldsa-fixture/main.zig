//! export-mldsa-fixture — writes fixtures/ml_dsa_87_golden.json
//!
//! Generates a deterministic ML-DSA-87 known-answer test vector using a
//! seeded PRNG (see deterministic_rand.c) so the output is identical on
//! every run. The fixture is committed to the repo as a stable test vector
//! for the Vitest `verifyMlDsa` primitive tests in
//! `src/lib/wasm/verify.test.ts`.
//!
//! Run via:
//!   zig build export-mldsa-fixture
//!
//! Output:
//!   fixtures/ml_dsa_87_golden.json
//!     { "pk": "<hex>", "msg": "<hex>", "sig": "<hex>" }
//!
//! Why hex? The rest of the repo uses base58 for user-facing identifiers
//! but hex is conventional for KAT vectors and is directly readable by
//! Node's `Buffer.from(hex, 'hex')` without extra dependencies.

const std = @import("std");

// ML-DSA-87 constants (FIPS-204 Category 5)
const PUBLIC_KEY_LEN: usize = 2592;
const SECRET_KEY_LEN: usize = 4896;
const SIGNATURE_LEN: usize = 4627;

// Fixed test message — stable across runs.
const MESSAGE = "dreamball-mldsa87-kat-message-2026";

// liboqs externs — same as src/ml_dsa.zig
extern fn pqcrystals_ml_dsa_87_ref_keypair(pk: [*]u8, sk: [*]u8) callconv(.c) c_int;
extern fn pqcrystals_ml_dsa_87_ref_signature(
    sig: [*]u8,
    siglen: *usize,
    m: [*]const u8,
    mlen: usize,
    ctx: ?[*]const u8,
    ctxlen: usize,
    sk: [*]const u8,
) callconv(.c) c_int;
extern fn pqcrystals_ml_dsa_87_ref_verify(
    sig: [*]const u8,
    siglen: usize,
    m: [*]const u8,
    mlen: usize,
    ctx: ?[*]const u8,
    ctxlen: usize,
    pk: [*]const u8,
) callconv(.c) c_int;

const hex_charset = "0123456789abcdef";

/// Encode bytes as lowercase hex into an allocated buffer. Caller owns result.
fn bytesToHexAlloc(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |b, i| {
        out[i * 2]     = hex_charset[(b >> 4) & 0xF];
        out[i * 2 + 1] = hex_charset[b & 0xF];
    }
    return out;
}

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    const io = std.Io.Threaded.global_single_threaded.io();

    var pk: [PUBLIC_KEY_LEN]u8 = undefined;
    var sk: [SECRET_KEY_LEN]u8 = undefined;

    // Generate keypair using the seeded deterministic_rand.c OQS_randombytes.
    const kp_rc = pqcrystals_ml_dsa_87_ref_keypair(&pk, &sk);
    if (kp_rc != 0) {
        std.debug.print("ERROR: keypair generation failed (rc={d})\n", .{kp_rc});
        std.process.exit(1);
    }

    var sig: [SIGNATURE_LEN]u8 = undefined;
    var siglen: usize = SIGNATURE_LEN;
    const sign_rc = pqcrystals_ml_dsa_87_ref_signature(
        &sig,
        &siglen,
        MESSAGE.ptr,
        MESSAGE.len,
        null,
        0,
        &sk,
    );
    if (sign_rc != 0) {
        std.debug.print("ERROR: sign failed (rc={d})\n", .{sign_rc});
        std.process.exit(1);
    }

    // Self-verify before writing fixture.
    const verify_rc = pqcrystals_ml_dsa_87_ref_verify(
        &sig,
        siglen,
        MESSAGE.ptr,
        MESSAGE.len,
        null,
        0,
        &pk,
    );
    if (verify_rc != 0) {
        std.debug.print("ERROR: self-verify failed — fixture would be invalid\n", .{});
        std.process.exit(1);
    }

    // Encode as hex strings.
    const pk_hex  = try bytesToHexAlloc(allocator, &pk);
    defer allocator.free(pk_hex);
    const msg_hex = try bytesToHexAlloc(allocator, MESSAGE);
    defer allocator.free(msg_hex);
    const sig_hex = try bytesToHexAlloc(allocator, sig[0..siglen]);
    defer allocator.free(sig_hex);

    // Build JSON content.
    // Use a fixed-size stack buffer — pk_hex is 5184 chars, sig_hex is 9254 chars,
    // msg_hex is small. Total well under 20 KB.
    const json = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "pk": "{s}",
        \\  "msg": "{s}",
        \\  "sig": "{s}"
        \\}}
        \\
    , .{ pk_hex, msg_hex, sig_hex });
    defer allocator.free(json);

    // Create fixtures/ directory if needed.
    std.Io.Dir.cwd().createDirPath(io, "fixtures") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const out_path = "fixtures/ml_dsa_87_golden.json";
    var file = try std.Io.Dir.cwd().createFile(io, out_path, .{ .truncate = true });
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var w = file.writer(io, &buf);
    try w.interface.writeAll(json);
    try w.interface.flush();

    const stdout = std.Io.File.stdout();
    var sbuf: [256]u8 = undefined;
    var sw = stdout.writer(io, &sbuf);
    try sw.interface.print(
        "wrote {s}  (pk={d}B msg={d}B sig={d}B)\n",
        .{ out_path, PUBLIC_KEY_LEN, MESSAGE.len, siglen },
    );
    try sw.interface.flush();
}
