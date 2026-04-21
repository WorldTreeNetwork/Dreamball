# 2026-04-21 — Presence channel wire format: raw CBOR, session-MAC, no per-frame signing

## Status

Accepted. Paired with `2026-04-21-multiplayer-architecture.md`
(the three-layer architectural decision). This ADR specifies the
exact wire shape of the presence-channel frame — the fast, lossy,
high-frequency transport that carries "where is the wayfarer's
body right now" state.

Landing the wire-shape decision before transport code so we don't
accidentally ship signed pose frames or full dCBOR-envelope
overhead on a 30Hz path.

## Context

The presence channel carries ephemeral state: avatar pose, gaze
target, voice frames (later), "currently holding this object"
flags, pointer/cursor, voxel-scale position. Rate: 10–60 Hz per
peer, typical 30 Hz. Peer count: 2–8 for MVP palaces.

Budget: a WebRTC SCTP data channel tops out around ~1 MB/s sustained
before queuing hurts latency. 30 Hz × 8 peers × N bytes/frame
must fit comfortably under that. With a per-frame byte budget of
100 bytes, a full 8-peer room uses 24 KB/s — a factor of 40 under
the channel limit. With a 4.6 KB ML-DSA signature on every frame,
the same room would need 1.1 MB/s — saturating the channel on
signatures alone, before any actual pose data.

Signing every frame is therefore not just wasteful — it is
incompatible with the channel. The question is how to get session-
level authenticity without per-frame asymmetric crypto.

Standard answer, used by every local-first system that's shipped
real presence (Yjs Awareness, Loro EphemeralStore, Automerge
awareness, Liveblocks, PartyKit): **one signed handshake per session
establishes a symmetric MAC key; every frame thereafter carries a
fast MAC, not a signature.**

## Decision

### Frame format — raw CBOR, no envelope wrapper

The presence frame does **not** use the Dreamball envelope shape
(`#6.200 / #6.201` tags, assertion arrays, etc.). It is a raw
CBOR map under the following schema. Rationale: the envelope
wrapper exists to carry attributes + signatures for content-
addressed signed artifacts. Presence frames are neither signed
nor content-addressed; they're wire-framed throwaway data.

```
{
  0: <uint>,         ; "seq" — monotonic counter per-sender, wraps at u32
  1: h'…8…',         ; "sender" — first 8 bytes of sender's DreamBall fingerprint (tiebreaker only)
  2: <uint>,         ; "timestamp-ms" — sender's monotonic clock millisecond value
  3: {               ; "pose" — OPTIONAL; presence frames MAY be non-pose (e.g. pure voice frame)
    0: [f16, f16, f16],    ; head position (x,y,z) — half-float under the §12.2 exception
    1: [f16, f16, f16, f16], ; head orientation quaternion
    2: [f16, f16, f16],    ; left-hand position (or null-if-absent via f16::NaN sentinel)
    3: [f16, f16, f16, f16], ; left-hand orientation
    4: [f16, f16, f16],    ; right-hand position
    5: [f16, f16, f16, f16], ; right-hand orientation
  },
  4: <bstr>,         ; OPTIONAL: "holding" — fingerprint-prefix of object currently gripped
  5: <bstr>,         ; OPTIONAL: "gaze" — fingerprint-prefix of object currently looked-at
  6: <bstr>,         ; OPTIONAL: "voice" — opaque bytes, a single Opus frame or similar
  7: <uint>,         ; OPTIONAL: "ttl-ms" — consumer may evict frame from state after this
  15: h'…16…',       ; "mac" — 16-byte ChaCha20-Poly1305 or BLAKE3-MAC tag over keys 0–7
}
```

**Integer keys, not strings.** CBOR integer-keyed maps save bytes
on every frame. Keys 0–7 are the documented semantic slots; 15 is
the MAC; 8–14 reserved for future low-frequency additions; ≥16
reserved for future growth.

**Half-floats everywhere.** Pose precision at half-float (1 part
in ~2048 over the typical room-scale range) is well inside
perceptual just-noticeable-difference for VR head and hand
tracking. Full-float pose is wasteful by 2×.

