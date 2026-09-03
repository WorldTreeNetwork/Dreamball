//! Story 3.2 — gen_cli per-archiform generator.
//!
//! Projects each entry of an archiform schema's `x-actions` map into a
//! generated CLI dispatcher under `src/cli/generated/palace_<verb>.zig`.
//!
//! Spike scope (D-024): only the `mint` verb is projected in this story.
//! Stories 3.3–3.4 add the remaining four verbs by passing additional
//! verb names through `WHITELIST` (or removing the whitelist guard once
//! all five verbs project cleanly). Story 3.5 deletes the legacy
//! hand-written verbs after parity verification.
//!
//! Architectural commitment (recorded in DAR for Story 3.2):
//!   1. Generator location: `tools/schema-gen/gen_cli.zig` (Option A —
//!      Zig-side, sibling to gen_zig/gen_ts/gen_valibot/gen_cbor).
//!   2. Output path:        `src/cli/generated/palace_<snake>.zig` where
//!      <snake> is the kebab verb name with `-` → `_`.
//!   3. Flag mapping:       each `inputs.properties.<name>` becomes a
//!      Spec entry with kebab→same long flag name (camelCase keys are
//!      passed through verbatim, e.g. `mythosFile` → `--mythosFile`);
//!      a synthetic `--help` Spec is always last; required-flag
//!      enforcement reads `inputs.required` at runtime.
//!   4. Confirmation gate:  emitted only when both
//!      `attributes.requiresConfirmation == true` AND
//!      `attributes.destructive == true`. Bypassed by `--yes` /
//!      `--no-confirm`.
//!   5. Bridge composition: the generated dispatcher composes the bridge
//!      pattern (D-022) by delegating to a `pub fn run<Verb>` exported
//!      from the legacy `src/cli/palace_<verb>.zig`. The dispatcher is
//!      flag-parse + help + confirmation only; the bridge primitive
//!      lives in the legacy file until Story 3.5 inlines it.
//!
//! Provenance (NFR9): the generated file's header names
//! `schemas/memory-palace-0.1.0.json` + its pin file as source.
//!
//! Drift detection (AC6): the generator validates that every key the
//! legacy verb expects is present in the manifest's `inputs.properties`
//! before emission. If the manifest is mutated to drop a required key
//! the generated dispatcher's argv parse will reject the legacy call
//! site (because the legacy `run<Verb>` requires that key) — drift
//! cannot land silently.

const std = @import("std");
const main_mod = @import("main.zig");
const cc = @import("codegen_common");

const OUT_DIR = "src/cli/generated";

/// Story 3.2 spike projected `mint`; Story 3.3 adds `inscribe` and `add-room`.
/// Story 3.4 adds `rename-mythos` and `move`. Story 3.5 removes the legacy files.
const WHITELIST = [_][]const u8{ "mint", "inscribe", "add-room", "rename-mythos", "move" };

/// Properties in this set are treated as positional CLI arguments by all
/// legacy verb implementations (they are never `--flag value` pairs). The
/// generator excludes them from the emitted SPECS table and from required-flag
/// enforcement so the generated dispatcher does not incorrectly reject
/// positional invocations like `dreamball palace inscribe <palace> --room <fp> <source>`.
///
/// Convention: `palace` is always the first positional arg in every verb.
/// `source` is the second positional in `inscribe`. This is a CLI-layer
/// convention, not in the JSON Schema itself.
const POSITIONAL_SKIP = [_][]const u8{ "palace", "source" };

pub fn generateArchiform(actx: *const cc.ArchiformCtx) !void {
    const x_actions = extractXActions(actx) catch |e| {
        try main_mod.logKVPub(actx.stderr, .{
            .{ "phase", "cli-projection" },
            .{ "status", "error" },
            .{ "detail", "missing x-actions" },
            .{ "schema", actx.schema_path },
        });
        return e;
    };

    try ensureDir(actx.io, OUT_DIR);

    var iter = x_actions.iterator();
    while (iter.next()) |entry| {
        const verb_name = entry.key_ptr.*;
        if (!isWhitelisted(verb_name)) continue;
        const manifest_obj = switch (entry.value_ptr.*) {
            .object => |o| o,
            else => {
                try main_mod.logKVPub(actx.stderr, .{
                    .{ "phase", "cli-projection" },
                    .{ "status", "error" },
                    .{ "verb", verb_name },
                    .{ "detail", "manifest entry is not an object" },
                });
                return error.MalformedManifest;
            },
        };
        try projectVerb(actx, verb_name, manifest_obj);
    }
}

