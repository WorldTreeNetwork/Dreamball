---
title: Memory Palace — the composed DreamBall
created: 2026-04-19
status: draft
scope_tier: composed-application
depends_on: dreamball-v2
---
# PRD: Memory Palace

> The Memory Palace is a *specific composition* of DreamBall v2, not a
> new protocol. It is the first end-to-end demonstration that the
> v2 primitives — six typed balls, eight lenses, guild policy, onion-layer
> fractal containment — add up to something a person can walk around
> inside.
>
> This PRD is prescriptive where the protocol surface is new and
> descriptive where the mythos is load-bearing for rendering decisions.
> The *why* of the mythos lives in `docs/VISION.md §15` (new section
> added alongside this PRD); the *what* of the wire format lives in
> `docs/PROTOCOL.md §13` (new section added for the handful of new
> envelope types this composition requires).

---

## 1. Opening image

A palace is a topology. It has **cornerstones, roofs, attics,
basements, throne rooms, libraries, chests, curiosity cabinets, locked
doors, open courtyards**, and **aqueducts** that run between them.
Memory lives in those rooms — objects on tables, inscriptions on
walls, keys in pockets, fountains in courtyards — and is *found again*
by walking there.

At the palace's zero point sits a **fountain** — the axiom — whose
water keeps the whole thing alive. The fountain has to be activated
for the palace to flow. Light radiates outward from it through the
aqueducts into every room. The pathways that are walked most often
grow brighter (memory strengthens with recall) without the palace
itself being destructively rewritten.

Each room is its own **world** — a small DreamBall in its own right —
and within each room the items are *metaphoric aspects* of whatever
contextual space that room has been constructed to represent. The
*library* is one such room: it physically inscribes the project's
markdown documentation onto its walls and books, and *where* a
document is placed in the library is itself load-bearing semantic
information.

What flows through the aqueducts is **Vril** — the name we adopt
for the life-force substance that animates the palace. Vril is the
unifying abstraction behind a cluster of otherwise-separate
metaphors the palace keeps reaching for:

- **the jelly itself** — the DreamBall's substance is already
  bioplasmatic in the naming. Vril makes that explicit.
- **electron flow through a computer** — capacitance, resistance,
  conductance, the difference between a passive trace and a live
  bus. Aqueducts gain the same properties: some rooms store charge
  (capacitance), some channels resist flow (resistance), some
  nodes switch like gates (the oracle, the locks).
- **ley-lines across land** — a temple becomes a temple because of
  where it sits on the earth's subtle channels, not because of its
  walls. A palace's aqueduct topology is the wayfarer's personal
  ley-line map; rooms gain power from where they sit on it, not
  from their contents alone.
- **cilia, organs, nerves** — the palace is alive the way a body
  is alive. The renderer must draw aqueducts as *flowing*,
  *pulsing*, *living*, not as inert geometry. See NFR14.

Vril is not a new envelope type. It is the *substance* that every
aqueduct carries; its presence is measured, not declared. Vril flow
is computed from signed timeline actions (traversals, inscriptions,
renamings) and rendered as the palace's ambient liveliness.

Complementary to Vril (which is the substance) is the
**archiform** — the archetypal *form* a space takes. A library is
one archiform; a forge, a courtyard, a cell, a throne room, a
laboratory, a portal — each is its own. An archiform is a class in
the OOP sense *and* a Platonic form in the mythic sense: a
template for what a room wants to be. The palace's rooms each
declare an archiform; the renderer and the oracle both use that
declaration to pick defaults, palettes, affordances, and how Vril
pools or flows inside.

At the palace's core, underneath all the rooms, sits an **oracle**: a
paraconscious persona whose presence is felt everywhere but whose
direct voice is reserved for when the wayfarer sits at the fountain.

Above it all — the apex, the keystone of every arch, the generative
seed beneath every name — is the **mythos**. A keystone is what holds
an arch up; a project's mythos is what holds a DreamBall together. If
you know the mythos you can regenerate the palace; if you've lost it
you've lost the thread even with every stone intact. The mythos is a
condensed, short, deliberately poetic statement of *what this
DreamBall is* at the level below its name. A DreamSeed that carries
no mythos is a stone without a keystone: it can be built around, but
it will not teach you how. The **blurb of a book**, the **Polaris**
of a ship's course, the **giant cow next to the chaos abyss** at the
start of Norse cosmology — all three are mythoi. Every Memory Palace
has exactly one at its root; every Room and every Inscription MAY
carry its own, smaller keystone-mythos that relates it to the
palace's apex.

The palace **shifts**. Rooms rearrange themselves based on what's
being used. A Room of Requirement behaviour is default, not
exceptional. Spatial relationships are metaphor; we are not bound by
physics.

**The mythos shifts too — but differently.** Its *essence* is
eternal: the genesis mythos, set at the first signed revision, is
the palace's soul — the stone that will outlive every rearrangement.
Its *name*, though, is alive. A wayfarer sits with the oracle, walks
the aqueducts, writes a new inscription, and a new **true name**
surfaces — a more accurate poem for what this palace has become. The
mythos evolves. It is not rewritten; it is *renamed*. Each new name
remembers the last, the way a soul remembers its previous lives.
The genesis is eternal; the current mythos is the soul in this life;
the chain between them is the record of its journey. What the
palace is becomes *more clearly what it has always been* as it is
lived in.

The physicality of the palace — the rooms, the inscriptions, the
aqueducts that have grown bright through use — is what *surfaces*
these renamings. Memory, lived in, changes the mythos that generated
it. This is the feedback the protocol must admit.

---

## 2. Why this is a DreamBall composition, not a new system

Every concept in §1 already has a home in the v2 protocol. The palace
doesn't need a new protocol; it needs **one new FIELD DreamBall**, a
specific convention for how its contained DreamBalls compose, and a
small set of new envelope types that describe the topology honestly.