**Fingerprint-prefix, not full fingerprint.** 8 bytes of Blake3
prefix for the sender and 8–16 bytes for referenced objects. The
handshake establishes the full-fingerprint mapping for the session;
frames only need enough to disambiguate. A collision at 8 bytes
within one session is a 2⁻³² event — acceptable for a lossy
channel with TTL eviction.

**Estimated frame sizes.**
- Pose-only (keys 0, 1, 2, 3, 15): ~78 bytes typical.
- Pose + holding: ~87 bytes.
- Pose + gaze + holding: ~96 bytes.
- Voice-frame only (key 6 with ~60-byte Opus frame): ~90 bytes.
- Pose + voice: ~150 bytes (still well under budget).

### Session MAC, not per-frame signature

On room entry, each peer performs a signed handshake
(`jelly.session-handshake` envelope, full `jelly.dreamball`-style
signed; spec'd in the multiplayer PRD). The handshake exchanges:

1. Each peer's DreamBall fingerprint + hybrid pubkeys (Ed25519 +
   ML-DSA-87).
2. A per-session ephemeral X25519 keypair contribution (ephemeral
   only — does NOT provide PQ forward secrecy; documented
   limitation, closed by the deferred BeeKEM work in the paired
   ADR).
3. A random session nonce.

The session MAC key is derived as:

```
mac_key = BLAKE3_derive_key(
  "Dreamball Presence Session MAC v1",
  x25519(my_ephemeral, their_ephemeral)
    || session_nonce
    || guild_fp
    || room_fp
)
```

One `mac_key` per (local-peer, remote-peer) pair. A peer in an
8-person room maintains 7 `mac_key`s. Every outbound frame is
MAC'd once per destination peer and broadcast. (This is where a
BeeKEM group key would become valuable — one MAC per frame instead
of N-1. Tracked in the paired ADR as deferred.)

**MAC algorithm.** BLAKE3 keyed hash, truncated to 16 bytes.
Rationale: BLAKE3 is already in the Dreamball crypto surface (Zig
core, WASM export). ChaCha20-Poly1305 would also work but
introduces a second primitive for no security benefit on a
keyed-MAC use case.

**MAC input.** The CBOR-serialised map with key 15 omitted, plus
the `seq` and `sender` fields (these are also in the map but
signing them outside the map-serialisation removes ambiguity if
CBOR canonicalisation ever drifts). Concretely:

```
mac_input = seq_u32_be || sender_prefix_8 || cbor_encode(map_without_key_15)
mac_tag = BLAKE3_keyed_hash(mac_key, mac_input)[:16]
```

Receiver verifies the MAC using its stored `mac_key` for that
sender.

### Replay defence

Per-sender monotonic `seq` (u32, wraps after ~4B frames = ~4 years
at 30 Hz per sender; a session will never reach this). Receiver
tracks the highest `seq` seen from each sender and drops frames
with `seq ≤ last_seq`. Window is not needed because presence is
loss-tolerant — an out-of-order frame is indistinguishable from a
dropped frame at the receiver's rendering layer.

**Clock-skew window.** Receiver rejects frames whose `timestamp-ms`
differs from local clock by more than ±30 seconds. Broader than
strictly needed for anti-replay; tight enough to bound session key
abuse if a key leaks.

### TTL eviction at the receiver

Each receiver maintains per-sender state:
- `last_pose` (last-received pose)
- `last_holding`, `last_gaze`, `last_voice`
- `last_received_ts` (wall-clock)

If `wall_clock - last_received_ts > 5000ms` (5 seconds), the sender
is treated as "away" — their avatar greys out, their pose locks
at last-known. Server is notified via WebRTC state callback; if
the WebRTC channel itself dies, the sender disappears.

This is the Loro-EphemeralStore TTL pattern applied to our frame.

## Security posture (explicitly documented limitations)

**What the session MAC protects against:**
- External observer forging pose/voice frames (requires `mac_key`
  which only session peers have).
- External observer modifying frames in flight (MAC covers all
  semantic bytes).
- Replay of old frames from a logged session (per-sender
  monotonic `seq` + clock-skew window).

