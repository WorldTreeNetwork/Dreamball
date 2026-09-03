# 2026-08-07 — Adopt real Gordian Envelope for the signed op log

**Status:** accepted. Decided by the project owner on 2026-08-07
(`Dreamball-y4t.16`); implemented the same day (`Dreamball-y4t.18`) in
`crates/identikey-log` of the `identikey-protocol` repo.

**Supersedes:** the `ball.action` v4 wire format as `src/envelope_v2.zig`
implements it, and the two v4 golden vectors in
`fixtures/goldens/manifest.json`.

## What we were doing

`ball.action` v4 borrowed Blockchain Commons' envelope CBOR tags — `#6.200`
for the envelope, `#6.201` for the leaf — and then diverged structurally from
Gordian Envelope in three ways:

1. A subject-only envelope was `200([201(core)])`: a one-element array.
   Gordian emits `200(201(core))`, and its decoder rejects an array shorter
   than two elements outright.
2. An attribute was a two-element array `["deps", value]`. A Gordian assertion
   is a single-entry map `{predicate: object}` whose predicate and object are
   themselves envelopes, and `'signed'` is a **known value** (the integer 3),
   not the six text bytes `"signed"`.
3. A signature was raw Ed25519 over the literal canonical unsigned bytes.
   Gordian signs the subject's SHA-256 **digest tree**.

The first Rust port (`Dreamball-y4t.1`) reproduced both v4 golden vectors
byte-for-byte on the first attempt — including the deterministic signature and
both blake3 digests, with nothing contorted. The encoder was correct and
self-consistent. But it achieved that on `dcbor`, the deterministic-CBOR codec,
and **not** on `bc_envelope::Envelope`, because `bc_envelope::Envelope` can
never produce those bytes.

## Why we changed it

Difference (3) is not cosmetic, and in an **op log** it is not a detail —
it is the product.

A signature over a digest tree survives **elision**: replacing an assertion
with its own digest leaves every enclosing digest unchanged, so a partially
redacted op still verifies against the author's key. A signature over literal
bytes cannot, because eliding anything changes the bytes it covers.

For a shared, append-only, multi-party log, that is the difference between
being able to hand someone a partially-redacted log they can still verify, and
not being able to. Elision-survivable signatures are the feature an op log most
wants, and we could not have had them on our own format without hand-rolling a
Merkle digest tree — which is the exact category of work this migration exists
to stop doing.

Secondary, and all obtained for free rather than for 1–2K lines of hand-rolled
crypto:

- **The documented capability gap closes.** `docs/PROTOCOL.md` §2.4 and §8
  promise salted elidable attributes, per-attribute digest coverage and
  post-signing elision validity; §4.x marks fields `[salted]`; `VISION.md`
  §7.1's per-slot visibility rests on all of it. A grep for
  `elide`/`elision`/`salt`/`digest` across every `.zig` and `.ts` returned
  nothing. Those sections did not describe bugs — they described a *different
  format* than the one we had implemented. They now describe the real one.
- **Inclusion proofs**, so a holder can prove one assertion against a root
  digest without revealing the rest.
- **Envelope-level interop** with `recrypt` and `identikey-wallet`, rather than
  merely codec-level.
- **The BC ecosystem**: UR for QR/sneakernet, the envelope CLI, `format` and
  `tree` rendering.

## What it cost, and why that was acceptable

Every golden vector changed at once, and `docs/PROTOCOL.md` needs substantial
rewriting (tracked separately — this ADR does not silently assume it done).

The re-baselining objection was already answered on 2026-08-05 and is recorded
in `fixtures/goldens/README.md`: there are no consumers of this application,
including ourselves; there is no live data signed against these bytes; and
where our bytes differ from a mature reference implementation, the reference
wins and we re-baseline with the reason recorded. That posture was adopted for
byte-level bugs. This is the same argument at format level.

## The shape we landed on

```text
unsigned:                          signed:
                                   {                       ← wrap
  {core map} [                       {core map} [
    "deps": Bytes                      "deps": Bytes
    "timestamp": Date                  "timestamp": Date
  ]                                  ]
                                   } [
                                     'signed': Signature
                                   ]
```

The core map — `hlc`, `body`, `kind`, `type`, `actor`, `parent-hashes`,
`format-version` — is unchanged, and its bytes are byte-identical to before.

**Signing wraps first, and that is load-bearing.** `Envelope::add_signature`
alone signs `subject().digest()`; on an unwrapped op that would cover the core
map and leave `deps`, `nacks`, `target-fp` and `timestamp` *outside* the signed
region. The pre-Gordian format covered them (it signed the whole canonical byte
string), so wrapping is what **preserves** the old security property while
gaining the new one. `tests/roundtrip.rs::tampering_with_an_assertion_invalidates_the_signature`
is what pins that choice.

