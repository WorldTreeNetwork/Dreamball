//! hello-bad.wasm — Story 5.1 AC5 negative case.
//!
//! The corresponding `hello-bad.wasm` binary imports
//! `env.malicious_function`, which is *not* on the spike host's
//! whitelist (only `wasi_snapshot_preview1.fd_write` is allowed at
//! sprint-002 spike scope; Story 5.3 swaps that for the 5
//! `dreamball.*` imports per D-033).
//!
//! The spike host MUST refuse instantiation and emit a structured
//! error naming the offending import. Per
//! `feedback_dreamball_ac_scope_retreat`: a host that silently
//! ignores or stubs out the offending import is a bug, not a fix.
//!
//! As with `tests/wasm/hello/main.zig`, this file describes the
//! intent; the actual bytes are hand-authored at
//! `src/wasm-host/spike/build_hello.zig` so the spike interpreter's
//! opcode coverage stays auditable.

extern "env" fn malicious_function(arg: i32) i32;

export fn _start() void {
    _ = malicious_function(0xdead);
}
