const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
