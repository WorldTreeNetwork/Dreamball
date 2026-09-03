//! Hand-authored wasm guest builders for the Story 5.2 production host.
//!
//! Like `src/wasm-host/spike/build_hello.zig`, these builders pin the
//! exact opcodes the production guests use so the in-tree interpreter's
//! coverage stays auditable. Each builder is a function that emits the
//! bytes for one guest scoped to one import (or, for the production
//! self-test guest, the AC4 happy-path).
//!
//! Story 5.4 will replace this with Zig→wasm compilation. Until then,
//! hand-authored bytes keep the runtime-selection ADR's "each new
//! opcode is one switch arm" growth model honest.

const std = @import("std");

const Builder = struct {
    buf: std.ArrayList(u8) = .empty,

    fn deinit(self: *Builder, allocator: std.mem.Allocator) void {
        self.buf.deinit(allocator);
    }

    fn writeByte(self: *Builder, allocator: std.mem.Allocator, b: u8) !void {
        try self.buf.append(allocator, b);
    }

    fn writeBytes(self: *Builder, allocator: std.mem.Allocator, bs: []const u8) !void {
        try self.buf.appendSlice(allocator, bs);
    }

    fn writeULeb(self: *Builder, allocator: std.mem.Allocator, value: u64) !void {
        var v = value;
        while (true) {
            var byte: u8 = @intCast(v & 0x7f);
            v >>= 7;
            if (v != 0) byte |= 0x80;
            try self.buf.append(allocator, byte);
            if (v == 0) break;
        }
    }

    fn writeSLeb(self: *Builder, allocator: std.mem.Allocator, value: i64) !void {
        var v = value;
        while (true) {
            const byte_low: u8 = @intCast(@as(u64, @bitCast(v)) & 0x7f);
            const sign_bit = (byte_low & 0x40) != 0;
            v >>= 7;
            const more = !((v == 0 and !sign_bit) or (v == -1 and sign_bit));
            const byte: u8 = if (more) byte_low | 0x80 else byte_low;
            try self.buf.append(allocator, byte);
            if (!more) break;
        }
    }

    fn writeName(self: *Builder, allocator: std.mem.Allocator, name: []const u8) !void {
        try self.writeULeb(allocator, name.len);
        try self.buf.appendSlice(allocator, name);
    }
};

fn encodeSection(allocator: std.mem.Allocator, out: *Builder, id: u8, payload: []const u8) !void {
    try out.writeByte(allocator, id);
    try out.writeULeb(allocator, payload.len);
    try out.writeBytes(allocator, payload);
}

/// Production self-test guest: imports `dreamball.emit_action_envelope`
/// and calls it once from `_start` with a small payload baked into a
/// data segment. Demonstrates the AC4 path end-to-end.
///
/// Memory layout:
///   0..N    payload bytes ("dreamball-prod-guest-payload")
///
/// Guest body for `_start`:
///   i32.const PAYLOAD_PTR  ;; 4096 (above host scratch region)
///   i32.const PAYLOAD_LEN
///   call 0                 ;; emit_action_envelope (import 0)
///   drop                   ;; discard envelope_ptr return
///   end
pub fn buildProdGuest(allocator: std.mem.Allocator) ![]u8 {
    const payload: []const u8 = "dreamball-prod-guest-payload";
    const payload_ptr: i32 = 4096;

    var out: Builder = .{};
    errdefer out.deinit(allocator);

    try out.writeBytes(allocator, &.{ 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00 });

    // Type section: 2 types.
    //   0: (i32 i32) -> i32   emit_action_envelope
    //   1: () -> ()           _start
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 2);
        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 2);
        try s.writeBytes(allocator, &.{ 0x7f, 0x7f });
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x7f);

        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 0);
        try s.writeULeb(allocator, 0);

        try encodeSection(allocator, &out, 1, s.buf.items);
    }

    // Imports: dreamball.emit_action_envelope
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeName(allocator, "dreamball");
        try s.writeName(allocator, "emit_action_envelope");
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 0);
        try encodeSection(allocator, &out, 2, s.buf.items);
    }

    // Functions: 1 defined, type 1.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 3, s.buf.items);
    }

    // Memory: 1 page.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 5, s.buf.items);
    }

    // Exports: memory + _start.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 2);
        try s.writeName(allocator, "memory");
        try s.writeByte(allocator, 0x02);
        try s.writeULeb(allocator, 0);
        try s.writeName(allocator, "_start");
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 7, s.buf.items);
    }

    // Code: _start.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);

        var body: Builder = .{};
        defer body.deinit(allocator);
        try body.writeULeb(allocator, 0); // 0 local groups
        try body.writeByte(allocator, 0x41); // i32.const
        try body.writeSLeb(allocator, payload_ptr);
        try body.writeByte(allocator, 0x41);
        try body.writeSLeb(allocator, @intCast(payload.len));
        try body.writeByte(allocator, 0x10); // call funcidx 0
        try body.writeULeb(allocator, 0);
        try body.writeByte(allocator, 0x1a); // drop
        try body.writeByte(allocator, 0x0b); // end

        try s.writeULeb(allocator, body.buf.items.len);
        try s.writeBytes(allocator, body.buf.items);
        try encodeSection(allocator, &out, 10, s.buf.items);
    }

    // Data: payload at addr 4096.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeULeb(allocator, 0); // mode 0 (active, mem 0)
        try s.writeByte(allocator, 0x41); // i32.const
        try s.writeSLeb(allocator, payload_ptr);
        try s.writeByte(allocator, 0x0b); // end
        try s.writeULeb(allocator, payload.len);
        try s.writeBytes(allocator, payload);
        try encodeSection(allocator, &out, 11, s.buf.items);
    }

    return out.buf.toOwnedSlice(allocator);
}

