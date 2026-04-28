//! Production wasm runtime — promoted from `src/wasm-host/spike/runtime.zig`
//! (Story 5.1) per Story 5.2 step 1. The interpreter remains the same in-tree
//! Zig wasm runtime selected in
//! `docs/decisions/2026-04-28-wasm-runtime-selection.md` (D-020 / D-032).
//!
//! Story 5.2 grows the runtime in two ways relative to the spike:
//!
//!   1. **Host-function calling convention generalises.** The spike only
//!      brokered `wasi_snapshot_preview1.fd_write`. Production hosts the 5
//!      sprint-002-locked `dreamball.*` imports, each with its own
//!      arity/result shape (D-033). The interpreter doesn't care about
//!      function names — it just respects each callee's `FuncType`.
//!
//!   2. **Opcode coverage broadens to whatever the per-import test guests
//!      need.** The new opcodes (i32 load/store, local.get) are added
//!      defensively; each new opcode is one switch arm per the
//!      runtime-selection ADR's growth model.
//!
//! Surface unchanged from the spike (the ADR's "Instantiation API surface"
//! section is the contract):
//!
//!   - `parse(allocator, bytes)` — bytes → validated `Module`.
//!   - `Instance.init(allocator, &module, .{ .imports = &.{...} })` —
//!     module + import set → ready instance. Unknown imports are rejected
//!     here (this is the SEC1 whitelist seam; Story 5.3 owns the failure
//!     paths AC).
//!   - `instance.invokeStart()` — runs `_start`.
//!   - `instance.invokeExport(name, args, &out)` — call any exported
//!     function by name. Story 5.2 uses this for per-import test guests
//!     that expose a tested entrypoint other than `_start`.
//!
//! Per D-032 (single shared host): this source MUST stay compatible with
//! both `jelly` CLI compilation and (future, sprint-003) browser
//! compilation. We avoid `std.os` and other CLI-only paths here; clock
//! reads and stderr output happen one level up (in `imports.zig` /
//! `main.zig`) where the platform shim layer lives.

const std = @import("std");

pub const Error = error{
    BadMagic,
    BadVersion,
    UnexpectedEof,
    UnknownSectionId,
    InvalidLeb,
    InvalidValueType,
    UnsupportedOpcode,
    UnknownImport,
    ImportTypeMismatch,
    NoStartExport,
    NoSuchExport,
    StackUnderflow,
    OutOfBounds,
    GuestTrap,
    OutOfMemory,
};

pub const ValueType = enum(u8) {
    i32 = 0x7f,
    i64 = 0x7e,
    f32 = 0x7d,
    f64 = 0x7c,
};

pub const FuncType = struct {
    params: []const ValueType,
    results: []const ValueType,
};

pub const Import = struct {
    module: []const u8,
    name: []const u8,
    type_idx: u32,
};

pub const Export = struct {
    name: []const u8,
    kind: enum(u8) { function = 0, table = 1, memory = 2, global = 3 },
    index: u32,
};

pub const FunctionBody = struct {
    locals_count: u32,
    code: []const u8,
};

pub const DataSegment = struct {
    mem_idx: u32,
    offset: u32,
    bytes: []const u8,
};

pub const Module = struct {
    allocator: std.mem.Allocator,
    bytes_owned: []u8,
    types: []FuncType,
    imports: []Import,
    function_type_indices: []u32,
    memory_initial_pages: u32,
    exports: []Export,
    bodies: []FunctionBody,
    data: []DataSegment,

    pub fn deinit(self: *Module) void {
        const a = self.allocator;
        for (self.types) |t| {
            a.free(t.params);
            a.free(t.results);
        }
        a.free(self.types);
        a.free(self.imports);
        a.free(self.function_type_indices);
        a.free(self.exports);
        a.free(self.bodies);
        a.free(self.data);
        a.free(self.bytes_owned);
    }
};

