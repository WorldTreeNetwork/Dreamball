# Memory Palace — Wire Extensions (auxiliary envelopes)

> Extracted verbatim from the canonical wire spec
> [`../../PROTOCOL.md`](../../PROTOCOL.md). These are the auxiliary envelopes
> of the Memory Palace archiform (timeline, action, aqueduct, mythos,
> inscription, archiform, …). **Section numbers (§13.x) are preserved from
> the root spec** for cross-reference stability. References to §12.x are the
> v2 reference types in [`../dreamball-v2/protocol.md`](../dreamball-v2/protocol.md);
> substrate framing is in the root spec; the *why* lives in
> [`vision.md`](vision.md).

---

## 13. Memory Palace composition — auxiliary envelopes

**Status:** Draft v1 — 2026-04-20.
**Scope:** One optional core field on `ball.dreamball.field`,
plus nine auxiliary envelope types introduced by the Memory Palace
composition (see [`docs/products/memory-palace/prd.md`](products/memory-palace/prd.md)
for the product spec and [`products/memory-palace/vision.md`](products/memory-palace/vision.md)
for the descriptive rationale).
**Rationale:** The palace is a *specific composition* of the v2
primitives, not a new protocol. Every envelope here is additive; v2
parsers without palace support see these as unknown attributes and
skip. No existing envelope gains or loses core fields.

### 13.1 The `field-kind` attribute

`ball.dreamball.field` (§12.1.5) gains **one optional attribute**:

```
"field-kind": "palace" | "room" | "ambient" | <open-enum>
```

| Value | Meaning |
|---|---|
| `"palace"` | A Memory Palace root. MUST carry a `ball.mythos` attribute (§13.8). Renderer routes to the `palace` lens. |
| `"room"` | A contained room inside a palace. Rendered only when the parent palace is the active Field. |
| `"ambient"` | The dream-field meaning from VISION §10.4.5 — environmental context for non-palace compositions. |
| *absent* | The v2 default. Behaves exactly as specified in §12.1.5. |

**Why an attribute, not a core field.** v2 §12.1 codified the
rule that "the difference between [Field variants] lives in
*attributes*." `field-kind` follows that pattern: elidable,
salt-friendly, additive without bumping `format-version`. Rendering
engines route on the attribute exactly as they would on a core
field. A Field with an unrecognised `field-kind` value MUST be
treated as if the attribute were absent; no other envelope types
are affected.

### 13.1.1 The `archiform-fp` attribute (genesis archiform binding)

`ball.dreamball.field` carries an optional **`archiform-fp`**
attribute on its genesis envelope:

```
"archiform-fp": h'…32 bytes…'    ; blake3 of the archiform schema body
```

The fingerprint is the canonical content-address of the archiform
schema this ball was minted against — for sprint-002 instances of
`field-kind: "palace"`, that is `blake3(<schemas/memory-palace-0.1.0.json>)`.
Future archiforms (forge, throne-room, library) reuse the same
mechanism with their own schema bodies.

**Immutable for the ball's lifetime.** Once the genesis envelope
declares an `archiform-fp`, every subsequent envelope, mutation, or
revision MUST preserve the value byte-for-byte. The archiform is
the ball's *species*, not its state — see
[`docs/sprints/002-archiform-foundation/architecture-decisions.md`](sprints/002-archiform-foundation/architecture-decisions.md)
D-017. Drift between two envelopes for the same ball is a verifier
error.

**Additive back-compat (sprint-001 instances).** Pre-sprint-002
genesis envelopes pre-date this attribute. Decoders MUST tolerate
its absence and substitute the implicit binding to
`dreamball/memory-palace@0.1.0` — the canonical schema fp recorded
at `schemas/.pins/memory-palace-0.1.0.fp`. Sprint-002 producers
emit the attribute on every new genesis; sprint-001 consumers
ignore the unknown attribute (CBOR open-extension semantics) and
continue to verify.

### 13.2 `ball.layout`

A Room or Palace Field carries a `layout` attribute that records
where its children sit in its local coordinate frame. The layout is
a **rendering hint**, not a security claim — multiple layouts can
coexist (the palace shifts; see PRD J5 and `products/memory-palace/vision.md` §7).

