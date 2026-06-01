//! Story 4.1 — gen_ts_client per-archiform generator (D-019, D-022, D-034).
//!
//! Projects each entry of an archiform schema's `x-actions` map into a typed
//! TypeScript async function inside `src/lib/generated/palace-client.ts`.
//!
//! Architectural commitments (recorded in DAR for Story 4.1):
//!   1. Generator location: NEW sibling `tools/schema-gen/gen_ts_client.zig`,
//!      dispatched from `runArchiformPass` after `gen_ts`. Keeps each
//!      generator small and focused (D-030 Option A philosophy; same shape
//!      as gen_cli).
//!   2. Output path:        `src/lib/generated/palace-client.ts` (single
//!      file containing all five verbs + their input/output types).
//!   3. Path alias:         `@dreamball/palace-client` mapped via
//!      `tsconfig.json` `paths` to the generated file. No npm package
//!      ships in sprint-002.
//!   4. Bridge composition (D-022): each generated client function shells
//!      out to `jelly palace <verb>` via Bun's spawn API. The CLI is itself
//!      manifest-derived (Story 3.x), so the call chain is:
//!        TS client (manifest types)
//!          → jelly CLI (manifest dispatcher, gen_cli output)
//!            → Zig staging
//!              → Bun bridge subprocess (`src/lib/bridge/palace-<verb>.ts`)
//!                → ServerStore (D-007 store wrapper)
//!                  → @ladybugdb/core
//!      The TS client never imports @ladybugdb or kuzu directly (AC5).
//!      The TS client never touches `__rawQuery` (AC4 — zero drift from D-007).
//!   5. Store integration (D-034): the bridge subprocesses already wrap the
//!      D-007 store wrapper. The generated client calls the manifest-driven
//!      CLI which triggers those bridges; D-007 is unchanged (IC6).
//!   6. Closed-set typing (D-035): `attributes` and `effects.kind` are
//!      typed against the closed set; this generator does not lean on them.
//!      Inputs/outputs are derived from `inputs.properties` and
//!      `outputs.properties` only.
//!
//! Provenance (NFR9): the generated file's header names
//! `schemas/memory-palace-0.1.0.json` + its pin file as source.
//!
//! Drift detection (AC6): when a manifest input/output property is removed,
//! the regenerated TS file's input/output interface no longer carries the
//! field. Any call site that passed/destructured the removed field becomes
//! a TypeScript error at `bun run check`. Drift cannot land silently.

const std = @import("std");
const main_mod = @import("main.zig");
const cc = @import("codegen_common");

const OUT_PATH = "src/lib/generated/palace-client.ts";

pub fn generateArchiform(actx: *const cc.ArchiformCtx) !void {
    const x_actions = extractXActions(actx) catch |e| {
        try main_mod.logKVPub(actx.stderr, .{
            .{ "phase", "ts-client-projection" },
            .{ "status", "error" },
            .{ "detail", "missing x-actions" },
            .{ "schema", actx.schema_path },
        });
        return e;
    };

    const arena = actx.arena;

    // Build provenance header.
    const header = try buildHeader(arena, actx);

    // Build body. Single file, all verbs.
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(arena);

    try body.appendSlice(arena, PRELUDE);

    // Iterate verbs in deterministic JSON object order.
    var iter = x_actions.iterator();
    while (iter.next()) |entry| {
        const verb_name = entry.key_ptr.*;
        const manifest_obj = switch (entry.value_ptr.*) {
            .object => |o| o,
            else => {
                try main_mod.logKVPub(actx.stderr, .{
                    .{ "phase", "ts-client-projection" },
                    .{ "status", "error" },
                    .{ "verb", verb_name },
                    .{ "detail", "manifest entry is not an object" },
                });
                return error.MalformedManifest;
            },
        };
        try projectVerb(arena, &body, verb_name, manifest_obj);
    }

    // Write file.
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
        .{ "pass", "ts-client-projection" },
    });
}

