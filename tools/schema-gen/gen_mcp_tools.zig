//! Story 4.2 — gen_mcp_tools per-archiform generator (D-019, D-035, FR9).
//!
//! Projects each entry of an archiform schema's `x-actions` map into one
//! MCP tool spec inside `src/lib/generated/palace-mcp-tools.ts`. Per AC1
//! each manifest action becomes a Tool with:
//!   - tool name = `palace.<action-key>` (e.g. `palace.mint`)
//!   - description = manifest's `summary`
//!   - inputSchema = manifest's `inputs` JSON-Schema fragment (verbatim)
//!   - handler = thin wrapper around the Story 4.1 generated TS client
//!     (D-034: the MCP layer wraps the client; the client wraps the
//!     bridges; the bridges wrap the D-007 store. AC6 grep audit confirms
//!     the only `from '../generated/...'`-style import in the emitted
//!     file references `palace-client.js`, never any store).
//!
//! Architectural commitments (recorded in DAR for Story 4.2):
//!   1. Generator location: NEW sibling `tools/schema-gen/gen_mcp_tools.zig`,
//!      dispatched from `runArchiformPass` after `gen_ts_client`. Keeps
//!      each generator small and focused (D-030 Option A philosophy; same
//!      shape as gen_cli + gen_ts_client).
//!   2. Output path: `src/lib/generated/palace-mcp-tools.ts` (single file
//!      containing all five tool specs + dispatcher).
//!   3. SDK shape (TC7, pinned `@modelcontextprotocol/sdk@1.29.0`): the
//!      file imports the `Tool` type and `RequestHandlerExtra`/server
//!      types only via `import type` so the artefact stays decoupled
//!      from any runtime SDK choice (the runtime entrypoint is Story
//!      4.3). Each tool exports a `register(mcpServer)` callback that
//!      uses `mcpServer.registerTool(...)` and surfaces elicitation via
//!      `mcpServer.server.elicitInput({ mode: 'form', ... })` when the
//!      manifest entry's `attributes.requiresConfirmation` is true.
//!   4. Closed-set typing (D-035): the `attributes` keys consumed are
//!      drawn from the closed set (`requiresConfirmation`,
//!      `confirmationMessage`, `destructive`, `agentVisible`); unknown
//!      values are not emitted. The generator does not encode
//!      `effects.kind` directly — the action body's effects are realised
//!      via the underlying client + bridge + envelope.
//!   5. Same-validator discipline (AC2): the input schema embedded in
//!      each Tool spec is the manifest's `inputs` JSON Schema fragment
//!      verbatim. The MCP SDK's `registerTool` runs Ajv-equivalent
//!      validation against this schema before dispatching the handler;
//!      the same JSON Schema document is also what Story 3.1's Ajv
//!      validator and the CLI dispatcher consume. One source, one shape,
//!      one validator behaviour.
//!   6. IC2 envelope-shape preservation: the handler delegates to the
//!      generated TS client (Story 4.1), which delegates to the
//!      manifest-derived CLI, which produces the existing signed-action
//!      envelope shape. The MCP layer adds zero new envelope fields.
//!
//! Provenance (NFR9): the generated file's header names
//! `schemas/memory-palace-0.1.0.json` + its pin file as source.

const std = @import("std");
const main_mod = @import("main.zig");
const gen_cypher = @import("gen_cypher.zig");

const OUT_PATH = "src/lib/generated/palace-mcp-tools.ts";

pub fn generateArchiform(actx: *const gen_cypher.ArchiformCtx) !void {
    const x_actions = extractXActions(actx) catch |e| {
        try main_mod.logKVPub(actx.stderr, .{
            .{ "phase", "mcp-tools-projection" },
            .{ "status", "error" },
            .{ "detail", "missing x-actions" },
            .{ "schema", actx.schema_path },
        });
        return e;
    };

    const arena = actx.arena;

    // Build provenance header.
    const header = try buildHeader(arena, actx);

    // Build body.
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(arena);

    try body.appendSlice(arena, PRELUDE);

    // First pass: collect verb names (kebab) so we can emit the imports.
    var verb_names: std.ArrayList([]const u8) = .empty;
    defer verb_names.deinit(arena);
    var key_iter = x_actions.iterator();
    while (key_iter.next()) |entry| {
        try verb_names.append(arena, entry.key_ptr.*);
    }

    // Emit the client import line. AC6: this is the ONLY `from './palace-client...'`
    // line in the file; no store imports.
    try body.appendSlice(arena, "import {\n");
    for (verb_names.items) |verb| {
        const fn_name = try kebabToCamel(arena, verb);
        try body.appendSlice(arena, "  ");
        try body.appendSlice(arena, fn_name);
        try body.appendSlice(arena, ",\n");
    }
    try body.appendSlice(arena, "} from './palace-client.js';\n\n");

    // Emit per-verb tool spec.
    var iter = x_actions.iterator();
    while (iter.next()) |entry| {
        const verb_name = entry.key_ptr.*;
        const manifest_obj = switch (entry.value_ptr.*) {
            .object => |o| o,
            else => {
                try main_mod.logKVPub(actx.stderr, .{
                    .{ "phase", "mcp-tools-projection" },
                    .{ "status", "error" },
                    .{ "verb", verb_name },
                    .{ "detail", "manifest entry is not an object" },
                });
                return error.MalformedManifest;
            },
        };
        try projectVerb(arena, &body, verb_name, manifest_obj);
    }

    // Emit aggregate registration helper.
    try emitRegisterAll(arena, &body, verb_names.items);

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
        .{ "pass", "mcp-tools-projection" },
    });
}

