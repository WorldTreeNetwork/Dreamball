# DreamBall Protocol

**Status:** Draft v0 — 2026-04-18
**File extension:** `.jelly`
**Media type:** `application/jelly+cbor` (binary), `application/jelly+json` (export)
**Sister project:** [recrypt](../../recrypt/) — shares cryptographic methodology (see `recrypt/docs/wire-protocol.md`)

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

## 2. Design conventions (inherited from recrypt)

The protocol reuses recrypt's wire conventions verbatim, except where noted:

1. **CBOR wire format, dCBOR-style determinism.** Map keys sorted canonically, smallest integer encoding, no floats in protocol fields, no indefinite-length items, tagged timestamps (`#6.1`), tagged envelopes (`#6.200`) and leaves (`#6.201`). See [recrypt wire-protocol §2.1](../../recrypt/docs/wire-protocol.md#21-dcbor).
2. **Envelope = core + attributes.** Load-bearing anchors (`type`, `format-version`, identity key, content hashes) go in the core. Mutable, elidable, descriptive metadata goes in attributes.
3. **Dual signatures, both required.** Every signed DreamBall carries exactly one Ed25519 and one ML-DSA-87 `'signed'` attribute. A verifier that sees only one MUST reject.
4. **Salted attributes for low-entropy elidable fields** (timestamps, small enums, templated strings). See [recrypt wire-protocol §6](../../recrypt/docs/wire-protocol.md#6-salting-policy).
5. **Fingerprint = `Blake3(Ed25519 public key)`**, 32 bytes, base58 for display.
6. **`format-version` in every core.** Parsers reject unknown versions before reading further.
7. **Three interchange formats**, same bytes underneath:

| Format      | Extension    | Primary use                        |
| ----------- | ------------ | ---------------------------------- |
| CBOR        | `.jelly`     | canonical binary; the authority    |
| JSON        | `.jelly.json` | open-protocol export; readable in any stack |
| ASCII armor | `.jelly.asc` | copy-paste / email / printed backups |

The CBOR bytes are authoritative. JSON and armor are wrappings of the same semantic content.

---

## 3. CBOR tags

| Tag      | Role                                   | Owner                |
| -------- | -------------------------------------- | -------------------- |
| `#6.200` | Envelope                               | Blockchain Commons   |
| `#6.201` | Leaf (dCBOR-encoded core)              | Blockchain Commons (upstream name: "subject") |
| `#6.1`   | Epoch time (RFC 8949)                  | IETF                 |
| `#6.???` | `jelly.asset-ref` (content-addressed)  | TBD — private-use until registered |
| `#6.???` | `jelly.dreamball-ref` (fingerprint)    | TBD — private-use until registered |

---

## 4. Domain types

### 4.1 `jelly.dreamball`

The primary envelope — represents a single DreamBall at any stage of its lifecycle.

```
200(                                              ; envelope
  201(                                            ; leaf core
    {
      "type":           "jelly.dreamball",
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
           "look":          <jelly.look envelope>,
           "feel":          <jelly.feel envelope>,
           "act":           <jelly.act envelope>,

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
| `type`           | string   | `"jelly.dreamball"`                              |
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

### 4.2 `jelly.look` (evolving)

**Status:** v1 is the simple asset-list shape below. v2 is actively being
designed around form-independence — see [`docs/VISION.md` §4](VISION.md#4-form-independence-in-the-look-slot-in-progress)
for the full rationale (shader-first layer, optional addressable base mesh,
graticule refs, resolution declarations). v2 will land as *additive*
attributes so v1 envelopes keep working.

```
200(
  201(
    {
      "type":           "jelly.look",
      "format-version": 1
    }
  )
) [
  "asset":           <jelly.asset envelope>,       ; repeatable — GLB, GLTF, splat, image, etc.
  "preview":         <jelly.asset envelope>,       ; optional — low-res/thumb
  "background":      "color:#0b1020",              ; or asset ref
  [salted] 'note':   "hummingbird silhouette, neon sugar palette"

  ; Reserved for v2 (ignored by v1 parsers; planned shape sketched only):
  ; "shader":     <jelly.shader envelope>          ; material/shader graph
  ; "base-mesh":  <jelly.mesh envelope>            ; addressable topology
  ; "graticule":  <jelly.graticule envelope>       ; space-distribution map
  ; "resolution": 8                                 ; declared quantisation level
]
```

The philosophical reason the v2 slots exist: mesh+texture assets bind the
visual identity to a specific topology, which breaks when the mesh is
substituted or re-topologised. Shaders, addressable base meshes, and
graticules each travel across topology changes, so a DreamBall's `look`
survives re-rigging, re-meshing, and medium changes (splat ↔ mesh ↔ SDF).

### 4.3 `jelly.feel`

```
200(
  201(
    {
      "type":           "jelly.feel",
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

### 4.4 `jelly.act`

The executable layer. References an LLM model, carries a system prompt, lists skills, scripts, and tool affordances. All script bodies are either **embedded** (short) or **referenced by `jelly.asset`** (large).

```
200(
  201(
    {
      "type":           "jelly.act",
      "format-version": 1
    }
  )
) [
  "model":           "claude-opus-4-7",
  "system-prompt":   "You are an aspect of curiosity...",
  "skill":           <jelly.skill envelope>,        ; repeatable
  "script":          <jelly.asset envelope>,        ; repeatable, when script body is large
  "tool":            "web.search",                  ; named tool affordance, repeatable
  [salted] 'note':   "avoid invoking shell tools without explicit user intent"
]
```

`jelly.skill` is a small envelope (`name`, `trigger`, `body` or `asset-ref`, optional `requires` list). Spelled out in §4.7.

### 4.5 `jelly.asset`

Any binary or URL-addressable payload (3D, image, script text, JSON blob).

```
200(
  201(
    {
      "type":           "jelly.asset",
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

### 4.6 `jelly.key-bundle`

Public-key bundle for a DreamBall's author/owner. Same shape as recrypt's `recrypt.public-key-bundle`, re-namespaced.

```
200(
  201(
    {
      "type":           "jelly.key-bundle",
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

### 4.7 `jelly.skill`

A single skill definition.

```
200(
  201(
    {
      "type":           "jelly.skill",
      "format-version": 1,
      "name":           "answer-with-citation"
    }
  )
) [
  "trigger":         "when user asks a factual question",
  "body":            "...prompt text...",            ; small bodies inline
  "asset":           <jelly.asset envelope>,         ; large bodies referenced
  "requires":        "web.search",                   ; tool dep, repeatable
  [salted] 'note':   "tested 2026-04"
]
```

---

## 5. Lifecycle: Seed → Ball → Dragon

### 5.1 DreamSeed

A DreamSeed is a `jelly.dreamball` with:

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
│ JELLY magic (4B "JELY") | version (1B) | flags (1B)         │
│ seal-type (1B) | reserved (1B)                              │
│ envelope-length (u32 little-endian)                          │
│ envelope-bytes: zstd( dCBOR( jelly.dreamball envelope ) )    │
│ attachment-count (u16 little-endian)                         │
│ [ attachment-length (u32) | attachment-bytes ] * count       │
└──────────────────────────────────────────────────────────────┘
```

- **Magic:** ASCII `"JELY"` (0x4A 0x45 0x4C 0x59).
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

- **Attachments:** optional raw bytes for large assets (GLB/GLTF/splats) whose hashes are referenced from `jelly.asset` envelopes inside the DreamBall. Attachments let a sealed DreamBall travel with its heavy visuals rather than depending on external URLs.

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
  "type": "jelly.dreamball",
  "format-version": 1,
  "stage": "dreamball",
  "identity": "b58:3xqJ...",
  "genesis-hash": "b58:5tYn...",
  "revision": 7,
  "name": "Aspect of Curiosity",
  "created": "2024-04-08T00:00:00Z",
  "look":  { "type": "jelly.look",  "format-version": 1, "asset": [...] },
  "feel":  { "type": "jelly.feel",  "format-version": 1, "personality": "..." },
  "act":   { "type": "jelly.act",   "format-version": 1, "model": "claude-opus-4-7", "system-prompt": "..." },
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

Identical to recrypt (see [recrypt wire-protocol §4](../../recrypt/docs/wire-protocol.md#4-signature-model)):

1. Producer constructs the envelope with core + all non-signature attributes.
2. Producer calls the library's `add_signatures(ed25519, ml-dsa-87)`; the library computes the signed digest and appends two `'signed'` attributes.
3. Verifier counts signatures (must be exactly two, one of each algorithm), verifies both, rejects on any failure.

Signatures cover the core digest plus every non-elided attribute's digest at signing time. Eliding a salted attribute after signing is valid.

---

## 9. Versioning

Each envelope carries `format-version` in its core. Additive changes (new attribute labels) do not bump the version. New core fields or removed core fields do. See [recrypt wire-protocol §10](../../recrypt/docs/wire-protocol.md#10-versioning-and-evolution).

Current version floor: `1` for every domain type.

---

## 10. Interop with recrypt

- **Key bundles are compatible.** A `jelly.key-bundle` and a `recrypt.public-key-bundle` use identical key encoding. Tooling that already has a recrypt identity can sign DreamBalls with the same keypair.
- **Sealing uses recrypt.** DragonBalls with `seal-type = 1` are plain recrypt encrypted-file envelopes whose plaintext payload is the DreamBall envelope bytes. Recrypt's proxy-recryption story applies unchanged — a sealed DreamBall can be shared with new recipients by asking recrypt's recryption proxy to rewrap the KEM.
- **Storage is compatible.** Content-addressed storage (Blake3 of the envelope bytes) lets DreamBalls live in recrypt's blob store with no protocol collision.

---

## 11. Open questions

1. **CBOR tag registration.** `jelly.asset-ref` and `jelly.dreamball-ref` need real tag numbers. Coordinate with recrypt's private-use tag registration.
2. **Attachment deduplication.** When a nested DreamBall and its parent both reference the same asset, DragonBall format currently stores the attachment twice. Consider a per-file asset table indexed by Blake3.
3. **Graph cycle detection.** Producers must not create containment cycles; do we enforce at encode time, verify time, or both?
4. **Large system prompts.** Should the wire format cap inline string lengths and force spill to `jelly.asset` past some threshold (e.g., 64 KiB) for parser predictability?
5. **"Born-dragon" envelopes.** Is there a use for a DreamBall that never existed in open form? If so, `stage = "dragonball"` inside the inner envelope carries meaning; if not, drop that value and always use `"dreamball"` inside a sealed wrapper.

---

## 12. Protocol v2 — typed DreamBalls, memory, guilds, transmission

**Version:** `format-version: 2` on every new envelope type introduced here. v1 envelopes continue to round-trip through v2 parsers unchanged.

**Rationale:** v1 shipped one `jelly.dreamball` envelope treated as a monolith. v2 recognises that DreamBalls are **MTG-style categories with different effects** (creature ≠ artifact ≠ land); each type demands different slot surfaces and renderer behaviour. v2 also gives DreamBalls the slots they need to be agents (memory, knowledge, emotion, skills) and the keyspace-style grouping to transmit skills across bodies. See [`docs/VISION.md` §10](VISION.md#10-the-six-type-taxonomy-mtg-style) for the why.

### 12.1 The six typed DreamBalls

Every v2 DreamBall core carries a `type` field selected from:

| Core `type` | Shape | Primary lens(es) |
|---|---|---|
| `jelly.dreamball.avatar` | look-heavy; minimal act | avatar, thumbnail |
| `jelly.dreamball.agent`  | act-heavy; model + memory + KG + emotion + skills | knowledge-graph, emotional-state |
| `jelly.dreamball.tool`   | single skill payload, transferable | thumbnail, flat |
| `jelly.dreamball.relic`  | sealed inner envelope; reveals on unlock | omnispherical, flat |
| `jelly.dreamball.field`  | omnispherical-grid parameters; ambient layer | omnispherical |
| `jelly.dreamball.guild`  | members list + keyspace ref + per-slot policy | flat, knowledge-graph |

The v1 bare `jelly.dreamball` value remains legal (untyped). Producers SHOULD migrate to one of the six typed values; consumers that see `jelly.dreamball` with no subtype MUST treat it as the Avatar variant (safest default).

All six share the v1 core fields (`format-version`, `stage`, `identity`, `genesis-hash`, `revision`) and add **zero load-bearing core fields** — the difference between types lives in which *attributes* the consumer expects to find.

#### 12.1.1 `jelly.dreamball.avatar`

Populated attribute surface: `look`, `feel` (optional), `name`, `note`, optional `wearer` (a fingerprint indicating the current wearer — informational; not a security claim).

Example:
```
200(
  201({ "type": "jelly.dreamball.avatar", "format-version": 2,
        "identity": h'…32…', "genesis-hash": h'…32…', "revision": 3,
        "stage": "dreamball" })
) [
  "name":   "Hummingbird Hat",
  "look":   <jelly.look envelope>,
  "feel":   <jelly.feel envelope>,
  [salted] "wearer": h'…32…',
  'signed': ..., 'signed': ...
]
```

#### 12.1.2 `jelly.dreamball.agent`

Full act surface plus the four new v2 agent attributes:
- `act` — v1-compatible skill + tool + model + prompt slot
- `memory` — `jelly.memory` envelope (§12.3)
- `knowledge-graph` — `jelly.knowledge-graph` envelope (§12.4)
- `emotional-register` — `jelly.emotional-register` envelope (§12.5)
- `interaction-set` — `jelly.interaction-set` envelope (§12.6), repeatable
- `personality-master-prompt` — text (the top-level system prompt; distinct from per-skill prompts)
- `secret` — `jelly.secret-ref` (§12.8), repeatable

#### 12.1.3 `jelly.dreamball.tool`

A transferable skill. Carries exactly one `skill` attribute (a `jelly.skill` envelope) and an optional `applicable-to` (list of DreamBall type names this Tool can attach to — defaults to `["jelly.dreamball.agent"]`).

#### 12.1.4 `jelly.dreamball.relic`

Wraps a sealed inner DreamBall. Core adds `sealed-payload-hash` (Blake3 of the sealed inner envelope bytes) and `unlock-guild` (Guild fingerprint whose keyspace can unlock). Attribute `reveal-hint` is an optional short text shown to would-be unlockers. Attachment slot in the `.jelly` file carries the sealed bytes.

#### 12.1.5 `jelly.dreamball.field`

Attribute surface includes `omnispherical-grid` (§12.2), `ambient-palette` (hex colors or `jelly.asset` refs), and `dream-field-id` (a UUID grouping related fields).

#### 12.1.6 `jelly.dreamball.guild`

Members + policy container. Core adds `guild-name` (display) and `keyspace-root-hash` (Blake3 of the keyspace root — the Guild fingerprint). Attributes: `member` (repeatable, each a fingerprint), `admin` (repeatable fingerprints of admins), `policy` (§12.7).

### 12.2 `jelly.omnispherical-grid`

The graticule that makes the dream-field renderable without committing to a mesh. See [`docs/VISION.md` §4](VISION.md#4-form-independence-in-the-look-slot-in-progress) for the optic-nerve / three-camera metaphor.

```
200(
  201({ "type": "jelly.omnispherical-grid", "format-version": 2 })
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

### 12.3 `jelly.memory`

A directed graph of memory nodes with labeled connections. Connections are typed: at minimum `semantic`, `emotional`, `temporal`.

```
200(
  201({ "type": "jelly.memory", "format-version": 2 })
) [
  "node":    <jelly.memory-node>,         ; repeatable
  "connection": <jelly.memory-connection>,      ; repeatable
  [salted] "last-updated": 1(…),
]
```

`jelly.memory-node` core: `{ "type": "jelly.memory-node", "format-version": 2, "id": <u64> }`. Attributes include `content` (text or asset ref), `created`, `last-recalled`, and `lookups` (map of lookup-name → sort-key value, supporting the "emotional lookup table" use case).

`jelly.memory-connection` core: `{ "type": "jelly.memory-connection", "format-version": 2, "from": <u64>, "to": <u64>, "kind": "semantic"|"emotional"|"temporal"|... }`. Attributes include `strength` (0.0–1.0) and `label` (text).

### 12.4 `jelly.knowledge-graph`

Triple-shaped ambient knowledge. Each triple is `[from, label, to]` — `from` and `label` are short text strings; `to` is either a text value or a fingerprint reference. (This replaces the RDF "subject, predicate, object" naming; the data model is the same, the words match our vocabulary.)

```
200(
  201({ "type": "jelly.knowledge-graph", "format-version": 2 })
) [
  "triple": ["curiosity", "inclines-toward", "new-things"],    ; repeatable
  "triple": ["haiku", "requires", "5-7-5 syllables"],
  [salted] "source": "hand-curated v0",
]
```

### 12.5 `jelly.emotional-register`

Current value of named emotional axes. Axes are open — producers declare the axes they use.

```
200(
  201({ "type": "jelly.emotional-register", "format-version": 2 })
) [
  "axis": { "name": "curiosity",  "value": 0.82, "range": [0.0, 1.0] },
  "axis": { "name": "warmth",     "value": 0.55, "range": [0.0, 1.0] },
  "axis": { "name": "urgency",    "value": 0.10, "range": [0.0, 1.0] },
  [salted] "observed-at": 1(…)
]
```

Values are floats (exception noted in §12.2). Renderers use this to tint lenses (e.g., the emotional-state lens visualises axis values as radial intensity).

### 12.6 `jelly.interaction-set`

Captured interaction histories — what this DreamBall *has done / been part of*.

```
200(
  201({ "type": "jelly.interaction-set", "format-version": 2,
        "set-id": h'…16 bytes…' })
) [
  "interaction": <jelly.interaction>,    ; repeatable
  [salted] "created": 1(…)
]
```

`jelly.interaction` core: `{ type, format-version, turn: u32, actor: fp, kind: "speak"|"listen"|"act"|"receive" }`. Attributes: `content` (text/asset), `timestamp`, `outcome` (optional short text).

### 12.7 `jelly.guild-policy`

Per-slot read/write permission policy. Attached to a Guild envelope as the `policy` attribute.

```
200(
  201({ "type": "jelly.guild-policy", "format-version": 2 })
) [
  "public":           "look",              ; repeatable — slot names readable by anyone
  "public":           "thumbnail",
  "guild-only":       "memory",            ; repeatable — slot names readable only by guild members
  "guild-only":       "knowledge-graph",
  "guild-only":       "emotional-register",
  "guild-only":       "interaction-set",
  "admin-only":       "secret",            ; repeatable — only guild admins
  [salted] 'note':    "default v2 policy"
]
```

A consumer rendering a DreamBall first checks `guild` attribute(s) on the target DreamBall, resolves each to a `jelly.dreamball.guild` envelope, reads the policy, and decides which attributes to expose to the current viewer identity.

Policy resolution is additive — if multiple Guilds claim the DreamBall, the union of `public` + `guild-only` slots is readable by members of any claiming Guild; `admin-only` requires admin membership in at least one claiming Guild.

### 12.8 `jelly.secret-ref`

An indirection pointing at an out-of-band secret store. Critically, secrets are **not** embedded in the CBOR envelope — the envelope only carries a pointer, because secrets must live behind the Guild keyspace access path.

```
200(
  201({ "type": "jelly.secret-ref", "format-version": 2,
        "name": "wallet-signing-key",
        "locator": "recrypt://…/wallets/abc..." })
) [
  [salted] "issued-by": h'…32…',
  [salted] "description": "ETH mainnet signing key for the swap skill"
]
```

The runtime requests the secret via the locator, presenting its fingerprint + Guild credentials; recrypt's proxy-recryption returns the plaintext only to authorised requesters. For v2, the locator path is mocked (see `TODO-CRYPTO` markers in the reference implementation); the envelope shape is real.

### 12.9 `jelly.transmission`

Auditable record of a Tool transferred to an Agent via a Guild. Producers emit this as the receipt of a successful `jelly transmit` call.

```
200(
  201({ "type": "jelly.transmission", "format-version": 2,
        "tool-fp":   h'…32…',    ; Blake3(Tool.identity)
        "target-fp": h'…32…',    ; the Agent DreamBall being augmented
        "via-guild": h'…32…' })
) [
  "tool-envelope":    <full jelly.dreamball.tool envelope>,   ; the Tool being transmitted, inlined
  [salted] "sender-fp": h'…32…',
  [salted] "transmitted-at": 1(…),
  'signed': ..., 'signed': ...
]
```

Upon receipt, the target Agent's custodian updates the Agent's `act.skill` (or the Tool is kept separate, referenced by fingerprint) and bumps the Agent's `revision`.

### 12.10 Attachment layout in the .jelly bundle

v2 adds two attachment slots beyond v1's freeform ordered list:

```
0: <sealed payload>   ; present only on Relics; bytes whose Blake3 = sealed-payload-hash
1+: <user attachments>
```

The v1 bundle header (magic `JELY`, version, flags, seal-type, attachment-count) is unchanged. v2 producers SHOULD set the `version` byte to `2` in new DragonBall bundles so that v1 parsers reject them cleanly; v1 parsers reading a v2 bundle MUST emit "unsupported version" rather than silently misinterpret the attachment order.

### 12.11 v1 → v2 migration

- **Additive.** Every new envelope type is new. No v1 type gains or loses core fields.
- **Untagged `jelly.dreamball` is preserved.** v1 producers keep emitting it; v2 consumers treat it as Avatar.
- **Golden-bytes lock extended.** `src/golden.zig` gains one additional fixture per new envelope type (§12.1 × 6 + §12.2–12.9 × 8 = 14 fixtures) pinning canonical byte output.
- **No wire-breaking changes.** A v2 consumer reading a v1 envelope emits identical semantics to v1; a v1 consumer reading a v2 Avatar envelope loses only the new attributes it doesn't know about (they're additive).

### 12.12 Open questions for v2

- Should `jelly.memory` triples and connections be content-addressed by their hash so a memory can be shared across DreamBalls? Defer — v2 treats memory as private to its Agent.
- Quorum signatures on Guild unlocks (m-of-n)? Currently any member can unlock; Vision tier.
- Should `jelly.transmission` carry a *revocation* counterpart (a Tool previously transmitted can be withdrawn)? Defer — transmission is additive; revocation needs the real recrypt wire-up.

---

## 13. Memory Palace composition — auxiliary envelopes

**Status:** Draft v1 — 2026-04-20.
**Scope:** One optional core field on `jelly.dreamball.field`,
plus nine auxiliary envelope types introduced by the Memory Palace
composition (see [`docs/products/memory-palace/prd.md`](products/memory-palace/prd.md)
for the product spec and [`docs/VISION.md §15`](VISION.md#15-the-memory-palace-the-first-composition)
for the descriptive rationale).
**Rationale:** The palace is a *specific composition* of the v2
primitives, not a new protocol. Every envelope here is additive; v2
parsers without palace support see these as unknown attributes and
skip. No existing envelope gains or loses core fields.

### 13.1 The `field-kind` attribute

`jelly.dreamball.field` (§12.1.5) gains **one optional attribute**:

```
"field-kind": "palace" | "room" | "ambient" | <open-enum>
```

| Value | Meaning |
|---|---|
| `"palace"` | A Memory Palace root. MUST carry a `jelly.mythos` attribute (§13.8). Renderer routes to the `palace` lens. |
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

### 13.2 `jelly.layout`

A Room or Palace Field carries a `layout` attribute that records
where its children sit in its local coordinate frame. The layout is
a **rendering hint**, not a security claim — multiple layouts can
coexist (the palace shifts; see PRD J5 and VISION §15.7).

```
200(
  201({ "type": "jelly.layout", "format-version": 2 })
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
out for `jelly.omnispherical-grid` in §12.2. No other fields use
floats.

### 13.3 `jelly.timeline` + `jelly.action`

A signed, hash-linked DAG of actions taken inside the palace.
Append-only per keypair; Merkle-rooted by `head-hash`; any
cryptographic-clock semantics can be derived without a central
authority. Multi-parent actions enable merge semantics (conflict
resolution is PRD FR68, Vision).

```
200(
  201({ "type": "jelly.timeline", "format-version": 2,
        "palace-fp": h'…32…'                 ; 1:1 identity anchor — which palace this timeline belongs to
  })
) [
  "head-hash":    h'…32…',                   ; Blake3 of the latest jelly.action envelope — attribute, updated on every append
  "action":       <jelly.action envelope>,   ; repeatable, ordered by parent-hash chain
  [salted] 'note': "genesis timeline"
]
```

`head-hash` lives in an attribute, not the core, because it is
the timeline's current *state*, not its *identity*. The core
stays stable across the timeline's entire life: `palace-fp` binds
the timeline to exactly one palace. Re-signing on append is still
required, but the core digest does not churn — the Merkle tree
over attributes is what changes.

`jelly.action` core:
```
{
  "type":           "jelly.action",
  "format-version": 2,
  "action-kind":    "inscribe"|"move"|"unlock"|"true-naming"|"shadow-naming"|…,
  "parent-hashes":  [h'…32…', h'…32…'],       ; one for linear history, multiple for merges
  "actor":          h'…32…'                    ; fingerprint of the signer
}
```
Attributes: `timestamp` (CBOR tag 1), `target-fp` (what the action
was performed on, if any), free-form per-kind payload, dual
signatures.

**Chain rules.**
- Every signed action's `parent-hashes` MUST resolve to previously
  signed actions in the same palace's timeline.
- Verification walks back from `head-hash` to the first action
  (whose `parent-hashes` is empty); a gap is a hard failure.
- An action whose `parent-hashes` points outside the palace's
  timeline is rejected with "foreign parent."

**`jelly.action-ref` shorthand.** A 32-byte Blake3 of a
`jelly.action` envelope's canonical bytes. Used from other envelopes
(notably `jelly.mythos.discovered-in`, §13.8) to cite a specific
action on the timeline without embedding it. Wire-level, it is a
plain byte-string — the name exists only for readability in this
document.

### 13.4 `jelly.aqueduct`

A directed, typed, weighted connection carrying **Vril** (see VISION §15.3).
The electrical-style fields are **load-bearing** — both the renderer
(particle speed, glow density, pulse phase) and the oracle
(diagnostic reasoning) consume them. Aqueducts sit *on top of* the
cold `contains` graph without polluting it.

```
200(
  201({ "type": "jelly.aqueduct", "format-version": 2,
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

### 13.5 `jelly.element-tag`

Open elemental/phase classification. A tag, not a schema — downstream
systems elect whether to honour it. Orthogonal to `jelly.archiform`
(§13.9): form answers "what kind of space is this?"; element answers
"what quality of energy animates it?"

```
200(
  201({ "type": "jelly.element-tag", "format-version": 2 })
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

### 13.6 `jelly.trust-observation`

A signed, local observation one actor emits about another.
**Decentralised by construction** — never aggregated into a
universal score at the protocol level; aggregation is reader-side
policy, typically weighted by social-graph distance.

```
200(
  201({ "type": "jelly.trust-observation", "format-version": 2,
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
  an explicit `jelly transmit`, scoped to a Guild.
- Axis values use the §12.2 float exception.
- Slot-level privacy follows `jelly.guild-policy` (§12.7). Default
  policy places trust observations in the `guild-only` bucket.

### 13.7 `jelly.inscription`

An Avatar DreamBall whose `look` geometry is *text arranged in
space*. Rendered by the new `inscription` lens (PRD §6.1) or
falls back to the `flat` lens with the markdown body.

```
200(
  201({ "type": "jelly.inscription", "format-version": 2 })
) [
  "source":    <jelly.asset envelope>,              ; media-type: text/markdown, text/plain, text/asciidoc, …
  "surface":   "scroll"|"tablet"|"book-spread"|"etched-wall"|"floating-glyph"|<open-enum>,
  "placement": "auto"|"curator",                    ; auto = renderer chooses; curator = parent room's jelly.layout
  [salted] 'note': "lives on the east wall"
]
```

Because `source` is content-addressed (Blake3 of file bytes), a
markdown file on disk and its inscription in a palace share an
identity. File-watcher logic on the oracle side can keep them
synchronised (PRD FR72, Growth).

### 13.8 `jelly.mythos`

The keystone. See VISION §15.2 for the *why*. Wire:

```
200(
  201({ "type": "jelly.mythos", "format-version": 2,
        "is-genesis":  <bool>,                      ; true iff this is the first mythos of this chain (canonical or poetic)
        "predecessor": h'…32…'                     ; Blake3 of the prior jelly.mythos envelope; absent iff is-genesis
  })
) [
  "about":        h'…32…',                                           ; POETIC ONLY — fingerprint of the DreamBall this mythos is about; absent on canonical (embedded) chains
  "form":         "blurb"|"invocation"|"image"|"utterance"|"glyph"|"true-name"|<open-enum>,
  "body":         "There is a giant cow beside the chaos abyss.",    ; the mythos in full poetic form
  "true-name":    "Audhumla",                                         ; optional condensed totem
  "source":       <jelly.asset envelope>,                             ; optional longer form
  "discovered-in":<jelly.action-ref>,                                 ; CANONICAL ONLY — paired 'true-naming' action on the palace timeline
  "synthesizes":  [h'…32…', h'…32…'],                                ; CANONICAL ONLY — poetic mythoi that informed this renaming (attribution)
  "inspired-by":  [h'…32…', h'…32…'],                                ; POETIC ONLY — other mythoi this author was thinking with
  [salted] "author":      h'…32…',
  [salted] "authored-at": 1(…)
]
```

**Two kinds of chain.** A DreamBall MAY have:

- A **canonical chain** — signed by the DreamBall's custodian(s),
  embedded as a `jelly.mythos` attribute directly on the DreamBall
  envelope, `about` absent. Load-bearing on identity. A
  `jelly.dreamball.field` with `field-kind: "palace"` MUST carry at
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
| `predecessor` | 32 bytes | Blake3 of the prior `jelly.mythos` envelope bytes *in the same chain*. MUST be absent iff `is-genesis` is `true`; MUST be present otherwise. |

**Chain rules.**
- Each chain is append-only within itself. Publishing a link whose
  `predecessor` doesn't resolve to a verifiable prior link in the
  same chain is rejected.
- Only the DreamBall's custodian(s) may extend the **canonical**
  chain — for a solo DreamBall, the identity keypair; for a
  Guild-owned one, any admin (Guild-policy-scoped quorum is Vision,
  PRD FR60g). Non-custodian-signed mythoi pointing at the DreamBall
  are always poetic, never canonical.
- Every canonical chain extension MUST emit a paired `jelly.action`
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

### 13.9 `jelly.archiform`

Archetypal form classification. Tag, not schema. Orthogonal to
`jelly.element-tag` (§13.5) and to the six v2 DreamBall types.

```
200(
  201({ "type": "jelly.archiform", "format-version": 2 })
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
`jelly.asset` of media-type
`application/vnd.palace.archiform-registry+json` for air-gapped
use. The `parent-form` field turns the archiform vocabulary into a
DAG; renderers walk parents to resolve unspecified defaults.

Archiform MAY appear on any DreamBall. It does not constrain the
envelope's slot surface; it hints to renderers, oracles, and
collaborators.

### 13.10 Attachment layout in the .jelly bundle

Palace compositions do not change §12.10's attachment layout.
Large inscriptions (media of sufficient size to benefit from
sidecar transport) use the existing user-attachment slot (`1+`).
Sealed rooms use the Relic sealed-payload slot (`0`) exactly as
v2 specifies.

### 13.11 Golden-bytes lock

`src/golden.zig` gains **thirteen new fixtures**. The fixtures pin
canonical byte output for:

1. `jelly.dreamball.field` with `field-kind: "palace"` attribute
   (minimal).
2. `jelly.layout` with two placements.
3. `jelly.timeline` with `head-hash` attribute set.
4. `jelly.action` single-parent variant.
5. `jelly.action` multi-parent variant.
6. `jelly.aqueduct` with all numeric fields populated.
7. `jelly.element-tag` with `phase` qualifier.
8. `jelly.trust-observation` with two axes + both signatures.
9. `jelly.inscription` with embedded markdown asset.
10. `jelly.mythos` canonical genesis.
11. `jelly.mythos` canonical successor with `synthesizes`.
12. `jelly.mythos` poetic (with `about` attribute).
13. `jelly.archiform` with `parent-form` set.

### 13.12 Migration

- **Fully additive.** Every introduction here is new. No v1 or v2
  envelope gains or loses core fields.
- **Version number unchanged.** All new envelopes carry
  `format-version: 2`.
- **v2 consumers without palace support.** Unknown attributes on a
  known envelope skip silently, preserving §9's versioning rule. A
  v2 consumer rendering a palace-flavoured Field without palace
  support sees a plain v2 Field and renders via the existing
  `omnispherical` lens — degraded but valid.

### 13.13 Open questions

Tracked in the Memory Palace PRD §9 rather than duplicated here.
Summary of protocol-shape-affecting ones:

1. **CRDT merge semantics for the timeline DAG.** Multi-writer
   merges are Vision (PRD FR68). A decision there may reshape
   `jelly.action`'s core.
2. **Mythos quorum on Guild-owned palaces.** PRD FR60g Vision.
   Default today is any-admin.
3. **Archiform registry federation.** Community-defined archiforms
   may fragment without a shared root registry. Deferred.
4. **NextGraph overlap.** Before locking CRDT and threshold-signature
   semantics, read `docs.nextgraph.org/en/specs/` (convergence noted
   in PRD §6.2.2) to avoid reinventing their solutions in an
   incompatible shape.
