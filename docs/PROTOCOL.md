# DreamBall Protocol

**Status:** Draft v0 — 2026-04-18
**File extension:** `.ball`
**Media type:** `application/ball+cbor` (binary), `application/ball+json` (export)
**Sister project:** [recrypt](../../recrypt/) — shares cryptographic methodology (see `recrypt/docs/wire-protocol.md`)
**Authoritative shape sources:** [`schemas/root-2.0.0.json`](../schemas/root-2.0.0.json) (root wire types) and [`schemas/memory-palace-0.1.0.json`](../schemas/memory-palace-0.1.0.json) (Memory Palace archiform) — both JSON Schema draft 2020-12; pinned at [`schemas/.pins/root-2.0.0.fp`](../schemas/.pins/root-2.0.0.fp) and [`schemas/.pins/memory-palace-0.1.0.fp`](../schemas/.pins/memory-palace-0.1.0.fp) respectively (D-018 + D-029). No hand-written schemas exist anywhere; JSON Schema is vendored locally and all generators consume it. See §14 (Schema vendoring and pin format) and §15 (Wasm module signing and trust model) for the full vendoring and trust contract.

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

This spec and the Memory Palace docs (VISION §15, `products/memory-palace/prd.md`) use a plainer vocabulary than the upstream Gordian Envelopes / recrypt literature. The underlying CBOR bytes are identical; only the prose terms differ.

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

## 12. Protocol v2 — typed DreamBalls, memory, guilds, transmission

**Version:** `format-version: 2` on every new envelope type introduced here. v1 envelopes continue to round-trip through v2 parsers unchanged.

