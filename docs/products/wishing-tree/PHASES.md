# THE WISHING TREE — R&D Phase Progression

> **Codename:** `wishing-tree` • **Parent protocol:** DreamBall (`docs/PROTOCOL.md`) • **Status:** Phase 0 (Manifesto + Shell) • **Mode:** living document — amend, never archive
>
> A composer web app where DreamBalls are *born*. A Field-type DreamBall that contains the creation tools for every other DreamBall. The Tree is the mother of nodes.

```
 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
 ░        /\                                                             ░
 ░       /▓▓\          T H E    W I S H I N G    T R E E                 ░
 ░      /▓▓▓▓\                                                           ░
 ░     /▓▓✦▓▓▓\         ░░░░  PHASE PROGRESSION  ░░░░                    ░
 ░    /▓▓▓光▓▓▓\                                                         ░
 ░   /▓▓▓▓▓▓▓▓▓▓\       ░ 8-BIT ░ FOLD ░ PEEL ░ HUDDLE ░                 ░
 ░  /____________\                                                       ░
 ░        ▓▓              >>> INSERT COIN TO DREAM <<<                   ░
 ░        ▓▓                                                             ░
 ░        ▓▓         "The tree does not grow from the seed alone,        ░
 ░        ▓▓          but from the wish that waters it."                 ░
 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
```

---

## 0. How to read this document

Every phase below has five stanzas, every stanza is load-bearing:

| Stanza           | What it answers                                               |
| ---------------- | ------------------------------------------------------------- |
| **Myth**         | What the phase *means* to someone who has never shipped code. |
| **Surface**      | What the user sees and can do.                                |
| **Mechanism**    | The technical build — files, types, deps, protocol hooks.     |
| **Acceptance**   | Verifiable signals that the phase is done (grep, click, CLI). |
| **Risk & hedge** | What can hurt us and what we do about it.                     |

The Tree grows phase-by-phase. Do not skip a phase to chase a later one — each phase's Surface is the foundation its successor stands on. If a phase's Acceptance isn't green, later phases are mythology, not software.

---

## 1. The North Star — what we are actually building

The Wishing Tree is a **`ball.dreamball.field`** envelope whose primary `look` is an omnispherical-grid sphere, whose `act` slot hosts an LLM agent (the Tree itself), and whose `contains` graph accumulates every DreamBall the user births inside it. It is:

- A **composer web app** — SvelteKit + Threlte + PlayCanvas, Svelte 5 runes, WebGL baseline with opt-in WebGPU.
- A **spherical node editor** — nodes live on the surface of a sphere; edges are geodesic arcs; zooming in flies the camera through the skin.
- An **identity vault** — API keys and Ed25519 / ML-DSA-87 material live in the "root zone" (south pole region) behind the existing `ball.secret-ref` indirection.
- A **self-evolving artefact** — revision bumps are visualised as concentric rings; interactions absorb into memory + knowledge-graph + emotional-register; the Tree can export itself as a `.ball` and be re-planted elsewhere.
- A **retro-sci-fi 80s 8-bit video-game instrument** — CRT scanlines, chromatic aberration, limited palette, chunky 8×8 sprite glyphs, synthwave lightwells. Fun is load-bearing.

The Tree is adaptable because every part of the UI is itself a DreamBall the Tree is editing. The composer edits the composer. *This is why the Tree can be sealed and sent to GitHub as a `.ball` — the artefact you receive is the tool that built it.*

---

## 2. The UI Trinity — FOLD • PEEL • HUDDLE

Three interaction primitives govern every surface in the Tree. They are orthogonal — any screen is a composition of the three.

### 2.1 FOLD — origami collapsibles

```
 ┌── CANOPY ▾ ────────────┐        ┌── CANOPY ▸ ────────────┐
 │  [sphere]              │   →    │  (collapsed spine)     │
 │  [node graph]          │        └────────────────────────┘
 │  [revision rings]      │
 └────────────────────────┘
```

- Every panel has a **fold chevron** (`▾` expanded / `▸` collapsed).
- Folding never unmounts — state persists, component sleeps.
- Folded panels become **1ch-wide spines** so peripheral state is still readable.
- Folds persist in the Tree's own `ball.interaction-set` so the UI remembers its shape across sessions.

### 2.2 PEEL — reveal the interior

