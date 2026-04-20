---
title: DreamBall v2 — Typed aspects, renderer, transmission, keyspace guilds
created: 2026-04-18
status: validated
scope_tier: mvp
---
# PRD: DreamBall v2

## Problem Statement

DreamBall v1 shipped a signed, evolvable container with three axes (look/feel/act) and a dCBOR wire format shared with recrypt. v1 lacks the *behaviour* needed to be useful as an NFT-like, MTG-style collectible agent/avatar: it has no way to distinguish an *avatar* from an *agent* from a *skill* from a *relic* from a *field* from a *group*. It has no runtime. It has no renderer. Memory, knowledge, emotional state, and transferable skills have no protocol slots. There is no way to transmit a skill between actors. There is no group/keyspace abstraction for delegated access. And there is no browser-reachable way to load, render, or interact with a DreamBall — today the only tool is the Zig CLI.

The v2 sprint closes all of those gaps in one coordinated cut, anchored by a single end-to-end demo ("Demo D") that exercises every new capability.

## User Personas

**P0 — Observer / audience.** A user whose browser tab shows someone else's worn DreamBall. They see the avatar, maybe a thumbnail card, possibly a field/environment — but never the agent's secrets. Low technical level; they're passive viewers. Pain: today there's no way to render a DreamBall at all, let alone one someone else is wearing.

**P1 — DreamBall-as-agent consumer.** A runtime (e.g., a chat app, a game engine) that loads a DreamBall and instantiates it as an agent — using the embedded model reference, personality prompt, memory graph, and transferable skills. Medium-to-high technical; calls the MCP server or the TypeScript lib. Pain: nowhere in v1 to put `model`, `memory`, `skills` beyond a single flat `act` slot.

**P2 — End-user wearer.** A person who picks up an Avatar DreamBall and "wears" it. They speak/move and their avatar representation animates with them — the "jelly bean" metaphor, where the DreamBall sits on their character like an inventory object but is expressive. Low technical. Pain: no concept of wearing exists.

**P3 — Aspect author.** A creator minting new DreamBalls. Uses either the extended Zig CLI or the Svelte web authoring UI. Medium technical. Pain: v1 CLI only knows about the monolithic `jelly.dreamball` envelope; it can't directly produce any of the six typed variants.

## User Journeys

**Journey 1 — Transmission (Alice's Tool → Bob's Agent, via Guild).**
Alice uses `jelly mint --type=tool --out alice-tool.jelly --name "haiku-compose"` to produce a Tool DreamBall carrying a skill definition. Bob already has `bob-agent.jelly`, an Agent-type container with `model`, `personality-master-prompt`, and a `memory` slot. Both are members of a Guild whose fingerprint is `g:abc…`. Alice runs `jelly transmit alice-tool.jelly --to=bob-fp --via-guild=g:abc…`. The jelly server (A2 mock-crypto stub, real wire-format) records the transmission. Bob's runtime re-fetches his Agent, sees the newly attached Tool in the Agent's `skills` list (via the Guild-delegated capability), and the renderer's skill-list lens shows the new skill lighting up.

**Journey 2 — Unlock (Relic reveal).**
A sealed Relic DreamBall is published at a known URL. Any observer can download it — it's an opaque DragonBall blob. A Guild member who holds the Guild's unlock credential runs `jelly unlock mysterious.jelly --guild=g:…`. The server mock-decrypts (real zip/dCBOR framing, mocked crypto), and the renderer's omnispherical viewer animates the reveal: the sealed dragon peels open, the inner DreamBall (Avatar + Field combo) fades in, and the lens switches to show what was sealed.

**Journey 3 — Wearer + Observer.**
A wearer loads an Avatar DreamBall in their browser tab and hits "wear". Their character (or stand-in avatar) now displays the DreamBall's visual aspect. In a second browser tab (same machine or different), an observer connects to the same session. The observer sees the wearer's avatar animated with whatever input the wearer feeds (text, webcam, inventory interaction) but does *not* see the Agent memory or any private slots. The wearer's own view shows the full Agent panel (memory graph, emotional register) in addition to the Avatar.