`content_hash` stays `blake3(canonical unsigned envelope bytes)` — deliberately
*not* the envelope's own SHA-256 digest. The digest is the structural,
elision-stable identity Gordian uses internally; `content_hash` is the log's
DAG identity, and DAG links are Blake3 throughout this stack. Both exist and
answer different questions. Its **value** changed for every op, since the bytes
it is taken over changed.

## How we know it worked

The decisive evidence is not that the tests pass. Every test passed against the
lookalike format too — round-tripping, rejection and tamper-detection are
properties any self-consistent encoder has, which is exactly why building
something Gordian-*shaped* went undetected.

`crates/identikey-log/tests/elision.rs` is the test that cannot pass on a
lookalike. It signs an op, elides an assertion, and asserts the mechanism (the
envelope digest is bit-identical), the consequence (the author's signature
still verifies), and — because a test where everything trivially verifies would
be worse than no test — that substituting a non-elided assertion still breaks
verification, that a redacted op does not verify against the wrong actor, and
that eliding the signature itself yields "unsigned" rather than a silent pass.

## Consequences

- `fixtures/goldens/manifest.json`'s two v4 `ball.action` entries are
  re-baselined and now carry `superseded_bytes_hex` / `superseded_blake3` /
  `superseded_by`. They are **pinned hex**, produced by the Rust crate; the Zig
  encoder cannot produce them and will not be taught to, because the Zig
  substrate is what the port replaces. The generator still runs the Zig encoder
  live and asserts it equals the *superseded* values, so the record is
  self-checking. See `fixtures/goldens/README.md`.
- `docs/PROTOCOL.md` still describes the pre-Gordian shape.
- The crate's former hand-rolled `fips204` seam is gone: a post-quantum
  signature is now just another variant of the same tagged `Signature` object,
  via `bc-components`' `pqcrypto` feature.
- `Dreamball-y4t.6` (turn on elision, salting and inclusion proofs) is
  substantially delivered on the Rust side by this change.

---

## Addendum, same day: the permanent wasm constraints of adopting Gordian

`Dreamball-y4t.20`. The bullet above — "the crate's former hand-rolled
`fips204` seam is gone" — was wrong, and wrong in a way worth recording
rather than quietly editing. It reversed `Dreamball-y4t.2`, which chose
`fips204` over `pqcrypto-mldsa` *specifically because* `pqcrypto-mldsa` is a
PQClean C binding that cannot target the browser. `identikey-log` built for
`wasm32-unknown-unknown` unmodified before the rewrite and did not build at
all after it. Nothing caught this, because nothing was watching: the
repository had no CI.

The general lesson is not "be careful". It is that **adopting Gordian Envelope
imposes three permanent constraints on any crate that must run in a browser**,
and they will be met by every such crate, not just this one:

1. **`bc-components/pqcrypto` must be off.** It is on by default and reachable
   through `bc-envelope`'s defaults. It pulls PQClean C, which needs a hosted
   stdlib. Not a flag problem; WASI works, the browser does not.
2. **Both vendored patches from `Dreamball-y4t.13` are required** —
   `vendor/bc-shamir` (force-enables `bc-crypto/secp256k1`, unavoidable
   downstream because `sskr` is non-optional in `bc-components`) and
   `vendor/dcbor` (chrono's `wasmbind` pulls wasm-bindgen). The second is the
   dangerous one: it **compiles fine** and silently adds seven host imports.
3. **Both `getrandom` majors must be routed to one custom backend** — 0.3 via
   `bc-rand`, 0.2 via `chacha20poly1305` — using `custom`, never `js`, since
   `js` re-imports wasm-bindgen and undoes (2).

A build that merely succeeds does not demonstrate (2). The invariant that does
is the **import section**: exactly one entry, `env.getRandomBytes`. That is
now a CI gate in `identikey-protocol` (`scripts/check-wasm-imports.sh`,
`.github/workflows/ci.yml`), along with a negative control asserting that
`--features pqcrypto` still *fails* for wasm32 — so if upstream ever ships a
no-std PQ path, we find out by that step turning green rather than by guessing.

### The cost that was not obvious until it was measured

Turning `pqcrypto` off does not merely disable PQ verification. `bc-components`
gates the `Signature::MLDSA` **enum variant**, and its CBOR decoder gates the
arm recognising tag `40105`. So a build without the feature cannot *parse* a
PQ-signed envelope — it fails at decode, not at verify. **That is an interop
split between runtimes**: if any actor signs with ML-DSA, browser peers cannot
read those ops at all.

ML-DSA-87 *verification* itself is not lost — the `fips204` seam is restored
and compiled unconditionally, in every configuration including wasm, and both
configurations route through it so native and browser can never diverge. The
missing capability is Blockchain Commons' representation, not the maths.

Closing the split is possible (parse the `#6.40105` tagged CBOR — just
`[level, bstr]` — into our own signature type and verify it with the existing
seam) and is filed as debt rather than done silently, since it changes a public
type. See `identikey-protocol/docs/pq-and-wasm.md` for the full analysis.
