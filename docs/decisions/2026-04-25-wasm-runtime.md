# 2026-04-25 — Wasm as runtime for executable code in DreamBalls

Sprint: sprint-002 · Significance: HIGH · Sibling decisions:
[archiform-registry](./2026-04-25-archiform-registry.md) ·
[json-schema-canonical](./2026-04-25-json-schema-canonical.md) ·
[action-manifest](./2026-04-25-action-manifest.md)

## Context

The Action Manifest
([action-manifest](./2026-04-25-action-manifest.md)) needs a runtime
for action implementations. More broadly, the DreamBall ecosystem will
ship executable code in several places: action implementations, lens
shaders, derivation rules (e.g., `Aqueduct.phase` computed from
`(strength, last_traversal_ts, decay_params)`), policy evaluators,
mythos validators. Each of these wants the same properties — sandboxed,
portable, content-addressed, reproducible across the same runtimes
that already host `jelly.wasm`.

## Decision

**Wasm is the runtime for all executable code in DreamBalls.** Action
implementations, derivation rules, policy evaluators, and lens
computations are all wasm modules; bundle assets (shaders, images,
fonts) accompany them as static files referenced from manifests.

A DreamBall thus becomes a fully self-contained, verifiable
computational artifact:

- **Bytes** — CBOR ([json-schema-canonical](./2026-04-25-json-schema-canonical.md))
- **Shape** — JSON Schema (same)
- **Code** — wasm (this decision)

All three content-addressed, all signable.

### Runtime contract

- Wasm modules run with **WASI** for filesystem/network access where
  the projection layer grants it (CLI grants more, browser renderer
  grants less, MCP server grants according to agent policy).
- Imports limited to a host-defined `dreamball.*` namespace —
  `dreamball.fp(bytes)`, `dreamball.encode_cbor(value)`,
  `dreamball.read_node(fp)`, `dreamball.emit_action_envelope(value)`,
  `dreamball.now_ms()`, etc. This is the same architectural seam as
  today's `env.getRandomBytes` import (VISION §14, ADR-1).
- Memory limit per module instance set by host; default conservative
  (16 MiB initial, configurable per projection).
- Modules are content-addressed by `blake3(wasm_bytes)`. The action
  manifest's `implementation.wasm` field is an fp; you cannot run
  different code than the manifest declared.

### Bun-script fallback (early authoring)

For the first ecosystem phase, archiform authors MAY ship `bun-script`
implementations instead of wasm:

```json
"implementation": { "bunScript": "actions/mint.ts", "export": "mint" }
```

Hosts that have bun installed run these directly; hosts without bun
refuse with a clear error (`requires-bun`). This lowers the bar to
authoring while the wasm toolchain matures. Production-grade
archiforms SHOULD ship wasm.

## Alternatives considered

1. **Bun script as primary** (no wasm). Rejected as primary —
   depends on bun being installed on every host, less sandboxed
   (full access to host process), no portable security model for
   third-party archiform code. Kept as fallback (above).
2. **Native binaries per platform** (git-style PATH discovery).
   Rejected — multiplies the release matrix, no sandboxing, hostile
   to agent-callable use cases (an MCP server can't safely shell out
   to an arbitrary native binary).
3. **Per-purpose runtimes** (Lua for derivations, Deno for actions,
   wasm for shaders). Rejected — fragments authoring story; an
   archiform author would need to learn three runtimes. One runtime
   for all executable surfaces is the right cost-benefit.

## Consequences

- Archiform deliverable is a tidy bundle:
  ```
  dreamball-memory-palace-0.1.0/
  ├── schema.json           # JSON Schema (D-003)
  ├── actions/              # wasm modules (this decision)
  │   ├── mint.wasm
  │   ├── inscribe.wasm
  │   └── add-room.wasm
  ├── lens-pack/            # static lens assets
  └── derivations/          # wasm helpers for derived properties
      └── aqueduct-phase.wasm
  ```
  The whole bundle is content-addressed; an archiform's fp =
  `blake3(canonical bundle manifest)`.
- Sprint-002 stands up the wasm action host inside `jelly` CLI. The
  browser renderer already hosts wasm via `jelly.wasm`; the same host
  code is reused for lens-side derivations.
- Bun-script fallback supported in sprint-002 for fast authoring.
  Wasm is the production target.
- Existing `jelly.wasm` is the *root primitive* host (CBOR codec,
  blake3, ML-DSA-87 verify). Archiform wasm modules are guests of this
  host, importing from `dreamball.*`.
- Permissions model: each projection layer declares which
  `dreamball.*` imports a given archiform may use (the renderer
  withholds `emit_action_envelope` for read-only views; the CLI
  grants everything). Imports become the security surface.

## What this unlocks

- **Lens computations are verifiable.** A lens that draws aqueducts
  with phase-coloured pulses runs the same wasm derivation everywhere,
  so two viewers of the same palace see the same phase even before
  they share traversal state.
- **Policy is portable.** An agent's `policy` evaluator is a wasm
  function; the same evaluator decides reads in browser, server, and
  CLI without divergence.
- **Third-party archiforms become safe to install.** `jelly install
  guild/citadel@1.0.0` ships sandboxed wasm; the host enforces import
  permissions; no arbitrary code execution.
- **The cross-runtime invariant grows naturally:** "the wire format
  lives in Zig (CBOR algorithm + golden vectors); the archiform
  shapes live in JSON Schema; the archiform code lives in wasm." Each
  layer has one authoritative location, content-addressed.
