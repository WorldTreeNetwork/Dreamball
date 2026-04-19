import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { execSync } from 'child_process';
import { mkdtempSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';

// End-to-end verify test. Mints a real DreamBall via the Zig CLI,
// loads the bytes, calls the WASM verifier. Confirms:
//   - pristine envelope verifies
//   - tampered envelope rejects
// This is the "browser acts as independent verifier" proof.

const WASM_PATH = resolve(__dirname, 'jelly.wasm');
const JELLY_CLI = resolve(__dirname, '..', '..', '..', 'zig-out', 'bin', 'jelly');

async function loadWasm() {
	const bytes = readFileSync(WASM_PATH);
	const mod = await WebAssembly.compile(bytes);
	let inst!: WebAssembly.Instance;
	const env = {
		getRandomBytes(ptr: number, len: number) {
			const mem = (inst.exports.memory as WebAssembly.Memory).buffer;
			crypto.getRandomValues(new Uint8Array(mem, ptr, len));
		}
	};
	inst = await WebAssembly.instantiate(mod, { env });
	return inst.exports as unknown as {
		memory: WebAssembly.Memory;
		alloc: (n: number) => number;
		reset: () => void;
		verifyJelly: (ptr: number, len: number) => number;
		resultErrPtr: () => number;
		resultErrLen: () => number;
	};
}

describe('WASM verifyJelly', () => {
	let wasm: Awaited<ReturnType<typeof loadWasm>>;
	let pristineBytes: Uint8Array;
	let tamperedBytes: Uint8Array;

	beforeAll(async () => {
		wasm = await loadWasm();

		const workdir = mkdtempSync(join(tmpdir(), 'jelly-verify-'));
		const jellyPath = join(workdir, 'test.jelly');

		// Mint a real DreamBall via the Zig CLI.
		execSync(`${JELLY_CLI} mint --out ${jellyPath} --type avatar --name test`, { stdio: 'pipe' });
		pristineBytes = new Uint8Array(readFileSync(jellyPath));

		// Tamper: flip a byte inside the signed region.
		const copy = new Uint8Array(pristineBytes);
		copy[60] ^= 0x01;
		tamperedBytes = copy;
	});

	function verify(bytes: Uint8Array): { code: number; reason: string } {
		wasm.reset();
		const ptr = wasm.alloc(bytes.length);
		new Uint8Array(wasm.memory.buffer, ptr, bytes.length).set(bytes);
		const code = wasm.verifyJelly(ptr, bytes.length);
		const ep = wasm.resultErrPtr();
		const el = wasm.resultErrLen();
		const reason = new TextDecoder().decode(new Uint8Array(wasm.memory.buffer, ep, el));
		return { code, reason };
	}

	it('verifies a pristine mint', () => {
		const { code } = verify(pristineBytes);
		expect(code).toBe(2);
	});

	it('rejects a tampered byte', () => {
		const { code, reason } = verify(tamperedBytes);
		// Either the signature fails (code 0) or the envelope no longer
		// parses cleanly (code -1); both are acceptable rejections.
		expect([-1, 0]).toContain(code);
		expect(reason.length).toBeGreaterThan(0);
	});

	it('rejects garbage input', () => {
		const garbage = new Uint8Array([0xff, 0xff, 0xff, 0xff]);
		const { code } = verify(garbage);
		expect(code).toBe(-1);
	});
});