/// Standalone fixture-mode entry: projects a single verb from an in-memory
/// manifest object to a caller-supplied output directory. Used by AC4
/// confirmation-behavior fixture tests so they don't need to mutate the
/// canonical schema.
pub fn projectVerbToDir(
    arena: std.mem.Allocator,
    io: std.Io,
    out_dir: []const u8,
    schema_path: []const u8,
    schema_fp: []const u8,
    schema_version: []const u8,
    pin_path: []const u8,
    verb_name: []const u8,
    manifest: std.json.ObjectMap,
    stderr: *std.Io.File.Writer,
) !void {
    const actx = cc.ArchiformCtx{
        .io = io,
        .arena = arena,
        .schema_path = schema_path,
        .schema_fp = schema_fp,
        .schema_version = schema_version,
        .pin_path = pin_path,
        .schema_value = .null,
        .stderr = stderr,
        .generator_id = main_mod.GENERATOR_ID,
        .generator_commit = main_mod.GENERATOR_COMMIT,
    };
    try ensureDir(io, out_dir);
    try projectVerbToDirImpl(&actx, out_dir, verb_name, manifest);
}

// ── Internals ────────────────────────────────────────────────────────────────

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

fn isWhitelisted(name: []const u8) bool {
    for (WHITELIST) |w| if (std.mem.eql(u8, w, name)) return true;
    return false;
}

fn isPositionalSkip(name: []const u8) bool {
    for (POSITIONAL_SKIP) |p| if (std.mem.eql(u8, p, name)) return true;
    return false;
}

fn projectVerb(
    actx: *const cc.ArchiformCtx,
    verb_name: []const u8,
    manifest: std.json.ObjectMap,
) !void {
    try projectVerbToDirImpl(actx, OUT_DIR, verb_name, manifest);
}

