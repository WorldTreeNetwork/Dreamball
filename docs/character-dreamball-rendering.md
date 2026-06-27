# Character DreamBalls — rendering a glTF inside a ball

**Phase:** first character DreamBall (Star Tamagotchi)
**Code:** `src/lib/lenses/AvatarLens.svelte` + `AvatarModel.svelte`,
`src/routes/demo/star/+page.svelte`, fixtures in `static/characters/`

---

## What this is

The first time a DreamBall carries a **character** rather than a scene or a
splat: a textured glTF mesh wrapped in a signed `ball/1` capsule, rendered in
the browser through the existing lens system. Star Tamagotchi is the worked
example; the path is the point — every future character (and the DreamBall
editor that authors them) rides it.

## The path (capsule → pixels)

```
/characters/star-tamagotchi.ball        a signed ball/1 capsule
  → verifyBall(bytes)                    Ed25519 (+ ML-DSA), via dreamball.wasm
  → parseBall(bytes)                     wasm decodes the CBOR envelope → typed DreamBall
  → <DreamBallViewer ball lens="avatar"> routes by look.asset[0] media-type
  → AvatarLens                           reads look.asset, picks the mesh asset
  → AvatarModel (useGltf)                loads + auto-fits the glTF
  → three.js                             draws it (EXT_texture_webp native)
```

The **wasm is the single source of truth** in the browser exactly as it is on
the server and in the CLI (the cross-runtime invariant — see
[`CLAUDE.md`](../CLAUDE.md) and [`ARCHITECTURE.md`](ARCHITECTURE.md)). The
renderer never hand-parses the envelope; it asks the wasm, gets a typed ball,
and reads `look.asset`. The mesh itself lives **outside** the capsule: the ball
holds a *pointer* (`look.asset[].url`) plus a Blake3 `hash` for integrity, not
the GLB bytes.

## Why AvatarLens auto-fits

Characters arrive from many DCC tools (Blender, Meshy, …) with arbitrary unit
scale and origin. `AvatarModel` recentres the loaded scene on the origin and
uniformly scales it so its largest bounding-box axis is `fit` (default 2) world
units, then lifts it so its base sits on `y = 0`. The lens's shared camera then
frames every character consistently, regardless of how it was exported. The
GLB's own materials and animations are left untouched.

The crystal placeholder remains as the graceful state: shown while the mesh
loads, when the ball has no mesh asset, or if the load fails — the lens always
renders something and never blocks on the network.

## Splat vs mesh routing

`DreamBallViewer` inspects `look.asset[0]`'s media-type. Gaussian-splat types
(see [`splat/media-types.ts`](../src/lib/splat/media-types.ts)) route to
`SplatLens` (PlayCanvas); everything else with a `model/gltf-binary` /
`model/gltf+json` asset (or a `.glb`/`.gltf` URL) renders through `AvatarLens`.
This is why a character ball asks for `lens="avatar"` and just works.

## Authoring a character DreamBall (how Star was made)

1. **Optimize the mesh.** A raw Meshy export was 18 MB / 228k tris; run
   `gltf-transform optimize` (webp textures, simplify) → ~1 MB / 18k tris. webp
   is fine — three's GLTFLoader decodes `EXT_texture_webp` natively.
2. **Author the look slot.** Write a `ball.look` JSON whose `asset[]` points at
   the served GLB with its Blake3 `hash` (base58, 32 bytes).
3. **Mint + grow with the CLI** (hybrid Ed25519 + ML-DSA signature; the
   browser/Bun wasm `growDreamBall` is Ed25519-only and can't attach a look
   slot — use the native CLI):

   ```
   dreamball mint --out seed.ball --name "Star Tamagotchi" --type avatar
   dreamball grow seed.ball --key seed.ball.key \
     --stage dreamball --set-look look.json --out star-tamagotchi.ball
   dreamball verify star-tamagotchi.ball     # exit 0
   ```

The repo fixture (`static/characters/star-tamagotchi.ball`) uses a
**site-relative** asset URL (`/characters/star-tamagotchi.glb`) so the demo is
self-contained; a distributed character ball would carry an absolute URL.

## Where this is going

Today Star is *only* a glTF in a ball. Next she carries `act` / `memory` /
`emotional-register` slots and an AI persona prompt — and the **same**
`DreamBallViewer` renders the richer ball (private slots gated by the backend's
permission resolution). "All characters as DreamBalls" + a DreamBall editor are
the same path with authoring on top.
