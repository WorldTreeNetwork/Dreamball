# 2026-05-31 — Capabilities and providers: dynamic linking for DreamBalls

Sprint: sprint-003 · Significance: HIGH ·
**Status: ADOPTED — landed incrementally on `main` (capabilities vocabulary +
validator + projector + manifest-driven resolver + graph-store/1 extraction,
incl. the §2 `gen_cypher` decoupling — Dreamball-9dq). WIT declined for now
(§12). Open in beads: browser-CSP spike (§10.7), Dreamball-ccb (OPFS provider),
Dreamball-dky (runtime wiring).** ·
Sibling decisions:
[action-manifest](./2026-04-25-action-manifest.md) ·
[json-schema-canonical](./2026-04-25-json-schema-canonical.md) ·
[archiform-registry](./2026-04-25-archiform-registry.md) ·
[wasm-runtime](./2026-04-25-wasm-runtime.md)

> This note captured the *why* before the code. It is now **largely landed** —
> §9 carries per-step status notes (✓ landed / tracked in beads). It remains the
> canonical rationale; the phased path was additive, so each increment shipped
> independently. Update §9 + the status line as the remaining increments land.

## 1. Context — the question

A DreamBall that needs a graph database should not have to *embed* a
graph database. It should be able to **declare a need for that
capability** and have a host **bind a provider** to it — ideally a
provider that is acquirable/downloadable and shared across every
DreamBall that asks for the same thing. The reference points raised in
discussion were **Linux shared libraries** (`ld.so` resolving an
undefined symbol against a `libfoo.so.2`) and **Nix** (immutable,
hash-addressed store paths with exact, side-by-side-versionable
closures) — "like shared libraries but without the craziness."

This is the runtime-side twin of the render-capability idea (a
DreamBall declaring what a *renderer* must implement, with
required/optional slots and graceful fallback). Both are the same
primitive — a **capability contract** — viewed from two sides.

The protocol's existing aesthetic is already the Nix-good-parts
aesthetic applied to *data*: everything content-addressed by blake3,
verify-before-use, vendored-and-pinned ([pins, D-029](
./2026-04-25-json-schema-canonical.md)), no hidden mutable state,
signatures for trust. Extending it to *capabilities* is a continuation,
not a new model.

## 2. Why now — the leak trace

The trigger was the observation that the protocol core knows about a
specific application. A scan confirms the leak is structural, not
cosmetic:

| Leak | Location | What it is |
|---|---|---|
| Graph-DB DDL generator in **core codegen** | `tools/schema-gen/gen_cypher.zig` → `src/memory-palace/schema.cypher` | The protocol's codegen emits kuzu/Cypher table definitions (`Palace`, `Room`, `Inscription`, `Triple`, `Aqueduct`, …) for one application + one storage engine. |
| Palace schema **baked into the protocol binary** | `src/archiform.zig` `@embedFile("schemas/memory-palace-0.1.0.json")` | The core binary literally contains the memory-palace schema bytes to compute an implicit fp. |
| Archiform types **hand-written in core Zig** | `src/protocol_v2.zig` (`Aqueduct`, `Inscription`, `Mythos`, `Triple`; `ActionKind.{palace_minted,room_added,aqueduct_created,inscription_*}`) | CLAUDE.md says these "come from the vendored archiform schema, not hand-written Zig." Acknowledged mid-migration debt ([json-schema-canonical](./2026-04-25-json-schema-canonical.md)). |
| Palace verbs in the **protocol CLI** | `src/cli/palace.zig`, `src/cli/internal/{add_room,inscribe,move,open,rename_mythos}.zig`, `src/cli/generated/palace_*` | `jelly` is both the protocol authoring tool and the palace application CLI. |
| "Per-archiform" generators **hardwired to one archiform** | `gen_cli` / `gen_ts_client` / `gen_mcp_tools` headers say "per-archiform" but hardcode `schemas/memory-palace-0.1.0.json` and emit `palace_*` / `palace-client.ts` / `palace-mcp-tools.ts` | The general mechanism exists; the instance is fused into output paths and the `palace.` namespace. |
| Embedding service in the **generic HTTP host** | `jelly-server/src/embedding/{qwen3,runpod}.ts`, `routes/embed*` | A 600 MB model runtime (`@huggingface/transformers`) lives in the otherwise-generic protocol server. |
| Heavy deps ride in via the composition | `package.json`: `@ladybugdb/core`, `kuzu-wasm`, `playcanvas`, `@threlte/*`; `jelly-server`: `@huggingface/transformers` | A clone of "the protocol" pulls a graph DB, a 3D engine, and an ONNX runtime. |

