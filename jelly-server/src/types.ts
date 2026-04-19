/**
 * Re-exports `app` and its type for Eden treaty consumers.
 *
 * Usage in Svelte/TS client:
 *   import { treaty } from '@elysiajs/eden';
 *   import type { JellyServerApp } from '@dreamball/jelly-server/types';
 *   const api = treaty<JellyServerApp>('http://localhost:9808');
 */

export { app } from './index.js';
export type { app as JellyServerApp } from './index.js';
