# 2026-04-21 — Palace embeds in the dream field; does not become one

## Status

Accepted. Closes PRD `docs/products/memory-palace/prd.md §9` open question
*"Relation to VISION §4.4.5 dream field"*.

## Context

VISION §4.4.5 frames the dream field as "the final layer — beyond the
last onion shell". That phrasing left an ambiguity for the Memory
Palace composition: since a palace is itself a Field DreamBall with
`field-kind: "palace"`, does a palace *become* the dream field for
its contained avatars, or does it *embed* in a dream field that
persists beyond its outermost shell?

The authoritative clarification (2026-04-21, user) reframes the dream
field as **omnipresent substrate, not a boundary layer**:

> "Everything is within the dream field and can interact with it. It's
> not that a DreamBall becomes a dream field, but it can unfold
> aspects of the dream field. … Even when the identity of the DreamBall
> itself is changing, it's all within the context of the dream field.
> This is why we use jelly — we're talking about the plasmatic
> universal underlayer, the vector equilibrium of popping in and out
> of existence, the hawking radiation of our imagination, reality
> itself morphing through the dream field. And yes, you can be fully
> lucid, but dreams present themselves. Sometimes the dream finds you."

This moves the dream field from a rendering concern (the "black void
behind the outermost ball") to a **metaphysical substrate** that every
DreamBall sits inside, interacts with, and can **unfold aspects of**
without ever becoming identical to. Identity morphing, forking,
universe-jumping, and the user-non-chosen "dream that finds you" all
happen *within* the dream field, not *because* a DreamBall has been
promoted to one.

## Decision

1. **A palace embeds in a dream field; it does not become one.** The
   same holds for every other DreamBall type. `jelly.dreamball.field`
   with `field-kind: "palace"` is a container; the dream field is the
   substrate the container floats in.

2. **The dream field is omnipresent, not boundary-layer.** VISION §4.4.5
   is revised (companion commit) from "the final layer beyond the last
   onion shell" to "the plasmatic substrate every DreamBall sits within
   and can unfold aspects of". The onion-shell phrasing is preserved as
   a *rendering* description (what a viewer sees at the outermost shell
   is the dream field showing through), not a topological one.

3. **Identity morphing happens within the dream field, not by becoming
   one.** When a DreamBall's identity changes (revision bump, `derived-from`
   fork, universe-jump in a lucid session), the change is mediated by the
   dream field as substrate. The protocol does not add a new envelope for
   this; the existing `contains` / `derived-from` connections plus the
   timeline's signed actions suffice. The dream field is the *context*
   those actions happen within, not an additional wire surface.

4. **Unfolding vs. becoming.** A DreamBall MAY carry a
   `dream-field-aspect` attribute (Vision tier) naming an archetypal
   facet it is currently expressing — e.g. `"zero-point"`, `"plenum"`,
   `"fork"`, `"lucid"`, `"dream-finds-you"`. The attribute is decorative
   at the protocol level; renderers and oracles MAY honour it to
   modulate ambient tint or reasoning. MVP does not ship this attribute;
   the placeholder is reserved so downstream work can add it without a
   `format-version` bump.

## Consequences

- **Rendering.** The omnispherical lens gains an ambient-dream-field
  hook separate from the outermost Field envelope. When rendering a
  palace, the renderer asks "which dream field aspect is active?"
  before choosing the default (trivially, a black void). No wire-format
  change for MVP.

- **Lucidity / intentionality.** The renderer and oracle treat
  DreamBall transitions along two axes: **lucid** (author-intended,
  signed action, timeline-visible) and **presenting** (emerges from
  the dream field, may surface without explicit user action). Both
  are legitimate; the protocol records the lucid ones and the
  resonance kernel (§6.3) surfaces the presenting ones. No new
  envelope required; the distinction is encoded in the `action-kind`
  taxonomy already specified in PRD §5.3.

- **Composition.** `derived-from` (v1) continues to carry fork
  semantics unchanged. This ADR does not promote forking into a
  dream-field-level protocol event — it only names the substrate
  forks happen in.

- **Phase 1 impact: none on wire format.** The palace envelope work
  (nine auxiliary envelopes in PRD §5) proceeds as specified. The
  implementation cost of this ADR is one hook in the renderer's
  ambient pass and a one-line note in VISION §4.4.5.

- **Future work (Vision tier).** A `jelly.dream-field` envelope naming
  persistent archetypal field states (e.g. a shared dream field a
  community palace embeds in) may be introduced post-MVP. This ADR
  leaves the door open without specifying the wire surface.

## References

- `docs/VISION.md §4.4.5` — to be updated in a companion commit so
  the "beyond the last shell" phrasing no longer implies a boundary.
- `docs/products/memory-palace/prd.md §9` — open question closed by
  this ADR.
- User clarification conversation, 2026-04-21 — context section above
  preserves the load-bearing prose.
