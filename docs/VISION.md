# DreamBall Vision

> A living document. Captures the *why* behind the protocol — the philosophical
> and aesthetic commitments that shape what a DreamBall *is* beyond what the
> wire spec describes. When implementation work reveals new structure, write
> it down here.

---

## 1. The three axes — look, feel, act

A DreamBall is an aspect. Aspects are not objects; they are **stances a mind
can take toward the world**. Each axis describes a different dimension of that
stance:

- **look** — the surface: how the aspect presents visually.
- **feel** — the mood: how the aspect inflects tone, pace, affect.
- **act** — the behaviour: what the aspect *does* when instantiated as an
  agent (model, system prompt, skills, scripts, tool affordances).

Together they produce a **coherent perspective** that can be instantiated,
inherited, composed, remixed, and archived — without any one of them being
load-bearing on its own.

---

## 2. The stages are biological, not technical

The lifecycle names — **DreamSeed → DreamBall → DragonBall** — were chosen
because they map real-world development:

- A seed carries potential and the genesis identity; it is small and quiet.
- A ball is the fruit — populated, signed, shareable, but still growing via
  additive revisions.
- A dragon ball is sealed — compressed, maybe encrypted, carrying attachments
  for transport. The dragon is the transport form, not a different kind of
  creature.

The lifecycle is **additive and revisional**, not a fork-and-merge dance. Two
people collaborating on the same aspect share *the same container* and bump
the revision together — like a shared Google Drive document, not a Git branch
tree. The graph edges are _containment_ (`contains`) and _inspiration_
(`derived-from`), never _ancestry-of-copy_.

This matters because it resists the instinct to treat every change as a new
entity. A DreamBall is **one living thing across its whole lifetime**; forking
it (making a new identity) is a deliberate act, not the default.

---

## 3. The graph is symmetric and fractal

DreamBalls nest. A DreamBall can contain other DreamBalls (`contains` edges),
and every contained DreamBall has the **same shape** as its parent — the same
three axes, the same signature structure, the same optional further
containment. This gives us two properties:

- **Fractal self-similarity.** A renderer or agent built to handle one
  DreamBall handles every descendant without special cases.
- **Symmetric composition.** There is no "main" child and no "primary"
  child — a hub DreamBall with ten children treats each equally. Hierarchy
  emerges from intent, not from the protocol.

The result is a directed acyclic graph (cycles forbidden) that is at once
hierarchical *when you look at a single branch* and symmetric *when you look
at a whole layer*. This matches how real knowledge structures feel: a bullet
list inside one point of another bullet list is still just bullets.

---

## 4. Form-independence in the `look` slot (in progress)

This is the section that is **actively evolving** — the user's most recent
insight reshapes how `look` should decompose in future versions of the
protocol.

### 4.1 The problem with mesh+texture

Most 3D formats bundle a **specific mesh** with a **specific texture** via UV
coordinates. UVs are a polar-wrap of a 2D pixel grid onto a 3D surface — the
classic consequence is that polar-projection maps distort at the poles
(small near the top and bottom of a globe) and the whole thing is locked to
the topology it was authored for. Move the mesh, change the topology, and the
texture breaks.

A DreamBall's **look** should outlive any particular mesh. If the underlying
geometry is re-topologised, retargeted, or substituted (low-poly vs hero
variant), the visual identity should still be recoverable.

### 4.2 The graticule metaphor

A **graticule** (as NASA uses in satellite imagery) is a network of lines
showing how space is distributed across a projection — lines of latitude and
longitude on a globe, for instance. A graticule is *about* the space, not
*inside* the space. It describes ratios and distributions independent of
what's being mapped.

For DreamBalls, a graticule-like structure in the `look` slot would carry
**addresses in a reference space** — a way to say "the eye region is here,
relative to the mouth region" — without committing to any specific mesh.

### 4.3 Material shaders as the universal wrapper

Across Blender, SolidWorks, Unreal, Unity, glTF, USD, and game engines
generally, the one unit of appearance that is **already portable** is the
**material shader**. A shader recipe (inputs, graph, outputs) can be applied
to any compatible surface. Different engines interpret the graph differently,
but the abstraction itself is shared.

The shader is therefore the natural primary unit of `look` — more universal
than any mesh. A DreamBall can define what it *looks like* (skin, palette,
iridescence, subsurface scattering, stylisation) as a shader spec, then
optionally provide one or more *embeddings* — a base mesh, a splat, a sprite
sheet — as concrete surfaces the shader can sit on.

