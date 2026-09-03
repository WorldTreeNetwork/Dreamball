//! gen_capabilities — per-archiform generator for the `x-capabilities` block.
//!
//! Projects an archiform schema's `x-capabilities` requirement block into a
//! typed TypeScript requirements manifest the capability resolver consumes
//! (`src/lib/generated/palace-capabilities.ts`). Sibling to gen_cli /
//! gen_ts_client / gen_mcp_tools; dispatched from `runArchiformPass`.
//!
//! Spec: docs/decisions/2026-05-31-capabilities-schema-vocabulary.md.
//! Why:  docs/decisions/2026-05-31-capability-provider-model.md.
//!
//! Validation (codegen-time gate, D-035 discipline) mirrors the dev-time
//! validator at `scripts/capabilities-validate.ts` + its 14-case test:
//!   - top-level keys ⊆ { requires, optional }
//!   - per-entry closed field set; `degradesTo` only on `optional`
//!   - `interface` is `<scope>/<name>` with scope ∈ { service, render }
//!   - `version` is a caret/tilde/exact range or `*` (warn if absent)
//!   - `select` ∈ the closed policy set; `source` is registry/git/local
//!   - `optional` entries MUST carry a non-empty `degradesTo`
//! Any violation is a hard codegen failure (returns error → `zig build
//! schemagen` exits non-zero).
//!
//! Absent `x-capabilities` → no-op (logs `skip`, writes nothing). This keeps
//! wiring the generator in additive: it activates only once a schema declares
//! the block. `x-capabilities` is schema metadata only — never on the CBOR
//! wire — so projecting it touches no golden vector.

const std = @import("std");
const main_mod = @import("main.zig");
const cc = @import("codegen_common");

const OUT_PATH = "src/lib/generated/palace-capabilities.ts";

const Presence = enum { required, optional };

const SELECT_POLICIES = [_][]const u8{
    "auto",
    "prefer-low-latency",
    "prefer-low-power",
    "prefer-quality",
    "prefer-local",
};

pub fn generateArchiform(actx: *const cc.ArchiformCtx) !void {
    const arena = actx.arena;

    const root = switch (actx.schema_value) {
        .object => |o| o,
        else => return error.SchemaNotObject,
    };

    // No-op when the archiform declares no capability needs.
    const xcaps_val = root.get("x-capabilities") orelse {
        try main_mod.logKVPub(actx.stderr, .{
            .{ "phase", "capabilities-projection" },
            .{ "status", "skip" },
            .{ "detail", "no x-capabilities block" },
            .{ "schema", actx.schema_path },
        });
        return;
    };
    const xcaps = switch (xcaps_val) {
        .object => |o| o,
        else => {
            try fail(actx, "<root>", "x-capabilities", "not-an-object");
            return error.InvalidCapabilities;
        },
    };

    // Top-level closed set: only `requires` / `optional`.
    var tit = xcaps.iterator();
    while (tit.next()) |e| {
        const k = e.key_ptr.*;
        if (!std.mem.eql(u8, k, "requires") and !std.mem.eql(u8, k, "optional")) {
            try fail(actx, "<top-level>", k, "unknown-top-level-key (allowed: requires, optional)");
            return error.InvalidCapabilities;
        }
    }

    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(arena);
    try body.appendSlice(arena, PRELUDE);
    try body.appendSlice(arena, "export const PALACE_CAPABILITIES: readonly CapabilityRequirement[] = [\n");

    var count: usize = 0;
    if (getObject(xcaps, "requires")) |req| try emitGroup(actx, &body, req, .required, &count);
    if (getObject(xcaps, "optional")) |opt| try emitGroup(actx, &body, opt, .optional, &count);

    try body.appendSlice(arena, "] as const;\n");

    const header = try buildHeader(arena, actx);

    var file = try std.Io.Dir.cwd().createFile(actx.io, OUT_PATH, .{ .truncate = true });
    defer file.close(actx.io);
    var fbuf: [4096]u8 = undefined;
    var fw = file.writer(actx.io, &fbuf);
    try fw.interface.writeAll(header);
    try fw.interface.writeAll(body.items);
    try fw.interface.flush();

    try main_mod.logKVPub(actx.stderr, .{
        .{ "phase", "output-written" },
        .{ "path", OUT_PATH },
        .{ "bytes", header.len + body.items.len },
        .{ "requirements", count },
        .{ "pass", "capabilities-projection" },
    });
}

