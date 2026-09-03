# Memory Palace — Vision

> A reference implementation of the DreamBall open type system (see the
> substrate vision at [`../../VISION.md`](../../VISION.md)). The palace is a
> type like any other — proof that a rich, multi-type, rendered application
> can be expressed *as* DreamBall types. It is near-universal in practice:
> agentic intelligence demands memory, and memory wants spatial form.
> (Today it is woven monolithically into the codebase; that is a debt, not
> a design — the target is that its Room / Aqueduct / Inscription / Mythos
> are authored through exactly the mechanism any third party uses.)

> Added 2026-04-20, alongside
> [`prd.md`](prd.md)
> and a new wire-format section at
> [`protocol.md`](protocol.md) (the palace's auxiliary envelopes).
> This section is the *why* of the palace — the descriptive register
> that explains what the composition means. The prescriptive register
> (wire format) and actionable register (FRs, scope, tiers) live in
> the two siblings above.

A **composition** is a DreamBall whose shape arises from how it *uses*
the v2 primitives together, not from any single primitive alone. The
Memory Palace is the first — six typed balls, eight lenses, guild
policy, onion-layer fractal containment, and the `dreamball.wasm` crypto
core happen to add up to a thing a person can walk around *inside*.
That outcome is not mechanical; it has to be felt for the composition
to be legible. This section records what that feel is, so future
composers (and future renderers) have a fixed reference for the
aesthetic commitments the palace makes.

## 1. The palace is a topology

A palace has cornerstones, roofs, attics, basements, throne rooms,
libraries, chests, courtyards, locked doors, and aqueducts that run
between them. Memory lives in those rooms — objects on tables,
inscriptions on walls, keys in pockets, fountains in courtyards —
and is *found again* by walking there. The palace is a first-class
spatial metaphor, not decoration around a conventional database. The
topology *is* the meaning-carrying structure.

Containment provides the cold backbone (inherited from §3's fractal
symmetry); the palace composition adds **warm connections** (§15.5) on top.
A room inside a palace uses the same `contains` connection that any
DreamBall inside any DreamBall uses. The palace never needs a
special-purpose nesting primitive.

## 2. The keystone is the mythos

Above every arch sits a keystone. A palace's keystone is its
**mythos** — the shortest coherent statement of what this DreamBall
is, sitting below the name, above every room. A DreamSeed without a
mythos is a stone without a keystone: it can be built around, but
it will not teach you how. The **blurb of a book**, the **Polaris of
a ship's course**, the **giant cow next to the chaos abyss** at the
start of Norse cosmology — all three are mythoi. One per palace,
mandatory at genesis, always public.

**The mythos is a living chain, not a frozen value.** The genesis
mythos — the first one ever signed — is immutable; it is the
palace's soul, the stone that will outlive every rearrangement. But
its *name* evolves. A wayfarer sits with the oracle, walks aqueducts
whose strength has grown with use, and a new **true name** surfaces
— a more accurate poem for what this palace has become. The mythos
is not rewritten; it is *renamed*. Each new name remembers the last,
the way a soul remembers its previous lives. The genesis is eternal;
the current mythos is the soul in this life; the chain between them
is the record of its journey. What the palace *is* becomes *more
clearly what it has always been* as it is lived in.

The chain is load-bearing at the protocol level — hash-linked,
append-only, signed — because the alternative (scattering the
generative seed across `name`, `note`, and `personality-master-prompt`)
loses the one property that makes it a keystone: it is the one
thing you can point at and say "this is what this DreamBall is."

**The palace is not monotheistic about its mythos.** A palace has
*one* canonical chain — the custodian-signed record of true-namings
discovered with the oracle — and an unbounded number of **poetic
mythoi**, each authored by a visitor whose heart has met the place.
Both are first-class in the protocol. Canonical and poetic chains
share the same envelope shape; what distinguishes them is who signed
(custodian vs. visitor) and whether an `about` pointer is present
(present = poetic standalone; absent = canonical embedded). The
canonical chain is the palace's self-knowing; the poetic chains are
its *being known*. Synthesis — where the oracle helps a custodian
incorporate what visitors have seen — is how the palace's canonical
understanding absorbs others' experiences of it. Divergence beyond
synthesis forks: a visitor whose poetic chain has drifted too far
can mint a new palace `derived-from` the original, no new protocol
primitive required. See PROTOCOL §13.8 for the wire shape; PRD §5.8
for the rules the palace imposes on top.

## 3. Vril — the life-force that flows

The palace is not inert furniture. It is alive. The substance that
makes it alive is **Vril** — the name we adopt for the life-force
that flows through every aqueduct and pools in every capacitive
room. Vril is a unifying abstraction behind four otherwise-separate
metaphors the palace kept reaching for before it had a shared word:

- **The jelly itself.** The DreamBall family is bioplasmatic in its
  naming (dreamball, gel, membrane, wobble). Vril is the substance the
  name has been pointing at all along.
- **Electron flow through a computer.** Capacitance, resistance,
  conductance, the difference between a passive trace and a live
  bus. The palace inherits this vocabulary literally: aqueducts gain
  resistance and capacitance fields; the oracle is a gate; locked
  doors are high-resistance junctions.
- **Ley-lines across land.** A temple becomes a temple because of
  where it sits on the earth's subtle channels, not because of its
  walls. A palace's aqueduct topology is the wayfarer's personal
  ley-line map; rooms gain power from *where they sit on it*, not
  from their contents alone.
- **Cilia, organs, nerves.** The palace is alive the way a body is
  alive. The renderer must draw aqueducts as *flowing*, *pulsing*,
  *living*, not as inert geometry. This is encoded as a non-
  functional requirement (PRD NFR14) because stock mesh rendering
  makes it too easy to forget.

Vril is not a new envelope. It is the *substance* every aqueduct
carries, *measured* (not declared) from the signed action history,
and *rendered* as the palace's ambient liveliness. Staying
measurement-only keeps Vril faithful to the protocol's rule that
every load-bearing claim is signed: the cause (traversals,
inscriptions, renamings) is signed; Vril is the effect.

## 4. Archiform — the form a space takes

Orthogonal to the six v2 DreamBall types (avatar / agent / tool /
relic / field / guild) is a different question: **what archetypal
form does this thing take?** A room typed `field` may be a `library`,
a `forge`, a `throne-room`, a `garden`, a `crypt`, a `portal`. An
item typed `avatar` may be a `scroll`, a `lantern`, a `vessel`, a
`compass`, a `seed`. An agent may be a `muse`, a `judge`, a
`midwife`, a `trickster`.

**Archiform is a classification axis, not a schema.** It doesn't
constrain the slot surface; it hints to renderers, oracles, and
collaborators *what this thing wants to be*. Three concrete reasons
the hint deserves protocol-level status:

1. **Renderer defaults without bespoke config.** A room tagged
   `library` picks sensible palette, audio, and layout defaults
   without the author specifying each.
2. **Oracle reasoning shortcuts.** The oracle asking "where would
   this inscription want to live?" matches against archiforms first
   (`forge` for a procedure, `library` for a reference, `garden`
   for a journal) before falling back to vector similarity.
3. **Cross-palace portability.** A shared room that crosses palaces
   still *looks kin* — two wayfarers' libraries honour the same
   `library` defaults even if their palette choices differ.

Archiforms form a DAG via `parent-form`; a `temple` may parent
`chapel`, `sanctum`, `ziggurat`. The protocol ships a small seed
set and leaves the tree community-extensible via a registry asset
on each palace. Archiform is intentionally parallel to (and
independent of) `ball.element-tag` — two tag dimensions for two
different questions. See PROTOCOL §13.9.

## 5. Aqueducts are warm; containment is cold

`contains` is symmetric, cold, and load-bearing on the graph's
structural meaning: cycles are forbidden, transitivity applies, the
renderer walks it to decide what's nested where. Containment is
what makes the palace a palace at all.

**Aqueducts are the warm substrate on top.** An aqueduct is a
directed, typed, weighted connection between two DreamBalls, carrying
Vril in one of a handful of `kind`s: `gaze` (the wayfarer's
attention flowed here), `visit` (they physically went), `transmit`
(a skill or observation flowed), `inscribe` (writing flowed),
`resource` (material, time, or care flowed), `ley-line` (an
energetic relationship with no walkable correspondence).

The electrical vocabulary (resistance, capacitance, conductance,
phase) is not decorative. It buys the palace two things cold connections
can't: **diagnostics** (a high-capacitance, low-conductance room is
where a wayfarer *holds* something but doesn't yet *release* it —
a debuggable property of the topology, not a vibe) and **renderer
animation** (particle speed, glow density, and pulse phase all
derive from these numbers). The oracle reasons over the same
numbers when suggesting shortcuts (see PRD FR98, Vision tier).