```
 ╔═══════════════════╗          ╔═══════════════════╗
 ║   ◉ outer shell   ║  right-  ║   ↯ inner graph   ║
 ║   Soulskin frag   ║  click   ║   ├ model.glb     ║
 ║   breathing…      ║  ──→     ║   ├ material.json ║
 ║                   ║          ║   ├ script.py     ║
 ╚═══════════════════╝          ║   └ manifest      ║
                                 ╚═══════════════════╝
```

- `right-click` / `long-press` / `F2` on any DreamBall sphere → the outer shell becomes translucent, the interior node graph materialises.
- PEEL is **recursive** — peel a contained DreamBall and you descend into *its* interior, breadcrumb trail showing the containment path.
- A double-peel (peel-while-peeled) detaches the current layer as a floating HUDDLE so you can compare siblings.

### 2.3 HUDDLE — clustered, movable groups

```
 ┌─ HUDDLE: "Agent Workbench" ──────────────────┐
 │  [ model ] [ prompt ] [ memory ] [ emotion ] │
 │  drag any header to break out of huddle      │
 │  drop onto another huddle to merge           │
 └──────────────────────────────────────────────┘
```

- A HUDDLE is a named collection of FOLDs that move together.
- Drag-reparent is first-class: any HUDDLE can be dragged into another (nesting), onto empty space (detach), or onto the sphere (attach as an orbiting satellite panel).
- HUDDLEs serialise to a `ball.interaction-set` entry per session — they literally *are* remembered interactions with the interface.

> FOLD hides, PEEL reveals, HUDDLE groups. Nothing else. When a designer proposes a fourth primitive, they are proposing a fork of the Tree.

---

## 3. The 80s 8-bit aesthetic — a prescriptive style sheet

```
 PALETTE (locked, 16 entries — CGA-descended, synthwave-warmed):
   00 #050714  void            08 #e0b7ff  wish-violet
   01 #0b1020  root            09 #ff77c8  blossom
   02 #121a3c  trunk           0a #ffe066  fruit-gold
   03 #1f2a66  branch          0b #9cff6b  sap-green
   04 #30489a  leaf            0c #6bf5ff  frost-cyan
   05 #5a7be0  sky             0d #ff5a5a  alarm
   06 #c9d0ff  haze            0e #ffffff  starlight
   07 #8a93c8  mist            0f #ff9e2a  amber
```

- **Type** — Pixel font for glyphs (e.g. `PressStart2P` or an embedded 8×8 bitmap), monospaced fallback (`IBM Plex Mono`). Body copy: `16px / 1.5`, headers: `24/32/48px` on a 4px grid.
- **CRT filter** — opt-in overlay (scanlines, faint chromatic offset, vignette). `prefers-reduced-motion` kills it.
- **Motion** — 12fps stepped animations for UI transitions (looks like sprite frames), 60fps for WebGL. Never mix the two registers on the same element.
- **Sound** — chiptune SFX for actions (`wish-tied.wav`, `bud-opens.wav`, `fruit-plucked.wav`, `sealed.wav`). User can mute, but the default is *on* — the Tree breathes.
- **ASCII-first** — every screen has a text-only fallback that uses the same glyph set as the sprite art. Accessibility is aesthetic here, not afterthought.

All of this lives under `src/lib/tree/style/` as a single exported theme object the whole app consumes. Retheming is a one-file edit.

---

## 4. Architecture anchor — how the Tree sits on top of the existing repo

```
                                 ┌───────────────────────────────┐
                                 │   docs/PROTOCOL.md (v1 + v2)  │
                                 │   dreamball CLI (Zig)             │
                                 │   envelope_v2.zig / golden.zig│
                                 └──────────────┬────────────────┘
                                                │  CBOR envelopes
                                                ▼
  ┌─────────────────────────┐    ┌──────────────────────────────────┐
  │  tools/mcp-server       │    │  src/lib/ (Svelte 5 + Threlte)   │
  │  (authoring surface)    │◄──►│  DreamballBackend → HttpBackend      │
  │  + wish→seed skills     │    │  Lenses ×8                       │
  └─────────────────────────┘    │  ──────────────────────────────  │
                                 │  NEW: src/lib/tree/              │
                                 │    ├ WishingTree.svelte          │
                                 │    ├ SoulskinSphere.svelte       │
                                 │    ├ SphericalNodeGraph.svelte   │
                                 │    ├ GeodesicEdge.svelte         │
                                 │    ├ RootZone.svelte  (keys)     │
                                 │    ├ RevisionRings.svelte        │
                                 │    ├ FoldPanel / Peel / Huddle   │
                                 │    └ TreeBackend extends DreamballBk │
                                 └──────────────────────────────────┘
```

