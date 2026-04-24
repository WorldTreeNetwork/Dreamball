/**
 * store.ts — TC12 swap boundary: re-exports ONLY shared types.
 *
 * Server consumers import from './store.server.js' directly (gets ServerStore).
 * Browser consumers import from './store.browser.js' directly (gets BrowserStore).
 *
 * Why not re-export either adapter here: re-exporting ServerStore from this
 * barrel pulled @ladybugdb/core into the browser bundle when code used
 * `import { StoreAPI } from './store'` — a HIGH-1 regression surfaced during
 * code review. Likewise kuzu-wasm would leak into the server bundle if
 * BrowserStore were re-exported here.
 *
 * TC12: @ladybugdb/core and kuzu-wasm MUST NOT be imported outside
 *   store.server.ts / store.browser.ts. The barrel carries no adapter code.
 */

export * from './store-types.js';