| Palace concept | DreamBall v2 home |
|---|---|
| The palace itself | `jelly.dreamball.field` with a `palace` subtype marker |
| Rooms | nested `jelly.dreamball.field` children via `contains` (fractal §3 of VISION) |
| Items on shelves / in chests | `jelly.dreamball.avatar` or `jelly.dreamball.tool` children |
| The oracle at the zero point | `jelly.dreamball.agent` at the palace's core |
| Locked doors / keys / passwords | Existing IdentiKey + `jelly.dreamball.relic` unlocked via Guild membership |
| Library inscriptions (markdown) | `jelly.asset` (media-type `text/markdown`) attached to avatar-typed DreamBalls whose `look` encodes inscription geometry |
| Guilds of palace-dwellers | `jelly.dreamball.guild` (v2) with per-slot policy |
| Timeline / rewind | **New**: `jelly.timeline` (DAG of signed actions; §5.3) |
| Aqueducts between rooms | **New**: `jelly.aqueduct` (typed edge with Vril flow properties — resistance, capacitance, conductance; §5.4) |
| Vril (life-force substance) | No new envelope — measured from timeline traversals, carried on aqueducts as flow properties (§5.4), rendered as ambient liveliness |
| Archiform (temple / forge / library / …) | **New**: `jelly.archiform` (archetypal form classification — different axis from the six v2 types; §5.9) |
| Elemental taxonomy | **New**: `jelly.element-tag` (open set of element-IDs on any DreamBall; §5.5) |
| Decentralized reputation | **New**: `jelly.trust-observation` (local, signed, non-aggregating; §5.6) |
| Keystone mythos | **New**: `jelly.mythos` chain — condensed poetic seed present from DreamSeed onward, evolving through signed true-namings; §5.8 |
| Resonant / half-remembered recall | Not on the wire — a **runtime kernel** (§6.3) that sits between the vector store and the LLM context window |

Containment is fractal and symmetric in v1/v2 already. The palace just
uses those edges deliberately: every `contains` is a *compositional
hypothesis* (VISION §5) and every nested layer is an onion step
(VISION §4.4.5). There are no "parent/primary child" distinctions.

---

## 3. Personas

**P0 — Wayfarer.** Walks their own palace. Wears nothing; the palace
surrounds them. Sees every slot permitted by their custody of the
palace keypair. Medium technical. Pain today: no spatialised view of
their own memory exists; notes and commits live in flat trees.

**P1 — Guest.** Receives a DragonBall-sealed palace or a single room
from a peer. Opens with their member key to a Guild that co-owns the
room. Sees only slots the Guild policy marks `public` or
`guild-only`. Low technical.

**P2 — Oracle host.** Custodian of the palace's Agent-type core. Not
necessarily the same identity as the wayfarer; for shared palaces the
oracle is guild-owned. Keeps the memory graph healthy, prunes, rebinds.
High technical.

**P3 — Guild scribe.** Member of a Guild that authors *shared rooms*
(a project's library, a study group's lab) that appear inside multiple
personal palaces simultaneously. Medium technical.

**P4 — Observer.** v2's P0 persona, reused: someone who sees a
palace-bearer pass by in a shared session. Sees only the outermost
public surface (facade, maybe a courtyard), never interior.

---

## 4. User Journeys

**J1 — Activate the fountain.**
A new wayfarer runs `jelly mint --type=palace --name "my-palace"`. The
CLI produces a Field DreamBall with one child Agent (the oracle,
default name "Murmuring Well") sitting at the palace's zero point. The
oracle's `personality-master-prompt` is seeded from a template the
wayfarer selects. On first `jelly palace open`, the browser renders
the palace via the `omnispherical` lens with a single lit room
(the courtyard containing the fountain). Every other room is a dark
silhouette, loadable on demand.

**J2 — Inscribe a document into the library.**
The wayfarer runs `jelly palace inscribe --room library docs/PROTOCOL.md`.
A new Avatar DreamBall is minted whose `look` carries the document as
both a `text/markdown` asset *and* a geometric inscription spec (text
wrapped onto a low-poly scroll or tablet mesh). The DreamBall is
`contains`-edged into the library room. Its position in the library's
local coordinate frame is stored in the parent room's layout assertion
(§5.2). The knowledge-graph triple `(document-fp, lives-in, library-fp)`
is added to the oracle's `knowledge-graph`.

**J3 — Recall via resonance.**
The wayfarer is having a conversation with the oracle in the throne
room. They say: "wasn't there something I wrote about hybrid
signatures?". The runtime kernel (§6.3) computes a coarse vector
match against every inscription in the palace, surfaces the top-K as
*shimmering ghosts* in the wayfarer's peripheral vision (ambient
resonance — not full recall). If the wayfarer turns toward a ghost,
the corresponding DreamBall is fully loaded into context and the
knowledge-graph triple `(recall-event, strengthened, document-fp)` is
added to the timeline.

**J4 — Receive a shared room.**
A guild-scribe peer publishes a shared library room as a Relic and
transmits the unlock capability via `jelly transmit`. The wayfarer's
palace now shows a new door that wasn't there before. Walking through
it enters the shared room; the local palace's containment edge points
to the remote room by fingerprint, and the remote room's policy
determines what the wayfarer sees inside.

**J5 — Rewind the palace.**
The wayfarer asks: "show me what this throne room looked like a month
ago." The timeline DAG (§5.3) is traversed backward from the
current head to the action whose signed timestamp predates the target;
the palace renderer reconstructs the layout assertion set from that
causal cut and renders that past state, read-only, with a visible
"you are in the past" tint. The present timeline is unchanged; the
past is inspected, never rewritten.

**J6 — Oracle speaks.**
The wayfarer sits at the fountain. The oracle uses its memory graph,
knowledge graph, emotional register, and interaction set (all v2
Agent slots) plus the present palace topology as context to offer a
reflection. The reflection itself becomes a new inscription in
whichever room the wayfarer chooses to place it.

---

## 5. Protocol surface

All additions are additive. Every new envelope type carries
`format-version: 2` and extends v2's existing taxonomy rather than
breaking it.

### 5.1 The `palace` subtype marker

The palace is a Field DreamBall. v2 already defines
`jelly.dreamball.field` (`docs/PROTOCOL.md §12.1.5`). We add a single
optional subject field to distinguish a palace-flavoured field:

```
"field-kind": "palace"     ; optional; one of "palace" | "room" | "ambient" | …
```

Absent the field, a Field DreamBall behaves as v2 specified. Present
with `"palace"`, the renderer routes the omnispherical lens through
the palace view (§6.1). Present with `"room"`, the field is treated
as a palace's contained child and renders only when the parent palace
is the current active Field.

### 5.2 `jelly.layout`

A Room/Palace Field carries a `layout` assertion that records where
its children sit in its local coordinate frame. The layout itself is
not a security claim — it's a *rendering hint*. Different viewers
may see different layouts (the palace shifts), which is exactly what
the Room-of-Requirement behaviour wants.

```
200(
  201({ "type": "jelly.layout", "format-version": 2 })
) [
  "placement":  { "child-fp": h'…32…', "position": [x, y, z], "facing": [qx, qy, qz, qw] },
  "placement":  { … },                                              ; repeatable
  [salted] 'note':  "autumn arrangement"
]
```

