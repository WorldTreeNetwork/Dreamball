# Archiform Projector — Design Specification

**Status:** proposed · **Date:** 2026-08-06 · **Supersedes nothing yet** · Related: [D-019 action-manifest](decisions/2026-04-25-action-manifest.md), [D-036 capabilities-schema-vocabulary](decisions/2026-05-31-capabilities-schema-vocabulary.md), [archiform-registry](decisions/2026-04-25-archiform-registry.md), [rust-canonical](decisions/2026-08-06-rust-canonical.md), PROTOCOL §§14–16, PRD FR12/FR13/FR14, NFR4.

> Declare a form once, as signed verifiable data, and every surface is a mechanical projection of it.

---

## 0. The decision in one paragraph

**The archiform IR is the wire format.** An archiform is authored as data, normalized, dCBOR-encoded, sealed in a `bc-envelope`, and content-addressed — and *that sealed IR is the only input any projector ever takes*. There is exactly one Rust type in the archiform position (`Module`), so the static proof burden is `1 × N surfaces`, checked once, in this crate, at its own compile time. Rust derive macros exist but are demoted to one of several **front-ends** (and to a runtime *conformance claim*, `Bind<T>`), never to the source of truth. Rust source is itself one of the projection targets. Every projector is a total match over a **closed kernel grammar with one designated unknown constructor**, extended by **open namespaced profiles and facets**. Failure is never a panic and never a boolean: it is a located, named, human-readable `Gap`, and that same value is the runtime answer to "can I render this?"

This resolves the crux by refusing the axis. The static/provable ↔ dynamic/open tension is a false dichotomy *provided you move the thing being proven*. We do not prove things about user types (impossible — they are authored elsewhere, later, by people without Rust). We prove things about **the analysis**: every projector handles every shape the checker admits, nothing unchecked can reach a projector, and the coverage computation is a total function that always terminates with either a projection or a named gap. That is the strongest true statement available, and it happens to be exactly the statement the three consumers need.

---

## 1. Why not the alternatives

**Derive-macro-first fails FR13 outright.** If a new type requires a Rust struct in someone's crate, then publishing a type requires a Rust toolchain, a crate release, and a rebuild-and-redeploy of every consumer that wants to *accept* it. That is a plugin system with a compiler-shaped gate, not an open type system. The PRD's own risk register names this failure mode (line 183) about Zig; nothing improves by swapping Zig for Rust.

**Trait-per-surface-per-type fails on cardinality.** `impl Project<Codec> for KanbanCard` is `N × 9` impls where `N` is unbounded and unknown at compile time. Dead on arrival for runtime-admitted forms.

**Pure runtime interpretation over untyped manifest JSON fails on correctness.** That is what `tools/schema-gen/gen_cli.zig` does today — `switch (entry.value_ptr.*) { .object => …, else => error.MalformedManifest }` at every access — and it is why the generators that read *open* input (JSON Schema) degenerated into hardcoded string bodies while the ones reading *closed* vocabularies (`x-actions`, `x-capabilities`) are genuinely structural. Verified today: `gen_valibot.zig` 596 lines, `gen_cbor.zig` 720 lines, `gen_ts.zig` 592 lines — overwhelmingly literal bodies; `gen_cli.zig` (729) and `gen_capabilities.zig` (499) are real projectors. 4,845 lines of Zig across ten files covering two vendored schemas.

**So: the object language is open; the metalanguage is closed.** Authors get an open, non-Rust, runtime-extensible type system. We get a fourteen-constructor grammar that `rustc`'s exhaustiveness checker polices across every back-end. Widening the grammar is a deliberate, versioned, N-file compile break — the tax and the safety net are the same mechanism.

---

## 2. Architecture

```
                 front-ends (open, plural, none canonical, outside trust boundary)
   AIR-JSON  ──┐
   .af (later)─┼──▶  lower  ──▶  normalize  ──▶  check  ──▶  Checked<Module>
   #[derive] ──┘                (hash-cons,      (kernel +      │
   schemars  ──┘                 canonical       profiles,      │  seal: dcbor + bc-envelope
                                 order)          budgets)       ▼  ArchiformId = blake3(subject)
                                                          ┌──────────────┐
                                                          │  sealed AIR  │  ← this is the wire format
                                                          └──────┬───────┘
                                                                 │
                    ┌────────────────────────────────────────────┴───────────────────────┐
                    │  projectors: fn(&Checked<Module>, &Opts) -> Out                     │
                    │  Out = live value  (codec, validator, verbs, routes, tools,         │
                    │                     renderer contract, caps, ddl-model, morphism)   │
                    │  Out = String      (TS types, TS client, Cypher, Rust source, MCP)  │
                    └─────────────────────────────────────────────────────────────────────┘
```

### 2.1 Crate layout

| Crate | Contents | Who depends on it |
|---|---|---|
| `archiform-kernel` | `Ty`, `Module`, normalize, `check`, dCBOR ser/de of AIR, `morph`, budgets. **No consumer vocabulary.** `no_std + alloc`. | everyone |
| `archiform-profiles` | independently-versioned profile grammars: `actions` (D-019/D-035), `facets` (FR12), `capabilities` (D-036) | Dreamball, identikey |
| `archiform-seal` | bc-envelope 0.43 sign/verify, `ArchiformId` | everyone that talks to the wire |
| `archiform-project` | the value projectors | per-consumer, feature-gated |
| `archiform-emit` | the text pretty-printers, each over a value projector | build-time tooling only |
| `archiform-derive` | `#[derive(Archiform)]` (front-end) and `#[derive(ArchiformView)]` (conformance claim) | Rust-native consumers |
| `afc` | CLI: `check · coverage · seal · project · emit · diff · call · serve` | authors, CI |
| `archiform-wasm` | wasm32 build of kernel (+ optional projector set) → `@archiform/kernel` on npm | browsers, Bun |

identikey depends on `archiform-kernel` + `archiform-seal` and compiles zero projector lines. mjolnir adds `morph` and the validator. Dreamball adds facets + renderer contract + the emitters. **Nothing in `archiform-kernel` names a ball, a palace, a lens, a channel, a DID, or an op.**

### 2.2 The layering rule that prevents Dreamball over-fit

The critiques of the interpreter and typestate designs both landed the same hit: the *type grammar* was consumer-neutral but the *archiform record* was not — `facets`, `actions`, `capabilities` sat as top-level fields inside the signed, digested, globally-versioned body. mjolnir and identikey would carry Dreamball's vocabulary forever, and a Dreamball vocabulary bump would strand their binaries.

