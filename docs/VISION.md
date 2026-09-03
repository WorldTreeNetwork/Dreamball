# DreamBall Vision

> A living document. Captures the *why* behind the protocol — the philosophical
> and aesthetic commitments that shape what a DreamBall *is* beyond what the
> wire spec describes. When implementation work reveals new structure, write
> it down here.

---

**PART I · WHAT A DREAMBALL IS**

---

## 1. The open type system — a verifiable container for anything

A DreamBall is the simplest useful thing first: **a few bytes of some type,
signed, that anyone can read and verify** without asking permission or
installing a viewer. A name. A number. A 3D transform. A line of a kanban
log. If you can describe its shape, it can be a DreamBall — and once it is,
it carries its own proof of who made it and that no one has touched it since.

The point is the word **anyone**. DreamBall is not a fixed catalogue of
things *we* decided the world needs; it is an **open type system** — the
people building on it author their own types, and get the same machinery we
use, exactly. Describe a type once — a Zig schema, the single canonical
source — and the whole pipeline falls out of it for free: a tamper-evident
envelope derived from the schema, typed encode / decode / validation over
canonical CBOR, and a renderer that knows how to draw the type simply because
it recognises the type's fields. New type, new renderer, no change to the
core. The author can be us or a stranger; the machinery does not care, and
that indifference is the whole gift.

This is the distinction that organises everything below. There is the
**substrate** — the container, the canonical bytes, the signature, the way a
type becomes real — which never changes from one type to the next; and there
are the **types** built on it, ours and yours. Everything in Parts I–III is
substrate: as true of a DreamBall holding a single number as of one holding a
cathedral of memory. The rich things — a Memory Palace you can walk inside, a
Wishing Tree that grows new DreamBalls — are types like any other. We
describe them throughout not because they are special, but because they show
how far the simple rules carry.

The mental model we keep reaching for is a **well-specified zip file**: a
compressed container with internal structure you can inspect without
unpacking everything, that travels as a single opaque file any compatible
tool can open, and that can be nested — a sealed DreamBall tucked inside
another. A zip file with a signature and a vocabulary. That is the whole of
it, and the whole of it is enough.

We did not arrive here from cleverness; the first person who tried to *use*
DreamBall in earnest showed us the door we had built and never opened. They
did not want our types. They wanted their own, with our verifiability
underneath. That request is the product. A universal container that only its
authors can extend is not universal — it is a private tool with a wishlist.
The rest of this vision is what it takes to mean *anyone*.

---

## 2. The three axes — look, feel, act

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

## 3. Aspects are for minds, not just models

A note on the name. An **aspect** in the classical sense is a perspective — a
way the same thing can be regarded. DreamBalls are not just bundles of data
for LLMs to eat; they're **perspectives a mind can take on**. A human can
load a DreamBall to put themselves in a particular mood, visual register, or
operating mode just as readily as an agent can.

This is why the act slot is separable from the rest: you can strip `act` and
still have a meaningful artefact. The feel-and-look pair is enough to be an
aesthetic, a mood board, a persona prompt. With `act` attached, it becomes an
instantiable agent. Both are first-class.

---

## 4. The stages are biological, not technical

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
tree. The graph connections are _containment_ (`contains`) and _inspiration_
(`derived-from`), never _ancestry-of-copy_.

This matters because it resists the instinct to treat every change as a new
entity. A DreamBall is **one living thing across its whole lifetime**; forking
it (making a new identity) is a deliberate act, not the default.

---

## 5. The graph is symmetric and fractal

DreamBalls nest. A DreamBall can contain other DreamBalls (`contains` connections),
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

## 6. Composition beats curation

DreamBalls should be **primarily composed**, not primarily curated. The
catalogue of aspects is not a finite library; it's a runtime produced by
combining and remixing aspects the community publishes.

This has implications:

- **Every containment connection is a composition hypothesis.** "This DreamBall
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

**PART II · OPENNESS, TRUST & BOUNDARIES**

---

## 7. Openness as a security property

The protocol is open. The wire format is self-describing CBOR; the JSON
export is lossless; the signatures are hybrid classical + post-quantum. These
choices collectively mean:

- **Any runtime can read a DreamBall** — there is no proprietary parser, no
  vendor lock-in, no "please install our viewer."
- **Any runtime can verify a DreamBall** — the signatures are standard
  primitives (Ed25519, and hybrid ML-DSA-87 post-quantum).