## 6. The oracle as paraconscious persona

Every palace has an oracle at its zero point. The oracle is a v2
Agent DreamBall — full slot surface: `personality-master-prompt`,
`memory`, `knowledge-graph`, `emotional-register`, `interaction-set`
— but occupies a distinguished position in the palace: **felt
everywhere, voice at the fountain**. The wayfarer can converse with
the oracle from anywhere (the emotional-register of the fountain
tints every lens), but the full-sit interaction is reserved for the
courtyard where the fountain lives.

The oracle's peculiar responsibility is that the **current head of
the mythos chain is always in its context**. This is how the
palace's keystone remains load-bearing during reasoning: no matter
what room the conversation is in, the mythos is present. When a
new true name is about to surface (the `reflect` ritual; PRD FR60e),
the oracle is the one who proposes it, drawing on the timeline since
the last renaming, the aqueducts whose strength has grown most, and
the emotional register's trajectory.

## 7. The palace shifts; its essence doesn't

Rooms rearrange themselves based on what's being used. A Room of
Requirement behaviour is default, not exceptional. Two viewers of
the same palace may see different layouts simultaneously — the
`ball.layout` attribute is a rendering hint, not a security claim,
and multiple layouts can coexist. Spatial relationships are
metaphor; the palace is not bound by physics.