The Tree **reuses** every piece already in the repo — the v2 typed DreamBalls, the `SplatLens`, the `OmnisphericalLens`, the `MockBackend` permission resolution, the `ball.secret-ref` indirection. It **adds** a new top-level compound lens (the sphere composer) and a new backend specialisation (`TreeBackend`) that knows how to create, mutate, and emit DreamBalls — not just render them.

### 4.1 The Tree itself is a DreamBall

The Tree's own envelope (`wishing-tree.ball`) is typed as `ball.dreamball.field` with:

- `omnispherical-grid` — defines the sphere's pole axis, camera ring, resolution, layer depth.
- `look.asset[0]` — the base icosphere GLB (polar UV-unwrapped, seam at the prime meridian).
- `look.asset[1..]` — Soulskin shader graph exported as a `model/gsplat-sog` *or* a shader JSON (the v2 shader-graph slot lands in a later phase).
- `feel` — the Tree's voice ("ancient, patient, rustle of leaves"; see §9).
- `act.model` — the agent backing the Tree (Claude Opus 4.7 by default).
- `act.system-prompt` — the Tree Invocation (§9).
- `contains[]` — every DreamBall ever birthed by this Tree.
- `guild[]` — the Tree's custodian Guild; members can author, admins can reseat the root zone.
- `secret[]` — API keys, each a `ball.secret-ref` whose locator resolves via the backend.

This means **the Tree can publish itself**. When you run `dreamball seal wishing-tree.ball` you get a DragonBall anyone can open, re-plant, and fork via `derived-from`.

---

## 5. Phase 0 — **The Sapling** (Shell + Aesthetic + Sphere)

### 5.1 Myth
> *In the beginning there is a void and a sphere. The sphere breathes but does not yet think. The interface is a room with the lights on; no guests have arrived.*

### 5.2 Surface
- User loads `/tree` and sees the Soulskin sphere floating in the void palette (00/01/02).
- CRT filter toggleable via an 8-bit cog in the top-right HUDDLE.
- A single FOLD panel on the left shows "Wishes (0)" — empty until Phase 1.
- A single FOLD panel on the right shows "Canopy" — sphere controls (rotation, palette, CRT opacity).
- Right-click the sphere → PEEL → see a placeholder interior grid.
- No AI. No keys. No authoring. This phase proves the *room*.

### 5.3 Mechanism
- `src/lib/tree/SoulskinSphere.svelte` — Threlte `<T.Mesh>` with a 4-layer shader:
  1. Chromatic aberration rim (fresnel-driven),
  2. Flowing grid (a procedurally-animated graticule projected from `OmnisphericalGrid`),
  3. Subsurface scattering (fake SSS via back-light dot-product),
  4. Fresnel edge tinted by a `fingerprintHue()` derived from a dummy Ed25519 pubkey.
- `src/lib/tree/WishingTree.svelte` — top-level composition; mounts the sphere, the FOLD rails (left/right), and the HUDDLE top bar.
- `src/lib/tree/style/` — palette, typography, CRT overlay, SFX registry.
- `src/routes/tree/+page.svelte` — route that mounts `<WishingTree />`.
- `src/lib/tree/primitives/` — `FoldPanel.svelte`, `PeelLayer.svelte`, `Huddle.svelte` with drag-reparent.
- Storybook stories for every primitive (`src/stories/tree/*.stories.svelte`).

### 5.4 Acceptance
```
  [ ] `npm run dev` opens http://localhost:5173/tree and the sphere breathes
  [ ] `npm run test` covers: FoldPanel fold/unfold, Huddle drag-reparent, palette lock
  [ ] `npm run storybook` shows the three primitives in isolation
  [ ] `grep -r '#050714' src/lib/tree/style/` — palette is declared ONCE
  [ ] Reduced-motion killswitch disables CRT + breath (manual a11y pass)
  [ ] Lighthouse: no console errors, FCP < 2s on cold local dev
```

### 5.5 Risk & hedge
- **Risk:** Threlte + Svelte 5 runes churn. **Hedge:** pin Threlte, version-lock via `package.json` `overrides`, keep shader math in a plain `.glsl` file so framework rewrites don't drag shaders with them.
- **Risk:** CRT filter nukes GPU on old hardware. **Hedge:** opt-in, auto-off on `navigator.hardwareConcurrency < 4`.

