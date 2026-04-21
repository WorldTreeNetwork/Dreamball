const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
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

    // schema-gen — Zig tool that emits src/lib/generated/*.ts
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
    const schemagen_step = b.step("schemagen", "Regenerate src/lib/generated/*.ts");
    schemagen_step.dependOn(&schemagen_run.step);

    // jelly-wasm — WASM build of the parser for browser consumption.
    // Separate module because freestanding-wasm drops std.Io / std.crypto.random,
    // so we skip linking signer.zig / io.zig. See tools/jelly-wasm/main.zig.
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/wasm_main.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    wasm_mod.addImport("build_options", build_opts.createModule());

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
}