const Reader = struct {
    bytes: []const u8,
    pos: usize = 0,

    fn remaining(self: Reader) usize {
        return self.bytes.len - self.pos;
    }

    fn need(self: *Reader, n: usize) Error!void {
        if (self.remaining() < n) return Error.UnexpectedEof;
    }

    fn readByte(self: *Reader) Error!u8 {
        try self.need(1);
        const b = self.bytes[self.pos];
        self.pos += 1;
        return b;
    }

    fn readBytes(self: *Reader, n: usize) Error![]const u8 {
        try self.need(n);
        const slice = self.bytes[self.pos .. self.pos + n];
        self.pos += n;
        return slice;
    }

    fn readU32Leb(self: *Reader) Error!u32 {
        var result: u32 = 0;
        var shift: u6 = 0; // u6 to hold up to 35 without overflow during iteration
        while (true) {
            const b = try self.readByte();
            const v: u32 = b & 0x7f;
            if (shift < 32) result |= std.math.shl(u32, v, @as(u5, @truncate(shift)));
            if ((b & 0x80) == 0) return result;
            shift += 7;
            // wasm u32 LEB128 is at most 5 bytes (35 bits); the 5th byte must
            // be the final byte (continuation bit must be clear). If we have
            // consumed 5 bytes and the continuation bit is still set the
            // encoding is malformed.
            if (shift >= 35) return Error.InvalidLeb;
        }
    }

    fn readI32Leb(self: *Reader) Error!i32 {
        var result: i32 = 0;
        var shift: u6 = 0; // u6 to avoid overflow when checking 5-byte LEB128
        var byte: u8 = 0;
        while (true) {
            byte = try self.readByte();
            const v: i32 = @as(i32, byte & 0x7f);
            if (shift < 32) result |= std.math.shl(i32, v, @as(u5, @truncate(shift)));
            shift += 7;
            if ((byte & 0x80) == 0) break;
            if (shift >= 35) return Error.InvalidLeb;
        }
        if (shift < 32 and (byte & 0x40) != 0) {
            const ones: i32 = @bitCast(@as(u32, 0xffff_ffff));
            result |= std.math.shl(i32, ones, @as(u5, @truncate(shift)));
        }
        return result;
    }

    fn readI64Leb(self: *Reader) Error!i64 {
        var result: i64 = 0;
        var shift: u7 = 0; // u7 to avoid overflow when checking 10-byte LEB128
        var byte: u8 = 0;
        while (true) {
            byte = try self.readByte();
            const v: i64 = @as(i64, byte & 0x7f);
            if (shift < 64) result |= std.math.shl(i64, v, @as(u6, @truncate(shift)));
            shift += 7;
            if ((byte & 0x80) == 0) break;
            if (shift >= 70) return Error.InvalidLeb;
        }
        if (shift < 64 and (byte & 0x40) != 0) {
            const ones: i64 = @bitCast(@as(u64, 0xffff_ffff_ffff_ffff));
            result |= std.math.shl(i64, ones, @as(u6, @truncate(shift)));
        }
        return result;
    }

    fn readName(self: *Reader) Error![]const u8 {
        const len = try self.readU32Leb();
        return try self.readBytes(len);
    }
};

fn parseValueType(b: u8) Error!ValueType {
    return switch (b) {
        0x7f => .i32,
        0x7e => .i64,
        0x7d => .f32,
        0x7c => .f64,
        else => Error.InvalidValueType,
    };
}

