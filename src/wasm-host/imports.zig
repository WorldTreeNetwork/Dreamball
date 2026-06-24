//! `dreamball.*` host-import surface — the 5 sprint-002 locked imports
//! per D-033. Story 5.2 owns this surface; addition or removal of any
//! import here is an architecture-decision event (new ADR), not a
//! story-execution decision (per D-025 + D-033 + the
//! `feedback_dreamball_ac_scope_retreat` discipline).
//!
//! ## Locked surface (AC1, AC8)
//!
//! Exactly five imports exist in this file. The `IMPORT_NAMES` array is
//! the single source of truth; `bindAll` enumerates from it; the AC8
//! grep audit (`grep -E '(?:^|[^a-z_])dreamball\.(?!fp|encode_cbor|read_node|emit_action_envelope|now_ms)'`)
//! must never produce a hit against this directory.
//!
//!   1. `dreamball.fp(bytes_ptr, bytes_len) -> fp_ptr`
//!      Compute `blake3(bytes)` and write the 32-byte digest into a
//!      host-managed slot in the guest's linear memory; return the
//!      pointer to that slot. Identity holds against `src/blake3.zig`'s
//!      Blake3 (see `src/fingerprint.zig`).  AC3.
//!
//!   2. `dreamball.encode_cbor(value_ptr, value_len) -> bytes_ptr,bytes_len`
//!      Wrap the guest-supplied bytes (already CBOR-shaped from the
//!      guest's perspective) in a canonical dCBOR byte-string header and
//!      return the encoded bytes. Sprint-002 happy-path semantics: the
//!      guest passes a value whose canonical CBOR encoding is "byte
//!      string of length N". The host returns the canonical encoding of
//!      that byte string with no allocator drift. The (ptr, len) result
//!      pair is returned via two i32 results.
//!
//!   3. `dreamball.read_node(node_id_ptr, node_id_len) -> node_ptr,node_len`
//!      Read a node from the bridge's read-side surface (per D-022). For
//!      sprint-002 the host carries an in-memory node store seeded by
//!      the host caller (the production wiring to the LadybugDB
//!      read-side adapter is a thin wrapper that lives in the projection
//!      layer; sprint-002's spike maintains parity by exposing the same
//!      read interface in-memory). Returns (0, 0) when the node is not
//!      present.
//!
//!   4. `dreamball.emit_action_envelope(payload_ptr, payload_len) ->
//!      envelope_ptr,envelope_len`
//!      Compose the bridge pattern (D-022) wasm-side:
//!        i.   write the envelope payload to the host's per-invocation
//!             staging area;
//!        ii.  invoke `signActionEnvelope(keypair, payload)` (the same
//!             primitive `dreamball.wasm`'s D-023 export wraps; see
//!             `src/sign_action.zig`) to produce an Ed25519 signature;
//!        iii. on success, promote staging → committed and append the
//!             signed envelope to the host's emit log;
//!        iv.  return envelope-bytes that carry the real signature.
//!      Per SEC2, the guest cannot bypass signing — the host *always*
//!      calls the seam.
//!
//!   5. `dreamball.now_ms() -> u64 (lo i32, hi i32)`
//!      Monotonic millisecond clock reading from the host's clock
//!      source. Two-call monotonicity is checked by the per-import
//!      test (AC5).
//!
//! ## Calling convention (documented inline per Story 5.2 Tech Note)
//!
//!   - Pointers are i32 (wasm32 linear memory addresses, treated as u32
//!     when read by the host).
//!   - Lengths are i32 (treated as u32 by the host).
//!   - Multi-result returns (`fp`, `encode_cbor`, `read_node`,
//!     `emit_action_envelope`) are flattened to (ptr, len) pairs via the
//!     host stashing the second component into a known guest-memory
//!     slot. The guest reads the secondary slot after the primary
//!     return. The slot location is the start of the host-managed
//!     scratch region (see `Host.init`).
//!   - `now_ms` returns a 64-bit value as a single i64 result.
//!
//! ## Per D-032 source-identical between CLI and browser
//!
//! Nothing in this file imports `std.os` or other CLI-only paths. Clock
//! reads use `std.time.milliTimestamp` which is satisfiable by both
//! WASI (CLI) and the browser shim layer. Stderr writes happen through
//! the `Host.log_stream`, supplied by the caller, so the browser host
//! can route NFR11 events to its own diagnostic channel without
//! rewriting this file.

const std = @import("std");
const runtime = @import("runtime.zig");
const sign_action = @import("sign_action");

