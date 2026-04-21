# DreamBall Architecture

> How the pieces fit. The *why* behind the choices lives in
> [`VISION.md`](VISION.md); the *wire format* lives in
> [`PROTOCOL.md`](PROTOCOL.md). This document is the map.

---

## 1. The one-slide picture

```
                        ┌───────────────────────────────┐
                        │     docs/PROTOCOL.md          │
                        │     (wire format = authority) │
                        └──────────────┬────────────────┘
                                       │
                         ┌─────────────▼──────────────┐
                         │   src/*.zig                │
                         │   Zig protocol core        │  ← single source of truth
                         │   (encode/decode/sign/     │
                         │    seal/verify/validate)   │
                         └─────┬──────────────────┬───┘
                               │                  │
                   zig build   │                  │  zig build wasm
                               ▼                  ▼
                    ┌──────────────────┐    ┌───────────────────────┐
                    │  zig-out/bin/    │    │  src/lib/wasm/        │
                    │    jelly (CLI)   │    │    jelly.wasm         │
                    └──────┬───────────┘    └──────┬────────────────┘
                           │                       │
                           │          ┌────────────┴─────────┐
                           │          │                      │
                           │       ┌──▼──────────────┐   ┌───▼──────────────┐
                           │       │  jelly-server   │   │  src/lib/        │
                           │       │  (Bun + Elysia) │   │   (Svelte lib,   │
                           │       │  Routes + Eden  │   │    browser)      │
                           │       └──────┬──────────┘   └──────────────────┘
                           │              │
                           ▼              │
                    ┌────────────────┐    │        ┌──────────────────────┐
                    │   Developer    │    └────────▶ Eden typed client     │
                    │   shell + MCP  │             │  (`treaty<App>`)      │
                    │   stdio server │             └──────────────────────┘
                    └────────────────┘

                              ┌───────────────────────┐
                              │   recrypt-server      │ ◀── Guild keyspace
                              │   (Rust)              │     proxy-recryption
                              └───────────────────────┘
                              (ML-DSA-87 is vendored liboqs inside the
                               jelly CLI + jelly.wasm — no HTTP hop.)
```

---

## 2. The invariant that governs everything

**The Zig protocol core is the only place the wire format exists.** Every
other surface — CLI, WASM, Svelte library, jelly-server, MCP docs
endpoint — derives from the Zig code. The rules:

1. No TypeScript code encodes or decodes CBOR by hand. It goes through
   the WASM module.
2. No hand-maintained schemas exist anywhere. TypeScript interfaces +
   Valibot schemas come from `tools/schema-gen/main.zig`, regenerated
   via `bun run codegen`.
3. The browser and server load **the same `jelly.wasm` binary**. No
   platform-specific build, no conditional code paths. A bug in the
   wire format is fixed in one place.

