# 2026-05-31 — Browser graph store: LadybugDB-wasm + OPFS (drop kuzu-wasm)

Sprint: sprint-003 (candidate) · Significance: MEDIUM ·
**Status: direction accepted; implementation deferred to the graph-store extraction** ·
Sibling decisions:
[ladybugdb-selection](./2026-04-21-ladybugdb-selection.md) ·
[store-browser-adapter](./2026-04-22-store-browser-adapter.md) ·
[vector-parity-spike](./2026-04-22-vector-parity-spike.md) ·
[capability-provider-model](./2026-05-31-capability-provider-model.md)

## Context

The server graph store is `@ladybugdb/core` (napi, disk) — settled and clean.
For the browser we pulled in `@ladybugdb/wasm-core` and hit build-time
regressions vs upstream `kuzu-wasm@0.11.3` — chiefly **IDBFS missing from the
default wasm build** — which blocked the local-first browser graph and forced a
**fall back to `kuzu-wasm@0.11.3`** in the browser. We filed that upstream as
[LadybugDB/ladybug#399](https://github.com/LadybugDB/ladybug/issues/399)
("Restore IDBFS in default wasm build; allow pthread pool auto-growth").

This left a **two-engine split**: kuzu-wasm in the browser, LadybugDB-napi on
the server — a cross-runtime parity surface plus a kuzu dependency
(`kuzu-wasm`, the `bootstrap-kuzu-wasm` step, the same-origin worker-path
bootstrap).

## The unblock

The LadybugDB maintainer's [comment on #399](https://github.com/LadybugDB/ladybug/issues/399#issuecomment-4340643666)
(adsharma, 2026-04-29): **"https://ladybugdb.github.io/wasm-shell/ uses opfs."**

The IDBFS blocker is therefore **moot** — LadybugDB's wasm persistence path is
**OPFS** (Origin Private File System), not IDBFS. OPFS is the modern browser-DB
persistence layer (synchronous access handles, no `syncfs()` round-trips; it is
what sqlite-wasm and serious browser databases use). Waiting for IDBFS to be
restored was solving the wrong problem.

## Decision

**The browser graph store becomes `@ladybugdb/wasm-core` + OPFS**, unifying on
LadybugDB across both runtimes. `kuzu-wasm` is dropped.

## Consequences

- **Parity becomes automatic.** Same engine on both sides removes the
  cross-runtime K-NN parity question entirely. (This also resolves a standing
  contradiction in our own records: [vector-parity-spike](./2026-04-22-vector-parity-spike.md)
  recorded *PASS* for kuzu-wasm↔ladybug K-NN, while `known-gaps.md`'s "NFR11
  K-NN relaxation" recorded a *HARD BLOCK* routing browser K-NN to HTTP.
  Unifying on LadybugDB removes the variable the contradiction is about.)
- **Drops the kuzu surface** — `kuzu-wasm` dependency, `bootstrap-kuzu-wasm`,
  and the worker-path copy step.
- **Browser deployment requirements (a degradation ladder):**
  - OPFS `createSyncAccessHandle()` is **Worker-scoped** → run the DB in a Web
    Worker. (Not itself cross-origin-isolation-gated.)
  - The **multithreaded** LadybugDB wasm build (pthreads — the *other* half of
    #399) needs `SharedArrayBuffer` → **COOP/COEP cross-origin isolation**
    headers. On a statically-generated site, serving COOP/COEP is the wrinkle.
  - So: **cross-origin-isolated** → multithreaded + OPFS (fastest);
    **not isolated** → single-threaded + OPFS (still persistent, slower);
    **OPFS unavailable** → in-memory (non-persistent) fallback.
- **Ties to the open browser question.** The COOP/COEP-on-a-static-site point
  is precisely the spike left open in
  [capability-provider-model §10.6/§10.7](./2026-05-31-capability-provider-model.md)
  (browser provider acquisition under CSP / static hosting). This decision
  sharpens that spike with a concrete first consumer.

## How it lands in the capability model

`graph-store/1` stays **engine-agnostic** ([capability-provider-model](./2026-05-31-capability-provider-model.md)):

- **server provider** = `ladybug-napi` (disk)
- **browser provider** = `ladybug-wasm + OPFS` (replacing kuzu-wasm) — a pure
  provider swap; the `graph-store/1` interface and every consumer are untouched.

The cross-origin-isolation requirement is a natural fit for the **resource-
profile + degradation** mechanism (§10.2): the browser provider declares a
profile `requires: cross-origin-isolated`; the resolver checks
`self.crossOriginIsolated` before binding the multithreaded provider and
**degrades down the ladder** (single-threaded OPFS → in-memory) otherwise. The
resolution report surfaces which tier bound.

## Alternatives considered

- **Wait for IDBFS restore in the default build.** Rejected — OPFS is the
  modern path the maintainer points to; IDBFS is unlikely to be prioritised and
  is the inferior persistence layer regardless.
- **Keep two engines (kuzu-wasm browser / ladybug-napi server).** Rejected — a
  needless parity surface and an extra dependency, for no benefit once
  `@ladybugdb/wasm-core` is viable via OPFS.

## Follow-ups

- Implement during the **`graph-store` extraction** (move `gen_cypher` +
  `schema.cypher` into the provider; stand up `ladybug-napi` server +
  `ladybug-wasm+OPFS` browser providers behind `graph-store/1`).
- Reconcile the parity-spike vs NFR11-relaxation records (see `known-gaps.md`).
- Spike COOP/COEP delivery for the static-site case (§10.6).
