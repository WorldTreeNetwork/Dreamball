# DreamBall Protocol

**Status:** Draft v0 — 2026-04-18
**File extension:** `.ball`
**Media type:** `application/ball+cbor` (binary), `application/ball+json` (export)
**Sister project:** [recrypt](../../recrypt/) — shares cryptographic methodology (see `recrypt/docs/wire-protocol.md`)
**Authoritative shape sources:** The canonical definition of every wire field — shapes, defaults, encoding rules, and ordering — is the **Rust types** carrying `serde` + `schemars` derives, per the [Rust-canonical ADR](decisions/2026-08-06-rust-canonical.md) (supersedes the 2026-06-25 Zig-canonical ADR, which superseded D-018). dCBOR semantics and envelope framing come from `dcbor` 0.25.2 / `bc-envelope` 0.43.0; we consume those crates rather than reimplementing them. JSON Schema (`schemas/*.json`), TypeScript types, Valibot schemas, and `cbor.ts` are **generated outputs** that flow downward; they are never hand-authored. *Transitional:* until epic `Dreamball-y4t` completes the port, the Zig types in `src/protocol*.zig` are still what the build compiles and are canonical in practice — edit them, but do not invest in the Zig codegen path. See §14 (Schema vendoring and pin format) and §15 (Wasm module signing and trust model) for the vendoring and trust contract.

---

## 1. Elevator pitch

A **DreamBall** is a self-contained, signed, evolvable container that bundles three axes of an "aspect":

| Axis       | What it holds                                                        |
| ---------- | -------------------------------------------------------------------- |
| **look**   | visual representation — URLs or embedded GLB/GLTF/splat/image assets |
| **feel**   | personality — tone, values, voice, affective profile                 |
| **act**    | executable layer — LLM model refs, system prompts, skills, scripts   |