This is why [`ADR-1`](#adr-1-wasm-as-the-cross-runtime-crypto-core) below
chose WASM over FFI and over subprocess.

---

## 3. Runtime map

| Runtime | Consumes | Produces | Role |
|---|---|---|---|
| **Zig CLI** (`zig-out/bin/jelly`) | argv, `~/.config/jelly` | `.jelly` files, `.jelly.json`, signed envelopes, sealed relics | The authoring tool. First-class test surface. |
| **Browser** (Svelte + Threlte) | `.jelly` bytes via `fetch`, user input | Rendered views, user interactions, signed commits | The consumer surface. Runs `jelly.wasm` for parse + verify + validate. |
| **`jelly-server`** (Bun + Elysia) | HTTP requests, filesystem `.jelly` store, `recrypt-server` | HTTP JSON responses, Eden-typed client calls | The authoring service + API. Runs the same `jelly.wasm` for write ops. |
| **`jelly` MCP server** (Bun, stdio) | JSON-RPC over stdio from Claude Code / any MCP client | MCP tool responses wrapping CLI commands | The scripting surface for AI agents. |
| **`recrypt-server`** (Rust) | HTTP requests for Guild keyspace proxy-recryption | Recrypted keys for sealed-relic unlock and guild-scoped transmission | The Guild proxy-recryption anchor. Shared across the IdentiKey family. (ML-DSA-87 signing + verify are vendored into the jelly CLI and jelly.wasm — no HTTP hop.) |

Each runtime holds different capabilities but shares the same wire format.

---

## 4. The three crypto tiers

Not every DreamBall needs every form of integrity. The protocol defines
three tiers; runtimes pick which applies:

### Tier 1 — Ed25519 only (default, always available)

- Native `std.crypto.sign.Ed25519` in Zig, WASM, and browser.
- Sufficient for authorship attribution + tamper detection today.
- The only tier that works fully offline and in-browser without network.

### Tier 2 — Ed25519 + ML-DSA-87 (hybrid, production-grade)

- Ed25519 as in Tier 1, plus real post-quantum signatures via the
  vendored liboqs subset linked directly into the `jelly` CLI (see
  `src/ml_dsa.zig`). No HTTP hop, no `recrypt-server` dependency for
  signing — the native binary holds ML-DSA-87 locally.
- Required by the `DreamBall.isFullySigned(.strict)` policy.
- Signing flow on the server: `jelly-server` subprocesses the native
  `jelly` binary, which signs with both Ed25519 + ML-DSA-87 in one
  pass using the hybrid key file format (see `src/key_file.zig`).
- **Browser verification runs locally.** `jelly.wasm` ships the
  ML-DSA-87 verify path too (same vendored liboqs subset, compiled
  for wasm32-freestanding via shim headers in
  `vendor/liboqs/wasm_shims/`). Both sigs check against the
  envelope's `identity` / `identity-pq` core fields. No network hop
  required for verify. See `docs/known-gaps.md §1` for the size
  measurement (+28.7 KB raw / +9.9 KB gzipped over Ed25519-only).

### Tier 3 — Encrypted transport (DragonBall + recrypt proxy-recryption)

- Sealed DreamBalls (Relics) and Guild-scoped transmissions use
  recrypt's proxy-recryption under the hood.
- Guild keyspaces are real recrypt keyspaces; member access is
  delegated via recryption keys.
- Tier 3 implies Tier 2 (a sealed DreamBall always carries real ML-DSA
  signatures on its inner envelope).

Tier is not declared on the envelope — it emerges from which slots are
populated. A consumer sees the slot surface and knows what to require
from the runtime.

---

## 5. Data flows

### 5.1 Mint a new Agent DreamBall (Tier 2)

```
  1.  client → POST /dreamballs { type: 'agent', name: 'Curious' }
                       │
  2.  jelly-server subprocesses `jelly mint --type agent --name ...`
                       │
                       ▼
  3.  Native CLI generates a hybrid Ed25519 + ML-DSA-87 keypair,
       signs the envelope with both, writes <fp>.jelly + <fp>.jelly.key
       (7560-byte hybrid format, DJELLY magic + both secrets)
                       │
  4.  jelly-server reads the envelope + key file, moves them to
       data/dreamballs/<fp>.jelly, data/keys/<fp>.key (0600)
                       │
  5.  client ← 200 { fingerprint, dreamball, secret_key_b58 }
```

Per-DreamBall signing-key material is stored as a raw `recrypt.identity`
Gordian Envelope (CBOR tag 200, dCBOR canonical form). The envelope carries
ed25519 + ML-DSA-87 keypairs as optional-but-populated assertions; PRE keys
are absent (Dreamball's signing flow doesn't participate in proxy recryption
directly). Legacy 64-byte ed25519-only files are still read; the retired
`DJELLY\n` hybrid layout is rejected on load. See
`docs/decisions/2026-04-21-identity-envelope.md` and
`vendor/recrypt-identity-fixtures/` for the interop contract.

After this mint response, the server will never emit `secret_key_b58`
again. The client holds the secret; server-side it stays on-disk at
`0600`.

### 5.2 Load a DreamBall in the browser

```
  1.  browser → GET /dreamballs/:fp
                       │
  2.  jelly-server reads data/dreamballs/<fp>.jelly, returns CBOR bytes
                       │
  3.  browser → parseJelly(bytes)  (via jelly.wasm, same binary as server)
                       │
  4.  browser → valibot.parse(DreamBallSchema, result)
                       │  ↳ schema drives runtime validation
                       ▼
  5.  renderer receives typed DreamBall → picks lens → renders
                       │
  6.  (optional) browser → verifyJelly(bytes)
                       │  ↳ both Ed25519 AND ML-DSA-87 verified locally
                       │    (no network hop; see ADR-3 below)
```

### 5.3 Unlock a sealed Relic (Tier 3)

```
  1.  client holds member keypair for guild G
                       │
  2.  client → POST /relics/:id/unlock { guild_member_key_b58 }
                       │
  3.  jelly-server loads sealed bundle (DragonBall), extracts the
       recrypt-wrapped payload from the first attachment slot
                       │
  4.  jelly-server → recrypt-server POST /recrypt
                       { wrapped, from_guild_fp, to_member_fp }
                       │
                       ▼
  5.  recrypted ciphertext returned
                       │
  6.  client decrypts locally with the member key
                       │  (the plaintext is the inner DreamBall envelope
                       │   bytes; server never sees it)
                       ▼
  7.  browser → parseJelly(inner) → render via OmnisphericalLens reveal
```

---

## 6. The MCP documentation layer

Every AI agent that meets a `jelly-server` can discover its full API
surface by hitting one well-known endpoint:

```
  GET /.well-known/mcp
```

Returns a **generated** JSON document containing:

- Every HTTP route's path, method, Valibot schema (serialised as JSON
  Schema), example request/response.
