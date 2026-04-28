# 2026-04-28 — Wasm runtime selection for the action host

Sprint: sprint-002 · Story: 5.1 · Significance: HIGH · Sibling decisions:
[D-020 wasm-runtime](./2026-04-25-wasm-runtime.md),
[D-032 single shared host (sprint architecture-decisions.md)](../sprints/002-archiform-foundation/architecture-decisions.md),
[D-024 spike-before-promote](../sprints/002-archiform-foundation/architecture-decisions.md)

## Context

D-020 commits the project to wasm as the runtime for action
implementations. D-032 commits us to **one shared Zig host** that
compiles for both the CLI (Zig + WASI) and the browser (`jelly.wasm` +
JS host glue). Story 5.1 is the spike that picks the engine that will
sit underneath that host.

The Cluster E story specs (5.1–5.5) only need a host that can:

- load a small wasm module from disk;
- enforce an import whitelist (today: WASI `fd_write` for the spike;
  tomorrow: 5 `dreamball.*` imports per D-033);
- broker a WASI `fd_write` call through to host stdout (AC4);
- reject a guest that imports `env.malicious_function` (AC5);
- start cold and finish a 1-shot run inside ≤ 100 ms on an M-series Mac
  (AC6, NFR4).

Crucially, the same host code must compile to **both** the CLI binary
and the browser. The browser already runs a different module
(`jelly.wasm`) via the WebAssembly JS API; sprint-003 will load
*action* wasm inside the browser context too, and per D-032 it must do
so without source divergence from the CLI host.

## Options evaluated

### Option A — In-tree minimal Zig interpreter

Write a small wasm decoder + stack-machine interpreter directly in
Zig, sized to the spike's needs (and growable through Story 5.2/5.3).

- **Build size:** zero new dependencies. Adds a few hundred lines of
  Zig to the `jelly` binary; comfortably under TC5's 200 KB / 64 KB
  gz budget for the *parser* wasm (the action host runs in `jelly`
  CLI, separate budget).
- **Cross-platform:** Zig source compiles identically for darwin and
  linux. WASI shim is a thin file-descriptor table the host owns.
