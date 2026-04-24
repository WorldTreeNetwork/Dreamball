# 2026-04-24 — Surface registry & fallback chain

Sprint: sprint-001 · Epic: 5 · Significance: MEDIUM · Related:
[PRD §6](../prd-rendering-engines.md) · PROTOCOL.md §13.7

## Context

`jelly.inscription.surface` is already declared as `<open-enum>` in
PROTOCOL.md §13.7 — the five named surfaces (`scroll`, `tablet`,
`book-spread`, `etched-wall`, `floating-glyph`) are canonical but not
exhaustive. Sprint-001's `InscriptionLens.svelte` hard-codes dispatch on
those five, with unknown surfaces falling back to `scroll` plus a
`console.warn`. This is the right runtime shape, but the *cross-engine*
story isn't spelled out: when an Unreal lens registers different
surfaces (`rune-pillar`, `holo-panel`), or when a future Web lens adds
`splat-scene` or `volumetric`, authored inscriptions shouldn't need to
know which engines will render them.

## Decision

**Surfaces are open strings; lenses publish surface registries; authors
MAY attach a fallback chain.** Concretely:

1. **`surface` stays `<open-enum>` on the wire.** No schema change;
   codegen emits `string` (not a Valibot union).
2. **Each lens implementation publishes a registry** — the list of
   surfaces it natively renders. For sprint-001's Web lens:
   `["scroll", "tablet", "book-spread", "etched-wall", "floating-glyph"]`.
   The registry lives adjacent to the dispatcher, not on the wire.
3. **`scroll` is the canonical baseline.** Every lens MUST render
   `scroll`. This is the protocol's minimum rendering contract for
   inscriptions. An inscription with `surface: "scroll"` works
   everywhere, forever.
4. **Authors MAY attach an optional `fallback` attribute** — an ordered
   list of surfaces to try if the primary isn't registered by the
   current lens. Example wire:
   ```
   "surface":  "splat-scene",
   "fallback": ["floating-glyph", "etched-wall", "scroll"]
   ```
   On render, the lens walks: `surface → fallback[0] → fallback[1] → … → "scroll"`.
5. **Unknown surfaces emit a single structured log entry** — today's
   `console.warn("unknown surface: mosaic — falling back to scroll")`
   stays, but adopts a stable format so other lenses can reproduce it:
   `{level: "info", event: "surface-fallback", requested, resolved, lens}`.

## Wire change

Add one optional attribute to `jelly.inscription` in PROTOCOL.md §13.7:

```
"fallback":  ["tablet", "scroll"]    ; optional; ordered list of surfaces to try
```

Old readers ignore it (CBOR attribute extension). No format-version
bump.

## Alternatives considered

1. **Closed union (status quo).** Rejected — adding a new surface
   becomes a protocol change, breaks codegen for older browsers,
   creates a coordination problem between engines.
2. **Surface as a nested envelope with required implementation
   metadata.** Rejected — over-engineered; inscriptions would carry
   engine-specific details they don't author.
3. **Lens-registered surfaces only, no fallback chain.** Rejected —
   leaves authors guessing which engines ship which surfaces. Fallback
   is cheap to add and lets authors express intent.

## Consequences

- `InscriptionLens.svelte` (Sprint-001 Story 5.4) implements the
  registry walk; AC2 updated to cover the fallback chain in addition to
  the unknown-surface → scroll path.
- Future engines (Unreal, Blender, MR/VR) can register their own
  surfaces without coordinating with the Web engine.
- The five canonical web surfaces remain canonical because `scroll` is
  the baseline and all five can be named in any engine's fallback
  chain.
- A future `"surface": "splat-scene"` inscription with
  `"fallback": ["tablet", "scroll"]` renders as a splat on lenses that
  support it, as a tablet on those that don't yet, and as a scroll on
  the minimum baseline.

## Aligned with existing pattern

Follows the protocol's existing `<open-enum>` convention (used for
`action-kind`, `form`, etc.). The fallback chain mirrors how HTML
handles unknown elements (treated as inline) and how glTF extensions
handle `extensionsRequired` vs `extensionsUsed`.
