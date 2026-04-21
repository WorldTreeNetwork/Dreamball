# Epic 5 — Walk the palace with eyes

5 stories · HIGH complexity · 2 thorough / 3 smoke

## Story 5.1 — `aqueduct-flow` shader spike (D-009 go/no-go)

**User Story**: As a developer, I want the `aqueduct-flow` Threlte shader implemented end-to-end with all six D-009 checkboxes green, so risk R4 (Threlte shader work in new territory) resolves before stories 2–4 commit and we have a tested pattern for the remaining three materials.
**FRs**: FR26 (renderer-side consumer of `conductance` + freshness uniform; formulas imported from Epic 2's `aqueduct.ts`). Gates FR18's renderer work.
**NFRs**: NFR10 (<200ms first particle render; per-shader frame budget), NFR14 (first of 4 materials; mythos fidelity anchor), NFR17.
**Decisions**: D-009 (HIGH — this story IS the risk gate); D-007 consumer; D-010 consumer.
**Complexity**: medium · **Test Tier**: thorough · **Risk gate** — R4

### Acceptance Criteria

**(a) Compiles on WebGL + WebGPU**
- Given Storybook scene loading the material, When mounted under WebGL, Then shader compiles zero warnings; toggling `webgpu` arg compiles under WebGPU without re-authoring; WebGPU unavailable → falls back to WebGL automatically (TC4 mandatory fallback); fallback path asserted by Vitest stub denying WebGPU context.

**(b) Reads `conductance` + `freshness` uniforms from `store.ts` derived value**
- Given mock aqueduct row exposed via `store.aqueductsForRoom`, When lens subscribes to derived store `{conductance, lastTraversed}`, Then `uConductance` updates reactively on every derived tick; `uFreshness` computed by importing from `src/memory-palace/aqueduct.ts` (NOT a copy; R7 parity unit test imports same module and asserts bit-identical result); no `@ladybugdb/core`/`kuzu-wasm` import in any lens file.

**(c) Animates particles along path**
- Given aqueduct with `conductance = 0.2`, When rendered for 2s simulated time, Then particle displacement at frames 30/60/90 monotone-increasing; same with `conductance = 0.8` → displacement per frame ≥3x baseline; particle count per unit path-length scales linearly with `capacity × strength`; freshness at floor dims luminance to ≤10% of fresh baseline.

**(d) Frame budget ≤2ms on aqueduct count up to 50**
- Given Storybook scene with 50 aqueducts in single room, When rendered on mid-range laptop (Apple M1 / Intel i7-10xxx baseline), Then per-frame GPU time for `aqueduct-flow` pass ≤2ms (measured via `performance.mark`); first particle within 200ms of mount (NFR10 slice); captured as Storybook play-test green on every CI commit.

**(e) Survives canvas resize**
- Given scene mounted at 800x600, When canvas resizes to 1920x1080 and back to 400x300, Then shader renders without recompilation; particle positions remain on-path; no WebGL context-lost event fires.

**(f) Storybook story renders with two values — high vs low freshness**
- Given two side-by-side scenes: `aqueduct-fresh` (last-traversed = now) and `aqueduct-stale` (last-traversed = 60 days ago), When Storybook play-test captures each, Then fresh shows bright particles flowing at conductance-derived speed; stale shows dim particles drifting toward ambient sink; visual diff exceeds configured pixel-delta threshold.

### Risk gate resolution (D-009)
- ALL SIX PASS → proceed to S5.2–S5.5.
- 2+ checkboxes fail → `/replan`; drop to fallback materials (instanced-line aqueducts via Three.js `Line2`).
- BLANK/UNCOMPILED → HARD BLOCK; replan rendering epic; consider non-shader fallback; `dust-cobweb` + `mythos-lantern` stub move to follow-up sprint per `sprint-scope.md`.

### Technical Notes
New: `src/lib/shaders/aqueduct-flow.{frag,vert}.glsl`, `src/lib/lenses/palace/shaders/AqueductFlow.svelte` (Threlte material wrapper), `src/lib/stories/AqueductFlowSpike.stories.svelte`. Consumer: `src/memory-palace/aqueduct.ts` (freshness half-life constants 30d/90d/365d per Vril ADR).

**Open questions**: Particle density upper bound before `Line2` instanced-path becomes better vehicle (defer to S5.5). Freshness half-life sensitivity — tune via Storybook controls.

---

## Story 5.2 — `PalaceLens.svelte` omnispherical navigable view (FR15)

**User Story**: As persona P0, I want a `PalaceLens.svelte` Svelte 5 component reading a palace envelope through `jelly.wasm` and rendering its rooms as omnispherical onion-shell nodes with click navigation events, so I can see and choose among palace rooms in 3D.
**FRs**: FR15.
**NFRs**: NFR10 (first lit room <2s on ≤500 rooms × ≤50 inscriptions), NFR14, NFR16 (≥3 Vitest), NFR17.
**Decisions**: D-007 consumer (`store.getPalace`, `store.roomsFor` — no `__rawQuery`); D-010 consumer; D-016 consumer; TC3, TC4, TC6, TC12, SEC6.
**Complexity**: medium · **Test Tier**: smoke

### Acceptance Criteria
- **AC1** [palace envelope decoding through WASM]: Given `jelly.dreamball.field` envelope with `field-kind: "palace"` byte-loaded, When `PalaceLens` mounts with palace fp, Then envelope decoded via `jelly.wasm` (TC6 — no hand-written CBOR decode); decoded shape conforms to Valibot schema from `src/lib/generated/schemas.ts`; no `@ladybugdb/core`/`kuzu-wasm` imports in lens file.
- **AC2** [omnispherical topology with ≥3 rooms]: Given palace containing 3 rooms each with `jelly.layout` position attribute, When `PalaceLens` renders, Then each room placed at `layout.position` (world coords); omnispherical onion-shell wrapper drawn around each room node; visible from default camera within first 2s (NFR10).
- **AC3** [deterministic-grid fallback when layout absent]: Given palace whose rooms have no `jelly.layout`, When renders, Then rooms placed on deterministic grid derived from fingerprint ordering; layout byte-stable across two independent mounts of same palace; single `console.info` note logged.
- **AC4** [room-click emits navigation event]: Given lens mounted with visible room, When user clicks room's 3D node, Then `navigate` custom event fires with payload `{kind: "room", fp: <room-fp>}`; bubbles through `DreamBallViewer` dispatch map; Storybook play-test asserts event fires.
- **AC5** [signed-action emission boundary (preparation for S5.5)]: Given lens mounted, When navigation event fires, Then lens itself does NOT write to LadybugDB or CAS directly (SEC11 boundary); event consumed by `DreamBallViewer` which (in S5.5) routes into `store.recordTraversal` → signed action emission via Epic 3 primitive.
- **AC6** [Storybook + Vitest]: Given Storybook with ≥3 rooms, When `bun run test-storybook` runs, Then story renders without errors; navigation-event play-test passes; ≥3 Vitest integration tests cover envelope decode, room placement, grid fallback (NFR16).

### Technical Notes
New: `src/lib/lenses/palace/PalaceLens.svelte` (Svelte 5 runes), `src/lib/lenses/palace/PalaceLens.stories.svelte`. Extend `src/lib/components/DreamBallViewer.svelte` (add `palace` entry to lens dispatch map).

**Open questions**: Camera model for omnispherical walk — orbit vs first-person? Default to orbit for sprint-001; first-person controls Growth-tier.

---

## Story 5.3 — `RoomLens.svelte` interior layout (FR16)

**User Story**: As persona P0, I want a `RoomLens.svelte` interior view that places room contents per the room's `jelly.layout` attribute (with deterministic grid fallback when absent), so I can see and orient inscriptions inside a chosen room.
**FRs**: FR16.
**NFRs**: NFR10 (interior renders in <500ms), NFR14, NFR16 (≥3 Vitest), NFR17.
**Decisions**: D-007 consumer (`store.roomContents(roomFp)`); D-016 consumer; TC3, TC4, TC6, TC12; SEC6.
**Complexity**: small · **Test Tier**: smoke

### Acceptance Criteria
- **AC1** [honours `jelly.layout` placement]: Given room with 2 inscribed avatars each carrying `placement` of `{position: [x,y,z], facing: [qw,qx,qy,qz]}`, When `RoomLens` renders, Then each avatar positioned at `placement.position` in world coords; oriented by `placement.facing` quaternion; orientation verified via Vitest math-assert on avatar's transform matrix.
- **AC2** [deterministic-grid fallback when layout absent]: Given room whose contents have no `placement`, When renders, Then inscriptions placed on deterministic grid; re-mount produces byte-identical world coords; no crash; only informational `console.info`.
- **AC3** [reads through store.ts (TC12)]: Given lens queries currently-configured backend (server or browser), When fetches room contents, Then calls single domain verb `store.roomContents(roomFp)` (D-007); no `@ladybugdb/core`/`kuzu-wasm` imports in lens; no raw Cypher in lens file.
- **AC4** [first-lit-room latency budget]: Given room with 50 inscriptions (NFR10 upper bound per room), When mounts cold, Then first visible frame within 500ms on mid-range laptop; Storybook play-test `performance.now()` delta.
- **AC5** [Storybook + Vitest]: Given stories with two inscriptions at declared placements + one with layout absent, When `bun run test-storybook` runs, Then both stories render without errors; ≥3 Vitest tests cover layout placement, grid fallback, store.ts verb invocation (NFR16).

### Technical Notes
New: `src/lib/lenses/room/RoomLens.svelte`, `src/lib/lenses/room/RoomLens.stories.svelte`. Extend `DreamBallViewer.svelte`.

**Open questions**: Inscriptions default-face room centroid or `[0,0,0]` camera origin when `facing` absent? Default: centroid; document in JSDoc.

---

## Story 5.4 — `InscriptionLens.svelte` + 5 surface variants (FR17)

**User Story**: As persona P0, I want an `InscriptionLens.svelte` with five surface dispatchers (`scroll`, `tablet`, `book-spread`, `etched-wall`, `floating-glyph`) each rendering text-in-3D with full body content from CAS, so I can read inscribed documents in their native rendered form.
**FRs**: FR17.
**NFRs**: NFR10 (text paints in <300ms), NFR14, NFR16, NFR17.
**Decisions**: D-007 consumer (`store.inscriptionBody(inscriptionFp)`); D-016 consumer (reads `Inscription.surface`); TC3, TC4, TC6, TC12, TC13 (CAS source-of-truth); SEC6.
**Complexity**: medium · **Test Tier**: smoke

### Acceptance Criteria
- **AC1** [five documented surfaces render correctly]: Given inscription with `surface: "scroll"` and body `"Hello palace"`, When renders, Then text visible in 3D on scroll-shaped mesh; full body of `jelly.asset` source rendered verbatim; Storybook play-test captures via `getByText("Hello palace")`. Same for `tablet` (rectangular slab), `book-spread` (left/right pages with spine), `etched-wall` (text inset into wall mesh, low-contrast), `floating-glyph` (each glyph individually-transformed mesh, softly animated).
- **AC2** [unknown surface falls back to scroll with warning]: Given inscription whose `surface` is not one of five (e.g. `"mosaic"`), When renders, Then falls back to `Scroll.svelte`; single `console.warn` logs `unknown surface: mosaic — falling back to scroll`; fallback does NOT crash; Vitest test asserts both fallback render and warning emission.
- **AC3** [body bytes through CAS (TC13)]: Given inscription whose `jelly.asset` source references Blake3 H, When lens resolves body, Then calls `store.inscriptionBody(inscriptionFp)` (D-007 verb); verb returns bytes sourced from CAS; no raw filesystem path constructed in lens; no HTTP fetch to non-local URL (SEC6).
- **AC4** [latency budget]: Given `scroll` inscription with 10 KB markdown body, When mounts cold, Then first visible text frame within 300ms on mid-range laptop.
- **AC5** [Storybook + Vitest]: Given five surface stories + one unknown-surface fallback, When `bun run test-storybook` runs, Then all six pass; ≥3 Vitest tests cover scroll render, fallback-with-warning, CAS-body fetch (NFR16).

### Technical Notes
New: `src/lib/lenses/inscription/InscriptionLens.svelte` (surface dispatch), `src/lib/lenses/inscription/surfaces/{Scroll,Tablet,BookSpread,EtchedWall,FloatingGlyph}.svelte`, `src/lib/lenses/inscription/InscriptionLens.stories.svelte` (one story per surface + one unknown-surface fallback). Extend `DreamBallViewer.svelte`.

**Open questions**: Typography choice — single serif family across all five vs surface-specific stone-carved glyphs? Default: single family. Body-length upper bound for `floating-glyph` before glyph-atlas cost prohibitive — soft-warn >2KB.

---

## Story 5.5 — Traversal events + remaining 3 shaders + NFR14 pack close (FR18 + FR26)

**User Story**: As persona P0, I want renderer-side traversal events to round-trip through `store.recordTraversal` → signed `jelly.action` → lazy aqueduct creation (per FR18 CLI side from Epic 3) plus the remaining three Threlte materials (`room-pulse`, `mythos-lantern` stub, `dust-cobweb`), so I can walk room-to-room with my movements signed and audited and see Vril visibly flowing per the Vril ADR.
**FRs**: FR18 (renderer half), FR26 (renderer-side freshness uniform consumer; formula imported from Epic 2 `aqueduct.ts`).
**NFRs**: NFR10 (end-to-end first-lit-room <2s on 500×50 — closing integration assertion), NFR14 (closes 4-shader budget: aqueduct-flow + room-pulse + mythos-lantern stub + dust-cobweb), NFR16 (≥3 Vitest), NFR17.
**Decisions**: D-007 (CRITICAL boundary — `store.recordTraversal` domain verb), Cross-epic FR18 lazy creation via Epic 3 primitive, Cross-epic FR26 R7 parity (imported, not copied), D-010 consumer; TC3, TC4, TC6, TC12, TC17; SEC11.
**Complexity**: large · **Test Tier**: thorough

### Acceptance Criteria

**Traversal event → signed action round-trip (FR18, SEC11)**
- Given two rooms A and B in palace, no aqueduct between, When user clicks A then B in `PalaceLens`, Then `store.recordTraversal({fromFp: A, toFp: B})` called (D-007 verb; single call site); signed `jelly.action` of kind `"move"` appended to timeline (FR9); new `jelly.aqueduct` envelope materialised with `resistance: 0.3`, `capacitance: 0.5`, `kind: "visit"` (D-003 defaults per FR18); paired `jelly.action` of kind `"aqueduct-created"` emitted; both actions carry dual Ed25519 + ML-DSA-87 signatures (NFR12); renderer does NOT paint traversal arc until signed action's Blake3 persisted (SEC11 ordering); integration test covers end-to-end.

**Subsequent traversal: Hebbian strength update, no new aqueduct (FR26, TC17)**
- Given aqueduct A→B exists with strength 0.1, When user traverses A→B again, Then `store.recordTraversal` calls `updateAqueductStrength` (Epic 2 verb) applying `strength ← strength + 0.1 × (1 - strength)`; strength after = 0.19 (±1e-9); no new aqueduct created (idempotency check); only one `"move"` action emitted (not paired create); strength on signed chain monotone non-decreasing across full history (TC17).

**Freshness uniform parity (R7 mitigation)**
- Given test harness calling `freshness(now, lastTraversed)` from `aqueduct.ts`, When invoked from renderer uniform derivation AND server-side spy test, Then both call sites return bit-identical values; unit test locks bit-identity (R7); freshness uses 30d/90d/365d half-life constants per Vril ADR.

**Three new shader materials — compile + behave**
- `room-pulse`: pulses with period proportional to capacitance (measurable via frame-sampled luminance); freshness tints colour toward dust-hue at floor; compiles WebGL+WebGPU.
- `mythos-lantern` stub: single lantern-like light source drawn at palace fountain zero-point; stub MVP-only (full lantern-ring deferred to Growth FR60f, acceptance note in shader file header).
- `dust-cobweb`: cobweb texture overlays aqueduct path with opacity proportional to decay depth when freshness <90-day cobweb threshold; at freshness floor (<365d sleeping), draws particles drifting toward ambient sink (Vril ADR §9 "return-to-zero-point is visual, not destructive").

**End-to-end NFR10 latency close**
- Given palace of 500 rooms × 50 inscriptions (NFR10 upper bound), When opened fresh in `PalaceLens` (cold, mid-range laptop), Then first lit room renders within 2s; 4-shader pack does NOT push any frame >16.7ms (60fps budget); integration test captures via `performance.mark` harness.

**5-lens × type × layout Storybook matrix (NFR14 close)**
- Given `FullRenderPackShowcase.stories.svelte` containing ≥5 composed scenes exercising (palace+aqueduct-flow), (palace+mythos-lantern-stub), (room+room-pulse), (room+dust-cobweb), (inscription-in-room), When `bun run test-storybook` runs, Then all five pass; no shader material beyond budgeted four (NFR14 hard cap); ≥3 Vitest integration tests cover traversal round-trip, freshness parity, NFR10 latency.

**No implicit exfiltration (SEC6)**
- Given any renderer/shader-wrapper module, When network-disabled testing applied, Then every lens still renders every shader from local assets; no HTTP fetch to non-local URL; lint rule or grep assertion enforces no `fetch(` outside `store.ts`-mediated paths.

**Graceful degradation if S5.1 gate partially failed**
- Given S5.1's D-009 gate passed `aqueduct-flow` but triggered `/replan` (2+ checkboxes failed on remaining), When S5.5 enters planning, Then `dust-cobweb` + `mythos-lantern` stub deferred to follow-up sprint per sprint-scope.md; this story delivers only `room-pulse` + FR18 traversal round-trip; NFR14 partially fulfilled (2 of 4) documented in new ADR.

### Technical Notes
New: `src/lib/shaders/{room-pulse,mythos-lantern,dust-cobweb}.{frag,vert}.glsl`, `src/lib/lenses/room/shaders/RoomPulse.svelte`, `src/lib/lenses/palace/shaders/{MythosLantern,DustCobweb}.svelte`, `src/lib/stories/FullRenderPackShowcase.stories.svelte`. Extend `PalaceLens.svelte` (wire traversal events from S5.2 into `store.recordTraversal`), `store.ts` (`recordTraversal` verb calling Epic 2 `updateAqueductStrength` + Epic 3 signed-action primitive in one transaction), `aqueduct.ts` (`freshness(now, lastTraversed)` pure function).

**Open questions**: Renderer-to-signed-action latency concealed by optimistic preview animation, or arc only paints after signature (SEC11 strict)? Default strict for sprint-001; optimistic Growth. If latency fails on 500×50, drop NFR10 target or drop a shader? Per sprint-scope.md replan note: drop `dust-cobweb` + `mythos-lantern` first.

---

## Epic 5 Health Metrics
- **Story count**: 5 (target 2–6) ✓
- **Complexity**: HIGH overall — Threlte shader work (R4) dominates; S5.1 is go/no-go gate with three downstream stories depending on it; S5.5 round-trips through Epic 2 + Epic 3 primitives.
- **Test tier**: S5.1 thorough (risk gate); S5.2/3/4 smoke; S5.5 thorough (FR18 round-trip + NFR14 close).
- **FR coverage**: FR15 → S5.2; FR16 → S5.3; FR17 → S5.4; FR18 → S5.5 (with S5.1 enabling); FR26 → S5.5 (renderer-side consumer; formula home Epic 2).
- **Cross-epic deps**: Epic 1 (envelopes via `jelly.wasm` decode; ML-DSA verify per D-010); Epic 2 (`store.ts` domain verbs + `aqueduct.ts` formulas — imported module, never copied; R7 parity); Epic 3 (S5.5 round-trips into signed-action emission + lazy-create transaction per FR9/FR18).
- **Risk gates**: R4 (Threlte shader new territory) → S5.1 six-checkbox gate; failure modes documented (two fallback branches per D-009).
- **NFR10 latency budget**: S5.1 sets per-shader (≤2ms frame, ≤200ms first render); S5.2/3/4 each ≤500ms / ≤300ms; S5.5 closes end-to-end ≤2s on 500×50. Mid-sprint replan: drop `dust-cobweb` + `mythos-lantern` first if NFR10 fails at S5.5.
- **NFR14 shader budget**: 4 materials. Hard cap enforced in S5.5 ACs.
- **Open questions**: 6 — camera model, freshness half-life tuning, room-default-facing, typography choice, floating-glyph body-length bound, optimistic-preview vs strict-signed ordering. None blocking.