Fix: **profiles are namespaced, independently versioned, and optional.**

```rust
pub struct Module {
    pub air: KernelVersion,               // kernel grammar level
    pub name: FormName,                   // authority/name@semver
    pub defs: Defs,                       // interned, hash-consed type graph
    pub root: TyId,
    pub profiles: BTreeMap<ProfileId, ProfileBody>,  // e.g. "af.actions@1", "af.facets@1"
}
```

`ProfileId` carries its own version. `check` validates a profile body against the profile grammar **if it knows that profile**, and otherwise records `ProfileUnknown { id }` and leaves the body byte-preserved. A `Coverage` query for a surface whose profile is unknown returns `Gap::ProfileUnknown`, not a hard failure. Dreamball can ship `af.facets@2` without touching mjolnir's kernel version.

Actions, facets, and capabilities are the **first three registered profiles**, and their grammars are as closed as PROTOCOL §16 requires — see §5.

---

## 3. The kernel grammar

```rust
/// Closed. Adding a constructor is an ADR, a kernel-version bump, and a
/// deliberate compile break in every projector. `deny(clippy::wildcard_enum_match_arm)`
/// is on in archiform-project.
#[derive(Clone, PartialEq, Eq, Hash)]
pub enum Ty {
    Bool,
    Int   { signed: bool, bits: IntBits },     // validation constraint ONLY — never a codec width
    Float,                                      // f64; dCBOR canonicalizes, it does not forbid
    Text  { len: Range, pattern: Option<PatId> },
    Bytes { len: Range },
    Enum  (SymSet),                             // closed ordered string set
    Opt   (TyId),
    List  { item: TyId, len: Range },
    Map   { key: TyId, val: TyId },             // key restricted by check() to orderable kinds
    Record(RecId),
    Union { tag: Sym, variants: VarSet, open: bool },
    Tagged{ tag: u64, inner: TyId },            // dCBOR tag passthrough
    Ref   (FormRef),                            // cross-module, resolved into the Module closure
    Opaque{ why: OpaqueReason },                // known-unknown: bytes preserved, hashed, uninterpreted
    Unknown{ ctor: u16, body: Cbor },           // ← FORWARD COMPATIBILITY. See §3.2.
}
```

Fourteen live constructors plus `Unknown`. Notes on three that the independent designs got wrong:

**`Int { bits }` is a validation constraint, never a codec parameter.** dCBOR determinism says the *value* selects the encoded width and integral floats reduce to integers. Any projector that treats declared width as an encoding decision produces non-canonical bytes. The codec projector never reads `bits`; the validator does.

**`Float` is supported.** dCBOR canonicalizes floats (smallest exact representation, integral reduction); it does not reject them. The primary consumer stores 3D transforms. A design that gaps on floats gaps on the flagship use case on day one. `Float` is excluded only from the *golden common subset* used for cross-runtime parity vectors, which is a test-corpus scoping decision, not a grammar decision.

**`Union { open }`** — an open union decodes unknown variants into `Opaque` rather than rejecting. This is user-level openness, distinct from the meta-level openness of `Unknown`.

### 3.1 Normalization happens before sealing

`ArchiformId = blake3(canonical dCBOR of the *normalized* Module subject)`. Normalization is:

1. hash-cons the type graph into `Defs` (structurally identical subtrees interned once),
2. canonical ordering of record fields, enum symbols, union variants, and map keys per the dCBOR profile,
3. resolve local names; inline-vs-named is erased,
4. profile bodies canonicalized by their profile grammar (unknown profiles: bytes preserved verbatim).

Consequence: **two authors using two different front-ends who mean the same shape produce the same `ArchiformId`.** This is what makes the front-end layer safely open and what makes the derive macro genuinely non-privileged. It is also what deletes `schemas/.pins/` and the byte-equivalence gate: content addressing becomes intrinsic rather than a linter over hand-maintained artifacts.

The cost, stated plainly: declaration order is *not* preserved in the signed body. Emitters that want author-pleasing field order read a non-normative `af.presentation` profile.

### 3.2 Forward compatibility of the grammar itself

The closed-enum safety argument and the signed-wire-data requirement are in direct tension, and every one of the four independent designs failed here. The resolution:

- `Module.air` is a **kernel level**, monotone.
- A decoder at level *L* meeting a constructor tag it does not know **does not reject the module**. It produces `Ty::Unknown { ctor, body }`, byte-preserving.
- `Unknown` is a real constructor, so every projector must handle it — and every projector handles it the same way: `Gap::UnknownConstructor { ctor, at }`. Codec round-trips it as opaque bytes so `content_hash` survives.
- Therefore: a v1 renderer meeting a v2 form **degrades on exactly the affected subtree**, not on the whole document, and the reason it degrades is displayable.

This is the honest version of forward compatibility: not silent partial interpretation, not whole-form refusal, but *located* refusal with byte preservation.

`check` may be configured to reject `Unknown` where safety demands it — see §7.3.

---

## 4. The projector interface

One signature. `Out` ranges over both live values and source text; there is no build-time/runtime dual path, which is precisely the drift the current generator tree institutionalizes.

```rust
pub struct Checked<T>(T);                 // private field; only `check()` mints one
pub fn check(m: Module, limits: &Limits) -> Result<Checked<Module>, CheckError>;

pub trait Surface: sealed::Sealed + 'static {
    const ID: SurfaceId;
    type Out;
    type Opts: Default;
    type Plan;                            // per-surface, so Admission is typed
}

pub trait Project<S: Surface> {
    /// Fallible. Decides applicability + admissibility, precomputes the plan.
    fn admits(&self, m: &Checked<Module>) -> Applicability<S>;

    /// INFALLIBLE. Every failure was forced upstream into `admits`.
    fn project(&self, m: &Checked<Module>, a: &Admission<S>, o: &S::Opts) -> S::Out;
}

pub enum Applicability<S: Surface> {
    Admits(Admission<S>),          // Admission holds S::Plan; constructor is crate-private
    Gap(Gap),                      // applicable, but cannot be produced — with a reason
    NotApplicable(&'static str),   // this surface is meaningless for this module
}
```

`Admission<S>` carries `S::Plan`, not a shared untyped `Plan` enum. This closes the `unreachable!()` hole that the typestate design conceded rested on a proptest rather than the type system.

### 4.1 `Gap` — the single most graftable idea in this design