fn emitGroup(
    actx: *const cc.ArchiformCtx,
    body: *std.ArrayList(u8),
    map: std.json.ObjectMap,
    presence: Presence,
    count: *usize,
) !void {
    var it = map.iterator();
    while (it.next()) |e| {
        const alias = e.key_ptr.*;
        const entry = switch (e.value_ptr.*) {
            .object => |o| o,
            else => {
                try fail(actx, alias, "<entry>", "requirement entry is not an object");
                return error.InvalidCapabilities;
            },
        };
        try validateAndEmitEntry(actx, body, alias, entry, presence);
        count.* += 1;
    }
}

fn validateAndEmitEntry(
    actx: *const cc.ArchiformCtx,
    body: *std.ArrayList(u8),
    alias: []const u8,
    entry: std.json.ObjectMap,
    presence: Presence,
) !void {
    const arena = actx.arena;

    // Closed field set.
    var fit = entry.iterator();
    while (fit.next()) |fe| {
        const k = fe.key_ptr.*;
        const allowed =
            std.mem.eql(u8, k, "interface") or
            std.mem.eql(u8, k, "version") or
            std.mem.eql(u8, k, "params") or
            std.mem.eql(u8, k, "select") or
            std.mem.eql(u8, k, "source") or
            (presence == .optional and std.mem.eql(u8, k, "degradesTo"));
        if (!allowed) {
            const why = if (std.mem.eql(u8, k, "degradesTo"))
                "degradesTo is only valid on `optional` entries"
            else
                "unknown field";
            try fail(actx, alias, k, why);
            return error.InvalidCapabilities;
        }
    }

    // interface — required, `<scope>/<name>`.
    const iface = getString(entry, "interface") orelse {
        try fail(actx, alias, "interface", "required (and must be a string)");
        return error.InvalidCapabilities;
    };
    if (!validInterface(iface)) {
        try fail(actx, alias, "interface", iface);
        return error.InvalidCapabilities;
    }

    // version — optional range; warn if absent, error if malformed.
    var version: []const u8 = "*";
    if (entry.get("version")) |vv| {
        const vs = switch (vv) {
            .string => |s| s,
            else => {
                try fail(actx, alias, "version", "not-a-string");
                return error.InvalidCapabilities;
            },
        };
        if (!validVersion(vs)) {
            try fail(actx, alias, "version", vs);
            return error.InvalidCapabilities;
        }
        version = vs;
    } else {
        try main_mod.logKVPub(actx.stderr, .{
            .{ "phase", "capabilities-projection" },
            .{ "status", "warn" },
            .{ "alias", alias },
            .{ "detail", "no version range; defaulting to *" },
        });
    }

    // select — optional, closed policy set.
    var select_opt: ?[]const u8 = null;
    if (entry.get("select")) |sv| {
        const ss = switch (sv) {
            .string => |s| s,
            else => {
                try fail(actx, alias, "select", "not-a-string");
                return error.InvalidCapabilities;
            },
        };
        if (!validSelect(ss)) {
            try fail(actx, alias, "select", ss);
            return error.InvalidCapabilities;
        }
        select_opt = ss;
    }

    // source — optional, registry/git/local form.
    var source_opt: ?[]const u8 = null;
    if (entry.get("source")) |sv| {
        const ss = switch (sv) {
            .string => |s| s,
            else => {
                try fail(actx, alias, "source", "not-a-string");
                return error.InvalidCapabilities;
            },
        };
        if (!validSource(ss)) {
            try fail(actx, alias, "source", ss);
            return error.InvalidCapabilities;
        }
        source_opt = ss;
    }

    // params — optional object.
    var params_opt: ?std.json.Value = null;
    if (entry.get("params")) |pv| {
        switch (pv) {
            .object => {},
            else => {
                try fail(actx, alias, "params", "not-an-object");
                return error.InvalidCapabilities;
            },
        }
        params_opt = pv;
    }

    // degradesTo — required + non-empty on optional (forbidden on required is
    // already caught by the closed-field check above).
    var degrades_opt: ?[]const u8 = null;
    if (presence == .optional) {
        const dv = entry.get("degradesTo") orelse {
            try fail(actx, alias, "degradesTo", "required on `optional` entries");
            return error.InvalidCapabilities;
        };
        const ds = switch (dv) {
            .string => |s| s,
            else => {
                try fail(actx, alias, "degradesTo", "not-a-string");
                return error.InvalidCapabilities;
            },
        };
        if (ds.len == 0) {
            try fail(actx, alias, "degradesTo", "must be a non-empty string");
            return error.InvalidCapabilities;
        }
        degrades_opt = ds;
    }

    const slash = std.mem.indexOfScalar(u8, iface, '/').?;
    const scope = iface[0..slash];

    // Emit the typed requirement literal.
    try body.appendSlice(arena, "  { alias: ");
    try appendJsonString(arena, body, alias);
    try body.appendSlice(arena, ", interface: ");
    try appendJsonString(arena, body, iface);
    try body.appendSlice(arena, ", version: ");
    try appendJsonString(arena, body, version);
    try body.appendSlice(arena, ", scope: ");
    try appendJsonString(arena, body, scope);
    try body.appendSlice(arena, ", presence: ");
    try appendJsonString(arena, body, if (presence == .required) "required" else "optional");
    if (select_opt) |s| {
        try body.appendSlice(arena, ", select: ");
        try appendJsonString(arena, body, s);
    }
    if (params_opt) |p| {
        try body.appendSlice(arena, ", params: ");
        try appendJsonValue(arena, body, p);
    }
    if (source_opt) |s| {
        try body.appendSlice(arena, ", source: ");
        try appendJsonString(arena, body, s);
    }
    if (degrades_opt) |d| {
        try body.appendSlice(arena, ", degradesTo: ");
        try appendJsonString(arena, body, d);
    }
    try body.appendSlice(arena, " },\n");
}

