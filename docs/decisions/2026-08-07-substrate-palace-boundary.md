# 2026-08-07 — The substrate/palace boundary: four destinations, not two

Sprint: epic Dreamball-y4t (IdentiKey substrate port) · Significance: HIGH ·
Beads: [Dreamball-jie](#) (the audit this ADR writes up),
Dreamball-h7s (archiform repo), Dreamball-etk (Memory Palace repo),
Dreamball-y4t.1 (op-log crate) ·
**Unblocks:** Dreamball-y4t.4 (port envelope encode/decode onto bc-envelope) ·
Related: [rust-canonical](./2026-08-06-rust-canonical.md) ·
[archiform-registry](./2026-04-25-archiform-registry.md) ·
[capability-provider-model](./2026-05-31-capability-provider-model.md) ·
[palace-mint](./2026-04-22-palace-mint.md)

## Context

### The leak list, and why listing leaks was the wrong frame

`Dreamball-jie` opened as a cleanup bead: four named places where the
protocol core knows about one application (the Memory Palace).
`src/archiform.zig` `@embedFile`s `schemas/memory-palace-0.1.0.json`
*into the protocol binary*. Archiform types are hand-written into
`src/protocol_v2.zig`. Palace verbs live in the protocol CLI. A ~600 MB
ONNX model runtime sits inside the otherwise-generic
`dreamball-server`. The audit found two more the bead had not named:
`src/root.zig` re-exports `memory-palace/mythos-chain.zig` from the
**library root** — the backwards dependency arrow made public API — and
`tools/schema-gen/` hardcodes the palace schema, so core codegen cannot
run without one application's schema present.

The sizing is the part that makes it urgent rather than tidy: the Memory
Palace composition is roughly **14.9K LOC against a protocol core of
roughly 13K**, in the same tree, with the dependency arrow pointing
backwards.

Framing that as a list of leaks invites the wrong remedy — move each
offending symbol from the "core" pile to the "palace" pile and declare
victory. That framing is too coarse and would mis-route the port.

### The root cause is a MISSING TIER, not carelessness

This is the insight this ADR exists to preserve.

Dreamball has two named places for a type to live: **core** and
**application**. Anything that is neither gets filed as core — because
core is where the Zig lives. There is no third directory, no third
build target, no third repo. So the filing decision is not really being
made; gravity is making it.

Look at what fell in: `Layout`, `Object3d`, `OmnisphericalGrid`,
`TrustObservation`, `Memory`. None of these is protocol substrate — none
of them is needed to encode, sign, or verify a DreamBall. But none of
them is *one application's* domain either. They are domain types at a
tier above the wire format and below any particular product. Spatial
layout is not the Memory Palace's private concern; neither is a trust
observation.

**That tier is exactly what `Dreamball-h7s` names *archiform*, and it
does not yet exist as a place to put a file.** So the types fall into
core by gravity, and then a later reader — reasonably — concludes that
the core is domain-polluted and someone was careless. Nobody was
careless. The filing system had two drawers and needed three.

The consequence for the port is direct and is the reason this ADR blocks
`Dreamball-y4t.4`: **porting to Rust without naming the tier re-creates
the gravity well in Cargo**, where it is harder to unwind. A misfiled
Zig struct is a `git mv`. A misfiled type inside a published crate,
depended on by `mjolnir` and by whatever else consumes
`identikey-protocol`, is a semver event. We would carry the same mistake
into a medium with a much higher cost of correction, and we would carry
it *deliberately*, having already seen it.

## Decision

### 1. Five destinations, and every type gets routed to exactly one

Not "substrate vs palace". The buckets are:

| # | Destination | What goes there |
|---|---|---|
| 1 | **The Rust core** (`identikey-protocol`) | Envelope, signing, fingerprints, dCBOR, `DreamBall`, `Timeline`, `Triple` — what you need to encode/sign/verify. |
| 2 | **The archiform repo** (`Dreamball-h7s`) | The missing tier. Domain types that are not one application's domain: `Layout`, `OmnisphericalGrid`, `TrustObservation`, `Memory`. |
| 3 | **The identikey op-log crate** (`Dreamball-y4t.1`) | Signed append-only action-log machinery, which is IdentiKey's concern and not Dreamball's. |
| 4 | **A Memory Palace sister repo, in TypeScript** (`Dreamball-etk`) | The palace: its types, its verbs, its CLI, its bridges. |
| 5 | **Delete** | Types whose only remaining consumer is a mechanism we have already dissolved. |

Of `protocol_v2.zig`'s 661 lines: ~120 to the core, ~230 to the palace
repo, ~40 to archiform, ~90 deleted outright. `protocol.zig` ports
almost entirely, with two deletions.

Bucket 5 is not a rounding error and should be spent before anything is
ported. Every line deleted is a line not translated, not reviewed in a
second language, and not carried on a crate's public surface.

### 2. The Memory Palace goes to its own TypeScript repo, not a second Rust crate

The obvious-looking move — palace becomes `dreamball-palace` in the
Cargo workspace — is wrong, for three reasons, and the third is the one
that matters.

**It is already TypeScript.** The palace is ~85% TS today. Its Zig half
is ~5,750 LOC (`src/cli/internal/*.zig` at 5,305, plus
`src/cli/generated/palace_*.zig` at 358 and `src/cli/palace.zig` at 91)
and those files are **thin shells over bun bridges** —
`src/lib/bridge/palace-*.ts` does the actual work. Porting a CLI shell
to Rust so that it can keep shelling out to Bun would be the most
expensive available mistake: maximum translation cost, zero behaviour
gained.

**It would re-import the coupling we are paying to remove.** A palace
crate in the same workspace is one `Cargo.toml` line away from
depending on core internals again, and the compiler will not stop it.
Repo separation is the enforcement mechanism; module separation is a
convention.

**It would falsify the archiform layer.** The acceptance test for
archiform is: *a consumer can author a type without the substrate's
language.* That is the whole promise — the open type system of
`docs/VISION.md` §17, the reference-types-are-not-special commitment of
§9.1 guardrail 2. If our own flagship consumer needs a Rust crate in
our workspace to exist, then the open path is a fiction and we have
proved it ourselves. The Memory Palace being a TypeScript repo that
depends only on published artifacts is not a concession — **it is the
proof obligation.** If it turns out to be impossible, the archiform
layer has failed and we should learn that from the palace rather than
from a stranger.

### 3. `Timeline.palace_fp` becomes `subject_fp`

(`Dreamball-y4t.12`.) A field in the substrate named after one
application is the leak in its purest form: not a dependency, just a
name, which is why it survived every dependency audit. `Timeline` is
generic; the field is the fingerprint of whatever the timeline is
*about*. Rename before the port, so the Rust type is born clean and no
serde alias is ever needed.

### 4. `DreamBallType` lands in Rust as an OPEN enum

`src/protocol.zig:21` defines a closed six-variant enum: `avatar`,
`agent`, `tool`, `relic`, `field`, `guild`. Ported literally, that is a
closed Rust enum in the substrate, and every consumer type is then
either one of our six or unrepresentable.

That is precisely what `docs/VISION.md` §9.1 guardrail 2 warns about —
"if our reference types stay special-cased monolithic code while third
parties get 'the open path,' the open path is a fiction." A hardcoded
closed enum in the substrate *is* the privileging. So:

```rust
pub enum DreamBallType {
    Avatar, Agent, Tool, Relic, Field, Guild,
    Other(String),   // ← load-bearing
}
```

The six named variants stay, because they are the reference
implementation and deserve ergonomics. `Other(String)` is what makes
them a reference implementation rather than an exception. Round-tripping
an unknown type string must be lossless.

### 5. Two corrections to the analysis this ADR is written up from

Both were flagged in `Dreamball-jie` and are recorded here rather than
quietly fixed, because the audit's other conclusions are load-bearing
for the port and a reader in six months needs a calibrated sense of how
much to trust them.

- **`Triple` is not a palace leak.** `src/protocol.zig:214` is
  `{from, label, to}` — RDF, the most domain-neutral struct in the
  file. It looked palace-y only because `gen_cypher` emitted a `Triple`
  table, and that leak already closed (`Dreamball-9dq`). It stays in the
  core.
- **`Object3d` should be deleted, not ported.** Its own docstring says
  it exists to demonstrate the Zig-canonical authoring pipeline, and
  [rust-canonical](./2026-08-06-rust-canonical.md) dissolved that
  pipeline. It is a demo of a dead mechanism with a golden vector
  attached. (Done: commit `898b9b4`, with the golden preserved as pinned
  hex data so the manifest blake3 is unchanged.)

## Where the analysis was wrong

The audit was right about the shape and wrong about two specifics. Both
errors are of the same kind — it under-checked *production* consumers
while checking test consumers carefully — and both changed real work.

**`ActionKind` was not safely deletable.** The analysis called it "9
hardcoded palace verb strings kept alive by one test and the palace
CLI," and put it in bucket 5. It was in fact **load-bearing in
production substrate**: `envelope_v2.zig`'s `decodeAction`/`encodeAction`
validated v3 action-kind strings against the 9-member set on the v3 wire
path, shared by the CLI, WASM, and `tools/`. Deleting it would have
broken the v3 decode path.

This is a useful error rather than an embarrassing one, because it
surfaced the real question hiding underneath: *does the Rust core need
`ball.action` v3 at all?* That became `Dreamball-y4t.15`, answered no —
and `ActionKind` became removable only once v3 itself was dropped
(commit `18f96f7`). The correct lesson is not "the analysis was sloppy"
but **"deletability is a property of the wire-format decision above it,
not of the symbol."** A type that looks orphaned is often held by a
compatibility path nobody named.

**The `src/archiform.zig` implicit-binding rule has consumers, and they
change the deletion order.** The analysis claimed
`MEMORY_PALACE_IMPLICIT_FP` had no consumers outside `archiform.zig`'s
own tests. It has two, both in palace code:

- `src/cli/internal/mint.zig:297` — genesis mint stamps
  `.archiform_fp = dreamball.archiform.MEMORY_PALACE_IMPLICIT_FP`
- `tools/export-palace-fixtures/main.zig:421` — the same, for fixtures

Neither is a test. That does not save the rule — embedding one
application's schema bytes in the protocol binary is still the leak —
but it changes **when** it can go. The implicit binding cannot be
deleted *before* the palace; it leaves *with* the palace, as part of
`Dreamball-etk`. Ordering, not verdict.

## Alternatives considered

1. **Two buckets: substrate and palace.** Rejected — this is the bead's
   original framing and the reason this ADR exists. It has nowhere to
   put `Layout` or `TrustObservation`, so they land in "substrate" by
   default and the Rust core inherits the pollution. The whole cost of
   the port is paid and the defect survives.
2. **Port everything to Rust first, sort the boundary afterwards.**
   Rejected. It is the maximally expensive ordering: you translate the
   ~90 lines you were going to delete, you translate 5,750 LOC of CLI
   shells that exist to call Bun, and you do the sorting later against
   crate boundaries and semver instead of against a `git mv`. Deletion
   and routing are strictly cheaper before translation.
3. **Palace as a second crate in the Cargo workspace.** Rejected —
   §2 above. Cheap-looking, and it falsifies the archiform acceptance
   test using our own flagship consumer as the counterexample.
4. **Create the archiform tier as a directory inside this repo rather
   than a repo.** Considered seriously; deferred rather than rejected.
   A `src/archiform/` directory would name the tier, which is most of
   the value, and it is much cheaper than a repo. But it does not
   enforce the arrow — nothing stops core from importing it, which is
   exactly how we got here — and `Dreamball-h7s` wants the archiform
   layer publishable to consumers who will never build this repo. The
   directory is an acceptable intermediate step; it is not the
   destination.
5. **Leave the ONNX embedding service in `dreamball-server` behind a
   lazy import.** Rejected — see Consequences. The dependency is
   installed whether or not it is imported; `bun install` pays for it
   either way, and the capability seam that makes it unnecessary
   already exists.

## Consequences

### Already executed against this boundary

This is a live document, not a plan. As of 2026-08-07:

- **`898b9b4`** — type-level deletion pass, pure subtraction, net −129
  lines. Removed `FieldKind`, `palaceInvariants` + `PalaceInvariantError`
  (a function named after one application, in the protocol core),
  `Object3d` + `encodeObject3d`, and 10 of 11 `v2.*` re-export shims.
  `Object3d`'s golden fixture survives as pinned hex **data**, so the
  manifest entry and its blake3 are unchanged.
- **`18f96f7`** — `ball.action` format_version 3 dropped from the core
  (`Dreamball-y4t.15`). `ActionKind` and the v3 encoder left the
  substrate. The v3 encoder was **lifted verbatim** to
  `src/cli/internal/palace_action_v3.zig` rather than deleted, because
  the palace CLI still authors v3 in production compile-time paths — it
  now moves wholesale with `Dreamball-etk`. Five v3 goldens moved to
  `fixtures/goldens/palace-v3-manifest.json`, bytes and hashes verified
  byte-identical.
- **This ADR** — the embedding service is out of `dreamball-server`
  (next section).

### Still open

- **`Dreamball-etk.1`** — remove the Zig palace CLI after the TS verbs
  land. This is the ~5,750 LOC, and it also carries the
  `MEMORY_PALACE_IMPLICIT_FP` consumers above and the `src/root.zig`
  re-export (deliberately deferred there in a comment, not forgotten).
  Note the two files that will *not* appear in any "palace files" work
  order but are why core `verify`/`show` cannot compile without the
  palace: `src/cli/verify.zig` and `src/cli/show.zig` carry palace
  branches (`--as-palace`, `field-kind == palace` routing).
- **`Dreamball-y4t.11`** — partition `fixtures/goldens/manifest.json` by
  destination before the port. Goldens are the gate for
  `Dreamball-y4t.4`; a single undifferentiated manifest cannot tell you
  whether the Rust core is correct, because it also contains vectors
  that are the palace's business.
- **`Dreamball-h7s`** — the archiform repo. Until it exists, the tier is
  named but has no address, and the gravity described above is still on.

### The embedding service is removed from `dreamball-server`

Leak (4) from the bead, executed with this ADR because it depended on
nothing and the seam replacing it was already built.

`dreamball-server` — an otherwise generic protocol server — depended on
`@huggingface/transformers`, which pulls `onnxruntime-node` and `sharp`:
a model runtime, ~600 MB installed, paid for by every `bun install` of
the protocol server whether or not anyone ever calls `/embed`. The
providers lived in `dreamball-server/src/embedding/`.

The capability seam that makes this unnecessary already existed at
`dreamball-server/src/capabilities/text-embed/` — interface, provider
registry, and resolver, built under
[capability-provider-model](./2026-05-31-capability-provider-model.md).
The leak was ~90% closed already; what remained was deleting the
in-process provider and the dependency. Done:

- `src/embedding/qwen3.ts` **deleted** — the in-process ONNX adapter.
- `truncateMrl` **moved** to `capabilities/text-embed/truncate.ts`. It
  was never a property of one model adapter: every provider declares a
  `nativeDim` and the resolver normalizes it through this one path. It
  belongs to the capability.
- `src/embedding/runpod.ts` **moved** to
  `capabilities/text-embed/runpod.ts`, and `src/embedding/` is gone.
  RunPod is a ~120-line dependency-free HTTP client. That is the shape a
  provider is allowed to have inside the server: **a wire adapter, not a
  runtime.**
- The `onnx-local` provider is **out of the registry**. Two remain:
  `mock` (CI) and `runpod` (BYO GPU).
- `@huggingface/transformers` removed from both `package.json` manifests
  (root and `dreamball-server`) and from both lockfiles.

**The rule this establishes:** hosting a model runtime is an application
concern. The substrate declares an interface and binds whatever
satisfies it. A consumer that wants local weights implements
`text-embed/1` in its own process — it does not get to make every
install of the protocol server pay for ONNX. This is the same
substrate/application line the rest of this ADR draws through the Zig,
drawn through the TypeScript server.

**Exit-test note.** Removing the in-process provider removes a
*convenience*, not an exit. Local weights remain reachable — through a
provider you run yourself, against a published interface. The remote
GPU path is unchanged. Nothing that was portable became unportable; a
600 MB default became an opt-in.

**Honest cost.** `DREAMBALL_EMBED_MODEL_PATH` no longer does anything,
and there is currently **no shipped local-weights provider** — the
interface exists, an implementation of it does not. Someone who was
running the server with local ONNX weights must now run a provider
process. That is a real regression in out-of-the-box capability, taken
deliberately: the capability was in the wrong process, and leaving it
there to avoid a migration would have meant every consumer of the
protocol server paid for one application's model.

The AC10 invariant ("the expensive setup runs once") survived the
change, and got stronger. It was never about ONNX; it was about binding
once. It now spies the bound provider's `load()` through the resolver
and asserts **exactly** one call across three requests — where the old
`loadQwen3Model` spy asserted `<= 1` and was satisfied vacuously by zero
in mock mode.

### Gates

`bun run check` → 1968 files, 0 errors. `bun run test:unit --run` →
742/742 passing (49 files). `scripts/server-smoke.sh` → 34 PASS, 0 FAIL,
including the `/embed` assertions (dimension 256, model
`qwen3-embedding-0.6b`, `mrl-256`), which are unchanged because the mock
provider is what the gate binds and always was.