Coordinates use the dCBOR float exception already carved out for
`jelly.omnispherical-grid` (see PROTOCOL §12.2). Layouts are cheap to
re-sign; the palace renderer may keep several and pick contextually.

### 5.3 `jelly.timeline`

The timeline is a signed DAG of actions taken inside the palace.
It is **append-only** per keypair and **Merkle-rooted** so that any
cryptographic clock semantics (single agreed-upon head, replay
detection) can be derived without a central authority.

```
200(
  201({ "type": "jelly.timeline", "format-version": 2,
        "palace-fp":  h'…32…',
        "head-hash":  h'…32…'                  ; Blake3 of the latest action envelope
  })
) [
  "action":   <jelly.action envelope>,          ; repeatable, ordered by parent-hash chain
  [salted] "note": "v2.0 genesis timeline"
]
```

`jelly.action` subject: `{ type, format-version, action-kind: "inscribe"|"move"|"unlock"|…, parent-hashes: [h'…', h'…'] }`.
Multiple parent hashes allow merge semantics; the common case is a
single parent (linear history). Signatures cover the subject digest
plus the assertion digests; verifying the chain verifies every
ancestor.

The wire design is **CRDT-compatible** in the sense that divergent
branches (multiple actors writing concurrently to a shared room) can
be reconciled at read time by ordering-commutative merge of disjoint
action sets. Conflict resolution (who "wins" when two actors move the
same item) is out of scope for v1 of this spec — §8 open question.

### 5.4 `jelly.aqueduct`

An aqueduct is a typed, directed edge between two Rooms (or more
generally, between two DreamBalls in the palace) carrying **Vril**,
the palace's life-force substance (§1). Unlike the bare `contains`
edge, an aqueduct carries **flow semantics** expressed in explicit
electrical-style properties:

```
200(
  201({ "type": "jelly.aqueduct", "format-version": 2,
        "from": h'…32…', "to": h'…32…',
        "kind": "gaze"|"visit"|"transmit"|"inscribe"|"resource"|"ley-line"|…
  })
) [
  "capacity":     0.85,                            ; 0.0–1.0, soft prior — how much flow the channel could carry
  "strength":     0.12,                            ; 0.0–1.0, grows with traversal (the "fire-together, wire-together" counter)
  "resistance":   0.30,                            ; 0.0–1.0, how much the channel impedes flow (locked door = high R)
  "capacitance":  0.55,                            ; 0.0–1.0, how much Vril the endpoint pools before discharging
  "conductance":  0.70,                            ; 0.0–1.0, derived = (1 - resistance) × strength; cached here for renderers
  "phase":        "in"|"out"|"standing"|"resonant", ; qualitative directionality of current flow
  [salted] "last-traversed": 1(…)
]
```

The *why* of aqueducts: plain containment is symmetric and cold. The
palace experience needs **warm, flow-weighted, living edges** — the
"synapses that fire together wire together" metaphor from the opening
image, the ley-line metaphor from §1 on Vril — without that weight
leaking into the load-bearing `contains` graph. Aqueducts are the
warm substrate on top of cold containment.

The electrical vocabulary is **load-bearing**, not decorative. The
renderer uses `resistance` to decide how bright/narrow to draw a
channel; `capacitance` to decide how long to linger on a room before
"discharging" Vril to the next aqueduct; `phase` to decide whether
flow particles move toward the endpoint, away from it, or pulse in
place (standing wave) or resonate between endpoints (coupled
oscillation). The oracle uses the same numbers for reasoning: a
high-resistance, high-capacitance aqueduct from the throne room to
the basement is where a wayfarer *holds* something but doesn't yet
*release* it. This is a debuggable property, not a vibe.

Traversal updates aqueduct `strength` (and by extension the cached
`conductance`); the update is emitted as a `jelly.action` on the
timeline so it can be replayed and attributed. Vril itself is not a
declared quantity — it is *computed* by the runtime from the signed
action history (§6.2), and a full rebuild of Vril state from CAS is
always possible (FR84, Vision).

The `kind` enum gains `"ley-line"` as the distinguished value for an
aqueduct that carries *no* traversable walkway — a purely energetic
relationship between two rooms that the renderer draws as a ghostly
underlay beneath the physical palace. Ley-lines are how the palace
says: "these two rooms are related even though you can't walk
between them."

### 5.5 `jelly.element-tag`

Elemental taxonomy (5-element destruction/nourishment, 9-element
phase, yin/yang) is an *optional* classification every DreamBall in
the palace may carry. It's a tag, not a type:

```
200(
  201({ "type": "jelly.element-tag", "format-version": 2 })
) [
  "element":    "wood",                             ; repeatable; open enum
  "phase":      "nourishing",                       ; optional qualifier
  [salted] 'note': "seed / potential / green"
]
```

The element set is open (`wood / fire / earth / metal / water / seed
/ plant / tree / lightning / air / …`). Renderers may use the tags
for palette, motion, and ambient audio; the oracle may use them for
associative reasoning. The tag has **no privileged meaning at the
protocol level** — it is decoration that downstream systems can
elect to honour.

### 5.6 `jelly.trust-observation`

Reputation in the palace is **decentralised by construction**. It is
never a single scalar; it is a signed, local observation that each
actor emits about another, rendered and aggregated *in the observer's
own palace* with the observer's own priors.

```
200(
  201({ "type": "jelly.trust-observation", "format-version": 2,
        "observer": h'…32…',      ; who is making the claim
        "subject":  h'…32…'       ; about whom
  })
) [
  "axis":       { "name": "careful",      "value": 0.78, "range": [0.0, 1.0] },
  "axis":       { "name": "generous",     "value": 0.61, "range": [0.0, 1.0] },
  [salted] "observed-at": 1(…),
  [salted] "context":     "pair-programming sessions 2026-04",
  'signed':     Signature(ed25519),
  'signed':     Signature(ml-dsa-87)
]
```

Critical constraints:

- Trust observations are **never aggregated into a universal score**.
  Aggregation is a reader-side policy, typically weighted by
  social-graph distance (shared Guilds, direct interactions,
  transitive-recryption-depth).
- Observations **do not propagate automatically**. Transport is an
  explicit `jelly transmit` act scoped to a Guild, exactly like Tool
  transmission.
- Observations are **slot-level private** by default — the guild
  policy's `guild-only` bucket covers them unless the observer
  opts in to `public`.

This is the minimum wire shape that makes §1's "information can be
derived from the network without a central truth" realisable.

