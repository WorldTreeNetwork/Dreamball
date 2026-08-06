## Project Configuration

- **Language**: TypeScript
- **Package Manager**: bun
- **Add-ons**: prettier, eslint, vitest, storybook, mcp

---

# CLAUDE.md — Dreamball project

## Read first

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the runtime map.
  How the Zig core, WASM binary, CLI, dreamball-server, Svelte lib, and
  recrypt-server fit together. Start here for the mental model.
- [`docs/PROTOCOL.md`](docs/PROTOCOL.md) — authoritative wire format.
- [`docs/VISION.md`](docs/VISION.md) — the *why* behind the code. Living
  document; contribute to it as you learn.
- [`docs/known-gaps.md`](docs/known-gaps.md) — residual `TODO-CRYPTO`
  markers and deferred work with tracking entries.
- [`docs/decisions/`](docs/decisions/) — dated architecture decisions.
  The 2026-04-25 set (archiform-registry, json-schema-canonical,
  action-manifest, wasm-runtime) defines the JSON-Schema / archiform /
  wasm shift landing in sprint-002.
- [`../recrypt/docs/wire-protocol.md`](../recrypt/docs/wire-protocol.md) —
  sibling crypto methodology; our conventions inherit from this.

## The cross-runtime invariant

**Rust is the single canonical source for the whole wire format**, which
factors into two parts, both Rust-canonical:

1. **dCBOR encoding algorithm — the Blockchain Commons crates.** `dcbor`
   0.25.2 owns canonical map ordering, integer width rules, and the
   bytes-vs-text discipline; `bc-envelope` 0.43.0 owns envelope framing.
   We *consume* them; we do not reimplement them. Every runtime must
   reproduce the same bytes for the same logical value, and the
   language-neutral golden vectors are what prove it.
2. **Field shapes — the Rust types**, with `serde` + `schemars` derives.
   These are the most expressive representation (defaults, methods,
   exact types), so everything else is *generated downward* from them:
   TS types, Valibot schemas, the CBOR codec (`cbor.ts`), **JSON
   Schema** (`schemas/*.json` — a generated *artifact*, published to
   aspects.sh if/when federation exists), and the Cypher DDL.

This supersedes the 2026-06-25 Zig-canonical ADR, which itself reverted
D-018 (JSON-Schema-canonical). Yes — that is three changes of canonical
medium. See
[`docs/decisions/2026-08-06-rust-canonical.md`](docs/decisions/2026-08-06-rust-canonical.md)
for the honest version: the first two moved the *label* and never
shipped a generator, while `serde` + `schemars` already exist and the
substrate itself is moving to Rust (epic `Dreamball-y4t`). The
most-expressive-medium principle is unchanged; it now points at Rust.

**Zig remains the build system**, scoped to two jobs it is genuinely
good at: the task orchestrator (`zig build test|smoke|wasm` keep
working, shelling out to `cargo` and `bun` — one stable command surface
over three toolchains) and cross-compilation/linking via
`cargo-zigbuild`. Zig no longer compiles protocol artifacts. This keeps
[`2026-05-24-hermetic-musl-default-linux.md`](docs/decisions/2026-05-24-hermetic-musl-default-linux.md)
true verbatim — Linux binaries are still static musl with no system
libc/crt dependency.

Concretely:

- No TypeScript code encodes or decodes CBOR *by hand* — it goes
  through the WASM module or the **generated** `cbor.ts` (generated, so
  it can't drift from the canonical Rust).
- **To add or change a wire type, edit the Rust types**, then
  regenerate. JSON Schema is an output, never hand-authored; do **not**
  add `x-cbor` / `x-zig` extension keys (that was the retired
  JSON-Schema-canonical authoring path).
- The browser and server load the same `dreamball.wasm` binary.
  Host-supplied randomness via one `env.getRandomBytes` import is the
  entire runtime seam; see [`docs/VISION.md §8`](docs/VISION.md) and
  ADR-1 in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). ADR-1 was
  never about Zig — it was about one compiled artifact with one host
  seam, and that survives the language change.

If you find yourself writing a second hand-maintained implementation of
a wire type — stop. The Rust types are canonical; the rest is generated
from them. (The Zig crypto substrate was a standing violation of exactly
this rule, one layer down. That is what epic `Dreamball-y4t` is paying
off.)