/// Per-import test guests. Each guest exposes a `test_<import>`
/// exported function that calls the import once with a known input
/// and writes the import's return into the start of linear memory so
/// the host can assert against it.
///
/// All guests share a memory layout:
///   0..3    "result low" — primary i32 return from the import.
///   4..7    "result high" — secondary i32 (length) for multi-result
///                            imports.
///   8..    input bytes / scratch for the import call.

pub const TestGuestSpec = struct {
    /// Import this guest binds (one of the 5 names in
    /// `imports.zig.IMPORT_NAMES`).
    import_name: []const u8,
    /// Wasm bytes the test guest comprises.
    bytes: []u8,
    /// Where the guest stores the import's primary i32 return (in
    /// guest linear memory). The host reads from here to assert.
    primary_addr: u32 = 0,
    /// Input bytes the host should write into guest memory before
    /// invoking the guest. Empty for `now_ms`.
    input_offset: u32 = 16,
    input_bytes: []const u8 = "",
};

/// Build a guest that calls `dreamball.fp(input_ptr, input_len)` and
/// stores the i32 fp_ptr return at memory[0..4].
pub fn buildFpGuest(allocator: std.mem.Allocator, input: []const u8) !TestGuestSpec {
    const bytes = try buildSingleArgGuest(allocator, .{
        .import_module = "dreamball",
        .import_name = "fp",
        .input_offset = 16,
        .input_bytes = input,
        .primary_result_addr = 0,
    });
    return .{
        .import_name = "fp",
        .bytes = bytes,
        .primary_addr = 0,
        .input_offset = 16,
        .input_bytes = input,
    };
}

/// Build a guest for `dreamball.encode_cbor(input_ptr, input_len)`.
pub fn buildEncodeCborGuest(allocator: std.mem.Allocator, input: []const u8) !TestGuestSpec {
    const bytes = try buildSingleArgGuest(allocator, .{
        .import_module = "dreamball",
        .import_name = "encode_cbor",
        .input_offset = 16,
        .input_bytes = input,
        .primary_result_addr = 0,
    });
    return .{
        .import_name = "encode_cbor",
        .bytes = bytes,
        .primary_addr = 0,
        .input_offset = 16,
        .input_bytes = input,
    };
}

/// Build a guest for `dreamball.read_node(node_id_ptr, node_id_len)`.
pub fn buildReadNodeGuest(allocator: std.mem.Allocator, node_id: []const u8) !TestGuestSpec {
    const bytes = try buildSingleArgGuest(allocator, .{
        .import_module = "dreamball",
        .import_name = "read_node",
        .input_offset = 16,
        .input_bytes = node_id,
        .primary_result_addr = 0,
    });
    return .{
        .import_name = "read_node",
        .bytes = bytes,
        .primary_addr = 0,
        .input_offset = 16,
        .input_bytes = node_id,
    };
}

/// Build a guest for `dreamball.emit_action_envelope(payload_ptr, len)`.
pub fn buildEmitGuest(allocator: std.mem.Allocator, payload: []const u8) !TestGuestSpec {
    const bytes = try buildSingleArgGuest(allocator, .{
        .import_module = "dreamball",
        .import_name = "emit_action_envelope",
        .input_offset = 16,
        .input_bytes = payload,
        .primary_result_addr = 0,
    });
    return .{
        .import_name = "emit_action_envelope",
        .bytes = bytes,
        .primary_addr = 0,
        .input_offset = 16,
        .input_bytes = payload,
    };
}

