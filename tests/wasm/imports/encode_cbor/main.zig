//! Per-import test description for `dreamball.encode_cbor` — Story 5.2 AC2.
//!
//! Wraps the guest-supplied bytes in a canonical dCBOR byte-string
//! header (major type 2, smallest-length encoding per
//! `src/dcbor.zig`). The driver asserts:
//!
//!   - `encode_cbor("abc")` produces the exact bytes `0x43 'a' 'b' 'c'`
//!     (single-byte header for len < 24).
//!   - 36-byte input produces `0x58 0x24 <bytes>` (1-byte length
//!     extension for len < 0x100).
//!
//! Equivalent Zig source for the hand-authored guest at
//! `src/wasm-host/build_guest.zig` `buildEncodeCborGuest`.

extern "dreamball" fn encode_cbor(input_ptr: u32, input_len: u32) i32;

const input: []const u8 = "abc";

export fn _start() void {
    const r = encode_cbor(@intFromPtr(input.ptr), @intCast(input.len));
    @as(*i32, @ptrFromInt(0)).* = r;
}