```rust
pub struct Gap {
    pub surface: SurfaceId,
    pub at: Path,                  // "Card.column", or a profile path
    pub kind: GapKind,
    pub why: &'static str,         // human-readable, displayable in a UI
}

pub enum GapKind {
    UnknownConstructor { ctor: u16 },
    UnsupportedShape   { kind: TyKind },
    UnresolvedRef      { form: FormRef },
    MissingFacet       { ns: &'static str, key: &'static str },
    ProfileUnknown     { id: ProfileId },
    ClosedSetViolation { set: &'static str, got: Sym },
    Lossy              { detail: &'static str },   // e.g. u64 → TS number
}
```

A six-month-old renderer binary receiving a form authored by a team that does not exist in its dependency graph answers not "can't render" but **"can't render `worldtree/kanban-card@1.2.0`: needs facet `render/card.badge` on field `column`."** That string is displayable in a UI, actionable by a non-Rust author, and identical to the build-time error `afc` printed to that author. One code path, two entry points.

### 4.2 The surface set, and what "coverage" means

`NotApplicable` is load-bearing. `9/9 coverage` is meaningless if "graph DDL" is scored against a scalar-rooted module. **Totality is a property of the analysis: every applicable surface answers.**

| # | Surface | Value form (runs on unknown AIR) | Text form (build-time printer) |
|---|---|---|---|
| 1 | dCBOR codec | `Codec` — opcode plan, canonical bytes | `cbor.ts` shim (thin; see §9) |
| 2 | Validator | `Validator` — opcode matcher | Valibot-shaped TS |
| 3 | TypeScript types | — (types are erased) | `types.d.ts` |
| 4 | CLI verb set | `VerbTable` — reflective `afc call` | clap scaffolding |
| 5 | Typed HTTP client | `RouteTable` | typed TS/Rust client |
| 6 | MCP descriptors | `Vec<ToolDescriptor>` — serve live | registration JSON |
| 7 | Renderer contract | `RendererContract` + `Verdict` | — |
| 8 | Graph DDL | `GraphModel` (dialect-parameterized) | `.cypher` |
| 9 | Capability manifest | `CapSet` + lockfile resolution | `-capabilities.ts` |
| — | **Rust source** | — | `.rs` with `#[derive(Archiform)]` + pinned digest |
| — | **Conformance corpus** | `Corpus` | fixtures + runner (see §9) |

Six of nine need no code generation at all. The three that emit language source are pretty-printers over a value form, never independent walks — so "the emitted TS validator agrees with the Rust validator" is a *property over one walk*, not a coincidence between two.

The `Surface` trait is sealed and `SurfaceId::ALL` is exhaustive, so `Coverage` is a `[Applicability; N]` whose literal fails to compile when a surface is added. Third parties get `ExtSurface` — unsealed, reported in a side map, excluded from the totality claim. Two tiers with different guarantees is a permanent conceptual tax and it is the correct one to pay: an unsealed set makes `Coverage` vacuous.

---

## 5. Profiles: actions, facets, capabilities

The typestate design demoted actions to `BTreeMap<Key, Cbor>` and thereby handed three protocol-mandated closed sets to hand-written untyped parsing — the exact failure being replaced. Actions are a **second grammar**, typed, checked in `check`, with D-035's closed sets as Rust enums.

```rust
// archiform-profiles::actions — profile id "af.actions@1"
pub struct Action {
    pub name: Sym,
    pub summary: Text,
    pub inputs:  TyId,          // check() enforces Record
    pub outputs: TyId,
    pub streaming: bool,
    pub effects: Vec<Effect>,          // Effect::kind is a CLOSED enum
    pub idempotency: Idempotency,      // CLOSED: creates | updates | destroys
    pub attributes: Attributes,        // CLOSED: exactly 4 keys, D-035
    pub implementation: Option<Impl>,  // { wasm: Blake3, export: Sym }
}
```

An unknown `effects.kind` or a fifth attribute key is a `ClosedSetViolation` gap at `check` time, once, rather than a per-generator hand-check duplicated in `gen_capabilities.zig` and `scripts/capabilities-validate.ts`.

`implementation` **stays inside the signed body** by default. PROTOCOL §15.1's chain — publisher signs body → body declares wasm fingerprints → host verifies bytes before instantiate — is intentional per §15.3 ("the schema is the unit of trust; the wasm is its implementation"). Relocating the fingerprint to a host-signed impl registry means the publisher attests to a contract but nothing about the code satisfying it; for identikey signed op bodies and mjolnir remote execution that is a security regression. A host-side override table exists but is opt-in, policy-gated, and requires an explicit `TrustPolicy::allow_impl_override`. **This is Open Question OQ-3** — the coupling §15.3 complains about is real, and the right fix may be an indirection layer rather than removal.

`af.facets@1` is the FR12 renderer contract, generalized: a facet is `{ name, fields: [Path], required: bool, ty_constraint: Option<TyId> }`. Nothing about balls or lenses.

`af.capabilities@1` is D-036's `requires`/`optional` block verbatim, including `select` and `degradesTo`.

---

## 6. FR13 — how a non-Rust author defines an archiform

**Plainly: they write one JSON file and run one binary. No Rust, no cargo, no derive macro, no recompilation of any consumer.**

```bash
npx @archiform/cli check    forms/kanban-card.air.json
npx @archiform/cli coverage forms/kanban-card.air.json      # the nine-row table, at author time
npx @archiform/cli seal     forms/kanban-card.air.json --key ~/.identikey/team.key
#   → kanban-card.af   id=blake3:9f2c…
npx @archiform/cli emit ts,ts-client,mcp kanban-card.af --out src/generated/
```

`@archiform/cli` is the Rust `afc` binary distributed through npm as platform packages — the esbuild/swc trick. The TypeScript team installs a binary, never a toolchain. This is the same distribution seam Dreamball already runs with `dreamball.wasm`.

**Authored form is AIR-JSON: a 1:1 JSON encoding of the kernel + profiles.** Deliberately *not* JSON Schema — the vocabulary is closed and small, unknown keys are rejected outright, and JSON Schema's open-by-default `x-*` culture is precisely why the current generators degenerated. AIR-JSON is also what the registry serves (`aspects.sh`'s Zod-validated body per the archiform-registry decision can validate AIR-JSON; sealed dCBOR is opaque to it), which is the second reason it is primary.