**Closure status (2026-06-01).** Row 1 — the `gen_cypher` core-codegen DDL leak
— is **closed** (Dreamball-9dq, §9.4): `gen_cypher` moved to
`tools/graphstore-schema/`; core no longer emits `schema.cypher`. The
`text-embed` and `graph-store/1` capabilities are **extracted** (§9.2/§9.4). The
remaining rows (`src/archiform.zig` `@embedFile`, hand-written archiform types in
`protocol_v2.zig`, palace CLI verbs, the embedding service in the HTTP host) are
**not yet addressed** — they remain the tracked direction, not done work.

**Sizing the imbalance:** the Memory Palace composition (`src/memory-palace/`,
≈ 14,960 LOC) is **larger than the entire Zig protocol core**
(`src/*.zig`, ≈ 10,444 LOC). The first composition outweighs the
protocol it is built on, and lives in the same tree, with the
dependency arrow pointing *backwards* — core → composition.

**The pattern already emerged on its own.** `routes/embed.ts` selects
between **three providers** for one logical capability — `qwen3` (local
ONNX), `runpod` (remote GPU), and a deterministic `mock` — via an
env-var `if/else`. That is the capability-with-swappable-providers shape
already present in the code, missing only a declared interface and a
resolver. We are not inventing a pattern; we are naming and
generalizing one the codebase reached for unprompted.

## 3. Proposal — capabilities are interfaces, providers are implementations

Introduce one new concept with two halves:

- A **capability** is a *named, versioned, content-addressed interface*
  — a contract (e.g. `graph-store/1`, `text-embed/1`,
  `render-splat/1`). A DreamBall/archiform depends on the **interface**,
  never on a specific implementation. This is the `soname` / WIT-world /
  Nix-derivation-input role.
- A **provider** is a *content-addressed implementation* that satisfies
  a capability (e.g. `kuzu-wasm@blake3:…`, `qwen3-onnx@blake3:…`). The
  `.so` file / store path / wasm component role.
- A **resolver** (the `ld.so` of this world) binds requirements →
  providers at load time: match by *interface + semver*, verify provider
  bytes against the manifest pin, instantiate, and report
  unbound-optional vs. unbound-fatal.

### 3.1 Declaration shape (sibling to the action manifest)

The action manifest already proves the "declare in JSON Schema → project
mechanically" pattern ([action-manifest, D-019](
./2026-04-25-action-manifest.md)). Capabilities are its symmetric twin —
where `actions` say *what this thing does*, `capabilities` say *what
this thing needs*:

```jsonc
"capabilities": {
  "requires": {
    "graph-store":  { "interface": "graph-store/1",        "category": "service" },
    "text-embed":   { "interface": "text-embed/1?dim=256", "category": "service" }
  },
  "optional": {
    "vector-knn":   { "interface": "vector-knn/1", "degradesTo": "sequential-replay" }
  }
}
```

This mirrors the inscription `surface → fallback[] → "scroll"` chain
([surface-registry, D-026](./2026-04-24-surface-registry.md)) and the
Tool `applicable-to` list — both are shards of this one idea, today
expressed ad hoc.

## 4. The distinction that does the work: two categories

Conflating these two is what makes "should every ball embed a graph DB?"
feel intractable. They have different physics.

**Category A — pure, portable code.** CBOR codecs, SDF evaluators,
layout solvers, shader interpreters, query planners. Sandboxable pure
functions. They *can* be shipped, content-addressed, fetched-once,
deduplicated, and instantiated — exactly a Nix store path. If 50
DreamBalls require `sdf-eval@blake3:abc`, the host holds **one** copy
and links it into all 50. Versions coexist by hash, not by name — which
*is* the fix for `.so` version roulette.

