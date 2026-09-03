//! hello.wasm — minimal WASI guest for Story 5.1's wasm runtime spike.
//!
//! Goals (per Story 5.1 ACs 2 + 4):
//!   - The corresponding `hello.wasm` binary imports
//!     `wasi_snapshot_preview1.fd_write` and writes a known marker
//!     to fd 1 (stdout) when its `_start` export is invoked.
//!   - The spike host brokers the call and the marker appears on
//!     host stdout.
//!
//! ## Why this file is a *description*, not the actual compiled guest
//!
//! The spike's runtime is an **in-tree Zig wasm interpreter**
//! (`src/wasm-host/spike/`). To keep the interpreter scope honest for
//! a spike, the canonical `hello.wasm` artefact is built from
//! deliberately hand-authored bytes
//! (`src/wasm-host/spike/build_hello.zig`) — every opcode in that
//! artefact is one the interpreter knows how to execute. See
//! `docs/decisions/2026-04-28-wasm-runtime-selection.md` for the
//! engine-choice rationale.
//!
//! This file describes the *equivalent* Zig source so a future
//! reader can see at a glance what the bytes are doing. Story 5.2
//! will replace the hand-authored bytes with a proper Zig→wasm
//! compile once the interpreter grows the opcode coverage.
//!
//! Per D-032 + TC4 + Story 5.1 AC4: WASI imports MUST be the only
//! host seam this guest uses. No `env.*` imports.
//!
//! See also `tests/wasm/hello-bad/main.zig` for the AC5 negative case.

// ciovec_t per WASI snapshot_preview1: { buf: ptr<u8>, len: u32 }.
const Ciovec = extern struct {
    buf: [*]const u8,
    len: u32,
};

// `fd_write(fd, iovs_ptr, iovs_len, nwritten_out_ptr) -> errno`.
extern "wasi_snapshot_preview1" fn fd_write(
    fd: i32,
    iovs: [*]const Ciovec,
    iovs_len: i32,
    nwritten: *u32,
) i32;

pub const marker: []const u8 = "HELLO_FROM_DREAMBALL_SPIKE\n";

export fn _start() void {
    var iov = [_]Ciovec{.{ .buf = marker.ptr, .len = @intCast(marker.len) }};
    var nwritten: u32 = 0;
    _ = fd_write(1, &iov, 1, &nwritten);
}