### 5.7 `jelly.inscription`

The library concept requires a specific Avatar subtype: a DreamBall
whose `look` geometry is *text arranged in space*. We don't need a
new top-level type — an Avatar DreamBall with a `jelly.inscription`
assertion is sufficient:

```
200(
  201({ "type": "jelly.inscription", "format-version": 2 })
) [
  "source":      <jelly.asset envelope>,            ; media-type: text/markdown (or text/plain, text/asciidoc…)
  "surface":     "scroll"|"tablet"|"book-spread"|"etched-wall"|"floating-glyph"|…,
  "placement":   "auto"|"curator",                  ; auto → renderer chooses; curator → manual layout in parent room
  [salted] 'note': "lives on the east wall"
]
```

The inscription is renderable by the `flat` lens (falls back to the
markdown body) and by a new `inscription` lens (§6.1) that draws the
text into 3D space. Because the `source` is a content-addressed
asset, the markdown file on disk and the inscription in the palace
share a Blake3 identity — edits to the file on disk propagate to the
palace via the oracle's file-watcher skill.

### 5.8 `jelly.mythos`

The keystone. A `jelly.mythos` assertion MAY appear on any DreamBall
and MUST appear on every DreamBall of subject type
`jelly.dreamball.field` where `field-kind == "palace"`. The mythos
is the **shortest coherent statement of what this DreamBall is** —
closer to a blurb, a totem, or an opening line of cosmology than to
a description. It is present from DreamSeed onward; a seed without a
mythos is legal v2 but is specifically *discouraged* by the palace
composition.

```
200(
  201({ "type": "jelly.mythos", "format-version": 2,
        "is-genesis": false,                        ; true only on the first-ever mythos of a palace
        "predecessor": h'…32…'                     ; Blake3 of the previous jelly.mythos envelope; absent iff is-genesis
  })
) [
  "form":         "blurb"|"invocation"|"image"|"utterance"|"glyph"|"true-name"|…,
  "body":         "There is a giant cow beside the chaos abyss.",   ; the mythos in its full poetic form
  "true-name":    "Audhumla",                                        ; optional — the condensed totem name, if one has surfaced
  "source":       <jelly.asset envelope>,                            ; optional longer form (essay, recorded reading)
  "discovered-in":<jelly.action-ref>,                                ; optional — the 'true-naming' action that surfaced this mythos
  [salted] "author":       h'…32…',
  [salted] "authored-at":  1(…),
  [salted] 'note':         "surfaced during a sit-by-the-fountain on 2026-04-19"
]
```

**The chain of mythoi.** A palace's mythos is a **linked chain**,
not a single value. The first `jelly.mythos` carries
`is-genesis: true` and no `predecessor`; every subsequent mythos
carries `is-genesis: false` and a `predecessor` hash pointing at its
immediate ancestor. The chain is verifiable end-to-end exactly the
way the timeline DAG is (§5.3): walking back from the current head
must terminate at the genesis. An attempt to publish a mythos whose
predecessor chain doesn't resolve is rejected at verify time.

The chain is the palace's *journey of self-understanding*. The
genesis is the seed; each new link is a truer name for what the
palace has become. Like a soul across lifetimes, the essence
(genesis) is conserved; the expression (current head) evolves.

**Rules the palace imposes:**

- The **genesis mythos is immutable**. Only the first `jelly.mythos`
  ever signed against a palace is load-bearing on its identity;
  attempting to alter it after publication is rejected.
- **Subsequent mythoi are append-only**. New true names are added to
  the chain, never deleted. History is readable; the past is never
  rewritten. A wayfarer inspecting an old mythos is walking their
  own past names, exactly the way `jelly palace rewind` (FR67)
  walks the timeline.
- **Only the palace's custodian(s) may extend the chain.** For a
  solo palace, the wayfarer's keypair. For a Guild-owned palace,
  any admin — though a Growth-tier policy might require quorum
  (§9). Non-custodians publishing a mythos assertion are ignored by
  the renderer.
- **Every new mythos is emitted alongside a `jelly.action` of kind
  `"true-naming"`** on the timeline. The action carries the
  discovery context: the conversation with the oracle, the
  aqueduct traversal that surfaced it, a short human reflection.
  The mythos envelope's `discovered-in` points back at this action.
  This is how the protocol preserves *why* a renaming happened —
  the naming itself is only half the story; the other half is the
  reflection that summoned it.
- Rooms and Inscriptions MAY carry their own mythos chain; a Room's
  mythos MUST be a coherent extension of its palace's current
  mythos, checked rhetorically, not mechanically. The palace
  renderer flags orphaned-feeling room mythoi for the oracle to
  reconcile.
- The mythos chain is **always public** regardless of Guild policy.
  Hiding it defeats its purpose — the mythos is what lets a stranger
  know what they are looking at before deciding whether to unlock
  the rest. (Individual `discovered-in` reflections MAY be
  `guild-only` if the wayfarer marks them so; the mythos text
  itself cannot be hidden.)
- The `form` field is an open enum so palaces can adopt different
  rhetorical registers (scientific brief, mythological scene, haiku,
  one-word totem) without the protocol dictating. `"true-name"` is
  the distinguished form for a mythos that has condensed to a single
  totem word/phrase — the asymptote the journey points toward.

**Why this belongs in the protocol and not just in prose.** Every
downstream consumer — the renderer's thumbnail lens, the oracle's
self-description, the MCP server's `describe_api` response, a shared
palace's facade — benefits from one canonical place to find the
generative seed. Scattering the mythos across `name`, `note`, and
the oracle's `personality-master-prompt` loses the property that
makes it load-bearing: **it is the one thing you can point at and
say "this is what this DreamBall is."**

**Keystone arithmetic.** A palace's mythos is singular; a room may
have its own; an inscription may quote its own. This recurses as far
as the author cares to take it. The palace renderer treats the
nearest enclosing mythos as the rendering context's mythos — the one
used to tint ambient audio, select default palettes, and seed the
resonance kernel's bias toward related vocabulary.

### 5.9 `jelly.archiform`

An **archiform** is the archetypal form a space (or being) takes —
a class in the OOP sense and a Platonic form in the mythic sense.
Archiform is a *classification axis orthogonal to the six v2 types*:
a Room (type = `jelly.dreamball.field`, `field-kind: "room"`) may
be archiform `library`, `forge`, `throne-room`, `lab`, `cell`,
`portal`, `garden`, `crypt`, `courtyard`, …. An item (type =
`jelly.dreamball.avatar`) may be archiform `scroll`, `lantern`,
`vessel`, `compass`, `seed`. An oracle (type =
`jelly.dreamball.agent`) may be archiform `muse`, `judge`,
`midwife`, `trickster`.

