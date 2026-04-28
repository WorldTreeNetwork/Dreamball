//! Hand-authored builders for hello.wasm and hello-bad.wasm.
//!
//! Why hand-author? See
//! `docs/decisions/2026-04-28-wasm-runtime-selection.md`. The spike
//! engine is an in-tree Zig interpreter scoped to exactly what these
//! two guests need; pinning the bytes here keeps the interpreter's
//! opcode coverage auditable. Story 5.2 grows the interpreter to
//! handle Zig→wasm-compiled guests.
//!
//! The two guests share most structure; differences:
//!   - `hello.wasm`: imports `wasi_snapshot_preview1.fd_write`
//!     (type: `(i32 i32 i32 i32) -> i32`) and writes a marker to
//!     fd 1 via fd_write.
//!   - `hello-bad.wasm`: imports `env.malicious_function`
//!     (type: `(i32) -> i32`); the spike host's whitelist must
//!     reject this at instantiation (AC5).
//!
//! Memory layout for hello.wasm (single data segment at addr 0):
//!   0..27   marker bytes ("HELLO_FROM_DREAMBALL_SPIKE\n")
//!   28..36  ciovec_t: { buf: u32 = 0, len: u32 = 27 }
//!   40..44  nwritten output slot (host writes here)
//!
//! Function body for hello.wasm `_start`:
//!   i32.const 1            ;; fd = stdout
//!   i32.const 28           ;; iovs_ptr
//!   i32.const 1            ;; iovs_len
//!   i32.const 40           ;; nwritten_ptr
//!   call 0                 ;; fd_write (import 0)
//!   drop                   ;; discard errno
//!   end
//!
//! Function body for hello-bad.wasm `_start`:
//!   i32.const 0xdead
//!   call 0                 ;; malicious_function (import 0)
//!   drop
//!   end

const std = @import("std");

pub const marker: []const u8 = "HELLO_FROM_DREAMBALL_SPIKE\n";

const Builder = struct {
    buf: std.ArrayList(u8),

    fn init() Builder {
        return .{ .buf = .empty };
    }

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

/// Encode a section: byte for section id, ULEB len, payload bytes.
fn encodeSection(allocator: std.mem.Allocator, out: *Builder, id: u8, payload: []const u8) !void {
    try out.writeByte(allocator, id);
    try out.writeULeb(allocator, payload.len);
    try out.writeBytes(allocator, payload);
}

/// Build the hello.wasm bytes.
pub fn buildHello(allocator: std.mem.Allocator) ![]u8 {
    var out = Builder.init();
    errdefer out.deinit(allocator);

    // Magic + version.
    try out.writeBytes(allocator, &.{ 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00 });

    // Section 1: types.
    {
        var s = Builder.init();
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 2); // 2 types
        // type 0: (i32 i32 i32 i32) -> i32  (fd_write)
        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 4);
        try s.writeBytes(allocator, &.{ 0x7f, 0x7f, 0x7f, 0x7f });
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x7f);
        // type 1: () -> ()  (_start)
        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 0);
        try s.writeULeb(allocator, 0);
        try encodeSection(allocator, &out, 1, s.buf.items);
    }

    // Section 2: imports.
    {
        var s = Builder.init();
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1); // 1 import
        try s.writeName(allocator, "wasi_snapshot_preview1");
        try s.writeName(allocator, "fd_write");
        try s.writeByte(allocator, 0x00); // import desc: function
        try s.writeULeb(allocator, 0); // type idx 0
        try encodeSection(allocator, &out, 2, s.buf.items);
    }

    // Section 3: functions (defined in this module).
    {
        var s = Builder.init();
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeULeb(allocator, 1); // _start uses type 1
        try encodeSection(allocator, &out, 3, s.buf.items);
    }

    // Section 5: memory.
    {
        var s = Builder.init();
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x00); // limits flag: no max
        try s.writeULeb(allocator, 1); // min = 1 page (64 KiB)
        try encodeSection(allocator, &out, 5, s.buf.items);
    }

    // Section 7: exports.
    {
        var s = Builder.init();
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 2);
        // export "memory" -> mem 0
        try s.writeName(allocator, "memory");
        try s.writeByte(allocator, 0x02); // export desc: memory
        try s.writeULeb(allocator, 0);
        // export "_start" -> func 1 (func 0 is the import; func 1 is _start)
        try s.writeName(allocator, "_start");
        try s.writeByte(allocator, 0x00); // export desc: function
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 7, s.buf.items);
    }

    // Section 10: code.
    {
        var s = Builder.init();
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1); // 1 body

        var body = Builder.init();
        defer body.deinit(allocator);
        try body.writeULeb(allocator, 0); // 0 local groups
        // body opcodes
        try body.writeByte(allocator, 0x41); // i32.const
        try body.writeSLeb(allocator, 1);
        try body.writeByte(allocator, 0x41);
        try body.writeSLeb(allocator, 28);
        try body.writeByte(allocator, 0x41);
        try body.writeSLeb(allocator, 1);
        try body.writeByte(allocator, 0x41);
        try body.writeSLeb(allocator, 40);
        try body.writeByte(allocator, 0x10); // call
        try body.writeULeb(allocator, 0); // funcidx 0 (the import)
        try body.writeByte(allocator, 0x1a); // drop
        try body.writeByte(allocator, 0x0b); // end

        try s.writeULeb(allocator, body.buf.items.len);
        try s.writeBytes(allocator, body.buf.items);
        try encodeSection(allocator, &out, 10, s.buf.items);
    }

    // Section 11: data.
    {
        var s = Builder.init();
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1); // 1 data segment

        // data segment: mode 0 (active, mem 0, offset i32.const 0), bytes
        try s.writeULeb(allocator, 0); // mode 0
        // init expr: i32.const 0; end
        try s.writeByte(allocator, 0x41);
        try s.writeSLeb(allocator, 0);
        try s.writeByte(allocator, 0x0b);

        // payload bytes:
        // 0..27   = marker (27 bytes)
        // 27      = padding (1 byte) so ciovec is 4-byte aligned at 28
        // 28..36  = ciovec { buf=0u32, len=27u32 } little-endian
        var payload = Builder.init();
        defer payload.deinit(allocator);
        try payload.writeBytes(allocator, marker);
        try payload.writeByte(allocator, 0); // alignment padding
        try payload.writeBytes(allocator, &.{ 0, 0, 0, 0 }); // buf = 0
        try payload.writeBytes(allocator, &.{ 0x1b, 0, 0, 0 }); // len = 27

        try s.writeULeb(allocator, payload.buf.items.len);
        try s.writeBytes(allocator, payload.buf.items);
        try encodeSection(allocator, &out, 11, s.buf.items);
    }

    return out.buf.toOwnedSlice(allocator);
}

