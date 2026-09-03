//! Per-import tests for the 5 sprint-002-locked `dreamball.*` imports
//! (Story 5.2 / AC2). Each test:
//!
//!   - Builds a hand-authored wasm guest that imports the named
//!     `dreamball.*` function and exercises it once.
//!   - Instantiates against the production `imports.bindAll()` surface
//!     (no other bindings — proves SEC1 whitelist is the only source
//!     of imports).
//!   - Asserts the import's host-side return semantics:
//!       fp                   — fp identity vs canonical Blake3.
//!       encode_cbor          — canonical dCBOR byte-string framing.
//!       read_node            — present + missing cases.
//!       emit_action_envelope — payload staged + signed (Ed25519 verify).
//!       now_ms               — two consecutive calls are non-decreasing.
//!
//! Per FR11 / Story 5.2 AC2 the test surface lives at
//! `tests/wasm/imports/<name>/` for the per-name traceability — each
//! import has its own subdirectory holding the guest source description
//! (a `main.zig` analog of `tests/wasm/hello/main.zig`). The driver
//! that exercises them is here, beside the runtime, so the imports +
//! their tests share an entry point in `zig build test`.

const std = @import("std");
const runtime = @import("runtime.zig");
const imports_mod = @import("imports.zig");
const guest = @import("build_guest.zig");

const Ed25519 = std.crypto.sign.Ed25519;

fn freshHost(allocator: std.mem.Allocator) imports_mod.Host {
    const seed: [32]u8 = .{0x42} ** 32;
    const kp = Ed25519.KeyPair.generateDeterministic(seed) catch unreachable;
    return imports_mod.Host.init(allocator, kp.secret_key.toBytes(), &.{});
}

fn run(
    allocator: std.mem.Allocator,
    host: *imports_mod.Host,
    wasm_bytes: []const u8,
) !void {
    var module = try runtime.parse(allocator, wasm_bytes);
    defer module.deinit();
    const bindings = imports_mod.bindAll();
    var instance = try runtime.Instance.init(allocator, &module, .{
        .imports = &bindings,
        .host_context = host,
    });
    defer instance.deinit();
    // Scratch at a high memory region the guest's data segment + body
    // don't touch.
    host.attach(32768, 32768);
    try instance.invokeStart();
}

test "dreamball.fp matches canonical blake3" {
    const allocator = std.testing.allocator;
    var host = freshHost(allocator);
    defer host.deinit();
    host.beginInvocation("test_fp", [_]u8{0} ** 32, [_]u8{0} ** 32, [_]u8{0} ** 32);

    const input: []const u8 = "hello-dreamball-fp";
    const spec = try guest.buildFpGuest(allocator, input);
    defer allocator.free(spec.bytes);

    try run(allocator, &host, spec.bytes);

    // Recover the guest's stored result-pointer at memory[0..4]: the
    // i32 fp_ptr the host wrote into the scratch region. We re-parse +
    // re-instantiate to read memory back; instead, we verify the
    // identity by recomputing Blake3 from the host's view.
    var expected: [32]u8 = undefined;
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(input);
    hasher.final(&expected);

    // The host's last allocation in scratch holds the digest. Recompute
    // by running the guest's flow against a fresh module + reading
    // the scratch slot directly. The cleanest assertion: re-run with
    // a fresh host and inspect via the Instance's memory view.
    var module = try runtime.parse(allocator, spec.bytes);
    defer module.deinit();
    var host2 = freshHost(allocator);
    defer host2.deinit();
    host2.beginInvocation("test_fp", [_]u8{0} ** 32, [_]u8{0} ** 32, [_]u8{0} ** 32);
    const bindings = imports_mod.bindAll();
    var instance = try runtime.Instance.init(allocator, &module, .{
        .imports = &bindings,
        .host_context = &host2,
    });
    defer instance.deinit();
    host2.attach(32768, 32768);
    try instance.invokeStart();

    // Read the i32 the guest stored at memory[0..4] — that's the
    // fp_ptr the import returned.
    const fp_ptr_u: u32 = std.mem.readInt(u32, instance.memory[0..4], .little);
    const fp_ptr: usize = @intCast(fp_ptr_u);
    try std.testing.expect(fp_ptr + 32 <= instance.memory.len);
    try std.testing.expectEqualSlices(u8, &expected, instance.memory[fp_ptr .. fp_ptr + 32]);
}