const PRELUDE =
    \\// palace-mcp-tools.ts — generated MCP tool spec projection of the Memory
    \\// Palace archiform's `x-actions` manifest (D-019, FR9, Story 4.2).
    \\//
    \\// One MCP tool per manifest action. Tool name = `palace.<action-key>`.
    \\// Tool description = manifest's `summary`. Tool inputSchema = manifest's
    \\// `inputs` JSON Schema fragment verbatim (AC2: same JSON Schema document
    \\// the CLI / Story 3.1 Ajv validator consume — one source of truth).
    \\//
    \\// Per D-034: this file imports ONLY from the Story 4.1 generated client
    \\// (`./palace-client.js`). It MUST NOT import from `../store`, the bridge
    \\// modules, `@ladybugdb/core`, or kuzu. The AC6 grep audit verifies this.
    \\//
    \\// Per AC4: when a manifest action's `attributes.requiresConfirmation` is
    \\// true, the handler surfaces an MCP elicitation step (via the SDK's
    \\// `server.elicitInput({ mode: 'form', ... })`) on first call and only
    \\// dispatches to the underlying client after the user grants the
    \\// elicitation. The manifest's `confirmationMessage` is the prompt copy.
    \\//
    \\// Per IC2: actions invoked via MCP serialize to the existing signed-
    \\// action envelope shape. The handler delegates to the generated client,
    \\// which dispatches to the manifest-derived CLI, which produces the
    \\// envelope. No new envelope fields here.
    \\//
    \\// Pinned MCP SDK floor (TC7): `@modelcontextprotocol/sdk@1.29.0`. This
    \\// file uses `import type` so swapping minor versions does not require
    \\// regenerating the artefact.
    \\
    \\import type {
    \\  Tool,
    \\  ElicitRequestFormParams,
    \\  ElicitRequestURLParams,
    \\  ElicitResult,
    \\} from '@modelcontextprotocol/sdk/types.js';
    \\
    \\/**
    \\ * Elicitation callback shape — the runtime entrypoint (Story 4.3) wires
    \\ * this to `mcpServer.server.elicitInput`. Decoupling the callback here
    \\ * keeps this generated artefact free of any McpServer instance binding,
    \\ * which makes the Story 4.2 elicitation spike self-contained (the test
    \\ * passes its own elicit callback, no full transport pair required).
    \\ */
    \\export type ElicitFn = (
    \\  params: ElicitRequestFormParams | ElicitRequestURLParams,
    \\) => Promise<ElicitResult>;
    \\
    \\/** Per-invocation context threaded into every tool handler. */
    \\export interface HandlerContext {
    \\  /** Elicitation callback (typically `mcpServer.server.elicitInput.bind(mcpServer.server)`). */
    \\  elicit: ElicitFn;
    \\  /** Set to true on the second call after the user grants the elicitation. */
    \\  confirmed?: boolean;
    \\}
    \\
    \\/** Discriminated handler result (AC4). */
    \\export type HandlerResult =
    \\  | { elicited: true; confirmed: false }
    \\  | { elicited: false; confirmed: true; output: unknown };
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

    const attributes = getObject(manifest, "attributes");
    const requires_confirmation = blk: {
        const attrs = attributes orelse break :blk false;
        const v = attrs.get("requiresConfirmation") orelse break :blk false;
        break :blk switch (v) {
            .bool => |b| b,
            else => false,
        };
    };
    const confirmation_message = blk: {
        const attrs = attributes orelse break :blk "";
        break :blk getString(attrs, "confirmationMessage") orelse "";
    };

    const fn_name = try kebabToCamel(arena, verb_name);
    const pascal = try kebabToPascal(arena, verb_name);

    const tool_name = try std.fmt.allocPrint(arena, "palace.{s}", .{verb_name});
    const spec_const = try std.fmt.allocPrint(arena, "{s}_TOOL", .{try toUpperSnake(arena, verb_name)});

    // ── Tool spec ────────────────────────────────────────────────────────────
    try body.appendSlice(arena, "/** MCP Tool spec for `");
    try body.appendSlice(arena, tool_name);
    try body.appendSlice(arena, "`. */\n");
    try body.appendSlice(arena, "export const ");
    try body.appendSlice(arena, spec_const);
    try body.appendSlice(arena, ": Tool = {\n");
    try body.appendSlice(arena, "  name: '");
    try body.appendSlice(arena, tool_name);
    try body.appendSlice(arena, "',\n");
    try body.appendSlice(arena, "  description: ");
    try writeJsString(arena, body, summary);
    try body.appendSlice(arena, ",\n");
    try body.appendSlice(arena, "  inputSchema: ");
    try writeInputSchema(arena, body, inputs_obj, 1);
    try body.appendSlice(arena, ",\n");
    if (requires_confirmation) {
        try body.appendSlice(arena, "  annotations: { destructiveHint: true, title: ");
        try writeJsString(arena, body, confirmation_message);
        try body.appendSlice(arena, " },\n");
    }
    try body.appendSlice(arena, "};\n\n");

    // ── Handler ──────────────────────────────────────────────────────────────
    try body.appendSlice(arena, "/** Handler for `");
    try body.appendSlice(arena, tool_name);
    try body.appendSlice(arena, "`. Wraps Story 4.1's generated client (D-034).\n");
    try body.appendSlice(arena, " *\n");
    try body.appendSlice(arena, " * Per AC4: when the manifest entry's `attributes.requiresConfirmation`\n");
    try body.appendSlice(arena, " * is true, the handler invokes `elicit({ mode: 'form', ... })` on first\n");
    try body.appendSlice(arena, " * call and only dispatches the action after the user grants the\n");
    try body.appendSlice(arena, " * elicitation. The `elicit` callback is the SDK's elicitInput; the\n");
    try body.appendSlice(arena, " * runtime entrypoint (Story 4.3) wires it to `mcpServer.server.elicitInput`.\n");
    try body.appendSlice(arena, " */\n");
    try body.appendSlice(arena, "export async function handle");
    try body.appendSlice(arena, pascal);
    try body.appendSlice(arena, "(\n");
    try body.appendSlice(arena, "  args: Record<string, unknown>,\n");
    try body.appendSlice(arena, "  ctx: HandlerContext,\n");
    try body.appendSlice(arena, "): Promise<HandlerResult> {\n");

    if (requires_confirmation) {
        try body.appendSlice(arena, "  // AC4: surface MCP elicitation on first call. Pinned SDK\n");
        try body.appendSlice(arena, "  // @modelcontextprotocol/sdk@1.29.0 form-mode elicitation request shape:\n");
        try body.appendSlice(arena, "  // `{ mode: 'form', message, requestedSchema: { type: 'object', properties, required } }`.\n");
        try body.appendSlice(arena, "  if (!ctx.confirmed) {\n");
        try body.appendSlice(arena, "    const elicitResult = await ctx.elicit({\n");
        try body.appendSlice(arena, "      mode: 'form',\n");
        try body.appendSlice(arena, "      message: ");
        try writeJsString(arena, body, confirmation_message);
        try body.appendSlice(arena, ",\n");
        try body.appendSlice(arena, "      requestedSchema: {\n");
        try body.appendSlice(arena, "        type: 'object',\n");
        try body.appendSlice(arena, "        properties: {\n");
        try body.appendSlice(arena, "          confirm: {\n");
        try body.appendSlice(arena, "            type: 'boolean',\n");
        try body.appendSlice(arena, "            title: 'Confirm',\n");
        try body.appendSlice(arena, "            description: ");
        try writeJsString(arena, body, confirmation_message);
        try body.appendSlice(arena, ",\n");
        try body.appendSlice(arena, "          },\n");
        try body.appendSlice(arena, "        },\n");
        try body.appendSlice(arena, "        required: ['confirm'],\n");
        try body.appendSlice(arena, "      },\n");
        try body.appendSlice(arena, "    });\n");
        try body.appendSlice(arena, "    const accepted =\n");
        try body.appendSlice(arena, "      elicitResult.action === 'accept' &&\n");
        try body.appendSlice(arena, "      typeof elicitResult.content === 'object' &&\n");
        try body.appendSlice(arena, "      elicitResult.content !== null &&\n");
        try body.appendSlice(arena, "      (elicitResult.content as { confirm?: unknown }).confirm === true;\n");
        try body.appendSlice(arena, "    if (!accepted) {\n");
        try body.appendSlice(arena, "      return { elicited: true, confirmed: false };\n");
        try body.appendSlice(arena, "    }\n");
        try body.appendSlice(arena, "    return handle");
        try body.appendSlice(arena, pascal);
        try body.appendSlice(arena, "(args, { ...ctx, confirmed: true });\n");
        try body.appendSlice(arena, "  }\n");
    }

    try body.appendSlice(arena, "  // Dispatch to the Story 4.1 generated client. The client wraps the\n");
    try body.appendSlice(arena, "  // manifest-derived CLI which preserves the bridge pattern (D-022).\n");
    try body.appendSlice(arena, "  // Type assertion: validation already happened via the Tool's\n");
    try body.appendSlice(arena, "  // inputSchema (AC2 — JSON Schema verbatim from manifest).\n");
    try body.appendSlice(arena, "  const result = await ");
    try body.appendSlice(arena, fn_name);
    try body.appendSlice(arena, "(args as unknown as Parameters<typeof ");
    try body.appendSlice(arena, fn_name);
    try body.appendSlice(arena, ">[0]);\n");
    try body.appendSlice(arena, "  return { elicited: false, confirmed: true, output: result };\n");
    try body.appendSlice(arena, "}\n\n");
}