> The standard for Category A already exists and the wasm host is one
> step from it: the **WebAssembly Component Model + WIT** (interface
> types / "worlds"). The `dreamball.*` import allowlist ([wasm-runtime,
> SEC1](./2026-04-25-wasm-runtime.md)) is this seam in embryo — 5
> imports wide, hardcoded into the host. WIT is that seam with a real
> IDL and resolver tooling. Prefer adopting it over inventing an ABI.

**Category B — stateful host services.** Graph databases, embedding
models, LLM endpoints, GPUs. Not pure functions: mutable state,
resources, hardware. You cannot content-address a live kuzu instance.
For Category B the DreamBall must **not** carry the service — it
declares a need for an *interface*, and the host binds a provider or
degrades.

### 4.1 Why Category B is safe to externalize (the load-bearing invariant)

For a DreamBall the graph database is **never canonical** — it is a
derived index over the signed action log
([replay-from-CAS, D-021](../sprints/002-archiform-foundation/architecture-decisions.md);
[triple-native, D-028](./2026-04-24-kg-triple-native-storage.md):
"Triple rows are derived state replayable from ActionLog"). The ball's
*truth* is its own signed `jelly.action` envelopes; the kuzu store is a
cache you can discard and rebuild.

So **"I need a graph DB" really means "I need somewhere to materialize a
queryable index over my own signed data."** The ball depends on
`graph-store/1`, not on kuzu; a host may satisfy it with kuzu, SQLite,
an in-memory map, or refuse and offer sequential replay — and nothing
canonical is lost. This is the clean answer to the original worry:
stateful capabilities are caches over signed logs, therefore always
safely host-provided.

## 5. The capability catalog (derived from the leak trace)

Each leak is an unbundled capability waiting to be named:

| Capability | Interface (proposed) | Cat. | Current provider(s) in-tree | Current fallback | Leaks via |
|---|---|---|---|---|---|
| Graph store | `graph-store/1` | B | `@ladybugdb/core` (server), `kuzu-wasm` (browser) | none in-mem; kNN→HTTP | `gen_cypher.zig`, `src/kuzu-wasm.d.ts`, `build.zig` |
| Text embedding | `text-embed/1?dim=256` | B | `qwen3` (ONNX), `runpod` (GPU), `mock` | `JELLY_EMBED_MOCK`; `inscription-pending-embedding` when offline | `jelly-server/embedding/*`, `cli/internal/inscribe.zig` |
| Vector K-NN | `vector-knn/1` | B (rides on graph-store) | kuzu vector index | HTTP `/kNN`; inscriptions-only ([known-gaps §13]) | `schema.cypher` `CREATE_VECTOR_INDEX` |
| 3D / splat render | `render-3d/1`, `render-splat/1` | renderer | Threlte (WebGL), PlayCanvas (splat) | lens fallback (`flat`, `thumbnail`) | `src/lib/` (renderer layer) |
| Oracle agent | `oracle-agent/1` | composition | `src/memory-palace/oracle.ts` | — | `src/root.zig` re-export; palace CLI verbs |

The **action-manifest projectors** (`gen_cli`/`gen_ts_client`/`gen_mcp_tools`)
are not capabilities — they are the *mechanism* that should be
parameterized per-archiform (the archiform package supplies source +
output namespace) and, extended, the same mechanism that projects a
capability-requirement set. `gen_cypher`, by contrast, is the
**provider-build step for `graph-store`** and belongs in that provider's
package, not in core.

## 6. Trust and security reuse existing machinery

No new trust primitives:

- **Integrity / acquisition.** Providers are content-addressed and
  pinned exactly like vendored schemas ([pins, D-029](
  ./2026-04-25-json-schema-canonical.md)); acquired and cached exactly
  like archiforms (aspects.sh resolve → local cache → air-gap snapshot,
  [archiform-registry](./2026-04-25-archiform-registry.md)).
- **Authenticity.** A capability interface is declared in a *signed*
  schema body; provider wasm is blake3-verified before instantiation —
  this is exactly the [D-031 trust chain](../PROTOCOL.md) (publisher
  signs schema → schema declares fps → host verifies bytes), already
  built for actions.
