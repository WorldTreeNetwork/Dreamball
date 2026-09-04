# 2026-08-06 — Rust is canonical for wire types; Zig is the build system

Sprint: epic Dreamball-y4t (IdentiKey substrate port) · Significance: HIGH ·
Beads: [Dreamball-y4t.3](#) (decision), Dreamball-y4t.9 (build scoping),
Dreamball-y4t.10 (this ADR) ·
**Supersedes:**
[zig-canonical-supersedes-json-schema](./2026-06-25-zig-canonical-supersedes-json-schema.md)
(which itself superseded D-018,
[json-schema-canonical](./2026-04-25-json-schema-canonical.md)) ·
**Preserves verbatim:**
[hermetic-musl-default-linux](./2026-05-24-hermetic-musl-default-linux.md) ·
Related: [codegen-spike-findings](./2026-04-28-codegen-spike-findings.md) ·
[archiform-registry](./2026-04-25-archiform-registry.md) ·
[wasm-size-budget-dev-velocity-bump](./2026-06-28-wasm-size-budget-dev-velocity-bump.md)

## Preface — this is the third change of canonical medium

A reader deserves the honest version up front. The canonical source for
wire-type field shapes has now moved three times:

| Date | Canonical medium | Why it changed |
|---|---|---|
| pre-2026-04-25 | Zig (`tools/schema-gen/main.zig` string bodies) | — |
| 2026-04-25 (D-018) | JSON Schema | federation via aspects.sh needed a language-neutral authoring format |
| 2026-06-25 | Zig types (`src/protocol*.zig`) | aspects.sh was unbuilt; JSON Schema could not express defaults/methods/exact types; the inversion never shipped |
| **2026-08-06 (this ADR)** | **Rust (`serde` + `schemars` derives)** | the generator that would have made Zig-canonical real was never built, and the substrate itself is moving to Rust |

Three changes in four months is a bad smell, and the right response is
not to pretend otherwise. Two things are worth noticing about the
pattern:

1. **The first two changes were both changes of *intent*, not of code.**
   D-018 never shipped a schema→output generator. The 2026-06-25 revert
   never shipped a Zig→output generator either. In both cases the
   declared canonical medium was aspirational: the actual mechanism
   keeping representations in sync was, and still is, a
   byte-equivalence gate over hand-maintained strings. We have changed
   the label on the box three times and never changed what is in the
   box.
2. **This change is different in kind**, and the reason is stated in
   "Why this one is more likely to stick" below: the mechanism exists
   before the decision, not after it. That is the claim to hold this
   ADR to.

## Context

### The Zig comptime generator was never built

The 2026-06-25 ADR's decision was "generate every representation from
the Zig types via comptime reflection (`@typeInfo`)." That generator is
bead `Dreamball-m97.2`, and it is still open. Verified against the repo
on 2026-08-06:

- `grep -rn "@typeInfo" tools/schema-gen/` returns **nothing**. There is
  no reflection anywhere in the generator tree.
- `gen_ts.zig`, `gen_valibot.zig`, `gen_cbor.zig` each write a hardcoded
  `BODY` constant — the emitted text is a string literal lifted from the
  legacy generator, not derived from any source of truth.
- `gen_zig.zig` (44 lines) is still a deliberate no-op that logs
  `generator-skipped`.
- The vendored `schemas/*.json` are held consistent by a blake3 pin plus
  a byte-equivalence gate — i.e. by *checking* that two hand-maintained
  artifacts agree, not by deriving one from the other.

So Zig-canonical has never actually shipped as designed. What shipped is
scaffolding — orchestrator, provenance headers, pin verification,
structured logging — around a set of hand-maintained strings. Every
field change today is a manual edit in five places behind a gate that
tells you when you got it wrong, which is a linter, not a generator.

### In Rust the generator is off the shelf

`serde` (derive-based (de)serialization) and `schemars` 1.2.2 (JSON
Schema emission from the same type definitions, ~378M downloads, last
published 2026-07-27) do, as a maintained dependency, exactly what
`m97.2` was going to build by hand: read the type definition at compile
time and emit a representation from it. There is no comptime-reflection
project to fund, no equivalence gate to maintain for the shapes those
crates cover, and no drift window between "edit the type" and "update
the four copies."

### The substrate is moving to Rust anyway

Epic `Dreamball-y4t` replaces the hand-rolled Zig crypto/envelope
substrate with the Blockchain Commons / IdentiKey Rust stack:
**bc-envelope 0.43.0** and **dcbor 0.25.2** (both pinned in
`identikey-protocol/Cargo.toml` today), plus `recrypt-wire::identity`,
`pqcrypto-mldsa`/`fips204`, and `identikey-wallet`. That epic exists
because Dreamball wrote a second implementation of primitives IdentiKey
already owned: `dcbor.zig` (861 LOC), `envelope.zig` (2,593 LOC),
`identity_envelope.zig` (938 LOC), `key_file.zig`, `signer.zig`,
`ml_dsa.zig` plus ~4.5K LOC of vendored liboqs C.

That duplication is precisely what CLAUDE.md's cross-runtime invariant
already forbids — "If you find yourself writing a second hand-maintained
implementation of a wire type, stop" — and the crypto layer has been
quietly violating it since sprint-001. The rule was written for wire
types and never extended to the substrate underneath them.

Once bc-envelope *is* the envelope, keeping the field shapes canonical
in Zig would put the type definitions in one language and the encoder
that must honour them in another — reintroducing, at the layer below,
exactly the two-implementation tax the epic exists to pay off.

### Downstream consumption

`mjolnir` (`/Users/dukejones/work/IdentiKey/mjolnir/native/`) already
hosts a Rust cargo workspace — `mjolnir_protocol`, `mjolnir_api`,
`mjolnir_gateway`, `mjolnir_client`, `mjolnir_guest_agent`. A Rust
type crate is a direct `Cargo.toml` dependency for that computational
fabric. A Zig type crate is not consumable there at all without an FFI
boundary and a hand-written binding layer.

## Decision

**1. Rust is the canonical source for wire types.** The canonical field
shapes live in Rust structs/enums with `serde` and `schemars` derives.
Every other representation — TypeScript types, Valibot validators, the
TS CBOR codec, JSON Schema, Cypher DDL — is generated from them.

**2. dCBOR encoding is canonical in the Blockchain Commons crates.**
`dcbor` 0.25.2 owns deterministic-CBOR semantics (map ordering, integer
width, bytes-vs-text); `bc-envelope` 0.43.0 owns envelope framing. We
consume them; we do not reimplement them. The cross-runtime invariant's
*substance* is unchanged: every runtime reproduces identical bytes for
the same logical value, enforced by golden vectors — those vectors are
being extracted into language-neutral fixtures under `Dreamball-y4t.8`
precisely so they survive the language change as an independent check.

**3. JSON Schema stays a generated artifact.** No change from
2026-06-25 in status, only in producer: `schemars` emits it instead of a
hypothetical Zig reflector. `x-cbor` / `x-zig` extension keys stay
retired. `schemas/*.json` remain outputs and equivalence fixtures, never
hand-authored.

**4. Zig remains the build system, scoped precisely** (detail in
`Dreamball-y4t.9`):

- **KEEP — task orchestrator.** `zig build test | smoke | wasm` keep
  working as the stable command facade, shelling out to `cargo` and
  `bun`. `build.zig` already carries ~25 steps that CI and muscle memory
  depend on. One stable command surface over three toolchains is the
  cure for build-system sprawl, not the cause of it.
- **KEEP — cross-compilation and linking** via `cargo-zigbuild` 0.23.0.
  This is where Zig is genuinely better than the alternatives, and it is
  what lets us keep the next point.
- **DROP — Zig compiling protocol artifacts.** Once the core is Rust,
  `build.zig` orchestrates and `cargo` compiles.
- **NOT DECIDED HERE.** The wasm action *host* (`src/wasm-host/`, ~2.5K
  LOC) is a wasm runtime host rather than protocol, and may stay Zig
  indefinitely. That is a separate question.

**5. [hermetic-musl-default-linux](./2026-05-24-hermetic-musl-default-linux.md)
survives this ADR verbatim and is explicitly reaffirmed.**
Static-musl-by-default on Linux was never a fact about Zig-the-language;
it was a fact about which libc our Linux artifacts link against, and
`cargo-zigbuild` keeps Zig as the linker driver that provides it. Linux
release binaries stay statically linked against Zig's bundled musl, with
zero system libc/crt dependency, and the Zig-0.16-LLD-vs-GCC-16
`.sframe` toolchain skew stays permanently sidestepped. The known
`cargo-zigbuild` caveat (issue #231, static *glibc* with an explicit
`--target`) does not bite us because musl is already the default.
`-Dtarget=native` remains the documented opt-out.

## Why this one is more likely to stick

The previous two changes both declared a canonical medium whose
generator did not exist, and then did not build it. D-018 needed a
JSON-Schema→everything generator; it was never wired. 2026-06-25 needed
a Zig `@typeInfo`→everything generator; `m97.2` sat open for six weeks
and is being dissolved by this ADR rather than completed.

The distinguishing property of this decision is that **the mechanism
ships before the decision does**:

1. `serde` and `schemars` are published, versioned, widely deployed
   crates. There is no build step between deciding and having.
2. The canonical medium and the substrate are now the *same language*.
   The previous arrangements always had a seam — the canonical medium
   sat in one place and the code that had to obey it sat in another, and
   the seam is where the hand-maintenance accumulated. Rust types
   feeding Rust encoders have no seam.
3. The decision is downstream of a commitment already made for
   independent reasons (epic `Dreamball-y4t`, adopting bc-envelope). It
   is not a speculative bet on a future need — unlike D-018's aspects.sh
   federation premise, which was betting on a system that still does not
   exist.

That is the case. It is not a guarantee; see Consequences.

## Alternatives considered

1. **Build the Zig `@typeInfo` generator (`m97.2`) as designed, keep
   Zig canonical.** Rejected. It is real, unfunded engineering to
   reproduce what `serde` + `schemars` give for free, and it would land
   *after* the substrate has moved to Rust — meaning the canonical types
   would live in a language that no longer compiles the encoders. Six
   weeks of the bead sitting open is also evidence about revealed
   priority.
2. **Keep Zig canonical for field shapes; use Rust only for the
   envelope substrate.** Rejected — this is the two-implementation tax
   restated. Type definitions in Zig, encoders in Rust, kept in sync by
   a byte-equivalence gate: precisely the drift-prone half-state that
   both previous ADRs were trying to escape.
3. **Rewrite everything in Rust, including the build.** Rejected as
   over-reach and as a real regression. Dropping `build.zig` would cost
   the ~25-step stable command surface CI depends on, and dropping Zig
   as the linker driver would forfeit
   [hermetic-musl-default-linux](./2026-05-24-hermetic-musl-default-linux.md)
   and reopen the GCC-16 `.sframe` breakage. Zig earns its keep at
   orchestration and linking; it does not need to also own the types.
4. **CDDL as canonical.** Rejected again, for a sharper reason than in
   2026-06-25: Blockchain Commons publishes CDDL for Gordian Envelope,
   so the temptation is real — but adopting it as *canonical* would put
   our source of truth upstream of a spec we do not control while the
   crates we actually link (`dcbor`, `bc-envelope`) are the operative
   authority. CDDL stays attractive as a generated conformance artifact
   (bead `Dreamball-nq1`), the same status JSON Schema holds.
5. **JSON Schema canonical (D-018 again).** Rejected — the
   expressivity argument from 2026-06-25 is unchanged and applies to
   Rust as it applied to Zig. Rust types carry defaults, methods, and
   exact widths that JSON Schema cannot hold; generation must flow
   lossy-downward from the expressive medium. **The most-expressive-medium
   principle from the superseded ADR is not being repudiated — it is
   being applied again, to a language that has an off-the-shelf
   projector.**

## Consequences

- The 2026-06-25 ADR gets a superseded-by banner. D-018 stays superseded
  (its banner now points through a chain; that is accurate and should
  not be flattened).
- **`Dreamball-m97.2` is dissolved, not deferred.** The Zig
  comptime-reflection generator will not be built. Its parent epic
  `Dreamball-m97` is complete on its substantive half (all five
  nested-envelope decoders shipped, 7/8 children closed); only the
  generator child remains, and it is being closed as obsolete.
- The hardcoded-`BODY` generators in `tools/schema-gen/` are on a
  deletion path, replaced by Rust-side derives plus whatever projectors
  survive (next bullet). The pin + byte-equivalence gate stays in force
  until the Rust path reproduces the same outputs — golden vectors
  (`Dreamball-y4t.8`) are the gate, not trust.
- **Named risk: not every generator is a `schemars` derive.** `serde` +
  `schemars` cover serialization and JSON Schema. They do **not** cover
  the per-archiform projectors this repo also runs — `gen_cli`,
  `gen_ts_client`, `gen_mcp_tools`, `gen_capabilities`, `gen_cypher` —
  which emit a CLI surface, an Eden client, MCP tool definitions,
  capability descriptors and Cypher DDL. Those are bespoke emissions
  with no off-the-shelf equivalent, so this ADR's "the generator is off
  the shelf" argument is **true for the schema layer and unproven for
  the projector layer**. If the projectors turn out to need a
  hand-written compiler in Rust (a design being spec'd separately), we
  will have moved the hand-written-generator problem rather than
  eliminated it — for those targets. That would not invalidate the
  decision, because the substrate-unification and downstream-consumption
  arguments stand on their own, but it *would* mean the strongest
  headline claim was overstated. Say so plainly if it happens.
- **Second risk: byte-for-byte continuity is not free.** Our hand-rolled
  `dcbor.zig` and `envelope.zig` may not agree with `dcbor` 0.25.2 /
  `bc-envelope` 0.43.0 on every edge case. Where they disagree, the
  crates win and the wire format changes. `Dreamball-y4t.8` (extract
  golden vectors into language-neutral fixtures) exists to make any such
  change visible and deliberate rather than silent.
- Linux release binaries are unaffected in ABI terms: still static musl,
  still no system libc dependency. CI gains a `cargo` requirement; it
  does not gain a system-toolchain requirement.
- The wasm story is unchanged in principle — one binary, both runtimes,
  host randomness through a single import (ADR-1 in
  `docs/ARCHITECTURE.md`). ADR-1 was never about Zig; it was about a
  single compiled artifact with one host seam. The wasm size budget
  ([2026-06-28](./2026-06-28-wasm-size-budget-dev-velocity-bump.md))
  will need re-baselining against a Rust-compiled core, and
  `Dreamball-8bk` (restore a tight gzip budget) should be re-measured
  after the port rather than before it.
- Docs updated by this change: `CLAUDE.md` ("The cross-runtime
  invariant"), `docs/ARCHITECTURE.md` §2 and §10, and the §13 runbook.

## Migration plan

1. This ADR + a superseded-by banner on
   [zig-canonical-supersedes-json-schema](./2026-06-25-zig-canonical-supersedes-json-schema.md).
2. Update `CLAUDE.md` and `docs/ARCHITECTURE.md` §2 / §10 / §13 so no
   document still asserts Zig-canonical field shapes.
3. Close `Dreamball-m97.2` as obsolete (generator dissolved, not
   deferred); note the dissolution on the parent epic `Dreamball-m97`.
   **Done 2026-09-03:** `m97.2` closed dissolved; parent `m97` closed
   (decoders shipped). Tracker pointer `Dreamball-y4t` now exists in
   this beads db.
4. `Dreamball-y4t.8` — extract golden vectors into language-neutral
   fixtures. This is the gate for everything below it and should land
   first.
5. `Dreamball-y4t.9` — scope `build.zig` to orchestrator + linker; wire
   `cargo-zigbuild`; prove Linux output is still static musl.
6. `Dreamball-y4t.4` — port envelope encode/decode onto `bc-envelope`,
   with the golden vectors as the gate.
7. `Dreamball-y4t.5` — delete the Zig crypto substrate and
   `vendor/liboqs` once the Rust path is green.