### 4.4 Base mesh with addressable topology

When a base mesh is included, its shape should be **topologically
addressable**: every vertex, every edge loop, every region has a stable name
across the lifetime of the container. The Disney-style "base mesh with edge
loops around eyes, mouth, joints" is a good existence proof — a shared
skeletal rig plus named regions supports infinite skin variation while
preserving addressability.

This enables:

- **Composability.** A mouth region defined on one base mesh can be folded
  into another base mesh that also has a mouth region — the shader and the
  mesh share an address space.
- **Quantisation-aware rendering.** A base mesh has an intrinsic *resolution*
  (number of addressable points). Downsampling destroys addresses (like
  quantising a number); upsampling can't recover them. The protocol should
  let producers declare the resolution, and consumers choose what to load.
- **Animation retargeting.** Named regions let skeletal motion generalise
  across meshes that share the naming convention.

### 4.4.5 The omnispherical perspective grid

> Added 2026-04-18 — this is the most important addition to §4 and comes
> from a live brainstorm about *how we actually see*.

Perspective, as computers usually draw it, is straight lines converging on a
vanishing point. That is not how **vision** works. If you peel back your
eyelids, what the retina does is project a **spherical** image onto a
2D-curved sheet whose signal is then carried through the optic nerve and
remapped across your visual cortex — V1 receives a topographically
distorted version of the retinal image; higher areas unfold it further. The
whole pipeline is a chain of **curvilinear** remappings, not
straight-line projections.

A DreamBall's `look` should mirror this. The primary geometric abstraction
is the **omnispherical perspective grid** (an *omni*directional graticule):
a mesh-free description of how space is distributed around an origin. It
carries:

- Pole definitions (usually north/south but not necessarily axis-aligned).
- A **three-camera onion-layer** model — the thing that gives DreamBalls
  their fractal / recursive-layer feel:
  - **Camera 1** — the view *from* the origin outward (you, looking out).
  - **Camera 2** — the view *of* the sphere from outside (someone watching
    you).
  - **Camera 3** — the view from that second camera's radius *back into*
    the sphere and out again (the watcher being watched; or the recursive
    inside-out fold). These can nest further: each layer is a discrete
    quantum jump in "outness."
- A **layer depth** (how deeply the onion nests).
- A **resolution** — how finely the grid is subdivided. Subdivision is
  **forward-only**: like quantising a number, once you destroy vertex
  addresses by up-sampling, you can't recover them. Downstream consumers
  see what was declared, not what was authored.

The final layer — beyond the last onion shell — is the **dream field**:
everything that isn't a discrete DreamBall but forms the ambient context in
which DreamBalls are seen. DreamBalls embed *into* a dream field; a
rendering session always has one dream field active (even if trivially, a
black void).

This matters because mesh+texture assets bind visual identity to a specific
topology; a graticule is **topology-independent**. The same DreamBall can
be rendered against a mesh surface, a gaussian splat cloud, an SDF field,
or a volumetric neural field — because the graticule speaks in the language
of *space distribution*, not of *triangle positions*.

Wire representation: `jelly.omnispherical-grid` (see `docs/PROTOCOL.md
§12.2`). It carries floats for coordinates — the one documented exception
to v1's no-floats dCBOR rule — because spatial coordinates without floats
would be absurd. The exception is confined to this envelope type.

### 4.5 The "jelly bean" — form as optional inner slot

The user's sketch: **the DreamBall is the container, the DragonBall is the
skin (Fortnite-style), the jelly bean is the form** — an optional inner slot
that carries topology and addresses.

Concretely, inside `jelly.look`, we reserve space for:

- `shader` — material/shader graph (glTF PBR, OSL, or a neutral graph spec)
- `base-mesh` — optional, with named regions and addressable topology
- `graticule` — optional, a space-distribution map that makes the shader
  renderable without committing to a specific mesh (e.g., a splat or
  volumetric field)
- `resolution` — declared quantisation level so consumers know what they're
  getting

v1 of the protocol keeps the simpler `asset` list for compatibility. v2 will
introduce these richer slots as additive assertions, so v1 DreamBalls keep
working and v2 producers can layer form-independent `look` on top.

### 4.6 Open engineering questions

1. Which shader graph format to standardise on? glTF material extensions are
   the widest base; OSL is more expressive; USD has the richest tooling.