// ── validation helpers (mirror scripts/capabilities-validate.ts) ──────────────

fn validInterface(s: []const u8) bool {
    const slash = std.mem.indexOfScalar(u8, s, '/') orelse return false;
    const scope = s[0..slash];
    const name = s[slash + 1 ..];
    if (!std.mem.eql(u8, scope, "service") and !std.mem.eql(u8, scope, "render")) return false;
    if (name.len == 0) return false;
    if (std.mem.indexOfScalar(u8, name, '/') != null) return false; // exactly one slash
    if (!(name[0] >= 'a' and name[0] <= 'z')) return false;
    for (name) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-';
        if (!ok) return false;
    }
    return true;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn validVersion(s: []const u8) bool {
    if (std.mem.eql(u8, s, "*")) return true;
    if (s.len == 0) return false;
    var i: usize = 0;
    if (s[0] == '^' or s[0] == '~' or s[0] == '=') i = 1;
    if (i >= s.len or !isDigit(s[i])) return false;
    var groups: usize = 1;
    while (i < s.len and isDigit(s[i])) i += 1;
    while (i < s.len) {
        if (s[i] != '.') return false;
        i += 1;
        if (i >= s.len or !isDigit(s[i])) return false;
        while (i < s.len and isDigit(s[i])) i += 1;
        groups += 1;
        if (groups > 3) return false;
    }
    return true;
}

fn validSelect(s: []const u8) bool {
    for (SELECT_POLICIES) |p| if (std.mem.eql(u8, s, p)) return true;
    return false;
}

fn validSource(s: []const u8) bool {
    if (std.mem.startsWith(u8, s, "aspects:")) return validInterface(s["aspects:".len..]);
    if (std.mem.startsWith(u8, s, "github:")) {
        const rest = s["github:".len..];
        return std.mem.indexOfScalar(u8, rest, '/') != null and rest.len > 2;
    }
    if (std.mem.startsWith(u8, s, "file:")) return s.len > "file:".len;
    return false;
}

// ── JSON value serializer (for `params`) ──────────────────────────────────────

fn appendJsonString(arena: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    try buf.append(arena, '"');
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(arena, "\\\""),
            '\\' => try buf.appendSlice(arena, "\\\\"),
            '\n' => try buf.appendSlice(arena, "\\n"),
            '\r' => try buf.appendSlice(arena, "\\r"),
            '\t' => try buf.appendSlice(arena, "\\t"),
            else => {
                if (c < 0x20) {
                    var b: [8]u8 = undefined;
                    const sl = try std.fmt.bufPrint(&b, "\\u{x:0>4}", .{c});
                    try buf.appendSlice(arena, sl);
                } else {
                    try buf.append(arena, c);
                }
            },
        }
    }
    try buf.append(arena, '"');
}

