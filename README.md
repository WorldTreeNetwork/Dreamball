# DreamBall

> Signed, evolvable, lens-rendered aspects — NFT-style containers for
> **look**, **feel**, and **act**. Open protocol, open implementation,
> hybrid post-quantum signatures, same WASM parser in the browser and on
> the server.

**File extension:** `.jelly` · **Media type:** `application/jelly+cbor`
**Sister project:** [recrypt](../recrypt/) (post-quantum trust anchor)

---

## What it is

A DreamBall is a protocol container with three axes:

| Axis       | What it holds                                                        |
| ---------- | -------------------------------------------------------------------- |
| **look**   | visual representation — URLs, embedded GLB/GLTF/splat assets         |
| **feel**   | personality — tone, values, voice, affective profile                 |
| **act**    | executable layer — model ref, system prompt, skills, scripts         |

Six MTG-style types change behaviour categorically:

- **Avatar** — worn, visible to observers ("jelly bean" style)
- **Agent** — instantiable with memory, knowledge graph, emotional register
- **Tool** — transferable skill
- **Relic** — sealed + encrypted, reveals on Guild key unlock
- **Field** — omnispherical ambient layer
- **Guild** — keyspace-backed group with per-slot policy

Full rationale in [`docs/VISION.md`](docs/VISION.md), wire format in
[`docs/PROTOCOL.md`](docs/PROTOCOL.md), architecture in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Try it in 60 seconds

```sh
# 1) Prereqs: Zig 0.16, Bun, a recent browser.
zig version   # expect 0.16.x
bun --version # any recent

# 2) Build.
bun install
zig build          # Zig library + jelly CLI
zig build wasm     # jelly.wasm for Bun + browser

# 3) Mint a DreamBall and inspect it.
./zig-out/bin/jelly mint --out my-aspect.jelly --type avatar --name curiosity
./zig-out/bin/jelly show my-aspect.jelly
./zig-out/bin/jelly verify my-aspect.jelly && echo OK
./zig-out/bin/jelly export-json my-aspect.jelly --out my-aspect.jelly.json

# 4) See it in the renderer.
bun run storybook
# → browse to http://localhost:6006

# 5) Run the full demo (jelly-server + showcase app).
bun run demo
# → jelly-server on :9808, showcase on Vite's default port
# → visit /demo/transmission, /demo/unlock, /demo/wearer, /demo/splat

# 6) Sanity-check every gate.
zig build test --summary all   # Zig unit tests
zig build smoke                 # CLI end-to-end
bun run test:unit -- --run      # Svelte lib + schemas + WASM tests
bun run check                   # svelte-check 0 errors
scripts/server-smoke.sh         # HTTP end-to-end via jelly-server
tests/e2e-cryptography.sh       # crypto pipeline (mock or real)
```

---

## The one-binary-two-runtimes principle

`src/wasm_main.zig` compiles to a single `jelly.wasm` (currently 109 KB)
that is executed **identically** in Bun (server) and in the browser
(Svelte lib). One imported function, `env.getRandomBytes`, is the
entire host seam.

Consequences: impossible drift between server and client, offline-first
protocol ops in the browser, and trust symmetry — the server's
guarantees are the same as the browser's because they run the same
bytes. See [`docs/VISION.md §14`](docs/VISION.md) and
[`docs/ARCHITECTURE.md §2`](docs/ARCHITECTURE.md).

---

## Architecture at a glance

```
              ┌──────────────────────────────┐
              │  src/*.zig  (protocol core)  │ ← authority
              └────────────┬─────────────────┘
                           │
           zig build   ┌───┴───┐   zig build wasm
                       ▼       ▼
              ┌───────────┐  ┌─────────────────────┐
              │ jelly CLI │  │  jelly.wasm (109KB) │
              └─────┬─────┘  └───┬──────────┬──────┘
                    │            │          │
                    ▼            ▼          ▼
            ┌──────────────┐ ┌─────────┐ ┌──────────────┐
            │  dev shell / │ │ jelly-  │ │  Svelte lib  │
            │  MCP stdio   │ │ server  │ │  (browser)   │
            │  server      │ │(Bun+Elysia│└──────────────┘
            └──────────────┘ │ +Eden)  │
                             └────┬────┘
                                  │
                                  ▼
                         ┌────────────────┐
                         │ recrypt-server │ ← ML-DSA-87 signing,
                         │ (Rust + liboqs)│   Guild keyspaces (Phase D)
                         └────────────────┘
```

---

## The MCP documentation layer

Any AI agent discovering a running `jelly-server` can query one
well-known endpoint to learn the full API surface:

```sh
curl http://localhost:9808/.well-known/mcp
```

Returns routes + Valibot schemas (as JSON Schema) + WASM export
signatures + type taxonomy + example request/response pairs + MCP tool
descriptors. The document is **generated at request time** from the
live route table and the same Valibot schemas that drive validation —
drift is structurally impossible.

`curl http://localhost:9808/.well-known/mcp/types` returns just the JSON
Schema bundle.

The stdio MCP server at `tools/mcp-server/server.ts` exposes the same
document via a `describe_api` tool so agents can pick either transport.

---

## Repo layout

| Path | Purpose |
|---|---|
| `src/*.zig` | Zig protocol core — authority for the wire format |
| `src/cli/` | `jelly` CLI commands |
| `src/wasm_main.zig` | `jelly.wasm` entry |
| `src/lib/` | Svelte 5 + Threlte renderer library |
| `src/lib/generated/` | AUTO — types.ts, schemas.ts (Valibot), cbor.ts |
| `src/lib/wasm/` | `jelly.wasm` + loader.ts |
| `src/routes/` | SvelteKit showcase app (Demo D) |
| `src/stories/` | Storybook stories |
| `jelly-server/` | Bun + Elysia HTTP server wrapping WASM |
| `tools/schema-gen/` | Zig → types.ts + schemas.ts codegen |
| `tools/mcp-server/` | stdio MCP server wrapping the CLI |
| `docs/` | PROTOCOL.md, VISION.md, ARCHITECTURE.md, known-gaps.md |
| `scripts/` | CLI smoke, server smoke, WASM env-import spike |
| `tests/` | e2e crypto pipeline |

---

## Contributing

Read these four files in order before touching code:

1. [`CLAUDE.md`](CLAUDE.md) — operating principles (document the why
   alongside the what).
2. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the runtime map.
3. [`docs/PROTOCOL.md`](docs/PROTOCOL.md) — the wire format.
4. [`docs/VISION.md`](docs/VISION.md) — the why.

Every change must keep these gates green:

- `zig build test` · `zig build smoke` · `zig build wasm` (≤150 KB)
- `bun run check` · `bun run test:unit -- --run` · `bun run build`
- `bun run build-storybook` · `bun run test-storybook`
- `scripts/server-smoke.sh` · `tests/e2e-cryptography.sh`

CI runs every gate on push/PR (`.github/workflows/ci.yml`). Storybook is
published to GitHub Pages on main-branch merges.

---

## License

TBD (matches recrypt's license once selected).