**The `.af` surface syntax is deferred, on purpose.** A language is a product — formatter, LSP, versioning policy, and diagnostics that are never finished — and for an audience defined as "people who do not write Rust", a compiler with mediocre errors is actively hostile. AIR-JSON fully satisfies FR13 today; `.af` is strictly additive against a frozen IR and can land in month six. This is the single largest de-scope lever and we are pulling it.

**Rust authors are a front-end, not a privileged path.**

```rust
#[derive(Archiform)]                        // lowers tokens → the SAME AIR
#[archiform(name = "identikey/rotate-key", version = "1.0.0")]
struct RotateKey { subject: String, new_pub: [u8; 32], reason: Option<String> }
```

Delete the macro and nothing stops working. The macro emits AIR and a compile-time `const AIR_JSON: &str`; it does **not** emit a digest constant. Compile-time content addressing was claimed by the derive design and does not survive scrutiny: dcbor's canonical serializer is not `const fn`, and a digest covering the transitive `Ref` closure would re-digest every dependent form whenever a leaf changed — reintroducing §15.3's coupling one layer up. `afc` computes the digest; `cargo test` asserts it matches the pinned one.

**Rust consumers get static types back without closing the system**, via a *conformance claim* rather than a definition:

```rust
#[derive(Deserialize, ArchiformView)]
#[archiform(name = "identikey/rotate-key", major = 1)]
struct RotateKey { /* … */ }

let bind: Bind<RotateKey> = RotateKey::bind(&checked)?;   // ONE morph check at startup
let op: RotateKey = bind.decode(&bytes)?;                 // typed, fast, from here on
```

If a peer ships `@1.1` with an added optional field, `morph` succeeds by width subtyping and the struct keeps working. If they made `reason` required, it fails **loudly at startup naming the field**, not at 3am in a decode path. Drift between Rust struct and published archiform becomes a boot error.

**And Rust source is a projection target.** `afc emit rust kanban-card.af > src/generated/kanban_card.rs` gives a TS team's archiform first-class Rust bindings without the TS team ever opening a `.rs` file. Round-trip law, tested over the corpus: `lower(emit_rust(M)) ≡ M`.

---

## 7. An unknown archiform arriving at runtime

**Plainly: it is verified, budget-checked, resolved, and then either projected or gapped. It never panics and never silently half-works.**

```rust
let env = Envelope::from_cbor(&bytes)?;
env.verify(&trust_policy)?;                          // bc-envelope 0.43; unsigned ⇒ reject
let raw = Module::from_dcbor(env.subject())?;        // ArchiformId = blake3(subject); dedup
debug_assert_eq!(blake3(env.subject()), id.0);

let module = registry.resolve_closure(raw, &budget).await?;   // ← the ONLY I/O step
let m: Checked<Module> = archiform::check(module, &Limits::UNTRUSTED)?;  // pure, no I/O

match CORE.renderer.admits(&m) {
    Applicability::Admits(a) => {
        let contract = CORE.renderer.project(&m, &a, &cfg);   // cannot fail
        if contract.satisfied_by(&self.facets) { self.render(&contract, &m) }
        else { self.render_degraded(contract.degrade_to()) }
    }
    Applicability::Gap(g)          => self.render_opaque(&g),   // displays g.why
    Applicability::NotApplicable(_) => self.render_generic(&m),
}
```

There is no `struct KanbanCard` in the binary. The form renders, or degrades along a path its author declared, or refuses with a reason a human can read.

### 7.1 Ref resolution is a separate, explicit, I/O-bearing phase

Three of the four independent designs put network fetches inside a function they simultaneously advertised as pure and microsecond-scale. Split it: `resolve_closure` performs bounded registry fetches and produces a `Module` containing its full transitive closure, interned. `check` is then pure, non-recursive (explicit worklist), and the crate's primary fuzz target. `Checked<Module>` witnesses the *whole closure*, so no projector can meet an unresolved `Ref`.

Unresolvable refs, after the budget is exhausted, become `Ty::Opaque { why: RefUnresolved }`.

### 7.2 Degradation tiers, preserved

| Tier | Requires | Gets |
|---|---|---|
| generic | nothing | raw dCBOR value, structural browse, content hash |
| checked | archiform bytes + valid signature | typed decode, validation, facets, actions, capabilities |
| bound | archiform + a matching Rust view | native structs, zero per-value checks |

Failure at tier 2 degrades to tier 1. It never fails the open. This preserves the archiform-registry position that CBOR plus root primitives already give a generic view without the schema.

### 7.3 `Opaque` is non-monotonic, and that must be an explicit policy

The same message admits on a host that has not fetched a referenced archiform and rejects on one that has. For a renderer that is graceful degradation. For **mjolnir channel admission it is an authorization decision that depends on cache contents**, which is unacceptable. Rule:

> `Opaque` and `Unknown` never satisfy a typed position on a security-relevant surface. `Limits::SECURITY` sets `allow_opaque: false, allow_unknown_ctor: false`, so `check` refuses rather than degrading. Renderer/`Limits::UNTRUSTED` sets both true.

Likewise `Morphism::Widening` must **not** be silently accepted onto a typed channel. Channel admission accepts `Iso | Narrowing` only. "Lossy accept" on a typed channel means untyped.

### 7.4 Adversarial AIR is a first-class threat

AIR is attacker-supplied wire data and the projectors interpret it.

```rust
Limits::UNTRUSTED = Limits {
    max_bytes: 256 << 10, max_depth: 32, max_nodes: 4_096,
    max_fields_per_record: 256, max_union_variants: 64,
    max_list_len_bound: 1 << 20,          // declared bounds are themselves bounded
    max_ref_closure: 16, max_closure_bytes: 1 << 20,
    max_plan_ops: 16_384, max_decode_work: 1 << 22,
    allow_unguarded_recursion: false,
};
```

Additional required properties: the codec and validator carry an explicit work budget (a tree walk needs a stack — the "linear scan, no allocation" claim is false for nested types and must not be shipped as a perf promise); the `Codec`/`Validator` plan cache is bounded and LRU-keyed by `ArchiformId` (an unbounded cache is attacker-controlled memory growth); `Map` keys sort per-value at encode time, which `plan` cannot precompute, and that cost is in the budget.

### 7.5 Reflective surfaces

Because value forms exist, unknown forms are reachable without codegen: `afc call <FormId> move --to done` works through `VerbTable`; a server serves `/.well-known/mcp` by projecting `Vec<ToolDescriptor>` for forms it learned about at runtime. D-019's claim that "CLI, REST, MCP … are mechanical projections" becomes literally true at runtime.

