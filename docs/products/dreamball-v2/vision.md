# DreamBall v2 — The Reference Types — Vision

> The six MTG-style types are DreamBall's reference implementation: proof
> that categorically different things can be expressed *as* DreamBall types
> rather than as code that merely uses DreamBall. They are not privileged
> built-ins — the target is that they are authored through exactly the
> mechanism any third party uses to define their own type. See the
> substrate vision at [`../../VISION.md`](../../VISION.md).

## 1. The six-type taxonomy (MTG-style)

> Added 2026-04-18 with the v2 protocol work.

v1 treated `ball.dreamball` as a monolith. That worked for a protocol
spec but collapsed the moment we tried to render one — because different
DreamBalls do **categorically different things**, not just different
variants of the same thing. Magic: The Gathering's category system is the
best analogy:

| MTG type | What it does | DreamBall analogue |
|---|---|---|
| Creature | A body, attacks and blocks | `avatar` — worn, visible, expressive |
| Planeswalker / agent | Acts over time, accumulates state | `agent` — model + memory + emotion |
| Artifact / instant | Activates an effect | `tool` — transferable skill |
| Land | Provides resources / defines space | `field` — omnispherical background layer |
| Sealed / face-down card | Surprise on reveal | `relic` — encrypted until unlocked |
| Deck / band | A collection that plays together | `guild` — a keyspace-bound group |

Two design implications flow from taking the MTG analogy seriously:

1. **Different types need different lenses.** A renderer that works
   uniformly across types is wrong. The `avatar` lens on an `agent` is
   silly; the `knowledge-graph` lens on a `field` is meaningless. Each
   type has a primary lens plus a handful of secondary lenses that make
   sense for it (see `protocol.md §12.1`).
2. **Types compose, they don't inherit.** A DreamBall isn't "an agent
   extending an avatar"; it's an agent *containing* an avatar via the
   graph connection that already exists in v1 (`contains`). An agent may have
   its own avatar; an avatar may be worn by an agent. The `contains` and
   `derived-from` connections carry the compositional semantics we already
   defined in v1 — v2 just teaches the renderer to honour them.

### 1.1 The "jelly bean" metaphor

When a DreamBall is *worn* (the wearer persona, P2), it behaves like a
small object that sits on the wearer's body — an inventory item, a charm,
a jacket patch, a jelly bean on their sleeve. It's tiny compared to the
wearer. And yet, when the wearer speaks, the jelly bean moves its mouth
— the wearer and the DreamBall *share an expression channel*. The
metaphor: **you are it, you become it** — the boundary between wearer and
worn dissolves during the interaction, then re-establishes when the
DreamBall comes off.

Mechanically, this is a rigging job: the wearer's audio or motion input
animates the DreamBall's visual, and both views are rendered
simultaneously — the wearer's own view shows full slots (memory, emotion,
knowledge); the observer view shows only the public slots (the avatar,
maybe a thumbnail of the feel). See §11 on the observer persona.

### 1.2 Scale is situational

A DreamBall might be:

- A **skin** (whole-body texture / mesh replacement) — if worn by an
  avatar of similar scale.
- An **inventory object** (a jelly bean) — if worn as a small charm.
- A **power / buff** (a stat modifier with no visual at all) — if the
  DreamBall is a Tool that augments the wearer invisibly.
- A **field** (ambient context) — if the DreamBall is the dream-field
  environment rather than a discrete actor.

The renderer chooses scale based on **type + context**, not based on a
scale field in the envelope. This is deliberate: scale is a property of
the *rendering situation*, not of the DreamBall itself. A Tool that
bestows flight is one thing in a platformer, something else in a chat
app.

### 1.3 The zip-file insight

Deep down, a DreamBall is a **well-specified zip file**. The `.ball`
bundle is dCBOR plus optional sidecar attachments plus a canonical
header. Zip-like semantics:

- It's a compressed container.
- It has internal structure you can inspect without unpacking everything.
- It travels as a single opaque file that any compatible tool can open.
- It can be nested (a Relic contains a sealed inner `.ball`).

That's the mental model we keep reaching for when describing the
protocol to someone new: "it's a zip file with a signature and a
vocabulary."

## 2. The observer persona (P0)

> Added 2026-04-18 with the six-type taxonomy.

v1 left an implicit gap: who sees someone else's worn DreamBall? v2 names
this persona **Observer / audience** — someone whose browser tab shows
the worn DreamBall but who isn't themselves wearing anything and isn't
the agent's custodian.

Think Fortnite: you walk around as your character; other players see your
skin, your emotes, the effects of your items — but they don't have
access to your inventory, your gear's enchantments, or your friend list.
The avatar is a public surface; the rest is private.

DreamBalls need this split at the protocol level because the Agent's
memory, knowledge graph, emotional register, and interaction history are
**private to its custodian and guild**, while the Avatar's visual
aspect — and any Field it's embedded in — is **public to observers**.
The `ball.guild-policy` envelope (see `protocol.md §12.7`) makes
this policy explicit: slot-level read/write permissions keyed to Guild
membership.

Practically: when rendering a DreamBall the consumer first looks at the
`guild` attribute(s), resolves each to its policy, and filters the slot
surface for the current viewer identity. An observer sees only
`public` slots; a Guild member sees `public` + `guild-only`; an admin
sees everything including `admin-only` (secrets, for instance).

This is openness-as-security restated through a permission lens: the
protocol is still open — every observer can read *the envelope's public
slots* from the raw bytes — but the privacy-sensitive slots are routed
through the Guild's keyspace via recrypt-compatible proxy-recryption.
Today those hops are mocked (see `TODO-CRYPTO` markers in the reference
implementation); the protocol shape lets us slot in the real hops
post-v2 without any wire-format changes.

## 3. Transmission — skills cross bodies

> Added 2026-04-18 with the v2 transmission protocol.

A Tool-type DreamBall is a **skill you can give someone**. The
transmission protocol is the hyperdimensional interface that moves it
from one owner to another target:

1. Sender has a Tool DreamBall (`tool.ball`) that declares what it does
   (a skill envelope: trigger, body, requires).
2. Sender and receiver both belong to a shared Guild `G`.
3. Sender invokes `dreamball transmit tool.ball --to=<receiver-fp>
   --via-guild=<G-fp>`.
4. A `ball.transmission` receipt is produced — a signed, auditable
   record of the transfer — and lodged against the receiver's Agent
   DreamBall.
5. Receiver's Agent custodian re-fetches the Agent; the Agent's
   `act.skill` list now includes the Tool (either embedded or
   fingerprint-referenced); the Agent's `revision` bumps; the Agent
   re-signs.

The reason this needs a Guild rather than point-to-point: it puts **skill
transmission under the same permission model as memory access**. If B is
in a Guild with A, A can transmit capabilities to B via the Guild's
delegation; if B isn't, A has to either invite B into the Guild first or
use a point-to-point recrypt recryption directly.

The Vision-tier extension (FR52 in the v2 PRD) is **chained delegation**:
Guild A → Guild B → agent, so a skill authored in one community can
propagate across federated communities via proxy-recryption. v2 leaves
that hop stubbed; the transmission envelope's shape already supports it.