## Success Metrics

| Metric | Target | Measurement |
|---|---|---|
| Demo D runs end-to-end from a clean checkout | 100% pass | `scripts/cli-smoke.sh` + `bun run test` both green; manual Demo D recorded as a single-take screen capture |
| Protocol v2 envelope types | 6 (Avatar, Agent, Tool, Relic, Field, Guild) | `zig build test` covers every type's encode/decode |
| Zig tests: v1 + v2 combined | ≥ 60 passing | `zig build test --summary all` |
| Bun/Vitest tests in the Svelte lib | ≥ 20 passing | `bun run test` |
| CBOR → TS codegen round-trip | byte-identical between hand-authored and generated types for every v2 type | unit test in the codegen module |
| MCP server tool count | ≥ 8 tools exposed | MCP `tools/list` response parsed by a test |
| Renderer lenses | 7 (avatar, thumbnail, knowledge-graph, emotional-state, omnispherical, flat, phone) | Storybook shows one story per lens × type combo where relevant |
| Mocked-crypto markers | 100% of mock sites tagged with a `TODO-CRYPTO: replace before prod` comment | grep count in CI |

## Functional Requirements

### Protocol v2 (FR1–FR14)

FR1. [MVP] The system shall bump `format-version` to `2` in every new envelope type introduced this sprint and keep `format-version: 1` working for v1-shaped envelopes.

FR2. [MVP] The system shall define six typed DreamBall classes: `jelly.dreamball.avatar`, `jelly.dreamball.agent`, `jelly.dreamball.tool`, `jelly.dreamball.relic`, `jelly.dreamball.field`, `jelly.dreamball.guild` — each expressed as a `type` value in the core.

FR3. [MVP] The system shall define a `jelly.memory` envelope (directed-graph memory store with labeled connections including at least `semantic`, `emotional`, `temporal`) and include it as an optional attribute on Agent-type DreamBalls.

FR4. [MVP] The system shall define a `jelly.knowledge-graph` envelope (ambient knowledge, triple-shaped) and include it as an optional attribute on Agent-type DreamBalls.

FR5. [MVP] The system shall define a `jelly.emotional-register` envelope (named emotional axes with current values in a normalized range) and include it as an optional attribute on Agent-type DreamBalls.

FR6. [MVP] The system shall define a `jelly.interaction-set` envelope (captured interaction histories) and include it as an optional attribute on Agent-type DreamBalls.

FR7. [MVP] The system shall define `jelly.guild` as a first-class envelope that carries a Guild fingerprint, a members list (fingerprints), a keyspace reference (recrypt-compatible), and a permission policy per slot (which members can read/write which slots).

FR8. [MVP] The system shall allow a DreamBall of any type to declare Guild membership via a `guild` attribute whose value is a Guild fingerprint; membership grants delegated access per the Guild's policy.