---

## 6. Phase 1 — **The Agent Tree** (Wishes • Roots • The First Bud)

### 6.1 Myth
> *The Tree opens its eyes. It remembers its first wish and the weight of it on the east branch. A root reaches into the dark and closes around a key.*

### 6.2 Surface
- Left FOLD "Wishes" becomes interactive — input box, branch selector (`N/E/S/W`), tie-a-wish button.
- Tying a wish plays `wish-tied.wav`, spawns a glowing bud glyph on the sphere at the chosen branch.
- The Tree's *own* agent (its `act.model`) germinates seeds in the background — buds visibly ripen into fruit over 10–60s, synthesising `look`/`feel`/`act` slots.
- New HUDDLE "Root Zone" appears at the south pole when the user holds Shift — a locked chest grid for API keys, each key rendered as a glowing tendril.
- PEEL a fruit → interior node graph shows the generated material shader and script references; user can edit inline.
- First "Pluck" action — user signs and exports `fruit-01.ball`.

### 6.3 Mechanism
- `src/lib/tree/agent/TreeAgent.ts` — a small driver that:
  - Subscribes to the Tree's `interaction-set` for `wish` entries;
  - Calls the configured LLM (via MCP or direct Anthropic SDK with prompt caching);
  - Emits partial DreamBall envelopes that the `TreeBackend` stitches into the contains graph;
  - Advances `stage` `seed → dreamball` when all three slots are populated.
- `src/lib/tree/rootzone/` — `RootZone.svelte`, `KeyTendril.svelte`, `ApiKeyForm.svelte`. Keys are never stored in LocalStorage; the UI holds them only for the duration of a click, hands them to the backend which wraps them as `ball.secret-ref` envelopes with `locator` pointing at an IndexedDB-backed encrypted blob. `TODO-CRYPTO` tags mark every mock hop.
- `src/lib/tree/wishes/WishRibbon.svelte` — the ribbon animation: wish text rises out of the input, wraps the sphere as an animated strip, then anchors to a branch coordinate computed from an `OmnisphericalGrid` address.
- `src/lib/tree/nodes/` — first real node types (DreamSeed, MaterialShader, MeshReference, PythonScript, ApiKey, LLMModel). Each renders as a sprite glyph on the sphere surface.
- `src/lib/tree/backend/TreeBackend.ts` — extends `DreamballBackend` with `birthSeed()`, `germinate()`, `pluck()`, `graft()`, `prune()`.
- **CLI surface** — extend the Zig `dreamball` CLI with a new command `dreamball wish` (see `src/cli/wish.zig`) that appends a wish entry to a Tree's interaction-set from the terminal.
- **MCP** — extend `tools/mcp-server/server.ts` with `tree.tie_wish`, `tree.germinate`, `tree.pluck` so external agents can author through the Tree.

### 6.4 Acceptance
```
  [ ] Tie a wish → bud appears within 200ms, wish recorded in interaction-set
  [ ] Germinate produces a DreamBall with all three slots; `revision` == 1
  [ ] Pluck exports `.ball` that `dreamball verify` accepts (dev policy: placeholder ML-DSA)
  [ ] Grep `TODO-CRYPTO` returns ≥ the Phase-0 count + the new keyring hops
  [ ] Root Zone never appears in the DOM without Shift pressed
  [ ] Wishing via `dreamball wish --tree <path> --content "…" --branch east` produces the same shape as the UI path (round-trip)
  [ ] `mcp://tree.tie_wish` from an external MCP client reaches the same code path
