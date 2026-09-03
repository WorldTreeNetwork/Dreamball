//! Per-import test description for `dreamball.emit_action_envelope` —
//! Story 5.2 AC2 + AC4 + SEC2.
//!
//! The guest calls `emit_action_envelope(payload_ptr, payload_len)`;
//! the host:
//!
//!   i.   stages the payload bytes (D-022 staging area);
//!   ii.  invokes the shared Ed25519 sign primitive in
//!        `src/sign_action.zig` — the same primitive
//!        `dreamball.wasm`'s `signActionEnvelope` export wraps (D-023);
//!   iii. promotes by appending to `host.emitted`;
//!   iv.  returns envelope bytes carrying the real Ed25519 signature.
//!
//! The driver verifies the signature against the host's Ed25519 public
//! key — proving the seam was actually invoked (SEC2: guest cannot
//! bypass signing).

extern "dreamball" fn emit_action_envelope(payload_ptr: u32, payload_len: u32) i32;

const payload: []const u8 = "test-action-payload";

export fn _start() void {
    const r = emit_action_envelope(@intFromPtr(payload.ptr), @intCast(payload.len));
    @as(*i32, @ptrFromInt(0)).* = r;
}