- **Tampering is detectable without trust** — the verifier needs only the
  public key, which is the identity itself.

This is the IdentiKey family's stance on security: keep the *openness* and
the *crypto* separate. The protocol's openness makes it universally
inspectable; the crypto makes it tamper-evident. Neither property diminishes
the other.

### 7.1 Visibility is per-slot

Openness is not all-or-nothing. A DreamBall can be universally readable in its
public slots while keeping privacy-sensitive slots — secrets, private memory,
an agent's inner state — routed through a permission model keyed to who is
looking. The protocol stays open (every observer can read the public bytes
directly) while the private slots are gated. This is openness-as-security
restated through a permission lens, and it is substrate: any type may have
parts not everyone should see. How a *specific* type draws that line — the
worn/observer split for an avatar, guild policy for a palace — lives with
those types in [`products/`](products/).

---

## 8. One binary, two runtimes — the WASM core

> Added 2026-04-19 with the v2.1 dreamball-server + browser-verify work.

A design principle that emerged from shipping v2.1: **the Zig protocol core
is compiled once to `dreamball.wasm` and executed identically in Bun-server
and in the browser**. Host-provided randomness flows through a single
`env.getRandomBytes` import; nothing else is host-specific.

This is surprisingly clarifying. Traditional architectures carve the protocol
into server-side (trusted, holds keys) and client-side (thin, deserialises
server responses). We don't. The browser can mint, grow, verify, and validate
on exactly the same code paths as the server — and by "the same code," we
mean *the same bytes* — because there is only one compiled artifact.

What this buys us:

- **Impossible drift.** A bug fixed in the Zig core propagates to browser and
  server in one rebuild. No parallel TypeScript CBOR parser exists to fall
  out of sync.
- **Offline-first by default.** Any operation that doesn't need the network
  (mint, parse, verify, grow, join-guild) works in a browser with no server.
  `dreamball-server` is an accelerator, not a requirement.
- **Trust symmetry.** The server's cryptographic guarantees are *the same* as
  the browser's — they run the same verifier on the same envelope bytes. When
  `dreamball-server` claims "this envelope verifies," the browser can
  independently re-verify without trusting the server. This is unusual; most
  systems require trusting the server's claims.
- **Minimal host seam.** One imported function (`getRandomBytes`). Swap hosts
  (Deno, Cloudflare Workers, a custom runtime) and everything still works so
  long as that one import is supplied.

What this *costs*:

- **Blocking I/O stays out of WASM.** File reads, HTTP fetches, and ML-DSA
  *signing* (which would need host entropy on every call) live in the host.
  The protocol core stays pure.
- **ML-DSA *verify* is pure and ships with the WASM.** The vendored liboqs
  subset (`vendor/liboqs/`) compiles clean for wasm32-freestanding via shim
  headers and a static-arena allocator, so browsers verify hybrid Ed25519 +
  ML-DSA-87 signatures locally — no network hop, no recrypt-server dependency.
- **WASM binary size is a real budget.** The browser pays for every byte over
  the wire, so each feature must earn its place. The budget is enforced in
  `build.zig` (and mirrored in `CLAUDE.md`), not narrated here — numbers in
  prose only rot.

The design decision is locked in ADR-1 of the v2.1 plan. The practical
evidence that it works is in `src/lib/wasm/write-ops.test.ts` and
`scripts/spike-wasm-env.ts` — a single WASM export used identically from Bun
tests and the Svelte lib's loader.

---

## 9. What this is NOT · the anti-vision

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
- **Not a network or sync engine.** DreamBall is a wire-format container, not
  transport. It does not move bytes between peers, resolve CRDT conflicts, or
  run a sync protocol — consumers own the network, recrypt owns sealed
  transport. Network-agnosticism is load-bearing.

### 9.1 How we lose the plot

Three guardrails, because these are the failures most likely to creep in:

1. **If DreamBall starts absorbing the network.** It is a verifiable
   wire-format container, not transport. The moment it grows a sync protocol,
   becomes "a CRDT engine," or moves bytes between peers, we have lost the
   plot. Network-agnosticism is load-bearing, not incidental — consumers own
   the network, and recrypt owns sealed transport.
2. **If we keep privileging our own types.** If our reference types stay
   special-cased monolithic code while third parties get "the open path," the
   open path is a fiction. Our types must be the reference implementation of
   the same mechanism, not exceptions to it. Eat our own dog food.
