/**
 * C1 — cross-runtime determinism assertions for the v4 `ball.action`
 * content_hash gate, shared by the Bun/node leg (`*.test.ts`) and the browser
 * leg (`*.svelte.test.ts`). Both legs load the SAME `dreamball.wasm` binary
 * (NFR2) and run these identical assertions, proving Zig-CLI ≡ browser ≡ Bun.
 *
 * The golden constants come from `__fixtures__/action-v4.golden.json`, the
 * TS-side mirror of `src/golden.zig`'s `GOLDEN_ACTION_V4_*` values. The Zig CLI
 * golden test pins the CLI side to those exact bytes; these assertions pin the
 * WASM side; transitively, CLI and WASM agree on the unsigned bytes (the
 * content_hash domain), the signed bytes, and the digest.
 *
 * Which bytes are hashed: `content_hash = Blake3-256(canonical UNSIGNED
 * envelope bytes)`, NO domain separation (D-043, PROTOCOL.md §16.7/§17.4).
 * `authorAction` returns the SIGNED envelope, so to recover the unsigned domain
 * we use the structural invariant that signed and unsigned share an identical
 * leaf+core block after the 3-byte header (envelope tag + outer-array header).
 */
import { expect } from 'vitest';
import fixture from './__fixtures__/action-v4.golden.json' with { type: 'json' };

/** Minimal view of the wasm exports this gate touches. */
export interface WasmAPI {
	memory: WebAssembly.Memory;
	alloc: (n: number) => number;
	reset: () => void;
	authorAction: (
		kindPtr: number,
		kindLen: number,
		bodyPtr: number,
		bodyLen: number,
		parentHashesPtr: number,
		parentHashesCount: number,
		hlcL: bigint,
		hlcC: bigint,
		secretPtr: number
	) => bigint;
	hashBlake3: (inputPtr: number, inputLen: number, outPtr: number) => void;
	resultErrPtr: () => number;
	resultErrLen: () => number;
}

/** Instantiate `dreamball.wasm` from raw bytes with the host-RNG seam. */
export async function instantiateWasm(bytes: Uint8Array): Promise<WasmAPI> {
	const mod = await WebAssembly.compile(bytes as unknown as BufferSource);
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

function hexToBytes(hex: string): Uint8Array {
	const out = new Uint8Array(hex.length / 2);
	for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
	return out;
}

function bytesToHex(bytes: Uint8Array): string {
	let s = '';
	for (const b of bytes) s += b.toString(16).padStart(2, '0');
	return s;
}

function copy(wasm: WasmAPI, bytes: Uint8Array): number {
	const ptr = wasm.alloc(bytes.length);
	new Uint8Array(wasm.memory.buffer, ptr, bytes.length).set(bytes);
	return ptr;
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

function blake3HexViaWasm(wasm: WasmAPI, bytes: Uint8Array): string {
	wasm.reset();
	const inPtr = copy(wasm, bytes);
	const outPtr = wasm.alloc(32);
	wasm.hashBlake3(inPtr, bytes.length, outPtr);
	return bytesToHex(new Uint8Array(wasm.memory.buffer, outPtr, 32).slice());
}

/**
 * Run the full cross-runtime golden gate against an instantiated wasm module.
 * Asserts: (1) WASM `authorAction` reproduces the Zig-CLI SIGNED golden byte for
 * byte; (2) that signed envelope embeds the exact canonical UNSIGNED core block
 * (the content_hash domain); (3) `Blake3(unsigned)` via the same WASM Blake3 the
 * CLI uses equals the pinned content_hash; (4) a one-byte perturbation flips it.
 */
export function assertCrossRuntime(wasm: WasmAPI): void {
	const actor = hexToBytes(fixture.actorHex);
	const secret64 = new Uint8Array(64);
	secret64.set(hexToBytes(fixture.secretSeedHex), 0); // seed (32 zero bytes)
	secret64.set(actor, 32); // public half — actor is derived from this in WASM

	const kind = new TextEncoder().encode(fixture.kind);
	const body = hexToBytes(fixture.bodyHex);
	const parents = hexToBytes(fixture.parentHashesHex.join(''));
	const parentCount = fixture.parentHashesHex.length;

	wasm.reset();
	const kindPtr = copy(wasm, kind);
	const bodyPtr = copy(wasm, body);
	const parentsPtr = copy(wasm, parents);
	const secretPtr = copy(wasm, secret64);
	const packed = wasm.authorAction(
		kindPtr,
		kind.length,
		bodyPtr,
		body.length,
		parentsPtr,
		parentCount,
		BigInt(fixture.hlc[0]),
		BigInt(fixture.hlc[1]),
		secretPtr
	);
	const signed = readPacked(wasm, packed);

	// (1) Byte-identical SIGNED envelope across runtimes — the canonical encoder
	// + deterministic Ed25519 reproduce exactly the CLI golden.
	expect(bytesToHex(signed)).toBe(fixture.signedBytesHex);

	// (2) The signed envelope carries the exact canonical UNSIGNED core block.
	// Offset 3 = 2-byte envelope tag (0xd8 0xc8) + 1-byte outer-array header;
	// signed/unsigned differ only in that header and the trailing `signed`
	// attribute, so the [3..] core block must match the unsigned golden's.
	const unsigned = hexToBytes(fixture.unsignedBytesHex);
	const coreLen = unsigned.length - 3;
	expect(Array.from(signed.slice(3, 3 + coreLen))).toEqual(Array.from(unsigned.slice(3)));

	// (3) content_hash = Blake3(unsigned), via the SAME wasm Blake3 the CLI uses.
	expect(blake3HexViaWasm(wasm, unsigned)).toBe(fixture.contentHash);

	// (4) Negative — a one-byte perturbation flips the digest.
	const tampered = unsigned.slice();
	tampered[tampered.length - 1] ^= 0x01;
	expect(blake3HexViaWasm(wasm, tampered)).not.toBe(fixture.contentHash);
}
