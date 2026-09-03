//! `mint-wasm-host` — Story 5.4 driver that loads and runs the
//! production `actions/mint/mint.wasm` module through the wasm host
//! end-to-end (AC2 + AC3 + AC6).
//!
//! Invocation model:
//!   mint-wasm-host <wasm-path> <expected-fp-hex>
//!     [--out-json <path>]
//!
//! Both arguments required:
//!   - `<wasm-path>`        — path to mint.wasm on disk.
//!   - `<expected-fp-hex>`  — 64-char lowercase hex blake3 from the
//!                            archiform schema's
//!                            `x-actions.mint.implementation.wasm`.
//!                            On mismatch the host emits the Story 5.3
//!                            `fp_mismatch` structured event and exits
//!                            non-zero (AC4).
//!
//! Output schema (stdout, one line):
//!   {"palaceFp":"<64-char-hex>"}
//!
//! Output schema (stderr, multi-line JSON events):
//!   {"phase":"verify","status":"match","module_fp":"<hex>"}      [AC3 — before instantiation]
//!   {"action_name":"...","actor_fp":"...",..."outcome":"ok"}     [Story 5.2 invocation event]
//!
//! On fp mismatch (AC4), stderr instead carries:
//!   {"phase":"verify","status":"mismatch","expected":"<hex>","actual":"<hex>","module_fp":"<hex>"}
//!   {"outcome":"fp_mismatch",...}                                [Story 5.3 failure event]
//!
//! ## Why "palaceFp" specifically
//!
//! The Story 5.4 AC2 contract is "the CLI returns a typed `{palaceFp}`
//! JSON output." `palaceFp` here = `blake3(envelope_payload || signature)` —
//! the field-envelope fp pattern used by `palace mint`'s legacy bridge.
//! Sprint-002 spike scope: this host driver is the wasm-route entry
//! point; the projection layer that feeds real palace inputs into the
//! envelope is Story 3.5 work.
//!
//! ## Per D-032 (single shared host)
//!
//! Nothing CLI-specific lives in this file beyond stdout/stderr writes
//! and argv parsing. The browser/dreamball-server hosts (sprint-003) reuse
//! `runtime.zig`, `imports.zig`, and `failure_paths.zig` directly.

const std = @import("std");
const runtime = @import("runtime.zig");
const imports_mod = @import("imports.zig");
const failure = @import("failure_paths.zig");

fn iface() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

fn writeStream(file: std.Io.File, bytes: []const u8) void {
    // Use writeStreamingAll (streaming = no positional seek) so that
    // multiple writes to the same file descriptor append correctly.
    // std.Io.File.writer() defaults to positional mode which resets the
    // write position to 0 on each call, silently overwriting prior output.
    file.writeStreamingAll(iface(), bytes) catch return;
}

fn writeStdout(bytes: []const u8) void {
    writeStream(std.Io.File.stdout(), bytes);
}

fn writeStderr(bytes: []const u8) void {
    writeStream(std.Io.File.stderr(), bytes);
}