```
200(
  201({ "type": "ball.layout", "format-version": 2 })
) [
  "placement":  { "child-fp": h'…32…',
                  "position": [x, y, z],
                  "facing":   [qx, qy, qz, qw] },          ; quaternion
  "placement":  { … },                                     ; repeatable
  [salted] 'note':  "autumn arrangement"
]
```

**Float exception.** Coordinates and quaternion components use the
same `#7.25` half-float / `#7.26` single-float rule already carved
out for `ball.omnispherical-grid` in §12.2. No other fields use
floats.

**Coordinate-frame composition (D-027).** Two coordinate regimes coexist:

- **Polar** at the omnispherical-grid (field) layer — matches the
  semantic intent of the dreamsphere (latitude, longitude, radius).
- **Cartesian** (right-handed, Y-up, meters, glTF-2.0 quaternion
  order) for placements local to a parent DreamBall.

Nested reference frames compose via cached world matrices
(`resolveWorldMatrices`); the GPU consumes
`worldMatrix × localPosition` — no polar arithmetic in shaders.

Sprint-001 shipped a simplified path (single reference frame, no
`polarShellToCartesian`). Full multi-frame resolution and the
`polarShellToCartesian` conversion are Growth-tier work. See
[`docs/decisions/2026-04-24-coord-frames.md`](decisions/2026-04-24-coord-frames.md)
(D-027) for the full rationale and alternatives considered.

### 13.3 `ball.timeline` + `ball.action`

A signed, hash-linked DAG of actions taken inside the palace.
Append-only per keypair; Merkle-rooted by the **head set**; any
cryptographic-clock semantics can be derived without a central
authority. Multi-parent actions enable merge semantics (conflict
resolution is PRD FR68, Vision).

```
200(
  201({ "type": "ball.timeline", "format-version": 3,
        "palace-fp": h'…32…'                 ; 1:1 identity anchor — which palace this timeline belongs to
  })
) [
  "head-hashes":  [h'…32…', h'…32…'],         ; set, cardinality ≥ 1 — Blake3 of each current leaf ball.action
  "action":       <ball.action envelope>,    ; repeatable, ordered by parent-hash chain
  [salted] 'note': "genesis timeline"
]
```

**`head-hashes` is a set, not a single hash.** A timeline with no
concurrent activity has exactly one head; multi-writer shared
rooms (FR68) transiently hold multiple heads until a merge action
lands. Verifiers MUST accept any cardinality ≥ 1 and walk back from
*every* head to the genesis. When cardinality drops to 1 after a
merge, the timeline is fully reconciled.

`head-hashes` lives in an attribute, not the core, because it is
the timeline's current *state*, not its *identity*. The core
stays stable across the timeline's entire life: `palace-fp` binds
the timeline to exactly one palace. Re-signing on append is still
required, but the core digest does not churn — the Merkle tree
over attributes is what changes.

**Format bump.** The shift from `head-hash` (singular, v2) to
`head-hashes` (set, v3) is a wire change. v2 timelines with a
single `head-hash` are accepted on read and rewritten as a
1-element `head-hashes` set on the next append.

`ball.action` core:

```
{
  "type":           "ball.action",
  "format-version": 3,
  "action-kind":    "inscribe"|"move"|"unlock"|"true-naming"|"shadow-naming"|…,
  "parent-hashes":  [h'…32…', h'…32…'],       ; ACKS — previous head(s) acknowledged; one for linear history, multiple for merges
  "actor":          h'…32…'                    ; fingerprint of the signer
}
```

Attributes: `timestamp` (CBOR tag 1), `target-fp` (what the action
was performed on, if any), free-form per-kind payload, dual
signatures, and two optional DAG-relation attributes below.

