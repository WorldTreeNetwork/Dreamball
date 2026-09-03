//! Per-import test description for `dreamball.now_ms` — Story 5.2 AC2 + AC5.
//!
//! `now_ms()` returns a u64 monotonic millisecond timestamp. The
//! driver calls the import twice and asserts the second call's value
//! is ≥ the first (AC5). The Host clamps to `last_now_ms` defensively
//! so non-monotonic platforms still satisfy the contract.

extern "dreamball" fn now_ms() i64;

export fn _start() void {
    _ = now_ms();
    _ = now_ms();
}