/// Build the hello-bad.wasm bytes — same shape but the import is
/// `env.malicious_function : (i32) -> i32` instead of WASI fd_write.
pub fn buildHelloBad(allocator: std.mem.Allocator) ![]u8 {
    var out = Builder.init();
    errdefer out.deinit(allocator);

    try out.writeBytes(allocator, &.{ 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00 });

    // Type section: 2 types.
    //  type 0: (i32) -> i32   (malicious_function)
    //  type 1: () -> ()       (_start)
    {
        var s = Builder.init();
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 2);
        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x7f);
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x7f);

        try s.writeByte(allocator, 0x60);
        try s.writeULeb(allocator, 0);
        try s.writeULeb(allocator, 0);
        try encodeSection(allocator, &out, 1, s.buf.items);
    }

    // Imports: env.malicious_function
    {
        var s = Builder.init();
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeName(allocator, "env");
        try s.writeName(allocator, "malicious_function");
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 0);
        try encodeSection(allocator, &out, 2, s.buf.items);
    }

    // Functions.
    {
        var s = Builder.init();
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeULeb(allocator, 1); // _start uses type 1
        try encodeSection(allocator, &out, 3, s.buf.items);
    }

    // Memory (min 1 page; the bad guest doesn't actually use it but
    // the host parses + validates a memory section as part of normal
    // module loading).
    {
        var s = Builder.init();
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 5, s.buf.items);
    }

    // Exports.
    {
        var s = Builder.init();
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);
        try s.writeName(allocator, "_start");
        try s.writeByte(allocator, 0x00);
        try s.writeULeb(allocator, 1);
        try encodeSection(allocator, &out, 7, s.buf.items);
    }

    // Code.
    {
        var s = Builder.init();
        defer s.deinit(allocator);
        try s.writeULeb(allocator, 1);

        var body = Builder.init();
        defer body.deinit(allocator);
        try body.writeULeb(allocator, 0);
        try body.writeByte(allocator, 0x41); // i32.const
        try body.writeSLeb(allocator, 0xdead);
        try body.writeByte(allocator, 0x10); // call
        try body.writeULeb(allocator, 0);
        try body.writeByte(allocator, 0x1a); // drop
        try body.writeByte(allocator, 0x0b); // end

        try s.writeULeb(allocator, body.buf.items.len);
        try s.writeBytes(allocator, body.buf.items);
        try encodeSection(allocator, &out, 10, s.buf.items);
    }

    return out.buf.toOwnedSlice(allocator);
}
