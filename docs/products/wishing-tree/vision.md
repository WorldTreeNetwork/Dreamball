# Wishing Tree — Vision

> A reference implementation of the DreamBall open type system (see the
> substrate vision at [`../../VISION.md`](../../VISION.md)). The Tree turns
> the idea on itself: the *composer* is a DreamBall too. A type like any
> other.

> Added 2026-04-19 with the Wishing Tree R&D plan.

Most protocols treat the authoring tool as outside the protocol: a
word processor is not a `.docx`, Blender is not a `.blend`. The
Wishing Tree takes the opposite stance — **the composer is itself a
DreamBall**, typed `ball.dreamball.field`, whose `contains` graph
accumulates every other DreamBall authored inside it.

This matters for three reasons:

1. **Birth is a first-class protocol operation.** v1 and v2 describe
   how DreamBalls *are*; the Wishing Tree defines how they *come into
   being*. Wishes (user intents) become DreamSeeds; seeds germinate
   into DreamBalls via the Tree's own `act` agent; DreamBalls are
   plucked (signed + exported). The whole lifecycle is a DreamBall
   graph, authored by another DreamBall.

2. **The tool is shareable by the same mechanism as its output.**
   Because the Tree is a DreamBall, `dreamball seal wishing-tree.ball`
   produces a DragonBall — the composer ships to anyone via the same
   wire format its own output uses. No vendor runtime, no special
   installer, no "download our app." Plant the `.ball` and the Tree
   grows a new Tree.

3. **Self-similarity all the way down.** The Tree's UI surfaces
   (FOLD / PEEL / HUDDLE) are themselves rendered by the existing
   lens stack — the same lenses that render any other DreamBall.
   Editing the Tree is editing a DreamBall. This closes the loop
   between composer and composed: there is no separate "editor mode"
   and "viewer mode"; there is only the lens you currently have
   open.

The south pole of the Tree is the Root Zone — API keys and signing
material wrapped as `ball.secret-ref` envelopes, never persisted in
plaintext client-side. The outer surface is the Soulskin: a 4-layer
shader whose animation states (breathing, thinking, wishing,
granting, sealing) map to the Tree agent's live activity. Nodes
live on the sphere's surface on great-circle-arc edges rather than
a flat 2D canvas — the sphere's curvature gives a finite, always-
oriented authoring space.

See [`PHASES.md`](PHASES.md)
for the phased R&D plan (Sapling → Agent Tree → Forest → World Tree
→ Self-Planting Seed) and the UI style (retro sci-fi 80s 8-bit,
palette-locked, CRT-optional).
