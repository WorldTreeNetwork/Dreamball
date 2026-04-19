import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

// Phase A — write-op WASM exports verified end-to-end.
// Every op's output is round-tripped through the existing parse path to
// prove the emitted envelope is structurally valid.

const WASM_PATH = resolve(__dirname, 'jelly.wasm');

interface WasmAPI {
	memory: WebAssembly.Memory;
	alloc: (n: number) => number;
	reset: () => void;
	parseJelly: (ptr: number, len: number) => bigint;
	verifyJelly: (ptr: number, len: number) => number;
	mintDreamBall: (
		typeId: number,
		namePtr: number,
		nameLen: number,
		created: bigint
	) => bigint;
	lastSecretPtr: () => number;
	lastSecretLen: () => number;
	joinGuildWasm: (
		envPtr: number,
		envLen: number,
		guildEnvPtr: number,
		guildEnvLen: number,
		secretPtr: number,
		secretLen: number,
		updated: bigint
	) => bigint;
	growDreamBall: (
		envPtr: number,
		envLen: number,
		secretPtr: number,
		secretLen: number,
		newNamePtr: number,
		newNameLen: number,
		updated: bigint,
		promoteToDreamball: number
	) => bigint;
	resultErrPtr: () => number;
	resultErrLen: () => number;
}

async function loadWasm(): Promise<WasmAPI> {
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
	return inst.exports as unknown as WasmAPI;
}

function readPacked(wasm: WasmAPI, packed: bigint): Uint8Array {
	if (packed === 0n) {
		const ep = wasm.resultErrPtr();
		const el = wasm.resultErrLen();
		const err = new TextDecoder().decode(new Uint8Array(wasm.memory.buffer, ep, el));
		throw new Error(`wasm returned 0: ${err}`);
	}
	const ptr = Number(packed >> 32n);
	const len = Number(packed & 0xffffffffn);
	return new Uint8Array(wasm.memory.buffer, ptr, len).slice();
}

function copyString(wasm: WasmAPI, s: string): { ptr: number; len: number } {
	const bytes = new TextEncoder().encode(s);
	const ptr = wasm.alloc(bytes.length);
	new Uint8Array(wasm.memory.buffer, ptr, bytes.length).set(bytes);
	return { ptr, len: bytes.length };
}

function copyBytes(wasm: WasmAPI, bytes: Uint8Array): number {
	const ptr = wasm.alloc(bytes.length);
	new Uint8Array(wasm.memory.buffer, ptr, bytes.length).set(bytes);
	return ptr;
}