/// The five locked import names (D-033). Used by `bindAll` and asserted
/// against by the AC8 grep audit.
pub const IMPORT_NAMES = [_][]const u8{
    "fp",
    "encode_cbor",
    "read_node",
    "emit_action_envelope",
    "now_ms",
};

/// Per-invocation outcome — emitted in NFR11 structured-log JSON
/// (`outcome` field). Populated by Host once an invocation completes.
pub const Outcome = enum {
    ok,
    trap,
    import_violation,
    fp_mismatch,
};

pub fn outcomeName(o: Outcome) []const u8 {
    return switch (o) {
        .ok => "ok",
        .trap => "trap",
        .import_violation => "import_violation",
        .fp_mismatch => "fp_mismatch",
    };
}

/// In-memory node store entry for `dreamball.read_node`. The production
/// projection layer wraps this same shape over LadybugDB; sprint-002
/// exposes the wrapping seam as an explicit `Node` slice rather than a
/// callback, keeping the runtime pure.
pub const Node = struct {
    id: []const u8,
    bytes: []const u8,
};

/// Single signed envelope captured from `dreamball.emit_action_envelope`.
/// The host caller (e.g. `dreamball` CLI's wasm-action runner) consumes
/// `host.emitted` after `invokeAction` returns.
pub const EmittedEnvelope = struct {
    payload: []u8,
    signature: [64]u8,
};

/// Host context passed through `runtime.Instance` as `host_context`.
/// All `dreamball.*` import implementations cast `instance.host_context`
/// back to `*Host` — `host_context` is opaque to the runtime per
/// Story 5.2 step 1's "preserve the spike's runtime selection" mandate.
pub const Host = struct {
    allocator: std.mem.Allocator,

    /// Ed25519 keypair used by `emit_action_envelope`. SEC2: guests
    /// cannot read this; only `emit_action_envelope` reaches it.
    keypair: [64]u8,

    /// Read-side node store (sprint-002 in-memory; production wiring is
    /// a thin LadybugDB adapter that fills this slice).
    nodes: []const Node,

    /// Emitted envelopes — the per-invocation "promoted staging" area.
    /// Cleared between invocations by `Host.beginInvocation`.
    emitted: std.ArrayList(EmittedEnvelope),

    /// Per-invocation count of `emit_action_envelope` calls (NFR11).
    emit_count: u32 = 0,

    /// Monotonic clock baseline. Read by `now_ms`.
    clock_zero_ms: i64,

    /// Last value returned by `now_ms` — used to enforce monotonicity
    /// across the same Host (AC5). The clock source itself is monotonic
    /// per std.time.milliTimestamp on darwin/linux; we still clamp here
    /// to be defensive against non-monotonic platforms.
    last_now_ms: u64 = 0,

    /// Where in linear memory the host writes secondary return slots
    /// (multi-result return convention, see file header). Set by
    /// `attach`; before that, host-helpers reject memory writes.
    scratch_base: u32 = 0,
    scratch_cursor: u32 = 0,
    scratch_limit: u32 = 0,

    /// NFR11 invocation context (action name + actor/archiform/module
    /// fps). Cleared between invocations.
    action_name: []const u8 = "",
    actor_fp: [32]u8 = [_]u8{0} ** 32,
    archiform_fp: [32]u8 = [_]u8{0} ** 32,
    module_fp: [32]u8 = [_]u8{0} ** 32,

    pub fn init(allocator: std.mem.Allocator, keypair: [64]u8, nodes: []const Node) Host {
        return .{
            .allocator = allocator,
            .keypair = keypair,
            .nodes = nodes,
            .emitted = .empty,
            .clock_zero_ms = @intCast(@divFloor(std.Io.Clock.real.now(std.Io.Threaded.global_single_threaded.io()).nanoseconds, std.time.ns_per_ms)),
        };
    }

    pub fn deinit(self: *Host) void {
        for (self.emitted.items) |env| {
            self.allocator.free(env.payload);
        }
        self.emitted.deinit(self.allocator);
    }

    /// Reserve a region of guest linear memory the host can use as
    /// a scratch buffer for return values (`fp`, `encode_cbor`,
    /// `read_node`, `emit_action_envelope` outputs all live here). The
    /// caller picks the location; we just remember it.
    pub fn attach(self: *Host, scratch_base: u32, scratch_size: u32) void {
        self.scratch_base = scratch_base;
        self.scratch_cursor = scratch_base;
        self.scratch_limit = scratch_base + scratch_size;
    }

    pub fn beginInvocation(
        self: *Host,
        action_name: []const u8,
        actor_fp: [32]u8,
        archiform_fp: [32]u8,
        module_fp: [32]u8,
    ) void {
        self.action_name = action_name;
        self.actor_fp = actor_fp;
        self.archiform_fp = archiform_fp;
        self.module_fp = module_fp;
        self.emit_count = 0;
        self.scratch_cursor = self.scratch_base;
    }

    fn allocScratch(self: *Host, mem: []u8, size: u32) runtime.Error!u32 {
        if (self.scratch_cursor + size > self.scratch_limit) return runtime.Error.OutOfBounds;
        if (self.scratch_cursor + size > mem.len) return runtime.Error.OutOfBounds;
        const ptr = self.scratch_cursor;
        // Align to 4 bytes for any subsequent allocation.
        const aligned_size = (size + 3) & ~@as(u32, 3);
        self.scratch_cursor += aligned_size;
        return ptr;
    }
};

