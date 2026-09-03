import { describe, it, beforeAll } from 'vitest';
import {
	instantiateWasm,
	assertAuthorActionGate,
	type WasmAPI
} from './action-v4-authoraction.shared.js';

// B4 — browser (chromium) leg of the authorAction + verifyAction gate.
// The `.svelte.test.ts` suffix routes this into the vitest `client` project,
// which runs under a real browser. It loads the SAME dreamball.wasm via Vite's
// asset URL + fetch (the exact path loader.ts uses in production), instantiates
// it, and runs the identical assertions as the Bun/node leg — proving
// Ed25519 sign + verify are symmetric in browser as well as Bun (NFR2).
//
// Browser-leg caveat (Dreamball-nvg): Playwright's chrome-headless-shell
// cannot be extracted locally (disk at 100%). This file is code-complete by
// construction; the browser leg is verified in CI where Playwright extraction
// succeeds. Do not block story B4 on local browser execution.

describe('v4 ball.action — authorAction + verifyAction (browser)', () => {
	let wasm: WasmAPI;
	beforeAll(async () => {
		const { default: wasmUrl } = await import('./dreamball.wasm?url');
		const resp = await fetch(wasmUrl);
		if (!resp.ok) throw new Error(`fetch dreamball.wasm: ${resp.status}`);
		wasm = await instantiateWasm(new Uint8Array(await resp.arrayBuffer()));
	});

	it('round-trip, tamper, wrong-key, and zero-length-kind cover the sign/verify gate', () => {
		assertAuthorActionGate(wasm);
	});
});