- The DreamBall type taxonomy (six v2 types + untyped v1) with each
  type's populated attribute surface.
- Every WASM export signature (`mintDreamBall`, `growDreamBall`,
  `joinGuildWasm`, `parseJelly`, `verifyJelly`, ...) with their
  parameter + return shape.
- MCP tool descriptors matching `tools/mcp-server/server.ts`'s format so
  an agent can choose between HTTP and stdio MCP interchangeably.
- Doc anchor URLs pointing at `PROTOCOL.md` / `VISION.md` /
  `ARCHITECTURE.md` (this doc).

Critically, the document is **assembled at request time** from the live
route table and the same Valibot schemas that drive validation. Drift
between "what the server does" and "what the docs say it does" is
structurally impossible.

A sibling endpoint `GET /.well-known/mcp/types` returns just the JSON
Schema bundle for agents that only want the type shapes.

The stdio MCP server at `tools/mcp-server/server.ts` exposes the same
document via a `describe_api` tool, proxying the HTTP endpoint. Agents
connecting over either transport see identical capability surfaces.

---

## 7. Directory guide

```
Dreamball/
├── build.zig, build.zig.zon     # Zig build system
├── package.json, bun.lock       # Bun/JS workspace
├── CLAUDE.md                    # Project operating principles
├── README.md                    # Quickstart
├── docs/
│   ├── PROTOCOL.md              # Wire format — authoritative
│   ├── VISION.md                # Why-doc (living)
│   ├── ARCHITECTURE.md          # This file
│   ├── known-gaps.md            # Residual TODOs with tracking issues
│   └── products/dreamball-v2/   # Sprint PRDs
│       └── prd.md
├── src/
│   ├── protocol.zig             # v1 domain types + DreamBallType enum
│   ├── protocol_v2.zig          # v2 aux types (Memory/KG/ER/Guild/Relic/...)
│   ├── cbor.zig                 # dCBOR encoder/decoder
│   ├── envelope.zig             # Core/attribute framing + decoders
│   ├── envelope_v2.zig          # v2-type envelope encoders
│   ├── signer.zig               # Ed25519 signing (CLI/non-WASM)
│   ├── sealing.zig              # DragonBall file wrapper
│   ├── graph.zig                # Containment cycle validation
│   ├── base58.zig               # Bitcoin-alphabet encode/decode
│   ├── fingerprint.zig          # Blake3(Ed25519 pk)
│   ├── json.zig                 # Lossless JSON export
│   ├── golden.zig               # Canonical-byte lock
│   ├── io.zig                   # Zig 0.16 std.Io helpers
│   ├── root.zig                 # Library module
│   ├── main.zig                 # `jelly` CLI entry
│   ├── wasm_main.zig            # `jelly.wasm` entry
│   ├── cli/                     # CLI commands (mint/grow/seal/...)
│   ├── lib/                     # Svelte 5 renderer library
│   │   ├── index.ts
│   │   ├── generated/           # AUTO — types.ts, schemas.ts, cbor.ts
│   │   ├── components/          # DreamBallViewer, DreamBallCard, ...
│   │   ├── lenses/              # 8 lenses
│   │   ├── backend/             # JellyBackend, MockBackend, HttpBackend
│   │   ├── playcanvas/          # Splat renderer setup
│   │   ├── splat/               # Splat media-type routing
│   │   └── wasm/                # jelly.wasm + loader.ts
│   ├── routes/                  # SvelteKit showcase app
│   └── stories/                 # Storybook stories
├── tools/
│   ├── schema-gen/              # Zig → types.ts + schemas.ts + cbor.ts
│   └── mcp-server/              # stdio MCP server wrapping the CLI
├── jelly-server/                # Bun + Elysia HTTP server
│   └── src/                     # WASM loader, routes, store, MCP docs
├── scripts/
│   ├── cli-smoke.sh             # CLI end-to-end test
│   ├── server-smoke.sh          # jelly-server end-to-end test
│   └── spike-wasm-env.ts        # Proves WASM env-import plumbing
└── tests/
    └── e2e-cryptography.sh      # Full real-crypto integration test
```

