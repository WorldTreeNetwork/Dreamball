import { describe, it, beforeAll } from 'vitest';
import { instantiateWasm, assertCrossRuntime, type WasmAPI } from './action-v4-cross-runtime.shared.js';

// C1 — browser (chromium) leg of the v4 content_hash cross-runtime gate.
// The `.svelte.test.ts` suffix routes this into the vitest `client` project,
// which runs under a real browser. It loads the SAME dreamball.wasm via Vite's
// asset URL + fetch (the exact path loader.ts uses in production), instantiates
// it, and runs the identical assertions as the Bun/node leg — proving
// Zig-CLI ≡ browser ≡ Bun (NFR1/NFR2).

describe('v4 ball.action content_hash — CLI ≡ WASM (browser)', () => {
	let wasm: WasmAPI;
	beforeAll(async () => {
		const { default: wasmUrl } = await import('./dreamball.wasm?url');
		const resp = await fetch(wasmUrl);
		if (!resp.ok) throw new Error(`fetch dreamball.wasm: ${resp.status}`);
		wasm = await instantiateWasm(new Uint8Array(await resp.arrayBuffer()));
	});

	it('reproduces the Zig golden signed bytes, unsigned core, and content_hash', () => {
		assertCrossRuntime(wasm);
	});
});
