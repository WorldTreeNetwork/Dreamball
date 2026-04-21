## Project Configuration

- **Language**: TypeScript
- **Package Manager**: bun
- **Add-ons**: prettier, eslint, vitest, storybook, mcp

---

# CLAUDE.md — Dreamball project

## Read first

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the runtime map.
  How the Zig core, WASM binary, CLI, jelly-server, Svelte lib, and
  recrypt-server fit together. Start here for the mental model.
- [`docs/PROTOCOL.md`](docs/PROTOCOL.md) — authoritative wire format.
- [`docs/VISION.md`](docs/VISION.md) — the *why* behind the code. Living
  document; contribute to it as you learn.
- [`docs/known-gaps.md`](docs/known-gaps.md) — residual `TODO-CRYPTO`
  markers and deferred work with tracking entries.
- [`../recrypt/docs/wire-protocol.md`](../recrypt/docs/wire-protocol.md) —
  sibling crypto methodology; our conventions inherit from this.

## The cross-runtime invariant

**There is one place the wire format lives: `src/*.zig`.** Every other
surface (CLI, `jelly.wasm`, Svelte lib, `jelly-server`, MCP docs) is
derived from the Zig code. Concretely:

- No TypeScript code encodes or decodes CBOR by hand — it goes through
  the WASM module.
- No hand-maintained schemas exist anywhere. `types.ts`, `schemas.ts`
  (Valibot), and `cbor.ts` are all generated from
  `tools/schema-gen/main.zig`. Regenerate via `bun run codegen`.
- The browser and server load the same `jelly.wasm` binary. Host-supplied
  randomness via one `env.getRandomBytes` import is the entire runtime
  seam; see [`docs/VISION.md §14`](docs/VISION.md) and ADR-1 in
  [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

If you find yourself writing a second implementation of something the
Zig core already does — stop. Regenerate from the Zig side instead.

## Operating principle — document the why, not only the what

When you do implementation work on this project, **also write down the
rationale** in `docs/**/*.md`. Code alone records decisions, not reasons.
The vision, constraints, aesthetic commitments, and architectural
trade-offs that led to the current shape belong in the docs tree — in the
appropriate file, or as a new one — next to the code that realises them.

Specifically:

- Feature work that changes the protocol surface → update `docs/PROTOCOL.md`
  (or an open-questions section if the direction isn't settled).
- Insights about what DreamBalls *are* or how they should compose →
  `docs/VISION.md`.
- Architectural trade-offs, library choices, or crypto decisions → a dated
  note under `docs/decisions/` (create the dir when first needed).
- Operational / runbook content (how to build, how to release) → `README.md`
  or a new `docs/ops/` note.

If you are about to write a line of code whose justification is non-obvious
and not already documented, **pause, write the justification, then write the
code**. A one-paragraph note that captures the *why* is cheap to produce and
extremely expensive to reconstruct later from Git blame.

## Build

Zig 0.16.0 + Bun. See `README.md` for the full command list.

**Zig side:**
- `zig build` — compile library + `jelly` CLI
- `zig build test` — unit tests (≥ 51 passing)
- `zig build smoke` — CLI end-to-end integration test
- `zig build wasm` — produce `src/lib/wasm/jelly.wasm` (≤ 200 KB raw, ≤ 64 KB gzipped; ships ML-DSA-87 verify)
- `zig build schemagen` — regenerate `src/lib/generated/*.ts`

**Bun side:**
- `bun install` — install JS/TS deps
- `bun run check` — svelte-check (must be 0 errors)
- `bun run test:unit -- --run` — Vitest
- `bun run storybook` / `bun run build-storybook` / `bun run test-storybook`
- `bun run build` — library + showcase build
- `bun run dev:server` — jelly-server (Elysia) on :9808
- `bun run demo` — jelly-server + Vite dev server in parallel
- `bun run codegen` — alias for `zig build schemagen`

**Integration gates:**
- `scripts/cli-smoke.sh` — Zig CLI end-to-end
- `scripts/server-smoke.sh` — HTTP jelly-server end-to-end
- `tests/e2e-cryptography.sh` — crypto pipeline (mock or real via `RECRYPT_SERVER_URL`)

Every commit must keep every gate green. CI (`.github/workflows/ci.yml`)
runs them all.

## Style

- Match recrypt's naming and terminology verbatim when the concept overlaps
  (signatures, envelopes, fingerprints, stages). If you find yourself
  inventing a new word, check recrypt first.
- Keep `docs/PROTOCOL.md` prescriptive and `docs/VISION.md` descriptive.
  They are different registers for different readers.
- Tests live inline in `src/**.zig` (`test "…"` blocks). Integration tests
  live in `scripts/cli-smoke.sh`.

## Deferred / known gaps

Tracked in `README.md` under "Roadmap". When you resolve one, remove the
bullet and reflect the change in `docs/` as above.

You are able to use the Svelte MCP server, where you have access to comprehensive Svelte 5 and SvelteKit documentation. Here's how to use the available tools effectively:

## Available Svelte MCP Tools:

### 1. list-sections

Use this FIRST to discover all available documentation sections. Returns a structured list with titles, use_cases, and paths.
When asked about Svelte or SvelteKit topics, ALWAYS use this tool at the start of the chat to find relevant sections.

### 2. get-documentation

Retrieves full documentation content for specific sections. Accepts single or multiple sections.
After calling the list-sections tool, you MUST analyze the returned documentation sections (especially the use_cases field) and then use the get-documentation tool to fetch ALL documentation sections that are relevant for the user's task.

### 3. svelte-autofixer

Analyzes Svelte code and returns issues and suggestions.
You MUST use this tool whenever writing Svelte code before sending it to the user. Keep calling it until no issues or suggestions are returned.

### 4. playground-link

Generates a Svelte Playground link with the provided code.
After completing the code, ask the user if they want a playground link. Only call this tool after user confirmation and NEVER if code was written to files in their project.

Always use bun for everything - for package management, short scripts, etc, except where we use zig.