**Honest scoping:** projection yields parsing, help text, validation, and routing — *not* verb bodies. A TS author can publish a working **type** with no Rust; publishing a working **action** still requires a wasm module or a host handler. Say this in the docs; do not let the demo imply otherwise.

---

## 8. The feel of it

### 8.1 A concrete archiform — `forms/kanban-card.air.json`

```jsonc
{
  "air": 1,
  "name": "worldtree/kanban-card@1.2.0",
  "doc": "A card on a kanban board.",
  "imports": { "core": "dreamball/core@2.1.0#blake3:41ab…" },

  "defs": {
    "ColumnRef": { "tagged": { "tag": 40010, "inner": { "ref": "core#Fp" } } },
    "Card": { "record": [
      { "name": "id",     "ty": { "ref": "core#Fp" },                    "doc": "content id" },
      { "name": "title",  "ty": { "text": { "min": 1, "max": 200 } } },
      { "name": "column", "ty": { "ref": "ColumnRef" } },
      { "name": "order",  "ty": { "opt": "float" } },
      { "name": "labels", "ty": { "list": { "item": "text", "max": 64 } }, "default": [] },
      { "name": "body",   "ty": { "bytes": { "max": 1048576 } } }
    ]}
  },
  "root": "Card",

  "profiles": {
    "af.actions@1": {
      "move": {
        "summary": "Move a card to another column",
        "inputs":  { "record": [ { "name": "card", "ty": { "ref": "core#Fp" } },
                                 { "name": "to",   "ty": { "ref": "ColumnRef" } },
                                 { "name": "order","ty": "float" } ] },
        "outputs": { "record": [ { "name": "hlc", "ty": { "ref": "core#Hlc" } } ] },
        "streaming": false,
        "effects": [ { "kind": "ActionEnvelope", "actionKind": "worldtree.kanban-card.move" } ],
        "idempotency": "updates",
        "attributes": { "destructive": false, "requiresConfirmation": false,
                        "confirmationMessage": "", "agentVisible": true },
        "implementation": { "wasm": "blake3:9f2c1e…", "export": "kanban_card_move" }
      }
    },

    "af.facets@1": {
      "card.title":  { "fields": ["title"],  "required": true },
      "card.badge":  { "fields": ["column"], "required": true },
      "card.body":   { "fields": ["body"],   "required": false, "degradesTo": "title-only" }
    },

    "af.capabilities@1": {
      "requires": { "store": { "interface": "service/graph-store", "version": "^1.2",
                               "select": "prefer-local" } },
      "optional": { "knn":   { "interface": "service/vector-knn", "version": "^1",
                               "degradesTo": "sequential-replay" } }
    },

    "af.graph@1": {
      "nodes": [ { "type": "Card", "key": "id" } ],
      "edges": [ { "name": "InColumn", "from": "Card", "to": "ColumnRef" } ]
    }
  }
}
```

```console
$ afc coverage forms/kanban-card.air.json
surface        status          detail
codec          ok              plan 61 ops
validator      ok              plan 44 ops
ts-types       ok
cli            ok              1 verb
http-client    ok              1 route
mcp            ok              1 tool (agentVisible)
renderer       ok              2 required facets, 1 optional
graph-ddl      ok              1 node, 1 edge
capabilities   ok              1 required, 1 optional
rust           ok
— applicable: 10/10, admitted: 10/10

$ afc seal forms/kanban-card.air.json --key ~/.identikey/team.key
  normalize   hash-consed 9 → 7 nodes, canonical order applied
  check       Limits::AUTHOR, 0 gaps
  canonical   dcbor 0.25.2, 604 bytes
  envelope    bc-envelope 0.43.0
  id          blake3:9f2c1e…   → kanban-card.af
```

### 8.2 Projection A — the dCBOR codec (a live value, the hot path)

The most *mechanical* surface. Lowers the type graph once to a flat opcode vector cached by `ArchiformId`; encode/decode is a stack machine.

```rust
pub enum Op {
    MapOpen(u32), MapKeyInt(u64), MapKeyText(SymId), MapClose,
    ArrOpen(LenSrc), ArrClose,
    Bool, Int, Float, Text(Range), Bytes(Range), EnumSym(SymSetId),
    Tag(u64),
    OptSome(PlanPc), OptNone,
    SortMapEntries,              // per-value canonical ordering; cannot be precomputed
    Opaque,                      // byte-preserving passthrough
    Jump(PlanPc), Call(PlanPc), Ret,
}

impl Project<Codec> for Core {
    fn admits(&self, m: &Checked<Module>) -> Applicability<Codec> {
        for (path, ty) in m.walk() {
            match ty {
                // the honest holes, located and explained:
                Ty::Unknown { ctor } => return Applicability::Gap(Gap {
                    surface: SurfaceId::Codec, at: path,
                    kind: GapKind::UnknownConstructor { ctor },
                    why: "this form uses a newer kernel constructor; \
                          the subtree round-trips as opaque bytes but is not typed here",
                }),
                // everything else is codec-representable. Exhaustive, no `_` arm:
                Ty::Bool | Ty::Int {..} | Ty::Float | Ty::Text {..} | Ty::Bytes {..}
                | Ty::Enum(_) | Ty::Opt(_) | Ty::List {..} | Ty::Map {..}
                | Ty::Record(_) | Ty::Union {..} | Ty::Tagged {..}
                | Ty::Ref(_) | Ty::Opaque {..} => {}
            }
        }
        Applicability::Admits(Admission::new(CodecPlan::lower(m)))
    }

    fn project(&self, m: &Checked<Module>, a: &Admission<Codec>, _: &CodecOpts) -> Codec {
        Codec { plan: a.plan().clone(), id: m.id(), budget: Budget::from(&m.limits) }
    }
}
```

Usage on a form the binary has never seen:

```rust
let codec = CODECS.get_or_project(&id, || CORE.codec.admits(&m).into_admission()?)?;
let value: Value = codec.decode(ball.body())?;      // rejects non-canonical input
let bytes = codec.encode(&value)?;                  // canonical by construction
assert_eq!(blake3(&bytes), ball.content_hash);
```

Two properties that make this trustworthy, both in the corpus (§9): `decode ∘ encode ≡ id` over generated values, and `encode` byte-identical to the Zig/`@ipld/dag-cbor` encoders on the FR14 common subset.

### 8.3 Projection B — the renderer contract (a live value, the *least* mechanical surface)

