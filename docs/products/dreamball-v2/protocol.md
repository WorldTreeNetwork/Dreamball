# DreamBall v2 — Reference-Type Wire Extensions

> Extracted verbatim from the canonical wire spec
> [`../../PROTOCOL.md`](../../PROTOCOL.md). These are the wire formats for the
> six reference DreamBall types and their slots (memory, knowledge-graph,
> emotional-register, guild-policy, transmission, …). **Section numbers
> (§12.x) are preserved from the root spec** for cross-reference stability.
> The substrate framing (envelope, CBOR, signatures, versioning) lives in the
> root spec; the *why* lives in [`vision.md`](vision.md).

---

## 12. Protocol v2 — typed DreamBalls, memory, guilds, transmission

**Version:** `format-version: 2` on every new envelope type introduced here. v1 envelopes continue to round-trip through v2 parsers unchanged.

**Rationale:** v1 shipped one `ball.dreamball` envelope treated as a monolith. v2 recognises that DreamBalls are **MTG-style categories with different effects** (creature ≠ artifact ≠ land); each type demands different slot surfaces and renderer behaviour. v2 also gives DreamBalls the slots they need to be agents (memory, knowledge, emotion, skills) and the keyspace-style grouping to transmit skills across bodies. See [`products/dreamball-v2/vision.md`](products/dreamball-v2/vision.md) (the reference types) for the why.

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

The graticule that makes the dream-field renderable without committing to a mesh. See [`docs/VISION.md` §10.4.5](../../VISION.md#1045-the-omnispherical-perspective-grid) for the optic-nerve / three-camera metaphor.

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
