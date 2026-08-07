# `fixtures/goldens/` — toolchain-neutral golden vectors

This directory holds the toolchain-neutral form of the 20 named golden
vectors that used to live only as ZIG TEST CODE in `src/golden.zig`. It
exists so a from-scratch implementation — concretely, the forthcoming Rust
`bc-envelope`/`dcbor` port (Dreamball-y4t) — can construct the same logical
inputs and compare canonical bytes **without running Zig, or even reading
Zig source, at all**.

## Five files, one partition (Dreamball-y4t.11)

All 20 vectors started life in one flat `manifest.json` (Dreamball-y4t.8).
That was fine as a first cut, but 15 of the 20 were Memory Palace or
archiform fixtures — if they had stayed in the file the Rust core's port
treats as its regression gate, palace fixtures would have become the
substrate's acceptance test, quietly re-cementing the exact boundary the
substrate/Memory-Palace split (epic Dreamball-jie, Dreamball-y4t) exists to
cut. So the 20 vectors are partitioned by destination, per the
Dreamball-jie boundary analysis, into five files:

| file | contents | destined for | gates the core build? |
|---|---|---|---|
| `manifest.json` | `zero_seed`, `memory_connection`, `action_v4_unsigned`, `action_v4_signed` | Rust core (Dreamball-y4t) | **yes** — the only one |
| `palace-v3-manifest.json` | v3-format `ball.action` x3 + `ball.timeline` x2 (Dreamball-y4t.15) | memory-palace repo (Dreamball-etk) | no |
| `palace-manifest.json` | v2-format `palace_field`, `aqueduct`, `element_tag`, `inscription`, `mythos_*` x3 | memory-palace repo (Dreamball-etk) | no |
| `archiform-manifest.json` | `archiform`, `object3d` | archiform repo (Dreamball-h7s) | no |
| `contested-manifest.json` | `layout`, `trust_observation` — **UNRESOLVED**, see the file's own `$comment` | undecided; filed separately on purpose so the split doesn't silently guess | no |

One generator (`tools/export-golden-fixtures/main.zig`) writes all five —
not five separate generators — and the `GoldenDrift` self-assertion against
`src/golden.zig`'s pinned constants (see `writeEntry`) covers every entry in
every file, not just the core manifest's. Every `bytes_hex`/`blake3` was
verified byte-for-byte identical across the move.

## Format

`manifest.json` is `{ "$comment": ..., "entries": [...] }`. Each entry:

