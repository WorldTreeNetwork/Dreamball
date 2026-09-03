import { describe, it, beforeAll } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { instantiateWasm, assertCrossRuntime, type WasmAPI } from './action-v4-cross-runtime.shared.js';

// C1 — Bun/node leg of the v4 content_hash cross-runtime gate.
// Loads the SAME dreamball.wasm the browser loads (NFR2) via Node fs and asserts
// it reproduces the Zig-CLI golden bytes + content_hash exactly. The browser leg
// lives in action-v4-cross-runtime.svelte.test.ts and runs the identical
// assertions under chromium.

const WASM_PATH = resolve(__dirname, 'dreamball.wasm');

describe('v4 ball.action content_hash — CLI ≡ WASM (Bun/node)', () => {
	let wasm: WasmAPI;
	beforeAll(async () => {
		wasm = await instantiateWasm(new Uint8Array(readFileSync(WASM_PATH)));
	});

	it('reproduces the Zig golden signed bytes, unsigned core, and content_hash', () => {
		assertCrossRuntime(wasm);
	});
});