**Transitional status (2026-08-06):** the port is in flight. Until epic
`Dreamball-y4t` lands, `src/protocol*.zig` and the hardcoded-string
generators in `tools/schema-gen/` are still what the build actually
runs, and the vendored `schemas/*.json` are still kept consistent by a
pin + byte-equivalence gate. So *while porting*: change the Zig types
and update the generated TS/Valibot/`cbor.ts` + JSON-Schema fixtures by
hand, as before — but don't invest in that path, and don't build new
Zig-side codegen. The Zig comptime `@typeInfo` generator
(`Dreamball-m97.2`) is **dissolved, not deferred** — do not build it.
Read the ADR before adding fields.

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
- `zig build` — compile library + `dreamball` CLI
- `zig build test` — unit tests (≥ 51 passing)
- `zig build smoke` — CLI end-to-end integration test
- `zig build wasm` — produce `src/lib/wasm/dreamball.wasm` (≤ 300 KB raw, ≤ 150 KB gzipped; ships ML-DSA-87 verify). **Gzipped (the over-the-wire cost) is the binding budget.** History: raw relaxed 200→224 KB on 2026-06-25 (nested-envelope decoders); **2026-06-28 dev-velocity bump to 300 KB raw / 150 KB gzip** (generous headroom) because `verifyAction` (sprint-003 B2) is the first WASM caller of `decodeAction` and links the full decode path. This bump is **temporary** — restoring a tight gzip budget is tracked in `Dreamball-8bk` (150 KB is a ceiling for fast iteration, not a target; the binary is ~66 KB gzip today). See [`docs/decisions/2026-06-28-wasm-size-budget-dev-velocity-bump.md`](docs/decisions/2026-06-28-wasm-size-budget-dev-velocity-bump.md) and [`docs/decisions/2026-06-25-zig-canonical-supersedes-json-schema.md`](docs/decisions/2026-06-25-zig-canonical-supersedes-json-schema.md).
- `zig build schemagen` — regenerate `src/lib/generated/*.ts`

On Linux, all of the above default to `-Dtarget=x86_64-linux-musl`
(Zig's bundled musl libc), producing statically-linked binaries with
no system libc/crt dependency. macOS keeps the native default. Pass
`-Dtarget=native` to opt into glibc-dynamic linkage. See
[`docs/decisions/2026-05-24-hermetic-musl-default-linux.md`](docs/decisions/2026-05-24-hermetic-musl-default-linux.md)
for the rationale (sidesteps the Zig-0.16-LLD-vs-GCC-16-`.sframe`
toolchain skew permanently).

**Bun side:**
- `bun install` — install JS/TS deps
- `bun run check` — svelte-check (must be 0 errors)
- `bun run test:unit -- --run` — Vitest
- `bun run storybook` / `bun run build-storybook` / `bun run test-storybook`
- `bun run build` — library + showcase build
- `bun run dev:server` — dreamball-server (Elysia) on :9808
- `bun run demo` — dreamball-server + Vite dev server in parallel
- `bun run codegen` — alias for `zig build schemagen`

**Integration gates:**
- `scripts/cli-smoke.sh` — Zig CLI end-to-end
- `scripts/server-smoke.sh` — HTTP dreamball-server end-to-end
- `tests/e2e-cryptography.sh` — crypto pipeline (mock or real via `RECRYPT_SERVER_URL`)

Every commit must keep every gate green. CI (`.github/workflows/ci.yml`)
runs them all.

**Before reporting a fix as "done" / "green" / "verified":** run every gate
above locally — not just the narrow test nearest the change. A bug shipped
in commit `06c7b83` precisely because only `zig build test` + narrow
Vitest were run; `zig build smoke` caught a broken invariant only after
the commit landed. Narrow tests pass false-positive when a change is
locally correct but violates an integration assumption. Verification
without `zig build smoke` is not verification.

## Style

- Match recrypt's naming and terminology verbatim when the concept overlaps
  (signatures, envelopes, fingerprints, stages). If you find yourself
  inventing a new word, check recrypt first.
- Keep `docs/PROTOCOL.md` prescriptive and `docs/VISION.md` descriptive.
  They are different registers for different readers.
- Tests live inline in `src/**.zig` (`test "…"` blocks). Integration tests
  live in `scripts/cli-smoke.sh`.

## Debug artefacts — keep them out of the repo

Playwright snapshots, ad-hoc Storybook screenshots, REPL dumps, and any
other throwaway debugging output go under `tmp/` (gitignored). **Never**
write debug screenshots to the repo root. If you reach for
`browser_take_screenshot` or `page.screenshot(...)`, target a path under
`tmp/screenshots/<topic>-<state>.png`. Same for any other scratch byte
output — `tmp/` is the only blessed scratch location.

The repo root is for source, config, and intentional fixtures only. If a
screenshot is genuinely a documentation artefact, place it under
`docs/images/` and reference it from a markdown file; otherwise it
belongs in `tmp/`.

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


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