fn parseHexFp(hex: []const u8) ![32]u8 {
    if (hex.len != 64) return error.InvalidHexLength;
    var out: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        out[i] = try std.fmt.parseInt(u8, hex[i * 2 .. i * 2 + 2], 16);
    }
    return out;
}

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;

    var args_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args_iter.deinit();

    var argv = std.ArrayList([]const u8).empty;
    defer {
        for (argv.items) |a| gpa.free(a);
        argv.deinit(gpa);
    }
    while (args_iter.next()) |arg| {
        try argv.append(gpa, try gpa.dupe(u8, arg));
    }

    if (argv.items.len < 3) {
        try printErrFmt(gpa, "usage: mint-wasm-host <wasm-path> <expected-fp-hex>\n", .{});
        return 2;
    }

    const wasm_path = argv.items[1];
    const expected_hex = argv.items[2];

    const expected_fp = parseHexFp(expected_hex) catch {
        try printErrFmt(gpa, "{{\"outcome\":\"invalid_fp\",\"detail\":\"expected 64-char hex, got len={d}\"}}\n", .{expected_hex.len});
        return 3;
    };

    // Load the wasm bytes from disk. Per D-032 platform-shimmed I/O
    // lives at the driver layer; the library code stays pure.
    const wasm_bytes = std.Io.Dir.cwd().readFileAlloc(
        iface(),
        wasm_path,
        gpa,
        .limited(64 * 1024 * 1024),
    ) catch |e| {
        try printErrFmt(gpa, "{{\"outcome\":\"read_error\",\"path\":\"{s}\",\"err\":\"{s}\"}}\n", .{ wasm_path, @errorName(e) });
        return 4;
    };
    defer gpa.free(wasm_bytes);

    // Compute actual fp and compare BEFORE any instantiation.
    // AC3: emit the verify event with the resolved status. Per Story
    // 5.3 the verify event fires before instantiation regardless of
    // outcome.
    const actual_fp = failure.computeBlake3(wasm_bytes);
    const matches = std.mem.eql(u8, &actual_fp, &expected_fp);

    const actual_hex: [64]u8 = std.fmt.bytesToHex(actual_fp, .lower);
    if (matches) {
        try printErrFmt(gpa,
            "{{\"phase\":\"verify\",\"status\":\"match\",\"module_fp\":\"{s}\"}}\n",
            .{actual_hex},
        );
    } else {
        const expected_hex_lower: [64]u8 = std.fmt.bytesToHex(expected_fp, .lower);
        try printErrFmt(gpa,
            "{{\"phase\":\"verify\",\"status\":\"mismatch\",\"expected\":\"{s}\",\"actual\":\"{s}\",\"module_fp\":\"{s}\"}}\n",
            .{ expected_hex_lower, actual_hex, actual_hex },
        );
        try printErrFmt(gpa,
            "{{\"outcome\":\"fp_mismatch\",\"expected\":\"{s}\",\"actual\":\"{s}\",\"module_fp\":\"{s}\"}}\n",
            .{ expected_hex_lower, actual_hex, actual_hex },
        );
        return 10;
    }

    // Set up host with deterministic keypair (sprint-002 trusted-by-default
    // per SEC5 — the projection layer feeds the real keypair in sprint-003).
    const seed: [32]u8 = .{0x42} ** 32;
    const kp = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(seed);
    const keypair_bytes = kp.secret_key.toBytes();

    var host = imports_mod.Host.init(gpa, keypair_bytes, &.{});
    defer host.deinit();

    var actor_fp: [32]u8 = undefined;
    var ah = std.crypto.hash.Blake3.init(.{});
    ah.update("actor:palace-mint-wasm");
    ah.final(&actor_fp);
    var archiform_fp: [32]u8 = undefined;
    var arh = std.crypto.hash.Blake3.init(.{});
    arh.update("archiform:dreamball/memory-palace@0.1.0");
    arh.final(&archiform_fp);

    host.beginInvocation("mint", actor_fp, archiform_fp, expected_fp);

    // Verify imports BEFORE instantiation — Story 5.3 AC2 / SEC1 / D-033.
    var module = runtime.parse(gpa, wasm_bytes) catch |e| {
        try printErrFmt(gpa, "{{\"outcome\":\"parse_error\",\"err\":\"{s}\"}}\n", .{@errorName(e)});
        return 11;
    };
    defer module.deinit();

    if (failure.verifyImports(&module)) |bad_import| {
        try printErrFmt(gpa,
            "{{\"outcome\":\"import_violation\",\"offending_import\":\"{s}.{s}\"}}\n",
            .{ bad_import.module, bad_import.name },
        );
        return 12;
    }

    _ = failure.checkMemoryLimit(&module, failure.DEFAULT_MEM_MIB) catch {
        try printErrFmt(gpa, "{{\"outcome\":\"trap\",\"trap_kind\":\"oom\"}}\n", .{});
        return 13;
    };

    const bindings = imports_mod.bindAll();
    var instance = runtime.Instance.init(gpa, &module, .{
        .imports = &bindings,
        .host_context = &host,
    }) catch |e| {
        try printErrFmt(gpa, "{{\"outcome\":\"instantiate_error\",\"err\":\"{s}\"}}\n", .{@errorName(e)});
        return 14;
    };
    defer instance.deinit();

    host.attach(0, 65536);

    instance.invokeStart() catch |e| {
        try printErrFmt(gpa, "{{\"outcome\":\"trap\",\"err\":\"{s}\"}}\n", .{@errorName(e)});
        return 15;
    };

    if (host.emit_count == 0 or host.emitted.items.len == 0) {
        try printErrFmt(gpa, "{{\"outcome\":\"no_emit\",\"detail\":\"guest did not call emit_action_envelope\"}}\n", .{});
        return 16;
    }

    const env = host.emitted.items[0];

    // palaceFp = blake3(payload || signature) — the canonical envelope-fp
    // shape for the wasm-route. Sprint-002 spike — Story 3.5 will feed
    // real palace inputs through; for now this is a deterministic fp
    // over the host-signed envelope bytes.
    var palace_fp: [32]u8 = undefined;
    var ph = std.crypto.hash.Blake3.init(.{});
    ph.update(env.payload);
    ph.update(&env.signature);
    ph.final(&palace_fp);
    const palace_hex: [64]u8 = std.fmt.bytesToHex(palace_fp, .lower);

    // Story 5.2 invocation event (AC7 schema).
    const actor_hex: [64]u8 = std.fmt.bytesToHex(actor_fp, .lower);
    const archiform_hex: [64]u8 = std.fmt.bytesToHex(archiform_fp, .lower);
    try printErrFmt(gpa,
        "{{\"action_name\":\"{s}\",\"actor_fp\":\"{s}\",\"archiform_fp\":\"{s}\",\"module_fp\":\"{s}\",\"emit_count\":{d},\"outcome\":\"ok\"}}\n",
        .{ host.action_name, actor_hex, archiform_hex, actual_hex, host.emit_count },
    );

    // Final stdout JSON: typed `{ palaceFp }` output (AC2).
    try printOutFmt(gpa, "{{\"palaceFp\":\"{s}\"}}\n", .{palace_hex});

    return 0;
}

fn printOutFmt(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(s);
    writeStdout(s);
}

fn printErrFmt(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(s);
    writeStderr(s);
}
