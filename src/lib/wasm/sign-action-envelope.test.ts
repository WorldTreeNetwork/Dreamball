import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

// Story 6.1 — AC2 (Ed25519 KAT round-trip) and AC3 (tamper test)
// Uses mintDreamBall to obtain a live keypair, then drives signActionEnvelope
// and verifies the produced signature via Web Crypto subtle.verify.
//
// Zig's Ed25519 secret key is 64 bytes: [seed(32) || pubkey(32)].
// The last 32 bytes are the raw Ed25519 public key, importable by subtle.

const WASM_PATH = resolve(__dirname, 'dreamball.wasm');

interface WasmAPI {
	memory: WebAssembly.Memory;
	alloc: (n: number) => number;
	reset: () => void;
	mintDreamBall: (typeId: number, namePtr: number, nameLen: number, created: bigint) => bigint;
	lastSecretPtr: () => number;
	lastSecretLen: () => number;
	signActionEnvelope: (
		keypairPtr: number,
		keypairLen: number,
		payloadPtr: number,
		payloadLen: number
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

function copyBytes(wasm: WasmAPI, bytes: Uint8Array): number {
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

// Copy a Uint8Array into a fresh ArrayBuffer (avoids SharedArrayBuffer typing issues).
function toArrayBuffer(u8: Uint8Array): ArrayBuffer {
	const buf = new ArrayBuffer(u8.byteLength);
	new Uint8Array(buf).set(u8);
	return buf;
}

// Import an Ed25519 public key (raw 32 bytes) via Web Crypto.
async function importEd25519PublicKey(rawBytes: Uint8Array): Promise<CryptoKey> {
	return crypto.subtle.importKey('raw', toArrayBuffer(rawBytes), { name: 'Ed25519' }, false, ['verify']);
}

// Verify an Ed25519 signature via Web Crypto subtle.
async function subtleVerify(pk: CryptoKey, payload: Uint8Array, sig: Uint8Array): Promise<boolean> {
	return crypto.subtle.verify({ name: 'Ed25519' }, pk, toArrayBuffer(sig), toArrayBuffer(payload));
}

describe('signActionEnvelope (AC2 + AC3)', () => {
	let wasm: WasmAPI;
	// keypair from mintDreamBall (real host-RNG seed)
	let secret64: Uint8Array; // 64 bytes: [seed(32) || pubkey(32)]
	let pubKeyRaw: Uint8Array; // last 32 bytes of secret64
	let pubKey: CryptoKey;

	const PAYLOAD = new TextEncoder().encode('dreamball-action-test-payload');

	beforeAll(async () => {
		wasm = await loadWasm();

		// Mint a DreamBall so we get a real keypair (host RNG flows through).
		wasm.reset();
		const nameBytes = new TextEncoder().encode('kat-action');
		const namePtr = copyBytes(wasm, nameBytes);
		const now = BigInt(Math.floor(Date.now() / 1000));
		const packed = wasm.mintDreamBall(0, namePtr, nameBytes.length, now);
		if (packed === 0n) throw new Error('mintDreamBall failed in beforeAll');

		const secretPtr = wasm.lastSecretPtr();
		const secretLen = wasm.lastSecretLen();
		expect(secretLen).toBe(64);
		secret64 = new Uint8Array(wasm.memory.buffer, secretPtr, secretLen).slice();

		// Zig Ed25519 secret_key.toBytes() = [seed(32) || pubkey(32)].
		// The public key is the last 32 bytes.
		pubKeyRaw = secret64.slice(32, 64);
		pubKey = await importEd25519PublicKey(pubKeyRaw);
	});

	it('AC2 — signActionEnvelope produces a 64-byte Ed25519 signature that verifies', async () => {
		wasm.reset();
		const skPtr = copyBytes(wasm, secret64);
		const plPtr = copyBytes(wasm, PAYLOAD);
		const packed = wasm.signActionEnvelope(skPtr, 64, plPtr, PAYLOAD.length);
		const sig = readPacked(wasm, packed);

		expect(sig.length).toBe(64);
		const ok = await subtleVerify(pubKey, PAYLOAD, sig);
		expect(ok).toBe(true);
	});

	it('AC3 — bit-flipped payload produces a different sig and fails verification', async () => {
		// Sign original payload.
		wasm.reset();
		const skPtr1 = copyBytes(wasm, secret64);
		const plPtr1 = copyBytes(wasm, PAYLOAD);
		const packed1 = wasm.signActionEnvelope(skPtr1, 64, plPtr1, PAYLOAD.length);
		const sig1 = readPacked(wasm, packed1);

		// Flip bit 0 of byte 0.
		const flipped = new Uint8Array(PAYLOAD);
		flipped[0] ^= 0x01;

		// Sign flipped payload.
		wasm.reset();
		const skPtr2 = copyBytes(wasm, secret64);
		const plPtr2 = copyBytes(wasm, flipped);
		const packed2 = wasm.signActionEnvelope(skPtr2, 64, plPtr2, flipped.length);
		const sig2 = readPacked(wasm, packed2);

		// Signatures must differ (Ed25519 is deterministic so same payload → same sig).
		const sigsEqual = sig1.every((b, i) => b === sig2[i]);
		expect(sigsEqual).toBe(false);

		// Verifying sig1 against the flipped payload must fail.
		const badVerify = await subtleVerify(pubKey, flipped, sig1);
		expect(badVerify).toBe(false);
	});

	it('AC1 — signActionEnvelope export exists in wasm module', async () => {
		// Verify the export is present as a function (belt-and-suspenders).
		const bytes = readFileSync(WASM_PATH);
		const mod = await WebAssembly.compile(bytes);
		const exports = WebAssembly.Module.exports(mod);
		const found = exports.find((e) => e.name === 'signActionEnvelope' && e.kind === 'function');
		expect(found).toBeDefined();
	});
});
