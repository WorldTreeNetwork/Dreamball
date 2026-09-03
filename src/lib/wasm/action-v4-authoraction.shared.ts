/**
 * B4 — authorAction + verifyAction assertions shared by Bun/node and browser legs.
 *
 * Mirrors the C1 pattern (action-v4-cross-runtime.shared.ts): a shared
 * assertions module loaded by two thin test files that differ only in how they
 * load the WASM binary. This gate adds the signature-verify path: after
 * authorAction produces a signed action envelope, we verify it, tamper it in
 * two places, zero-out the signature, and test zero-length kind — proving the
 * WASM's Ed25519 sign + verify are symmetric in both Bun/node and browser
 * (NFR2).
 *
 * Note on spec naming: the B4 spec lists `verifyBall` in the WasmAPI, but
 * `verifyBall` calls `decodeDreamBallSubject` (reads `identity`) and returns
 * -1 on action envelopes (which carry `actor`, not `identity`). The correct
 * WASM export for action envelopes is `verifyAction`, which calls `decodeAction`
 * (reads `actor`) and re-encodes canonical unsigned bytes via `encodeActionV4`.
 * This module uses `verifyAction`. (Deviation recorded in the B4 Dev Agent Record.)
 *
 * KAT secret: [seed(32) || pubkey(32)] where seed = all-zeros and pubkey is
 * the Ed25519 public key of that seed (fixture.actorHex). The WASM uses
 * secret[32..64] as the `actor` field embedded in the envelope, so the
 * signing key and the embedded actor agree → verifyAction returns VERIFY_OK (2).
 */
import { expect } from 'vitest';
import fixture from './__fixtures__/action-v4.golden.json' with { type: 'json' };

/** Minimal view of the WASM exports touched by this gate. */
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
	verifyAction: (ptr: number, len: number) => number;
	resultErrPtr: () => number;
	resultErrLen: () => number;
}

/** Instantiate dreamball.wasm from raw bytes with the host-RNG seam. */
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

/** Reset the bump arena and call verifyAction on the given bytes. */
function callVerifyAction(wasm: WasmAPI, bytes: Uint8Array): number {
	wasm.reset();
	const ptr = copy(wasm, bytes);
	return wasm.verifyAction(ptr, bytes.length);
}

/**
 * Run the full authorAction + verifyAction gate against an instantiated WASM module.
 *
 * Sub-cases:
 *   1. Round-trip: authorAction → verifyAction → code 2 (VERIFY_OK, Ed25519 valid)
 *   2. Tamper body (byte at index 4, inner-tag byte): not code 2
 *      Note: verifyAction re-encodes canonical bytes via encodeActionV4, so
 *      structural corruption at byte 4 causes decodeAction to fail (code -1)
 *      rather than a signature mismatch (code 0). We assert ≤ 0.
 *   3. Tamper trailing byte (last byte, inside Ed25519 sig attr): code 0 (VERIFY_FAILED)
 *   4. Wrong-key (zero the 64 trailing signature bytes): code 0 (VERIFY_FAILED)
 *   5. Zero-length kind: authorAction returns packed 0n + non-empty diagnostic
 *
 * Signature-offset verification (against action-v4.golden.json signedBytesHex):
 * The hex ends with `5840` + 128 hex chars. `0x5840` = CBOR bytes(64), confirming
 * the last 64 bytes of the signed envelope are the raw Ed25519 signature.
 */