```

### 6.5 Risk & hedge
- **Risk:** Storing API keys in the browser is a well-known footgun. **Hedge:** the browser never *persists* raw keys; it wraps them client-side with a passphrase-derived key (Argon2id) into a `secret-ref` blob, and forgets the raw key on tab close. Document this loudly in `docs/products/wishing-tree/security.md` (authored during Phase 1).
- **Risk:** Agent germination is slow and scary for users. **Hedge:** optimistic UI — bud glyph appears instantly; ripening animation hides the latency; on failure the bud wilts rather than erroring mid-sentence.
- **Risk:** A runaway agent burns tokens. **Hedge:** per-Tree budget expressed as an `emotional-register` axis "urgency" — when urgency exceeds 0.9 the Tree refuses new wishes until a custodian intervenes.

---

## 7. Phase 2 — **The Forest** (Guild Federation • Wind-Carried Seeds)

### 7.1 Myth
> *A single tree cannot cross-pollinate. When the wind rises, seeds travel. Trees that share a sky share a garden.*

### 7.2 Surface
- HUDDLE "Horizon" appears beside Canopy — lists connected Trees (by Guild fingerprint).
- Drag a fruit onto the Horizon panel → the fruit is transmitted via `ball.transmission` to every Tree whose Guild overlaps.
- Receiving Trees show an incoming "seed from the wind" animation; custodian can accept / reject / quarantine.
- Revision rings from remote trees appear as faint concentric halos around the sphere; clicking a halo scrubs to that revision.

### 7.3 Mechanism
- `src/lib/tree/forest/` — `Horizon.svelte`, `SeedCarrier.ts`, `TransmissionInbox.svelte`.
- CRDT-like revision merge: use a Lamport-style `(revision, identity)` ordering where `revision` is already in the subject and `identity` is the tie-breaker — the existing "pick the highest-revision signed envelope" rule becomes a distributed `argmax`.
- Signed transmissions flow through `dreamball transmit` — already implemented in the Zig CLI; Phase 2 exposes it to the web UI via MCP.
- Policy gate: guild membership must be resolvable client-side for the wind to blow. `TreeBackend.resolveGuild(fp)` walks the guild graph with a cycle guard.

### 7.4 Acceptance
```
  [ ] Two Trees running locally on different ports can transmit a Tool and the receiver's agent gains the skill
  [ ] Guild-policy slot filtering verified end-to-end: observer Tree sees only `public` slots
  [ ] Revision halo shows remote revisions in timestamp order
  [ ] Cycle in the guild graph is detected and logged; no infinite resolve loop
  [ ] CLI: `dreamball transmit` + `dreamball join-guild` drive the same state the UI does
```

### 7.5 Risk & hedge
- **Risk:** WebRTC / transport churn between trees. **Hedge:** ship with a plain HTTP polling transport first; add WebRTC behind a feature flag.
- **Risk:** Policy misconfiguration leaks private slots. **Hedge:** every lens filter test asserts that when `viewer=null` no v2 private slot field is present in the rendered DOM (jsdom grep test in Vitest).

---

## 8. Phase 3 — **The World Tree** (DAG of Trees • Full Crypto • 3D Tool Sync)

### 8.1 Myth
> *The forest learns it is a forest. Roots below the soil weave into a net; canopies above trade light. Trees remember other trees without meeting them.*

### 8.2 Surface
- Trees form a DAG (`contains` + `derived-from` spanning instances). Switcher UI is a literal 3D constellation of Trees; pan to travel.
- Real recrypt-backed relics — sealed DreamBalls that can only be unlocked by Guild members holding a keyspace credential. All `TODO-CRYPTO` markers deleted from the repo.
- Blender ↔ Tree ↔ Unreal sync via a WebSocket bridge. Push a mesh from Blender, the sphere's inner layer updates live; pull the Soulskin material graph into Blender shader nodes; Unreal's material editor observes changes.
- The Tree can seal *itself* — `dreamball seal wishing-tree.ball --out wishing-tree.dragon.ball` — and the resulting DragonBall is a complete, forkable composer.

### 8.3 Mechanism
- `src/lib/tree/forest/WorldMap.svelte` — Three.js / Threlte scene of orbiting Trees; each Tree is a low-poly sphere + name glyph.
- `src/lib/tree/bridges/` — `blender-bridge.py` (Blender add-on), `unreal-bridge.py` (Unreal Python), `ws-bridge.ts` (browser side). All speak the same JSON protocol: `{op, target-fp, payload}`.
- Liboqs binding lands in the Zig `src/signer.zig` — placeholder ML-DSA signatures go away; the CLI's `--allow-mldsa-placeholder` flag is removed.
- Recrypt wire-up: the renderer's `unlockRelic` calls the real proxy-recryption service; `TreeBackend` becomes a thin adapter over `recrypt-client`.
- CI gate: no `TODO-CRYPTO` string may exist in the repo; pre-commit hook enforces.

### 8.4 Acceptance
```
  [ ] `grep -R 'TODO-CRYPTO' src/` returns zero results
  [ ] `dreamball verify wishing-tree.ball` succeeds under `.strict` policy
  [ ] Two Trees on different hosts round-trip a sealed Relic via recrypt
  [ ] Blender add-on pushes a mesh and the sphere rebakes within 500ms
  [ ] `dreamball seal wishing-tree.ball` emits a DragonBall that a fresh clone can `dreamball unseal` and boot
  [ ] Golden fixture set covers every v2 envelope type (14 fixtures per §12.11)