fn emitRegisterAll(
    arena: std.mem.Allocator,
    body: *std.ArrayList(u8),
    verbs: [][]const u8,
) !void {
    try body.appendSlice(arena, "/** Aggregate Tool[] for callers that want the full spec set. */\n");
    try body.appendSlice(arena, "export const PALACE_TOOLS: readonly Tool[] = [\n");
    for (verbs) |verb| {
        const upper = try toUpperSnake(arena, verb);
        try body.appendSlice(arena, "  ");
        try body.appendSlice(arena, upper);
        try body.appendSlice(arena, "_TOOL,\n");
    }
    try body.appendSlice(arena, "];\n\n");

    try body.appendSlice(arena, "/** Dispatch table: tool name → handler. The runtime entrypoint (Story 4.3) */\n");
    try body.appendSlice(arena, "/** wires this map into its `tools/call` request handler. */\n");
    try body.appendSlice(arena, "export const PALACE_HANDLERS: Record<\n");
    try body.appendSlice(arena, "  string,\n");
    try body.appendSlice(arena, "  (args: Record<string, unknown>, ctx: HandlerContext) => Promise<HandlerResult>\n");
    try body.appendSlice(arena, "> = {\n");
    for (verbs) |verb| {
        const pascal = try kebabToPascal(arena, verb);
        try body.appendSlice(arena, "  'palace.");
        try body.appendSlice(arena, verb);
        try body.appendSlice(arena, "': handle");
        try body.appendSlice(arena, pascal);
        try body.appendSlice(arena, ",\n");
    }
    try body.appendSlice(arena, "};\n");
}