/// Build a guest for `dreamball.now_ms()`. The guest calls now_ms twice
/// and stores both i64 results at memory[0..8] and memory[8..16].
pub fn buildNowMsGuest(allocator: std.mem.Allocator) !TestGuestSpec {
    var out: Builder = .{};
    errdefer out.deinit(allocator);

    try out.writeBytes(allocator, &.{ 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00 });

    // Types:
    //   0: () -> i64   now_ms
    //   1: () -> ()    _start
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 2);
        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 0);
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x7e); // i64

        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 0);
        try s.writeULeb(allocator, 0);
        try encodeSection(allocator, &out, 1, s.buf.items);
    }

    // Imports: dreamball.now_ms
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeName(allocator, "dreamball");
        try s.writeName(allocator, "now_ms");
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 0);
        try encodeSection(allocator, &out, 2, s.buf.items);
    }

    // Functions: 1 defined, type 1.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 3, s.buf.items);
    }

    // Memory.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 5, s.buf.items);
    }

    // Exports.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 2);
        try s.writeName(allocator, "memory");
        try s.writeByte(allocator, 0x02);
        try s.writeULeb(allocator, 0);
        try s.writeName(allocator, "_start");
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 7, s.buf.items);
    }

    // Code: drop the i64 return rather than storing it (host reads
    // last_now_ms from Host directly; the guest just exercises the
    // call path twice for AC5 monotonicity).
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);

        var body: Builder = .{};
        defer body.deinit(allocator);
        try body.writeULeb(allocator, 0);
        try body.writeByte(allocator, 0x10); // call 0
        try body.writeULeb(allocator, 0);
        try body.writeByte(allocator, 0x1a); // drop
        try body.writeByte(allocator, 0x10);
        try body.writeULeb(allocator, 0);
        try body.writeByte(allocator, 0x1a);
        try body.writeByte(allocator, 0x0b); // end

        try s.writeULeb(allocator, body.buf.items.len);
        try s.writeBytes(allocator, body.buf.items);
        try encodeSection(allocator, &out, 10, s.buf.items);
    }

    const bytes = try out.buf.toOwnedSlice(allocator);
    return .{
        .import_name = "now_ms",
        .bytes = bytes,
        .primary_addr = 0,
    };
}

// ─────────────────────────────────────────────────────────────────────────
// Story 5.3 failure-path test guests
// ─────────────────────────────────────────────────────────────────────────

/// Build a wasm guest that imports `env.malicious_function` — an import
/// outside the `dreamball.*` allowlist. Used by the import-violation
/// fixture test (AC2). The host's `verifyImports` check rejects this
/// module BEFORE instantiation.
///
/// Guest body: just calls the bad import once (never actually runs
/// because the host rejects it at load time).
pub fn buildBadImportGuest(allocator: std.mem.Allocator) ![]u8 {
    var out: Builder = .{};
    errdefer out.deinit(allocator);

    try out.writeBytes(allocator, &.{ 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00 });

    // Types:
    //   0: () -> ()   malicious_function
    //   1: () -> ()   _start
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 2);
        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 0);
        try s.writeULeb(allocator, 0);
        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 0);
        try s.writeULeb(allocator, 0);
        try encodeSection(allocator, &out, 1, s.buf.items);
    }

    // Imports: env.malicious_function — outside dreamball.* allowlist.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeName(allocator, "env");
        try s.writeName(allocator, "malicious_function");
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 0);
        try encodeSection(allocator, &out, 2, s.buf.items);
    }

    // Functions: _start.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 3, s.buf.items);
    }

    // Memory: 1 page.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 5, s.buf.items);
    }

    // Exports: _start.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeName(allocator, "_start");
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 7, s.buf.items);
    }

    // Code: _start calls import 0 (unreachable in tests; host rejects first).
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);

        var body: Builder = .{};
        defer body.deinit(allocator);
        try body.writeULeb(allocator, 0);
        try body.writeByte(allocator, 0x10); // call 0
        try body.writeULeb(allocator, 0);
        try body.writeByte(allocator, 0x0b); // end

        try s.writeULeb(allocator, body.buf.items.len);
        try s.writeBytes(allocator, body.buf.items);
        try encodeSection(allocator, &out, 10, s.buf.items);
    }

    return out.buf.toOwnedSlice(allocator);
}