- **Object-capability discipline.** The host grants only what it binds;
  a provider can do only what its interface permits — the same
  allowlist-before-run rule as the `dreamball.*` imports (SEC1). Here
  "capability" is both *feature* and *unforgeable permission token*,
  which is the property we want, not a pun to apologize for.

## 7. What this adopts from Nix / WASM, and what it refuses from `.so`

**Adopt:** content-addressed providers (side-by-side versions, no global
mutable namespace), exact pins (reproducible closures), interface-typed
linking (the WIT *model* — but expressed in our own JSON-Schema-declared
interfaces, **not** the WIT toolchain; see §10.7 + §12), verify-before-link.

**Refuse:** the three sources of `.so` "craziness" — name-addressing
(`libfoo.so` symlink roulette), a global mutable `/usr/lib`, and absence
of integrity. All three are already rejected for data in this project;
we simply decline to reintroduce them for code.

## 8. What changes in the repo

The capability model is the principled justification for the
boundary cut:

- **Core ships interfaces + the resolver, and zero providers.** No
  `cypher`/`kuzu`/`qwen`/`palace` string survives in `src/*.zig`,
  `tools/schema-gen` (root pass), or `jelly-server` core.
- **`gen_cypher` moves** into the `graph-store` provider package as its
  build step; core codegen does root types + generic archiform
  projection only.
- **`src/archiform.zig`'s embedded palace schema** is removed; the
  implicit-fp back-compat shim becomes provider/archiform-local.
- **The Memory Palace dissolves** into: a `palace` DreamBall + a
  `graph-store` provider + a `text-embed` provider + an `oracle-agent`
  — each separately versioned, content-addressed, acquirable.
- This can be enforced **in the monorepo first** (strict package
  boundaries + a "no core→composition import" lint), with a physical
  split as a later, mechanical step. The real fix is the dependency
  *direction*; relocating files before that is premature.

## 9. Phased, additive path

1. **Name the interfaces** for the five catalog capabilities (this doc).
2. **Formalize the embedding capability first** — it already has three
   providers; replace the env-var `if/else` with a minimal resolver and
   a declared `text-embed/1` interface. Lowest-risk proof.
3. **Add the `capabilities` declaration** to the JSON Schema vocabulary
   (sibling to `actions`); project it through the existing generator
   mechanism. No wire-format change — it is schema metadata.
4. **Extract `graph-store`** behind `graph-store/1`, moving
   `gen_cypher` + `schema.cypher` into the provider; rely on
   replay-from-log (§4.1) for the in-memory/degraded provider.
   - **Status (Dreamball-9dq, landed):** the §2 DDL leak is closed.
     `gen_cypher.zig` no longer lives in core codegen — it moved to
     `tools/graphstore-schema/`, compiled by a graph-store-owned
     `zig build graphstore-schema` step (run after `zig build schemagen`
     by `bun run codegen`). The core `schema-gen` exe no longer imports
     or compiles `gen_cypher` and no longer emits `schema.cypher`. The
     shared `ArchiformCtx` + schema-read/pin-verify + blake3/log helpers
     were extracted to the neutral `tools/codegen-common/codegen_common.zig`
     module so neither core nor the per-archiform generators depend on the
     graph store's DDL generator. `schema.cypher` stays at
     `src/memory-palace/` (the ladybug provider's runtime DDL, pinned
     byte-for-byte by `tests/codegen/cypher-byte-equivalence.test.ts`).
5. **Generalize the `dreamball.*` host** to interface-typed linking for
   Category A providers, expressed in our own capability vocabulary (not
   the WIT toolchain — §12); keep the allowlist semantics.
6. **Enforce the boundary** with a lint; split repos only if/when
   warranted.

## 10. Design decisions on the open questions (2026-05-31 working session)

The prior open questions were worked through with the user. Resolutions
below; two items remain pending research (§10.7).

### 10.1 Versioning policy — *enforced* semver over content-addressed providers