fn buildHeader(allocator: std.mem.Allocator, actx: *const gen_cypher.ArchiformCtx) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        \\// DO NOT EDIT — generated by tools/schema-gen/gen_mcp_tools.zig.
        \\// Provenance:
        \\//   source-schema:     {0s}
        \\//   source-schema-fp:  blake3:{1s}
        \\//   schema-pin:        {2s}
        \\//   schema-version:    {3s}
        \\//   generator-id:      {4s}
        \\//   generator-commit:  {5s}
        \\// Regenerate via `bun run codegen`. Hand-edits will be overwritten.
        \\// See docs/sprints/002-archiform-foundation/architecture-decisions.md
        \\// (D-019 action manifest, D-035 closed sets, D-034 client wrapping).
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

fn extractXActions(actx: *const gen_cypher.ArchiformCtx) !std.json.ObjectMap {
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

/// kebab-case → camelCase. e.g. "rename-mythos" → "renameMythos".
fn kebabToCamel(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, s.len);
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

/// kebab-case → PascalCase.
fn kebabToPascal(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, s.len);
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

/// kebab-case → UPPER_SNAKE_CASE.
fn toUpperSnake(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, s.len);
    for (s) |c| {
        if (c == '-') {
            try out.append(allocator, '_');
        } else if (c >= 'a' and c <= 'z') {
            try out.append(allocator, c - 32);
        } else {
            try out.append(allocator, c);
        }
    }
    return out.toOwnedSlice(allocator);
}