FR9. [MVP] The system shall define a `jelly.relic` envelope that wraps a sealed DreamBall payload plus unlock metadata (which Guild's keyspace can unlock, a reveal-hint string, a sealed-until timestamp).

FR10. [MVP] The system shall define `jelly.transmission` as a signed, auditable record of a Tool's transfer from one party to another DreamBall (source fingerprint, target DreamBall fingerprint, via-guild fingerprint, Tool envelope).

FR11. [MVP] The system shall treat the `.jelly` file as a well-specified zip-like bundle: dCBOR envelope + optional sidecar attachments (textures, splats, embedded scripts), with a canonical header (magic `JELY`, version, flags, seal-type) as already defined in v1 `sealing.zig` extended for v2 attachments.

FR12. [MVP] The system shall preserve dCBOR canonical ordering (smallest-int, sorted map keys, no floats) for every v2 envelope, extending the existing `golden.zig` bytes-lock with v2 golden fixtures.

FR13. [Growth] The system shall define a `jelly.field` envelope carrying omnispherical-grid parameters (pole definitions, three-camera onion layer depths, ambient palette) consumed by the renderer's omnispherical lens.

FR14. [Growth] The system shall allow a `jelly.relic` to nest recursively — a Relic can wrap another Relic — for layered reveals.

### Zig CLI extension (FR15–FR23)

FR15. [MVP] The system shall accept `--type=<avatar|agent|tool|relic|field|guild>` on the `mint` command and produce the correct typed envelope for each.

FR16. [MVP] The system shall add a `transmit <tool.jelly> --to=<fp> --via-guild=<fp> --out=<transmission.jelly>` command that produces a `jelly.transmission` record.

FR17. [MVP] The system shall add a `join-guild <dreamball.jelly> --guild=<guild.jelly> --key=<keyfile>` command that appends a Guild membership attribute and re-signs the DreamBall.

FR18. [MVP] The system shall add a `seal-relic <inner.jelly> --for-guild=<guild.jelly> --out=<sealed.jelly>` command that wraps a DreamBall inside a `jelly.relic` envelope using mocked encryption with a clear `TODO-CRYPTO` marker.

FR19. [MVP] The system shall add an `unlock <relic.jelly> --guild=<guild.jelly> --key=<keyfile> --out=<inner.jelly>` command that reverses `seal-relic` (mocked decrypt).

FR20. [MVP] The system shall keep every v1 command (`mint`, `grow`, `seal`, `unseal`, `show`, `verify`, `export-json`, `import-json`) working on v1 envelopes.

FR21. [MVP] The system shall extend `show` with type-aware pretty-printing: displays the slot surface relevant to the DreamBall's type.

FR22. [MVP] The system shall extend `verify` to validate type-specific invariants (e.g., a Relic must carry a `sealed-payload`; a Guild must have at least one member).

FR23. [Growth] The system shall add `inventory` — a command that lists DreamBalls in a local directory, grouped by type.

### CBOR → TypeScript codegen (FR24–FR27)

FR24. [MVP] The system shall provide a Zig program (`tools/schema-gen`) that reads the protocol schema (derived from `src/protocol.zig` + `src/envelope.zig`) and emits `src/lib/generated/types.ts` containing TypeScript types for every v2 envelope.

FR25. [MVP] The generated TypeScript shall include CBOR encode/decode helpers per type so the Svelte lib can round-trip envelopes without hand-written serialization.

FR26. [MVP] The generated TypeScript shall be checked into the repo (not generated at install time) with a `bun run codegen` script to refresh it.

FR27. [Growth] The generator shall emit Storybook-compatible type examples (one canonical instance per type) for the Svelte lib's Storybook.

### Jelly MCP server (FR28–FR31)

FR28. [MVP] The system shall ship an MCP server (stdio transport) exposing at minimum: `mint_dreamball`, `transmit_skill`, `seal_relic`, `unlock_relic`, `join_guild`, `list_dreamballs`, `show_dreamball`, `verify_dreamball`.

FR29. [MVP] Each MCP tool shall be thin — it wraps the Zig `jelly` CLI via subprocess and returns structured output so an AI agent can compose DreamBalls interactively.

FR30. [MVP] The MCP server shall be invocable from Claude Code via an entry the user can add to their `.mcp.json` or `settings.json` (documented in README).

FR31. [Growth] The MCP server shall support a `describe_protocol` tool that returns the v2 type taxonomy + slot list for LLMs that haven't seen the spec.

### Svelte/Threlte renderer library (FR32–FR42)

FR32. [MVP] The system shall publish a Svelte 5 library (`src/lib/`) exporting `<DreamBallViewer ball={...} lens="..." />` as the top-level component.

FR33. [MVP] The library shall support seven lenses: `thumbnail`, `avatar`, `knowledge-graph`, `emotional-state`, `omnispherical`, `flat`, `phone`.

FR34. [MVP] The library shall switch lens behavior based on DreamBall type: e.g., the `avatar` lens renders an Avatar DreamBall's visual mesh/texture; the `knowledge-graph` lens renders an Agent's knowledge graph as a 3D force-directed graph; the `omnispherical` lens uses the Field's three-camera onion-layer parameters.

FR35. [MVP] The library shall embed Threlte for WebGL-backed 3D rendering and expose a `preferGpu?: boolean` prop that opts into a WebGPU path when available.

FR36. [MVP] The library shall include a `<DreamBallCard ball={...} />` thumbnail component usable in listing UIs.

FR37. [MVP] The library shall include a `<SealedRelic relic={...} onUnlock={...} />` component that animates a reveal when the `onUnlock` handler returns a resolved inner DreamBall.

FR38. [MVP] The library shall include a `<Wearer ball={...} sourceTrack={...} />` component driving the Avatar's facial/body rig from `sourceTrack` (MediaStream for webcam, text input for typed speech).

FR39. [MVP] The library shall read DreamBalls via a `JellyBackend` interface with a default implementation that HTTP-calls a local `jelly-server` daemon (A2). The backend interface is mockable for Vitest.

FR40. [MVP] Every backend crypto call shall carry a `TODO-CRYPTO: replace before prod` marker; the mock backend produces structurally-correct bytes but does *not* provide cryptographic authenticity.

FR41. [MVP] The library shall include a Storybook story per lens × DreamBall-type pair that makes sense (skipping nonsensical combinations; documented in each story).

FR42. [Growth] The library shall expose a `<Guild guild={...} members={...} />` component visualizing keyspace relationships as a graph.

### Showcase app — Demo D (FR43–FR48)

FR43. [MVP] The showcase SvelteKit app (`src/routes/`) shall include a `/demo` route that walks through Demo D's three scenarios (Transmission, Unlock, Wearer) in a guided UI.

FR44. [MVP] The `/demo/transmission` scenario shall fully exercise: Alice minting a Tool, Bob minting an Agent, both joining a Guild, Alice transmitting, Bob's Agent displaying the new skill. All backed by the mock `jelly-server`.

FR45. [MVP] The `/demo/unlock` scenario shall show a sealed Relic card and animate the reveal when the user clicks "Unlock with Guild Key".

FR46. [MVP] The `/demo/wearer` scenario shall use `getUserMedia` to capture the wearer's webcam, map it to the Avatar rig, and render a second "observer" pane that sees only the Avatar + Field slice (private slots are null in the observer view).

FR47. [MVP] The showcase shall provide a "start the demo server" script (`bun run demo`) that starts the local `jelly-server` daemon and the Vite dev server in parallel.

FR48. [Growth] The showcase shall support a two-tab observer mode where the second tab shares state via BroadcastChannel for local multi-observer testing.

### Permissions & keyspace model (FR49–FR52)

FR49. [MVP] The system shall define Guild keyspaces as compatible with recrypt's keyspace semantics (see `/Users/dukejones/work/Identikey/recrypt/docs/`): a Guild fingerprint is the hash of its keyspace root, and members hold delegated recrypt keys. **Mocked for this sprint** — the data structures exist and round-trip but the recrypt proxy-recryption calls are stubbed.

FR50. [MVP] The system shall support per-slot permission policies on an Agent DreamBall: `look` and `thumbnail` are public; `memory`, `knowledge-graph`, `emotional-register`, `interaction-set`, and any embedded secrets are Guild-restricted by default.

FR51. [MVP] The renderer shall respect per-slot permissions — the observer pane receives only the slots the observer's fingerprint is authorized for.

FR52. [Vision] The system shall support hyperdimensional skill transmission across Guild boundaries via chained delegation (Guild A → Guild B → agent) using recrypt's proxy-recryption — deferred from this sprint.

## Non-Functional Requirements

NFR1. [compatibility] v1 envelopes must continue to round-trip through the v2 encoder/decoder with byte-identical output for unchanged inputs. Enforced via golden-bytes lock in `src/golden.zig`.

NFR2. [portability] The Svelte lib must run in every evergreen browser (Chromium, Firefox, Safari); WebGPU path must degrade gracefully to WebGL.

NFR3. [observability] Every protocol-level error must name the failing envelope's `type` and `format-version` so debuggers can triage.

NFR4. [mocked-crypto hygiene] Every mocked crypto call must carry a `TODO-CRYPTO: replace before prod` comment visible via `rg TODO-CRYPTO`. CI (once configured) should fail if any such marker lacks a resolver issue link after the v2→production cut.

NFR5. [documentation] Every non-obvious protocol decision (new envelope type, slot semantics, policy model) must land in `docs/PROTOCOL.md` (prescriptive) or `docs/VISION.md` (descriptive) in the same sprint.

NFR6. [polyglot hygiene] The repo is polyglot Zig + TypeScript + Svelte. Zig is for the protocol/CLI/MCP-server; TypeScript/Svelte is for the renderer + showcase. No Zig↔TS dependency except through the generated `src/lib/generated/types.ts` artifact and the HTTP backend.

## Scope Boundaries

### In Scope

- Protocol v2 with six typed envelopes plus memory/knowledge-graph/emotional-register/interaction-set/guild/relic/transmission auxiliary types
- Zig `jelly` CLI extended with typed mint, transmit, join-guild, seal-relic, unlock, inventory
- CBOR → TypeScript type generation as a Zig tool
- jelly MCP server (thin wrapper around the CLI)
- Svelte 5 + Threlte renderer library with seven lenses
- SvelteKit showcase app implementing Demo D
- Mocked crypto with uniform TODO markers
- Polyglot monorepo structure (Zig + TS living in the same repo)

### Out of Scope

- Real recrypt proxy-recryption wire-up (replaces the mocks post-sprint)
- Real Ed25519 + ML-DSA-87 signatures in the browser (v1 already has them in Zig; the TS side mocks them)
- WebGPU compute shaders for ML-core offload (WebGPU path is a render-only fast lane)
- Native mobile renderer (web-only; mobile views served via SvelteKit's adaptive layouts)
- Federation / cross-Guild chained delegation (FR52 — Vision tier)
- Built-in neural-net embedding inside DreamBalls (v1 references models by name only; weights-in-the-ball is a future beyond v2)
- A full inventory/marketplace UI (showcase only demonstrates the primitives)

## MVP / Growth / Vision Tiers

### MVP
FR1–FR12, FR15–FR22, FR24–FR26, FR28–FR30, FR32–FR41, FR43–FR47, FR49–FR51, NFR1–NFR6.
Six types in the protocol; CLI + MCP + codegen + renderer + Demo D all working end-to-end with mocked crypto.

### Growth
FR13 (Field omnispherical parameters as first-class envelope), FR14 (nested Relics), FR23 (inventory command), FR27 (Storybook codegen), FR31 (MCP describe_protocol), FR42 (Guild visualizer), FR48 (BroadcastChannel observer).
Polish and depth on the primitives shipped in MVP.

### Vision
FR52 (hyperdimensional chained-delegation transmission across Guild boundaries via real recrypt proxy-recryption).
Requires real crypto wire-up plus multi-hop delegation semantics.

## Constraints

- **Zig 0.16.0** for the protocol, CLI, and MCP server (pinned `minimum_zig_version` in `build.zig.zon`).
- **Bun + TypeScript** for all JS/TS tooling; do not introduce npm/yarn/pnpm.
- **Svelte 5 runes** for component reactivity; no legacy `$:` syntax.
- **Threlte** for WebGL; WebGPU opt-in behind a prop.
- **Mocked crypto only** this sprint; every mock must carry a visible marker.
- **Until done** timeline — no artificial sprint cap. Verification gates (tests green, architect approved) are the stopping condition.
- **Polyglot repo hygiene**: Zig and Svelte code coexist under `src/` with the `sv` template's convention (`src/lib/`, `src/routes/`) layered on top of the Zig convention (`src/*.zig`, `src/cli/`). Both build systems must keep working side-by-side.

## Assumptions & Risks

- **Assumption**: Threlte + Svelte 5 runes are production-ready. *Mitigation*: use the Svelte MCP server's `list-sections` + `get-documentation` tools to confirm each API before use.
- **Assumption**: Zig 0.16's `std.compress.zstd` will gain a compressor mid-sprint. *Mitigation*: the `.jelly` zip-bundle format works uncompressed; compression remains optional and deferred.
- **Risk**: Mocked crypto that *looks* real may leak into production by accident. *Mitigation*: the uniform `TODO-CRYPTO: replace before prod` marker lets CI/grep catch every site; NFR4 makes this explicit.
- **Risk**: The six-type taxonomy may prove too narrow (or too wide) once the renderer is built. *Mitigation*: envelopes are versioned and additive; adding a seventh type in v2.1 requires no breaking change.
- **Risk**: Polyglot dev experience is painful (two test runners, two package managers, two build tools). *Mitigation*: the `scripts/` directory gathers the common recipes (`scripts/cli-smoke.sh`, a new `scripts/all-check.sh`); README documents the workflow clearly.
- **Risk**: The wearer-observer split demos webcam capture, which may fail in some environments. *Mitigation*: fall back to a synthetic "animated avatar" input when `getUserMedia` is denied.

## Open Questions

- Should a DreamBall's type be a single value (current plan) or a bitmask (an envelope could be both an Avatar *and* a Field)? Defer — single-type first; revisit if authoring demands compounds.
- Where does a DreamBall's *memory graph* serialize if it gets large (>1 MB)? Inline dCBOR or content-addressed sidecar? Defer — inline until a real size pressure appears.
- Does the Guild concept need a quorum/threshold signature scheme (m-of-n for unlocks)? Recrypt supports multi-sig; v2 uses single-sig per member with any-member-can-unlock; quorum is Vision.
- Is the omnispherical three-camera model renderable with Threlte's stock cameras, or does it require a custom post-processing shader? To be answered during Phase 6 spike.
- Should the MCP server run as a long-lived daemon or per-invocation? Starting with per-invocation (MCP stdio spawns a fresh process); daemon mode is Growth.

## Existing System Context

- `src/protocol.zig`, `src/envelope.zig`, `src/cbor.zig`, `src/sealing.zig`, `src/signer.zig` — v1 protocol core, 38 tests passing.
- `src/cli/` — v1 CLI command dispatch; extend with v2 commands in the same structure.
- `src/json.zig` — v1 JSON export/import; extend for v2 types.
- `src/graph.zig` — v1 fleet cycle detection; reused for Guild member graphs.
- `src/golden.zig` — canonical byte-lock; extend with v2 fixtures.
- `docs/PROTOCOL.md` — v1 wire format (§4.2 `jelly.look` already marked evolving for form-independence).
- `docs/VISION.md` — living why-doc; §4 needs the omnispherical/three-camera addition.
- `docs/products/dreamball-v2/` — this PRD's home.
- `src/lib/` — Svelte library root (from `sv` template).
- `src/routes/` — SvelteKit showcase app root.
- `src/stories/` — Storybook stories.
- `package.json` / `bun.lock` — JS tooling configured for bun.
- `/Users/dukejones/work/Identikey/recrypt/docs/` — keyspace, wire-protocol, hybrid-encryption references.

## Changelog

- 2026-04-18 — Initial PRD captured from interview. All four interview questions answered (personas, types, demo, tech boundary). Status: validated (writer pass — no critic loop because the answers were crisp and the FR extraction is direct).