The thing that **does not shift** is the genesis mythos. Everything
else — the layout, the current mythos head, the aqueduct
strengths, the archiforms of rooms, the oracle's emotional
register — evolves. The genesis is the palace's fixed point; the
evolving surface is how it comes to know itself through being
lived in.

## 8. Two hash-linked chains — doings and becomings

The palace introduces two parallel append-only signed chains:

- `ball.timeline` + `ball.action` — the record of *doings*. Every
  state-changing palace action is signed and linked to its parent
  by Blake3 hash. The chain is CRDT-compatible at the wire level
  (merge semantics are explicitly deferred to Vision tier).
- `ball.mythos` — the record of *becomings*. Every true-naming
  extends this chain; the genesis terminates it on the far side.

The symmetry is deliberate. The protocol's sister system (recrypt)
already uses a hash-linked signed model for its encrypted-file
history; the palace reuses the pattern twice, in two different
registers. If the wire shape feels familiar, that's on purpose.

## 9. Why these belong here and not only in the PRD

A product requirements doc records *what ships*. A vision doc
records *what the work is for*. The palace's mytho-poetic framing —
Vril, archiform, keystone, oracle — is not ornamental. It directs
concrete implementation choices:

- The renderer's default aesthetic (PRD NFR14) is specified against
  the Vril metaphor. Without that metaphor written down in a
  non-prescriptive register, the next renderer author would
  reasonably strip the "flowing light" affect as gratuitous.
- The mythos-as-keystone framing is why the mythos chain is in the
  protocol at all (PROTOCOL §13.8). Without the keystone metaphor,
  the mythos looks like a redundant `name` field; with it, the
  append-only signed chain is obviously load-bearing.
- The archiform/element-tag distinction is why they're two tags and
  not one. Without the distinction — form (archetype) vs substance
  (element) — it would be tempting to collapse them, and the
  oracle's reasoning shortcuts (§15.4) would lose a handle.

The vision doc is where these metaphors live so that future
contributors (human or AI) can tell *why* each protocol decision
exists before they touch the code that implements it. The palace
is the first composition to prove the pattern; more will follow.