fn castHost(instance: *runtime.Instance) runtime.Error!*Host {
    const ctx = instance.host_context orelse return runtime.Error.GuestTrap;
    return @ptrCast(@alignCast(ctx));
}

// ─────────────────────────────────────────────────────────────────────────
// 3a. dreamball.fp(bytes_ptr, bytes_len) -> fp_ptr
// ─────────────────────────────────────────────────────────────────────────
//
// Type-marshalling: i32 ptr + i32 len in; i32 fp_ptr out. The host hashes
// the named slice with Blake3 (the same routine used by
// `src/fingerprint.zig`), writes the 32-byte digest into the host
// scratch region, and returns the digest's address.
//
// Error semantics: out-of-bounds slice → trap (Error.OutOfBounds);
// scratch exhaustion → trap (Error.OutOfBounds). No partial writes.
pub fn fp(
    instance: *runtime.Instance,
    args: []const runtime.Value,
    out: *?runtime.Value,
) runtime.Error!void {
    if (args.len != 2) return runtime.Error.GuestTrap;
    const host = try castHost(instance);
    const ptr: u32 = @bitCast(args[0].i32);
    const len: u32 = @bitCast(args[1].i32);
    const mem = instance.memory;
    if (@as(usize, ptr) + @as(usize, len) > mem.len) return runtime.Error.OutOfBounds;

    var digest: [32]u8 = undefined;
    var hasher = std.crypto.hash.Blake3.init(.{});
    hasher.update(mem[ptr .. ptr + len]);
    hasher.final(&digest);

    const slot = try host.allocScratch(mem, 32);
    @memcpy(mem[slot .. slot + 32], &digest);
    out.* = .{ .i32 = @bitCast(slot) };
}

