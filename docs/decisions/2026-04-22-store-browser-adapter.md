# 2026-04-22 — store.browser.ts adapter decisions

## Routing strategy for store.ts

**Decision**: `store.ts` remains a simple server re-export. Browser consumers import `store.browser.ts` directly.

**Rationale**: The project's `package.json` already uses the `"exports"` field for the Svelte lib public surface (the `"."` entry with `"svelte"` and `"types"` conditions). Adding a `"browser"`/`"node"` conditional export for this *internal* module would either (a) collide with the lib entry by repurposing the `"."` key, or (b) require a second named export key that breaks the current barrel import pattern. A runtime `typeof window` branch in `store.ts` with top-level dynamic `await import()` causes TypeScript to infer `StoreAPI | undefined` because the module-level assignment depends on a runtime condition — making the type signatures harder to read. The cleanest solution for the MVP scope is: server code imports from `./store.js` (which re-exports `./store.server.js`); browser code imports from `./store.browser.js`. SvelteKit's Vite bundler tree-shakes each unused branch at build time because the import paths are statically resolvable. TC12 is preserved: the bundler never pulls `kuzu-wasm` into a Node/Bun build.

## Double-open safety (AC10) — return existing vs throw

**Decision**: `open()` is idempotent — returns the existing handle silently when already open.

**Rationale**: Throwing `StoreAlreadyOpen` is the correct error-recovery signal when callers *should not* re-open without first closing. However, IDBFS-backed stores have a costly open lifecycle (mkdir → mountIdbfs → syncfs → DB init). Making `open()` idempotent means hot-path callers (Svelte component `onMount`) can call `open()` defensively without needing to track whether they already opened it. `StoreAlreadyOpen` is exported from `store-types.ts` for future implementors who want the throwing variant. The S2.2 server adapter uses the same idempotent pattern (`if (this.conn !== null) return`).

## IndexedDB test isolation in Playwright

**Decision**: Each Playwright test gets a fresh browser context (Playwright's default), so each test runs in a new IDB origin namespace. No explicit `indexedDB.deleteDatabase()` call between tests.

**Rationale**: Playwright's `test` creates a new browser context per test by default. Each context has an isolated origin storage, so IDB data written in one test is invisible to the next. This is simpler than a per-test cleanup helper and avoids the timing hazard of `deleteDatabase` racing with a still-open connection. The trade-off is that persistent cross-reload tests (AC5) must use `page.reload()` within the *same* test, not across separate tests — which is the correct isolation shape anyway.

## kNN routing flag

**Decision**: `KNN_LOCAL = true` (constant). HTTP fallback branch exists but is unreachable.

**Rationale**: S2.1 parity spike passed (set-equal, max |Δ| = 0.000048). Per D-015, the local kuzu-wasm path is the primary route for MVP. The HTTP fallback branch is preserved verbatim (with `TODO-KNN-FALLBACK` marker) so that if a future S2.1 re-run degrades to WARN/HARD BLOCK, setting `KNN_LOCAL = false` activates the stub. The stub currently throws to ensure the fallback is not silently no-op'd. Epic 6 implements the real HTTP fetch when this branch is needed.