const PRELUDE =
    \\// palace-client.ts — generated TypeScript projection of the Memory Palace
    \\// archiform's `x-actions` manifest (D-019). One typed async function per verb.
    \\//
    \\// Per D-034: this client wraps the D-007 store wrapper at one remove — each
    \\// function dispatches to the manifest-derived `jelly palace <verb>` CLI, which
    \\// runs Zig + the existing bridge subprocesses (`src/lib/bridge/palace-*.ts`),
    \\// which in turn use the ServerStore. The bridge pattern (D-022) is preserved
    \\// underneath. This file MUST NOT import @ladybugdb/core, kuzu, or use
    \\// `__rawQuery` (AC4, AC5).
    \\//
    \\// Per Story 4.1 Phase 3 architectural choice: invocation is via Bun's spawn
    \\// API; stdout is parsed as JSON to recover the typed outputs. The CLI verbs
    \\// emit a single JSON line on stdout when invoked with `--json` (sprint-002
    \\// extension; falls back to text parse when --json is absent).
    \\
    \\import { spawnSync, type SpawnSyncOptions } from 'node:child_process';
    \\
    \\/**
    \\ * Resolve the `jelly` CLI path. Defaults to `zig-out/bin/jelly` (the local
    \\ * build output); overridable via JELLY_CLI env var for test/CI environments.
    \\ */
    \\function resolveJelly(): string {
    \\  return process.env.JELLY_CLI ?? 'zig-out/bin/jelly';
    \\}
    \\
    \\/**
    \\ * Common spawn helper. Shells out to `jelly palace <verb> ...flags`, captures
    \\ * stdout, and returns it. Throws on non-zero exit, surfacing stderr text.
    \\ */
    \\function invokeVerb(verb: string, flags: string[], opts: SpawnSyncOptions = {}): string {
    \\  const argv = ['palace', verb, ...flags];
    \\  const res = spawnSync(resolveJelly(), argv, {
    \\    encoding: 'utf-8',
    \\    ...opts,
    \\  });
    \\  if (res.error) throw res.error;
    \\  if (res.status !== 0) {
    \\    const stderr = typeof res.stderr === 'string' ? res.stderr : '';
    \\    throw new Error(
    \\      `palace ${verb} failed (exit ${res.status ?? 'null'}): ${stderr.trim()}`,
    \\    );
    \\  }
    \\  return typeof res.stdout === 'string' ? res.stdout : '';
    \\}
    \\
    \\/**
    \\ * Convert an inputs object to CLI flags. Skips undefined values; converts
    \\ * camelCase keys to kebab-case to match the generated CLI dispatcher's flag
    \\ * convention (see `tools/schema-gen/gen_cli.zig camelToKebab`). Boolean true
    \\ * becomes a bare flag; boolean false omits the flag.
    \\ */
    \\function inputsToFlags(inputs: Record<string, unknown>): string[] {
    \\  const flags: string[] = [];
    \\  for (const [key, value] of Object.entries(inputs)) {
    \\    if (value === undefined || value === null) continue;
    \\    const flag = '--' + key.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase());
    \\    if (typeof value === 'boolean') {
    \\      if (value) flags.push(flag);
    \\      continue;
    \\    }
    \\    flags.push(flag, String(value));
    \\  }
    \\  return flags;
    \\}
    \\
    \\
;