The most *semantic* surface — and the one where `Gap` earns its keep. Note it reads a **profile**, not the kernel, and is `NotApplicable` when the profile is absent.

```rust
pub struct RendererContract {
    pub form: ArchiformId,
    pub required: Vec<Slot>,     // { facet, fields, ty }
    pub optional: Vec<Slot>,
    pub degrade: BTreeMap<FacetName, DegradeTo>,
}

pub enum Verdict {
    Full,
    Degraded { missing: Vec<FacetName>, to: DegradeTo },
    Cannot   { gap: Gap },
}

impl Project<Renderer> for Core {
    fn admits(&self, m: &Checked<Module>) -> Applicability<Renderer> {
        let Some(fp) = m.profile::<facets::Facets>("af.facets@1") else {
            return Applicability::NotApplicable("no af.facets profile — nothing to render against");
        };
        if let ProfileState::Unknown(id) = fp {
            return Applicability::Gap(Gap { surface: SurfaceId::Renderer, at: Path::profile(id),
                kind: GapKind::ProfileUnknown { id },
                why: "this form declares a newer facets profile than this binary understands" });
        }
        let mut slots = Vec::new();
        for facet in fp.iter() {
            for field in &facet.fields {
                let Some(f) = m.field_at(field) else {
                    return Applicability::Gap(Gap { surface: SurfaceId::Renderer, at: field.clone(),
                        kind: GapKind::MissingFacet { ns: "render", key: facet.name.as_str() },
                        why: "facet names a field that does not exist on this form" });
                };
                if matches!(m.ty(f.ty), Ty::Unknown {..} | Ty::Opaque {..}) && facet.required {
                    return Applicability::Gap(Gap { surface: SurfaceId::Renderer, at: field.clone(),
                        kind: GapKind::UnsupportedShape { kind: TyKind::Opaque },
                        why: "a required facet resolves to an uninterpretable subtree" });
                }
                slots.push(Slot::new(facet, f));
            }
        }
        Applicability::Admits(Admission::new(RenderPlan { slots, degrade: fp.degrade_map() }))
    }

    fn project(&self, m: &Checked<Module>, a: &Admission<Renderer>, o: &RenderCfg)
        -> RendererContract { /* pure assembly from the plan — cannot fail */ }
}

impl RendererContract {
    /// FR12, as a typed relation rather than field-presence sniffing.
    pub fn verdict(&self, advertised: &FacetSet) -> Verdict {
        let missing: Vec<_> = self.required.iter()
            .filter(|s| !advertised.satisfies(&s.facet, &s.ty))   // NAME *and* type agreement
            .map(|s| s.facet.clone()).collect();
        match missing.as_slice() {
            [] => Verdict::Full,
            ms => match self.degrade.pick(ms) {
                Some(to) => Verdict::Degraded { missing: ms.to_vec(), to },
                None => Verdict::Cannot { gap: Gap::missing_facets(ms) },
            },
        }
    }
}
```

The two projections could hardly be more different — one is a byte-level opcode machine over the kernel with no semantic judgement, the other is a semantic relation over a profile with no bytes anywhere — and they share a signature, a witness type, an error vocabulary, and a plan discipline. That is the evidence the abstraction is real rather than decorative.

**Scoping honesty:** `Verdict::Full` proves the fields exist and the types agree. It does not prove the renderer can *draw the value* (ranges, units, magnitudes). This beats FR12's name-only dispatch materially; it is not a solution to renderability.

---

## 9. Correctness infrastructure (not optional, budget it)

The design's own residual risk is that the Rust interpreter and the emitted TypeScript validator are two implementations of one semantics — exactly the NFR4 violation this repo already forbids. Mitigations, all first-class:

1. **Conformance corpus back-end.** For each module, generate `(value, expected_bytes, accept/reject)` triples plus property tests: `rust_accept(v) ⟺ ts_accept(v)`, byte-identical encodings, `decode ∘ encode ≡ id`. **Seed it from the language-neutral golden fixtures being extracted under `Dreamball-y4t.8`, not from the Rust encoder** — an oracle that is the implementation under test proves agreement, never correctness.
2. **Front-end parity corpus.** The same logical form authored via AIR-JSON, `#[derive]`, and (later) `.af` must produce byte-identical sealed subjects. This is what makes FR13 a guarantee rather than a claim, and it is the same discipline as FR14's dag-cbor↔native parity applied to the type system itself.
3. **Rust round-trip law.** `lower(emit_rust(M)) ≡ M`.
4. **`morph` soundness.** `conforms(a,b) ⇒ ∀ v : gen(a), codec_for(b).decode(encode_a(v)).is_ok()`, property-tested from day one. `morph` gates renderer dispatch, channel admission, view binding, and semver diffing; an unsound `morph` admits bad data onto a mjolnir channel. Recursive `Ref` requires a coinductive assumption set (Amadio–Cardelli) — this is real compiler work and a classic non-termination bug farm. **Budget more prose than code:** a written subtyping spec with variance rules ships alongside the implementation.
5. **Surface parity.** `arg_set(Cli, a) == arg_set(Http, a) == arg_set(Mcp, a)` for every action — D-019's prose promise as an executable property.
6. **Fuzzing** of `Module::from_dcbor` + `check` + `Codec::decode` under `Limits::UNTRUSTED`.

