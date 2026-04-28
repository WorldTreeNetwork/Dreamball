//! Per-import test description for `dreamball.fp` — Story 5.2 AC2 / AC3.
//!
//! Equivalent Zig source for the hand-authored guest the
//! `imports_test.zig` driver builds (`guest.buildFpGuest`). Same
//! pattern as `tests/wasm/hello/main.zig`: this file is a *description*
//! a future reader can use to understand what the bytes do — the
//! authoritative bytes come from `src/wasm-host/build_guest.zig`.
//!
//! The driver instantiates against the production
//! `imports.bindAll()` surface, calls `_start`, and reads
//! `memory[0..4]` for the i32 fp_ptr the import returned. The
//! assertion (AC3): the 32 bytes at fp_ptr equal
//! `blake3(input_bytes)` computed independently by the test.

extern "dreamball" fn fp(input_ptr: u32, input_len: u32) i32;

const input: []const u8 = "hello-dreamball-fp";

export fn _start() void {
    const r = fp(@intFromPtr(input.ptr), @intCast(input.len));
    @as(*i32, @ptrFromInt(0)).* = r;
}
