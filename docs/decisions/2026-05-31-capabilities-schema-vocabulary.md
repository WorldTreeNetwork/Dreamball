# 2026-05-31 — `x-capabilities`: the capability requirement + provider vocabulary

Sprint: sprint-003 (candidate) · Significance: HIGH ·
**Status: DRAFT — spec proposal** · Sibling decisions:
[capability-provider-model](./2026-05-31-capability-provider-model.md) (the *why*) ·
[action-manifest](./2026-04-25-action-manifest.md) (the symmetric twin) ·
[json-schema-canonical](./2026-04-25-json-schema-canonical.md) ·
[archiform-registry](./2026-04-25-archiform-registry.md)

> Implements step 3 of
> [capability-provider-model §9](./2026-05-31-capability-provider-model.md).
> This doc specs the schema vocabulary; it does not yet mutate any pinned
> schema (that needs re-pin + a `gen_capabilities` projector — §9 here).

## 1. Context

`x-actions` already proves the pattern: an archiform declares operations
in its JSON Schema, content-addresses their wasm
(`implementation.wasm = <blake3-hex>`), and CLI/REST/MCP are mechanical
projections ([action-manifest](./2026-04-25-action-manifest.md)). Where
`x-actions` says *what this archiform does*, **`x-capabilities` says what
it needs** — the symmetric twin. It is the keystone the resolver, the
provider model, versioning, profiles, and discovery all hang off
([capability-provider-model](./2026-05-31-capability-provider-model.md)).

**Schema metadata, never on the wire.** Like `x-actions`, `x-capabilities`
lives in the archiform JSON Schema and is projected to generated code +
validation. It is **never serialized into a DreamBall CBOR envelope** — so
adding it is additive schema metadata, not a wire-format change.

## 2. Interface identifiers

An interface identifier is `<scope>/<name>` plus a semver range carried
separately. Two scopes (the §10.4 two-resolver-scopes decision):

| Scope | Bound by | Lifecycle | Degradation |
|---|---|---|---|
| `service/*` | the runtime/host | per session | functional (no kNN → sequential replay) |
| `render/*` | the renderer with the ball open | per render context | visual (down the lens/surface chain) |

The scope is the namespace prefix; the resolver routes by it. Examples:
`service/graph-store`, `service/text-embed`, `render/omnispherical`,
`render/splat`.

**Versioning** follows [capability-provider-model §10.1]: npm-style caret
ranges, with the **major as the capability discriminator** — a `^1`
requirement and a `^2` requirement never match the same provider, so
`graph-store/2` is effectively a different capability. (Prose shorthand
`graph-store/1` ≡ `{ interface: "service/graph-store", version: "^1" }`.)
Within a major, minor is additive/forward-compatible, so a `^1.2`
requirement binds happily to a `1.4` provider.

This is **enforced semver**, not npm's trust-based semantics
([capability-provider-model §10.1]): the range syntax is npm's, but a
provider's `implements` claim is only valid if it passes that interface
version's **conformance suite** (recorded in `conformsTo`, §4). An
interface version is therefore a `(label, suite-hash)` pair — `text-embed@1.3`
for humans, the suite content-hash for the machine — paralleling every
schema's `(name, .fp pin)`. And because compatibility is *enforced*,
provider **selection is a preference, not a safety call**: the `select`
field (§5) defaults to newest-conformant-locked-at-seal and drills in to
minimum-version/pinned.

## 3. The requirement block (consumer side)

Top-level `x-capabilities` key, sibling to `x-actions`, with two groups —
`requires` (fatal if unbound) and `optional` (degrades if unbound) — each
a map keyed by a local alias (mirroring how `x-actions` keys by verb):

```jsonc
"x-capabilities": {
  "requires": {
    "store": {
      "interface": "service/graph-store",
      "version":   "^1.2",            // caret default; major must match scope id
      "select":    "prefer-local"     // policy hint (§5); default "auto"
    },
    "embed": {
      "interface": "service/text-embed",
      "version":   "^1",
      "params":    { "dim": 256 }     // interface-defined parameters
    },
    "scene": {
      "interface": "render/omnispherical",
      "version":   "^1"
    }
  },
  "optional": {
    "knn": {
      "interface":  "service/vector-knn",
      "version":    "^1",
      "degradesTo": "sequential-replay"   // required on optional entries
    }
  }
}
```