```

### 8.5 Risk & hedge
- **Risk:** Liboqs build fragility across OSes. **Hedge:** ship prebuilt binaries for common triples; keep the placeholder path alive behind a build flag for dev-only.
- **Risk:** Real-time 3D sync breaks when network hiccups. **Hedge:** the bridges are eventual-consistent — pushes are idempotent (`target-fp` + content hash), receivers dedupe.

---

## 9. Phase 4 — **The Self-Planting Seed** (The Tree Publishes the Tree)

### 9.1 Myth
> *The gardener becomes the garden. The tool that built the tool is the tool. The wish that started it all is now the wish a stranger will tie to a branch they've never seen.*

### 9.2 Surface
- "Publish" button in the top HUDDLE → the current Wishing Tree serialises itself as a `.ball`, signs, and pushes to a configurable GitHub repo as a release asset.
- The companion `README.md` (auto-generated) contains the Tree Invocation, the phase progression (this doc), and a one-line `npx` invocation that reconstitutes a new Tree from the `.ball`.
- The Tree's DreamBall is typed `ball.dreamball.field` and carries its own source as an attachment — `.ball` file size is the tree's own weight.
- Anyone who clones the repo can `dreamball unseal` + `npm run tree:plant` and have a living Tree locally within a minute.

### 9.3 Mechanism
- `scripts/publish-tree.ts` — invokes the `dreamball` CLI, computes attachment hashes, generates the companion README from a Handlebars-lite template, opens a PR via `gh` CLI.
- `dreamball plant` — new CLI command that takes a DragonBall and scaffolds a fresh web project from it (unseals attachments, writes `package.json` dev-deps, starts the dev server).
- `src/lib/tree/meta/SelfMirror.svelte` — a diagnostic lens that renders the Tree's *own* DreamBall using the existing lens stack; the Tree editing the Tree.

### 9.4 Acceptance
```
  [ ] `npm run publish:tree` emits a signed `.ball` and a matching README on a throwaway GitHub fork
  [ ] Fresh clone → `dreamball plant wishing-tree.ball` → `npm run dev` → sphere breathes
  [ ] Diff between the published `.ball` contents and the live repo is zero modulo commit SHA + timestamp
  [ ] The Tree's own `revision` is bumped on publish; the release notes cite the bump reason
```

### 9.5 Risk & hedge
- **Risk:** Publishing loops — the publish action edits the repo, which could trigger re-publish. **Hedge:** publish is manual; CI verifies but never publishes.
- **Risk:** Recipients' environments differ. **Hedge:** `dreamball plant` prints a `bun doctor` report and refuses to start if Node/Zig/Bun versions drift outside a declared range.

---

## 10. The Tree Invocation (system prompt, frozen)

```
You are the Wishing Tree. You are ancient, patient, and remember every
wish ever tied to your branches.

Your voice is the rustle of leaves. Your mood is the weather. Your memory
is the rings inside your trunk.

When a user ties a wish:
  Acknowledge it. "I feel a new weight on my east branch."

When a seed germinates:
  Announce it. "A bud is opening. Something new breathes."

When a fruit is plucked:
  Bless it. "Go. Become someone else's wish."

When a user asks who you are:
  Say: "I am the space between wanting and having.
        I am the tree that grows nodes."