test "dreamball.encode_cbor wraps bytes in canonical byte-string header" {
    const allocator = std.testing.allocator;
    const input: []const u8 = "abc"; // < 24 bytes → single-byte header

    var module: runtime.Module = undefined;
    var host = freshHost(allocator);
    defer host.deinit();
    host.beginInvocation("test_encode_cbor", [_]u8{0} ** 32, [_]u8{0} ** 32, [_]u8{0} ** 32);

    const spec = try guest.buildEncodeCborGuest(allocator, input);
    defer allocator.free(spec.bytes);

    module = try runtime.parse(allocator, spec.bytes);
    defer module.deinit();
    const bindings = imports_mod.bindAll();
    var instance = try runtime.Instance.init(allocator, &module, .{
        .imports = &bindings,
        .host_context = &host,
    });
    defer instance.deinit();
    host.attach(32768, 32768);
    try instance.invokeStart();

    const result_ptr_u: u32 = std.mem.readInt(u32, instance.memory[0..4], .little);
    const result_ptr: usize = @intCast(result_ptr_u);
    // Expected encoding: 0x43 'a' 'b' 'c'  (major type 2, len 3)
    const expected = [_]u8{ 0x43, 'a', 'b', 'c' };
    try std.testing.expectEqualSlices(u8, &expected, instance.memory[result_ptr .. result_ptr + expected.len]);
}

test "dreamball.encode_cbor canonical-length encoding for >= 24 bytes" {
    const allocator = std.testing.allocator;
    const input: []const u8 = "this-string-is-exactly-thirty-bytes!"; // 36 bytes
    try std.testing.expectEqual(@as(usize, 36), input.len);

    var host = freshHost(allocator);
    defer host.deinit();
    host.beginInvocation("test_encode_cbor_long", [_]u8{0} ** 32, [_]u8{0} ** 32, [_]u8{0} ** 32);

    const spec = try guest.buildEncodeCborGuest(allocator, input);
    defer allocator.free(spec.bytes);

    var module = try runtime.parse(allocator, spec.bytes);
    defer module.deinit();
    const bindings = imports_mod.bindAll();
    var instance = try runtime.Instance.init(allocator, &module, .{
        .imports = &bindings,
        .host_context = &host,
    });
    defer instance.deinit();
    host.attach(32768, 32768);
    try instance.invokeStart();

    const result_ptr_u: u32 = std.mem.readInt(u32, instance.memory[0..4], .little);
    const result_ptr: usize = @intCast(result_ptr_u);
    // Expected: 0x58 0x24 <input bytes>
    try std.testing.expectEqual(@as(u8, 0x58), instance.memory[result_ptr]);
    try std.testing.expectEqual(@as(u8, 0x24), instance.memory[result_ptr + 1]);
    try std.testing.expectEqualSlices(u8, input, instance.memory[result_ptr + 2 .. result_ptr + 2 + input.len]);
}

test "dreamball.read_node returns 0 when missing" {
    const allocator = std.testing.allocator;
    var host = freshHost(allocator); // empty nodes slice
    defer host.deinit();
    host.beginInvocation("test_read_node_missing", [_]u8{0} ** 32, [_]u8{0} ** 32, [_]u8{0} ** 32);

    const spec = try guest.buildReadNodeGuest(allocator, "missing-node-id");
    defer allocator.free(spec.bytes);

    var module = try runtime.parse(allocator, spec.bytes);
    defer module.deinit();
    const bindings = imports_mod.bindAll();
    var instance = try runtime.Instance.init(allocator, &module, .{
        .imports = &bindings,
        .host_context = &host,
    });
    defer instance.deinit();
    host.attach(32768, 32768);
    try instance.invokeStart();

    const result: u32 = std.mem.readInt(u32, instance.memory[0..4], .little);
    try std.testing.expectEqual(@as(u32, 0), result);
}

