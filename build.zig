const std = @import("std");

pub fn build(b: *std.Build) void {
    // Default to Zig's bundled musl libc on Linux (native arch); macOS
    // stays native. Override with `-Dtarget=native`. Rationale + toolchain
    // history in docs/decisions/2026-05-24-hermetic-musl-default-linux.md.
    const builtin = @import("builtin");
    const default_target: std.Target.Query = if (builtin.os.tag == .linux)
        .{ .cpu_arch = builtin.target.cpu.arch, .os_tag = .linux, .abi = .musl }
    else
        .{};
    const target = b.standardTargetOptions(.{ .default_target = default_target });
    const optimize = b.standardOptimizeOption(.{});

    // Build options. ML-DSA-87 VERIFY is linked into the WASM module by
    // default — the DreamBall protocol is hybrid-signed and every node the
    // browser might receive carries a PQ signature that deserves local
    // verification. The spike (docs/known-gaps.md §1) measured the delta
    // at +28.7 KB raw / +9.9 KB gzipped, well inside the 200 KB budget.
    // Pass `-Dpq-wasm=false` only for the Ed25519-only build used to size
    // regressions against the spike baseline.
    const pq_wasm = b.option(
        bool,
        "pq-wasm",
        "Link ML-DSA-87 verify into jelly.wasm. Default: true.",
    ) orelse true;

    const build_opts = b.addOptions();
    build_opts.addOption(bool, "pq_wasm", pq_wasm);

    const zbor_dep = b.dependency("zbor", .{
        .target = target,
        .optimize = optimize,
    });
    const zbor_mod = zbor_dep.module("zbor");

    const mod = b.addModule("dreamball", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("zbor", zbor_mod);
    mod.addImport("build_options", build_opts.createModule());

    // liboqs ML-DSA-87 reference implementation, vendored under vendor/liboqs.
    // See vendor/liboqs/VENDOR.md for pin + scope. The .c sources compile into
    // the dreamball module, so any artifact using this module (native library,
    // CLI, or unit tests) automatically links the post-quantum signer. The
    // wasm32-freestanding target uses a separate module (wasm_mod) which does
    // not pull these in — see src/ml_dsa.zig for the `enabled` gate.
    mod.link_libc = true;
    const liboqs_vendor = b.path("vendor/liboqs");
    mod.addIncludePath(liboqs_vendor.path(b, "include"));
    mod.addIncludePath(liboqs_vendor.path(b, "src/common/pqclean_shims"));
    mod.addIncludePath(liboqs_vendor.path(b, "src/common/sha3"));
    mod.addIncludePath(liboqs_vendor.path(b, "src/common/sha3/xkcp_low/KeccakP-1600/plain-64bits"));
    mod.addIncludePath(liboqs_vendor.path(b, "src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref"));
    mod.addCSourceFiles(.{
        .files = &.{
            // ML-DSA-87 reference implementation (pqcrystals-dilithium).
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/ntt.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/packing.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/poly.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/polyvec.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/reduce.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/rounding.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/sign.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/symmetric-shake.c",
            // XKCP SHAKE frontend + portable 64-bit Keccak backend.
            "vendor/liboqs/src/common/sha3/sha3.c",
            "vendor/liboqs/src/common/sha3/xkcp_sha3.c",
            "vendor/liboqs/src/common/sha3/xkcp_low/KeccakP-1600/plain-64bits/KeccakP-1600-opt64.c",
            // OQS_randombytes + OQS_MEM_aligned_{alloc,free} backed by libc.
            "vendor/liboqs/src/dreamball_stubs.c",
        },
        .flags = &.{
            "-DDILITHIUM_MODE=5", // selects ML-DSA-87 via config.h
            "-std=c11",
            // liboqs's upstream sources are clean but compile with a handful
            // of warnings under strict flags; silence the noisy categories
            // rather than patching vendored code.
            "-Wno-unused-parameter",
            "-Wno-unused-but-set-variable",
            "-Wno-sign-compare",
        },
    });

    // src/recrypt-identity-fixtures is a symlink → vendor/recrypt-identity-fixtures.
    // @embedFile resolves relative to the source file, so no addEmbedPath needed.

    const lib = b.addLibrary(.{
        .name = "dreamball",
        .root_module = mod,
    });
    b.installArtifact(lib);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("dreamball", mod);
    exe_mod.addImport("zbor", zbor_mod);

    const exe = b.addExecutable(.{
        .name = "jelly",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the jelly CLI");
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_unit_tests.step);

    const smoke_cmd = b.addSystemCommand(&.{"scripts/cli-smoke.sh"});
    smoke_cmd.step.dependOn(b.getInstallStep());
    const smoke_step = b.step("smoke", "Run end-to-end CLI smoke test");
    smoke_step.dependOn(&smoke_cmd.step);

    // schema-gen — D-030 Option A JSON-Schema-canonical orchestrator.
    // Dispatches to the per-target generators (gen_zig, gen_ts,
    // gen_valibot, gen_cbor, gen_cypher) under `tools/schema-gen/`.
    // Legacy static-text generator deleted in Story 1.5 (cutover).
    const schemagen_mod = b.createModule(.{
        .root_source_file = b.path("tools/schema-gen/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const schemagen_exe = b.addExecutable(.{
        .name = "schema-gen",
        .root_module = schemagen_mod,
    });
    const schemagen_run = b.addRunArtifact(schemagen_exe);
    const schemagen_step = b.step("schemagen", "Regenerate src/lib/generated/*.ts + src/memory-palace/schema.cypher");
    schemagen_step.dependOn(&schemagen_run.step);

    // Story 3.2 — gen_cli unit tests (AC4 confirmation-fixture coverage).
    // Tests live inline in tools/schema-gen/gen_cli.zig under the
    // `test "AC4: …"` blocks. Wired here so `zig build test` exercises them.
    const gen_cli_test_mod = b.createModule(.{
        .root_source_file = b.path("tools/schema-gen/gen_cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    const gen_cli_tests = b.addTest(.{
        .root_module = gen_cli_test_mod,
    });
    const run_gen_cli_tests = b.addRunArtifact(gen_cli_tests);
    const gen_cli_test_step = b.step(
        "gen-cli-test",
        "Run the Story 3.2 gen_cli AC4 confirmation-fixture tests",
    );
    gen_cli_test_step.dependOn(&run_gen_cli_tests.step);
    test_step.dependOn(&run_gen_cli_tests.step);

    // schemagen-spike — Story 1.1 codegen-inversion spike.
    // Reads tools/schema-gen/spike/schemas/*.json and emits byte-equivalent
    // fixtures under tools/schema-gen/spike/out/. The byte-equivalence diff
    // against tools/schema-gen/legacy-spike-fixture/ is AC2 of the story.
    // See docs/decisions/2026-04-28-codegen-spike-findings.md for AC3 gaps.
    const schemagen_spike_mod = b.createModule(.{
        .root_source_file = b.path("tools/schema-gen/spike/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const schemagen_spike_exe = b.addExecutable(.{
        .name = "schema-gen-spike",
        .root_module = schemagen_spike_mod,
    });
    const schemagen_spike_run = b.addRunArtifact(schemagen_spike_exe);
    const schemagen_spike_step = b.step(
        "schemagen-spike",
        "Run the Story 1.1 JSON-Schema-consumer spike (writes tools/schema-gen/spike/out/)",
    );
    schemagen_spike_step.dependOn(&schemagen_spike_run.step);

    // Story 1.1 AC1 round-trip tests over the spike consumer.
    const schemagen_spike_tests = b.addTest(.{
        .root_module = schemagen_spike_mod,
    });
    const run_schemagen_spike_tests = b.addRunArtifact(schemagen_spike_tests);
    const schemagen_spike_test_step = b.step(
        "schemagen-spike-test",
        "Run the Story 1.1 spike's AC1 round-trip tests",
    );
    schemagen_spike_test_step.dependOn(&run_schemagen_spike_tests.step);

    // export-envelope-fixtures — write fixtures/envelope_golden/<type>.cbor for
    // Vitest round-trip parity tests (Story 1.5 / AC2).
    const envelope_fixture_mod = b.createModule(.{
        .root_source_file = b.path("tools/export-envelope-fixtures/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // The tool accesses all encoders via the dreamball module (root.zig re-exports
    // protocol_v2, protocol, envelope_v2 as pub fields).
    envelope_fixture_mod.addImport("dreamball", mod);
    const envelope_fixture_exe = b.addExecutable(.{
        .name = "export-envelope-fixtures",
        .root_module = envelope_fixture_mod,
    });
    const envelope_fixture_run = b.addRunArtifact(envelope_fixture_exe);
    const envelope_fixture_step = b.step("export-envelope-fixtures", "Write fixtures/envelope_golden/*.cbor for Vitest round-trip tests");
    envelope_fixture_step.dependOn(&envelope_fixture_run.step);

    // export-mldsa-fixture — deterministic KAT vector for WASM verify tests.
    // Uses a seeded PRNG (tools/export-mldsa-fixture/deterministic_rand.c)
    // so the same fixtures/ml_dsa_87_golden.json bytes are produced on
    // every run, making the fixture safe to commit and pin in Vitest.
    const fixture_mod = b.createModule(.{
        .root_source_file = b.path("tools/export-mldsa-fixture/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Link the same liboqs C sources as the main module, but replace
    // dreamball_stubs.c with the deterministic_rand.c seeded variant.
    fixture_mod.link_libc = true;
    fixture_mod.addIncludePath(liboqs_vendor.path(b, "include"));
    fixture_mod.addIncludePath(liboqs_vendor.path(b, "src/common/pqclean_shims"));
    fixture_mod.addIncludePath(liboqs_vendor.path(b, "src/common/sha3"));
    fixture_mod.addIncludePath(liboqs_vendor.path(b, "src/common/sha3/xkcp_low/KeccakP-1600/plain-64bits"));
    fixture_mod.addIncludePath(liboqs_vendor.path(b, "src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref"));
    fixture_mod.addCSourceFiles(.{
        .files = &.{
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/ntt.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/packing.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/poly.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/polyvec.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/reduce.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/rounding.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/sign.c",
            "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/symmetric-shake.c",
            "vendor/liboqs/src/common/sha3/sha3.c",
            "vendor/liboqs/src/common/sha3/xkcp_sha3.c",
            "vendor/liboqs/src/common/sha3/xkcp_low/KeccakP-1600/plain-64bits/KeccakP-1600-opt64.c",
            // Deterministic seeded PRNG — replaces dreamball_stubs.c for fixture gen.
            "tools/export-mldsa-fixture/deterministic_rand.c",
        },
        .flags = &.{
            "-DDILITHIUM_MODE=5",
            "-std=c11",
            "-Wno-unused-parameter",
            "-Wno-unused-but-set-variable",
            "-Wno-sign-compare",
        },
    });
    const fixture_exe = b.addExecutable(.{
        .name = "export-mldsa-fixture",
        .root_module = fixture_mod,
    });
    const fixture_run = b.addRunArtifact(fixture_exe);
    const fixture_step = b.step("export-mldsa-fixture", "Write fixtures/ml_dsa_87_golden.json (deterministic KAT vector)");
    fixture_step.dependOn(&fixture_run.step);

    // jelly-wasm — WASM build of the parser for browser consumption.
    // Separate module because freestanding-wasm drops std.Io / std.crypto.random,
    // so we skip linking signer.zig / io.zig. See tools/jelly-wasm/main.zig.
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    // zbor is compiled for the wasm32-freestanding target for this module.
    // zbor pulls no libc / syscalls — it's pure data manipulation — so the
    // freestanding target handles it cleanly.
    const zbor_wasm_dep = b.dependency("zbor", .{
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    const zbor_wasm_mod = zbor_wasm_dep.module("zbor");

    const wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/wasm_main.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    wasm_mod.addImport("build_options", build_opts.createModule());
    wasm_mod.addImport("zbor", zbor_wasm_mod);

    // Optional PQ verify: link the vendored liboqs subset into the WASM
    // module. The linker's dead-code elimination (ReleaseSmall + wasm-ld)
    // drops the sign/keypair paths when only verify is exported.
    if (pq_wasm) {
        wasm_mod.link_libc = false;
        // Shim directory goes FIRST so our stub <string.h>/<stdlib.h>/<stdio.h>/<limits.h>
        // resolve ahead of anything the toolchain might surface. Freestanding-wasm
        // has no libc, and we only need declarations the compiler-rt side
        // already provides (memcpy/memset) or that live in never-expanded macros.
        wasm_mod.addIncludePath(liboqs_vendor.path(b, "wasm_shims"));
        wasm_mod.addIncludePath(liboqs_vendor.path(b, "include"));
        wasm_mod.addIncludePath(liboqs_vendor.path(b, "src/common/pqclean_shims"));
        wasm_mod.addIncludePath(liboqs_vendor.path(b, "src/common/sha3"));
        wasm_mod.addIncludePath(liboqs_vendor.path(b, "src/common/sha3/xkcp_low/KeccakP-1600/plain-64bits"));
        wasm_mod.addIncludePath(liboqs_vendor.path(b, "src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref"));
        wasm_mod.addCSourceFiles(.{
            .files = &.{
                "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/ntt.c",
                "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/packing.c",
                "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/poly.c",
                "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/polyvec.c",
                "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/reduce.c",
                "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/rounding.c",
                "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/sign.c",
                "vendor/liboqs/src/sig/ml_dsa/pqcrystals-dilithium-standard_ml-dsa-87_ref/symmetric-shake.c",
                "vendor/liboqs/src/common/sha3/sha3.c",
                "vendor/liboqs/src/common/sha3/xkcp_sha3.c",
                "vendor/liboqs/src/common/sha3/xkcp_low/KeccakP-1600/plain-64bits/KeccakP-1600-opt64.c",
                "vendor/liboqs/src/dreamball_stubs_wasm.c",
            },
            .flags = &.{
                "-DDILITHIUM_MODE=5",
                "-std=c11",
                "-Wno-unused-parameter",
                "-Wno-unused-but-set-variable",
                "-Wno-sign-compare",
                // No stdlib on freestanding — liboqs sources don't need any
                // beyond memcpy/memset, both of which Zig's compiler-rt
                // provides automatically.
                "-ffreestanding",
            },
        });
    }

    const wasm_exe = b.addExecutable(.{
        .name = "jelly",
        .root_module = wasm_mod,
    });
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;
    // Install the produced jelly.wasm into src/lib/wasm/ so the Svelte lib
    // can import it via Vite's asset pipeline.
    const wasm_install = b.addInstallArtifact(wasm_exe, .{
        .dest_dir = .{ .override = .{ .custom = "../src/lib/wasm" } },
    });
    const wasm_step = b.step("wasm", "Build jelly.wasm for the Svelte lib");
    wasm_step.dependOn(&wasm_install.step);

    // ----------------------------------------------------------------
    // Story 5.1 spike: minimal Zig wasm host for Cluster E.
    // See docs/decisions/2026-04-28-wasm-runtime-selection.md.
    //
    // The spike runs natively on the host machine (darwin/linux); it
    // builds the hand-authored hello.wasm + hello-bad.wasm bytes
    // in-process and exercises the in-tree Zig wasm runtime. No
    // wasm32 target is involved on the host side.
    // ----------------------------------------------------------------
    const wasm_spike_mod = b.createModule(.{
        .root_source_file = b.path("src/wasm-host/spike/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const wasm_spike_exe = b.addExecutable(.{
        .name = "wasm-spike-host",
        .root_module = wasm_spike_mod,
    });
    b.installArtifact(wasm_spike_exe);
    const wasm_spike_run = b.addRunArtifact(wasm_spike_exe);
    const wasm_spike_step = b.step(
        "wasm-spike-host",
        "Run Story 5.1 wasm host spike: load hello.wasm, broker WASI, reject hello-bad.wasm",
    );
    wasm_spike_step.dependOn(&wasm_spike_run.step);

    // ----------------------------------------------------------------
    // Story 5.2 production wasm host. Promotes the Story 5.1 spike to
    // a host that exposes the 5 sprint-002-locked `dreamball.*`
    // imports (D-033). See
    // `docs/sprints/002-archiform-foundation/stories/5.2-dreamball-imports-implementation.md`.
    //
    // `zig build wasm-host` runs the production driver which:
    //   - exercises the AC1 + AC4 happy-path (guest calls
    //     dreamball.emit_action_envelope; host signs with Ed25519);
    //   - emits the NFR11 / AC7 structured-log JSON event on stderr;
    //   - measures AC6 / NFR3 latency (100 iterations, p95 ≤ 50 ms).
    //
    // `zig build wasm-host-test` runs the per-import unit tests.
    // ----------------------------------------------------------------
    const sign_action_mod = b.createModule(.{
        .root_source_file = b.path("src/sign_action.zig"),
        .target = target,
        .optimize = optimize,
    });

    const wasm_host_mod = b.createModule(.{
        .root_source_file = b.path("src/wasm-host/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    wasm_host_mod.addImport("sign_action", sign_action_mod);
    const wasm_host_exe = b.addExecutable(.{
        .name = "wasm-host",
        .root_module = wasm_host_mod,
    });
    b.installArtifact(wasm_host_exe);
    const wasm_host_run = b.addRunArtifact(wasm_host_exe);
    const wasm_host_step = b.step(
        "wasm-host",
        "Run Story 5.2 production wasm host: 5 dreamball.* imports + AC4 + AC6 perf",
    );
    wasm_host_step.dependOn(&wasm_host_run.step);

    // Per-import tests live in `src/wasm-host/imports_test.zig`. We
    // wire them as a dedicated test step so `zig build test` and
    // `zig build wasm-host-test` both run them; AC2 requires fresh
    // output for each gate.
    const wasm_host_test_mod = b.createModule(.{
        .root_source_file = b.path("src/wasm-host/imports_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    wasm_host_test_mod.addImport("sign_action", sign_action_mod);
    const wasm_host_tests = b.addTest(.{
        .root_module = wasm_host_test_mod,
    });
    const run_wasm_host_tests = b.addRunArtifact(wasm_host_tests);
    const wasm_host_test_step = b.step(
        "wasm-host-test",
        "Run Story 5.2 per-import tests (5 dreamball.* imports + AC8 grep audit assertion)",
    );
    wasm_host_test_step.dependOn(&run_wasm_host_tests.step);

    // Aggregate tests step: zig build test runs sign_action's KAT and
    // the wasm-host per-import suite alongside the existing module tests.
    const sign_action_tests = b.addTest(.{
        .root_module = sign_action_mod,
    });
    const run_sign_action_tests = b.addRunArtifact(sign_action_tests);
    test_step.dependOn(&run_sign_action_tests.step);
    test_step.dependOn(&run_wasm_host_tests.step);

    // AC8 grep audit step. Fails if any name beyond the 5 locked
    // imports surfaces in `src/wasm-host/`. The regex matches D-033's
    // scope-lock; the grep's exit code is the gate (zero hits = exit 1
    // for `grep -E`, which we invert into success).
    const wasm_host_audit = b.addSystemCommand(&.{
        "sh",
        "-c",
        // grep returns 1 when there are no matches — that's the success
        // case for AC8. We swap with `! grep` so the build step
        // succeeds iff no rogue dreamball.* names exist.
        "! grep -E -rn '(^|[^a-zA-Z0-9_])dreamball\\.(?!fp\\b|encode_cbor\\b|read_node\\b|emit_action_envelope\\b|now_ms\\b)[a-zA-Z_][a-zA-Z0-9_]*' src/wasm-host/ --include='*.zig'",
    });
    const wasm_host_audit_step = b.step(
        "wasm-host-audit",
        "Story 5.2 AC8: grep audit — surface locked to exactly 5 dreamball.* imports",
    );
    wasm_host_audit_step.dependOn(&wasm_host_audit.step);
    test_step.dependOn(&wasm_host_audit.step);

    // ----------------------------------------------------------------
    // Story 5.3: Wasm Host Failure Paths
    //   - failure_paths.zig: verifyBlake3, verifyImports, checkMemoryLimit
    //   - failure_paths_test.zig: Zig-level unit tests for AC1/AC2/AC3/AC4/AC5
    //   - failure_test_main.zig: standalone binary whose JSON output is
    //     consumed by the AC8 TypeScript fixture tests
    // ----------------------------------------------------------------

    // Story 5.3 failure-path Zig unit tests.
    const wasm_host_failure_test_mod = b.createModule(.{
        .root_source_file = b.path("src/wasm-host/failure_paths_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    wasm_host_failure_test_mod.addImport("sign_action", sign_action_mod);
    const wasm_host_failure_tests = b.addTest(.{
        .root_module = wasm_host_failure_test_mod,
    });
    const run_wasm_host_failure_tests = b.addRunArtifact(wasm_host_failure_tests);
    const wasm_host_failure_test_step = b.step(
        "wasm-host-failure-test-zig",
        "Story 5.3: Zig-level failure-path unit tests (AC1/AC2/AC3/AC4/AC5)",
    );
    wasm_host_failure_test_step.dependOn(&run_wasm_host_failure_tests.step);
    test_step.dependOn(&run_wasm_host_failure_tests.step);

    // Story 5.3 AC6: grep audit — failure helpers live in src/wasm-host/.
    const failure_helpers_audit = b.addSystemCommand(&.{
        "sh",
        "-c",
        // Confirm verifyBlake3, verifyImports, checkMemoryLimit all exist in
        // src/wasm-host/ (not per-platform files). Per D-032 / AC6.
        "grep -RE 'verifyBlake3|verifyImports|checkMemoryLimit' src/wasm-host/ --include='*.zig' > /dev/null",
    });
    const failure_helpers_audit_step = b.step(
        "wasm-host-failure-audit",
        "Story 5.3 AC6: grep audit — failure helpers in shared src/wasm-host/",
    );
    failure_helpers_audit_step.dependOn(&failure_helpers_audit.step);
    test_step.dependOn(&failure_helpers_audit.step);

    // Story 5.3 AC8: standalone binary for TypeScript fixture tests.
    // The binary exercises all three failure scenarios and emits JSON.
    const wasm_host_failure_main_mod = b.createModule(.{
        .root_source_file = b.path("src/wasm-host/failure_test_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    wasm_host_failure_main_mod.addImport("sign_action", sign_action_mod);
    const wasm_host_failure_exe = b.addExecutable(.{
        .name = "wasm-host-failure-test",
        .root_module = wasm_host_failure_main_mod,
    });
    b.installArtifact(wasm_host_failure_exe);
    const wasm_host_failure_run = b.addRunArtifact(wasm_host_failure_exe);
    const wasm_host_failure_step = b.step(
        "wasm-host-failure-test",
        "Story 5.3 AC8: run failure-path test binary (fp-mismatch + import-violation + oom)",
    );
    wasm_host_failure_step.dependOn(&wasm_host_failure_run.step);

    // ----------------------------------------------------------------
    // Story 5.4 — production `mint.wasm` action module.
    //
    // Compiles `actions/mint/main.zig` to `actions/mint/mint.wasm`
    // (wasm32-freestanding, ReleaseSmall). The blake3 of the produced
    // module is recorded in `schemas/memory-palace-0.1.0.json`
    // `x-actions.mint.implementation.wasm` and pinned via
    // `bun run schemas:pin`. Per D-024 spike-before-promote: this is
    // the FIRST production wasm action; its end-to-end execution against
    // the wasm host (`zig build mint-wasm-host`) is the integration
    // acceptance for Cluster E.
    //
    // Import surface (AC7): only `dreamball.*`. No `env.*`, no
    // `wasi_snapshot_preview1.*`. The import-violation check in
    // `src/wasm-host/failure_paths.zig` enforces this at host-load time.
    //
    // Story 5.5 ships an analogous mint-malicious.wasm (AC8); see
    // `tests/wasm/mint-malicious/`.
    // ----------------------------------------------------------------
    const mint_wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const mint_wasm_mod = b.createModule(.{
        .root_source_file = b.path("actions/mint/main.zig"),
        .target = mint_wasm_target,
        .optimize = .ReleaseSmall,
    });
    const mint_wasm_exe = b.addExecutable(.{
        .name = "mint",
        .root_module = mint_wasm_mod,
    });
    mint_wasm_exe.entry = .disabled;
    mint_wasm_exe.rdynamic = true;
    // Install the produced mint.wasm next to its source so the schema's
    // `implementation.wasm` fp pin and CLI loader can find it at a fixed
    // path under repo root.
    const mint_wasm_install = b.addInstallArtifact(mint_wasm_exe, .{
        .dest_dir = .{ .override = .{ .custom = "../actions/mint" } },
    });
    const mint_wasm_step = b.step(
        "mint-wasm",
        "Story 5.4 — build actions/mint/mint.wasm (production wasm action module)",
    );
    mint_wasm_step.dependOn(&mint_wasm_install.step);

    // Companion: mint-malicious.wasm — AC8 negative fixture proving
    // SEC2 (the guest cannot forge signatures). The malicious guest
    // attempts to compose its own signature bytes; the host-produced
    // envelope (after the host signs) STILL verifies against the
    // host's pubkey, but if we feed the guest-composed bytes into
    // `verifyEd25519`, it does not verify. The Zig fixture test in
    // `src/wasm-host/failure_paths_test.zig` (or a sibling) exercises
    // this. We build it here so the wasm artefact is present.
    const mint_mal_mod = b.createModule(.{
        .root_source_file = b.path("tests/wasm/mint-malicious/main.zig"),
        .target = mint_wasm_target,
        .optimize = .ReleaseSmall,
    });
    const mint_mal_exe = b.addExecutable(.{
        .name = "mint-malicious",
        .root_module = mint_mal_mod,
    });
    mint_mal_exe.entry = .disabled;
    mint_mal_exe.rdynamic = true;
    const mint_mal_install = b.addInstallArtifact(mint_mal_exe, .{
        .dest_dir = .{ .override = .{ .custom = "../tests/wasm/mint-malicious" } },
    });
    const mint_mal_step = b.step(
        "mint-malicious-wasm",
        "Story 5.4 AC8 — build tests/wasm/mint-malicious/mint-malicious.wasm",
    );
    mint_mal_step.dependOn(&mint_mal_install.step);

    // mint-wasm-host driver (AC2 + AC3 + AC6) — load actions/mint/mint.wasm
    // via the production wasm host, run end-to-end, emit the structured
    // verify-before-instantiate event {phase: "verify", status: "match",
    // module_fp} BEFORE instantiation, and print `{ "palaceFp": "..." }`
    // JSON to stdout on success. This is what `jelly palace mint --use-wasm`
    // (and the AC6 smoke gate) shells out to.
    const mint_host_mod = b.createModule(.{
        .root_source_file = b.path("src/wasm-host/mint_host_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    mint_host_mod.addImport("sign_action", sign_action_mod);
    const mint_host_exe = b.addExecutable(.{
        .name = "mint-wasm-host",
        .root_module = mint_host_mod,
    });
    b.installArtifact(mint_host_exe);
    const mint_host_run = b.addRunArtifact(mint_host_exe);
    // mint-wasm-host depends on the wasm artefact existing.
    mint_host_run.step.dependOn(&mint_wasm_install.step);
    const mint_host_step = b.step(
        "mint-wasm-host",
        "Story 5.4 AC2/AC3/AC6 — run actions/mint/mint.wasm through the wasm host end-to-end",
    );
    mint_host_step.dependOn(&mint_host_run.step);
}