**Closed field set** (validator rejects anything else, mirroring D-035):

| Field | Where | Meaning |
|---|---|---|
| `interface` | both | `<scope>/<name>` identifier (required) |
| `version` | both | semver range; default `"*"` (lint warns — pin a caret) |
| `params` | both | interface-defined parameters (e.g. embedding `dim`) |
| `select` | both | profile-selection policy hint (§5); default `"auto"` |
| `source` | both | discovery override (§6); default = registry |
| `degradesTo` | `optional` only | named fallback behavior when unbound (required here) |

A `required` entry with no bound provider is a hard resolution failure. An
`optional` entry with no provider takes its `degradesTo` path.

## 4. The provider manifest (provider side)

A provider package declares an `x-provider` block (in its own
schema/manifest) — what interfaces it satisfies, content-addressed:

```jsonc
"x-provider": {
  "name":    "qwen3-onnx",
  "version": "0.6.0",                       // the provider's OWN version (informational)
  "implements": ["service/text-embed@1.3"], // interface ids + version it conforms to
  "implementation": {
    "wasm": "…blake3-hex…"                  // Category-A code: same shape as x-actions
    // — or, for a Category-B native service —
    // "engine": "onnxruntime-node", "entry": "qwen3.js"
  },
  "conformsTo": {                            // proof the implements-claim is checkable
    "service/text-embed@1.3": "…blake3 of the conformance-suite run…"
  },
  "profiles": [ /* §5 */ ]
}
```

**The load-bearing rule restated** (§10.1): `implements` is only valid if
the provider passes that interface version's conformance suite in CI; a
break forces a major bump *even if the provider's own version is a patch*.
`conformsTo` records the passing suite — verify, don't trust.

This is why **a different engine qualifies**: a SQLite provider declaring
`implements: ["service/graph-store@1.2"]` and passing the
`graph-store/1.2` suite is interchangeable with the kuzu provider. The
interface is the query/replay surface, not the engine.

## 5. Resource profiles (provider side)

Per [capability-provider-model §10.2]: a provider offers *alternative
execution profiles*, not one resource line. The host/resolver intersects
them with available hardware and ranks by the requirement's `select`:

```jsonc
"profiles": [
  { "id": "cpu",          "requires": { "accelerator": "none",       "ram": "2GB" },
    "characteristics": { "latency": "high",   "quality": "full", "power": "low" } },
  { "id": "gpu-cuda",     "requires": { "accelerator": "cuda",       "vram": "1.5GB" },
    "characteristics": { "latency": "low",    "quality": "full", "power": "high" } },
  { "id": "npu-coreml",   "requires": { "accelerator": "coreml-ane" },
    "characteristics": { "latency": "low",    "quality": "full", "power": "low" } },
  { "id": "split-npu-cpu","requires": { "accelerator": "coreml-ane", "ram": "1GB" },
    "characteristics": { "latency": "medium", "quality": "full", "power": "medium" } }
]
```

`select` policy values (§10.5 sensible-default + drill-in):
`auto` (default — balanced), `prefer-low-latency`, `prefer-low-power`,
`prefer-quality`, `prefer-local` (never leave the device — ties to the
"single sanctioned network exit", NFR11). No matching profile + a
`required` capability → resolution fails before instantiation; `optional`
→ `degradesTo`. (Profile axes are a starter set; seed the canonical
vocabulary from the user's Papyrus speech-to-text trade-offs and ONNX
Runtime execution providers — §10.2.)

## 6. Discovery — three reference forms

`source` (optional; default = registry) follows the npm-shaped forms from
[capability-provider-model §10.3]:

| Form | Example | Use |
|---|---|---|
| registry (default) | *(omit `source`)* → aspects.sh resolves `<scope>/<name>` | normal |
| git | `"github:org/repo#v1.3"` | not yet in the registry |
| local | `"file:./providers/sqlite-graph-store"` | dev / air-gap / private |