**Rationale:** v1 shipped one `ball.dreamball` envelope treated as a monolith. v2 recognises that DreamBalls are **MTG-style categories with different effects** (creature ≠ artifact ≠ land); each type demands different slot surfaces and renderer behaviour. v2 also gives DreamBalls the slots they need to be agents (memory, knowledge, emotion, skills) and the keyspace-style grouping to transmit skills across bodies. See [`docs/VISION.md` §10](VISION.md#10-the-six-type-taxonomy-mtg-style) for the why.

### 12.1 The six typed DreamBalls

Every v2 DreamBall core carries a `type` field selected from:

| Core `type` | Shape | Primary lens(es) |
|---|---|---|
| `ball.dreamball.avatar` | look-heavy; minimal act | avatar, thumbnail |
| `ball.dreamball.agent`  | act-heavy; model + memory + KG + emotion + skills | knowledge-graph, emotional-state |
| `ball.dreamball.tool`   | single skill payload, transferable | thumbnail, flat |
| `ball.dreamball.relic`  | sealed inner envelope; reveals on unlock | omnispherical, flat |
| `ball.dreamball.field`  | omnispherical-grid parameters; ambient layer | omnispherical |
| `ball.dreamball.guild`  | members list + keyspace ref + per-slot policy | flat, knowledge-graph |

The v1 bare `ball.dreamball` value remains legal (untyped). Producers SHOULD migrate to one of the six typed values; consumers that see `ball.dreamball` with no subtype MUST treat it as the Avatar variant (safest default).

All six share the v1 core fields (`format-version`, `stage`, `identity`, `genesis-hash`, `revision`) and add **zero load-bearing core fields** — the difference between types lives in which *attributes* the consumer expects to find.

#### 12.1.1 `ball.dreamball.avatar`

Populated attribute surface: `look`, `feel` (optional), `name`, `note`, optional `wearer` (a fingerprint indicating the current wearer — informational; not a security claim).

Example:

```
200(
  201({ "type": "ball.dreamball.avatar", "format-version": 2,
        "identity": h'…32…', "genesis-hash": h'…32…', "revision": 3,
        "stage": "dreamball" })
) [
  "name":   "Hummingbird Hat",
  "look":   <ball.look envelope>,
  "feel":   <ball.feel envelope>,
  [salted] "wearer": h'…32…',
  'signed': ..., 'signed': ...
]
```

#### 12.1.2 `ball.dreamball.agent`

Full act surface plus the four new v2 agent attributes:

- `act` — v1-compatible skill + tool + model + prompt slot
- `memory` — `ball.memory` envelope (§12.3)
- `knowledge-graph` — `ball.knowledge-graph` envelope (§12.4)
- `emotional-register` — `ball.emotional-register` envelope (§12.5)
- `interaction-set` — `ball.interaction-set` envelope (§12.6), repeatable
- `personality-master-prompt` — text (the top-level system prompt; distinct from per-skill prompts)
- `secret` — `ball.secret-ref` (§12.8), repeatable

#### 12.1.3 `ball.dreamball.tool`

A transferable skill. Carries exactly one `skill` attribute (a `ball.skill` envelope) and an optional `applicable-to` (list of DreamBall type names this Tool can attach to — defaults to `["ball.dreamball.agent"]`).

#### 12.1.4 `ball.dreamball.relic`

Wraps a sealed inner DreamBall. Core adds `sealed-payload-hash` (Blake3 of the sealed inner envelope bytes) and `unlock-guild` (Guild fingerprint whose keyspace can unlock). Attribute `reveal-hint` is an optional short text shown to would-be unlockers. Attachment slot in the `.ball` file carries the sealed bytes.

The Relic wrapper has its own ephemeral `identity` (Ed25519 pubkey of the
relic-issuer keypair) and MAY carry an `identity-pq` (ML-DSA-87 pubkey of
the same issuer) so the wrapper is self-verifying under the §2.3 hybrid
model. When `identity-pq` is present the core advertises
`format-version: 3`; Ed25519-only wrappers remain `format-version: 2`.
The relic keypair is typically ephemeral — generated fresh at seal
time, discarded after — so the hybrid strength protects the seal
record, not the issuer's long-lived identity.

#### 12.1.5 `ball.dreamball.field`

Attribute surface includes `omnispherical-grid` (§12.2), `ambient-palette` (hex colors or `ball.asset` refs), and `dream-field-id` (a UUID grouping related fields).

#### 12.1.6 `ball.dreamball.guild`

Members + policy container. Core adds `guild-name` (display) and `keyspace-root-hash` (Blake3 of the keyspace root — the Guild fingerprint). Attributes: `member` (repeatable, each a fingerprint), `admin` (repeatable fingerprints of admins), `policy` (§12.7).

### 12.2 `ball.omnispherical-grid`

The graticule that makes the dream-field renderable without committing to a mesh. See [`docs/VISION.md` §4](VISION.md#4-form-independence-in-the-look-slot-in-progress) for the optic-nerve / three-camera metaphor.

```
200(
  201({ "type": "ball.omnispherical-grid", "format-version": 2 })
) [
  "pole-north":   [0.0, 1.0, 0.0],                 ; v2 note: we DO allow floats for spatial coords
  "pole-south":   [0.0, -1.0, 0.0],
  "camera-ring":  [ {radius, tilt, fov}, ... ],    ; three cameras at minimum: origin-out, at-sphere, nested-out
  "layer-depth":  3,                                ; onion layers
  "resolution":   8,                                ; quantisation level (subdivision forward-only)
  [salted] 'note': "day variant"
]
```

**dCBOR float exception.** v1's no-floats rule is relaxed *only* for this envelope type. Coordinates and field values use CBOR `#7.25` half-floats (16-bit IEEE-754) where precision permits; `#7.26` single-floats otherwise. This is documented here so no other envelope introduces floats without a spec change.

### 12.3 `ball.memory`

A directed graph of memory nodes with labeled connections. Connections are typed: at minimum `semantic`, `emotional`, `temporal`.

```
200(
  201({ "type": "ball.memory", "format-version": 2 })
) [
  "node":    <ball.memory-node>,         ; repeatable
  "connection": <ball.memory-connection>,      ; repeatable
  [salted] "last-updated": 1(…),
]
```

`ball.memory-node` core: `{ "type": "ball.memory-node", "format-version": 2, "id": <u64> }`. Attributes include `content` (text or asset ref), `created`, `last-recalled`, and `lookups` (map of lookup-name → sort-key value, supporting the "emotional lookup table" use case).

`ball.memory-connection` core: `{ "type": "ball.memory-connection", "format-version": 2, "from": <u64>, "to": <u64>, "kind": "semantic"|"emotional"|"temporal"|... }`. Attributes include `strength` (0.0–1.0) and `label` (text).

> **Implementation note (2026-06-25).** `memory` is a first-class
> `DreamBall` slot, modelled exactly like `look` / `feel` / `act`: the
> `Memory` type lives in `src/protocol.zig` beside its siblings, its codec
> (`encodeMemory` / `decodeMemory`) lives in `src/envelope.zig`, and
> `DreamBall.memory` is attached/parsed inline in `encodeDreamBall` /
> `decodeDreamBall`. It used to live under the `protocol_v2` / `envelope_v2`
> split; per
> [`docs/decisions/2026-06-25-zig-canonical-supersedes-json-schema.md`](decisions/2026-06-25-zig-canonical-supersedes-json-schema.md)
> (Zig is canonical) the artificial v1/v2 split for this slot was removed.
> The shared envelope decode helpers were hoisted down to `src/dcbor.zig`
> to break the `envelope_v2 → envelope` import cycle. **The wire format above
> is unchanged** — this was a module-layout refactor only.

### 12.4 `ball.knowledge-graph`

Triple-shaped ambient knowledge. Each triple is `[from, label, to]` — `from` and `label` are short text strings; `to` is either a text value or a fingerprint reference. (This replaces the RDF "subject, predicate, object" naming; the data model is the same, the words match our vocabulary.)

```
200(
  201({ "type": "ball.knowledge-graph", "format-version": 2 })
) [
  "triple": ["curiosity", "inclines-toward", "new-things"],    ; repeatable
  "triple": ["haiku", "requires", "5-7-5 syllables"],
  [salted] "source": "hand-curated v0",
]
```

> **Implementation note (2026-06-26).** `knowledge-graph`,
> `emotional-register`, `interaction-set` (§12.6) and `guild-policy` (§12.7)
> are first-class `DreamBall` slots, modelled exactly like `look` / `feel` /
> `act` / `memory`: the value types (`KnowledgeGraph`, `EmotionalRegister`,
> `InteractionSet`, `GuildPolicy`, …) live in `src/protocol.zig` beside their
> siblings, their codecs (`encodeKnowledgeGraph`/`decodeKnowledgeGraph`,
> `encodeEmotionalRegister`/`decodeEmotionalRegister`,
> `encodeInteractionSet`/`decodeInteractionSet`,
> `encodeGuildPolicy`/`decodeGuildPolicy`) live in `src/envelope.zig`, and
> `encodeDreamBall`/`decodeDreamBall` attach/parse them inline. `interaction-set`
> is **repeatable** on the `DreamBall` (`DreamBall.interaction_sets` is a slice,
> emitting one `interaction-set` assertion per element); `guild-policy` rides as
> the `guild-policy` assertion (distinct from the `policy` map embedded inside a
> Guild envelope). These used to live under the `protocol_v2` / `envelope_v2`
> split; per
> [`docs/decisions/2026-06-25-zig-canonical-supersedes-json-schema.md`](decisions/2026-06-25-zig-canonical-supersedes-json-schema.md)
> (Zig is canonical) the artificial v1/v2 split for these slots was removed.
> **The wire formats in §12.4–12.7 are unchanged** — this was a module-layout
> refactor plus the addition of the missing decoders.

### 12.5 `ball.emotional-register`

Current value of named emotional axes. Axes are open — producers declare the axes they use.

```
200(
  201({ "type": "ball.emotional-register", "format-version": 2 })
) [
  "axis": { "name": "curiosity",  "value": 0.82, "range": [0.0, 1.0] },
  "axis": { "name": "warmth",     "value": 0.55, "range": [0.0, 1.0] },
  "axis": { "name": "urgency",    "value": 0.10, "range": [0.0, 1.0] },
  [salted] "observed-at": 1(…)
]
```

Values are floats (exception noted in §12.2). Renderers use this to tint lenses (e.g., the emotional-state lens visualises axis values as radial intensity).

### 12.6 `ball.interaction-set`

Captured interaction histories — what this DreamBall *has done / been part of*.

```
200(
  201({ "type": "ball.interaction-set", "format-version": 2,
        "set-id": h'…16 bytes…' })
) [
  "interaction": <ball.interaction>,    ; repeatable
  [salted] "created": 1(…)
]
```

`ball.interaction` core: `{ type, format-version, turn: u32, actor: fp, kind: "speak"|"listen"|"act"|"receive" }`. Attributes: `content` (text/asset), `timestamp`, `outcome` (optional short text).

### 12.7 `ball.guild-policy`

Per-slot read/write permission policy. Attached to a Guild envelope as the `policy` attribute.

```
200(
  201({ "type": "ball.guild-policy", "format-version": 2 })
) [
  "public":           "look",              ; repeatable — slot names readable by anyone
  "public":           "thumbnail",
  "guild-only":       "memory",            ; repeatable — slot names readable only by guild members
  "guild-only":       "knowledge-graph",
  "guild-only":       "emotional-register",
  "guild-only":       "interaction-set",
  "admin-only":       "secret",            ; repeatable — only guild admins
  "quorum-policy":    <ball.quorum-policy>,  ; optional — co-signing rule for quorum-gated actions
  [salted] 'note':    "default v2 policy"
]
```

A consumer rendering a DreamBall first checks `guild` attribute(s) on the target DreamBall, resolves each to a `ball.dreamball.guild` envelope, reads the policy, and decides which attributes to expose to the current viewer identity.

Policy resolution is additive — if multiple Guilds claim the DreamBall, the union of `public` + `guild-only` slots is readable by members of any claiming Guild; `admin-only` requires admin membership in at least one claiming Guild.

**`quorum-policy` (optional).** Defines the co-signing rule for
Guild-quorum-gated actions (PRD FR60g — mythos divergence
resolution; future uses: palace-custodian-change actions,
Guild-admin rotations):

```
200(
  201({ "type": "ball.quorum-policy", "format-version": 2,
        "kind": "m-of-n" })
) [
  "m":      3,                          ; threshold — how many admin sigs required
  "admins": [h'…32…', h'…32…', ...],   ; fingerprints eligible to co-sign; cardinality = n
  [salted] 'note': "default admin quorum"
]
```

Quorum is enforced **at the signature-verification layer** by
requiring an action to carry ≥ `m` `'signed'` attribute pairs
(Ed25519 + ML-DSA-87) each from a distinct fingerprint in the
`admins` list, each verifying over the action's canonical bytes.
This is a policy check on top of the existing "all present
signatures must verify" rule (§8) — it does **not** introduce a
threshold-aggregate signature scheme (which would be incompatible
with ML-DSA-87's lack of a reference threshold construction). See
`docs/decisions/2026-04-21-nextgraph-crdt-review.md` "Option A" for
the rationale.

### 12.8 `ball.secret-ref`

An indirection pointing at an out-of-band secret store. Critically, secrets are **not** embedded in the CBOR envelope — the envelope only carries a pointer, because secrets must live behind the Guild keyspace access path.

```
200(
  201({ "type": "ball.secret-ref", "format-version": 2,
        "name": "wallet-signing-key",
        "locator": "recrypt://…/wallets/abc..." })
) [
  [salted] "issued-by": h'…32…',
  [salted] "description": "ETH mainnet signing key for the swap skill"
]
```

The runtime requests the secret via the locator, presenting its fingerprint + Guild credentials; recrypt's proxy-recryption returns the plaintext only to authorised requesters. For v2, the locator path is mocked (see `TODO-CRYPTO` markers in the reference implementation); the envelope shape is real.

### 12.9 `ball.transmission`

Auditable record of a Tool transferred to an Agent via a Guild. Producers emit this as the receipt of a successful `dreamball transmit` call.

```
200(
  201({ "type":                "ball.transmission",
        "format-version":      3,                    ; 3 when sender-identity is set; 2 otherwise
        "tool-fp":             h'…32…',              ; Blake3(Tool.identity)
        "target-fp":           h'…32…',              ; the Agent DreamBall being augmented
        "via-guild":           h'…32…',              ; Guild fingerprint scoping the transfer
        "sender-identity":     h'…32…',              ; sender Ed25519 pubkey — verifies the Ed25519 'signed'
        "sender-identity-pq":  h'…2592…'             ; sender ML-DSA-87 pubkey — verifies the ML-DSA 'signed'
  })
) [
  "tool-envelope":    <full ball.dreamball.tool envelope>,   ; the Tool being transmitted, inlined
  [salted] "sender-fp": h'…32…',                               ; optional — Blake3(sender-identity); redundant when sender-identity present
  [salted] "transmitted-at": 1(…),
  'signed': ..., 'signed': ...
]
```

Pre-v3 Transmission envelopes carried only `sender-fp` (a
fingerprint), requiring verifiers to look up the sender's pubkey
bundle out-of-band. v3 embeds the sender's full public keys in
the core so the receipt is self-verifying. A Transmission that
sets `sender-identity-pq` MUST also set `sender-identity` and a
matching ML-DSA-87 `'signed'` attribute; verification follows the
§2.3 hybrid model. Ed25519-only senders set `sender-identity`
only and emit one signature.

Upon receipt, the target Agent's custodian updates the Agent's `act.skill` (or the Tool is kept separate, referenced by fingerprint) and bumps the Agent's `revision`.

### 12.10 Attachment layout in the .ball bundle

v2 adds two attachment slots beyond v1's freeform ordered list:

```
0: <sealed payload>   ; present only on Relics; bytes whose Blake3 = sealed-payload-hash
1+: <user attachments>
```

The v1 bundle header (magic `BALL`, version, flags, seal-type, attachment-count) is unchanged. v2 producers SHOULD set the `version` byte to `2` in new DragonBall bundles so that v1 parsers reject them cleanly; v1 parsers reading a v2 bundle MUST emit "unsupported version" rather than silently misinterpret the attachment order.

### 12.11 v1 → v2 migration

- **Additive.** Every new envelope type is new. No v1 type gains or loses core fields.
- **Untagged `ball.dreamball` is preserved.** v1 producers keep emitting it; v2 consumers treat it as Avatar.
- **Golden-bytes lock extended.** `src/golden.zig` gains one additional fixture per new envelope type (§12.1 × 6 + §12.2–12.9 × 8 = 14 fixtures) pinning canonical byte output.
- **No wire-breaking changes.** A v2 consumer reading a v1 envelope emits identical semantics to v1; a v1 consumer reading a v2 Avatar envelope loses only the new attributes it doesn't know about (they're additive).

### 12.12 Open questions for v2

- Should `ball.memory` triples and connections be content-addressed by their hash so a memory can be shared across DreamBalls? Defer — v2 treats memory as private to its Agent.
- Quorum signatures on Guild unlocks (m-of-n)? Currently any member can unlock; Vision tier.
- Should `ball.transmission` carry a *revocation* counterpart (a Tool previously transmitted can be withdrawn)? Defer — transmission is additive; revocation needs the real recrypt wire-up.

---

## 13. Memory Palace composition — auxiliary envelopes

**Status:** Draft v1 — 2026-04-20.
**Scope:** One optional core field on `ball.dreamball.field`,
plus nine auxiliary envelope types introduced by the Memory Palace
composition (see [`docs/products/memory-palace/prd.md`](products/memory-palace/prd.md)
for the product spec and [`docs/VISION.md §15`](VISION.md#15-the-memory-palace-the-first-composition)
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
| `"ambient"` | The dream-field meaning from VISION §4.4.5 — environmental context for non-palace compositions. |
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
coexist (the palace shifts; see PRD J5 and VISION §15.7).

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

A directed, typed, weighted connection carrying **Vril** (see VISION §15.3).
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

The keystone. See VISION §15.2 for the *why*. Wire:

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

## 14. Schema vendoring and pin format

*Implements D-029 (aspects.sh vendor-first contract + pin file format).*

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
| `bun run schemas:refresh` | (Sprint-003 candidate) Fetch the latest schema version from aspects.sh, verify the digest matches the declared pin, and swap in if matched |

`schemas:refresh` is **not** a CI gate. It is an optional maintenance
path for updating vendored schemas. The CI gate is `schemas:verify`
only, which runs entirely against local files.

### 14.4 Update lifecycle

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