| field            | meaning                                                                 |
|------------------|--------------------------------------------------------------------------|
| `name`           | short id, matching the `src/golden.zig` constant name (minus `GOLDEN_`/`_BLAKE3` decoration) |
| `type`           | the `ball.*` wire type string                                            |
| `format_version` | the `format-version` value the Zig encoder puts in the core map          |
| `value`          | **the logical value, as JSON.** This is the important part — it's what lets you construct the same input in Rust without reverse-engineering a Zig struct literal. Byte strings are lowercase hex (`..._hex` keys), never base58 or CBOR-specific encodings. |
| `bytes_hex`      | the FULL canonical dCBOR bytes the Zig encoder produced for `value`, hex-encoded (not just a hash — you can diff these directly against a Rust encoder's output) |
| `blake3`         | Blake3-256 of the raw bytes behind `bytes_hex`, hex-encoded              |
| `note`           | present only where a fixture needs a caveat (see below)                 |

## Regenerating

```
zig build export-golden-fixtures
```

Writes `fixtures/goldens/manifest.json`. The generator
(`tools/export-golden-fixtures/main.zig`) re-encodes every fixture through
the same Zig encoders `src/golden.zig`'s tests call, and asserts its own
output against the `src/golden.zig` constants before writing anything — if
`src/golden.zig` and this manifest ever disagree, the build fails loudly
(`error.GoldenDrift`) rather than silently drifting. Output is fully
deterministic (no timestamps, no hash-map iteration order in the JSON) —
running the generator twice in a row produces byte-identical files.

`src/golden.zig` itself is untouched and still the thing Zig's test suite
gates on; this manifest is a **read-only export**, not a replacement, while
the Zig protocol core is still in service.

## The re-baselining posture — READ THIS BEFORE TREATING A DIFF AS A BUG

**These fixtures are not a migration ratchet**, and `bytes_hex`/`blake3` in
this manifest are **not** "the Zig bytes are authoritative, match them or
fail." That framing was explicitly struck for this work
(Dreamball-y4t.8, re-scoped 2026-08-06) and the same softening applies to
`docs/PROTOCOL.md` §16.7's older "a change that alters a v3 golden is a
bug" language, which predates this decision.

The reasoning: there are no consumers of this application, including
ourselves. There is no live data anywhere signed against these bytes. So
when a Rust `bc-envelope`/`dcbor` encoder produces different bytes for the
same `value`, the prior is that **our hand-rolled Zig CBOR encoder was
wrong**, not that a mature, independently-specified Rust CBOR/dCBOR stack
is wrong.

Concretely, when you run this manifest's fixtures through the Rust path
and get a diff:

1. **Investigate the diff.** Read both encoders' output byte-by-byte if you
   have to. Common causes to check first: dCBOR canonical map-key ordering
   (length-then-lex, per `docs/PROTOCOL.md`), float encoding (shortest-form
   vs. always-f64), integer width rules, and whether an optional field with
   a default value was included when it should have been omitted (or vice
   versa).
2. **If it's a genuine semantic regression** in the port (the Rust side
   encodes something the spec doesn't call for, or drops a field the spec
   requires) — fix the port. That's the one case where the Zig bytes stay
   authoritative for this fixture.
3. **Otherwise — which is the expected common case — bc-envelope wins.**
   Re-run `zig build export-golden-fixtures` is the wrong move here (it
   will just re-assert the old Zig bytes); instead, replace the fixture's
   `value`/`bytes_hex`/`blake3` in `manifest.json` with the Rust encoder's
   output, and record *why* in that entry's `note` field (or, if `note` is
   already used for something else, extend it). Do not add a `note` field
   that argues the Zig bytes were correct anyway; the whole point of this
   posture is that Zig's `src/golden.zig` also gets corrected once the
   port's encoder is trusted, not preserved as a fossil.

Do not write code (in Rust or anywhere else) that asserts byte-identity
with these Zig-produced vectors as an invariant. Comparability, not
identity, is the property this manifest is for.

## Coverage — what's in these manifests vs. what's only in `src/golden.zig`

All 20 named golden constants in `src/golden.zig` are represented as
manifest entries, across the five files described above. Two
`src/golden.zig` `test` blocks are **not** separate manifest entries because
they aren't fixtures — they're invariant checks over fixtures already
covered above:

- `"C1 negative: a one-byte body perturbation flips content_hash"` — asserts
  that mutating `action_v4_unsigned`'s body changes its `content_hash`. Not
  a new logical value; re-derivable by any implementation that has
  `action_v4_unsigned` and can flip a byte.
- `"AC5: mythos canonical-genesis, canonical-successor, poetic hashes are
  distinct"` — asserts the three `mythos_*` fixtures above hash to three
  different values. Also re-derivable, not a new value.

Every fixture that could be expressed as data, was — including the two
that involve Ed25519 signing (`action_v4_unsigned`, `action_v4_signed`).
Those are **not** excluded as "depends on a secret key": the signing seed
is the public, all-zeros 32-byte test vector `actor_seed_hex` baked into
the fixture itself, and Ed25519 signing (RFC 8032) is fully deterministic,
so any conformant implementation — Rust's `ed25519-dalek` included — must
reproduce the exact same public key and the exact same signature bytes
from that seed. There is nothing in this manifest that "genuinely cannot
be expressed as data."

`fixtures/ml_dsa_87_golden.json` is out of scope for this manifest — it is
owned by other in-flight work and intentionally left alone.