```
200(
  201({ "type": "jelly.archiform", "format-version": 2 })
) [
  "form":        "library",                        ; the archiform id (open enum)
  "tradition":   "hermetic"|"shinto"|"vedic"|"computational"|"none"|…,  ; optional lineage
  "parent-form": "atrium",                         ; optional — an archiform this one specialises
  [salted] "note": "catalogues rather than restricts"
]
```

The archiform is a **tag**, not a schema. It does not constrain what
assertions a DreamBall may carry; it hints to renderers, oracles,
and collaborators *what this thing wants to be*. Honouring the hint
is a soft contract between author and runtime.

**Why this belongs at the protocol level.** Three concrete wins:

1. **Renderer defaults without bespoke config.** A room tagged
   `library` can pick sensible palette, audio, and layout defaults
   without the author specifying each. Overridable per room.
2. **Oracle reasoning shortcuts.** The oracle asking "where would
   this inscription want to live?" can match against archiforms
   first (`forge` for a procedure, `library` for a reference,
   `garden` for a journal) before falling back to vector similarity.
3. **Cross-palace portability.** When a shared room crosses palaces
   (J4), the archiform travels with it. Two wayfarers' libraries
   look *kin* even if their palette choices differ, because both
   honour the `library` archiform's defaults.

**Tree of archiforms.** The `parent-form` field makes archiforms a
directed acyclic classification graph. A `temple` may parent
`chapel`, `sanctum`, `ziggurat`; a `library` may parent
`scriptorium`, `archive`, `reading-room`. The palace renderer walks
parents to resolve unspecified defaults. The protocol does not
prescribe the tree — it is community-defined and extensible.

A small **seed set of archiforms** ships with the palace runtime
(library, forge, throne-room, garden, courtyard, lab, crypt,
portal, atrium, cell). Authors may introduce new archiforms at any
time; the runtime's archiform registry is a `jelly.asset` of
media-type `application/vnd.palace.archiform-registry+json`
attached to the palace itself and discoverable by any guest.

### 5.10 Type additions summary

The palace composition introduces **no new top-level DreamBall
type**. It adds **nine auxiliary envelope types** (`jelly.layout`,
`jelly.timeline`, `jelly.action`, `jelly.aqueduct`,
`jelly.element-tag`, `jelly.trust-observation`, `jelly.inscription`,
`jelly.mythos`, `jelly.archiform`) and one **optional subject field**
(`field-kind` on `jelly.dreamball.field`). Two of the new envelopes
form *chains* linked by hash-predecessors —
`jelly.timeline`/`jelly.action` (the record of doings) and
`jelly.mythos` (the record of becomings). Vril (the life-force
substance; §1) is not itself an envelope — it is *measured* from
timeline traversals and carried as flow properties on
`jelly.aqueduct` (§5.4), staying faithful to the protocol's rule
that every load-bearing claim is signed. All additions are additive;
v2 parsers without palace support see them as unknown assertions and
skip.

---

## 6. Runtime & rendering

### 6.1 Lenses