`cbor.ts` mostly survives as a hand-written dCBOR *reader library* (it is 674 of `gen_cbor.zig`'s 720 lines today, and libraries are hardcoded because libraries are hardcoded). Do not book that as a deletion.

---

## 10. Is this writing our own compiler? Yes. How big?

**Yes, and naming it correctly is a feature.** Front-ends parse. AIR is the AST *and* the wire format. `check` is semantic analysis and it emits a typing judgement carried in the type system as `Checked<Module>`. `lower` is bytecode generation. `morph` is a subtyping algorithm. Projectors are back-ends. Every one of these has forty years of known-good structure, and the moment you name them you stop reinventing them badly — which is exactly what `tools/schema-gen` does today, where each generator re-derives validation and re-walks untyped JSON.

What it is **not**: no type inference, no unification, no optimizer, no register allocation, no machine code. There is no lexer or parser at all in v1 (AIR-JSON is decoded by serde/dcbor). It is closer to Protobuf's descriptor + codegen than to rustc.

| Component | LoC (non-test) | Difficulty |
|---|---:|---|
| kernel: `Ty`/`Module`, interning, normalize, dCBOR ser/de of AIR | 2,200 | medium — determinism matters |
| `check` (worklist, budgets, closed sets, key orderability, recursion guard) | 1,300 | **medium-high — everything downstream rests on it** |
| `Checked`/`Admission`/`Gap`/`Coverage`/`Applicability` | 500 | low |
| `morph` + coinductive recursion + variance | 900 | **high — small code, subtle semantics** |
| `resolve_closure` + registry client + lockfile | 900 | medium |
| seal/verify (bc-envelope glue, `ArchiformId`) | 400 | low |
| profiles: actions, facets, capabilities, graph | 1,100 | low — grammars + checks |
| codec plan + stack machine | 1,400 | **medium-high — dCBOR rules are unforgiving** |
| validator | 500 | low (second walk of the plan) |
| 7 remaining value projectors | 2,400 | low each, tedious |
| 5 text emitters (TS types, TS client, Cypher, Rust source, MCP JSON) | 2,200 | low-medium; escaping/reserved words are the grubby part |
| conformance-corpus back-end + generators + shrinker | 1,600 | medium; non-optional |
| `afc` CLI + cache + drift gate | 900 | low |
| derive + view macros | 1,100 | medium — token-level work is always grubby |
| **subtotal, non-test** | **~17,400** | |
| tests, goldens, differential runners, corpus | ~4,000 | |
| npm platform-package distribution, wasm build, CI matrix, signing | ~1,500 + real ops time | |
| **realistic total** | **~23,000–30,000** | |

The four independent estimates clustered at 11k–13.5k and every critique judged them 2–3× light for the same reasons: distribution, registry, the corpus as permanent tax, and emitters that produce *language source* rather than data. **Publish 25k, not 12k.** Against 4,845 lines of Zig that cover two vendored schemas with hardcoded bodies and cannot answer a single question about a form it has never seen, that is roughly 5× the code for something that is general, works at runtime, and deletes the pin + byte-equivalence machinery.

**Where the cost actually lives, and it is not LoC.** (1) Choosing the closed vocabularies — `Ty`'s constructors, the facet model, what `conforms` means for optional fields and union width. These are opinion-heavy, semi-irreversible, and pulled in three directions. Budget design time, not typing time. (2) `morph`'s written soundness argument. (3) The corpus. (4) If `.af` ever ships: diagnostics, which decay continuously and are what a non-Rust audience judges you on.

**The shape of the curve is the argument.** Cost is concentrated in the kernel and paid once; surfaces 4 through 10 are 2–5 days *each* because by then they are total matches over a frozen grammar. That superlinear-then-sublinear profile is the opposite of the current design, where every additional archiform is copy-paste.

---

## 11. Open questions

### 11.1 Resolved here (do not relitigate without a new ADR)

| # | Decision |
|---|---|
| R-1 | Data-first. The sealed, normalized IR **is** the wire format and the sole projector input. No projector ever takes a Rust type. |
| R-2 | `#[derive(Archiform)]` is a front-end; `#[derive(ArchiformView)]` is a runtime conformance *claim*. Neither is canonical. Rust source is the tenth projection target. |
| R-3 | Closed kernel grammar + `Ty::Unknown` for meta-level forward compatibility + open namespaced profiles/facets for object-level extension. |
| R-4 | One projector signature; `Out` ranges over live values and source text. Text emitters are pretty-printers over value forms, never independent walks. |
| R-5 | `admits`/`project` split; `project` infallible; `Admission<S>` carries `S::Plan`; failures are located, named `Gap`s. `NotApplicable` is a first-class outcome and coverage means "every *applicable* surface answers". |
| R-6 | Normalization (hash-consing + canonical ordering) precedes sealing; `ArchiformId` is over the normalized subject, so front-end choice is unobservable. |
| R-7 | `Float`/f64 is supported. `Int { bits }` is a validation constraint, never a codec width. |
| R-8 | Ref closure resolution is an explicit I/O phase before `check`; `check` is pure and non-recursive. `Checked<Module>` witnesses the whole closure. |
| R-9 | AIR-JSON is the authored form for v1. `.af` surface syntax is deferred and strictly additive. |
| R-10 | Actions/facets/capabilities are typed, checked profiles with D-035's closed sets as Rust enums — not untyped facet bags. |
| R-11 | No refinement/predicate expression language in v1. Cross-field invariants live in consumer code. (This boundary *will* be pushed around month three; hold it — granting it means an evaluator for attacker-supplied predicates on the wire.) |
| R-12 | Adversarial AIR gets an explicit threat model, `Limits::{AUTHOR, UNTRUSTED, SECURITY}`, bounded plan caches, and fuzzing. `Opaque`/`Unknown` never satisfy typed positions under `SECURITY`. Channel admission accepts `Iso | Narrowing` only. |
| R-13 | Generic/parameterized archiforms are unsupported. A parameterized type has no single content address; that is a property of content-addressing, not of Rust. Explicit monomorphization only. |

### 11.2 Genuinely needs the project owner

**OQ-1 — dCBOR map ordering. Blocking; decide before any bytes are sealed.**
Dreamball's canonical ordering is length-first (FR3, `src/dcbor.zig:44`). Blockchain Commons `dcbor` 0.25.2 follows RFC 8949 core-deterministic lexicographic ordering. These produce different bytes, which changes every `content_hash` and invalidates every golden vector (M2). Options: (a) adopt BC ordering and accept a one-time re-hash of the world plus vector regeneration; (b) pin a Dreamball dCBOR profile and fork/configure the ordering; (c) dual-profile with the ordering rule recorded in `Module.air`. **My recommendation: (a), now, while the corpus is small — but this is a re-hashing event and it is yours to authorize.**

**OQ-2 — the browser. Blocking; this is the kill criterion in the spike.**
Dreamball's renderer runs in the browser under a budget CLAUDE.md already describes as a temporary dev-velocity bump (300 KB raw / 150 KB gzip, ~66 KB today, tightening tracked in `Dreamball-8bk`). Kernel + dcbor + bc-envelope verify + codec/validator machinery on `wasm32-unknown-unknown` is plausibly 250–600 KB gzip. Three options, all with real costs: (a) raise the budget and ship the Rust kernel to the browser; (b) ship a **TS kernel** for the browser — an explicit, documented NFR4 waiver policed by the conformance corpus; (c) browser stays at tier-1 generic view and all typed work happens server-side. Every independent design either ignored this or assumed it away. Measure first (§12, Day 1).

**OQ-3 — does `implementation` (wasm blake3) stay inside the signed body?**
Status quo (PROTOCOL §15, D-031) says yes and calls the coupling intentional. §15.3 documents the pain: a wasm bugfix forces a schema reissue and republication. Moving the fingerprint to a host-signed impl registry fixes that and weakens the trust chain — the publisher would attest to a contract but nothing about the code. I have kept it **in** the body with an opt-in host override. If you want the decoupling, it needs a threat model and its own ADR, not a bullet in a strengths list.

**OQ-4 — is full coverage a publishing requirement?**
Does `afc seal` refuse a module with any `Gap`, warn, or record gaps in the sealed body as declared limitations? Affects whether authors can publish types that are, say, deliberately un-DDL-able.

**OQ-5 — semver enforcement: inside the trust boundary or advisory?**
`afc diff` classifies a change via `conforms(old_root, new_root)` and can refuse a same-major breaking edit. But front-ends are declared open and untrusted, so a CLI-side check is bypassable. Either `check` enforces it against the prior `ArchiformId` (requiring registry access during authoring), or it is advisory. It cannot be both.

**OQ-6 — registry artifact.** aspects.sh's archiform-registry decision assumes a Zod-validated JSON body. Sealed dCBOR is opaque to it. Does the registry store AIR-JSON + a detached signature, sealed dCBOR + a JSON projection, or both with a parity gate?

**OQ-7 — key management for `afc seal`.** FR13's hardest unglamorous part: a TS/Bun team that has never touched identikey now needs a signing key, a key location convention, a rotation story, and a "can I author unsigned drafts locally?" policy.

**OQ-8 — mjolnir's real type theory, before the kernel freezes.** `docs/everything-is-a-channel.md` is ten lines and its only typing statement is "types determine what goes through the channel." Pi-calculus channel typing needs i/o capability variance (input covariant, output contravariant, invariant without a capability split); anything session-shaped needs behavioral types — sequencing, choice, duality, linearity. The kernel has none of these constructors, and `morph` is width/depth subtyping over records: that is **payload admission, the easy half**, not channel-type admission. Either (a) mjolnir accepts payload-only typing for v1, or (b) someone writes mjolnir's type spec before we freeze. Do not let "it falls out" stand unexamined. Same question, milder, for identikey: does its 180-line CDDL (occurrences, `.size`/`.regexp`/`.cbor` control operators) lower cleanly onto the fourteen constructors?

**OQ-9 — authority namespace policy.** Who may publish under `worldtree/`? Is `authority` bound to a signing key, and is that binding checked at admission?

---

## 12. First implementation slice — prove or kill it in five days

Deliberately ordered so the highest-risk, cheapest-to-falsify items come first. Each day has an explicit kill criterion. Nothing here requires a parser, a language, or nine projectors.

**Day 1 — the browser size spike. KILL FIRST.**
Build a `wasm32-unknown-unknown` binary containing: `dcbor` decode, `bc-envelope` signature verify, a stub `check`, and a stub opcode machine. Measure raw and gzip.
*Kill criterion:* if the kernel alone exceeds ~200 KB gzip with no plausible path under budget, OQ-2(a) is dead and the design must be re-planned around OQ-2(b) or (c) **before** anything else is built. This is the one thing that changes the architecture, so it goes first. Every one of the four independent designs skipped it.

**Day 2 — normalize + seal + front-end parity.**
`Ty`/`Module`, hash-consing, canonical ordering, dCBOR ser/de of AIR, `ArchiformId`. Author `kanban-card` twice — once as AIR-JSON with fields in one order, once via a throwaway `#[derive]` with a different order and an inlined-vs-named difference.
*Kill criterion:* if the two sealed subjects are not byte-identical, R-6 fails and FR13's guarantee collapses to a claim.

**Day 3 — the codec, against real golden vectors.**
Opcode lowering + encode/decode for an *existing* Dreamball type (`ball.action` v4). Run it against the language-neutral golden fixtures from `Dreamball-y4t.8`.
*Kill criterion:* if the interpreted codec cannot reproduce the existing canonical bytes — after OQ-1 is settled — the whole "one semantics" claim is unproven and the Zig encoder stays canonical indefinitely.

**Day 4 — the crux, end to end.**
`check` with `Limits::UNTRUSTED`, the `af.facets@1` profile, and `Project<Renderer>`. Demo: a binary compiled with zero knowledge of `kanban-card` reads the sealed file, verifies, checks, and prints either a `RendererContract` or a `Gap`. Then delete a facet field from the manifest, re-seal, and show the exact refusal string.
*Kill criterion:* if the `Gap` is not specific enough to be shown to a non-Rust author verbatim, the design's headline runtime story does not hold up.

**Day 5 — the differential seam.**
`Project<TsTypes>` as `String` plus a `Validator` value form; generate ~30 values; assert `rust_accept(v) ⟺ tsc_and_run(ts, v)`.
*Kill criterion:* if establishing this loop takes more than a day at this scale, the corpus tax is larger than budgeted and the 25k estimate is low again.

**What is explicitly NOT in the slice:** `.af` syntax, `morph`, the registry, seven of the ten projectors, the derive macro beyond a throwaway, npm distribution. Those are all mechanical once the kernel is frozen — and none of them can save the design if Days 1–4 fail.

**Go/no-go after five days.** Green on all five: proceed, freeze the kernel at the smallest set that expresses Dreamball's `protocol_v2` plus identikey's CDDL, resolve OQ-8 before adding anything for mjolnir, and ship validator + renderer contract + TS types as the first useful triple in week three. Red on Day 1: re-plan around the browser before writing another line. Red on Day 3: escalate OQ-1 to a decision meeting; the substrate choice may need revisiting.

---

## 13. Positioning check

Everything above exists to make one sentence literally true rather than aspirational:

> **Declare a form once, as signed verifiable data, and every surface is a mechanical projection of it.**

"Signed verifiable data" is why the IR is the wire format. "Once" is why normalization precedes sealing and why the derive macro cannot be canonical. "Every surface" is why the grammar is closed and the projectors are exhaustive. "Mechanical" is why there is one code path for build-time and runtime, and why anything that is *not* mechanical surfaces as a located, named, human-readable `Gap` instead of a hardcoded string body.

The prior three canonical-medium changes each moved a label without changing what was in the box. The test for this one is Day 3 of the slice: bytes out of a projector that match bytes already in the golden vectors, produced by walking data rather than by printing a literal. If that happens, the box has changed.
