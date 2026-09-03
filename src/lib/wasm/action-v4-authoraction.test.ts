import { describe, it, beforeAll } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import {
	instantiateWasm,
	assertAuthorActionGate,
	type WasmAPI
} from './action-v4-authoraction.shared.js';

// B4 — Bun/node leg of the authorAction + verifyAction gate.
// Loads the SAME dreamball.wasm the browser loads (NFR2) via Node fs and asserts
// the WASM's Ed25519 sign + verify round-trip, two tamper paths, wrong-key
// rejection, and zero-length-kind error. The browser leg lives in
// action-v4-authoraction.svelte.test.ts and runs the identical assertions
// under chromium.

const WASM_PATH = resolve(__dirname, 'dreamball.wasm');

describe('v4 ball.action — authorAction + verifyAction (Bun/node)', () => {
	let wasm: WasmAPI;
	beforeAll(async () => {
		wasm = await instantiateWasm(new Uint8Array(readFileSync(WASM_PATH)));
	});

	it('round-trip, tamper, wrong-key, and zero-length-kind cover the sign/verify gate', () => {
		assertAuthorActionGate(wasm);
	});
});