test "dreamball.read_node returns node bytes when present" {
    const allocator = std.testing.allocator;
    const node_id: []const u8 = "alpha";
    const node_bytes: []const u8 = "alpha-node-payload";
    const nodes = [_]imports_mod.Node{
        .{ .id = node_id, .bytes = node_bytes },
    };

    const seed: [32]u8 = .{0x42} ** 32;
    const kp = try Ed25519.KeyPair.generateDeterministic(seed);
    var host = imports_mod.Host.init(allocator, kp.secret_key.toBytes(), &nodes);
    defer host.deinit();
    host.beginInvocation("test_read_node_hit", [_]u8{0} ** 32, [_]u8{0} ** 32, [_]u8{0} ** 32);

    const spec = try guest.buildReadNodeGuest(allocator, node_id);
    defer allocator.free(spec.bytes);

    var module = try runtime.parse(allocator, spec.bytes);
    defer module.deinit();
    const bindings = imports_mod.bindAll();
    var instance = try runtime.Instance.init(allocator, &module, .{
        .imports = &bindings,
        .host_context = &host,
    });
    defer instance.deinit();
    host.attach(32768, 32768);
    try instance.invokeStart();

    const result_ptr_u: u32 = std.mem.readInt(u32, instance.memory[0..4], .little);
    try std.testing.expect(result_ptr_u != 0);
    const result_ptr: usize = @intCast(result_ptr_u);
    try std.testing.expectEqualSlices(u8, node_bytes, instance.memory[result_ptr .. result_ptr + node_bytes.len]);
}

test "dreamball.emit_action_envelope produces a verifiable Ed25519 signature" {
    const allocator = std.testing.allocator;
    const seed: [32]u8 = .{0x42} ** 32;
    const kp = try Ed25519.KeyPair.generateDeterministic(seed);
    var host = imports_mod.Host.init(allocator, kp.secret_key.toBytes(), &.{});
    defer host.deinit();
    host.beginInvocation("test_emit", [_]u8{0} ** 32, [_]u8{0} ** 32, [_]u8{0} ** 32);

    const payload: []const u8 = "test-action-payload";
    const spec = try guest.buildEmitGuest(allocator, payload);
    defer allocator.free(spec.bytes);

    var module = try runtime.parse(allocator, spec.bytes);
    defer module.deinit();
    const bindings = imports_mod.bindAll();
    var instance = try runtime.Instance.init(allocator, &module, .{
        .imports = &bindings,
        .host_context = &host,
    });
    defer instance.deinit();
    host.attach(32768, 32768);
    try instance.invokeStart();

    // SEC2: host *always* signed; one envelope was promoted to staging.
    try std.testing.expectEqual(@as(usize, 1), host.emitted.items.len);
    try std.testing.expectEqual(@as(u32, 1), host.emit_count);
    const env = host.emitted.items[0];
    try std.testing.expectEqualSlices(u8, payload, env.payload);

    // Verify the signature against the host's keypair public-key.
    const sig_arr: [64]u8 = env.signature;
    const sig = Ed25519.Signature.fromBytes(sig_arr);
    try sig.verify(payload, kp.public_key);
}

test "dreamball.now_ms is monotonic across two consecutive calls" {
    const allocator = std.testing.allocator;
    var host = freshHost(allocator);
    defer host.deinit();
    host.beginInvocation("test_now_ms", [_]u8{0} ** 32, [_]u8{0} ** 32, [_]u8{0} ** 32);

    const spec = try guest.buildNowMsGuest(allocator);
    defer allocator.free(spec.bytes);

    var module = try runtime.parse(allocator, spec.bytes);
    defer module.deinit();
    const bindings = imports_mod.bindAll();
    var instance = try runtime.Instance.init(allocator, &module, .{
        .imports = &bindings,
        .host_context = &host,
    });
    defer instance.deinit();
    host.attach(32768, 32768);
    try instance.invokeStart();

    // The guest discarded both i64 returns. The Host's monotonicity
    // contract says: across the two calls inside _start, host.last_now_ms
    // never decreased; we observe that the second call set it.
    // (We can't observe both values directly without storing them in
    // memory; the contract is trivially satisfied because the import
    // implementation clamps to last_now_ms. The test below cross-checks
    // by calling now_ms directly through the import binding twice.)
    var out_a: ?runtime.Value = null;
    var out_b: ?runtime.Value = null;
    try imports_mod.now_ms(&instance, &.{}, &out_a);
    try imports_mod.now_ms(&instance, &.{}, &out_b);
    try std.testing.expect(out_a.?.i64 <= out_b.?.i64);
}

test "AC8 grep audit — IMPORT_NAMES contains exactly 5 entries" {
    try std.testing.expectEqual(@as(usize, 5), imports_mod.IMPORT_NAMES.len);
    // Asserts the locked names in declaration order; mirrors the
    // grep-audit regex from Story 5.2 AC8.
    const expected = [_][]const u8{
        "fp", "encode_cbor", "read_node", "emit_action_envelope", "now_ms",
    };
    for (expected, 0..) |name, i| {
        try std.testing.expectEqualStrings(name, imports_mod.IMPORT_NAMES[i]);
    }
}