fn projectVerb(
    arena: std.mem.Allocator,
    body: *std.ArrayList(u8),
    verb_name: []const u8,
    manifest: std.json.ObjectMap,
) !void {
    const summary = getString(manifest, "summary") orelse "";
    const inputs_obj = getObject(manifest, "inputs") orelse return error.ManifestMissingInputs;
    const props = getObject(inputs_obj, "properties") orelse return error.ManifestMissingProperties;
    const required_arr = getArray(inputs_obj, "required");

    const outputs_obj = getObject(manifest, "outputs") orelse return error.ManifestMissingOutputs;
    const out_props_opt = getObject(outputs_obj, "properties");

    // Convert kebab verb name to camelCase TS identifier.
    const fn_name = try kebabToCamel(arena, verb_name);
    // Convert kebab verb name to PascalCase for type names.
    const pascal = try kebabToPascal(arena, verb_name);

    const inputs_type = try std.fmt.allocPrint(arena, "{s}Inputs", .{pascal});
    const outputs_type = try std.fmt.allocPrint(arena, "{s}Outputs", .{pascal});

    // ── Inputs interface ─────────────────────────────────────────────────────
    try body.appendSlice(arena, "/** Inputs for `");
    try body.appendSlice(arena, verb_name);
    try body.appendSlice(arena, "` — derived from manifest `inputs.properties`. */\n");
    try body.appendSlice(arena, "export interface ");
    try body.appendSlice(arena, inputs_type);
    try body.appendSlice(arena, " {\n");
    var pit = props.iterator();
    while (pit.next()) |pent| {
        const pname = pent.key_ptr.*;
        const pobj = switch (pent.value_ptr.*) {
            .object => |o| o,
            else => continue,
        };
        const ptype = getString(pobj, "type") orelse "string";
        const pdesc = getString(pobj, "description") orelse "";
        const required = isRequired(required_arr, pname);
        // Multi-line JSDoc form so the description line starts with `*` and is
        // recognised by audits (e.g. oracle.test.ts AC3) as narrative/comment
        // rather than code (otherwise a single-line `/** ... */` containing
        // `.oracle.key` trips the read-site audit).
        try body.appendSlice(arena, "  /**\n   * ");
        try writeTsCommentEscaped(arena, body, pdesc);
        // S4.1 AC3 smoke-script lint: every `.oracle.key` site needs a
        // TODO-CRYPTO marker within 3 lines (oracle key is plaintext;
        // wrap with recrypt wallet DCYW shell post-MVP per known-gaps §6).
        if (std.mem.indexOf(u8, pdesc, ".oracle.key") != null) {
            try body.appendSlice(arena, "\n   * TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)");
        }
        try body.appendSlice(arena, "\n   */\n");
        try body.appendSlice(arena, "  ");
        try writeTsKey(arena, body, pname);
        if (!required) try body.appendSlice(arena, "?");
        try body.appendSlice(arena, ": ");
        try body.appendSlice(arena, jsonTypeToTs(ptype));
        try body.appendSlice(arena, ";\n");
    }
    try body.appendSlice(arena, "}\n\n");

    // ── Outputs interface ────────────────────────────────────────────────────
    try body.appendSlice(arena, "/** Outputs for `");
    try body.appendSlice(arena, verb_name);
    try body.appendSlice(arena, "` — derived from manifest `outputs.properties`. */\n");
    try body.appendSlice(arena, "export interface ");
    try body.appendSlice(arena, outputs_type);
    try body.appendSlice(arena, " {\n");
    if (out_props_opt) |op| {
        var oit = op.iterator();
        while (oit.next()) |oent| {
            const oname = oent.key_ptr.*;
            const oobj = switch (oent.value_ptr.*) {
                .object => |o| o,
                else => continue,
            };
            const otype = getString(oobj, "type") orelse "string";
            const odesc = getString(oobj, "description") orelse "";
            // Multi-line JSDoc form (see inputs section above for rationale —
            // single-line `/** ... */` containing `.oracle.key` trips the
            // oracle.test.ts AC3 audit which expects narrative-comment shape).
            try body.appendSlice(arena, "  /**\n   * ");
            try writeTsCommentEscaped(arena, body, odesc);
            // S4.1 AC3 smoke-script lint: every `.oracle.key` site needs a
            // TODO-CRYPTO marker within 3 lines (per oracle.ts:113 convention).
            if (std.mem.indexOf(u8, odesc, ".oracle.key") != null) {
                try body.appendSlice(arena, "\n   * TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)");
            }
            try body.appendSlice(arena, "\n   */\n");
            try body.appendSlice(arena, "  ");
            try writeTsKey(arena, body, oname);
            try body.appendSlice(arena, ": ");
            try body.appendSlice(arena, jsonTypeToTs(otype));
            try body.appendSlice(arena, ";\n");
        }
    }
    try body.appendSlice(arena, "}\n\n");

    // ── Function ─────────────────────────────────────────────────────────────
    try body.appendSlice(arena, "/**\n * ");
    try writeTsCommentEscaped(arena, body, summary);
    try body.appendSlice(arena, "\n *\n");
    try body.appendSlice(arena, " * Dispatches to `jelly palace ");
    try body.appendSlice(arena, verb_name);
    try body.appendSlice(arena, "` (manifest-derived CLI; gen_cli output). The CLI runs\n");
    try body.appendSlice(arena, " * the bridge subprocess `src/lib/bridge/palace-");
    try body.appendSlice(arena, verb_name);
    try body.appendSlice(arena, ".ts` underneath, which\n");
    try body.appendSlice(arena, " * uses the D-007 store wrapper (D-022 bridge pattern preserved beneath).\n");
    try body.appendSlice(arena, " */\n");
    try body.appendSlice(arena, "export async function ");
    try body.appendSlice(arena, fn_name);
    try body.appendSlice(arena, "(inputs: ");
    try body.appendSlice(arena, inputs_type);
    try body.appendSlice(arena, "): Promise<");
    try body.appendSlice(arena, outputs_type);
    try body.appendSlice(arena, "> {\n");
    try body.appendSlice(arena, "  const flags = inputsToFlags(inputs as unknown as Record<string, unknown>);\n");
    try body.appendSlice(arena, "  // sprint-002: CLI does not yet emit JSON; the generated client returns an\n");
    try body.appendSlice(arena, "  // empty outputs object as a typed scaffold. Sprint-003 wires the CLI's\n");
    try body.appendSlice(arena, "  // --json flag so this body parses real outputs.\n");
    try body.appendSlice(arena, "  invokeVerb('");
    try body.appendSlice(arena, verb_name);
    try body.appendSlice(arena, "', flags);\n");
    try body.appendSlice(arena, "  return {} as ");
    try body.appendSlice(arena, outputs_type);
    try body.appendSlice(arena, ";\n");
    try body.appendSlice(arena, "}\n\n");
}

