---
title: Plain-English terminology over Gordian/recrypt vocabulary
date: 2026-04-20
status: accepted
---

# ADR: Rename Gordian/RDF vocabulary to plain English

## Context

The Dreamball spec inherited its wire-format vocabulary from upstream
Gordian Envelopes (via recrypt): *envelope*, *subject*, *assertion*,
*predicate*, *object* — plus graph-theoretic *edge*. During Memory
Palace PRD drafting (2026-04-19) we interrogated each term against
the actual spread of use cases in the spec: plain metadata
properties, pointer-to-node connections, elidable private notations,
nested structured sub-envelopes, cryptographic signatures, and
mutable state values.

The inherited vocabulary was obscuring the design rather than
revealing it. Specifically:

- *predicate* is RDF/logic jargon; readers without that background
  have no intuition for it.
- *subject fields* does not communicate "the load-bearing data that
  defines what this node is."
- *assertion* is better than *statement* but still reads technical —
  it does, however, capture the non-committal/elidable flavour that
  is protocol-essential.
- *edge* is a graph-theory term of art, opaque without graph-theory
  exposure.
- *object* is triple-ambiguous: OOP object, RDF triple-object,
  Gordian assertion-object. It was impossible to use without
  disambiguating every time.

## Decision

Rename throughout the Dreamball docs:

| Gordian / RDF | Dreamball term |
|---|---|
| envelope | **node** |
| subject | **core** |
| assertion | **attribute** |
| predicate | **label** |
| object (terminal) | **value** |
| object (envelope) | **connected node** |
| edge | **connection** |

One-sentence summary, repeated at `docs/PROTOCOL.md §1.2`:
**a DreamBall is a node; its core defines what it is; its attributes
are labeled connections to values or to other nodes.**

The word *attribute* beat *facet*, *entry*, *mark*, *binding*, and
*remark* in a pressure-test against the six example use cases above
plus the stress phrases "signed X", "elidable X", "salted X" — it
was the only candidate that read cleanly in all nine cases. A local
renderer or lens is free to call an attribute a *facet* or
*inscription* where the specific vibe of that lens calls for it; the
spec uses *attribute* uniformly.

## Scope

Renamed everywhere in `docs/`:

- `docs/VISION.md`
- `docs/PROTOCOL.md`
- `docs/ARCHITECTURE.md`
- `docs/products/memory-palace/prd.md`
- `docs/products/dreamball-v2/prd.md`

Wire-format identifiers that had leaked the old vocabulary were also
renamed:

- Envelope type name: `jelly.memory-edge` → `jelly.memory-connection`
- CBOR field keys: `"edge":` → `"connection":` (inside `jelly.memory`)
- Trust-observation core field: `"subject":` → `"about":`
- `jelly.action` core field: `subject-fp` → `target-fp`
- `jelly.knowledge-graph` triple shape: `[subject, predicate, object]`
  → `[from, label, to]`
- CLI argument: `jelly observe <subject-fp>` →
  `jelly observe <observed-fp>`

Preserved (intentional):

- 3D mesh "edge loops" in VISION §4 — different meaning (Disney-style
  base-mesh topology addressing), unambiguous in context.
- Shell-test "assertions" in `docs/known-gaps.md` — different meaning
  (test assertions in e2e scripts).
- External research docs under `docs/research/` — these cite
  external graph-DB literature verbatim and should not paraphrase.
- CBOR tag `#6.201` description references "subject" as the
  upstream Blockchain Commons name, parenthesised.

## Consequences

**Wire-format breaking change accepted.** No production clients or
published DreamBalls exist yet, so forward compatibility was not
load-bearing. The rename was done now specifically to avoid
committing to the old vocabulary under any real-client pressure
later.

**Translation table retained** at `docs/PROTOCOL.md §1.2` for
readers arriving from Gordian/recrypt upstream documentation. The
table is reference-only; the Dreamball spec itself uses only the
right column.

**Code sync — complete as of 2026-04-21.** The bulk landed in
commit `7b0fec8` (wire-format identifiers — `jelly.memory-edge` →
`jelly.memory-connection`, `"edge":` → `"connection":` CBOR key,
triple-field rename on the typed surface, golden fixture
rebaseline); the 2026-04-21 follow-up pass cleaned up the residue:

- `src/envelope_v2.zig` — local `assertion_count` → `attribute_count`
  across all four encoders; comments rewritten to use attribute /
  label / value / core.
- `src/envelope.zig` — public error `StripError.MalformedAssertion`
  → `MalformedAttribute`; a doc-header block clarifies that the
  rest of this file intentionally preserves Gordian-Envelope /
  Blockchain-Commons vocabulary (subject, assertion, predicate,
  object) because it implements the CBOR encoding of that format.
  See the Preserved list below.
- `src/protocol.zig`, `src/wasm_main.zig`, `src/signer.zig`,
  `src/golden.zig` — doc-comments, error messages, and golden-bytes
  test names updated to the new vocabulary.
- `src/cli/dispatch.zig`, `src/cli/join_guild.zig` — CLI help text
  now says "attribute" not "assertion".
- `tools/schema-gen/main.zig` + regenerated `src/lib/generated/`
  (schemas.ts, README.md) — embedded docstrings and the
  `commonCore` (formerly `commonSubject`) schema-spread name.
- `tools/mcp-server/server.ts` — `shared_core_fields` (formerly
  `shared_subject_fields`) in the `/.well-known/mcp` surface.
- `src/lib/wasm/loader.ts`, `src/lib/wasm/loader.test.ts`,
  `src/stories/types/agent.stories.svelte` — comments and test
  names updated.

Validation: `zig build test`, `zig build smoke`, `bun run check`
(1124 files, 0 errors), and `bun run test:unit` (32 files / 123
tests) all pass. Golden Blake3 constants in `src/golden.zig` are
unchanged — the rename did not alter any serialized bytes.

**v1/v2 protocol tables** (PROTOCOL §4, §12) now read in the new
vocabulary. The wire bytes are unchanged where field names were not
renamed; where they were renamed (listed above), the CBOR bytes
differ and the old bytes will no longer parse. Again: acceptable
because no production artifacts.

## Rejected alternatives

- **Keep Gordian vocabulary and add a glossary.** Rejected: the
  glossary would need consulting on every read; the spec itself
  would still be obscure. A rename solves the problem at the root.
- **Rename docs only, leave code on Gordian terms.** Rejected: the
  docs/code gap is worse than either the full rename or no rename.
- **Use *claim* instead of *attribute*.** Rejected: *claim* felt
  too technical and carried cryptographic-assertion overtones that
  were wrong for simple metadata fields like `name` or `revision`.
- **Use *facet* instead of *attribute*.** Rejected: *facet* broke
  on "signed ___" and "salted ___" phrasing.

## Related

- `docs/PROTOCOL.md §1.2` — translation table
- `docs/products/memory-palace/prd.md §9` — Phase 0 code sync task
