/**
 * Re-exports `app` and its type for Eden treaty consumers.
 *
 * Usage in Svelte/TS client:
 *   import { treaty } from '@elysiajs/eden';
 *   import type { DreamballServerApp } from '@dreamball/dreamball-server/types';
 *   const api = treaty<DreamballServerApp>('http://localhost:9808');
 */

export { app } from './index.js';
export type { app as DreamballServerApp } from './index.js';