// ─────────────────────────────────────────────────────────────────────────
// 3b. dreamball.encode_cbor(value_ptr, value_len) -> bytes_ptr (len in scratch[0..4])
// ─────────────────────────────────────────────────────────────────────────
//
// Type-marshalling: guest passes a slice (ptr, len) of bytes that the
// guest considers a CBOR value. The host wraps those bytes in the
// canonical dCBOR byte-string header (major type 2) using the smallest
// length encoding (the dcbor canonical rule from `src/dcbor.zig`).
//
// The result pair (ptr, len) is returned as a single i32 ptr; the
// length is written to the scratch slot pointed at by `result_len_ptr`
// stashed at scratch_base+0..4 — guests read it after the call. This
// keeps the wasm import to a single i32 result, which is the simplest
// shape every wasm host (CLI + browser, per D-032) handles uniformly.
//
// Error semantics: out-of-bounds in/out → trap.
pub fn encode_cbor(
    instance: *runtime.Instance,
    args: []const runtime.Value,
    out: *?runtime.Value,
) runtime.Error!void {
    if (args.len != 2) return runtime.Error.GuestTrap;
    const host = try castHost(instance);
    const ptr: u32 = @bitCast(args[0].i32);
    const len: u32 = @bitCast(args[1].i32);
    const mem = instance.memory;
    if (@as(usize, ptr) + @as(usize, len) > mem.len) return runtime.Error.OutOfBounds;

    // dCBOR major type 2 (byte string), canonical-length encoded:
    //   len < 24:        0x40|len
    //   len < 0x100:     0x58 <u8 len>
    //   len < 0x10000:   0x59 <u16 len BE>
    //   len < 0x1_0000_0000: 0x5a <u32 len BE>
    var header: [5]u8 = undefined;
    var header_len: usize = 0;
    if (len < 24) {
        header[0] = 0x40 | @as(u8, @intCast(len));
        header_len = 1;
    } else if (len < 0x100) {
        header[0] = 0x58;
        header[1] = @intCast(len);
        header_len = 2;
    } else if (len < 0x10000) {
        header[0] = 0x59;
        std.mem.writeInt(u16, header[1..3], @intCast(len), .big);
        header_len = 3;
    } else {
        header[0] = 0x5a;
        std.mem.writeInt(u32, header[1..5], len, .big);
        header_len = 5;
    }

    const total_len: u32 = @intCast(header_len + len);

    // Allocate output in scratch; layout: [u32 length][bytes...]
    const len_slot = try host.allocScratch(mem, 4);
    const bytes_slot = try host.allocScratch(mem, total_len);
    if (@as(usize, bytes_slot) + total_len > mem.len) return runtime.Error.OutOfBounds;

    @memcpy(mem[bytes_slot .. bytes_slot + header_len], header[0..header_len]);
    if (len > 0) {
        // Source and dest may not overlap; if they do, copy via a temp.
        if (overlap(mem, ptr, len, bytes_slot + @as(u32, @intCast(header_len)), len)) {
            // Safe path: dupe through host allocator.
            const tmp = try host.allocator.dupe(u8, mem[ptr .. ptr + len]);
            defer host.allocator.free(tmp);
            @memcpy(mem[bytes_slot + @as(u32, @intCast(header_len)) .. bytes_slot + total_len], tmp);
        } else {
            @memcpy(
                mem[bytes_slot + @as(u32, @intCast(header_len)) .. bytes_slot + total_len],
                mem[ptr .. ptr + len],
            );
        }
    }
    std.mem.writeInt(u32, mem[len_slot..][0..4], total_len, .little);

    // Convention: return `bytes_slot` directly; guest reads length from
    // scratch_base[0..4] (the most recently allocated len_slot).
    out.* = .{ .i32 = @bitCast(bytes_slot) };
}

fn overlap(mem: []u8, a_off: u32, a_len: u32, b_off: u32, b_len: u32) bool {
    _ = mem;
    if (a_len == 0 or b_len == 0) return false;
    const a_end = a_off + a_len;
    const b_end = b_off + b_len;
    return !(a_end <= b_off or b_end <= a_off);
}

// ─────────────────────────────────────────────────────────────────────────
// 3c. dreamball.read_node(node_id_ptr, node_id_len) -> node_ptr (len in next-allocated slot)
// ─────────────────────────────────────────────────────────────────────────
//
// Type-marshalling: i32 ptr + i32 len → i32 result_ptr (0 means "not
// found"; non-zero ptr's preceding 4 bytes carry the node-bytes length).
//
// Error semantics: out-of-bounds slice → trap; missing node → returns 0
// (not a trap — guests test presence by checking the result).
pub fn read_node(
    instance: *runtime.Instance,
    args: []const runtime.Value,
    out: *?runtime.Value,
) runtime.Error!void {
    if (args.len != 2) return runtime.Error.GuestTrap;
    const host = try castHost(instance);
    const ptr: u32 = @bitCast(args[0].i32);
    const len: u32 = @bitCast(args[1].i32);
    const mem = instance.memory;
    if (@as(usize, ptr) + @as(usize, len) > mem.len) return runtime.Error.OutOfBounds;
    const id_slice = mem[ptr .. ptr + len];

    for (host.nodes) |node| {
        if (std.mem.eql(u8, node.id, id_slice)) {
            const node_len: u32 = @intCast(node.bytes.len);
            const len_slot = try host.allocScratch(mem, 4);
            const bytes_slot = try host.allocScratch(mem, node_len);
            std.mem.writeInt(u32, mem[len_slot..][0..4], node_len, .little);
            if (node_len > 0) {
                @memcpy(mem[bytes_slot .. bytes_slot + node_len], node.bytes);
            }
            out.* = .{ .i32 = @bitCast(bytes_slot) };
            return;
        }
    }
    out.* = .{ .i32 = 0 };
}