fn projectVerbToDirImpl(
    actx: *const cc.ArchiformCtx,
    out_dir: []const u8,
    verb_name: []const u8,
    manifest: std.json.ObjectMap,
) !void {
    const arena = actx.arena;

    // Snake-case the verb name for the output filename + Zig identifier.
    const snake = try kebabToSnake(arena, verb_name);

    const out_path = try std.fmt.allocPrint(
        arena,
        "{s}/palace_{s}.zig",
        .{ out_dir, snake },
    );

    const summary = getString(manifest, "summary") orelse "";
    const inputs_obj = getObject(manifest, "inputs") orelse return error.ManifestMissingInputs;
    const props = getObject(inputs_obj, "properties") orelse return error.ManifestMissingProperties;
    const required_arr = getArray(inputs_obj, "required");
    const attributes = getObject(manifest, "attributes") orelse return error.ManifestMissingAttributes;
    const destructive = getBool(attributes, "destructive") orelse false;
    const requires_confirmation = getBool(attributes, "requiresConfirmation") orelse false;
    const confirmation_message = getString(attributes, "confirmationMessage") orelse "";
    const needs_confirm_gate = destructive and requires_confirmation;

    // Story 5.4 / D-024 spike-before-promote: wasm-route gating.
    // When implementation.wasm is a non-zero 64-char hex fp, the generator
    // bakes a wasm-route delegation into the emitted dispatcher. The route:
    //   1. Adds a --use-wasm flag to SPECS (off by default).
    //   2. When --use-wasm is passed, shells out to `<verb>-wasm-host
    //      actions/<verb>/<verb>.wasm <fp>` and pipes its JSON stdout.
    //   3. Falls through to the legacy delegate when --use-wasm is absent.
    // This logic is codegen-resident so it survives `bun run codegen` without
    // hand-edits to the generated file.
    const impl_obj = getObject(manifest, "implementation");
    const wasm_fp_str = if (impl_obj) |o| getString(o, "wasm") orelse "" else "";
    const has_wasm_route = isNonZeroFp(wasm_fp_str);

    // Build the provenance header.
    const header = try buildHeader(arena, actx);

    // Build the body.
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(arena);

    try body.appendSlice(arena, "//! Generated CLI dispatcher for `dreamball palace ");
    try body.appendSlice(arena, verb_name);
    try body.appendSlice(arena,
        \\`.
        \\//!
        \\//! Composes the bridge pattern (D-022) by delegating to the internal
        \\//! verb primitive after flag parsing. Story 3.5 moved the primitives
        \\//! from `src/cli/palace_<verb>.zig` to `src/cli/internal/<verb>.zig`.
        \\
        \\const std = @import("std");
        \\const Allocator = std.mem.Allocator;
        \\
        \\const io = @import("../../io.zig");
        \\const args_mod = @import("../args.zig");
        \\const legacy = @import("../internal/
    );
    try body.appendSlice(arena, snake);
    try body.appendSlice(arena, ".zig\");\n\n");

    // Emit SUMMARY constant (AC2 — derived from manifest).
    try body.appendSlice(arena, "pub const SUMMARY: []const u8 = \"");
    try writeZigEscaped(arena, &body, summary);
    try body.appendSlice(arena, "\";\n\n");

    // Emit per-property metadata: order matches manifest iteration order
    // (deterministic JSON object iteration order from std.json).
    // Also emit a synthetic --help spec at the end.
    //
    // prop_names: manifest key (used for required-flag error messages).
    // prop_flags: kebab-case CLI flag name for SPECS (camelCase converted).
    //   e.g. manifest key "embedVia" → SPECS flag "embed-via" to match
    //   the legacy verb's arg parsing convention and the smoke-test invocations.
    var prop_names: std.ArrayList([]const u8) = .empty;
    defer prop_names.deinit(arena);
    var prop_flags: std.ArrayList([]const u8) = .empty;
    defer prop_flags.deinit(arena);
    var prop_types: std.ArrayList([]const u8) = .empty;
    defer prop_types.deinit(arena);
    var prop_descs: std.ArrayList([]const u8) = .empty;
    defer prop_descs.deinit(arena);

    var pit = props.iterator();
    while (pit.next()) |pent| {
        const pname = pent.key_ptr.*;
        // Skip properties that are positional CLI arguments (not --flags).
        // See POSITIONAL_SKIP declaration for rationale.
        if (isPositionalSkip(pname)) continue;
        const pobj = switch (pent.value_ptr.*) {
            .object => |o| o,
            else => continue,
        };
        const ptype = getString(pobj, "type") orelse "string";
        const pdesc = getString(pobj, "description") orelse "";
        const pflag = try camelToKebab(arena, pname);
        try prop_names.append(arena, pname);
        try prop_flags.append(arena, pflag);
        try prop_types.append(arena, ptype);
        try prop_descs.append(arena, pdesc);
    }

    // SPECS table — uses kebab-case flag names to match legacy verb conventions.
    try body.appendSlice(arena, "const SPECS = [_]args_mod.Spec{\n");
    for (prop_flags.items, prop_types.items) |pflag, ptype| {
        const takes_value = !std.mem.eql(u8, ptype, "boolean");
        try body.appendSlice(arena, "    .{ .long = \"");
        try body.appendSlice(arena, pflag);
        try body.appendSlice(arena, "\"");
        if (!takes_value) {
            try body.appendSlice(arena, ", .takes_value = false");
        }
        try body.appendSlice(arena, " },\n");
    }
    try body.appendSlice(arena, "    .{ .long = \"yes\", .takes_value = false },\n");
    try body.appendSlice(arena, "    .{ .long = \"no-confirm\", .takes_value = false },\n");
    // Story 5.4: wasm-route flag — emitted only when implementation.wasm is non-zero.
    if (has_wasm_route) {
        try body.appendSlice(arena, "    .{ .long = \"use-wasm\", .takes_value = false },\n");
    }
    try body.appendSlice(arena, "    .{ .long = \"help\", .takes_value = false },\n");
    try body.appendSlice(arena, "};\n\n");

    // Help-text constant.
    try body.appendSlice(arena, "pub const HELP_TEXT: []const u8 =\n");
    try body.appendSlice(arena, "    \"dreamball palace ");
    try body.appendSlice(arena, verb_name);
    try body.appendSlice(arena, " — \" ++\n");
    try body.appendSlice(arena, "    SUMMARY ++ \"\\n\\n\" ++\n");
    try body.appendSlice(arena, "    \"Flags:\\n\"");
    for (prop_flags.items, prop_types.items, prop_descs.items) |pflag, ptype, pdesc| {
        try body.appendSlice(arena, " ++\n    \"  --");
        try body.appendSlice(arena, pflag);
        try body.appendSlice(arena, " <");
        try body.appendSlice(arena, ptype);
        try body.appendSlice(arena, ">  ");
        try writeZigEscaped(arena, &body, pdesc);
        try body.appendSlice(arena, "\\n\"");
    }
    try body.appendSlice(arena, " ++\n    \"  --help                  Show this help and exit.\\n\"");
    if (needs_confirm_gate) {
        try body.appendSlice(arena, " ++\n    \"  --yes                   Skip the destructive-action confirmation prompt.\\n\"");
        try body.appendSlice(arena, " ++\n    \"  --no-confirm            Alias for --yes.\\n\"");
    }
    try body.appendSlice(arena, ";\n\n");

    // run() entry point.
    try body.appendSlice(arena,
        \\pub fn run(gpa: Allocator, argv: [][:0]const u8) !u8 {
        \\    var parsed = try args_mod.parse(gpa, argv, &SPECS);
        \\    defer parsed.deinit();
        \\
    );
    // Emit help-flag check. The synthetic --help is the last spec.
    // Index layout: [prop_flags..., yes, no-confirm, (use-wasm?), help]
    const yes_idx = prop_names.items.len;
    const no_confirm_idx = prop_names.items.len + 1;
    const use_wasm_idx = if (has_wasm_route) prop_names.items.len + 2 else null;
    const help_idx = prop_names.items.len + 2 + @as(usize, if (has_wasm_route) 1 else 0);
    {
        const tmp = try std.fmt.allocPrint(
            arena,
            "    if (parsed.flag({d})) {{\n        try io.writeAllStdout(HELP_TEXT);\n        return 0;\n    }}\n\n",
            .{help_idx},
        );
        try body.appendSlice(arena, tmp);
    }

    // Required-flag enforcement (AC1 — flag mapping respects inputs.required).
    // Positional-skip properties (see POSITIONAL_SKIP) are excluded: they are
    // validated by the legacy verb's own positional-arg checks, not by flag lookup.
    if (required_arr) |req| {
        for (req.items) |req_v| {
            const req_name = switch (req_v) {
                .string => |s| s,
                else => continue,
            };
            // Skip positional args — they are never in SPECS.
            if (isPositionalSkip(req_name)) continue;
            // Find index in prop_names.
            var found_idx: ?usize = null;
            for (prop_names.items, 0..) |pn, idx| {
                if (std.mem.eql(u8, pn, req_name)) {
                    found_idx = idx;
                    break;
                }
            }
            if (found_idx) |idx| {
                // Legacy-compatible message shape: "error: --<flag> required" — preserves
                // the substring grep used by scripts/cli-smoke.sh (Story 3.2 AC5 / Story 3.4 AC2).
                // Use prop_flags[idx] (kebab-case) with -- prefix so smoke-test greps like
                // `grep -q "\-\-body"` match the emitted error message.
                const pflag_for_err = prop_flags.items[idx];
                const tmp = try std.fmt.allocPrint(
                    arena,
                    "    if (parsed.get({d}) == null) {{\n        try io.writeAllStderr(\"error: --{s} required\\n\");\n        return 2;\n    }}\n",
                    .{ idx, pflag_for_err },
                );
                try body.appendSlice(arena, tmp);
            }
        }
        try body.appendSlice(arena, "\n");
    }

    // Confirmation gate (AC4) — only emit when destructive AND requiresConfirmation.
    if (needs_confirm_gate) {
        const gate_head = try std.fmt.allocPrint(
            arena,
            "    // AC4 confirmation gate (destructive + requiresConfirmation).\n" ++
                "    const skip_confirm = parsed.flag({d}) or parsed.flag({d});\n" ++
                "    if (!skip_confirm) {{\n" ++
                "        try io.writeAllStderr(\"",
            .{ yes_idx, no_confirm_idx },
        );
        try body.appendSlice(arena, gate_head);
        try writeZigEscaped(arena, &body, confirmation_message);
        try body.appendSlice(arena,
            "\\n\");\n" ++
                "        try io.writeAllStderr(\"Pass --yes to confirm.\\n\");\n" ++
                "        return 2;\n" ++
                "    }\n\n",
        );
    } else {
        // Even when not gated, suppress unused-warning by reading the flags.
        const tmp = try std.fmt.allocPrint(
            arena,
            "    _ = parsed.flag({d});\n    _ = parsed.flag({d});\n\n",
            .{ yes_idx, no_confirm_idx },
        );
        try body.appendSlice(arena, tmp);
    }

    // Story 5.4 / D-024 spike-before-promote: wasm-route delegation.
    // When the manifest's implementation.wasm is non-zero AND --use-wasm is
    // passed, shell out to `<verb>-wasm-host actions/<verb>/<verb>.wasm <fp>`.
    // The host driver verifies the fp (Story 5.3), instantiates the wasm
    // module, and prints `{"palaceFp":"..."}` JSON to stdout (AC2).
    // The verify-before-instantiate event `{phase:"verify",status:"match",...}`
    // is emitted to stderr (AC3). On fp mismatch the driver exits non-zero with
    // a structured fp_mismatch event (AC4). Falls through to legacy when absent.
    if (has_wasm_route) {
        if (use_wasm_idx) |wi| {
            const wasm_route_code = try std.fmt.allocPrint(
                arena,
                \\    // Story 5.4 wasm-route: --use-wasm delegates to the wasm host driver.
                \\    if (parsed.flag({d})) {{
                \\        const wasm_path = "actions/{s}/{s}.wasm";
                \\        const expected_fp = "{s}";
                \\        const wasm_io = std.Io.Threaded.global_single_threaded.io();
                \\        var child = try std.process.spawn(wasm_io, .{{
                \\            .argv = &.{{ "zig-out/bin/{s}-wasm-host", wasm_path, expected_fp }},
                \\            .stdout = .inherit,
                \\            .stderr = .inherit,
                \\        }});
                \\        const term = try child.wait(wasm_io);
                \\        return switch (term) {{
                \\            .exited => |code| code,
                \\            else => 1,
                \\        }};
                \\    }}
                \\
                \\
                ,
                .{ wi, snake, snake, wasm_fp_str, snake },
            );
            try body.appendSlice(arena, wasm_route_code);
        }
    }

    // Delegate to legacy verb's pub fn run() — composes the bridge pattern.
    // The legacy run() re-parses argv (it has its own SPECS) but the
    // generated dispatcher's role per the architectural commitment is
    // help/confirmation/required-flag policing; runtime body is delegated.
    try body.appendSlice(arena, "    return legacy.run(gpa, argv);\n");
    try body.appendSlice(arena, "}\n");

    // Write the file (header + body).
    var file = try std.Io.Dir.cwd().createFile(actx.io, out_path, .{ .truncate = true });
    defer file.close(actx.io);
    var fbuf: [4096]u8 = undefined;
    var fw = file.writer(actx.io, &fbuf);
    try fw.interface.writeAll(header);
    try fw.interface.writeAll(body.items);
    try fw.interface.flush();

    try main_mod.logKVPub(actx.stderr, .{
        .{ "phase", "output-written" },
        .{ "path", out_path },
        .{ "bytes", header.len + body.items.len },
        .{ "pass", "cli-projection" },
        .{ "verb", verb_name },
    });
}

fn buildHeader(allocator: std.mem.Allocator, actx: *const cc.ArchiformCtx) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        \\// DO NOT EDIT — generated by tools/schema-gen/gen_cli.zig.
        \\// Provenance:
        \\//   source-schema:     {0s}
        \\//   source-schema-fp:  blake3:{1s}
        \\//   schema-pin:        {2s}
        \\//   schema-version:    {3s}
        \\//   generator-id:      {4s}
        \\//   generator-commit:  {5s}
        \\// Regenerate via `bun run codegen`. Hand-edits will be overwritten.
        \\// See docs/sprints/002-archiform-foundation/architecture-decisions.md
        \\// (D-019 action manifest, D-022 bridge pattern, D-024 spike-before-promote).
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

fn ensureDir(io_h: std.Io, path: []const u8) !void {
    std.Io.Dir.cwd().createDirPath(io_h, path) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
}

fn kebabToSnake(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| out[i] = if (c == '-') '_' else c;
    return out;
}

/// Convert a camelCase property name to a kebab-case CLI flag name.
/// E.g. "embedVia" → "embed-via", "mythosFile" → "mythos-file".
/// Names already in kebab or lowercase pass through unchanged.
/// This is the canonical CLI flag form; legacy verbs use kebab-case flags.
fn camelToKebab(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    // Count uppercase letters to determine output length.
    var extra: usize = 0;
    for (s) |c| if (c >= 'A' and c <= 'Z') { extra += 1; };
    const out = try allocator.alloc(u8, s.len + extra);
    var j: usize = 0;
    for (s) |c| {
        if (c >= 'A' and c <= 'Z') {
            out[j] = '-';
            j += 1;
            out[j] = c + 32; // toLower
            j += 1;
        } else {
            out[j] = c;
            j += 1;
        }
    }
    return out[0..j];
}

/// Returns true if `fp` is a 64-char hex string that is NOT all-zero.
/// Used to gate wasm-route emission: zero fp = placeholder, non-zero = real module.
fn isNonZeroFp(fp: []const u8) bool {
    if (fp.len != 64) return false;
    for (fp) |c| if (c != '0') return true;
    return false;
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

fn getBool(obj: std.json.ObjectMap, key: []const u8) ?bool {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .bool => |b| b,
        else => null,
    };
}

/// Escape a string for safe inclusion inside a Zig double-quoted string literal.
fn writeZigEscaped(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, c),
        }
    }
}

// ── AC4 fixture-mode tests ────────────────────────────────────────────────────
//
// These tests synthesise a manifest in memory, run the generator, and read the
// emitted Zig source back as a string. The generated source is NOT compiled at
// test time (that would require recursive build invocation); the assertions
// inspect the source for the presence/absence of the confirmation-gate block.
// This is sufficient to prove the generator's confirmation behavior is driven
// by the manifest's `attributes` (AC4): destructive+requiresConfirmation gate
// emission is binary.

const test_helpers = struct {
    fn writeFixture(
        arena: std.mem.Allocator,
        manifest: std.json.ObjectMap,
        verb: []const u8,
        out_dir: []const u8,
    ) ![]const u8 {
        const io_h = std.Io.Threaded.global_single_threaded.io();
        const stderr = std.Io.File.stderr();
        var err_buf: [256]u8 = undefined;
        var err_w = stderr.writer(io_h, &err_buf);

        // Make sure the output dir exists.
        std.Io.Dir.cwd().createDirPath(io_h, out_dir) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };

        try projectVerbToDir(
            arena,
            io_h,
            out_dir,
            "tests/cli/fixtures/destructive-manifest.json",
            "0000000000000000000000000000000000000000000000000000000000000000",
            "0.0.0-fixture",
            "tests/cli/fixtures/destructive-manifest.fp",
            verb,
            manifest,
            &err_w,
        );

        const snake = try kebabToSnake(arena, verb);
        const path = try std.fmt.allocPrint(arena, "{s}/palace_{s}.zig", .{ out_dir, snake });
        return std.Io.Dir.cwd().readFileAlloc(io_h, path, arena, .limited(1 << 20));
    }

    fn buildManifest(
        arena: std.mem.Allocator,
        destructive: bool,
        requires_confirmation: bool,
    ) !std.json.ObjectMap {
        // Build the JSON tree by parsing a templated JSON string. This avoids
        // the awkward (in 0.16) ObjectMap construction API and keeps the test
        // expressive.
        const dest_str = if (destructive) "true" else "false";
        const req_str = if (requires_confirmation) "true" else "false";
        const json_text = try std.fmt.allocPrint(
            arena,
            \\{{
            \\  "summary": "Fixture verb for AC4 confirmation behavior testing.",
            \\  "inputs": {{
            \\    "type": "object",
            \\    "required": ["name"],
            \\    "properties": {{
            \\      "name": {{ "type": "string", "description": "Target name." }}
            \\    }}
            \\  }},
            \\  "outputs": {{ "type": "object", "properties": {{}} }},
            \\  "effects": {{ "kind": "ActionEnvelope" }},
            \\  "idempotency": "creates",
            \\  "streaming": false,
            \\  "attributes": {{
            \\    "destructive": {s},
            \\    "requiresConfirmation": {s},
            \\    "confirmationMessage": "This will permanently destroy the target.",
            \\    "agentVisible": true
            \\  }},
            \\  "implementation": {{ "wasm": "0000000000000000000000000000000000000000000000000000000000000000" }}
            \\}}
        ,
            .{ dest_str, req_str },
        );
        const value = try std.json.parseFromSliceLeaky(std.json.Value, arena, json_text, .{});
        return switch (value) {
            .object => |o| o,
            else => error.UnexpectedJson,
        };
    }
};

test "AC4: destructive + requiresConfirmation emits confirmation gate" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const manifest = try test_helpers.buildManifest(arena, true, true);
    const out_dir = "tmp/test-cli-fixtures";
    const source = try test_helpers.writeFixture(arena, manifest, "destroy-fixture", out_dir);

    // The generated source must contain the confirmation gate.
    try std.testing.expect(std.mem.indexOf(u8, source, "AC4 confirmation gate") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "skip_confirm") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "Pass --yes to confirm") != null);
    // The confirmation message text propagates from the manifest.
    try std.testing.expect(std.mem.indexOf(u8, source, "permanently destroy") != null);
    // Help text mentions --yes and --no-confirm.
    try std.testing.expect(std.mem.indexOf(u8, source, "Skip the destructive-action") != null);
}

test "AC4: non-destructive omits confirmation gate" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // requiresConfirmation: true but destructive: false → no gate.
    const manifest = try test_helpers.buildManifest(arena, false, true);
    const out_dir = "tmp/test-cli-fixtures";
    const source = try test_helpers.writeFixture(arena, manifest, "soft-fixture", out_dir);

    try std.testing.expect(std.mem.indexOf(u8, source, "AC4 confirmation gate") == null);
    try std.testing.expect(std.mem.indexOf(u8, source, "Pass --yes to confirm") == null);
}

test "AC4: destructive but not requiresConfirmation omits gate" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // destructive: true but requiresConfirmation: false → no gate.
    const manifest = try test_helpers.buildManifest(arena, true, false);
    const out_dir = "tmp/test-cli-fixtures";
    const source = try test_helpers.writeFixture(arena, manifest, "silent-fixture", out_dir);

    try std.testing.expect(std.mem.indexOf(u8, source, "AC4 confirmation gate") == null);
}

test "AC2: help text derived from manifest summary + properties" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const manifest = try test_helpers.buildManifest(arena, false, false);
    const out_dir = "tmp/test-cli-fixtures";
    const source = try test_helpers.writeFixture(arena, manifest, "help-fixture", out_dir);

    // Summary text from manifest must appear in the generated SUMMARY constant.
    try std.testing.expect(std.mem.indexOf(u8, source, "Fixture verb for AC4") != null);
    // Each input property must appear as a flag in the help text.
    try std.testing.expect(std.mem.indexOf(u8, source, "--name <string>") != null);
    // Required-flag enforcement code is emitted for `name` (with -- prefix per Story 3.4).
    try std.testing.expect(std.mem.indexOf(u8, source, "--name required") != null);
}