3. **If we over-fit to one consumer.** The first consumer's particular needs
   — their last-writer-wins, their clock shape, their merge rules — are a
   probe to find where we are useful, explicitly **not** the ideal use case.
   The substrate must stay domain-neutral. The day the protocol encodes one
   consumer's domain, we have mistaken the probe for the destination.

---

**PART III · RENDERING & FORM**

---

## 10. Form-independence in the `look` slot (in progress)

This is the section that is **actively evolving** — the user's most recent
insight reshapes how `look` should decompose in future versions of the
protocol.

### 10.1 The problem with mesh+texture

Most 3D formats bundle a **specific mesh** with a **specific texture** via UV
coordinates. UVs are a polar-wrap of a 2D pixel grid onto a 3D surface — the
classic consequence is that polar-projection maps distort at the poles
(small near the top and bottom of a globe) and the whole thing is locked to
the topology it was authored for. Move the mesh, change the topology, and the
texture breaks.

A DreamBall's **look** should outlive any particular mesh. If the underlying
geometry is re-topologised, retargeted, or substituted (low-poly vs hero
variant), the visual identity should still be recoverable.

### 10.2 The graticule metaphor

A **graticule** (as NASA uses in satellite imagery) is a network of lines
showing how space is distributed across a projection — lines of latitude and
longitude on a globe, for instance. A graticule is *about* the space, not
*inside* the space. It describes ratios and distributions independent of
what's being mapped.

For DreamBalls, a graticule-like structure in the `look` slot would carry
**addresses in a reference space** — a way to say "the eye region is here,
relative to the mouth region" — without committing to any specific mesh.

### 10.3 Material shaders as the universal wrapper

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

### 10.4 Base mesh with addressable topology

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

### 10.4.5 The omnispherical perspective grid

> Added 2026-04-18 — this is the most important addition to §10 and comes
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

Wire representation: `ball.omnispherical-grid` (see
`products/dreamball-v2/protocol.md §12.2`). It carries floats for
coordinates — the one documented exception
to v1's no-floats dCBOR rule — because spatial coordinates without floats
would be absurd. The exception is confined to this envelope type.

### 10.4.6 Splats as cached radiance — the renderer's universal scene query

> Added 2026-05-02. Emerges from noticing that the bloom post-effect
> we dial up on the splat lens is a coarse approximation of something
> the splat already knows — and that "what the splat already knows"
> turns out to be the answer to most of the questions the renderer
> keeps asking.

A gaussian splat is not a textured point. It is, mathematically, a
tiny cached tensor: *for every viewing direction within its angular
footprint, here is the colour and radiance you would see.* The
spherical-harmonic coefficients (or SOG-encoded equivalents) are a
compressed description of that direction-dependent emission. Every
splat is already a fragment of a baked light field — a frozen slice
of the ray-traced scene that produced it. A splat *scene* is
therefore the union of those slices: a queryable function `(position,
direction) → radiance`, plus a companion `position → density`,
blanketing the captured volume.

Today's pipeline throws most of that information away. We rasterise
each splat to a single colour, write it into the framebuffer, and
*then* run a chain of post-processes — bloom, tonemap, colour grade,
exposure, ambient occlusion, sometimes screen-space reflections —
each trying to *fake* a property the splat already encoded. Bloom is
the most obvious example: a screen-space gaussian blur over bright
pixels that has no idea which splats contributed which photons, no
access to the off-axis radiance the splat actually encoded, and no
link between a glow's spatial extent and the splats underneath it.
The same critique generalises: every classical post-pass is a
re-derivation of something already in the cached field.

Inverting this gives the **renderer's universal scene query**: treat
`sampleRadiance(p, ω)` and `sampleDensity(p)` as the renderer's two
fundamental primitives, and make every downstream stage — image-based
lighting on inserted meshes, soft shadows, ambient occlusion, camera
collision, reflections, fog, inscription contrast, even the
bloom-replacement that started this thread — a thin consumer of those
two functions. New radiance representations (NeRFs, neural fields,
authored environment SH as fallback) slot in without rewriting
consumers. Avatars walking into a captured palace pre-bake a small SH
probe at their bounding sphere and read it as IBL; the captured
environment lights the imported mesh automatically, no HDRI bake.
Camera collision becomes a density threshold; AO becomes a density
ray-march; reflections become a radiance lookup at the hit direction.
One representation; many consumers.