All three resolve to a content-addressed provider whose hash is locked
(§7). Air-gap snapshotting vendors the registry/git source — an existing
protocol pattern.

## 7. The lockfile

Resolution writes `capabilities.lock` (the `package-lock.json` / Nix
hybrid) so a binding is reproducible:

```jsonc
{
  "lockfileVersion": 1,
  "resolved": {
    "service/text-embed": {
      "requirement": "^1",
      "provider":    "qwen3-onnx@0.6.0",
      "implements":  "service/text-embed@1.3",
      "wasm":        "…blake3-hex…",      // or engine ref + package hash
      "profile":     "npu-coreml",
      "source":      "aspects:service/text-embed"
    }
  }
}
```

Re-resolution *with* the lock returns exact bytes; *without* it picks the
newest conformant provider in range.

## 8. Worked example — the Memory Palace archiform

`schemas/memory-palace-0.1.0.json` gains `x-capabilities` beside its
existing `x-actions` (it currently *embeds* these as core knowledge — see
the leak trace in
[capability-provider-model §2](./2026-05-31-capability-provider-model.md)):

```jsonc
"x-capabilities": {
  "requires": {
    "store": { "interface": "service/graph-store", "version": "^1", "select": "prefer-local" },
    "embed": { "interface": "service/text-embed",  "version": "^1", "params": { "dim": 256 } },
    "scene": { "interface": "render/omnispherical", "version": "^1" }
  },
  "optional": {
    "knn": { "interface": "service/vector-knn", "version": "^1", "degradesTo": "sequential-replay" }
  }
}
```

Two scopes in one block (§10.4): `store`/`embed`/`knn` bind in the host
scope; `scene` binds in the renderer scope. `graph-store` being a
*required service* whose data is a replayable index over the signed action
log (D-021/D-028) is precisely why it can be externalized — the palace
declares the need, the host binds kuzu **or SQLite**, nothing canonical
moves.

## 9. Projection through schema-gen (no wire change)

A new sibling generator `gen_capabilities` (alongside `gen_cli` /
`gen_ts_client` / `gen_mcp_tools`, [json-schema-canonical](./2026-04-25-json-schema-canonical.md)):

1. **Validate** `x-capabilities` against the closed field set (§3) and
   confirm every `interface` resolves (registry/git/local) and every
   `version` major agrees with its scope id. Hard-fail on drift (D-035
   discipline).
2. **Emit** a typed requirements manifest the resolver consumes — e.g.
   `src/lib/generated/<archiform>-capabilities.ts` — mirroring how
   `gen_ts_client` emits `palace-client.ts`. The `text-embed/1` resolver
   prototype (`jelly-server/src/capabilities/text-embed/`) is the
   hand-written shape this would generate.
3. **Expose** in `/.well-known/mcp` so an agent meeting a server learns
   the archiform's capability needs alongside its actions.

No CBOR codec, no envelope field — `x-capabilities` is schema-level only,
so the golden-vector lock is untouched.

## 10. Migration + open items

- **Additive.** New top-level key; existing schemas without it are
  unaffected; the validator only runs where the key is present.
- **Landing it** requires: add `x-capabilities` to the target schema,
  `bun run schemas:pin`, build `gen_capabilities`, regenerate, commit
  together (the §13 runbook in ARCHITECTURE.md).
- **Open — instance-level capabilities.** v1 is archiform-schema-level
  (like `x-actions`). A specific DreamBall instance declaring extra needs
  is a future extension; defer.
- **Open — `params` schema per interface.** Each interface version should
  publish the JSON-Schema for its `params` (e.g. `text-embed` declares
  `dim`); how that's stored in the registry is TBD.
- **Open — render-scope `degradesTo` vocabulary.** Service fallbacks are
  behaviors (`sequential-replay`); render fallbacks are the existing
  lens/surface chain. Unify the naming or keep two registries — decide
  when the first `render/*` interface is specced.
```