- **Browser parity (D-032):** the same interpreter compiles to
  wasm32-freestanding. In the browser, the *outer* engine (the
  browser's WebAssembly.Module) hosts our interpreter, and our
  interpreter hosts the action guest. WASI imports in the action
  guest get rerouted to JS-side shims via `dreamball.*` once D-033's
  5 imports replace the WASI calls in Story 5.2.
- **Instantiation API surface:** small and ours. We control the seam.
  No FFI, no opaque handles. Errors are typed Zig errors with
  attributable provenance ("rejected import `env.malicious_function`
  at module byte offset N").
- **Performance:** an interpreter is slower than a JIT, but the
  budget is 100 ms cold for a guest that prints one line. A
  hand-written Zig interpreter clears that budget by orders of
  magnitude (microseconds, not milliseconds).
- **Spec coverage risk:** the interpreter starts as a subset. We grow
  coverage as Cluster E demands more opcodes. Each new opcode is one
  case in a switch; not architectural.
- **Maintenance:** the interpreter is *our* code, so debuggability is
  excellent and the CI surface is `zig build` only — no system
  packages, no version-skew between dev and CI.

### Option B — Link wasmtime via its C ABI

Wasmtime is mature, JIT-fast, supports WASI out of the box, and has a
stable C API.

- **Build size:** wasmtime's C library is large (tens of MB). The
  CLI binary either statically links it (binary balloon) or
  dynamically loads it (system-package dep). Either way it's a
  significant departure from today's lean `jelly` binary.
- **Cross-platform:** good native support; CI install via `apt
  install wasmtime-dev` on Ubuntu and `brew install wasmtime` on
  darwin. But this introduces a *system-package* dep, breaking the
  current "Zig + bun, nothing else" build story.
- **Browser parity (D-032):** wasmtime is **not** available in the
  browser. A wasmtime-based host would force a *separate* JS-side
  engine for the browser projection — exactly the per-runtime
  divergence D-032 prohibits.
- **Instantiation API surface:** opaque handles, error codes, and a
  C ABI through `extern` declarations. Workable but foreign to the
  rest of the codebase.
- **Performance:** JIT-fast. Massively over-budget on cold start
  (wasmtime's compilation step alone routinely exceeds 50 ms for
  trivial modules; we'd need to use the `wasmtime::Engine`
  pre-compilation cache to stay under 100 ms).
- **Maintenance:** version-pinning a third-party C library across
  darwin + linux + (eventually) Windows is real ongoing cost.

### Option C — Link wasmer via its C ABI

Wasmer's tradeoffs mirror wasmtime: mature, JIT-fast, has a C ABI,
supports WASI. Same browser-parity blocker (D-032), same system-package
cost.

Wasmer's marginal advantage over wasmtime is broader pluggable backend
support (LLVM, Cranelift, singlepass), which we don't need for the
spike or for sprint-002.

## Decision

**Option A — in-tree minimal Zig interpreter.**

Rationale:

1. **D-032 alignment.** Only Option A keeps the host code identical
   across CLI and browser. Options B and C would force a separate
   browser-side engine, which D-032 explicitly forbids.
2. **TC5 budget headroom.** Adding a few KB of Zig to the action
   host is invisible; adding wasmtime is megabytes.
3. **Spike-before-promote (D-024).** A small Zig interpreter is the
   right *minimum viable engine* — it grows naturally as Cluster E
   stories surface new opcode/import needs, and each growth event is
   a small reviewable diff inside our codebase.
4. **CI simplicity.** No new system packages, no version pinning of
   foreign libraries, no apt/brew steps in `.github/workflows/ci.yml`.
5. **Honest provenance.** Errors come from code we wrote, not from
   wasmtime's error enum. Story 5.3's import-violation tests get to
   assert on Zig error names, not opaque C error codes.

The interpreter starts at the subset hello.wasm needs (fundamental
control flow, i32 ops, memory load/store, function calls, WASI
`fd_write` import) and grows as Stories 5.2–5.4 demand more.

## Instantiation API surface

```zig
const wasm_host = @import("wasm-host");

// Read-only loaded module: parsed sections, validated imports.
const module = try wasm_host.Module.parse(allocator, bytes);
defer module.deinit();

// Instance: imports resolved against caller-supplied host functions.
// Imports the host doesn't know how to resolve are an error here —
// this is the SEC1 whitelist seam. Story 5.3 enriches the rejection
// path with structured error codes.
var instance = try wasm_host.Instance.init(allocator, &module, .{
    .imports = &.{
        .{ .module = "wasi_snapshot_preview1", .name = "fd_write",
           .impl = .{ .host_fn = wasiFdWrite } },
    },
});
defer instance.deinit();

// Run an exported function. WASI's `_start` is the conventional
// entry point; spike host calls it directly.
try instance.invokeStart();
```

The seam is intentionally narrow:

- `Module.parse` — bytes → validated AST (rejects malformed binary).
- `Instance.init` — module + import set → ready-to-run instance
  (rejects unknown imports here; this is where AC5 fails).
- `instance.invokeStart()` — runs `_start`, brokers WASI imports
  through the registered host functions.

Story 5.2 will rename `Instance.init`'s `imports` argument to take a
`dreamball.*` whitelist as the canonical seam. The mechanical shape
stays the same.

## Consequences

- New code: `src/wasm-host/spike/` for sprint-002 Cluster E spike;
  Story 5.2 promotes to `src/wasm-host/`.
- No new system packages. CI workflow gains a `wasm-spike` step that
  runs `zig build wasm-spike-host` and confirms guest output.
- Future opcode/import expansion is in-tree; each new opcode is a
  switch arm; each new import is a registry entry.
- Browser projection (sprint-003): the interpreter compiles to
  wasm32-freestanding and ships inside the JS-side runtime alongside
  `jelly.wasm`. No separate engine.
- If a future story discovers a wasm feature beyond what the
  interpreter supports (e.g., SIMD, threads, GC proposal), that's an
  ADR amendment event — we either grow the interpreter or revisit
  this decision. SIMD/threads/GC are not on Cluster E's path.

## Open questions deferred

- **Memory ceiling enforcement** (D-020: 16 MiB initial, 64 MiB
  hard ceiling) is Story 5.3's concern. The spike sets a generous
  soft cap and notes the hook for 5.3 to tighten.
- **Verify-before-instantiate (SEC4 / D-031)** is Story 5.3. The
  spike host loads bytes directly; production host will verify
  blake3(wasm_bytes) against the action manifest's `implementation.wasm`
  fp before parsing.