---

## 8. Architectural decision records

Short form. Full context in
[`.omc/plans/2026-04-19-jelly-server-storybook-mldsa-recrypt.md`](../.omc/plans/2026-04-19-jelly-server-storybook-mldsa-recrypt.md)
§6.

### ADR-1: WASM as the cross-runtime crypto core

**Decision.** Compile the Zig protocol core to a single `jelly.wasm`.
Bun and the browser execute the exact same bytes. Host-provided
randomness via a single `env.getRandomBytes` import.

**Alternatives rejected.** `bun:ffi` (requires platform-specific
`.dylib`; user said no FFI), subprocess spawn per request (~20 ms cost;
argv injection surface), full Rust rewrite (scope creep).

**Consequences.** Any op that needs blocking I/O stays out of WASM —
but the protocol core is all pure functions + randomness, so this
constraint doesn't bind. File I/O and network calls happen in the
host. ML-DSA-87 *signing* stays on the native CLI by design (user
signing lives in the key-bearing extension/app path); ML-DSA-87
*verify* runs in WASM locally (see ADR-3).

### ADR-2: Elysia + Eden + Valibot for `jelly-server`

**Decision.** Bun-native HTTP via Elysia 1.x. Eden (`treaty<App>`) gives
end-to-end type safety without codegen churn. Valibot schemas (from
`schema-gen`) drive request/response validation via Elysia's
Standard-Schema integration.

**Alternatives rejected.** tRPC (non-standard wire), Hono+OpenAPI
(duplicated codegen with `schema-gen`), bare `Bun.serve` (boilerplate).

**Consequences.** Some Elysia lock-in (Node migration is possible but
suboptimal). Free Swagger docs. Free MCP docs generation from the same
route table.

### ADR-3: ML-DSA-87 via vendored liboqs (native + WASM)

