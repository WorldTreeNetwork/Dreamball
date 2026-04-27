# 2026-04-25 — Action Manifest as universal action contract

Sprint: sprint-002 · Significance: HIGH · Sibling decisions:
[archiform-registry](./2026-04-25-archiform-registry.md) ·
[json-schema-canonical](./2026-04-25-json-schema-canonical.md) ·
[wasm-runtime](./2026-04-25-wasm-runtime.md)

## Context

Each archiform exposes a set of operations on its instances —
`palace mint`, `palace inscribe`, `palace add-room`, etc. Sprint-001
implemented these as Zig CLI verbs hard-coded into the `jelly`
binary. With archiforms federated via aspects.sh
([archiform-registry](./2026-04-25-archiform-registry.md)), each
archiform needs to declare its own actions, and those actions need to
be reachable from every surface the project supports: CLI, REST,
MCP (agents), in-renderer buttons, programmatic TS calls.

Two paths considered: ship a per-archiform CLI plugin, or define an
abstract action surface that projects to all surfaces.

## Decision

An archiform declares **actions** in its JSON Schema. The **Action
Manifest** is the universal contract; CLI, REST, MCP, in-renderer,
and programmatic clients are mechanical *projections* of it.

There is no separate "CLI plugin runtime." There is a wasm action
runtime ([wasm-runtime](./2026-04-25-wasm-runtime.md)), and every
projection calls into it through the same manifest.

### Action declaration shape

```json
"actions": {
  "mint": {
    "summary": "Create a new memory palace",
    "inputs":  { "type": "object", "properties": { "name": {...}, "mythosTemplate": {...} } },
    "outputs": { "type": "object", "properties": { "palaceFp": {...} } },
    "effects": [{ "kind": "ActionEnvelope", "actionKind": "palace.mint" }],
    "idempotency": "creates",
    "streaming": false,
    "attributes": {
      "destructive": false,
      "requiresConfirmation": false
    },
    "implementation": { "wasm": "actions/mint.wasm", "export": "mint" }
  },
  "inscribe": { ... }
}
```

### Discipline (normative)

**Actions are pure transactions; never interactive.** No prompts inside
an action body. If confirmation is needed, declare it as an attribute
(`destructive: true`, `requiresConfirmation: true`,
`confirmationMessage: "..."`) and let the projection layer render the
confirmation in its idiom. This makes actions agent-callable: an LLM
can't satisfy a TTY prompt, but it can call `preview` then `commit`.

Where preview/commit splits are needed, declare two actions
(`palace.mint.preview` returns *what would happen*; `palace.mint`
does it).

### Projection mapping

| Projection | Derived from manifest |
|---|---|
| **CLI** | Flag mapping from `inputs`; `outputs` printed as JSON; `attributes.requiresConfirmation` triggers TTY prompt |
| **REST** | `POST /<archiform>/<action>` with `inputs` body, `outputs` response; destructive+unconfirmed returns 409 with confirmation token |
| **MCP** | Tool spec — name from action key, description from `summary`, JSON Schema is already MCP's tool schema; confirmation via MCP elicitation |
| **Renderer (Svelte)** | Generated TS client; buttons call it; destructive actions show dialog |
| **Programmatic** | Same TS client, importable from any bun script |

### Streaming, blob input, auth (cross-projection concerns)

Declared once in the manifest:

- `streaming: true` — CLI streams stdout, REST uses SSE, MCP uses
  streaming results, renderer subscribes
- Input field with `format: "blob"` — CLI takes a path, REST takes
  multipart, MCP base64s, renderer takes a `File`
- Auth/identity is **never** in the action body; each projection layer
  resolves it (keychain / bearer token / agent context)

## Alternatives considered

1. **Per-archiform CLI plugin** (git-style PATH discovery, or wasm
   plugin to `jelly`). Rejected as primary framing — couples to one
   projection (CLI), doesn't help REST/MCP/renderer at all. The plugin
   model is correct as a *consequence* of the manifest, not as the
   abstraction itself.
2. **Hand-write per-projection implementations** (one CLI verb +
   one REST handler + one MCP tool per action). Rejected — N×M
   problem; new archiforms would need to write integrations against
   every projection runtime.
3. **Allow interactive prompts inside action bodies.** Rejected —
   breaks agent-callability and forces every projection to support a
   TTY-shaped affordance.

## Consequences

- Sprint-002 ships **CLI + programmatic + MCP** projections (essentially
  the same code path with different output formats). REST and
  in-renderer derivation follow in sprint-003 once the manifest has
  been used in anger and friction is observed.
- `jelly palace mint` etc. continue to work, but become *generated*
  CLI verbs derived from the Memory Palace archiform's action
  manifest, not hand-written Zig code.
- The discipline (no interaction in actions; confirmation as
  attribute) is the only thing the spec must enforce up-front. Every
  other concern is a per-projection mechanical mapping.
- Actions that emit signed envelopes (`effects`) integrate with the
  dual-sig signer story for sprint-002 — the wasm action body emits
  the envelope value, the host signs and persists.

## Aligned with prior art

Pattern shared with: schema.org **Actions**, ActivityStreams 2.0
**Activities**, OpenAPI **Operations**, gRPC **services**. The
projection trick — one declarative surface, many transports — is well
travelled; we are not inventing it, only naming it for DreamBall.