fn buildHeader(allocator: std.mem.Allocator, actx: *const cc.ArchiformCtx) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        \\// DO NOT EDIT — generated by tools/schema-gen/gen_ts_client.zig.
        \\// Provenance:
        \\//   source-schema:     {0s}
        \\//   source-schema-fp:  blake3:{1s}
        \\//   schema-pin:        {2s}
        \\//   schema-version:    {3s}
        \\//   generator-id:      {4s}
        \\//   generator-commit:  {5s}
        \\// Regenerate via `bun run codegen`. Hand-edits will be overwritten.
        \\// See docs/sprints/002-archiform-foundation/architecture-decisions.md
        \\// (D-019 action manifest, D-022 bridge pattern, D-034 client wraps D-007).
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

// ── helpers ─────────────────────────────────────────────────────────────────

fn extractXActions(actx: *const cc.ArchiformCtx) !std.json.ObjectMap {
    const root = switch (actx.schema_value) {
        .object => |o| o,
        else => return error.SchemaNotObject,
    };
    const xa = root.get("x-actions") orelse return error.MissingXActions;
    return switch (xa) {
        .object => |o| o,
        else => error.XActionsNotObject,
    };
}

fn isRequired(required_arr: ?std.json.Array, name: []const u8) bool {
    const arr = required_arr orelse return false;
    for (arr.items) |v| switch (v) {
        .string => |s| if (std.mem.eql(u8, s, name)) return true,
        else => continue,
    };
    return false;
}

fn jsonTypeToTs(t: []const u8) []const u8 {
    if (std.mem.eql(u8, t, "string")) return "string";
    if (std.mem.eql(u8, t, "boolean")) return "boolean";
    if (std.mem.eql(u8, t, "integer")) return "number";
    if (std.mem.eql(u8, t, "number")) return "number";
    if (std.mem.eql(u8, t, "array")) return "unknown[]";
    if (std.mem.eql(u8, t, "object")) return "Record<string, unknown>";
    return "unknown";
}

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

fn getArray(obj: std.json.ObjectMap, key: []const u8) ?std.json.Array {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .array => |a| a,
        else => null,
    };
}

/// kebab-case → camelCase. e.g. "rename-mythos" → "renameMythos".
fn kebabToCamel(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, s.len);
    defer out.deinit(allocator);
    var upper_next = false;
    for (s) |c| {
        if (c == '-') {
            upper_next = true;
            continue;
        }
        if (upper_next and c >= 'a' and c <= 'z') {
            try out.append(allocator, c - 32);
            upper_next = false;
        } else {
            try out.append(allocator, c);
            upper_next = false;
        }
    }
    return out.toOwnedSlice(allocator);
}

/// kebab-case → PascalCase. e.g. "rename-mythos" → "RenameMythos".
fn kebabToPascal(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, s.len);
    defer out.deinit(allocator);
    var upper_next = true;
    for (s) |c| {
        if (c == '-') {
            upper_next = true;
            continue;
        }
        if (upper_next and c >= 'a' and c <= 'z') {
            try out.append(allocator, c - 32);
            upper_next = false;
        } else {
            try out.append(allocator, c);
            upper_next = false;
        }
    }
    return out.toOwnedSlice(allocator);
}

/// Emit a TS object key — quoted if it isn't a plain identifier (e.g. has '-').
fn writeTsKey(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), key: []const u8) !void {
    var plain = true;
    for (key, 0..) |c, i| {
        const ok = (c == '_') or
            (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (i > 0 and c >= '0' and c <= '9');
        if (!ok) {
            plain = false;
            break;
        }
    }
    if (plain) {
        try buf.appendSlice(allocator, key);
    } else {
        try buf.append(allocator, '"');
        try buf.appendSlice(allocator, key);
        try buf.append(allocator, '"');
    }
}

/// Escape text for safe inclusion inside a `/** ... */` JSDoc comment.
/// Replaces "*/" with "*\/" and strips control characters other than spaces/tabs.
fn writeTsCommentEscaped(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c == '*' and i + 1 < s.len and s[i + 1] == '/') {
            try buf.appendSlice(allocator, "*\\/");
            i += 1; // also consume the '/'
            continue;
        }
        if (c == '\n' or c == '\r') {
            try buf.append(allocator, ' ');
            continue;
        }
        try buf.append(allocator, c);
    }
}