**Optional `deps` attribute — logical dependencies (adapted from
NextGraph's DEPS).** `parent-hashes` conflates two concerns: the
prior head(s) this action acknowledges (ACKS), and the earlier
actions this one logically depends on (a `move` of an item
depends on the `inscribe` that created it; a `true-naming` depends
on the `reflect` session that surfaced it). When the distinction
matters — typically for renderer highlighting, diagnostic
traversal, or "what is the minimum causal slice of history
required to replay this action?" queries — authors MAY add an
optional `deps` attribute:

```
"deps": [<ball.action-ref>, <ball.action-ref>, ...]  ; repeatable; logical predecessors; disjoint from parent-hashes
```

Absent = no explicit logical dependencies beyond ACKS. Not
load-bearing for verification: walk still proceeds via
`parent-hashes`. Load-bearing for "causal slice" queries.

**Optional `nacks` attribute — invalidation (adapted from
NextGraph's NACKS).** An action that invalidates earlier actions
on the same timeline MAY list their refs in a `nacks` attribute:

```
"nacks": [<ball.action-ref>, ...]  ; repeatable; invalidated prior actions
```

Used by `dreamball palace rewind` (FR67) and by the FR60g "shadow-
naming" flow (a quorum-resolved canonical `true-naming` `nacks`
the losing branch's `true-naming` candidate, preserving it on the
timeline as a read-only record). Verifiers accept `nacks` entries
that reference existing actions; they do not require the
referenced action to be reachable from any current head.

**Chain rules.**

- Every signed action's `parent-hashes` MUST resolve to previously
  signed actions in the same palace's timeline.
- Verification walks back from *every* entry in `head-hashes` to
  the first action (whose `parent-hashes` is empty); a gap on any
  walk is a hard failure.
- An action whose `parent-hashes` points outside the palace's
  timeline is rejected with "foreign parent."
- `deps` and `nacks` refs MUST resolve to actions in the same
  palace's timeline but are NOT required to be reachable from the
  current head set.

**`ball.action-ref` shorthand.** A 32-byte Blake3 of a
`ball.action` envelope's canonical bytes. Used from other envelopes
(notably `ball.mythos.discovered-in`, §13.8) to cite a specific
action on the timeline without embedding it. Wire-level, it is a
plain byte-string — the name exists only for readability in this
document.

### 13.4 `ball.aqueduct`

A directed, typed, weighted connection carrying **Vril** (see `products/memory-palace/vision.md` §3).
The electrical-style fields are **load-bearing** — both the renderer
(particle speed, glow density, pulse phase) and the oracle
(diagnostic reasoning) consume them. Aqueducts sit *on top of* the
cold `contains` graph without polluting it.

```
200(
  201({ "type": "ball.aqueduct", "format-version": 2,
        "from": h'…32…',
        "to":   h'…32…',
        "kind": "gaze"|"visit"|"transmit"|"inscribe"|"resource"|"ley-line"|<open-enum>
  })
) [
  "capacity":    0.85,    ; 0.0–1.0, soft prior (declared)
  "strength":    0.12,    ; 0.0–1.0, grows with traversal (measured)
  "resistance":  0.30,    ; 0.0–1.0, impedance (declared)
  "capacitance": 0.55,    ; 0.0–1.0, endpoint pooling (declared)
  "conductance": 0.70,    ; 0.0–1.0, derived: (1 - resistance) × strength
  "phase":       "in"|"out"|"standing"|"resonant",
  [salted] "last-traversed": 1(…)
]
```

All numeric fields use half-floats (`#7.25`) under the §12.2 float
exception.

**`conductance` is an intermediate accumulator, not a load-bearing
derivation.** True conductance in a Vril network depends on
neighbour flow, which depends on *their* neighbours — an
EigenTrust/PageRank-shaped iterative problem with no closed-form
solution. The stored value is the author's best-effort snapshot at
signing time. Verifiers MUST NOT reject on `conductance` mismatch;
runtimes MAY recompute opportunistically and overwrite in place; a
palace MAY be instructed to reset-and-reflow (discard all stored
`conductance` values and re-iterate) without loss of correctness.
See PRD §5.4 for the rationale.

`kind = "ley-line"` denotes a purely energetic connection with no
walkable correspondence — rendered as a ghostly underlay beneath
the walkable palace geometry.

### 13.5 `ball.element-tag`

Open elemental/phase classification. A tag, not a schema — downstream
systems elect whether to honour it. Orthogonal to `ball.archiform`
(§13.9): form answers "what kind of space is this?"; element answers
"what quality of energy animates it?"

```
200(
  201({ "type": "ball.element-tag", "format-version": 2 })
) [
  "element":   "wood"|"fire"|"earth"|"metal"|"water"|"seed"|"tree"|"lightning"|"air"|<open-enum>,
  "phase":     "nourishing"|"destruction"|"yin"|"yang"|<open-enum>,   ; optional qualifier
  [salted] 'note': "seed / potential / green"
]
```

Element/phase enums are intentionally open. The protocol does not
prescribe a tradition (five-element, nine-element, alchemical,
hermetic, etc.); the palace's archiform registry (§13.9) may bundle
a preferred taxonomy.

### 13.6 `ball.trust-observation`

A signed, local observation one actor emits about another.
**Decentralised by construction** — never aggregated into a
universal score at the protocol level; aggregation is reader-side
policy, typically weighted by social-graph distance.

```
200(
  201({ "type": "ball.trust-observation", "format-version": 2,
        "observer": h'…32…',    ; signer
        "about":    h'…32…'     ; about whom (fingerprint of the party being observed)
  })
) [
  "axis":        { "name": "careful",  "value": 0.78, "range": [0.0, 1.0] },
  "axis":        { "name": "generous", "value": 0.61, "range": [0.0, 1.0] },
  [salted] "observed-at": 1(…),
  [salted] "context":     "pair-programming sessions 2026-04",
  'signed':      Signature(ed25519, …),
  'signed':      Signature(ml-dsa-87, …)
]
```

**Rules.**

- Observations are never transmitted implicitly. Transport is always
  an explicit `dreamball transmit`, scoped to a Guild.
- Axis values use the §12.2 float exception.
- Slot-level privacy follows `ball.guild-policy` (§12.7). Default
  policy places trust observations in the `guild-only` bucket.

### 13.7 `ball.inscription`

An Avatar DreamBall whose `look` geometry is *text arranged in
space*. Rendered by the new `inscription` lens (PRD §6.1) or
falls back to the `flat` lens with the markdown body.

```
200(
  201({ "type": "ball.inscription", "format-version": 2 })
) [
  "source":    <ball.asset envelope>,              ; media-type: text/markdown, text/plain, text/asciidoc, …
  "surface":   "scroll"|"tablet"|"book-spread"|"etched-wall"|"floating-glyph"|<open-enum>,
  "fallback":  ["tablet", "scroll"],                ; optional ordered fallback chain; see surface registry below
  "placement": "auto"|"curator",                    ; auto = renderer chooses; curator = parent room's ball.layout
  [salted] 'note': "lives on the east wall"
]
```

Because `source` is content-addressed (Blake3 of file bytes), a
markdown file on disk and its inscription in a palace share an
identity. File-watcher logic on the oracle side can keep them
synchronised (PRD FR72, Growth).

**Surface registry (D-026).** The `surface` value is an **open string**
on the wire — new surfaces can be registered without a protocol version
bump. Each lens implementation publishes its own registry of natively-
rendered surfaces.

Rules:

- `"scroll"` is the **mandatory baseline** — every lens MUST be able to
  render it. An inscription with no recognised surface always falls back
  here.
- Authors MAY attach an optional `fallback` attribute — an ordered array
  of surface names to try before reaching `"scroll"`. The renderer walks
  `surface → fallback[0] → fallback[1] → … → "scroll"`, stopping at the
  first surface its lens registry knows how to render.
- **Cycle detection.** If the fallback chain contains a cycle (e.g.,
  `surface: "A"`, `fallback: ["B", "A"]`), the renderer emits a
  `surface-fallback-cycle` event and breaks immediately to `"scroll"`.
- Per-lens registries are the extension point: Unreal, Blender, and
  MR/VR lenses may support surfaces (`"holographic-slab"`,
  `"depth-texture"`) that the reference Svelte lens does not; the
  fallback chain lets authors declare graceful degradation paths across
  lens implementations.

### 13.8 `ball.mythos`

The keystone. See `products/memory-palace/vision.md` §2 for the *why*. Wire:

```
200(
  201({ "type": "ball.mythos", "format-version": 2,
        "is-genesis":  <bool>,                      ; true iff this is the first mythos of this chain (canonical or poetic)
        "predecessor": h'…32…'                     ; Blake3 of the prior ball.mythos envelope; absent iff is-genesis
  })
) [
  "about":        h'…32…',                                           ; POETIC ONLY — fingerprint of the DreamBall this mythos is about; absent on canonical (embedded) chains
  "form":         "blurb"|"invocation"|"image"|"utterance"|"glyph"|"true-name"|<open-enum>,
  "body":         "There is a giant cow beside the chaos abyss.",    ; the mythos in full poetic form
  "true-name":    "Audhumla",                                         ; optional condensed totem
  "source":       <ball.asset envelope>,                             ; optional longer form
  "discovered-in":<ball.action-ref>,                                 ; CANONICAL ONLY — paired 'true-naming' action on the palace timeline
  "synthesizes":  [h'…32…', h'…32…'],                                ; CANONICAL ONLY — poetic mythoi that informed this renaming (attribution)
  "inspired-by":  [h'…32…', h'…32…'],                                ; POETIC ONLY — other mythoi this author was thinking with
  [salted] "author":      h'…32…',
  [salted] "authored-at": 1(…)
]
```

**Two kinds of chain.** A DreamBall MAY have:

- A **canonical chain** — signed by the DreamBall's custodian(s),
  embedded as a `ball.mythos` attribute directly on the DreamBall
  envelope, `about` absent. Load-bearing on identity. A
  `ball.dreamball.field` with `field-kind: "palace"` MUST carry at
  least the genesis canonical mythos.
- Zero or more **poetic chains** — each signed by a visitor,
  standalone envelopes carrying `about: <dreamball-fp>`, discoverable
  via the aspects.sh registry (§13.9) or local query. Decorative on
  the DreamBall's identity; load-bearing on the visitor's
  relationship to it.

The wire shape is identical for both; the distinction is **who
signed it** plus **whether `about` is present**. `discovered-in` /
`synthesizes` may appear only on canonical links; `inspired-by` may
appear only on poetic links. Mixing (e.g., a canonical link with
`about` present, or a poetic link with `discovered-in`) is a
protocol error and rejected at verify time.

**Core fields** are both load-bearing:

| Field | Type | Rule |
|---|---|---|
| `is-genesis` | bool | `true` on exactly one mythos per chain; immutable thereafter. |
| `predecessor` | 32 bytes | Blake3 of the prior `ball.mythos` envelope bytes *in the same chain*. MUST be absent iff `is-genesis` is `true`; MUST be present otherwise. |

**Chain rules.**

- Each chain is append-only within itself. Publishing a link whose
  `predecessor` doesn't resolve to a verifiable prior link in the
  same chain is rejected.
- Only the DreamBall's custodian(s) may extend the **canonical**
  chain — for a solo DreamBall, the identity keypair; for a
  Guild-owned one, any admin (Guild-policy-scoped quorum is Vision,
  PRD FR60g). Non-custodian-signed mythoi pointing at the DreamBall
  are always poetic, never canonical.
- Every canonical chain extension MUST emit a paired `ball.action`
  of `action-kind: "true-naming"` on the owning palace's timeline.
  The mythos envelope's `discovered-in` points back at that action.
  Poetic chains do NOT emit timeline actions — they are a personal
  act, not a palace-state change.
- The canonical chain is **always public** regardless of Guild
  policy; individual `discovered-in` reflections MAY be
  `guild-only`. Poetic chains follow their author's own policy —
  they are independent envelopes under their author's keypair.
- Divergence beyond synthesis: a visitor whose poetic chain has
  drifted too far from the canonical chain MAY fork by minting a
  new DreamBall with a `derived-from` connection (v1 primitive) and a
  fresh genesis canonical mythos. No new protocol support needed.

### 13.9 `ball.archiform`

Archetypal form classification. Tag, not schema. Orthogonal to
`ball.element-tag` (§13.5) and to the six v2 DreamBall types.

```
200(
  201({ "type": "ball.archiform", "format-version": 2 })
) [
  "form":        "library"|"forge"|"throne-room"|"garden"|"courtyard"|"lab"|"crypt"|"portal"|"atrium"|"cell"|"scroll"|"lantern"|"vessel"|"compass"|"seed"|"muse"|"judge"|"midwife"|"trickster"|<open-enum>,
  "tradition":   "hermetic"|"shinto"|"vedic"|"computational"|"none"|<open-enum>,    ; optional lineage
  "parent-form": "atrium",                          ; optional — the archiform this one specialises
  [salted] 'note': "catalogues rather than restricts"
]
```

The `form` enum is open. The **authoritative registry lives at
[aspects.sh](https://aspects.sh)** — a general-purpose schema
registry that resolves archiform identifiers (and, by the same
mechanism, registers poetic mythoi under §13.8). A palace resolves
via aspects.sh at load time and caches locally; palaces published
offline or into an isolated network MAY snapshot the registry as a
`ball.asset` of media-type
`application/vnd.palace.archiform-registry+json` for air-gapped
use. The `parent-form` field turns the archiform vocabulary into a
DAG; renderers walk parents to resolve unspecified defaults.

Archiform MAY appear on any DreamBall. It does not constrain the
envelope's slot surface; it hints to renderers, oracles, and
collaborators.

### 13.10 Attachment layout in the .ball bundle

Palace compositions do not change §12.10's attachment layout.
Large inscriptions (media of sufficient size to benefit from
sidecar transport) use the existing user-attachment slot (`1+`).
Sealed rooms use the Relic sealed-payload slot (`0`) exactly as
v2 specifies.

### 13.11 Golden-bytes lock

`src/golden.zig` gains **thirteen new fixtures**. The fixtures pin
canonical byte output for:

1. `ball.dreamball.field` with `field-kind: "palace"` attribute
   (minimal).
2. `ball.layout` with two placements.
3. `ball.timeline` with 1-element `head-hashes` set (quiescent).
3a. `ball.timeline` with 2-element `head-hashes` set (concurrent writers, unmerged).
4. `ball.action` single-parent variant.
5. `ball.action` multi-parent variant.
5a. `ball.action` with `deps` and `nacks` attributes populated.
6. `ball.aqueduct` with all numeric fields populated.
7. `ball.element-tag` with `phase` qualifier.
8. `ball.trust-observation` with two axes + both signatures.
9. `ball.inscription` with embedded markdown asset.
10. `ball.mythos` canonical genesis.
11. `ball.mythos` canonical successor with `synthesizes`.
12. `ball.mythos` poetic (with `about` attribute).
13. `ball.archiform` with `parent-form` set.

### 13.12 Migration

- **Mostly additive.** Every introduction here is new, with one
  wire-format change: `ball.timeline` and `ball.action` bump to
  `format-version: 3` to carry the `head-hashes` set (was
  `head-hash` singular) and the optional `deps` / `nacks`
  attributes on actions. Readers accept v2 timelines and normalize
  `head-hash` → 1-element `head-hashes` on the next append. Every
  other new envelope in this section carries `format-version: 2`.
  No v1 or v2 envelope outside `ball.timeline`/`ball.action`
  gains or loses core fields.
- **v2 consumers without palace support.** Unknown attributes on a
  known envelope skip silently, preserving §9's versioning rule. A
  v2 consumer rendering a palace-flavoured Field without palace
  support sees a plain v2 Field and renders via the existing
  `omnispherical` lens — degraded but valid.
- **Pre-FR68 wire tweaks.** The `head-hashes` pluralisation, the
  `deps`/`nacks` optional attributes on `ball.action`, and the
  `quorum-policy` attribute on `ball.guild-policy` (§12.7) are
  landed as spec-only changes ahead of FR68 code work to avoid a
  later breaking wire revision. Rationale in
  `docs/decisions/2026-04-21-nextgraph-crdt-review.md`.

### 13.13 Open questions

Tracked in the Memory Palace PRD §9 rather than duplicated here.
Summary of protocol-shape-affecting ones:

1. **CRDT merge semantics for the timeline DAG.** Multi-writer
   merges are Vision (PRD FR68). Pre-FR68 wire tweaks landed
   2026-04-21 (`head-hashes` set, optional `deps`/`nacks` on
   actions) so the envelope shape can accommodate the merge
   without a future breaking change. The merge *algorithm* (who
   emits the merge action, conflict-surfacing policy) remains
   open.
2. **Mythos quorum on Guild-owned palaces.** PRD FR60g Vision.
   Wire shape landed 2026-04-21 as `ball.quorum-policy` under
   `ball.guild-policy` (§12.7) — enforced via stacked `'signed'`
   attributes rather than a threshold-aggregate scheme. Default
   today remains any-admin.
3. **Archiform registry federation.** Community-defined archiforms
   may fragment without a shared root registry. Deferred.
4. **NextGraph overlap.** Before locking CRDT and threshold-signature
   semantics, read `docs.nextgraph.org/en/specs/` (convergence noted
   in PRD §6.2.2) to avoid reinventing their solutions in an
   incompatible shape.

---