pub fn parse(allocator: std.mem.Allocator, bytes_in: []const u8) Error!Module {
    const owned = try allocator.dupe(u8, bytes_in);
    errdefer allocator.free(owned);

    var r = Reader{ .bytes = owned };

    const magic = try r.readBytes(4);
    if (!std.mem.eql(u8, magic, &.{ 0x00, 0x61, 0x73, 0x6d })) return Error.BadMagic;
    const version = try r.readBytes(4);
    if (!std.mem.eql(u8, version, &.{ 0x01, 0x00, 0x00, 0x00 })) return Error.BadVersion;

    var types: std.ArrayList(FuncType) = .empty;
    errdefer {
        for (types.items) |t| {
            allocator.free(t.params);
            allocator.free(t.results);
        }
        types.deinit(allocator);
    }
    var imports: std.ArrayList(Import) = .empty;
    errdefer imports.deinit(allocator);
    var func_type_indices: std.ArrayList(u32) = .empty;
    errdefer func_type_indices.deinit(allocator);
    var memory_initial_pages: u32 = 0;
    var exports: std.ArrayList(Export) = .empty;
    errdefer exports.deinit(allocator);
    var bodies: std.ArrayList(FunctionBody) = .empty;
    errdefer bodies.deinit(allocator);
    var data: std.ArrayList(DataSegment) = .empty;
    errdefer data.deinit(allocator);

    while (r.remaining() > 0) {
        const id = try r.readByte();
        const sec_len = try r.readU32Leb();
        const sec_start = r.pos;
        const sec_end = sec_start + sec_len;
        if (sec_end > r.bytes.len) return Error.UnexpectedEof;

        switch (id) {
            0 => {
                r.pos = sec_end;
            },
            1 => {
                const count = try r.readU32Leb();
                var i: u32 = 0;
                while (i < count) : (i += 1) {
                    const tag = try r.readByte();
                    if (tag != 0x60) return Error.InvalidValueType;
                    const param_count = try r.readU32Leb();
                    const params = try allocator.alloc(ValueType, param_count);
                    errdefer allocator.free(params);
                    for (params) |*p| p.* = try parseValueType(try r.readByte());
                    const result_count = try r.readU32Leb();
                    const results = try allocator.alloc(ValueType, result_count);
                    errdefer allocator.free(results);
                    for (results) |*p| p.* = try parseValueType(try r.readByte());
                    try types.append(allocator, .{ .params = params, .results = results });
                }
            },
            2 => {
                const count = try r.readU32Leb();
                var i: u32 = 0;
                while (i < count) : (i += 1) {
                    const mod_name = try r.readName();
                    const fn_name = try r.readName();
                    const desc = try r.readByte();
                    if (desc != 0x00) {
                        return Error.UnsupportedOpcode;
                    }
                    const type_idx = try r.readU32Leb();
                    try imports.append(allocator, .{
                        .module = mod_name,
                        .name = fn_name,
                        .type_idx = type_idx,
                    });
                }
            },
            3 => {
                const count = try r.readU32Leb();
                var i: u32 = 0;
                while (i < count) : (i += 1) {
                    try func_type_indices.append(allocator, try r.readU32Leb());
                }
            },
            5 => {
                const count = try r.readU32Leb();
                var i: u32 = 0;
                while (i < count) : (i += 1) {
                    const flag = try r.readByte();
                    const min = try r.readU32Leb();
                    if (flag & 0x01 != 0) _ = try r.readU32Leb();
                    if (i == 0) memory_initial_pages = min;
                }
            },
            7 => {
                const count = try r.readU32Leb();
                var i: u32 = 0;
                while (i < count) : (i += 1) {
                    const name = try r.readName();
                    const kind_byte = try r.readByte();
                    const idx = try r.readU32Leb();
                    if (kind_byte > 3) return Error.InvalidValueType;
                    try exports.append(allocator, .{
                        .name = name,
                        .kind = @enumFromInt(kind_byte),
                        .index = idx,
                    });
                }
            },
            10 => {
                const count = try r.readU32Leb();
                var i: u32 = 0;
                while (i < count) : (i += 1) {
                    const body_size = try r.readU32Leb();
                    const body_start = r.pos;
                    const body_end = body_start + body_size;
                    if (body_end > r.bytes.len) return Error.UnexpectedEof;

                    const groups = try r.readU32Leb();
                    var total_locals: u32 = 0;
                    var g: u32 = 0;
                    while (g < groups) : (g += 1) {
                        const n = try r.readU32Leb();
                        _ = try r.readByte();
                        total_locals += n;
                    }
                    const code = r.bytes[r.pos..body_end];
                    r.pos = body_end;
                    try bodies.append(allocator, .{
                        .locals_count = total_locals,
                        .code = code,
                    });
                }
            },
            11 => {
                const count = try r.readU32Leb();
                var i: u32 = 0;
                while (i < count) : (i += 1) {
                    const mode = try r.readU32Leb();
                    if (mode != 0) return Error.UnsupportedOpcode;
                    const op = try r.readByte();
                    if (op != 0x41) return Error.UnsupportedOpcode;
                    const offset_signed = try r.readI32Leb();
                    const end_op = try r.readByte();
                    if (end_op != 0x0b) return Error.UnsupportedOpcode;
                    const offset: u32 = @bitCast(offset_signed);
                    const data_len = try r.readU32Leb();
                    const data_bytes = try r.readBytes(data_len);
                    try data.append(allocator, .{
                        .mem_idx = 0,
                        .offset = offset,
                        .bytes = data_bytes,
                    });
                }
            },
            else => {
                r.pos = sec_end;
            },
        }

        if (r.pos != sec_end) {
            return Error.UnexpectedEof;
        }
    }

    return .{
        .allocator = allocator,
        .bytes_owned = owned,
        .types = try types.toOwnedSlice(allocator),
        .imports = try imports.toOwnedSlice(allocator),
        .function_type_indices = try func_type_indices.toOwnedSlice(allocator),
        .memory_initial_pages = memory_initial_pages,
        .exports = try exports.toOwnedSlice(allocator),
        .bodies = try bodies.toOwnedSlice(allocator),
        .data = try data.toOwnedSlice(allocator),
    };
}

// --- Instance + interpreter -------------------------------------------------

pub const Value = union(enum) {
    i32: i32,
    i64: i64,
};