2. What canonical addressable base mesh(es) to ship as "the Disney of
   DreamBalls" — one for humanoids, one for non-humanoid characters, one for
   inanimate objects, etc.?
3. How to encode "this region is eyes" in a language-agnostic, stable way?
   Named UDIM tiles? A registry of region identifiers?
4. Do graticules (when the form is not a mesh at all — splats, SDFs,
   neural-rendered volumes) need their own envelope type?

---

## 5. Composition beats curation

DreamBalls should be **primarily composed**, not primarily curated. The
catalogue of aspects is not a finite library; it's a runtime produced by
combining and remixing aspects the community publishes.

This has implications:

- **Every containment edge is a composition hypothesis.** "This DreamBall
  includes that one" is a claim that the two fit together meaningfully.
- **Derivation without ancestry.** `derived-from` records that a DreamBall
  drew inspiration from another, but does not imply they share any
  cryptographic material. The inspired container has its own identity and
  its own lifecycle.
- **No central registry required.** Because the identity key is the
  addressable name and signatures establish authority, DreamBalls can be
  discovered anywhere — an IPFS CID, an HTTP URL, a local directory, a QR
  code — and composed without coordination.

---

## 6. Openness as a security property

The protocol is open. The wire format is self-describing CBOR; the JSON
export is lossless; the signatures are hybrid classical + post-quantum with
both required. These choices collectively mean:

- **Any runtime can read a DreamBall** — there is no proprietary parser, no
  vendor lock-in, no "please install our viewer."
- **Any runtime can verify a DreamBall** — the signatures are standard
  primitives (Ed25519 today, ML-DSA-87 as soon as the liboqs binding lands).
- **Tampering is detectable without trust** — the verifier needs only the
  public key, which is the identity itself.

This is the IdentiKey family's stance on security: keep the *openness* and
the *crypto* separate. The protocol's openness makes it universally
inspectable; the crypto makes it tamper-evident. Neither property diminishes
the other.

---

## 7. Aspects are for minds, not just models

A final note on the name. An **aspect** in the classical sense is a
perspective — a way the same thing can be regarded. DreamBalls are not just
bundles of data for LLMs to eat; they're **perspectives a mind can take on**.
A human can load a DreamBall to put themselves in a particular mood,
visual register, or operating mode just as readily as an agent can.

This is why the act slot is separable from the rest: you can strip `act` and
still have a meaningful artefact. The feel-and-look pair is enough to be an
aesthetic, a mood board, a persona prompt. With `act` attached, it becomes
an instantiable agent. Both are first-class.

---

## 8. What this vision does NOT promise

To keep this doc honest:

- **Not a photorealistic renderer.** The protocol carries references and
  specs; it does not define how to rasterise or ray-trace them.
- **Not a VM.** The `act` slot carries prompts/skills/scripts, but DreamBalls
  are not expected to run untrusted code. Executors decide how to sandbox.
- **Not a consensus system.** Revisions are signed by the identity holder;
  there is no distributed agreement about which revision is "canonical."
  Consumers pick the highest-revision signed variant they trust.
- **Not a replacement for recrypt.** Encryption and proxy-recryption live in
  recrypt; DragonBalls delegate to it for sealed transport.

---

## 10. The six-type taxonomy (MTG-style)

> Added 2026-04-18 with the v2 protocol work.

v1 treated `jelly.dreamball` as a monolith. That worked for a protocol
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
   sense for it (see `docs/PROTOCOL.md §12.1`).
2. **Types compose, they don't inherit.** A DreamBall isn't "an agent
   extending an avatar"; it's an agent *containing* an avatar via the
   graph edge that already exists in v1 (`contains`). An agent may have
   its own avatar; an avatar may be worn by an agent. The `contains` and
   `derived-from` edges carry the compositional semantics we already
   defined in v1 — v2 just teaches the renderer to honour them.

### 10.1 The "jelly bean" metaphor

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

### 10.2 Scale is situational

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

### 10.3 The zip-file insight

Deep down, a DreamBall is a **well-specified zip file**. The `.jelly`
bundle is dCBOR plus optional sidecar attachments plus a canonical
header. Zip-like semantics:

- It's a compressed container.
- It has internal structure you can inspect without unpacking everything.
- It travels as a single opaque file that any compatible tool can open.
- It can be nested (a Relic contains a sealed inner `.jelly`).