/// Emit a JSON-Schema object/value as a TS object literal. Used to embed
/// the manifest's `inputs` fragment directly into the generated Tool spec.
/// The output is valid TypeScript syntax (uses single-quoted strings,
/// trailing-commas-omitted for safety, and inlines all primitive values).
fn writeInputSchema(
    arena: std.mem.Allocator,
    body: *std.ArrayList(u8),
    obj: std.json.ObjectMap,
    indent: usize,
) !void {
    try body.append(arena, '{');
    try body.append(arena, '\n');
    var iter = obj.iterator();
    while (iter.next()) |entry| {
        try writeIndent(arena, body, indent + 1);
        try writeJsKey(arena, body, entry.key_ptr.*);
        try body.appendSlice(arena, ": ");
        try writeJsonValue(arena, body, entry.value_ptr.*, indent + 1);
        try body.appendSlice(arena, ",\n");
    }
    try writeIndent(arena, body, indent);
    try body.append(arena, '}');
}

fn writeJsonValue(
    arena: std.mem.Allocator,
    body: *std.ArrayList(u8),
    v: std.json.Value,
    indent: usize,
) !void {
    switch (v) {
        .null => try body.appendSlice(arena, "null"),
        .bool => |b| try body.appendSlice(arena, if (b) "true" else "false"),
        .integer => |i| {
            var buf: [32]u8 = undefined;
            const slice = try std.fmt.bufPrint(&buf, "{d}", .{i});
            try body.appendSlice(arena, slice);
        },
        .float => |f| {
            var buf: [32]u8 = undefined;
            const slice = try std.fmt.bufPrint(&buf, "{d}", .{f});
            try body.appendSlice(arena, slice);
        },
        .number_string => |s| try body.appendSlice(arena, s),
        .string => |s| try writeJsString(arena, body, s),
        .array => |arr| {
            if (arr.items.len == 0) {
                try body.appendSlice(arena, "[]");
                return;
            }
            try body.appendSlice(arena, "[\n");
            for (arr.items) |item| {
                try writeIndent(arena, body, indent + 1);
                try writeJsonValue(arena, body, item, indent + 1);
                try body.appendSlice(arena, ",\n");
            }
            try writeIndent(arena, body, indent);
            try body.append(arena, ']');
        },
        .object => |o| {
            if (o.count() == 0) {
                try body.appendSlice(arena, "{}");
                return;
            }
            try body.appendSlice(arena, "{\n");
            var oit = o.iterator();
            while (oit.next()) |oent| {
                try writeIndent(arena, body, indent + 1);
                try writeJsKey(arena, body, oent.key_ptr.*);
                try body.appendSlice(arena, ": ");
                try writeJsonValue(arena, body, oent.value_ptr.*, indent + 1);
                try body.appendSlice(arena, ",\n");
            }
            try writeIndent(arena, body, indent);
            try body.append(arena, '}');
        },
    }
}

fn writeIndent(arena: std.mem.Allocator, body: *std.ArrayList(u8), level: usize) !void {
    var i: usize = 0;
    while (i < level) : (i += 1) {
        try body.appendSlice(arena, "  ");
    }
}

/// Write a JS object key — quoted always (safest; manifest keys may contain
/// hyphens or other non-identifier characters).
fn writeJsKey(arena: std.mem.Allocator, body: *std.ArrayList(u8), key: []const u8) !void {
    try writeJsString(arena, body, key);
}

/// Write a TS/JS string literal using single quotes. Escapes `\\`, `'`, and
/// non-printable bytes; passes through Unicode code points raw (the file is
/// UTF-8).
fn writeJsString(arena: std.mem.Allocator, body: *std.ArrayList(u8), s: []const u8) !void {
    try body.append(arena, '\'');
    for (s) |c| {
        switch (c) {
            '\\' => try body.appendSlice(arena, "\\\\"),
            '\'' => try body.appendSlice(arena, "\\'"),
            '\n' => try body.appendSlice(arena, "\\n"),
            '\r' => try body.appendSlice(arena, "\\r"),
            '\t' => try body.appendSlice(arena, "\\t"),
            else => {
                if (c < 0x20) {
                    var buf: [8]u8 = undefined;
                    const slice = try std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c});
                    try body.appendSlice(arena, slice);
                } else {
                    try body.append(arena, c);
                }
            },
        }
    }
    try body.append(arena, '\'');
}