// ─────────────────────────────────────────────────────────────────────────
// 3d. dreamball.emit_action_envelope(payload_ptr, payload_len) -> envelope_ptr
// ─────────────────────────────────────────────────────────────────────────
//
// The envelope returned to the guest is the concatenation:
//   [u32 LE: payload_len][payload bytes][64 bytes Ed25519 signature]
//
// Per AC4 / SEC2:
//   i.   Host stages the payload bytes (copies them out of guest
//        linear memory into host-owned `EmittedEnvelope`).
//   ii.  Host invokes `sign_action.signEd25519(keypair, payload)` —
//        the same primitive `dreamball.wasm`'s `signActionEnvelope` export
//        wraps (D-023). One seam, called from both compile targets.
//   iii. On signing success, host promotes by appending to
//        `host.emitted` (the per-invocation staging → committed).
//   iv.  Host writes the canonical envelope bytes back into the guest
//        scratch region and returns the pointer.
//
// The guest cannot bypass signing: there is no path through the host
// that emits an envelope without calling `sign_action.signEd25519`.
//
// Error semantics: bad slice → trap; sign failure → trap (no partial
// promotion).
pub fn emit_action_envelope(
    instance: *runtime.Instance,
    args: []const runtime.Value,
    out: *?runtime.Value,
) runtime.Error!void {
    if (args.len != 2) return runtime.Error.GuestTrap;
    const host = try castHost(instance);
    const ptr: u32 = @bitCast(args[0].i32);
    const len: u32 = @bitCast(args[1].i32);
    const mem = instance.memory;
    if (@as(usize, ptr) + @as(usize, len) > mem.len) return runtime.Error.OutOfBounds;

    // Stage: copy payload out of guest memory into host ownership.
    const payload_owned = host.allocator.dupe(u8, mem[ptr .. ptr + len]) catch return runtime.Error.OutOfMemory;
    errdefer host.allocator.free(payload_owned);

    // Sign via the shared primitive. This is the SEC2 invariant: the
    // guest cannot reach this primitive directly — only through the
    // host, which always calls it before promoting.
    const sig = sign_action.signEd25519(host.keypair, payload_owned) catch return runtime.Error.GuestTrap;

    // Promote: append to emitted log.
    host.emitted.append(host.allocator, .{
        .payload = payload_owned,
        .signature = sig,
    }) catch return runtime.Error.OutOfMemory;
    host.emit_count += 1;

    // Materialise envelope bytes into scratch:
    //   [u32 LE payload_len][payload bytes][64 bytes signature]
    const total_len: u32 = 4 + len + 64;
    const len_slot = try host.allocScratch(mem, 4);
    const env_slot = try host.allocScratch(mem, total_len);
    if (@as(usize, env_slot) + total_len > mem.len) return runtime.Error.OutOfBounds;

    std.mem.writeInt(u32, mem[env_slot..][0..4], len, .little);
    @memcpy(mem[env_slot + 4 .. env_slot + 4 + len], payload_owned);
    @memcpy(mem[env_slot + 4 + len .. env_slot + total_len], &sig);
    std.mem.writeInt(u32, mem[len_slot..][0..4], total_len, .little);
    out.* = .{ .i32 = @bitCast(env_slot) };
}

// ─────────────────────────────────────────────────────────────────────────
// 3e. dreamball.now_ms() -> i64 (monotonic milliseconds)
// ─────────────────────────────────────────────────────────────────────────
//
// Type-marshalling: zero args; one i64 result.
//
// Monotonicity: clamped to never decrease across two consecutive calls
// against the same Host (AC5). std.time.milliTimestamp is monotonic on
// darwin/linux; the clamp is defensive.
pub fn now_ms(
    instance: *runtime.Instance,
    args: []const runtime.Value,
    out: *?runtime.Value,
) runtime.Error!void {
    if (args.len != 0) return runtime.Error.GuestTrap;
    const host = try castHost(instance);
    const raw: i64 = @intCast(@divFloor(std.Io.Clock.real.now(std.Io.Threaded.global_single_threaded.io()).nanoseconds, std.time.ns_per_ms));
    const since: i64 = raw - host.clock_zero_ms;
    const candidate: u64 = if (since < 0) 0 else @intCast(since);
    const clamped: u64 = if (candidate < host.last_now_ms) host.last_now_ms else candidate;
    host.last_now_ms = clamped;
    out.* = .{ .i64 = @intCast(clamped) };
}

/// Return all 5 import bindings as a fixed-size array. The runtime
/// applies the SEC1 whitelist from this set at instance-init time.
pub fn bindAll() [IMPORT_NAMES.len]runtime.ImportBinding {
    return .{
        .{ .module = "dreamball", .name = "fp", .impl = fp },
        .{ .module = "dreamball", .name = "encode_cbor", .impl = encode_cbor },
        .{ .module = "dreamball", .name = "read_node", .impl = read_node },
        .{ .module = "dreamball", .name = "emit_action_envelope", .impl = emit_action_envelope },
        .{ .module = "dreamball", .name = "now_ms", .impl = now_ms },
    };
}
