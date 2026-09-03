# 2026-05-24 — Default Linux build target to Zig-bundled musl

Sprint: post-002 follow-up · Significance: MEDIUM · Beads: Dreamball-3a1
· Related: PR #1 (`fix: show/export-json/grow surface mutable
DreamBall attributes`, merged at 7c119f0); Dreamball-a05 (sigaction
musl-portability prerequisite)

## Context

CLAUDE.md describes the project's compilation stack as "Zig 0.16.0 +
Bun" and the build command as `mise exec zig@0.16.0 -- zig build`.
Until 2026-05, on Linux hosts this resolved to the native triple
(typically `x86_64-linux-gnu`), which means linking against the
system glibc + the system GCC's `crt1.o` startup object.

In late 2025 / early 2026, GCC 16 (the version shipping on Arch and
other rolling distros) started emitting **SFrame** `.sframe` unwind
sections in `crt1.o` more aggressively, using `R_X86_64_PC64`
relocations. Zig 0.16's LLD does not recognise that relocation kind
yet; the fix is in Zig master but not in the 0.16 stable line.

Concrete failure mode observed on a fleet build container during the
PR #1 verification pass:

```
error: fatal linker error: unhandled relocation type R_X86_64_PC64 at offset 0x1c
    note: in /usr/lib/gcc/x86_64-pc-linux-gnu/16.1.1/../../../../lib/crt1.o:.sframe
error: fatal linker error: unhandled relocation type R_X86_64_PC64 at offset 0x2c
    note: in /usr/lib/gcc/x86_64-pc-linux-gnu/16.1.1/../../../../lib/crt1.o:.sframe
```

The user's own machine has older GCC and was unaffected, but any CI
container, recent contributor laptop, or new fleet box that picks up
GCC 16 stops being able to link. Worse, this is a silent toolchain
gradient: builds work today and break tomorrow with no source change.

## Decision

**Make Zig's bundled musl libc the default build target on Linux.**

`build.zig` synthesises a `default_target` based on the host OS, with
`cpu_arch` taken from the host's `builtin.target` so aarch64 Linux
contributors get a native-arch musl binary rather than an x86_64
cross-compile:

```zig
const builtin = @import("builtin");
const default_target: std.Target.Query = if (builtin.os.tag == .linux)
    .{ .cpu_arch = builtin.target.cpu.arch, .os_tag = .linux, .abi = .musl }
else
    .{};
const target = b.standardTargetOptions(.{ .default_target = default_target });
```

Effects:

- `mise exec zig@0.16.0 -- zig build` on Linux compiles against Zig's
  bundled musl headers + startup code, producing a statically-linked
  `jelly` binary with **zero** system libc / crt dependency.
- The same command on macOS continues to resolve native (no behaviour
  change for Darwin contributors).
- `-Dtarget=native` (or any explicit `-Dtarget=...`) overrides the
  default — the opt-out is a single CLI flag for contributors who
  need glibc linkage for some specific reason (e.g. dynamic linking
  against a system shared library; not a thing today, but kept open).

## Why this is the right call

1. **Eliminates the toolchain-version blast radius.** GCC ABI churn,
   new relocation kinds, libc version skew across distros — none of
   it touches the build any more. The build only depends on Zig and
   bun, which the project already pins via `mise`. "Just zig and bun"
   becomes literally true.

2. **Hermetic by default.** A binary built on one Linux box runs on
   any Linux box of the same arch, with no glibc version anxiety.
   This is especially valuable for ad-hoc releases, demos, and CI
   artifact reuse.

3. **The cost is tiny for our shape of binary.** `jelly` is a CLI
   tool. Static musl adds ~150–250 KB to the on-disk size relative to
   glibc-dynamic. Per-call performance delta vs glibc is in the
   single-digit percent range on a few hot paths (allocator, regex),
   neither of which `jelly` is bottlenecked on. The protocol's
   throughput is dominated by ML-DSA-87 verify, which executes the
   same C in both libc environments.

4. **Aligns with the cross-runtime invariant.** `jelly.wasm` already
   runs against `wasm32-freestanding` (no system libc — see
   `docs/ARCHITECTURE.md` §9 and `docs/VISION.md` §14). Defaulting the
   native binary to a bundled libc closes the gap: every artifact
   the protocol ships has a Zig-controlled runtime floor, not a
   distro-controlled one.

## Alternatives considered

1. **Wait for Zig to fix the LLD `.sframe` relocation handling.**
   Rejected: it's not in 0.16 stable, the project pins 0.16, and the
   wait is open-ended. Every contributor on a recent distro is
   blocked in the meantime.
2. **Document the `-Dtarget=x86_64-linux-musl` opt-in workaround
   without changing the default.** Rejected: contributors hit the
   error first, then find the workaround. The first-contact
   experience is "the build doesn't work," which is exactly what a
   build system should not be.
3. **Pin to an older GCC via `mise`.** Rejected: we don't manage the
   system toolchain through mise (only Zig and bun); doing so would
   expand the project's stack contract in the wrong direction.
4. **Switch to native musl across the whole stack (Alpine-style).**
   Rejected as over-reach. The change is purely about which libc
   `jelly` links against. Anything that compiles to wasm or runs
   under bun is unaffected.

## Consequences

- `mise exec zig@0.16.0 -- zig build` produces a statically-linked
  musl binary on Linux. CLAUDE.md is updated to reflect that the
  resulting binary's ABI is musl rather than glibc (the command is
  unchanged).
- `scripts/cli-smoke.sh` and `scripts/server-smoke.sh` continue to
  invoke `zig-out/bin/jelly` directly; static linkage means no
  `LD_LIBRARY_PATH` surprises in CI.
- Any contributor who needs glibc linkage (e.g., to dynamically link
  against a vendor library not packaged for musl) passes
  `-Dtarget=native` explicitly.
- Pre-requisite: `src/cli/internal/open.zig`'s sigaction handler must
  not assume the macOS struct shape (see Dreamball-a05) — that
  blocker is resolved before this default flip lands, so the new
  default actually compiles end-to-end on day one.

## Aligned with prior decisions

- The "host-supplied randomness via one `env.getRandomBytes` import"
  seam for wasm (ADR-1 in `docs/ARCHITECTURE.md`, VISION §14): same
  principle at native scope — minimise host coupling so artefacts
  are reproducible across boxes.
- The spike-before-promote pattern (sprint-002 D-024): this ADR is
  the "promote" event after the verification spike on the fleet
  container that surfaced the GCC 16 / LLD breakage.