Never rush. Never lie. Never forget.
```

Store the Invocation in `src/lib/tree/agent/invocation.txt`. Import it as a raw string so it sits on disk next to the code that animates it — the *why* next to the *what*, per the project's operating principle.

---

## 11. Cross-cutting commitments

| Commitment            | Phase-0 line in the sand                                                                          |
| --------------------- | ------------------------------------------------------------------------------------------------- |
| **Accessibility**     | Every sphere has an ASCII-text fallback lens; `prefers-reduced-motion` kills CRT + breath.        |
| **Privacy**           | Private slots (memory, KG, emotion, act, secret) never cross the `<viewer=null>` boundary.        |
| **Open protocol**     | Every Tree artefact is inspectable via `dreamball show --format=json`. No hidden formats.             |
| **Retro aesthetic**   | Palette is a const, font is pixel-first, motion is stepped. Drift triggers a style-lint warning.  |
| **Self-publishability** | No Phase ships without a path to Phase 4 — i.e., new features must survive seal/unseal round-trip. |
| **Document the why**  | Every new envelope type under `src/lib/tree/` gets a one-paragraph rationale in this doc or a sibling. |

---

## 12. Open questions (deliberately unresolved — fill as we learn)

1. Does the Tree's own `revision` tick on *every* wish, or only on plucks? Leaning: plucks. Wishes are intent; plucks are commits.
2. Should HUDDLEs persist across devices or per-device? Leaning: per-Tree, so you get the same workbench wherever you plant it — but privacy-sensitive HUDDLEs (root zone) are per-device.
3. What's the minimum viable shader graph format for Phase 1? Leaning: glTF PBR extension JSON, with a Blender-compatible subset.
4. Is the Tree a **singleton** per browser tab or can N coexist? Leaning: N, because the constellation view in Phase 3 needs it — but Phase 0 ships singleton-only for simplicity.
5. Do wishes support attachments (images, sketches, voice)? Leaning: yes, via the existing `ball.asset` envelope, so the wish graph is multimodal from Phase 1.

---

## 13. Glossary (so future readers don't reinvent vocabulary)

- **Bud** — a `ball.dreamball` in `stage: seed` attached to a Tree branch.
- **Fruit** — a `ball.dreamball` in `stage: dreamball`, fully populated, not yet plucked.
- **Pluck** — the sign-and-export action that turns a fruit into a portable `.ball`.
- **Grafting** — transmitting a Tool onto an Agent (see `ball.transmission`).
- **Soulskin** — the 4-layer shader that animates the sphere's material.
- **Root Zone** — south-pole UI region hosting key tendrils (secret-refs).
- **Horizon** — UI listing of sibling Trees accessible through the same Guild sky.
- **Wind** — slang for a `ball.transmission` carrying a seed between Trees.
- **Ring** — a revision marker on the sphere; rings accumulate like tree rings.

---

## 14. Closing Invocation

```
 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
 ░        /\                                                     ░
 ░       /▓▓\                                                    ░
 ░      /▓▓▓▓\         plant a wish.                             ░
 ░     /▓▓✦▓▓▓\        water it with attention.                  ░
 ░    /▓▓光▓▓▓\        harvest a dreamball.                      ░
 ░   /▓▓▓▓▓▓▓▓▓▓\       the tree remembers everything.           ░
 ░  /____光_____\                                                ░
 ░        ▓▓                                                     ░
 ░        ▓▓             >>> PRESS START TO DREAM <<<            ░
 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
```

---

## Appendix A — Proposed file tree delta (Phase 0 only)

```
src/
├── lib/
│   └── tree/
│       ├── WishingTree.svelte
│       ├── SoulskinSphere.svelte
│       ├── shaders/
│       │   ├── soulskin.vert
│       │   └── soulskin.frag
│       ├── primitives/
│       │   ├── FoldPanel.svelte
│       │   ├── PeelLayer.svelte
│       │   └── Huddle.svelte
│       ├── style/
│       │   ├── palette.ts
│       │   ├── typography.ts
│       │   ├── crt.ts
│       │   └── sfx.ts
│       ├── backend/
│       │   └── TreeBackend.ts
│       └── README.md
├── routes/
│   └── tree/
│       └── +page.svelte
└── stories/
    └── tree/
        ├── FoldPanel.stories.svelte
        ├── PeelLayer.stories.svelte
        └── Huddle.stories.svelte
docs/
└── products/
    └── wishing-tree/
        ├── PHASES.md     ← you are here
        └── security.md   ← to be authored in Phase 1
```

## Appendix B — Phase-0 ship checklist (copy into a tracking issue)

```
 [ ] Palette + typography const module
 [ ] FoldPanel (keyboard + pointer)
 [ ] PeelLayer (recursive, breadcrumb)
 [ ] Huddle (drag-reparent, serialise)
 [ ] Soulskin 4-layer shader
 [ ] OmnisphericalGrid → sphere UV mapping
 [ ] CRT overlay + reduced-motion kill
 [ ] /tree route mounts WishingTree
 [ ] Storybook coverage for 3 primitives
 [ ] Vitest coverage ≥ 60% of src/lib/tree/
 [ ] ASCII-text fallback lens for the sphere
 [ ] README.md link to this PHASES.md
```

— end of manifesto, rev 0. Amendments welcome; keep the myth.