Versioning has two jobs, and only one is open. **Identity /
reproducibility** ("exactly which bytes, reproducibly?") is already solved
Nix-style — blake3 content-addressing + a lockfile (concept 3 below). The
open job is **compatibility / selection** ("will this provider satisfy my
need?"). The answer is **enforced semver**: npm's *range syntax* (familiar)
+ Go's *major-in-identity* (incompatibility is structural) + **Elm-grade
*enforcement*** (the version claim is checked by a conformance suite, not
trusted) + Nix *integrity* underneath. It is emphatically **not** npm's
trust-based semantics — only its ergonomics. (Why not pure Nix for
compatibility: Nix has no ranges and punts "what's compatible" to nixpkgs
*curation* — a central coherent set, antithetical to this project's
no-central-registry / composition-beats-curation stance, VISION §5.) Three
concepts, deliberately decoupled:

1. **Interface version** `name@MAJOR.MINOR` — the contract.
   - MAJOR = breaking. `graph-store/2` is a *different capability* than
     `graph-store/1`; v1 consumers are untouched by v2's existence
     (major-in-the-name, like WIT's `@0.2.0` worlds).
   - MINOR = additive only (new optional operation/field). Forward-
     compatible within a major: a consumer needing `1.2` runs against a
     `1.4` provider.
   - PATCH = editorial; never load-bearing for matching.

2. **Requirement range** (what a DreamBall declares) — caret-default:
   `^1.2` ≡ `>=1.2.0 <2.0.0`. Default = caret; drill-in to pin exact
   (`=1.2.0`) or widen (§10.5).

3. **Provider implementation** — content-addressed (`blake3:…`) with its
   *own independent version* (the kuzu/sqlite release). What matters for
   matching is the provider's declared `implements: ["graph-store/1.4"]`,
   **not** its internal version. Integrity + dedup from the hash;
   reproducibility from a lockfile recording the resolved hash (the
   `package-lock.json` / Nix hybrid).

**The load-bearing rule** (exactly where npm-in-practice fails): a
provider author MUST bump the *interface* major when they break the
contract — *even when their own release is "just a patch."* Decoupling
provider-version from interface-version is what makes "kuzu 0.11.3 →
0.11.4 still implements `graph-store/1.4`" an honest, checkable claim —
the "a `.x` DB release still runs your DB code" case — while still
catching the "sometimes a new version breaks everything" case.

**Conformance suites police the claim.** Each interface version ships a
conformance/golden suite (reusing the repo's golden-vector discipline).
`implements: graph-store/1.4` is valid only if the provider passes the
`graph-store/1.4` suite in CI. This converts npm's "trust me, it's
compatible" into the project's native "verify, don't trust": a provider
whose new version silently breaks the contract fails conformance, so the
author either bumps the major (honest) or the resolver refuses it (safe).
A DreamBall's `^1.2` is never silently broken. (This is also the rule
that lets a *different engine entirely* — SQLite instead of kuzu —
qualify as a `graph-store/1` provider: the interface is the query/replay
surface it must pass, not the engine.)

**Decision A — selection is a *preference*, not a safety call.** Because
compatibility is enforced (every in-range provider is conformance-verified),
"which provider do I pick?" no longer affects correctness — only taste. So
selection is a policy under §10.5: **default = newest conformant, locked at
seal time** (a long-lived DreamBall keeps working *and* picks up bugfixes
when re-resolved, yet stays reproducible via the lock); **drill-in =
minimum-version-selection / pinned** (Go-style "boring floor, no
surprises"). npm's "newest" and Go's "minimum" become two selectable
policies, not a global law.

**Decision B — an interface version is a `(label, suite-hash)` pair**,
exactly mirroring how every schema already carries a human name
(`memory-palace-0.1.0`) *and* a `.fp` pin. The semver string
(`text-embed@1.3`) is the ergonomic handle for humans; the **conformance-
suite content-hash** is ground truth for the machine. "Does this provider
really implement 1.3?" becomes a content-addressed question (does it pass
suite-hash *H*?), not a trusted string. The vocabulary's `conformsTo` field
records the passing suite-hash.

### 10.2 Resource requirements — alternative execution profiles, not one line

Adopted as an **optional** part of the spec. A Category-B provider does
not have a single resource cost — it has a *set of alternative execution
profiles*, each with different hardware needs and trade-offs. An
embedding (or speech-to-text) model may run on CPU, GPU, NPU, or split
NPU+CPU. The provider declares profiles; the host/resolver selects one by
intersecting available hardware with the profiles, ranked by policy
(default balanced; override `prefer-low-latency` / `prefer-low-power`):

```jsonc
"profiles": [
  { "id": "cpu",        "requires": { "accelerator": "none",       "ram": "2GB" },
    "characteristics": { "latency": "high",   "quality": "full", "power": "low" } },
  { "id": "gpu-cuda",   "requires": { "accelerator": "cuda",       "vram": "1.5GB" },
    "characteristics": { "latency": "low",    "quality": "full", "power": "high" } },
  { "id": "npu-coreml", "requires": { "accelerator": "coreml-ane" },
    "characteristics": { "latency": "low",    "quality": "full", "power": "low" } },
  { "id": "split-npu-cpu", "requires": { "accelerator": "coreml-ane", "ram": "1GB" },
    "characteristics": { "latency": "medium", "quality": "full", "power": "medium" } }
]
```

Prior art on both sides: **ONNX Runtime "execution providers"**
(CPU/CUDA/CoreML EP) — apt because the qwen3 provider already runs on
onnxruntime — and the user's own **Papyrus** application, which hand-tuned
exactly these CPU/GPU/NPU trade-offs for a speech-to-text model. The
Papyrus dimensions should seed the canonical profile vocabulary (open
item: capture them). Starter axes: `accelerator`, memory (`ram`/`vram`),
and `characteristics` (latency / quality / power-thermal). The resolver
uses profiles to **fail before instantiation** (no matching profile →
declared degrade path), formalizing today's ad-hoc `JELLY_EMBED_MOCK` /
`inscription-pending-embedding` fallback.

### 10.3 Provider discovery — three reference forms, npm-shaped

Keep **aspects.sh as the general-purpose registry** (default), plus **git**
and **local** references, mirroring how the JS world references deps:

- Registry: `graph-store/^1` → resolved via aspects.sh.
- Git: `github:org/repo#tag` (or git URL) — provider not yet in the registry.
- Local: `file:./providers/sqlite-graph-store` — development / air-gap / private.

All three resolve to a content-addressed provider whose hash is locked;
air-gap snapshotting (an existing protocol pattern) works by vendoring
the registry/git source.

### 10.4 Render vs. runtime — one vocabulary, two resolver scopes

**One capability vocabulary** (one versioning spec, one provider model,
one discovery story) with **two resolver scopes**, inferred from the
interface namespace and overridable:

- **Renderer-scoped** (`render/*`): bound by whichever renderer has the
  ball open. Lifecycle = per render context; two viewers can bind
  differently at once (wallet vs. palace); degradation is *visual* (down
  the lens/surface fallback chain).
- **Host-scoped** (`service/*`): bound by the runtime (browser app or
  server). Lifecycle = per session; stateful; degradation is *functional*
  (no `vector-knn` → sequential replay).

Trade-off: *two vocabularies* would duplicate the entire
versioning/lockfile/discovery apparatus and force authors to learn two
systems; *one vocabulary, two scopes* keeps a single mental model and
lets the resolver route each requirement to the right binder by
namespace. The only cost is that routing step. A DreamBall declares all
needs in one `capabilities` block regardless of scope.

### 10.5 Cross-cutting principle — sensible defaults, drill-in to configure

Stated once, applies everywhere: **every knob has a sensible default and
an optional drill-in override.** Versioning defaults to caret ranges;
resource selection auto-picks a profile; discovery defaults to the
registry; browser acquisition ships a default set with opt-in download.
The explicit anti-goal is *the Linux problem* — having to understand
everything about everything to use anything. A consumer opens a DreamBall
with zero configuration and progressively configures only what they care
about.

### 10.6 Browser resolver — direction set, details pending

Direction: the browser resolver is **part of the web app**. The app
declares to a loaded DreamBall what capabilities it *offers* and what it
can *acquire*, downloads providers lazily as needed, and follows §10.5.
Open (research, §10.7): CSP constraints on fetching+instantiating wasm at
runtime, and the statically-generated-site case (no server → no real-time
download without some server support). Likely shape: a static site ships
a default provider bundle and acquires more only when backed by a server
or a CSP-permitted CDN. Cross that bridge after the spike.

### 10.7 Research outcomes + remaining open items

- **WIT / Component Model adoption — RESOLVED: decline now, keep the
  model.** A research pass (full note at §12) found: the Component Model
  is not a W3C standard (Wasm 3.0, Sept 2025, shipped without it); WASI
  0.2 is the stable pin but 0.3 churn is imminent and 1.0 stability is
  still future; **no browser runs Components natively** (the browser path
  is a build-time `jco` transpile to core-wasm + JS glue); and **Zig has
  no first-party binding generator** (you hand-wrap generated C + a
  WASIp1→p2 adapter). For a Zig-core + Bun + browser project whose seam is
  already one clean `jelly.wasm` + a single host import, adopting the WIT
  *toolchain* now would add a hand-maintained C-binding/adapter layer
  tracking pre-1.0 churn for a non-standard browser workaround.
  **Decision:** keep WIT's *conceptual model* (interface-typed linking,
  semver-on-interfaces) but express interfaces in our own
  JSON-Schema-declared `capabilities` vocabulary; revisit the WIT
  toolchain only after WASI 1.0 lands and a first-party Zig binding
  generator exists.
- **Browser provider-acquisition under CSP / static hosting — narrowed.**
  The research clarified the general wasm facts: runtime
  `WebAssembly.instantiate` needs `wasm-unsafe-eval` in `script-src` (not
  the broader `unsafe-eval`), works on a fully static site when assets are
  pre-bundled, and runtime *download* of a provider needs a CSP-permitted
  source. Remaining open: the concrete acquisition design for our own
  (non-jco) wasm providers — default-bundle vs. server/CDN-backed
  download — per §10.6. Still wants a focused spike.

## 11. Alternatives considered

- **Status quo (bundle everything).** What we have: the protocol clone
  carries a graph DB + ONNX + 3D engine; the first composition outweighs
  the core. Rejected — the leak trace is the cost.
- **Per-archiform CLI/runtime plugins (no interface layer).** Rejected
  for the same reason [action-manifest](./2026-04-25-action-manifest.md)
  rejected a "CLI plugin runtime": it multiplies bespoke runtimes instead
  of projecting one contract.
- **Hard repo split first.** Rejected as premature — splitting before the
  import graph is clean relocates the tangle without resolving the
  dependency direction. Boundary-lint first, split later.

## 12. Research note — WIT / Component Model assessment (2026-05-31)

Commissioned to answer §10.7's WIT question. Verdict: **well-supported for
server-side (Bun/Node via `jco`, native via `wasmtime`), but no-go as a
browser+server unifying layer for this Zig-core stack right now.**

- **Not standardized.** Component Model lives in the WASM CG (Bytecode-
  Alliance-driven), ~phase 2/3. **Wasm 3.0 (W3C, Sept 2025) shipped
  without it** (core features only). WASI 0.2 / Preview 2 (Jan 2024) is
  the stable pin; WASI 0.3 (~Feb 2026) reworks async (not purely
  additive); WASI 1.0 stability is still future.
- **Server tooling is solid.** `wasm-tools`, `wasmtime` component support,
  `wit-bindgen` (first-party Rust/C/Go); JS via `componentize-js` / `jco`.
- **Browser: no native support.** Path is `jco transpile` → core wasm +
  ES-module JS glue at build time. Typically needs only `wasm-unsafe-eval`
  CSP (not `unsafe-eval`); works on static sites; overhead unquantified.
- **Zig: no first-party story.** WIT → generated C bindings → Zig
  C-interop → core wasm → WASIp1→p2 adapter. Manual; you code against
  generated C, not idiomatic Zig. The biggest friction for this repo.
- **Risks:** pre-1.0 spec churn; indefinite non-standard browser
  workaround; harder debugging at the JS-glue/wasm seam; BA-tooling
  lock-in for the web path.

Sources: `component-model.bytecodealliance.org`;
`github.com/WebAssembly/component-model`; `thenewstack.io` (Wasm 3.0, no
Component Model); `redmonk.com` ("Wasm's Identity Crisis"); `wasi.dev/roadmap`;
`github.com/bytecodealliance/jco`; `blog.vigoo.dev` (Zig + component model).