**What the session MAC does NOT protect against:**
- A *malicious peer inside the session* forging frames claiming to
  come from another session peer. MAC is a shared symmetric
  secret per (local, remote) pair — only pairwise authenticity.
  For 3+ peer rooms this means peer A can forge a frame claiming
  to come from peer B by MAC'ing with the A-to-C key (which C has,
  but C should also have a separate B-to-C key — so C detects
  the forgery). **Therefore**: every receiver MUST verify the MAC
  with the key specific to the claimed sender, not just any
  session key. This is the protocol's load-bearing invariant; a
  bug here defeats all pairwise auth.
- Post-compromise: if a `mac_key` leaks, all frames under that key
  remain forgeable for the session's lifetime. Mitigated by short
  session lifetimes (default 30 min); fully closed by deferred
  PQ-BeeKEM.
- Malicious server/network observer seeing encrypted pose traffic.
  MAC provides authenticity, not confidentiality. **Pose is not
  secret** — anyone on the WebRTC mesh or server relay can read
  it by design. For palaces where pose privacy matters (unclear
  whether any do), encryption could be added by XORing each frame
  with `ChaCha20(mac_key, seq_u64)` — but this is not in the MVP
  spec.
- Denial of service via spam. A peer can saturate the WebRTC
  channel with frames. Receivers cap per-sender frame rate at
  120 Hz (4× the typical 30 Hz); excess is dropped with a UI
  warning that the sender is misbehaving.

## Code implications

- `src/presence.zig` — frame encoder/decoder, MAC compute/verify.
  Exports `encodeFrame`, `decodeFrame`, `verifyMac`.
- `src/lib/multiplayer/presence.ts` — per-session state tracking,
  WebRTC data-channel plumbing, calls into `jelly.wasm` for MAC.
- `jelly.wasm` exports: `presenceMac(mac_key_ptr, input_ptr,
  input_len) → 16 bytes`. Uses existing BLAKE3 path — no new
  crypto primitives.
- **Never** route a presence frame through the `jelly.envelope`
  encode path. Enforced by `presence.zig` living in its own
  module with its own encoder; `envelope.zig` is not imported.

## Consequences

- Presence frames are **not content-addressed**. They have no
  Blake3 identity. They cannot be referenced from any `jelly.*`
  envelope. They are broadcast, rendered, TTL'd, discarded.
- Presence frames are **not stored in CAS**. jelly-server relays
  them if a peer can't WebRTC-connect, but does not persist them.
  An attacker who compromises jelly-server can observe presence
  traffic during their attack window but cannot exfiltrate a
  history.
- Presence frames are **not signed**. A future audit of "who did
  what in the palace" cannot rely on presence data — only on the
  durable `jelly.action` timeline. If a user's pose data matters
  forensically (it probably doesn't), the durable timeline is
  the source of record; presence is perception layer only.
- **Clock requirements.** Peers must have monotonic millisecond
  clocks. Standard everywhere (browser `performance.now()`, Zig
  `std.time.milliTimestamp()`). Wall-clock-skew between peers is
  bounded by the 30-second replay window; palaces spanning
  continents are fine.

## Verification

- Unit test: encode/decode round-trip preserves pose within
  half-float precision (~2⁻¹¹ relative error).
- Unit test: MAC verify passes with correct key, fails with wrong
  key, fails with modified frame.
- Unit test: replay of a frame with lower `seq` is rejected.
- Integration test (minimal spike): two browsers, 30 Hz pose
  broadcast on localhost, measure frame-to-render latency (target
  <50 ms including network + CBOR decode + MAC verify + Threlte
  update).
- Security test: one peer attempts to forge a frame "from" another
  session peer using the wrong `mac_key`. Receiver rejects.

## References

- Paired ADR: `2026-04-21-multiplayer-architecture.md`
- Loro EphemeralStore (v1.8.0 release notes) —
  https://www.loro.dev/llms-full.txt
- Yjs Awareness Protocol —
  https://github.com/yjs/y-protocols/blob/master/awareness.js
- BLAKE3 keyed hash spec —
  https://github.com/BLAKE3-team/BLAKE3-specs
- CBOR integer-keyed map encoding (RFC 8949 §3.1)
- PROTOCOL.md §12.2 (half-float exception), §8 (signature rule)
- `docs/research/vr-crdt-sync-paper-extract.md` — latency budget
  justification (§5.4, Dantas & Baquero)
