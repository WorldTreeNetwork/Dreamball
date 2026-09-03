//! Per-import test description for `dreamball.read_node` — Story 5.2 AC2.
//!
//! `read_node(id_ptr, id_len)` returns 0 when no node with that id
//! exists; otherwise returns a pointer into the host scratch region
//! holding the node's bytes. Driver asserts both branches: missing-id
//! → 0; present id "alpha" → bytes "alpha-node-payload".
//!
//! Per D-022 the production wiring reads from a LadybugDB adapter; the
//! sprint-002 host carries an in-memory `Node` slice supplied by the
//! caller (`Host.init(..., nodes)`). The import surface is identical
//! across both wirings.

extern "dreamball" fn read_node(id_ptr: u32, id_len: u32) i32;

const id: []const u8 = "alpha";

export fn _start() void {
    const r = read_node(@intFromPtr(id.ptr), @intCast(id.len));
    @as(*i32, @ptrFromInt(0)).* = r;
}