That's the mental model we keep reaching for when describing the
protocol to someone new: "it's a zip file with a signature and a
vocabulary."

## 11. The observer persona (P0)

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
The `jelly.guild-policy` envelope (see `docs/PROTOCOL.md §12.7`) makes
this policy explicit: slot-level read/write permissions keyed to Guild
membership.

Practically: when rendering a DreamBall the consumer first looks at the
`guild` assertion(s), resolves each to its policy, and filters the slot
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

## 12. Rendering: lenses and backends

> Added 2026-04-18 with the Svelte/Threlte renderer library.

A **lens** is a schema of visibility — a specific slice of a DreamBall's
slots rendered in a specific way. v2 ships eight lenses:

| Lens | What it shows | Primary for |
|---|---|---|
| `thumbnail` | tiny card with name + type icon | any type, listings |
| `avatar` | 3D avatar surface (mesh / splat / field) | Avatar, worn Agent |
| `splat` | Gaussian-splat cloud (PlayCanvas, SOG-first) | Avatar / Field when the primary asset is a splat |
| `knowledge-graph` | force-directed 3D graph of triples | Agent |
| `emotional-state` | radial intensity plot of emotional-register axes | Agent |
| `omnispherical` | three-camera onion viewer (§4.4.5) | Field, revealed Relic |
| `flat` | plain 2D text / image card | Tool, any type as fallback |
| `phone` | mobile-portrait optimised layout | any type on a phone |

The `splat` lens deserves special mention. Gaussian splats are the
**topology-free** rendering mode — no mesh, no UVs, just a cloud of
3D-positioned gaussian primitives with colour and opacity. This is the
closest existing consumer-web rendering tech comes to the
**omnispherical graticule** vision in §4.4.5: a DreamBall rendered as
a splat carries spatial distribution without committing to any
particular topology, exactly as the graticule metaphor asks. When a
DreamBall's primary `look.asset` carries a splat media-type (see
[`docs/PROTOCOL.md §4.5`](PROTOCOL.md#45-jellyasset)), the viewer
auto-routes to this lens. The reference implementation embeds
PlayCanvas's native GSplat engine because at the time of v2 it is the
most production-ready splat pipeline on the web, handling the ordered
SOG format + compressed PLY out of the box. See the sister project
`/Users/dukejones/work/Projects/Family/web3d-space` for the
renderer pattern we mirrored.

A lens does three things: (a) filters the slot surface to what's
relevant, (b) applies a render strategy (2D / 3D / graph / omni), and
(c) respects the Guild policy for the viewer identity.

Render backend choices:

- **WebGL via Threlte** — baseline. Every evergreen browser.
- **WebGPU** — opt-in via `preferGpu` prop. Enables ML-core offload for
  graph layouts and shader paths that benefit from compute; degrades
  gracefully back to WebGL where unavailable.

The renderer library lives in `src/lib/`; the showcase app in
`src/routes/`. Both use Svelte 5 runes and Threlte. Mocked crypto backend
lets the renderer run end-to-end without a real recrypt wire-up; every
mock site is tagged `TODO-CRYPTO: replace before prod` so grep can find
them later.

## 13. Transmission — skills cross bodies

> Added 2026-04-18 with the v2 transmission protocol.

A Tool-type DreamBall is a **skill you can give someone**. The
transmission protocol is the hyperdimensional interface that moves it
from one owner to another target:

1. Sender has a Tool DreamBall (`tool.jelly`) that declares what it does
   (a skill envelope: trigger, body, requires).
2. Sender and receiver both belong to a shared Guild `G`.
3. Sender invokes `jelly transmit tool.jelly --to=<receiver-fp>
   --via-guild=<G-fp>`.
4. A `jelly.transmission` receipt is produced — a signed, auditable
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

## 9. How this doc evolves

Every time implementation work reveals a new principle or reshapes an
existing one, add it here. Don't worry about making this doc read like a
polished whitepaper — the goal is that a contributor (human or AI) can pick
up any thread and understand **why** the thread exists before they touch the
code that implements it.

Sections currently in motion:

- §4 (form-independence in `look`) — active rework triggered by the shader /
  graticule / base-mesh insight. Expect v2 of the protocol's `jelly.look`
  envelope to formalise this.
- §5 (composition) — the `contains` / `derived-from` graph semantics need
  worked examples.
- §6 (openness-as-security) — depends on ML-DSA-87 real signing landing.