/// Build a wasm guest that declares more memory than `max_mib` allows.
/// The host's `checkMemoryLimit` rejects this module BEFORE instantiation
/// (AC3 / NFR7). Used by the memory-limit fixture test.
///
/// `pages` — number of 64 KiB pages to declare. Pass a value that
/// exceeds the configured limit to trigger the rejection.
pub fn buildOomGuest(allocator: std.mem.Allocator, pages: u32) ![]u8 {
    var out: Builder = .{};
    errdefer out.deinit(allocator);

    try out.writeBytes(allocator, &.{ 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00 });

    // Types:
    //   0: (i32 i32) -> i32   emit_action_envelope (need a valid import)
    //   1: () -> ()           _start
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 2);
        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 2);
        try s.writeBytes(allocator, &.{ 0x7f, 0x7f });
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x7f);

        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 0);
        try s.writeULeb(allocator, 0);
        try encodeSection(allocator, &out, 1, s.buf.items);
    }

    // Imports: dreamball.emit_action_envelope (valid import so import check passes).
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeName(allocator, "dreamball");
        try s.writeName(allocator, "emit_action_envelope");
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 0);
        try encodeSection(allocator, &out, 2, s.buf.items);
    }

    // Functions: _start.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 3, s.buf.items);
    }

    // Memory: `pages` pages — deliberately large to exceed the limit.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, pages);
        try encodeSection(allocator, &out, 5, s.buf.items);
    }

    // Exports: _start.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeName(allocator, "_start");
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 7, s.buf.items);
    }

    // Code: _start is a no-op (host rejects at checkMemoryLimit; never runs).
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);

        var body: Builder = .{};
        defer body.deinit(allocator);
        try body.writeULeb(allocator, 0);
        try body.writeByte(allocator, 0x0b); // end

        try s.writeULeb(allocator, body.buf.items.len);
        try s.writeBytes(allocator, body.buf.items);
        try encodeSection(allocator, &out, 10, s.buf.items);
    }

    return out.buf.toOwnedSlice(allocator);
}

const SingleArgGuestArgs = struct {
    import_module: []const u8,
    import_name: []const u8,
    input_offset: u32,
    input_bytes: []const u8,
    primary_result_addr: u32,
};

/// Build a guest that calls `<import_module>.<import_name>(input_ptr, input_len)`
/// and stores the i32 return at `primary_result_addr`. The input bytes
/// are placed in a data segment at `input_offset`.
fn buildSingleArgGuest(allocator: std.mem.Allocator, args: SingleArgGuestArgs) ![]u8 {
    var out: Builder = .{};
    errdefer out.deinit(allocator);

    try out.writeBytes(allocator, &.{ 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00 });

    // Types:
    //   0: (i32 i32) -> i32   the import
    //   1: () -> ()           _start
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 2);
        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 2);
        try s.writeBytes(allocator, &.{ 0x7f, 0x7f });
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x7f);

        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 0);
        try s.writeULeb(allocator, 0);
        try encodeSection(allocator, &out, 1, s.buf.items);
    }

    // Imports.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeName(allocator, args.import_module);
        try s.writeName(allocator, args.import_name);
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 0);
        try encodeSection(allocator, &out, 2, s.buf.items);
    }

    // Functions.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 3, s.buf.items);
    }

    // Memory.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 5, s.buf.items);
    }

    // Exports.
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 2);
        try s.writeName(allocator, "memory");
        try s.writeByte(allocator, 0x02);
        try s.writeULeb(allocator, 0);
        try s.writeName(allocator, "_start");
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 7, s.buf.items);
    }

    // Code:
    //   _start:
    //     i32.const primary_result_addr  ;; addr for store
    //     i32.const input_offset         ;; ptr arg
    //     i32.const input_len            ;; len arg
    //     call 0                         ;; the import
    //     i32.store offset=0, align=2
    //     end
    {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);

        var body: Builder = .{};
        defer body.deinit(allocator);
        try body.writeULeb(allocator, 0);

        try body.writeByte(allocator, 0x41); // i32.const primary_result_addr
        try body.writeSLeb(allocator, @intCast(args.primary_result_addr));
        try body.writeByte(allocator, 0x41); // i32.const input_offset
        try body.writeSLeb(allocator, @intCast(args.input_offset));
        try body.writeByte(allocator, 0x41); // i32.const input_len
        try body.writeSLeb(allocator, @intCast(args.input_bytes.len));
        try body.writeByte(allocator, 0x10); // call 0
        try body.writeULeb(allocator, 0);
        try body.writeByte(allocator, 0x36); // i32.store
        try body.writeULeb(allocator, 2); // align
        try body.writeULeb(allocator, 0); // offset
        try body.writeByte(allocator, 0x0b); // end

        try s.writeULeb(allocator, body.buf.items.len);
        try s.writeBytes(allocator, body.buf.items);
        try encodeSection(allocator, &out, 10, s.buf.items);
    }

    // Data segment: input bytes at input_offset.
    if (args.input_bytes.len > 0) {
        var s: Builder = .{};
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeULeb(allocator, 0);
        try s.writeByte(allocator, 0x41);
        try s.writeSLeb(allocator, @intCast(args.input_offset));
        try s.writeByte(allocator, 0x0b);
        try s.writeULeb(allocator, args.input_bytes.len);
        try s.writeBytes(allocator, args.input_bytes);
        try encodeSection(allocator, &out, 11, s.buf.items);
    }

    return out.buf.toOwnedSlice(allocator);
}