fn appendJsonValue(arena: std.mem.Allocator, buf: *std.ArrayList(u8), v: std.json.Value) !void {
    switch (v) {
        .null => try buf.appendSlice(arena, "null"),
        .bool => |b| try buf.appendSlice(arena, if (b) "true" else "false"),
        .integer => |i| {
            var b: [32]u8 = undefined;
            try buf.appendSlice(arena, try std.fmt.bufPrint(&b, "{d}", .{i}));
        },
        .float => |f| {
            var b: [32]u8 = undefined;
            try buf.appendSlice(arena, try std.fmt.bufPrint(&b, "{d}", .{f}));
        },
        .number_string => |ns| try buf.appendSlice(arena, ns),
        .string => |s| try appendJsonString(arena, buf, s),
        .array => |a| {
            try buf.append(arena, '[');
            for (a.items, 0..) |item, idx| {
                if (idx > 0) try buf.append(arena, ',');
                try appendJsonValue(arena, buf, item);
            }
            try buf.append(arena, ']');
        },
        .object => |o| {
            try buf.append(arena, '{');
            var it = o.iterator();
            var first = true;
            while (it.next()) |e| {
                if (!first) try buf.append(arena, ',');
                first = false;
                try appendJsonString(arena, buf, e.key_ptr.*);
                try buf.append(arena, ':');
                try appendJsonValue(arena, buf, e.value_ptr.*);
            }
            try buf.append(arena, '}');
        },
    }
}

// ── small shared helpers ──────────────────────────────────────────────────────

fn getString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

fn getObject(obj: std.json.ObjectMap, key: []const u8) ?std.json.ObjectMap {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .object => |o| o,
        else => null,
    };
}

fn fail(actx: *const cc.ArchiformCtx, alias: []const u8, field: []const u8, detail: []const u8) !void {
    try main_mod.logKVPub(actx.stderr, .{
        .{ "phase", "capabilities-projection" },
        .{ "status", "error" },
        .{ "alias", alias },
        .{ "field", field },
        .{ "detail", detail },
        .{ "schema", actx.schema_path },
    });
}

fn buildHeader(allocator: std.mem.Allocator, actx: *const cc.ArchiformCtx) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        \\// DO NOT EDIT — generated by tools/schema-gen/gen_capabilities.zig.
        \\// Provenance:
        \\//   source-schema:     {0s}
        \\//   source-schema-fp:  blake3:{1s}
        \\//   schema-pin:        {2s}
        \\//   schema-version:    {3s}
        \\//   generator-id:      {4s}
        \\//   generator-commit:  {5s}
        \\// Regenerate via `bun run codegen`. Hand-edits will be overwritten.
        \\// Spec: docs/decisions/2026-05-31-capabilities-schema-vocabulary.md.
        \\
        \\
    ,
        .{
            actx.schema_path,
            actx.schema_fp,
            actx.pin_path,
            actx.schema_version,
            actx.generator_id,
            actx.generator_commit,
        },
    );
}

const PRELUDE =
    \\// palace-capabilities.ts — generated TypeScript projection of the archiform's
    \\// `x-capabilities` block (capability requirements; the symmetric twin of the
    \\// `x-actions` manifest). Consumed by the capability resolver. Validated at
    \\// codegen time against the closed-field set + interface/version/select/source
    \\// rules (gen_capabilities.zig), mirroring scripts/capabilities-validate.ts.
    \\
    \\export type CapabilityScope = 'service' | 'render';
    \\export type CapabilityPresence = 'required' | 'optional';
    \\
    \\export interface CapabilityRequirement {
    \\  /** local alias (the x-capabilities map key) */
    \\  readonly alias: string;
    \\  /** `<scope>/<name>` interface identifier */
    \\  readonly interface: string;
    \\  /** semver range (caret default); "*" if unspecified */
    \\  readonly version: string;
    \\  /** derived from the interface namespace prefix */
    \\  readonly scope: CapabilityScope;
    \\  readonly presence: CapabilityPresence;
    \\  readonly select?: string;
    \\  readonly params?: Record<string, unknown>;
    \\  readonly source?: string;
    \\  /** fallback behavior when an optional capability is unbound */
    \\  readonly degradesTo?: string;
    \\}
    \\
    \\
;