describe('WASM write-ops', () => {
	let wasm: WasmAPI;
	beforeAll(async () => {
		wasm = await loadWasm();
	});

	it('mintDreamBall produces a signed envelope that verifies', () => {
		wasm.reset();
		const name = copyString(wasm, 'spike-curiosity');
		const now = BigInt(Math.floor(Date.now() / 1000));
		const packed = wasm.mintDreamBall(0, name.ptr, name.len, now); // 0 = avatar
		const envelope = readPacked(wasm, packed);
		expect(envelope.length).toBeGreaterThan(100);

		// Secret key should now be available.
		const secretPtr = wasm.lastSecretPtr();
		const secretLen = wasm.lastSecretLen();
		expect(secretLen).toBe(64);
		const secret = new Uint8Array(wasm.memory.buffer, secretPtr, secretLen).slice();
		// Non-zero — proves the host RNG flowed through.
		expect(secret.some((b) => b !== 0)).toBe(true);

		// Envelope should parse cleanly.
		wasm.reset();
		const envPtr = copyBytes(wasm, envelope);
		const parsedPacked = wasm.parseJelly(envPtr, envelope.length);
		const parsedBytes = readPacked(wasm, parsedPacked);
		const parsed = JSON.parse(new TextDecoder().decode(parsedBytes));
		expect(parsed.type).toBe('jelly.dreamball.avatar');
		expect(parsed.stage).toBe('seed');
		expect(parsed.name).toBe('spike-curiosity');

		// And verify the Ed25519 signature.
		wasm.reset();
		const vPtr = copyBytes(wasm, envelope);
		const vCode = wasm.verifyJelly(vPtr, envelope.length);
		expect(vCode).toBe(2); // verified with Ed25519
	});

	it('mintDreamBall covers every type_id 0..5 and the untyped legacy shape (6)', () => {
		const typeMap = [
			[0, 'jelly.dreamball.avatar'],
			[1, 'jelly.dreamball.agent'],
			[2, 'jelly.dreamball.tool'],
			[3, 'jelly.dreamball.relic'],
			[4, 'jelly.dreamball.field'],
			[5, 'jelly.dreamball.guild'],
			[6, 'jelly.dreamball']
		] as const;

		for (const [id, expectedType] of typeMap) {
			wasm.reset();
			const name = copyString(wasm, `t${id}`);
			const packed = wasm.mintDreamBall(
				id,
				name.ptr,
				name.len,
				BigInt(Math.floor(Date.now() / 1000))
			);
			const env = readPacked(wasm, packed);
			wasm.reset();
			const envPtr = copyBytes(wasm, env);
			const parsedPacked = wasm.parseJelly(envPtr, env.length);
			const parsed = JSON.parse(new TextDecoder().decode(readPacked(wasm, parsedPacked)));
			expect(parsed.type).toBe(expectedType);
		}
	});

	it('growDreamBall bumps revision, preserves identity, and re-verifies', () => {
		// 1. Mint a seed.
		wasm.reset();
		const name = copyString(wasm, 'grow-test');
		const now = BigInt(Math.floor(Date.now() / 1000));
		const packed1 = wasm.mintDreamBall(0, name.ptr, name.len, now);
		const env1 = readPacked(wasm, packed1);
		const secret = new Uint8Array(
			wasm.memory.buffer,
			wasm.lastSecretPtr(),
			wasm.lastSecretLen()
		).slice();

		// 2. Grow it.
		wasm.reset();
		const envPtr = copyBytes(wasm, env1);
		const secretPtr = copyBytes(wasm, secret);
		const newName = copyString(wasm, 'grown-name');
		const packed2 = wasm.growDreamBall(
			envPtr,
			env1.length,
			secretPtr,
			secret.length,
			newName.ptr,
			newName.len,
			now + 100n,
			1 // promote to dreamball
		);
		const env2 = readPacked(wasm, packed2);

		// 3. Parse + verify.
		wasm.reset();
		const p2 = copyBytes(wasm, env2);
		const parsed = JSON.parse(
			new TextDecoder().decode(readPacked(wasm, wasm.parseJelly(p2, env2.length)))
		);
		expect(parsed.revision).toBe(1);
		expect(parsed.stage).toBe('dreamball');
		expect(parsed.name).toBe('grown-name');

		wasm.reset();
		const v2 = copyBytes(wasm, env2);
		expect(wasm.verifyJelly(v2, env2.length)).toBe(2);
	});

	it('joinGuildWasm adds a guild assertion + re-verifies', () => {
		// Mint the member DreamBall.
		wasm.reset();
		const memberName = copyString(wasm, 'member');
		const now = BigInt(Math.floor(Date.now() / 1000));
		const packed1 = wasm.mintDreamBall(1, memberName.ptr, memberName.len, now); // agent
		const memberEnv = readPacked(wasm, packed1);
		const memberSecret = new Uint8Array(
			wasm.memory.buffer,
			wasm.lastSecretPtr(),
			wasm.lastSecretLen()
		).slice();

		// Mint the guild.
		wasm.reset();
		const guildName = copyString(wasm, 'the-hummingbirds');
		const packed2 = wasm.mintDreamBall(5, guildName.ptr, guildName.len, now); // guild
		const guildEnv = readPacked(wasm, packed2);

		// Join.
		wasm.reset();
		const mPtr = copyBytes(wasm, memberEnv);
		const gPtr = copyBytes(wasm, guildEnv);
		const sPtr = copyBytes(wasm, memberSecret);
		const packed3 = wasm.joinGuildWasm(
			mPtr,
			memberEnv.length,
			gPtr,
			guildEnv.length,
			sPtr,
			memberSecret.length,
			now + 50n
		);
		const joinedEnv = readPacked(wasm, packed3);

		// Parse + verify.
		wasm.reset();
		const jPtr = copyBytes(wasm, joinedEnv);
		const parsed = JSON.parse(
			new TextDecoder().decode(readPacked(wasm, wasm.parseJelly(jPtr, joinedEnv.length)))
		);
		expect(parsed.revision).toBe(1);
		expect(parsed.guild).toBeDefined();
		expect(parsed.guild.length).toBe(1);

		wasm.reset();
		const vPtr = copyBytes(wasm, joinedEnv);
		expect(wasm.verifyJelly(vPtr, joinedEnv.length)).toBe(2);
	});

	it('rejects bad type_id', () => {
		wasm.reset();
		const packed = wasm.mintDreamBall(99, 0, 0, BigInt(Math.floor(Date.now() / 1000)));
		expect(packed).toBe(0n);
		const ep = wasm.resultErrPtr();
		const el = wasm.resultErrLen();
		const err = new TextDecoder().decode(new Uint8Array(wasm.memory.buffer, ep, el));
		expect(err).toMatch(/type_id/);
	});
});