Post-effects then collapse into something almost embarrassingly
small. Because radiance is stored as SH coefficients (linear basis
functions), exposure, white balance, tonemap, colour grade,
time-of-day, and feel-aspect modulation are all **matrix transforms
applied to the SH vector before evaluation** — five framebuffer
passes collapse into one matmul at sample time. The matrices are
small, differentiable, and naturally trainable: ML techniques absorb
into the rendering layer without any of it leaking to the wire. Vril
flowing into a room becomes a learned operator on that room's cached
radiance field, not a bespoke shader; the *feel* axis acquires a
physical interpretation in the renderer.

This is the strongest expression so far of §10.4.5's claim that splats
are the most honest expression of the omnispherical idea: we treat
them not as a clever rendering hack but as the canonical storage
format for *what light arrives at this point of space, from every
direction* — and the renderer's job is to integrate them through a
small operator algebra, not to retouch their output afterwards.

The architectural pattern, the two-primitive interface, the consumer
table (including the bloom-replacement codenamed *sploom*), the
operator algebra, and the engineering tradeoffs are specified in
[`docs/prd-rendering-engines.md §4`](prd-rendering-engines.md).

### 10.5 The "jelly bean" — form as optional inner slot

The user's sketch: **the DreamBall is the container, the DragonBall is the
skin (Fortnite-style), the jelly bean is the form** — an optional inner slot
that carries topology and addresses.

Concretely, inside `ball.look`, we reserve space for:

- `shader` — material/shader graph (glTF PBR, OSL, or a neutral graph spec)
- `base-mesh` — optional, with named regions and addressable topology
- `graticule` — optional, a space-distribution map that makes the shader
  renderable without committing to a specific mesh (e.g., a splat or
  volumetric field)
- `resolution` — declared quantisation level so consumers know what they're
  getting

v1 of the protocol keeps the simpler `asset` list for compatibility. v2 will
introduce these richer slots as additive attributes, so v1 DreamBalls keep
working and v2 producers can layer form-independent `look` on top.

### 10.6 Open engineering questions

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

## 11. Rendering: lenses and renderer-dispatch

> Added 2026-04-18 with the Svelte/Threlte renderer library.

A **lens** is a schema of visibility — a specific slice of a DreamBall's
slots rendered in a specific way. It is the concrete form of the
renderer-dispatch-by-field-presence rule from §1: a lens recognises which
slots a DreamBall has populated and draws exactly those. New type, new lens,
no core change. The reference renderer ships eight:

| Lens | What it shows | Primary for |
|---|---|---|
| `thumbnail` | tiny card with name + type icon | any type, listings |
| `avatar` | 3D avatar surface (mesh / splat / field) | Avatar, worn Agent |
| `splat` | Gaussian-splat cloud (PlayCanvas, SOG-first) | Avatar / Field when the primary asset is a splat |
| `knowledge-graph` | force-directed 3D graph of triples | Agent |
| `emotional-state` | radial intensity plot of emotional-register axes | Agent |
| `omnispherical` | three-camera onion viewer (§10.4.5) | Field, revealed Relic |
| `flat` | plain 2D text / image card | Tool, any type as fallback |
| `phone` | mobile-portrait optimised layout | any type on a phone |