**Decision (revised 2026-04-21).** The vendored liboqs subset under
`vendor/liboqs/` is the post-quantum engine for both runtimes.

- **Native CLI** links the liboqs C sources directly — ~4500 LoC of
  dilithium ref impl + XKCP SHAKE. No HTTP hop, no
  `recrypt-server` dependency for signing. `jelly mint` / `grow` /
  `transmit` / `seal-relic` all sign locally with Ed25519 +
  ML-DSA-87.
- **WASM** (`jelly.wasm`) links the same C sources for wasm32-freestanding
  via four shim headers (`<string.h>`, `<stdlib.h>`, `<stdio.h>`,
  `<limits.h>` in `vendor/liboqs/wasm_shims/`) and a static-arena
  allocator (`vendor/liboqs/src/dreamball_stubs_wasm.c`). The linker's
  dead-code elimination drops the sign + keypair paths, leaving only
  the verify-reachable subset. Result: +28.7 KB raw / +9.9 KB gzipped
  over the Ed25519-only baseline. Browser verification is local and
  hybrid — no network hop required.

**Prior decision (superseded).** An earlier version of this ADR
delegated ML-DSA to `recrypt-server` over HTTP. The motivation was a
pessimistic ~250–400 KB WASM size estimate from Emscripten's full
liboqs build. The verify-only spike landed at ~28 KB raw, making local
verify strictly preferable. Signing was already local on the native
side once we vendored liboqs in `7cdf5eb`. `recrypt-server` still
exposes `POST /sign/ml-dsa` / `POST /verify/ml-dsa` endpoints for
cross-project use, but Dreamball does not call them.

**Consequences.** Offline signing works end-to-end via the native
CLI; offline verification works end-to-end in any runtime. The
protocol's hybrid-PQ promise is fulfilled without a
network-dependent trust anchor. Browser bundle cost is a one-time
+10 KB over the wire.

### ADR-4: Storybook as the developer testing environment

**Decision.** Storybook stories are the primary UI development + testing
environment. Every lens has a dedicated story with interactive Controls;
every DreamBall type has a "tour" story; play functions cover
interactive flows.

**Alternatives rejected.** Hand-rolled dev routes (more work, less
interactive), Ladle (scaffold is already Storybook).

**Consequences.** Stories become a maintenance surface — each new lens
or type adds stories. Acceptable given the 8-lens × 7-type ceiling.

---

## 9. The three canonical files

Any contributor (human or AI) who reads these three files and this
`ARCHITECTURE.md` has enough context to make meaningful changes to the
codebase:

1. `docs/PROTOCOL.md` — what the wire format *is*.
2. `docs/VISION.md` — what the protocol is *for*.
3. `CLAUDE.md` — how to work on it.

This document ties them together.

---

## 10. Where to add a new envelope type (runbook)

1. Add the Zig types in `src/protocol.zig` or `src/protocol_v2.zig`.
2. Add the encoder in `src/envelope.zig` or `src/envelope_v2.zig`.
3. Add the decoder in `src/envelope.zig` (extend `decodeDreamBall`).
4. Update `docs/PROTOCOL.md §12` with the wire-format description.
5. Update `tools/schema-gen/main.zig`'s `TYPES_SRC` and `SCHEMAS_SRC`
   with the new TypeScript interface + Valibot schema.
6. Run `bun run codegen` and `zig build wasm`.
7. Update `docs/VISION.md §10` if the type changes the taxonomy story.
8. Add a Storybook story under `src/stories/types/`.
9. Run `zig build test`, `bun run test:unit -- --run`,
   `bun run test-storybook`, `scripts/cli-smoke.sh`,
   `scripts/server-smoke.sh` — all must pass.
10. Update `docs/ARCHITECTURE.md §7` (this file, directory guide) if
    you added new top-level directories.

If all 10 steps pass in one commit, you haven't drifted.