DreamBalls are addressed by an **Ed25519 public key** (the container's identity key) and carry **dual signatures** (Ed25519 + ML-DSA-87) for classical + post-quantum integrity — the same hybrid model as recrypt.

The lifecycle has three named stages:

| Stage          | Meaning                                                              |
| -------------- | -------------------------------------------------------------------- |
| **DreamSeed**  | Early/nascent form. Minimal slots filled. Growing.                   |
| **DreamBall**  | Fruition form. Populated, signed, shareable. Can be added to over time. |
| **DragonBall** | Sealed form. Compressed and optionally encrypted. 3D assets may be attached/embedded for transport. |

### 1.1 What a DreamBall is **not**

- Not a fork/clone artifact. Development is **ongoing and additive** — more like a living document on a shared drive than a Git tree. Branching exists as _containment_ (a DreamBall referencing another), not as copy-and-diverge.
- Not a monolithic blob. DreamBalls nest; the structure is a **directed graph** of containment with fractal, self-similar internal organization. A DreamBall may contain other DreamBalls (by fingerprint reference or by embedded envelope).
- Not private by default. The protocol is **open** — the binary wire format has an exhaustive JSON export, and consumers that cannot parse CBOR can still read every field.

---

## 1.2 Terminology (our vocabulary vs. Gordian's)

This spec and the Memory Palace docs (`products/memory-palace/vision.md`, `products/memory-palace/prd.md`) use a plainer vocabulary than the upstream Gordian Envelopes / recrypt literature. The underlying CBOR bytes are identical; only the prose terms differ.

| Gordian / recrypt term | Our term | What it is |
|---|---|---|
| `envelope` | **node** | a DreamBall or any of its nested sub-structures |
| `subject` | **core** | the node-intrinsic data inside CBOR tag `#6.201`; what the node *is* |
| `assertion` | **attribute** | a labeled outbound connection from the core; what the node *says* |
| `predicate` | **label** | the attribute's key — the word that locates its meaning in the schema |
| `object` (terminal) | **value** | a terminal datum at the end of an attribute |
| `object` (envelope) | **connected node** | a nested node at the end of an attribute |
| `edge` (graph term) | **connection** | same shape; plainer word |

In one sentence: **a DreamBall is a node; its core defines what it is; its attributes are labeled connections to values or to other nodes.**

This vocabulary is used consistently throughout the Dreamball spec (PROTOCOL, VISION, ARCHITECTURE, and all product PRDs). The translation table exists for readers coming from the upstream Gordian / recrypt literature; our own docs no longer use the original terms except when citing upstream directly (e.g., the CBOR tag `#6.201` definition in §3).

## 1.3 Protocol epoch — `ball/1`

This document specifies wire epoch **`ball/1`**, the first depend-able
release of the format (package `0.1.0`).

- **Envelope type tags use the `ball.` prefix** — `ball.dreamball`,
  `ball.action`, `ball.mythos`, `ball.timeline`, and the rest. The tag
  string is part of the signed CBOR core and is the variant discriminator.
- **The sealed-wrapper binary magic is the 4 bytes `BALL`** (see §5 /
  the binary header below).
- **File extension is `.ball`** (compounds: `.ball.json` for canonical
  JSON, `.dragon.ball` for sealed DragonBalls).

**Clean break, no back-compat.** Pre-release builds used the legacy
codename prefix `jelly.` on type tags and the magic `JELY`. Those were
removed wholesale before the first client — a `ball/1` reader does **not**
accept `jelly.`-tagged envelopes or `JELY`-magic wrappers, and there is no
durable pre-release data to migrate. Any artifact carrying the old tags
predates `ball/1` and is out of spec.

## 2. Design conventions (inherited from recrypt)

The protocol reuses recrypt's wire conventions verbatim, except where noted:

1. **CBOR wire format, dCBOR-style determinism.** Map keys sorted canonically, smallest integer encoding, no floats in protocol fields, no indefinite-length items, tagged timestamps (`#6.1`), tagged envelopes (`#6.200`) and leaves (`#6.201`). See [recrypt wire-protocol §2.1](../../recrypt/docs/wire-protocol.md#21-dcbor).
2. **Envelope = core + attributes.** Load-bearing anchors (`type`, `format-version`, identity key, content hashes) go in the core. Mutable, elidable, descriptive metadata goes in attributes.
3. **Hybrid signatures, "all present must verify."** A signed DreamBall carries one or more `'signed'` attributes. A verifier MUST check every attached signature against the appropriate verification key (Ed25519 against `identity`; ML-DSA-87 against `identity-pq`) and reject on any failure, but there is no minimum count. Ed25519-only nodes are valid — useful for lower-stakes artifacts where classical-only is acceptable, or for ephemeral wrappers like `ball.relic` whose identity has no persisted PQ key. Nodes that include `identity-pq` in the core and an ML-DSA-87 `'signed'` attribute get full hybrid strength. This is a deliberate deviation from recrypt's stricter "both required" rule; recrypt is expected to relax to match.
4. **Salted attributes for low-entropy elidable fields** (timestamps, small enums, templated strings). See [recrypt wire-protocol §6](../../recrypt/docs/wire-protocol.md#6-salting-policy).
5. **Fingerprint = `Blake3(Ed25519 public key)`**, 32 bytes, base58 for display.
6. **`format-version` in every core.** Parsers reject unknown versions before reading further.
7. **Three interchange formats**, same bytes underneath:

| Format      | Extension    | Primary use                        |
| ----------- | ------------ | ---------------------------------- |
| CBOR        | `.ball`     | canonical binary; the authority    |
| JSON        | `.ball.json` | open-protocol export; readable in any stack |
| ASCII armor | `.ball.asc` | copy-paste / email / printed backups |

The CBOR bytes are authoritative. JSON and armor are wrappings of the same semantic content.

---

## 3. CBOR tags

| Tag      | Role                                   | Owner                |
| -------- | -------------------------------------- | -------------------- |
| `#6.200` | Envelope                               | Blockchain Commons   |
| `#6.201` | Leaf (dCBOR-encoded core)              | Blockchain Commons (upstream name: "subject") |
| `#6.1`   | Epoch time (RFC 8949)                  | IETF                 |
| `#6.???` | `ball.asset-ref` (content-addressed)  | TBD — private-use until registered |
| `#6.???` | `ball.dreamball-ref` (fingerprint)    | TBD — private-use until registered |

---

## 4. Domain types

### 4.1 `ball.dreamball`

The primary envelope — represents a single DreamBall at any stage of its lifecycle.

```
200(                                              ; envelope
  201(                                            ; leaf core
    {
      "type":           "ball.dreamball",
      "format-version": 1,
      "stage":          "dreamball",              ; "seed" | "dreamball" | "dragonball"
      "identity":       h'...32 bytes...',        ; Ed25519 public key (the DreamBall's ID)
      "genesis-hash":   h'...32 bytes...'         ; Blake3 of the initial seed payload; immutable
    }
  )
) [
           "name":          "Aspect of Curiosity",
  [salted] "created":       1(1712534400),
  [salted] "updated":       1(1713000000),
           "revision":      7,                     ; monotonic; bumped on every signed update
  [salted] "note":          "Draft personality for the hummingbird line",

  ; === look / feel / act slots ===
           "look":          <ball.look envelope>,
           "feel":          <ball.feel envelope>,
           "act":           <ball.act envelope>,

  ; === graph linkage (fractal containment) ===
           "contains":      h'...32 bytes...',     ; fingerprint of a nested DreamBall, repeatable
           "derived-from":  h'...32 bytes...',     ; optional origin-seed fingerprint, repeatable

           'signed':        Signature(ed25519, ...),
           'signed':        Signature(ml-dsa-87, ...)
]
```

**Core fields** (all load-bearing):

| Field            | Type     | Meaning                                          |
| ---------------- | -------- | ------------------------------------------------ |
| `type`           | string   | `"ball.dreamball"`                              |
| `format-version` | u32      | `1`                                              |
| `stage`          | string   | `"seed"` → `"dreamball"` → `"dragonball"`        |
| `identity`       | 32 bytes | Ed25519 public key; the container's identity    |
| `genesis-hash`   | 32 bytes | Blake3 of the canonical seed payload; immutable |

`identity` and `genesis-hash` together uniquely name the DreamBall across its entire lifetime. Updates bump `revision` and re-sign; they do not change these two fields.

**Attributes of note:**

- `look` / `feel` / `act` are **nested envelopes**, each defined below. They may be elided (replaced with their digest) when transporting a "pointer only" view of the DreamBall.
- `contains` carries the fingerprint of a nested DreamBall (graph connection). A DreamBall that aggregates others looks like a hub with many `contains` attributes.
- `derived-from` records inspirational ancestry without implying the current DreamBall is a mutable copy of the ancestor.
- `revision` is the only way to tell two envelopes with the same `identity` + `genesis-hash` apart. Verifiers picking "the current state" MUST pick the highest-revision envelope whose signatures verify.

### 4.2 `ball.look` (evolving)

**Status:** v1 is the simple asset-list shape below. v2 is actively being
designed around form-independence — see [`docs/VISION.md` §4](VISION.md#4-form-independence-in-the-look-slot-in-progress)
for the full rationale (shader-first layer, optional addressable base mesh,
graticule refs, resolution declarations). v2 will land as *additive*
attributes so v1 envelopes keep working.

```
200(
  201(
    {
      "type":           "ball.look",
      "format-version": 1
    }
  )
) [
  "asset":           <ball.asset envelope>,       ; repeatable — GLB, GLTF, splat, image, etc.
  "preview":         <ball.asset envelope>,       ; optional — low-res/thumb
  "background":      "color:#0b1020",              ; or asset ref
  [salted] 'note':   "hummingbird silhouette, neon sugar palette"

  ; Reserved for v2 (ignored by v1 parsers; planned shape sketched only):
  ; "shader":     <ball.shader envelope>          ; material/shader graph
  ; "base-mesh":  <ball.mesh envelope>            ; addressable topology
  ; "graticule":  <ball.graticule envelope>       ; space-distribution map
  ; "resolution": 8                                 ; declared quantisation level
]
```

The philosophical reason the v2 slots exist: mesh+texture assets bind the
visual identity to a specific topology, which breaks when the mesh is
substituted or re-topologised. Shaders, addressable base meshes, and
graticules each travel across topology changes, so a DreamBall's `look`
survives re-rigging, re-meshing, and medium changes (splat ↔ mesh ↔ SDF).

### 4.3 `ball.feel`

```
200(
  201(
    {
      "type":           "ball.feel",
      "format-version": 1
    }
  )
) [
  "personality":     "playful, quick, precise, occasionally snarky",
  "voice":           "young, curious, fast cadence",
  "values":          ["curiosity", "clarity", "kindness"],
  "tempo":           "fast",
  [salted] 'note':   "leans toward wit over warmth"
]
```

### 4.4 `ball.act`

The executable layer. References an LLM model, carries a system prompt, lists skills, scripts, and tool affordances. All script bodies are either **embedded** (short) or **referenced by `ball.asset`** (large).

```
200(
  201(
    {
      "type":           "ball.act",
      "format-version": 1
    }
  )
) [
  "model":           "claude-opus-4-7",
  "system-prompt":   "You are an aspect of curiosity...",
  "skill":           <ball.skill envelope>,        ; repeatable
  "script":          <ball.asset envelope>,        ; repeatable, when script body is large
  "tool":            "web.search",                  ; named tool affordance, repeatable
  [salted] 'note':   "avoid invoking shell tools without explicit user intent"
]
```

`ball.skill` is a small envelope (`name`, `trigger`, `body` or `asset-ref`, optional `requires` list). Spelled out in §4.7.

### 4.5 `ball.asset`

Any binary or URL-addressable payload (3D, image, script text, JSON blob).

```
200(
  201(
    {
      "type":           "ball.asset",
      "format-version": 1,
      "media-type":     "model/gltf-binary",        ; RFC 6838 media type
      "hash":           h'...32 bytes...'           ; Blake3 of the byte content
    }
  )
) [
  "url":             "https://cdn.example/dreams/abc.glb",   ; zero-or-more; resolvable locations
  "embedded":        h'...raw bytes...',                     ; optional — inline payload
  [salted] "size":   1048576,
  [salted] 'note':   "low-poly day variant"
]
```

An asset MUST have at least one of `url` or `embedded`. Consumers verify `hash` against whichever representation they fetch.

**Splat media types** (v2 addition). When `media-type` matches one of the values below, renderers route the asset to a gaussian-splat pipeline (PlayCanvas in the reference implementation) instead of the default mesh/texture path:

| Media type                                 | Format                                                       |
|--------------------------------------------|--------------------------------------------------------------|
| `application/vnd.playcanvas.gsplat+sog`    | SOG — SuperSplat Optimized Gaussian. **The ordered format** — sorted by spatial / morton index so the renderer can stream + draw progressively without a global sort. **Priority** for v2. |
| `model/gsplat-sog`                         | Neutral alias for SOG                                        |
| `model/gsplat-ply`                         | Compressed PLY (the community standard)                      |
| `application/vnd.playcanvas.gsplat+ply`    | PlayCanvas compressed PLY alias                              |
| `model/gsplat`                             | Plain PLY (non-compressed fallback)                          |

Splats are the topology-free rendering mode — no mesh, no UVs, just spatial distribution of gaussian primitives. This is why `docs/VISION.md §4.4.5` privileges them as the most honest expression of the omnispherical-graticule idea. The reference renderer exposes them via the `splat` lens in the Svelte library. Future splat formats (`.splat`, `.ksplat`, `.spz`) land behind the same media-type registry as they gain PlayCanvas or independent-handler support.

### 4.6 `ball.key-bundle`

Public-key bundle for a DreamBall's author/owner. Same shape as recrypt's `recrypt.public-key-bundle`, re-namespaced.

```
200(
  201(
    {
      "type":           "ball.key-bundle",
      "format-version": 1,
      "ed25519":        h'...32 bytes...',
      "ml-dsa-87":      h'...~2592 bytes...'
    }
  )
) [
           "fingerprint": h'...32 bytes...',         ; Blake3(ed25519)
  [salted] "created":     1(1712534400),
  [salted] 'note':        "minted on kite-flyer.local"
]
```

### 4.7 `ball.skill`

A single skill definition.

```
200(
  201(
    {
      "type":           "ball.skill",
      "format-version": 1,
      "name":           "answer-with-citation"
    }
  )
) [
  "trigger":         "when user asks a factual question",
  "body":            "...prompt text...",            ; small bodies inline
  "asset":           <ball.asset envelope>,         ; large bodies referenced
  "requires":        "web.search",                   ; tool dep, repeatable
  [salted] 'note':   "tested 2026-04"
]
```

---

## 5. Lifecycle: Seed → Ball → Dragon

### 5.1 DreamSeed

A DreamSeed is a `ball.dreamball` with:

- `stage = "seed"`,
- at least `identity` and `genesis-hash` populated,
- any subset of `look` / `feel` / `act` slots (often just one),
- dual signatures over whatever is present.

The seed's `genesis-hash` becomes the container's permanent origin anchor for the rest of its life.

### 5.2 DreamBall (fruiting/ongoing)

Promotion is a **re-sign**, not a copy. Producers:

1. Add/update attributes on the same `identity`/`genesis-hash` core.
2. Bump `revision`.
3. Update `updated` (salted).
4. Re-sign (Ed25519 + ML-DSA-87).

Consumers pick the highest-revision envelope that verifies. Older revisions are historical, not garbage — they may be retained for provenance.

**Containment, not forking.** To "remix" a DreamBall, create a _new_ DreamBall (new `identity`) whose `derived-from` attribute points to the source's fingerprint. The source is untouched; the new one has its own lifecycle.

### 5.3 DragonBall (sealed)

A DragonBall is a DreamBall that has been **compressed and optionally encrypted** for transport.

```
┌──────────────────────────────────────────────────────────────┐
│ BALL magic (4B "BALL") | version (1B) | flags (1B)         │
│ seal-type (1B) | reserved (1B)                              │
│ envelope-length (u32 little-endian)                          │
│ envelope-bytes: zstd( dCBOR( ball.dreamball envelope ) )    │
│ attachment-count (u16 little-endian)                         │
│ [ attachment-length (u32) | attachment-bytes ] * count       │
└──────────────────────────────────────────────────────────────┘
```

- **Magic:** ASCII `"BALL"` (0x42 0x41 0x4C 0x4C).
- **Version byte:** `1`.
- **Flags byte (bitfield):**

  | Bit | Meaning                                     |
  | --- | ------------------------------------------- |
  | 0   | `envelope` is zstd-compressed               |
  | 1   | `envelope` is encrypted (via recrypt KEM)   |
  | 2   | One or more `attachment` slots are encrypted |
  | 3–7 | reserved                                    |

- **seal-type:**

  | Value | Meaning                                                    |
  | ----- | ---------------------------------------------------------- |
  | `0`   | plain (CBOR envelope, possibly compressed)                 |
  | `1`   | recrypt-wrapped (bytes decode as a `recrypt.encrypted-file` envelope wrapping the DreamBall CBOR) |

- **Attachments:** optional raw bytes for large assets (GLB/GLTF/splats) whose hashes are referenced from `ball.asset` envelopes inside the DreamBall. Attachments let a sealed DreamBall travel with its heavy visuals rather than depending on external URLs.

Unsealing is the reverse: verify magic → check version → decompress → (optional) recrypt-decrypt → parse envelope → verify signatures → resolve attachment hashes.

### 5.4 Stage transitions

| From        | To           | What changes                                                 |
| ----------- | ------------ | ------------------------------------------------------------ |
| seed        | dreamball    | `stage` flips; `revision++`; usually more slots filled; re-sign |
| dreamball   | dragonball   | Serialize → (zstd) → (encrypt) → wrap in sealed-file header; inner envelope unchanged |
| dragonball  | dreamball    | Unseal as above; inner envelope identical to what was sealed |

A DragonBall's inner envelope still says `stage = "dreamball"` — the dragon form is purely a transport wrapper. The `stage = "dragonball"` value exists for envelopes that are _born_ sealed (e.g., a sealed-only distribution artifact that never existed in open form).

---

## 6. Graph model

DreamBalls form a directed graph:

- **`contains`** connections: this DreamBall embeds/depends-on that one. Containment is transitive — a DreamBall containing a DreamBall that contains another effectively contains the grandchild. Cycles are forbidden.
- **`derived-from`** connections: this DreamBall was inspired by that one. Not transitive. No effect on signature validation.

The structure is **fractal** in the sense that any sub-DreamBall has the same shape as the whole — look/feel/act slots, signatures, optional further containment. A renderer written for the top-level DreamBall works unchanged on any descendant.

The structure is **symmetric** in that all containment connections are the same kind — there is no distinction between "parent" and "primary" children. A hub DreamBall with ten `contains` attributes treats each child equally.

---

## 7. JSON export

The JSON export is a **lossless rendering** of the CBOR envelope tree. Every CBOR field becomes a JSON field with the same name. Byte strings become base58-encoded strings prefixed with `"b58:"`. CBOR tag 1 timestamps become RFC 3339 strings.

```json
{
  "type": "ball.dreamball",
  "format-version": 1,
  "stage": "dreamball",
  "identity": "b58:3xqJ...",
  "genesis-hash": "b58:5tYn...",
  "revision": 7,
  "name": "Aspect of Curiosity",
  "created": "2024-04-08T00:00:00Z",
  "look":  { "type": "ball.look",  "format-version": 1, "asset": [...] },
  "feel":  { "type": "ball.feel",  "format-version": 1, "personality": "..." },
  "act":   { "type": "ball.act",   "format-version": 1, "model": "claude-opus-4-7", "system-prompt": "..." },
  "contains": ["b58:..."],
  "signatures": [
    { "alg": "ed25519",   "value": "b58:..." },
    { "alg": "ml-dsa-87", "value": "b58:..." }
  ]
}
```

JSON import/export MUST round-trip to identical CBOR bytes when the JSON was produced by the canonical exporter. Hand-authored JSON going to CBOR is allowed but the reverse ("was this edited?") is out of scope.

---

## 8. Signature model

Follows recrypt's shape (see [recrypt wire-protocol §4](../../recrypt/docs/wire-protocol.md#4-signature-model)) with the policy relaxation described in §2.3:

1. Producer constructs the node with core + all non-signature attributes. A hybrid producer also sets `identity-pq` in the core (2592-byte ML-DSA-87 public key) and bumps `format-version` to the appropriate v3 line.
2. Producer signs the canonical unsigned bytes with every key they hold and appends one `'signed'` attribute per algorithm. An Ed25519-only producer appends one attribute; a hybrid producer appends two.
3. Verifier iterates every `'signed'` attribute, identifies the algorithm (`ed25519` or `ml-dsa-87`), looks up the verification key (`identity` for Ed25519, `identity-pq` for ML-DSA-87), and checks the signature against the stripped-canonical unsigned bytes. Reject on any failure. An ML-DSA-87 attribute on a node whose core lacks `identity-pq` is a verification error — there is no key to check against.

Signatures cover the core digest plus every non-elided attribute's digest at signing time. Eliding a salted attribute after signing is valid.

**No minimum signature count.** A node with zero `'signed'` attributes is unsigned and MUST be treated as untrusted input. A node with one valid Ed25519 signature is a valid Ed25519-only node. A node with both a valid Ed25519 and a valid ML-DSA-87 signature is a valid hybrid node. The "hybrid strength" claim in application-layer UX reflects whether `identity-pq` + an ML-DSA-87 signature are both present.

---

## 9. Versioning

Each envelope carries `format-version` in its core. Additive changes (new attribute labels) do not bump the version. New core fields or removed core fields do. See [recrypt wire-protocol §10](../../recrypt/docs/wire-protocol.md#10-versioning-and-evolution).

Current version floor: `1` for every domain type.

---

## 10. Interop with recrypt

- **Key bundles are compatible.** A `ball.key-bundle` and a `recrypt.public-key-bundle` use identical key encoding. Tooling that already has a recrypt identity can sign DreamBalls with the same keypair.
- **Sealing uses recrypt.** DragonBalls with `seal-type = 1` are plain recrypt encrypted-file envelopes whose plaintext payload is the DreamBall envelope bytes. Recrypt's proxy-recryption story applies unchanged — a sealed DreamBall can be shared with new recipients by asking recrypt's recryption proxy to rewrap the KEM.
- **Storage is compatible.** Content-addressed storage (Blake3 of the envelope bytes) lets DreamBalls live in recrypt's blob store with no protocol collision.

---

## 11. Open questions

1. **CBOR tag registration.** `ball.asset-ref` and `ball.dreamball-ref` need real tag numbers. Coordinate with recrypt's private-use tag registration.
2. **Attachment deduplication.** When a nested DreamBall and its parent both reference the same asset, DragonBall format currently stores the attachment twice. Consider a per-file asset table indexed by Blake3.
3. **Graph cycle detection.** Producers must not create containment cycles; do we enforce at encode time, verify time, or both?
4. **Large system prompts.** Should the wire format cap inline string lengths and force spill to `ball.asset` past some threshold (e.g., 64 KiB) for parser predictability?
5. **"Born-dragon" envelopes.** Is there a use for a DreamBall that never existed in open form? If so, `stage = "dragonball"` inside the inner envelope carries meaning; if not, drop that value and always use `"dreamball"` inside a sealed wrapper.

---

## 12. Protocol v2 — typed DreamBalls (reference-type wire extensions)

> **Moved — reference type, not substrate.** The six typed DreamBalls and
> their slots (`ball.memory`, `ball.knowledge-graph`,
> `ball.emotional-register`, `ball.interaction-set`, `ball.guild-policy`,
> `ball.secret-ref`, `ball.transmission`, `ball.omnispherical-grid`) are
> wire extensions authored on the substrate, exactly as a third-party type
> would be. They now live — verbatim, with their original **§12.x** section
> numbers preserved — in
> [`products/dreamball-v2/protocol.md`](products/dreamball-v2/protocol.md).
> The *why* is in
> [`products/dreamball-v2/vision.md`](products/dreamball-v2/vision.md). Any
> reference to "§12.x" resolves there.

---

## 13. Memory Palace composition — auxiliary envelopes (reference-type wire extensions)

> **Moved — reference type, not substrate.** The Memory Palace archiform's
> auxiliary envelopes (`ball.layout`, `ball.timeline` + `ball.action`,
> `ball.aqueduct`, `ball.element-tag`, `ball.trust-observation`,
> `ball.inscription`, `ball.mythos`, `ball.archiform`, and the
> `field-kind` / `archiform-fp` attributes) are a wire extension authored on
> the substrate. They now live — verbatim, with their original **§13.x**
> section numbers preserved — in
> [`products/memory-palace/protocol.md`](products/memory-palace/protocol.md).
> The *why* is in
> [`products/memory-palace/vision.md`](products/memory-palace/vision.md). Any
> reference to "§13.x" (including `src/golden.zig`'s golden-bytes fixtures at
> §13.11) resolves there.

## 14. Schema vendoring and pin format

*Implements D-029 (aspects.sh vendor-first contract + pin file format).*

> **Status change (2026-08-06 — supersedes the 2026-06-25 ADR, which
> superseded D-018):** Per the
> [Rust-canonical ADR](decisions/2026-08-06-rust-canonical.md),
> `schemas/*.json` are **generated artifacts** — emitted from the canonical
> Rust types via `schemars` — not canonical vendored sources. The §14.4
> update lifecycle and the `schemas:refresh` tool below describe the
> pre-ADR (D-018) workflow and are retained for historical context only.
> The correct update path is: edit the canonical types → regenerate →
> commit the regenerated outputs together with the updated pin files.
> *Transitionally* (while epic `Dreamball-y4t` runs) that is still
> `src/protocol*.zig` → `zig build schemagen`.

### 14.1 Location convention

Archiform JSON Schema documents live at:

```
schemas/<archiform>-<version>.json
```

Examples:

- `schemas/root-2.0.0.json` — root DreamBall wire types
- `schemas/memory-palace-0.1.0.json` — Memory Palace archiform

These files are **vendored locally** — no network access at build
time. Schema updates are explicit: fetch the new version, update the
pin (see §14.2), regenerate, commit.

### 14.2 Pin file format

Every vendored schema has a corresponding pin file at:

```
schemas/.pins/<archiform>-<version>.fp
```

The pin file is plain text: a single line containing the hex-encoded
`blake3` digest of the canonical schema file bytes. No trailing
newline. No other content.

Example:

```
a3f2c1d4e5b6a7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2
```

The build-time verification step (`bun run codegen`, which calls
`bun run schemas:verify`) recomputes the blake3 of each vendored
schema and fails if any digest does not match its pin file. This is
the only place pin verification runs — there is no network round-trip.

### 14.3 Tooling

| Script | Purpose |
|---|---|
| `bun run schemas:pin <path>` | Compute and write the `.fp` pin for a single schema file |
| `bun run schemas:verify` | Verify all vendored schemas against their pin files; called automatically by `bun run codegen` |
| `bun run schemas:refresh` | (Pre-ADR / historical) Fetch the latest schema version from aspects.sh, verify the digest matches the declared pin, and swap in if matched. Superseded by the canonical-types generation path (see §14 supersession notice) |

`schemas:refresh` is **not** a CI gate. It is an optional maintenance
path for updating vendored schemas. The CI gate is `schemas:verify`
only, which runs entirely against local files.

### 14.4 Update lifecycle (Pre-ADR / historical)

> This lifecycle treats `schemas/*.json` as authoritative inputs — the
> retired D-018 contract. It is no longer operative. The current update
> path is the one in the §14 supersession notice above: edit the
> canonical types → regenerate → commit regenerated outputs + pins. The
> steps below are retained because the byte-equivalence gate still
> compares against the vendored fixtures until the Rust `schemars` path
> produces them. (`Dreamball-m97.2`, the Zig comptime generator, is
> **dissolved** by the [Rust-canonical ADR](decisions/2026-08-06-rust-canonical.md),
> not deferred.)

1. Download the new schema version from aspects.sh (or author it locally).
2. Run `bun run schemas:pin schemas/<archiform>-<version>.json` to
   write the new `.fp` file.
3. Run `bun run codegen` (which runs `schemas:verify` then
   `zig build schemagen`) to regenerate all derived outputs.
4. Commit the schema, the pin file, and the regenerated outputs together.

Updating a schema without updating its pin causes `bun run codegen` to
fail with a digest-mismatch error — this is the intended guard.

---

## 15. Wasm module signing and trust model

*Implements D-031 (signed schema body + content-addressed wasm).*

### 15.1 Trust chain

The trust model is **transitive authentication via signed schema body**:

1. The schema-aspect body (the JSON Schema document) is signed by its
   publisher via aspects.sh's existing aspect-signing mechanism.
2. The schema body contains the action manifest, which includes
   `implementation.wasm` fingerprints for each action.
3. Wasm modules are content-addressed by `blake3(wasm_bytes)`.
4. Before instantiation, the host verifies that
   `blake3(fetched_wasm_bytes)` matches the fp declared in the action
   manifest (SEC4 — verify-before-instantiate).

Trust chain in full: **publisher signs schema body → schema body
declares wasm fps → host verifies wasm bytes against fps before
instantiation.** No wasm module runs unless its bytes match the fp
the schema author declared.

### 15.2 blake3 verify-before-instantiate (SEC4)

Every wasm action module is verified by blake3 content hash before
the host instantiates it. Verification failure is a hard error — the
action is refused, the error is logged, and no fallback execution
occurs.

This is the only verification step needed at the module level for
sprint-002: because the schema is signed, trusting the schema means
trusting the fp list, which means trusting any wasm bytes that match.

### 15.3 Wasm-and-schema lifecycle coupling

Any change to a wasm action module's bytes — including bug fixes —
changes its `blake3` hash, which means the old fp in the schema no
longer matches. **Every wasm bug fix requires a schema reissue:**

1. Fix the wasm source.
2. Rebuild the wasm module.
3. Compute the new blake3 fp.
4. Update the action manifest entry in the schema with the new fp.
5. Reissue the schema (new version, new publisher signature).
6. Update the vendored copy and pin in the Dreamball repo.

This coupling is **intentional**: it forces archiform authors to treat
"schema + actions" as one versioned unit. The schema is the unit of
trust; the wasm is its implementation. They evolve together.

### 15.4 Per-module signature (deferred)

Giving each wasm module its own detached signature (in addition to the
fp-inside-schema trust chain) is deferred to sprint-003+. The
additional ceremony does not improve security meaningfully when the
schema is already signed — a per-module signature would only say
"the same publisher who signed the schema also signed this wasm," which
the fp chain already guarantees. The per-module option remains open for
cases where wasm modules need to carry independent provenance (e.g.,
third-party contributed modules not authored by the schema publisher).

---

## 16. Action manifest

*Implements D-019 (Action Manifest as universal action contract) and
D-035 (closed `attributes` + `effects.kind` enumeration).*

An archiform declares its operations in the JSON Schema under an
`"actions"` key. The action manifest is the universal contract; CLI,
REST, MCP, in-renderer, and programmatic clients are mechanical
projections of it. See
[`docs/decisions/2026-04-25-action-manifest.md`](decisions/2026-04-25-action-manifest.md)
for the full rationale.

### 16.1 Action declaration shape

```json
"actions": {
  "mint": {
    "summary":     "Create a new memory palace",
    "inputs":      { "type": "object", "properties": { "name": {}, "mythosTemplate": {} } },
    "outputs":     { "type": "object", "properties": { "palaceFp": {} } },
    "effects":     [{ "kind": "ActionEnvelope", "actionKind": "palace.mint" }],
    "idempotency": "creates",
    "streaming":   false,
    "attributes": {
      "destructive":           false,
      "requiresConfirmation":  false,
      "confirmationMessage":   "",
      "agentVisible":          true
    },
    "implementation": { "wasm": "actions/mint.wasm", "export": "mint" }
  }
}
```

### 16.2 Closed `attributes` set (D-035)

The `attributes` object for sprint-002 accepts exactly **four keys**:

| Key | Type | Meaning |
|---|---|---|
| `destructive` | bool | Action cannot be undone; projections warn the caller |
| `requiresConfirmation` | bool | Projection layer MUST obtain explicit confirmation before calling |
| `confirmationMessage` | string | Human-readable text shown in the confirmation dialog |
| `agentVisible` | bool | Whether agent projections (MCP) expose this action |

The validator **rejects** any key not in this list. The `x-` prefix
convention is **reserved** for sprint-003+ experimental attributes; the
sprint-002 validator also rejects `x-*` keys to prevent accidental drift.

### 16.3 Closed `effects.kind` enum (D-035)

Each entry in the `effects` array carries a `kind` field. Exactly
**three values** are valid for sprint-002:

| Value | Meaning |
|---|---|
| `ActionEnvelope` | The action emits a signed `ball.action` envelope appended to the palace timeline |
| `Read` | The action is read-only; it queries but does not mutate state |
| `Derived` | The action computes a derived value (e.g., aggregation, phase calculation) without emitting an envelope |

The validator rejects any other value.

### 16.4 Closed `idempotency` enum (D-035)

Three values inherited from sprint-001:

| Value | Meaning |
|---|---|
| `creates` | Each invocation produces a new resource; retrying produces a duplicate unless the caller checks |
| `updates` | Modifies existing state; not safe to retry without checking current state |
| `idempotent` | Safe to retry; the same inputs always produce the same observable outcome |

The validator rejects any other value.

### 16.5 Pure-transaction discipline

**Actions are pure transactions; never interactive.** No TTY prompts
inside an action body. If confirmation is needed, declare it via
`requiresConfirmation: true` and `confirmationMessage` — the
projection layer renders the confirmation in its idiom (TTY prompt,
dialog box, MCP elicitation). This makes actions fully agent-callable.

### 16.6 Sprint-003+ extension path

- Opening `x-*` attribute keys is a new ADR.
- Adding new `attributes` keys or `effects.kind` values is a new ADR.
- Per D-025 (forward-declare consumer seam contracts), no extension
  to this closed set occurs without an architecture decision.

### 16.7 `ball.action` wire format (v4 only; v3 removed from the core)

*Implements D-037. The wire shape frozen here is the canonical basis for C1's
golden vectors — downstream encoding work locks against these bytes.*

**format_version 4 is the only `ball.action` format the core substrate
supports.** `format-version` is the discriminant — decoders MUST branch on it
before interpreting the core map, and MUST reject any value other than `4`
with a clear decode error (`DecodeError.UnsupportedFormatVersion` in the Zig
implementation) rather than attempting to interpret the rest of the core map.

**v4 core map** (open type — 6 or 7 keys, dCBOR length-first + lex order):

| dCBOR key | Type | Required | Notes |
|---|---|---|---|
| `"hlc"` | array [uint64, uint64] | yes | see §17 |
| `"body"` | bytes | no | omitted from the map when there is no payload |
| `"kind"` | text | yes | open kind string; see §18 |
| `"type"` | text | yes | `"ball.action"` |
| `"actor"` | bytes (32) | yes | Ed25519 public-key fingerprint |
| `"parent-hashes"` | array of bytes(32) | yes | DAG parent hash list |
| `"format-version"` | uint | yes | `4` |

**Key ordering.** dCBOR sorts map keys length-first, lexicographically within
equal length. The 7-key ordering (with `body` present) is: `"hlc"` (3) →
`"body"`, `"kind"`, `"type"` (all length 4, alphabetical) → `"actor"` (5) →
`"parent-hashes"` (13) → `"format-version"` (14). When `body` is absent the
map has 6 keys; `"body"` is simply omitted.

**`body` encoding.** When present, `body` is a CBOR byte string (major type 2)
whose content bytes are the consumer's canonical CBOR payload. The encoder
calls `assertCanonical` on the body bytes before embedding. The decoder returns
body as raw bytes for the consumer to parse. The body is opaque to the
protocol — internal structure is the consumer's responsibility (D-043).

**Covered by `content_hash`.** `content_hash = Blake3(canonical_envelope_bytes)`.
`hlc`, `kind`, and `body` are all part of the canonical envelope bytes; changing
any of them changes the hash and invalidates the signature. No domain-separation
prefix is needed (D-043).

**History — v3 removed, 2026-08-07 (Dreamball-y4t.15).** Through sprint-003
the core carried BOTH formats: `format-version` 3, a CLOSED 5-key palace
profile (`"type"`, `"actor"`, `"action-kind"` — one of 9 fixed values, no
payload, no logical clock — `"parent-hashes"`, `"format-version"`); and
`format-version` 4, the OPEN type system above. D-037 introduced v4 as v3's
successor but the core kept decoding both, and this section used to say "v3
goldens are a regression gate... a change that alters a v3 golden is a bug."

That commitment is retired. v3 was always the Memory Palace's closed profile,
never a general substrate concern, and the Memory Palace is being extracted to
its own repository (epic Dreamball-etk) — so v3 support belongs there, in
whatever form the palace needs, not in the shared protocol/envelope core. The
core substrate (`src/protocol_v2.zig`, `src/envelope_v2.zig`) dropped
`ActionKind` and the v3 encoder/decoder entirely; a v3 envelope now fails
decode cleanly instead of being silently accepted.

**This is a breaking wire-format change** — a `format-version: 3` envelope
that used to decode now does not — and it is acceptable specifically because,
per the project owner (2026-08-05/2026-08-07): there are no consumers of this
application, and no persisted data, so nothing that already exists needs to
keep decoding. The three v3 `ball.action` golden vectors and the two
palace-profile `ball.timeline` goldens are preserved byte-for-byte in
[`fixtures/goldens/palace-v3-manifest.json`](../fixtures/goldens/palace-v3-manifest.json)
— NOT a core regression gate, but a handoff artifact for whoever continues
the palace's v3 support after the Dreamball-etk extraction. Format_version 4
golden vectors (introduced separately in C1) remain in
`fixtures/goldens/manifest.json` and remain the core's regression gate.

**Follow-up — the rest of the palace/archiform partition, 2026-08-07
(Dreamball-y4t.11).** This section only ever addressed the v3-format
fixtures. The remaining v2-format-version fixtures that were still sitting
undifferentiated in `manifest.json` — the Memory Palace domain types
(`palace_field`, `aqueduct`, `element_tag`, `inscription`, the three
`mythos_*` vectors) and the archiform types (`archiform`, `object3d`) — have
now been partitioned out too, by the same non-gating logic, into
[`fixtures/goldens/palace-manifest.json`](../fixtures/goldens/palace-manifest.json)
and
[`fixtures/goldens/archiform-manifest.json`](../fixtures/goldens/archiform-manifest.json)
respectively (per the Dreamball-jie boundary analysis). Two fixtures —
`layout` and `trust_observation` — were left CONTESTED by that analysis
(candidate destinations argued but not adopted by a boundary ADR) and were
moved to their own
[`fixtures/goldens/contested-manifest.json`](../fixtures/goldens/contested-manifest.json)
rather than guessed into either bucket. `manifest.json` now contains only
`zero_seed`, `memory_connection`, `action_v4_unsigned`, and
`action_v4_signed` — the four fixtures that are actually substrate-owned —
and this is the file the Rust core's port should treat as its regression
gate.

Two things have NOT (yet) followed the core substrate off of v3, and are
called out here rather than silently left inconsistent:
- The palace CLI verbs (`src/cli/internal/{mint,add_room,move,rename_mythos,inscribe}.zig`)
  still author `format-version: 3` envelopes, via a verbatim copy of the old
  core encoder kept in `src/cli/internal/palace_action_v3.zig` — no v4
  CLI-authoring migration has landed for these verbs. Since the CLI only
  encodes (it does not call `decodeAction` on what it mints), this does not
  conflict with the core's decode-side rejection, but it does mean the CLI
  still ships wire bytes the core's own decoder now refuses.
- The generated TypeScript CBOR codec (`tools/schema-gen/gen_cbor.zig` →
  `cbor.ts`) still implements v3 decode as a backward-compat branch, since the
  browser/bridge layer needs to read the v3 envelopes the CLI is still
  minting. It was deliberately left unchanged by this decision rather than
  regenerated to match the Zig core.

Both are consequences of the Memory Palace extraction (Dreamball-etk) not
having happened yet; resolving them is that epic's work, not this section's.

The open type system's full context — motivation, PRD, and sprint plan — is in
[`prd-open-type-system-mvp.md`](prd-open-type-system-mvp.md) and
[`sprints/003-open-type-system/`](sprints/003-open-type-system/). This section
is the prescriptive wire spec; those documents are the rationale.

---

## 17. HLC Specification

*Implements D-039. Resolves bead Dreamball-fch.*

The **Hybrid Logical Clock (HLC)** provides causal ordering for `ball.action`
v4 envelopes authored by independent nodes without a shared global clock. The
HLC is **mandatory** in every format_version 4 `ball.action`; a v4 envelope
without an `hlc` field is a decode error.

### 17.1 Wire shape

```
[l, c]   ; CBOR array (major type 4, definite length 2)
         ; index 0: l — major type 0, uint64, dCBOR shortest encoding
         ; index 1: c — major type 0, uint64, dCBOR shortest encoding
         ; no CBOR tag
```

| Field | Index | Zig type | Meaning |
|---|---|---|---|
| `l` | 0 | `u64` | Physical component — millisecond wall-clock timestamp, advanced monotonically |
| `c` | 1 | `u64` | Counter — disambiguates concurrent events from independent authors with the same `l` |

Wire key in the core map: `"hlc"` (3-byte CBOR text string). No CBOR tag.
Zig struct: `hlc: [2]u64` where `hlc[0] = l` and `hlc[1] = c`.
TypeScript type: `[number, number]` — both values fit within
`Number.MAX_SAFE_INTEGER` for any practical timestamp.

### 17.2 Advance algorithm

When issuing a new event, the author advances the HLC as follows:

```
new_l = max(local_wall_ms, last_l) + 1
new_c = 0   ; l always strictly advances; counter resets
```

`local_wall_ms` is the current millisecond-resolution wall-clock
(`Date.now()` in JS; `std.time.milliTimestamp()` in Zig). `last_l` is the `l`
value of the most recently issued or observed event, or `0` on first use.

The `+1` guarantees `new_l > max(local_wall_ms, last_l)`, so sequential events
from the same author are always strictly ordered by `l` alone. The `c` counter
differentiates events from independent authors that independently arrived at the
same `l` value.

### 17.3 Total order

```
(l1, c1) < (l2, c2)   iff   l1 < l2   OR   (l1 == l2 AND c1 < c2)
```

Events where `l1 == l2` and `c1 == c2` are **concurrent**. The protocol
imposes no merge rule for concurrent events — the consumer's domain logic
determines the outcome (VISION.md §17, guardrail 1).

### 17.4 Coverage by `content_hash`

The HLC is part of the core map and therefore covered by
`content_hash = Blake3(canonical_envelope_bytes)`. Changing either `l` or `c`
changes the hash and invalidates the signature.

---

## 18. Kind Namespace Convention

*Implements D-038.*

The `kind` field in `ball.action` v4 is an **open UTF-8 string**. Any valid,
non-empty UTF-8 string is accepted at the wire level.

### 18.1 Wire type

```
kind = text   ; CBOR major type 3, any valid non-empty UTF-8 string
```

Wire key in the core map: `"kind"` (4-byte CBOR text). Zig type: `kind: []const u8`.
**Zero-length `kind` is a decode error** — a v4 envelope with `kind = ""`
is rejected.

### 18.2 Recommended convention

```
<namespace>.<noun>.<verb>
```

| Component | Role | Example values |
|---|---|---|
| `<namespace>` | Author or product identity; lowercase, no dots | `worldtree`, `palace`, `myapp` |
| `<noun>` | Entity or resource being acted upon | `kanban-card`, `room`, `document` |
| `<verb>` | The operation | `move`, `add`, `archive` |

**Full examples:** `worldtree.kanban-card.move`, `palace.room-added`,
`palace.minted`.

The convention is **recommended, not enforced** at the wire level. A decoder
MUST accept any non-empty UTF-8 kind string, including un-namespaced ones.
Consumers who follow the convention gain collision-safe dispatch keys;
those who do not risk kind-string collisions with envelopes from other producers.

### 18.3 Palace kinds in v4

The 9 former v3 palace action kinds and their recommended dot-convention
equivalents for format_version 4 envelopes. The closed `ActionKind` enum that
used to canonicalize these values lived in `src/protocol_v2.zig`; it was
deleted along with the rest of v3 core support (§16.7, Dreamball-y4t.15,
2026-08-07). The wire strings below are historical/recommended values only —
the palace CLI's own copy of them now lives in
`src/cli/internal/palace_action_v3.zig` (v3 authoring, until the Memory
Palace extraction, Dreamball-etk):

| Former v3 `action-kind` (closed enum, now removed) | Recommended v4 `kind` |
|---|---|
| `"palace-minted"` | `"palace.minted"` |
| `"room-added"` | `"palace.room-added"` |
| `"avatar-inscribed"` | `"palace.avatar-inscribed"` |
| `"aqueduct-created"` | `"palace.aqueduct-created"` |
| `"move"` | `"palace.move"` |
| `"true-naming"` | `"palace.true-naming"` |
| `"inscription-updated"` | `"palace.inscription-updated"` |
| `"inscription-orphaned"` | `"palace.inscription-orphaned"` |
| `"inscription-pending-embedding"` | `"palace.inscription-pending-embedding"` |

Format_version 4 palace envelopes SHOULD use the `"palace.*"` dot-prefix
forms above. Any non-empty string is accepted at the wire level in v4 — the
convention is a recommendation, not a gate. (Format_version 3 envelopes are
no longer decodable by the core substrate at all — see §16.7 — so there is no
"format_version 3 palace envelope" to route through this convention any
more; the row above documents the mapping historically, for whoever
continues v3 authoring in the extracted Memory Palace repo.)

### 18.4 Renderer dispatch

Renderer dispatch (FR12, planned growth feature) uses `kind` as the lookup
key. The dot namespace convention ensures that `"worldtree.kanban-card"` and
`"palace.room"` route to separate handlers without a central registry — no
coordination required between producers.