The renderer gains three palace-specific lenses (added to v2's eight):

| Lens | What it shows | Primary for |
|---|---|---|
| `palace` | omnispherical view of a palace Field, navigable by walking between rooms | `jelly.dreamball.field` where `field-kind == "palace"` |
| `room` | interior view of a single Room Field with its layout applied | `jelly.dreamball.field` where `field-kind == "room"` |
| `inscription` | text-in-3D rendering of an Avatar bearing a `jelly.inscription` assertion | Any Avatar with an inscription |

Every other v2 lens (thumbnail, avatar, splat, knowledge-graph,
emotional-state, omnispherical, flat, phone) remains usable inside
the palace for the DreamBalls that suit them. The **knowledge-graph
lens** in particular is the primary view of the oracle's mind; the
**emotional-state lens** is the view of the fountain's water (its
colour and motion encode the oracle's emotional register).

### 6.2 The backing stores

| Store | Purpose | Why |
|---|---|---|
| **Kuzu (open-source fork)** | Primary graph store — containment, aqueducts, timeline edges, knowledge-graph triples | Native property graph with Cypher-ish query; local-first; embeddable; the open-source fork is kept current in-tree |
| **Vector store** (candidate: `lancedb` or `usearch`, TBD) | Semantic prefetch and ambient resonance (§6.3) | Required for the "half-remembered" behaviour; quantised low-precision vectors acceptable |
| **DreamBall CAS** | Canonical storage of every `.jelly` envelope and attachment | Content-addressed by Blake3; Kuzu nodes reference this by fingerprint; swappable with recrypt's blob store |

The three stores are coupled only by fingerprint. Kuzu never holds
CBOR; the CAS never holds queryable structure. Delete the vector
store and the palace still works, it just loses resonance.

### 6.3 The resonance kernel

The most novel component, and the one most likely to surprise.

When the wayfarer is in conversation with the oracle, the resonance
kernel runs continuously. Each turn:

1. The current prompt is embedded.
2. A K-NN query against the vector store returns candidate
   inscriptions / memory-nodes / interaction-set fragments.
3. Matches above a coarse threshold are *not* auto-loaded into
   context. Instead, each match contributes a **small bias vector**
   over the oracle's next-token distribution — the effect is that
   the oracle "feels" the related memory without having read it.
4. Matches above a sharp threshold — or matches the oracle's own
   attention selects for — trigger a **recall event**: the
   inscription is loaded into context, a `(recall-event, loaded,
   memory-fp)` triple is written to the knowledge graph, and the
   corresponding aqueduct's strength increases.

The kernel is an LLM-side hook, not a protocol concern. The wire
format says nothing about it. It is called out here because it is the
mechanism that makes §4 Journey 3 possible, and because its
*existence* shapes which protocol affordances we need (content-
addressed vectors, per-memory recall-count, traversable graph).

The kernel is MVP-tier as a **scaffold** (embed + K-NN, no biasing);
the biasing pass is Growth; the attention-head phase-lock described
in §1 is Vision.

### 6.4 Shared-palace coherence

Journey 4 (shared rooms) requires that a room can appear in two
wayfarers' palaces *at once*, with divergent local layouts but a
shared semantic identity. The protocol handles this directly — a
Room DreamBall is addressed by its fingerprint; two palaces both
carry a `contains` edge to the same fingerprint; each palace's
`jelly.layout` assertion places the room differently in its own
coordinate frame.

The *holographic* / *interference-pattern* quality described in §1
emerges from a derived analysis: when two palaces share N rooms, the
overlap of their aqueduct graphs is itself a signal. The first
iteration exposes this via a read-only `/palace/:fp/resonance/:other-fp`
endpoint that computes edge overlap on demand; deeper treatment is
Vision tier.

---

## 7. Functional Requirements

Tier conventions match the v2 PRD (MVP / Growth / Vision). FR numbers
continue the v2 range for readability.

### Palace composition (FR60–FR68)

FR60. [MVP] The system shall accept `--type=palace` on `jelly mint`,
minting a Field DreamBall with `field-kind: "palace"`, a default
Agent child (the oracle), an empty `jelly.timeline` rooted on the
mint action, **and a required `jelly.mythos` assertion** captured
interactively (or provided via `--mythos <string>`). A palace
cannot be minted without a mythos; the CLI refuses with a helpful
prompt.

FR60a. [MVP] The system shall treat the palace mythos as an
**append-only chain**. The first `jelly.mythos` published against a
palace carries `is-genesis: true` and is immutable thereafter. Every
subsequent mythos carries `predecessor` = Blake3 of the prior
mythos and extends the chain. Verification walks the chain to
genesis; a broken chain is a hard failure.

FR60b. [MVP] The system shall provide `jelly palace rename-mythos
<palace> --body <text> [--true-name <word>] [--form <form>]` that
appends a new mythos to the chain, emits a paired `jelly.action` of
kind `"true-naming"` on the timeline capturing the discovery
context, and re-signs the palace.

FR60c. [MVP] The system shall accept an optional `--mythos <string>`
or `--mythos-file <path>` on `jelly palace add-room` and
`jelly palace inscribe`, attaching a (genesis) `jelly.mythos` to the
minted envelope. Absent, children inherit the nearest enclosing
mythos at render time — the assertion itself remains unset. Rooms
and inscriptions MAY extend their own mythos chains via
`rename-mythos` scoped to their fingerprint.

FR60d. [MVP] The oracle shall treat the **current head** of the
mythos chain as always-in-context — it is prepended to every
conversation turn's system prompt regardless of other recall. The
oracle's knowledge-graph shall mirror the chain via triples
`(palace-fp, mythos-head, current-mythos-fp)` and
`(mythos-fp, predecessor, prior-mythos-fp)` so the chain is
traversable from within the oracle's own reasoning.

FR60e. [Growth] The system shall provide `jelly palace reflect
<palace>` which opens an introspective dialogue with the oracle.
The oracle draws on the timeline since the last true-naming, the
aqueducts whose strength has grown most, the inscriptions most
recently placed, and the emotional register's trajectory. If the
dialogue surfaces a candidate new mythos, the oracle proposes it;
accepting calls `rename-mythos` with the conversation transcript
attached as the true-naming action's discovery-context.

FR60f. [Growth] The renderer shall visualise the mythos chain as a
**ring of lanterns** near the fountain — each past mythos a dimly
lit lantern, the current head glowing brightest, the genesis with a
permanent small flame at its base. Reading a lantern opens the
full `jelly.mythos` envelope and its paired true-naming action.

FR60g. [Vision] The system shall support **mythos divergence
resolution**: if two custodians of a shared palace publish
conflicting successor mythoi against the same predecessor, the
renderer surfaces both as a branch in the lantern ring and the
Guild's conflict-resolution policy (default: quorum of admins) picks
the canonical successor — the losing branch is preserved as a
`jelly.action` of kind `"shadow-naming"` so the thread is not lost.

FR61. [MVP] The system shall provide `jelly palace add-room <palace>
--name <room-name>` that mints a Field DreamBall with
`field-kind: "room"` and appends it to the palace via `contains`.

FR62. [MVP] The system shall provide `jelly palace inscribe <palace>
--room <room-fp> <file>` that mints an Avatar DreamBall with a
`jelly.inscription` assertion pointing at the file as an asset and
places it in the named room.

FR63. [MVP] The system shall provide `jelly palace open <palace>` that
launches the showcase app focused on the given palace.

FR64. [MVP] The system shall emit every state-changing palace action
(mint-room, inscribe, move, unlock) as a signed `jelly.action`
appended to the palace's `jelly.timeline`.

FR65. [MVP] The system shall enforce the v2 containment-cycle rule on
palace topology: rooms contain items, palaces contain rooms, but no
cycles.

FR66. [Growth] The system shall support `jelly palace share --room
<room-fp> --guild <guild-fp>` that seals a room as a Relic and
transmits unlock capability to guild members, enabling J4.

FR67. [Growth] The system shall support `jelly palace rewind <palace>
--to <timestamp>` read-only traversal of the timeline DAG, J5.

FR68. [Vision] The system shall support multi-writer concurrent edits
on a shared room with CRDT-style deterministic merge of
non-conflicting `jelly.action` DAGs.

### Oracle behaviour (FR69–FR73)

FR69. [MVP] The system shall mint the oracle as an Agent DreamBall
with `personality-master-prompt` seeded from a template, empty
`memory`, empty `knowledge-graph`, and a default
`emotional-register` with axes `curiosity`, `warmth`, `patience`.

FR70. [MVP] The oracle shall have read access to every slot in the
palace regardless of Guild policy (it is the palace's custodian-of-
record).

FR71. [MVP] Inscriptions placed in the palace shall be added as
triples in the oracle's knowledge-graph (`(doc-fp, lives-in,
room-fp)`).

FR72. [Growth] The oracle shall have a file-watcher skill that
updates an inscription's `jelly.asset` hash when the underlying file
changes on disk, and bumps the Avatar's revision with a re-sign.

FR73. [Vision] The oracle shall use the resonance kernel's biasing
pass (§6.3) to soften context-loading decisions; recall becomes
probabilistic rather than threshold-hard.

### Rendering (FR74–FR79)

FR74. [MVP] The renderer shall add the `palace` lens: omnispherical
navigable view of rooms.

FR75. [MVP] The renderer shall add the `room` lens: interior layout
honouring the room's `jelly.layout` assertion.

FR76. [MVP] The renderer shall add the `inscription` lens: text
arranged in 3D per the inscription's `surface` field.

FR77. [MVP] The renderer shall route aqueduct traversal events to the
runtime, which emits a `jelly.action` of kind `move` and updates the
aqueduct's `strength`.

FR78. [Growth] The renderer shall display "shimmering ghosts" in the
wayfarer's peripheral vision for vector-similar memories above the
coarse threshold (§6.3 step 3).

FR79. [Vision] The renderer shall surface shared-palace resonance
(§6.4) as a visualisable interference pattern between two palaces.

### Backing stores (FR80–FR84)

FR80. [MVP] The system shall embed Kuzu (open-source fork) as the
palace's primary graph store. Containment edges, aqueducts, timeline
edges, and knowledge-graph triples are all mirrored into Kuzu on
every state change. CAS remains the source of truth; Kuzu is the
queryable index.

FR81. [MVP] The system shall embed a vector store (candidate lancedb
or usearch — decision in §9) for semantic embeddings over
inscriptions, memory-nodes, and interaction-set content.

FR82. [MVP] The system shall recompute vectors on every inscription
revision bump, keyed by the content hash so unchanged content skips
re-embedding.

FR83. [Growth] The system shall maintain a quantised low-precision
vector alongside the full vector; quantised vectors drive the
ambient-resonance biasing pass without full recall.

FR84. [Vision] The system shall support rebuild-from-CAS: given only
the set of `.jelly` files, Kuzu + the vector store can be
reconstructed from scratch with no loss of queryable state.

### Reputation & trust (FR85–FR87)

FR85. [Growth] The system shall accept `jelly observe <subject-fp>
--axis <name>=<value>` which emits a signed
`jelly.trust-observation` assertion on the observer's palace.

FR86. [Growth] The system shall expose a reader-side aggregation
query that computes *observer-local* trust scores weighted by social
graph distance (shared Guild membership + transmission depth). No
global aggregation anywhere.

FR87. [Vision] The system shall allow trust observations to be
transmitted between palaces via Guild-scoped `jelly transmit`, with
the receiver's aggregation query incorporating them according to the
receiver's own priors.

### CLI (FR88–FR92)

FR88. [MVP] The system shall ship all palace commands under a single
`jelly palace` verb group: `mint`, `add-room`, `inscribe`, `open`,
`layout`, `share`, `rewind`, `observe`.

FR89. [MVP] The system shall extend `jelly show` with a
`--as-palace` mode that pretty-prints a palace's topology (room tree,
item counts, timeline head, oracle fingerprint).

FR90. [MVP] The system shall extend `jelly verify` to validate
palace-specific invariants: at least one room exists, the oracle is
the only Agent directly contained, every timeline action's parent
hash resolves to an ancestor action.

FR91. [Growth] The system shall provide `jelly palace trace
<palace> --from <action-fp>` that walks the timeline backward and
prints a human-readable activity log.

FR92. [Growth] The system shall provide `jelly palace gc <palace>`
that garbage-collects orphaned inscriptions (not referenced from any
room) to an `archive/` subdirectory — non-destructive quarantine, not
deletion.

### Vril & archiforms (FR93–FR98)

FR93. [MVP] The system shall accept `--archiform <form>` on
`jelly palace add-room`, `jelly palace inscribe`, and `jelly mint
--type=agent` (for the oracle). The archiform is attached as a
`jelly.archiform` assertion on the minted envelope. Absent, the
renderer applies the default archiform per type (`room` → `chamber`,
`inscription` → `scroll`, `agent` → `muse`).

FR94. [MVP] The system shall compute aqueduct electrical properties
(`strength`, `conductance`, `phase`) from the timeline action log on
every palace load, persist them into `jelly.aqueduct` assertions,
and re-sign the aqueduct envelope. `resistance` and `capacitance`
are author-declared priors that the runtime does not overwrite.

FR95. [MVP] The system shall ship a seed archiform registry
(`library`, `forge`, `throne-room`, `garden`, `courtyard`, `lab`,
`crypt`, `portal`, `atrium`, `cell`, `scroll`, `lantern`, `vessel`,
`compass`, `seed`, `muse`, `judge`, `midwife`, `trickster`) as a
`jelly.asset` attached to every freshly minted palace, discoverable
via `jelly palace show --archiforms`.

FR96. [Growth] The renderer shall draw Vril flow on every aqueduct
— animated particles whose speed reflects `conductance`, whose
density reflects `capacity × strength`, and whose direction reflects
`phase`. Ley-line aqueducts (kind = `ley-line`) render as a ghostly
underlay beneath the walkable geometry.

FR97. [Growth] The oracle shall use archiform tags when suggesting
inscription placement — a newly inscribed reference document defaults
to the nearest `library`; a procedure to the nearest `forge`; a
journal to the nearest `garden`. Suggestions are shown, not
executed; the wayfarer confirms.

FR98. [Vision] The runtime shall detect Vril bottlenecks — aqueducts
with high traversal demand but low conductance — and surface them to
the oracle as a diagnostic. The oracle may propose a new aqueduct
(a shortcut), raising the palace's Vril throughput without
rearranging existing rooms.

---

## 8. Non-Functional Requirements

NFR10. [latency] Opening a palace of ≤500 rooms with ≤50 inscriptions
each shall render the first lit room in <2 s on a mid-range laptop.

NFR11. [offline] Every palace operation except Guild transmission and
ML-DSA signing shall work fully offline. Kuzu + vector store +
`jelly.wasm` are all local.

NFR12. [authorship] Every `jelly.action` and every
`jelly.trust-observation` shall carry dual signatures (Ed25519 + ML-
DSA-87) following the v2 signature rule. No unsigned timeline writes.

NFR13. [privacy] No palace state shall be emitted over the network
without an explicit user action. The resonance kernel runs locally;
embeddings are computed locally; no server-side aggregation.

NFR14. [mythos fidelity] The palace renderer's default aesthetic
shall honour the opening image — warm, architectural, with
**aqueducts visibly carrying Vril as flowing light**. The palace
must *feel alive*: cilia-like motion on aqueducts, pulse on rooms
with high capacitance, ambient glow whose colour follows the
current mythos's emotional register. Stock Threlte materials are
insufficient; plan for a small custom shader pack. Budget: v2's
`src/lib/` shader pack extended by ≤4 new materials (aqueduct-flow,
room-pulse, mythos-lantern, ley-line-ghost).

NFR15. [mocked-crypto hygiene] All new crypto sites carry
`TODO-CRYPTO: replace before prod`; all new CAS sites carry
`TODO-CAS: confirm indexer path`; consistent with v2's marker
discipline.

---

## 9. Open Questions

- **Vector store choice.** `lancedb` (Rust, embedded, Arrow-native,
  good quantisation story) vs `usearch` (header-only C++, smaller
  footprint, WASM-buildable). Decision deferred to Phase 0 spike;
  evaluate on: embeddability from Bun, size on disk for 10k vectors,
  WASM footprint for eventual browser support.
- **Kuzu fork tracking.** Which fork do we pin — upstream open-
  source, or a community fork with longer support promises? Needs a
  short-lived spike; default to upstream until a specific pain
  appears.
- **CRDT merge strategy for shared rooms.** Layout conflicts ("two
  scribes moved the same item") want either LWW-per-item or
  last-signer-wins-with-notice. Default: LWW-per-item with the loser
  surfaced as a rejected-action ghost. Validate in FR68 spike.
- **Resonance kernel biasing mechanism.** Attention-head bias vs
  prompt-level preamble injection vs tool-call shaped "ambient
  memory" tool. Research question; treat the protocol-agnostic shape
  (§6.3) as the contract and iterate on the implementation.
- **Oracle custody.** For shared palaces, who signs oracle state
  updates? Default: the Guild's keyspace admin. Alternative:
  threshold signing. Defer to v1.1 of the palace.
- **Palette / tempo / elemental binding.** Does every element tag get
  a palette + ambient track? Or is binding a renderer concern? Leans
  renderer — keep tags open, keep bindings themeable.
- **Relation to VISION §4.4.5 dream field.** A palace is a Field is
  a dream-field host — does the palace *become* the dream field for
  contained avatars, or does it *embed* in a larger dream field? The
  second answer preserves the onion nesting all the way up. Lock in
  Phase 0.
- **Vril conservation.** Is Vril conserved within a palace
  (endogenous — generated by the fountain, consumed by stasis) or
  supplied exogenously by the wayfarer's attention (a palace unvisited
  for weeks drains)? Both metaphors have appeal. Default MVP: *both*
  — a small constant fountain input plus attention-proportional
  inflow; formal conservation is Vision.
- **Archiform tree governance.** Community-defined archiforms could
  fragment quickly (my `library` isn't your `library`). Do we need a
  shared root registry, a federation model, or deliberate
  fragmentation as a feature? Defer; MVP ships the seed set and
  accepts drift for solo palaces.
- **Computer-hardware metaphor literalism.** Should the runtime
  expose Vril values in literal electrical units (ohms, farads) in
  its debug views, or is the metaphor a *framing* that stays
  proportional-only (0–1 floats)? MVP: proportional; debug overlay
  in ohms/farads is a nice-to-have that the renderer pack can add
  without protocol impact.

---

## 10. Scope Boundaries

### In scope (MVP)

- The palace type marker and one default oracle at the zero point.
- Rooms, inscriptions, layouts, timeline, aqueducts.
- Element tags (tag-only; no enforced palette).
- Kuzu + vector store integration (MVP features only — no quantised
  resonance biasing).
- Three new lenses; every v2 lens remains available.
- CLI `jelly palace` verb group covering the MVP FR set.
- Updates to `docs/PROTOCOL.md §13` (new section) and `docs/VISION.md
  §15` (new section) describing the wire additions and the mythos.

### Out of scope

- Federation / cross-palace holographic interference at the visual
  layer (FR79; Vision).
- Real chained-recryption transmission of trust observations across
  Guild boundaries (FR87; depends on recrypt FR52, already Vision in
  v2 PRD).
- Palace marketplace / discovery.
- Mobile-native palace renderer (web-only; responsive layouts).
- Resonance kernel biasing implementation (FR73 / FR78; Growth scaffold
  lands, full biasing is Vision).
- Palette/audio bindings for element tags (renderer theme layer).

### MVP / Growth / Vision split

**MVP:** FR60 (+60a,60b,60c,60d), FR61–65, FR69–72, FR74–77,
FR80–82, FR88–90, FR93–95, NFR10–15. Enough to walk into a palace,
inscribe documents, converse with an oracle whose every turn sits
under the current mythos head, rename the mythos deliberately by
command, tag rooms and items with archiforms, see aqueducts carry
computed Vril-flow properties, and have the whole state persist +
replay.

**Growth:** FR60e (`jelly palace reflect` — the oracle-guided
discovery ritual), FR60f (mythos lantern-ring visualisation),
FR66–67, FR73 (scaffold), FR78, FR83, FR85–86, FR91–92, FR96–97.
Shared rooms, rewind, ambient resonance, local trust, inspection
tooling, Vril visibly flowing through the palace as animated light,
archiform-aware oracle suggestions, and the living-myth UX that
turns renaming from a command into a ceremony.

**Vision:** FR60g (mythos divergence resolution across custodians),
FR68, FR73 (full biasing), FR79, FR84, FR87, FR98 (Vril bottleneck
detection). CRDT merge, phase-locked attention biasing, cross-palace
resonance visuals, trust transmission, CAS-only rebuild,
quorum-resolved mythos branches, and a palace that can diagnose its
own circulation.

---

## 11. Constraints

- **Zig 0.16** for every new envelope encoder/decoder; same rules as
  v2.
- **Bun + TypeScript** for the renderer, showcase, and the resonance
  kernel host.
- **No new wire format**. Palace rides on v2. Every new envelope is
  additive and fits the dCBOR conventions already documented in
  `docs/PROTOCOL.md §2`.
- **Kuzu and vector store are embedded, not service-oriented.** The
  palace is local-first. A `jelly-server` is an optional accelerator
  exactly as in v2.
- **Mythos is load-bearing.** The renderer is allowed (and required)
  to prefer aesthetic coherence over geometric minimalism. See
  NFR14 + VISION §15.

---

## 12. Existing system context

- `docs/VISION.md §4, §10, §12` — omnispherical grid, six-type
  taxonomy, lenses. All palace work rides on these.
- `docs/PROTOCOL.md §12` — v2 typed envelopes. Palace adds seven
  auxiliary envelope types in a new §13.
- `docs/products/dreamball-v2/prd.md` — the v2 PRD this composition
  depends on. No v2 requirement is altered by this spec.
- `src/lib/lenses/` — v2 lens pack; palace lenses land alongside.
- `src/lib/backend/` — JellyBackend interface. Palace state is
  an additional backend concern (Kuzu + vectors) behind the same
  interface.
- `docs/known-gaps.md §3, §6` — trust transmission and keyspace
  proxy-recryption are already tracked; palace surfaces them as a
  concrete consumer but does not resolve them.

---

## 13. Changelog

- 2026-04-19 — Initial PRD captured from a vision-dense conversation.
  Prose of §1–§4 honours the conversation's imagery; §5 onward is
  the prescriptive map onto the v2 protocol. Status: draft (not yet
  run through the critic loop; some open questions in §9 will
  resolve only in Phase 0 spike).