/// Host functions get a context pointer through which they can stash any
/// host-side state needed across calls (per-invocation staging area for
/// `emit_action_envelope` lives here, for example). The runtime is
/// agnostic about what the context contains; `imports.zig` defines the
/// concrete `HostContext` shape.
pub const HostFn = *const fn (
    instance: *Instance,
    args: []const Value,
    out: *?Value,
) Error!void;

pub const ImportBinding = struct {
    module: []const u8,
    name: []const u8,
    impl: HostFn,
};

pub const InstanceConfig = struct {
    imports: []const ImportBinding,
    /// Opaque host context pointer. The host-functions cast it back to
    /// the concrete shape they expect (see `imports.zig`).
    host_context: ?*anyopaque = null,
};

pub const ImportRejection = struct {
    module: []const u8,
    name: []const u8,
};

pub const Instance = struct {
    allocator: std.mem.Allocator,
    module: *const Module,
    memory: []u8,
    bound_imports: []HostFn,
    host_context: ?*anyopaque,

    rejected_import: ?ImportRejection = null,

    pub fn init(
        allocator: std.mem.Allocator,
        module: *const Module,
        cfg: InstanceConfig,
    ) Error!Instance {
        const page_size: u32 = 65536;
        const mem_bytes = @as(usize, module.memory_initial_pages) * page_size;
        // Allow modules without explicit memory section (memory_initial_pages
        // = 0) to still allocate a small scratch page so host-side helpers
        // (e.g. dreamball.fp output slot) can write into linear memory.
        // Guest must declare its own memory if it wants to share buffers.
        const final_bytes = if (mem_bytes == 0) page_size else mem_bytes;
        const memory = try allocator.alloc(u8, final_bytes);
        @memset(memory, 0);
        errdefer allocator.free(memory);

        const bound = try allocator.alloc(HostFn, module.imports.len);
        errdefer allocator.free(bound);

        var instance: Instance = .{
            .allocator = allocator,
            .module = module,
            .memory = memory,
            .bound_imports = bound,
            .host_context = cfg.host_context,
            .rejected_import = null,
        };

        for (module.imports, 0..) |imp, i| {
            var found: ?HostFn = null;
            for (cfg.imports) |cand| {
                if (std.mem.eql(u8, cand.module, imp.module) and
                    std.mem.eql(u8, cand.name, imp.name))
                {
                    found = cand.impl;
                    break;
                }
            }
            if (found == null) {
                instance.rejected_import = .{ .module = imp.module, .name = imp.name };
                return Error.UnknownImport;
            }
            bound[i] = found.?;
        }

        for (module.data) |seg| {
            const end = @as(usize, seg.offset) + seg.bytes.len;
            if (end > memory.len) return Error.OutOfBounds;
            @memcpy(memory[seg.offset..end], seg.bytes);
        }

        return instance;
    }

    pub fn deinit(self: *Instance) void {
        self.allocator.free(self.memory);
        self.allocator.free(self.bound_imports);
    }

    pub fn findExport(self: *const Instance, name: []const u8) ?Export {
        for (self.module.exports) |e| {
            if (std.mem.eql(u8, e.name, name)) return e;
        }
        return null;
    }

    pub fn invokeStart(self: *Instance) Error!void {
        const exp = self.findExport("_start") orelse return Error.NoStartExport;
        if (exp.kind != .function) return Error.NoStartExport;
        try self.invokeFunction(exp.index, &.{}, null);
    }

    /// Call any exported function by name. Used by Story 5.2's per-import
    /// test guests, which expose typed entrypoints (e.g. `test_fp`)
    /// instead of `_start`.
    pub fn invokeExport(
        self: *Instance,
        name: []const u8,
        args: []const Value,
        out_result: ?*?Value,
    ) Error!void {
        const exp = self.findExport(name) orelse return Error.NoSuchExport;
        if (exp.kind != .function) return Error.NoSuchExport;
        try self.invokeFunction(exp.index, args, out_result);
    }

    fn invokeFunction(
        self: *Instance,
        func_idx: u32,
        args: []const Value,
        out_result: ?*?Value,
    ) Error!void {
        const import_count = self.module.imports.len;
        if (func_idx < import_count) {
            var host_result: ?Value = null;
            try self.bound_imports[func_idx](self, args, &host_result);
            if (out_result) |o| o.* = host_result;
            return;
        }
        const local_idx = func_idx - import_count;
        if (local_idx >= self.module.bodies.len) return Error.OutOfBounds;
        const body = self.module.bodies[local_idx];

        const type_idx = self.module.function_type_indices[local_idx];
        const ty = self.module.types[type_idx];

        var locals_buf: std.ArrayList(Value) = .empty;
        defer locals_buf.deinit(self.allocator);
        try locals_buf.ensureTotalCapacity(self.allocator, ty.params.len + body.locals_count);
        for (args) |a| locals_buf.appendAssumeCapacity(a);
        var i: u32 = 0;
        while (i < body.locals_count) : (i += 1) locals_buf.appendAssumeCapacity(.{ .i32 = 0 });

        try self.runBody(body.code, locals_buf.items, out_result);
    }

    fn runBody(
        self: *Instance,
        code: []const u8,
        locals: []Value,
        out_result: ?*?Value,
    ) Error!void {
        var stack: std.ArrayList(Value) = .empty;
        defer stack.deinit(self.allocator);

        var r = Reader{ .bytes = code };
        while (r.remaining() > 0) {
            const op = try r.readByte();
            switch (op) {
                0x0b => {
                    if (out_result) |o| {
                        o.* = if (stack.items.len > 0) stack.items[stack.items.len - 1] else null;
                    }
                    return;
                },
                0x10 => {
                    // call funcidx
                    const fi = try r.readU32Leb();
                    const callee_imports = self.module.imports.len;
                    const callee_type_idx = if (fi < callee_imports)
                        self.module.imports[fi].type_idx
                    else
                        self.module.function_type_indices[fi - callee_imports];
                    const callee_ty = self.module.types[callee_type_idx];

                    if (stack.items.len < callee_ty.params.len) return Error.StackUnderflow;
                    const args_start = stack.items.len - callee_ty.params.len;
                    const args = stack.items[args_start..];
                    var sub_result: ?Value = null;
                    try self.invokeFunction(fi, args, &sub_result);
                    stack.shrinkRetainingCapacity(args_start);
                    if (callee_ty.results.len > 0) {
                        if (sub_result == null) return Error.GuestTrap;
                        try stack.append(self.allocator, sub_result.?);
                    }
                },
                0x1a => {
                    if (stack.items.len == 0) return Error.StackUnderflow;
                    _ = stack.pop();
                },
                0x20 => {
                    // local.get idx
                    const idx = try r.readU32Leb();
                    if (idx >= locals.len) return Error.OutOfBounds;
                    try stack.append(self.allocator, locals[idx]);
                },
                0x21 => {
                    // local.set idx
                    const idx = try r.readU32Leb();
                    if (idx >= locals.len) return Error.OutOfBounds;
                    if (stack.items.len == 0) return Error.StackUnderflow;
                    locals[idx] = stack.pop().?;
                },
                0x28 => {
                    // i32.load (memarg: align u32, offset u32)
                    _ = try r.readU32Leb();
                    const offset = try r.readU32Leb();
                    if (stack.items.len == 0) return Error.StackUnderflow;
                    const addr_val = stack.pop().?;
                    const base: u32 = @bitCast(addr_val.i32);
                    const ea = base + offset;
                    if (ea + 4 > self.memory.len) return Error.OutOfBounds;
                    const v = std.mem.readInt(u32, self.memory[ea..][0..4], .little);
                    try stack.append(self.allocator, .{ .i32 = @bitCast(v) });
                },
                0x36 => {
                    // i32.store (memarg) value, addr
                    _ = try r.readU32Leb();
                    const offset = try r.readU32Leb();
                    if (stack.items.len < 2) return Error.StackUnderflow;
                    const v = stack.pop().?;
                    const addr_val = stack.pop().?;
                    const base: u32 = @bitCast(addr_val.i32);
                    const ea = base + offset;
                    if (ea + 4 > self.memory.len) return Error.OutOfBounds;
                    const u: u32 = @bitCast(v.i32);
                    std.mem.writeInt(u32, self.memory[ea..][0..4], u, .little);
                },
                0x41 => {
                    // i32.const
                    const v = try r.readI32Leb();
                    try stack.append(self.allocator, .{ .i32 = v });
                },
                0x42 => {
                    // i64.const
                    const v = try r.readI64Leb();
                    try stack.append(self.allocator, .{ .i64 = v });
                },
                0x6a => {
                    // i32.add
                    if (stack.items.len < 2) return Error.StackUnderflow;
                    const b = stack.pop().?;
                    const a = stack.pop().?;
                    try stack.append(self.allocator, .{ .i32 = a.i32 +% b.i32 });
                },
                else => return Error.UnsupportedOpcode,
            }
        }
        return Error.UnexpectedEof;
    }
};
