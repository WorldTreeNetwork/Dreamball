# DreamBall

> Signed, evolvable, lens-rendered aspects — NFT-style containers for
> **look**, **feel**, and **act**. Open protocol, open implementation,
> hybrid post-quantum signatures, same WASM parser in the browser and on
> the server.

**File extension:** `.ball` · **Media type:** `application/ball+cbor`
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
zig build          # Zig library + dreamball CLI
zig build wasm     # dreamball.wasm for Bun + browser

# 3) Mint a DreamBall and inspect it.
./zig-out/bin/dreamball mint --out my-aspect.ball --type avatar --name curiosity
./zig-out/bin/dreamball show my-aspect.ball
./zig-out/bin/dreamball verify my-aspect.ball && echo OK
./zig-out/bin/dreamball export-json my-aspect.ball --out my-aspect.ball.json

# 4) See it in the renderer.
bun run storybook
# → browse to http://localhost:6006

# 5) Run the full demo (dreamball-server + showcase app).
bun run demo
# → dreamball-server on :9808, showcase on Vite's default port
# → visit /demo/transmission, /demo/unlock, /demo/wearer, /demo/splat

# 6) Sanity-check every gate.
zig build test --summary all   # Zig unit tests
zig build smoke                 # CLI end-to-end
bun run test:unit -- --run      # Svelte lib + schemas + WASM tests
bun run check                   # svelte-check 0 errors
scripts/server-smoke.sh         # HTTP end-to-end via dreamball-server
tests/e2e-cryptography.sh       # crypto pipeline (mock or real)
```

---

## The one-binary-two-runtimes principle

`src/wasm_main.zig` compiles to a single `dreamball.wasm` (currently 109 KB)
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
              └───────────────┬──────────────┘
                              │
              zig build   ┌───┴───┐   zig build wasm
                          ▼       ▼
                ┌─────────────────┐   ┌──────────────────────────┐
                │  dreamball CLI  │   │  dreamball.wasm (109 KB) │
                └────────┬────────┘   └────┬────────────────┬────┘
                         │                 │                │
                         ▼                 ▼                ▼
              ┌──────────────────┐ ┌──────────────────┐ ┌──────────────┐
              │  dev shell /     │ │  dreamball-      │ │  Svelte lib  │
              │  MCP stdio       │ │  server          │ │  (browser)   │
              │  server          │ │  (Bun+Elysia     │ └──────────────┘
              └──────────────────┘ │   +Eden)         │
                                   └────────┬─────────┘
                                            │
                                            ▼
                                   ┌────────────────┐
                                   │ recrypt-server │ ← ML-DSA-87 signing,
                                   │ (Rust + liboqs)│   Guild keyspaces (Phase D)
                                   └────────────────┘
```

---

## The MCP documentation layer

Any AI agent discovering a running `dreamball-server` can query one
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
| `src/cli/` | `dreamball` CLI commands |
| `src/wasm_main.zig` | `dreamball.wasm` entry |
| `src/lib/` | Svelte 5 + Threlte renderer library |
| `src/lib/generated/` | AUTO — types.ts, schemas.ts (Valibot), cbor.ts |
| `src/lib/wasm/` | `dreamball.wasm` + loader.ts |
| `src/routes/` | SvelteKit showcase app (Demo D) |
| `src/stories/` | Storybook stories |
| `dreamball-server/` | Bun + Elysia HTTP server wrapping WASM |
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

- `zig build test` · `zig build smoke` · `zig build wasm` (≤200 KB raw / ≤64 KB gzipped; ships ML-DSA-87 verify)
- `bun run check` · `bun run test:unit -- --run` · `bun run build`
- `bun run build-storybook` · `bun run test-storybook`
- `scripts/server-smoke.sh` · `tests/e2e-cryptography.sh`

CI runs every gate on push/PR (`.github/workflows/ci.yml`). Storybook is
published to GitHub Pages on main-branch merges.

---

## Releases

Releases are **tag-driven**: push a semver tag (`vX.Y.Z`, matching
`package.json`'s `version`) and `.github/workflows/release.yml` builds and
publishes a GitHub Release with cross-platform `dreamball` CLI tarballs
(linux x86_64/aarch64 musl-static + macOS arm64), the versioned
`dreamball.wasm` bundle, and a `SHA256SUMS` manifest. The Svelte library is
published to npm in lockstep when an `NPM_TOKEN` secret is set.

```bash
git tag -a v0.1.1 -m "dreamball 0.1.1"   # tag == package.json version
git push origin v0.1.1
```

Full runbook (dry runs, npm setup, the version-sync rule):
[`docs/ops/releasing.md`](docs/ops/releasing.md).

---

## License

TBD (matches recrypt's license once selected).
