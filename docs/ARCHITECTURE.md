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
                    │ dreamball (CLI)  │    │   dreamball.wasm      │
                    └──────┬───────────┘    └──────┬────────────────┘
                           │                       │
                           │          ┌────────────┴──────────┐
                           │          │                       │
                           │       ┌──▼─────────────────┐   ┌─▼────────────────┐
                           │       │  dreamball-server  │   │  src/lib/        │
                           │       │  (Bun + Elysia)    │   │   (Svelte lib,   │
                           │       │  Routes + Eden     │   │    browser)      │
                           │       └────────┬───────────┘   └──────────────────┘
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
                               dreamball CLI + dreamball.wasm — no HTTP hop.)
```

---

## 2. The cross-runtime invariant

The wire format factors into two parts, both **Rust-canonical** as of
2026-08-06. This is the third change of canonical medium (Zig →
JSON Schema (D-018) → Zig (2026-06-25) → Rust); the reasoning, including
why the first two never actually shipped a generator, is in
[`docs/decisions/2026-08-06-rust-canonical.md`](decisions/2026-08-06-rust-canonical.md).
The most-expressive-medium principle from the 2026-06-25 ADR is
unchanged — it now points at Rust, which has a maintained projector
(`serde` + `schemars`) where Zig's comptime reflector was never built.

### Part 1 — dCBOR encoding in the Blockchain Commons crates + golden vectors

Deterministic-CBOR semantics are canonical in `dcbor` 0.25.2 (map key
ordering, integer-width rules, bytes-vs-text discipline) and envelope
framing in `bc-envelope` 0.43.0. We consume those crates; we do not
reimplement them. Every runtime must reproduce the same bytes for the
same logical value, and the language-neutral golden vectors are the
check that proves it. There is no second implementation of CBOR
semantics.

### Part 2 — Field shapes in the Rust types (canonical)

The Rust structs/enums carrying `serde` + `schemars` derives are the
canonical source for all field shapes — the most expressive
representation (defaults, methods, exact types). Everything else is
**generated downward** from them: TypeScript interfaces, Valibot schemas,
the CBOR codec (`cbor.ts`), **JSON Schema** (`schemas/*.json` — a
generated artifact, vendored + blake3-pinned at `schemas/.pins/`, D-029),
and `src/memory-palace/schema.cypher`. To add or change a wire type, edit
the Rust types, then regenerate. JSON Schema is an output, never
hand-authored.

**Zig remains the build system**, scoped to the task orchestrator
(`zig build test|smoke|wasm`, shelling to `cargo` and `bun`) and to
cross-compilation/linking via `cargo-zigbuild`. It no longer compiles
protocol artifacts. That preserves
[`hermetic-musl-default-linux`](decisions/2026-05-24-hermetic-musl-default-linux.md)
verbatim: Linux binaries stay statically linked against Zig's bundled
musl.

> **Transitional note (2026-08-06):** the port (epic `Dreamball-y4t`) is
> in flight. What the build actually runs today is still the Zig types in
> `src/protocol.zig` + `src/protocol_v2.zig` and the hardcoded-body
> generators in `tools/schema-gen/`, with the vendored `schemas/*.json`
> held consistent by a pin + byte-equivalence gate. While porting, edit
> the Zig types and update the generated outputs + JSON-Schema fixtures
> by hand — but do not invest further in that path. The Zig comptime
> `@typeInfo` generator (`Dreamball-m97.2`) is **dissolved, not
> deferred**; do not build it.

### Single shared host code (D-032)

The wasm host that brokers the `dreamball.*` import surface is one Zig
codebase compiled to two targets: `dreamball` CLI (Zig + WASI) and
`dreamball.wasm` (browser, sprint-003+). Host behavior is identical across
targets; only the platform-shim layer (file I/O, network) differs.

The concrete rules that fall out of this invariant:

1. No TypeScript code encodes or decodes CBOR by hand. It goes through
   the WASM module.
2. No hand-maintained schemas drift. TypeScript interfaces, Valibot
   schemas, CBOR codecs, and JSON Schema are all generated from the
   canonical Rust types (Zig types, transitionally) via
   `bun run codegen`.
3. The browser and server load **the same `dreamball.wasm` binary**. No
   platform-specific build, no conditional code paths. A bug in the
   wire format is fixed in one place.
4. Host-supplied randomness flows through one `env.getRandomBytes`
   import. All other crypto is pure functions in the Zig core.

This invariant is reproduced verbatim in `CLAUDE.md §"The cross-runtime
invariant"` — the two documents must remain consistent. This is why
[`ADR-1`](#adr-1-wasm-as-the-cross-runtime-crypto-core) below chose
WASM over FFI and over subprocess.

---

## 3. Runtime map

| Runtime | Consumes | Produces | Role |
|---|---|---|---|
| **Zig CLI** (`zig-out/bin/dreamball`) | argv, `~/.config/dreamball` | `.ball` files, `.ball.json`, signed envelopes, sealed relics | The authoring tool. First-class test surface. |
| **Browser** (Svelte + Threlte) | `.ball` bytes via `fetch`, user input | Rendered views, user interactions, signed commits | The consumer surface. Runs `dreamball.wasm` for parse + verify + validate. |
| **`dreamball-server`** (Bun + Elysia) | HTTP requests, filesystem `.ball` store, `recrypt-server` | HTTP JSON responses, Eden-typed client calls | The authoring service + API. Runs the same `dreamball.wasm` for write ops. |
| **`dreamball` MCP server** (Bun, stdio) | JSON-RPC over stdio from Claude Code / any MCP client | MCP tool responses wrapping CLI commands | The scripting surface for AI agents. |
| **`recrypt-server`** (Rust) | HTTP requests for Guild keyspace proxy-recryption | Recrypted keys for sealed-relic unlock and guild-scoped transmission | The Guild proxy-recryption anchor. Shared across the IdentiKey family. (ML-DSA-87 signing + verify are vendored into the dreamball CLI and dreamball.wasm — no HTTP hop.) |

Each runtime holds different capabilities but shares the same wire format.

### 3.1 Transmittable locator (store keys, not identity)

A **Transmittable** is `{ bucket, filename }` — an object-store locator
for signed `.ball` bytes. It is an app-level adapter, not a wire type
(no `ball.transmittable` envelope, no codegen). The bytes are
`application/ball+cbor`; the only decode path is `dreamball.wasm`
`verifyBall` then `parseBall`. A DreamBall's identity remains its
Ed25519 fingerprint. `GET /dreamballs/:fp` is unchanged.

Error vocabulary (TypeScript, `src/lib/transmittable.ts`):

| Case | Code |
|---|---|
| Object missing | `transmittable-not-found` |
| wasm verify failed | `transmittable-verify-failed` |
| wasm parse failed | `transmittable-parse-failed` |

Empty query params are "no locator", not a not-found. Secret keys never
ride this path. Fetch implementation is `add-transmittable-fetch`.

The viewer-shell mesh (Star Tamagotchi glTF at
`/characters/star-tamagotchi.glb`) is independent of this locator: the
`shell` lens always loads that URL; inner contents arrive later via the
locator. Path, capsule, AvatarModel auto-fit, and Blender provenance:
[`character-dreamball-rendering.md`](character-dreamball-rendering.md).

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
  vendored liboqs subset linked directly into the `dreamball` CLI (see
  `src/ml_dsa.zig`). No HTTP hop, no `recrypt-server` dependency for
  signing — the native binary holds ML-DSA-87 locally.
- Required by the `DreamBall.isFullySigned(.strict)` policy.
- Signing flow on the server: `dreamball-server` subprocesses the native
  `dreamball` binary, which signs with both Ed25519 + ML-DSA-87 in one
  pass using the hybrid key file format (see `src/key_file.zig`).
- **Browser verification runs locally.** `dreamball.wasm` ships the
  ML-DSA-87 verify path too (same vendored liboqs subset, compiled
  for wasm32-freestanding via shim headers in
  `vendor/liboqs/wasm_shims/`). Both sigs check against the
  envelope's `identity` / `identity-pq` core fields. No network hop
  required for verify.

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
  2.  dreamball-server subprocesses `dreamball mint --type agent --name ...`
                       │
                       ▼
  3.  Native CLI generates a hybrid Ed25519 + ML-DSA-87 keypair,
       signs the envelope with both, writes <fp>.ball + <fp>.ball.key
       (key file = raw recrypt.identity envelope, CBOR tag 200)
                       │
  4.  dreamball-server reads the envelope + key file, moves them to
       data/dreamballs/<fp>.ball, data/keys/<fp>.key (0600)
                       │
  5.  client ← 200 { fingerprint, dreamball, secret_key_b58 }
```

Per-DreamBall signing-key material is stored as a raw `recrypt.identity`
Gordian Envelope (CBOR tag 200, dCBOR canonical form). The envelope carries
ed25519 + ML-DSA-87 keypairs as populated assertions; PRE keys are absent
(Dreamball's signing flow doesn't participate in proxy recryption directly).
`decode` requires both ed25519 and ML-DSA secrets present and rejects
anything else. See `docs/decisions/2026-04-21-identity-envelope.md` and
`vendor/recrypt-identity-fixtures/` for the interop contract.

After this mint response, the server will never emit `secret_key_b58`
again. The client holds the secret; server-side it stays on-disk at
`0600`.

### 5.2 Load a DreamBall in the browser

```
  1.  browser → GET /dreamballs/:fp
                       │
  2.  dreamball-server reads data/dreamballs/<fp>.ball, returns CBOR bytes
                       │
  3.  browser → parseBall(bytes)  (via dreamball.wasm, same binary as server)
                       │
  4.  browser → valibot.parse(DreamBallSchema, result)
                       │  ↳ schema drives runtime validation
                       ▼
  5.  renderer receives typed DreamBall → picks lens → renders
                       │
  6.  (optional) browser → verifyBall(bytes)
                       │  ↳ both Ed25519 AND ML-DSA-87 verified locally
                       │    (no network hop; see ADR-3 below)
```

### 5.3 Unlock a sealed Relic (Tier 3)

```
  1.  client holds member keypair for guild G
                       │
  2.  client → POST /relics/:id/unlock { guild_member_key_b58 }
                       │
  3.  dreamball-server loads sealed bundle (DragonBall), extracts the
       recrypt-wrapped payload from the first attachment slot
                       │
  4.  dreamball-server → recrypt-server POST /recrypt
                       { wrapped, from_guild_fp, to_member_fp }
                       │
                       ▼
  5.  recrypted ciphertext returned
                       │
  6.  client decrypts locally with the member key
                       │  (the plaintext is the inner DreamBall envelope
                       │   bytes; server never sees it)
                       ▼
  7.  browser → parseBall(inner) → render via OmnisphericalLens reveal
```

---

## 6. The MCP documentation layer

Every AI agent that meets a `dreamball-server` can discover its full API
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
  `joinGuildWasm`, `parseBall`, `verifyBall`, ...) with their
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
│   ├── main.zig                 # `dreamball` CLI entry
│   ├── wasm_main.zig            # `dreamball.wasm` entry
│   ├── cli/                     # CLI commands (mint/grow/seal/...)
│   ├── wasm-host/               # Wasm action host (D-020, D-032)
│   │   ├── main.zig             # CLI target driver (platform shims here)
│   │   ├── runtime.zig          # Platform-pure host runtime
│   │   ├── imports.zig          # dreamball.* import implementations
│   │   ├── failure_paths.zig    # SEC1/SEC4/NFR7 failure handling
│   │   └── build_guest.zig      # Guest wasm build helper
│   ├── lib/                     # Svelte 5 renderer library
│   │   ├── index.ts
│   │   ├── generated/           # AUTO — types.ts, schemas.ts, cbor.ts
│   │   ├── components/          # DreamBallViewer, DreamBallCard, ...
│   │   ├── lenses/              # 8 lenses
│   │   ├── backend/             # DreamballBackend, MockBackend, HttpBackend
│   │   ├── playcanvas/          # Splat renderer setup
│   │   ├── splat/               # Splat media-type routing
│   │   └── wasm/                # dreamball.wasm + loader.ts
│   ├── routes/                  # SvelteKit showcase app
│   └── stories/                 # Storybook stories
├── schemas/                     # Generated JSON Schema artifacts (zig build schemagen); fp-pinned (D-029). Superseded D-018 treated these as canonical sources — see §2
│   ├── root-2.0.0.json          # Root DreamBall wire types
│   ├── memory-palace-0.1.0.json # Memory Palace archiform
│   └── .pins/                   # blake3 fp pins (one per schema)
├── tools/
│   ├── codegen-common/          # codegen_common.zig — shared ArchiformCtx + schema-read/pin + blake3/log
│   ├── schema-gen/              # JSON Schema → core generated outputs (D-030); no graph-store DDL
│   │   ├── main.zig             # Orchestrator: reads schema, verifies pin, dispatches
│   │   ├── gen_zig.zig          # → src/protocol_v2.zig extensions
│   │   ├── gen_ts.zig           # → src/lib/generated/types.ts
│   │   ├── gen_valibot.zig      # → src/lib/generated/schemas.ts
│   │   ├── gen_cbor.zig         # → src/lib/generated/cbor.ts
│   │   └── …                    # + per-archiform projectors: gen_cli / gen_ts_client / gen_mcp_tools / gen_capabilities
│   ├── graphstore-schema/       # gen_cypher.zig → src/memory-palace/schema.cypher (graph-store-owned; `zig build graphstore-schema`, Dreamball-9dq)
│   └── mcp-server/              # stdio MCP server wrapping the CLI
├── dreamball-server/                # Bun + Elysia HTTP server
│   └── src/                     # WASM loader, routes, store, MCP docs
├── scripts/
│   ├── cli-smoke.sh             # CLI end-to-end test
│   ├── server-smoke.sh          # dreamball-server end-to-end test
│   └── spike-wasm-env.ts        # Proves WASM env-import plumbing
└── tests/
    └── e2e-cryptography.sh      # Full real-crypto integration test
```

---

## 8. Architectural decision records

Short form. Full context in
[`.omc/plans/2026-04-19-dreamball-server-storybook-mldsa-recrypt.md`](../.omc/plans/2026-04-19-dreamball-server-storybook-mldsa-recrypt.md)
§6.

### ADR-1: WASM as the cross-runtime crypto core

**Decision.** Compile the Zig protocol core to a single `dreamball.wasm`.
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

### ADR-2: Elysia + Eden + Valibot for `dreamball-server`

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
  `recrypt-server` dependency for signing. `dreamball mint` / `grow` /
  `transmit` / `seal-relic` all sign locally with Ed25519 +
  ML-DSA-87.
- **WASM** (`dreamball.wasm`) links the same C sources for wasm32-freestanding
  via four shim headers (`<string.h>`, `<stdlib.h>`, `<stdio.h>`,
  `<limits.h>` in `vendor/liboqs/wasm_shims/`) and a static-arena
  allocator (`vendor/liboqs/src/dreamball_stubs_wasm.c`). The linker's
  dead-code elimination drops the sign + keypair paths, leaving only
  the verify-reachable subset — a small, budgeted increment over the
  Ed25519-only baseline. Browser verification is local and hybrid — no
  network hop required.

**Prior decision (superseded).** An earlier version of this ADR
delegated ML-DSA to `recrypt-server` over HTTP. The motivation was a
pessimistic WASM size estimate from Emscripten's full liboqs build. The
verify-only spike came in far smaller — an order of magnitude — making
local verify strictly preferable. Signing was already local on the native
side once we vendored liboqs in `7cdf5eb`. `recrypt-server` still
exposes `POST /sign/ml-dsa` / `POST /verify/ml-dsa` endpoints for
cross-project use, but Dreamball does not call them.

**Consequences.** Offline signing works end-to-end via the native
CLI; offline verification works end-to-end in any runtime. The
protocol's hybrid-PQ promise is fulfilled without a
network-dependent trust anchor. Browser bundle cost is a small one-time
increment over the wire, within the size budget.

### ADR-4: Storybook as the developer testing environment

**Decision.** Storybook stories are the primary UI development + testing
environment. Every lens has a dedicated story with interactive Controls;
every DreamBall type has a "tour" story; play functions cover
interactive flows.

**Alternatives rejected.** Hand-rolled dev routes (more work, less
interactive), Ladle (scaffold is already Storybook).

**Consequences.** Stories become a maintenance surface — each new lens
or type adds stories. Acceptable given the 8-lens × 7-type ceiling.

### ADR-5: Sprint-002 promoted decisions (D-021 through D-025, D-028)

These decisions were promoted from sprint-001 retrospective emergents and
drafted ADRs to the numbered sequence in sprint-002. Each carries an
ADR-lite entry in
[`docs/sprints/002-archiform-foundation/architecture-decisions.md`](sprints/002-archiform-foundation/architecture-decisions.md).
What changed in each:

**D-021 — LadybugDB transactional model (logical commit + replay-from-CAS)**
Formalises the "stage-then-promote" mutation primitive that was rediscovered
across 5 sprint-001 stories. Every mutation: (1) stages writes to a
content-addressed bundle, (2) appends a single ActionLog row as the logical
commit, (3) replays from the ActionLog on recovery. Idempotency keys
(`blake3(agent_fp || subject || predicate || object)`) make replay no-op for
already-applied state. Closes the relitigation pattern — all sprint-002
mutation stories inherit this protocol.

**D-022 — Bridge pattern (Zig staging → Bun bridge → promote-on-success)**
Formalises the canonical mutation primitive as: Bun caller invokes Zig CLI
with `--staging-dir=<tmp>`; Zig writes envelopes to staging; on success, Bun
atomically renames staging into live CAS path; ActionLog append happens after
promote. Wasm actions compose the same primitive: `dreamball.emit_action_envelope`
writes to a per-invocation staging area; the host promotes after the action
returns. New mutations follow this template — it is the only sanctioned
write path.

**D-023 — Dual-sig via `dreamball.wasm` `signActionEnvelope` export**
Closes the sprint-001 silent-substitution debt (S4.4 / S5.5) where derived-fp
sentinels were substituted for real signatures. `dreamball.wasm` now exports
`signActionEnvelope(keypair_bytes, payload_bytes) → ed25519_sig_bytes` — the
single seam through which all signatures are produced (Ed25519 for sprint-002;
PQ dual-sig deferred to the security pass per SEC6). The wasm action host's
`dreamball.emit_action_envelope` calls this export internally; guest code
cannot forge signatures because it has no access to private key material.

**D-024 — Spike-before-promote default for new shaders / materials / wasm actions**
Any new shader, material, lens, or wasm action that introduces an unfamiliar
host or API surface ships a spike story first (proof-of-concept on one minimal
end-to-end case). The spike's deliverable is the architectural commitment that
follow-up stories inherit; follow-ups do not dispatch until the spike lands
green. Applied in sprint-002 to: the first wasm action (Cluster E), the root
JSON Schema codegen (Cluster A), and CBOR golden vector authoring (FR3).

**D-025 — Forward-declare consumer seam contracts in `architecture-decisions.md`**
Cross-epic contracts (shapes consumed by ≥2 epics or clusters) MUST be
authored in `architecture-decisions.md` before the producing story dispatches.
Adding a new entry to such a contract during story execution is an
architecture-decision event, not a story-execution decision. Sprint-002
subjects: `dreamball.*` import surface (D-033), action manifest shape
(D-019/D-035), generated TS client API surface (D-031), bridge pattern
signature (D-022), pin file format (D-029), wasm host import contract (D-032).

**D-028 — Triple-native KG storage (revises D-016)**
Pre-sprint-002 the oracle Agent's KG lived in `Agent.knowledge_graph STRING`
(JSON array of triples). Replaced with native graph storage: `Triple` node
table with `fp = blake3(agent_fp || subject || predicate || object)` as MERGE
key, `HAS_KNOWLEDGE` rel from `Agent` to `Triple`, and `Agent.knowledge_graph`
field removed. CBOR remains the wire format on ActionLog envelopes; Triple rows
are derived state replayable from ActionLog. The generated `schema.cypher` must
match the post-sprint-002 hardened shape.

---

## 9. Wasm action host (D-020, D-032)

*See also `docs/dreamball-imports.md` for the full import contract (D-033).*

The wasm action host is the runtime that loads and executes archiform action
modules. It is implemented as a single Zig codebase under `src/wasm-host/`
that compiles to two targets:

- **CLI target** — `dreamball` binary (Zig + WASI). Ships in sprint-002.
- **Browser target** — `dreamball.wasm` host (WebAssembly without WASI).
  Sprint-003+ deliverable; the source is shared today, no new host code
  will be required when the browser target ships.

### 9.1 Verify-before-instantiate (SEC4, D-031)

Every wasm action module is verified by `blake3(wasm_bytes)` before the
host instantiates it. The blake3 fingerprint must match the fp declared in the
action manifest (which lives inside the schema body, itself signed by the
archiform publisher via aspects.sh). This is the complete trust chain (D-031):

```
publisher signs schema body (aspects.sh)
       ↓
schema body declares wasm fps in action manifest
       ↓
host: blake3(fetched_wasm_bytes) == declared_fp   ← SEC4 gate
       ↓
host instantiates module
```

Verification failure is a hard error. No fallback execution occurs. The
structured log emits `outcome: "fp_mismatch"`.

### 9.2 Memory budget (NFR7)

| Limit | Value |
|---|---|
| Initial per-instance | 16 MiB |
| Hard ceiling | 64 MiB |

Exceeding the hard ceiling causes an OOM trap. The structured log emits
`outcome: "trap"` with the memory fault detail.

### 9.3 Import surface (D-033)

Guests declare imports under the `dreamball` namespace exclusively:
`extern "dreamball" fn <name>(...)`. The host validates the import table
against the allowlist before any guest code runs (SEC1). Exactly **5 imports**
are available for sprint-002:

| Import | Purpose |
|---|---|
| `dreamball.fp` | blake3 fingerprint of a guest memory slice |
| `dreamball.encode_cbor` | canonical dCBOR byte-string encoding |
| `dreamball.read_node` | read a DreamBall node from the host node store |
| `dreamball.emit_action_envelope` | sign + promote an action result envelope |
| `dreamball.now_ms` | monotonic millisecond timestamp |

Any import outside this allowlist produces `outcome: "import_violation"` and
the module is refused. Adding a 6th import requires an ADR amendment (D-025,
D-033) — not a story-execution event.

For the full per-import arity, error semantics, calling convention, and
host-trust notes see [`docs/dreamball-imports.md`](dreamball-imports.md).

### 9.4 Structured invocation events (NFR11)

Every invocation emits a structured-log JSON line to stderr (parseable by CI
and smoke gates). The `outcome` field is a closed enum:

| Value | Meaning |
|---|---|
| `"ok"` | Invocation completed successfully |
| `"trap"` | Guest trapped (bad memory access, OOM, sign failure) |
| `"import_violation"` | Guest declared an import outside the allowlist |
| `"fp_mismatch"` | `blake3(wasm_bytes)` ≠ manifest-declared fp |

---

## 10. Codegen flow (D-029, D-030)

The codegen pipeline flows **outward from the canonical Rust types**
(2026-08-06 ADR — see §2). TS types, Valibot schemas, CBOR codecs, JSON
Schema, and the Cypher DDL are all generated artifacts. `serde` +
`schemars` derives replace the Zig comptime `@typeInfo` generator that
the 2026-06-25 ADR called for and that was never built.

> **Transitional:** the diagram below is what the build runs *today*, and
> it is being replaced by epic `Dreamball-y4t`. The `schema-gen` tool
> reads the *vendored, pinned* `schemas/*.json` as an intermediate and
> the generator bodies are hardcoded strings; the schemas are kept
> byte-consistent with the (transitionally canonical) Zig types by the
> pin + byte-equivalence gate. Do not extend this pipeline — the
> comptime-reflection generator (`Dreamball-m97.2`) is dissolved, not
> deferred.

**Known open question — the projector layer.** `serde` + `schemars`
cover serialization and JSON Schema. They do *not* cover the
per-archiform projectors (`gen_cli`, `gen_ts_client`, `gen_mcp_tools`,
`gen_capabilities`, `gen_cypher`), which emit a CLI surface, an Eden
client, MCP tool definitions, capability descriptors and Cypher DDL.
Whether those become a hand-written Rust compiler is being spec'd
separately; see the Consequences section of the 2026-08-06 ADR, which
names this as the decision's principal risk.

```
schemas/<archiform>-<version>.json        ← vendored, pinned (transitional)
          │
          ▼  (blake3 verify at codegen entry)
schemas/.pins/<archiform>-<version>.fp    ← vendor-integrity pin (D-029)
          │
          ▼
tools/schema-gen/main.zig                 ← orchestrator (D-030)
  reads JSON Schema, verifies pin,
  dispatches generators in order,
  emits structured-log per phase (NFR10)
          │
    ┌─────┼─────────────┬───────────┐
    ▼     ▼             ▼           ▼
gen_zig gen_ts     gen_valibot  gen_cbor
    │     │             │           │
    ▼     ▼             ▼           ▼
src/lib/generated/
  ├── types.ts        ← gen_ts
  ├── schemas.ts      ← gen_valibot
  └── cbor.ts         ← gen_cbor
  (Zig types folded into protocol_v2.zig ← gen_zig; per-archiform
   projectors gen_cli / gen_ts_client / gen_mcp_tools / gen_capabilities
   also run in the archiform pass)
```

**Graph-store DDL is NOT emitted by core** (Dreamball-9dq — graph-store/1 §2
leak fix). A separate graph-store-owned orchestrator (`tools/graphstore-schema/`,
run by `zig build graphstore-schema` after `schemagen`, both chained by
`bun run codegen`) emits `src/memory-palace/schema.cypher` via `gen_cypher.zig`.
The shared `ArchiformCtx` + schema-read/pin + blake3/log helpers live in the
neutral `tools/codegen-common/codegen_common.zig`, so neither core nor the
per-archiform generators depend on the graph store's DDL generator.

**Pin verification** runs twice: (1) `bun run schemas:verify` (called by
`bun run codegen` before dispatch) and (2) inside `main.zig` itself
(structured-log phase `pin-verify`). Both must pass; `codegen` fails hard
on mismatch.

**Per-target provenance headers** (NFR9): every generated file carries a
`// AUTO-GENERATED by tools/schema-gen@<date>` header. Do not edit by hand;
regenerate via `bun run codegen`.

**CBOR semantics never live in TypeScript**: `gen_cbor.zig` emits TS shims
that delegate to the CBOR primitives exposed via `dreamball.wasm`. It does
not re-implement CBOR semantics in TypeScript. Post-port those primitives
come from `dcbor` / `bc-envelope` compiled into the same wasm binary; the
shim contract is unchanged.

---

## 11. Sentinel debt closure and PQ forward-declaration (D-023, FR13, SEC3, SEC6)

Sprint-002 (Stories 6.1 + 6.2) closed the silent-substitution debt from
sprint-001 where derived-fp sentinel values were substituted for real Ed25519
signatures at two call sites (`oracle.ts oracleSignAction` and
`store.recordTraversal`). Both sites now call `dreamball.wasm`'s
`signActionEnvelope` export (D-023), the single seam through which all
action-envelope signatures are produced. FR13 and SEC3 are satisfied.

**PQ dual-sig (ML-DSA-87) is explicitly deferred to the security pass.**
Sprint-002 ships Ed25519-only single signatures per the 2026-04-25 steering
decision. The `signActionEnvelope` export is parameterised to accept a second
signer when the security pass adds ML-DSA-87 support (SEC6). No code path
in sprint-002 produces or validates ML-DSA-87 signatures through the action
signing seam; that work is tracked in `docs/known-gaps.md` under the
security-pass section.

---

## 12. The three canonical files

Any contributor (human or AI) who reads these three files and this
`ARCHITECTURE.md` has enough context to make meaningful changes to the
codebase:

1. `docs/PROTOCOL.md` — what the wire format *is*.
2. `docs/VISION.md` — what the protocol is *for*.
3. `CLAUDE.md` — how to work on it.

This document ties them together.

---

## 13. Where to add a new envelope type (runbook)

1. Add or change the field shape in the canonical types. Post-port
   (2026-08-06 ADR) that means the Rust types with `serde` + `schemars`
   derives; **while epic `Dreamball-y4t` is in flight** it is still the
   Zig structs in `src/protocol.zig` / `src/protocol_v2.zig`. Either way
   there is exactly one source and everything else descends from it. Do
   **not** hand-author JSON Schema or other generated files.
2. Run `bun run codegen` (calls `schemas:verify` then `zig build schemagen`).
   This regenerates `src/lib/generated/types.ts`, `schemas.ts`, `cbor.ts`,
   and `src/memory-palace/schema.cypher`.
3. Update the vendored JSON-Schema fixture + its pin
   (`bun run schemas:pin schemas/<file>.json`) so the byte-equivalence gate
   matches the Zig types (transitional, until the reflection generator lands).
4. Add the encoder in `src/envelope.zig` or `src/envelope_v2.zig`.
5. Add the decoder in `src/envelope.zig` (extend `decodeDreamBall`).
6. Update `docs/PROTOCOL.md §12` with the wire-format description.
7. Run `zig build wasm`.
8. Update `docs/VISION.md §12` (the reference types) if the type changes
   the taxonomy story.
9. Add a Storybook story under `src/stories/types/`.
10. Run all 7 gates: `zig build test`, `zig build smoke`,
    `bun run check`, `bun run test:unit -- --run`,
    `scripts/cli-smoke.sh`, `scripts/server-smoke.sh`,
    `tests/e2e-cryptography.sh` — all must pass.
11. Update `docs/ARCHITECTURE.md §7` (this file, directory guide) if
    you added new top-level directories.

If all 11 steps pass in one commit, you haven't drifted.