export function assertAuthorActionGate(wasm: WasmAPI): void {
	// Build the 64-byte secret: [seed(32) || pubkey(32)].
	// The WASM uses secret[32..64] as the actor fingerprint embedded in the
	// action's core map. Using the KAT seed and its derived pubkey ensures the
	// actor field and the signing key agree → verifyAction returns VERIFY_OK (2).
	const secret64 = new Uint8Array(64);
	secret64.set(hexToBytes(fixture.secretSeedHex), 0); // seed (32 zero bytes)
	secret64.set(hexToBytes(fixture.actorHex), 32); // Ed25519 pubkey derived from that seed

	const kind = new TextEncoder().encode(fixture.kind);
	const body = hexToBytes(fixture.bodyHex);
	const parents = hexToBytes(fixture.parentHashesHex.join(''));
	const parentCount = fixture.parentHashesHex.length;

	// --- Sub-case 1: round-trip (authorAction → verifyAction → code 2) ---
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
	expect(packed, 'authorAction should return a non-zero packed pointer').not.toBe(0n);
	const signed = readPacked(wasm, packed);

	const code1 = callVerifyAction(wasm, signed);
	expect(code1, 'verifyAction on valid signed envelope should return VERIFY_OK (2)').toBe(2);

	// --- Sub-case 2: tamper body (byte at index 4 = second byte of inner CBOR tag) ---
	// XOR flips d8c9 → d8c8 (inner tag 201 → 200). verifyAction calls decodeAction
	// on the corrupted bytes before re-encoding; if decodeAction rejects the wrong
	// inner tag, verifyAction returns -1 (parse error). Either way the tamper
	// must not produce a clean code 2 — we assert ≤ 0.
	const tampered2 = signed.slice();
	tampered2[4] ^= 0x01;
	const code2 = callVerifyAction(wasm, tampered2);
	expect(
		code2,
		'body-tampered envelope (byte 4 XOR) should not verify cleanly (code ≤ 0)'
	).toBeLessThanOrEqual(0);

	// --- Sub-case 3: tamper trailing byte (last byte, inside Ed25519 signature attr) ---
	// The last byte is inside the 64-byte raw signature. stripSignatures extracts
	// the corrupted sig bytes; sig.verify fails → verifyAction returns code 0.
	const tampered3 = signed.slice();
	tampered3[tampered3.length - 1] ^= 0x01;
	const code3 = callVerifyAction(wasm, tampered3);
	expect(
		code3,
		'trailing-byte-tampered envelope should return VERIFY_FAILED (0)'
	).toBe(0);

	// --- Sub-case 4: wrong-key (zero the 64-byte Ed25519 signature bytes) ---
	// Confirmed against action-v4.golden.json signedBytesHex: the hex ends with
	// `5840<128-hex-chars>`, i.e. CBOR bytes(64) header then 64 raw sig bytes.
	// The last 64 bytes of the signed envelope are therefore the raw signature.
	const wrongKey = signed.slice();
	for (let i = wrongKey.length - 64; i < wrongKey.length; i++) wrongKey[i] = 0;
	const code4 = callVerifyAction(wasm, wrongKey);
	expect(code4, 'zeroed-signature envelope should return VERIFY_FAILED (0)').toBe(0);

	// --- Sub-case 5: zero-length kind → error sentinel 0n ---
	wasm.reset();
	const emptyKindPtr = wasm.alloc(1); // valid ptr; we pass kindLen=0 to trigger the guard
	const bodyPtr5 = copy(wasm, body);
	const parentsPtr5 = copy(wasm, parents);
	const secretPtr5 = copy(wasm, secret64);
	const packedErr = wasm.authorAction(
		emptyKindPtr,
		0, // kindLen = 0 → WASM guard returns error sentinel
		bodyPtr5,
		body.length,
		parentsPtr5,
		parentCount,
		BigInt(fixture.hlc[0]),
		BigInt(fixture.hlc[1]),
		secretPtr5
	);
	expect(packedErr, 'zero-length kind should return error sentinel 0n').toBe(0n);
	const ep = wasm.resultErrPtr();
	const el = wasm.resultErrLen();
	const errMsg = new TextDecoder().decode(new Uint8Array(wasm.memory.buffer, ep, el));
	expect(errMsg.length, 'zero-length kind should produce a non-empty diagnostic').toBeGreaterThan(
		0
	);
}