The `splat` lens deserves special mention. Gaussian splats are the
**topology-free** rendering mode — no mesh, no UVs, just a cloud of
3D-positioned gaussian primitives with colour and opacity. This is the
closest existing consumer-web rendering tech comes to the
**omnispherical graticule** vision in §10.4.5: a DreamBall rendered as
a splat carries spatial distribution without committing to any
particular topology, exactly as the graticule metaphor asks. When a
DreamBall's primary `look.asset` carries a splat media-type (see
[`docs/PROTOCOL.md §4.5`](PROTOCOL.md#45-ballasset)), the viewer
auto-routes to this lens. The reference implementation embeds
PlayCanvas's native GSplat engine because at the time of v2 it is the
most production-ready splat pipeline on the web, handling the ordered
SOG format + compressed PLY out of the box. See the sister project
`/Users/dukejones/work/Projects/Family/web3d-space` for the
renderer pattern we mirrored.

A lens does three things: (a) filters the slot surface to what's
relevant, (b) applies a render strategy (2D / 3D / graph / omni), and
(c) respects the per-slot visibility policy (§7.1) for the viewer identity.

Render backend choices:

- **WebGL via Threlte** — baseline. Every evergreen browser.
- **WebGPU** — opt-in via `preferGpu` prop. Enables ML-core offload for
  graph layouts and shader paths that benefit from compute; degrades
  gracefully back to WebGL where unavailable.

The renderer library lives in `src/lib/`; the showcase app in
`src/routes/`. Both use Svelte 5 runes and Threlte.

---

**PART IV · WHAT YOU CAN BUILD**

---

## 12. The reference types

DreamBall ships six MTG-style types as its reference implementation — proof
that categorically different things can be expressed *as* DreamBall types
rather than as code that merely uses DreamBall. They are not privileged
built-ins; the target is that they are authored through exactly the mechanism
a third party uses to define their own type.

| Type | What it does |
|---|---|
| **Avatar** | worn, visible to observers ("jelly bean" style) |
| **Agent** | instantiable — model + memory + knowledge graph + emotional register |
| **Tool** | a transferable skill |
| **Relic** | sealed + encrypted; reveals on Guild key unlock |
| **Field** | omnispherical ambient layer |
| **Guild** | keyspace-backed group with per-slot policy |

Two principles carry from taking the analogy seriously. **Different types
need different lenses** — a renderer that works uniformly across all types is
wrong; the avatar lens on an agent is silly. And **types compose, they don't
inherit** — a DreamBall isn't "an agent extending an avatar"; it's an agent
*containing* an avatar via the `contains` connection that already exists in
the graph.

The depth — each type's full slot surface, the worn/observer rendering split,
skill transmission between bodies, the jelly-bean and scale metaphors — lives
in [`products/dreamball-v2/`](products/dreamball-v2/vision.md).

---

## 13. Where 3D meets AI

The sharpest thing the substrate makes possible is **convergence**: a single
signed container that is at once *seen* and *thinking*. `look` gives it a body
you can render; `act` gives it a mind that reasons; `feel` colours both; and
the signature underneath means the whole thing carries its own provenance.
Most stacks keep these apart — a 3D asset here, an agent config there, a trust
story bolted on later. A DreamBall is all three at once, in one file,
verifiable.

The range is the point. The same rules hold from the smallest case to the
largest:

- a single verifiable value — a number, a name, signed;
- a 3D object — a transform, a mesh, a splat, that any renderer can place;
- an agent — model, memory, knowledge, emotional register, that can be
  instantiated and grow;
- a whole world — many typed DreamBalls nested into something you can walk
  inside.

Two built examples show how far that carries. The **Memory Palace** is what
happens when an intelligence needs *memory with a place* — rooms you walk,
inscriptions you find again by going back to where you left them, a living
mythos at the keystone. It is near-universal in practice: agentic
intelligence demands memory, and memory wants spatial form. The **Wishing
Tree** turns the idea on itself — the *composer* is a DreamBall too, one whose
`contains` graph accumulates every DreamBall authored inside it, shippable by
the very wire format its output uses. Plant the `.ball`, and the Tree grows a
new Tree.

Both are described where they are built —
[Memory Palace](products/memory-palace/vision.md),
[Wishing Tree](products/wishing-tree/vision.md) — and both are types like any
other. That is the whole demonstration: nothing about them required a
privileged path the substrate doesn't offer everyone.

---

**META**

---

## 14. How this doc evolves

Every time implementation work reveals a new principle or reshapes an
existing one, add it here. Don't worry about making this doc read like a
polished whitepaper — the goal is that a contributor (human or AI) can pick
up any thread and understand **why** the thread exists before they touch the
code that implements it.

Sections currently in motion:

- §1 (the open type system) — the newest organising principle, and the spine
  the rest of this doc now serves. Expect it to drive the next protocol
  additions (the generic signed-op envelope; a consumer schema-registration
  path; the renderer-dispatch contract) and, eventually, the extraction of
  the reference types into first-class type + renderer modules.
- §10 (form-independence in `look`) — active rework triggered by the shader /
  graticule / base-mesh insight. Expect the protocol's `ball.look` envelope to
  formalise this.
- §6 (composition) — the `contains` / `derived-from` graph semantics need
  worked examples; the reference implementations in [`products/`](products/)
  are the first such examples.
- §7 (openness-as-security) — slot-level visibility (§7.1) and the hybrid
  post-quantum signature story both continue to firm up.
- The reference implementations evolve in their own homes:
  [`products/memory-palace/`](products/memory-palace/vision.md),
  [`products/wishing-tree/`](products/wishing-tree/vision.md), and
  [`products/dreamball-v2/`](products/dreamball-v2/vision.md). Each carries
  its own change notes; this doc keeps only the substrate.
