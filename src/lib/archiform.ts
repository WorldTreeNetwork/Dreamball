/**
 * Story 2.3 / FR5 / D-017 — TypeScript-side archiform_fp helpers.
 *
 * AC2 (implicit-binding back-compat): sprint-001 envelopes lacking
 * `archiform-fp` must decode to a struct that exposes the implicit
 * Memory Palace fp. Per Technical Notes: "computed once at decoder
 * init: MEMORY_PALACE_IMPLICIT_FP = blake3(<canonical-bytes-of-
 * schemas/memory-palace-0.1.0.json>) — cached, not recomputed per
 * decode." On the TS side we read the schema bytes once on first use
 * and memoize via module-load.
 *
 * The hex-encoded fp is also recorded in `schemas/.pins/memory-palace-
 * 0.1.0.fp` (D-029) — this module re-derives it at runtime against the
 * vendored schema bytes so the constant cannot drift from the schema.
 *
 * Per IC1 (additive back-compat): producers (sprint-002 forward) emit
 * `archiform-fp` on the wire; consumers tolerate absence by substituting
 * the implicit fp.
 */

import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { base58Encode, fromBase58Tagged, toBase58Tagged } from './generated/cbor.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
// The lib lives at src/lib/; the schemas dir is two parents up.
const SCHEMA_PATH = resolve(__dirname, '..', '..', 'schemas', 'memory-palace-0.1.0.json');

let _implicitFpBytes: Uint8Array | null = null;

/** 32-byte blake3 of `schemas/memory-palace-0.1.0.json`, computed via
 *  the WebCrypto-friendly host blake3 wired through `jelly.wasm`. The
 *  module loads the wasm on first call and caches the digest. */
async function computeBlake3(bytes: Uint8Array): Promise<Uint8Array> {
	// Use Web Crypto subtle.digest is SHA-only; we delegate to the
	// vendored jelly.wasm which exports `hashBlake3`. To avoid pulling
	// the full wasm loader into every consumer, the public API
	// memoizes after first call; tests can also pass the bytes
	// directly via `setMemoryPalaceImplicitFp`.
	const wasmPath = resolve(__dirname, 'wasm', 'jelly.wasm');
	const wasmBytes = readFileSync(wasmPath);
	let inst: WebAssembly.Instance;
	const env = {
		getRandomBytes(ptr: number, len: number) {
			const mem = (inst.exports.memory as WebAssembly.Memory).buffer;
			crypto.getRandomValues(new Uint8Array(mem, ptr, len));
		},
	};
	const result = await WebAssembly.instantiate(wasmBytes, { env });
	inst = result.instance;
	const exp = inst.exports as unknown as {
		memory: WebAssembly.Memory;
		alloc(n: number): number;
		reset(): void;
		hashBlake3(inPtr: number, inLen: number, outPtr: number): void;
	};
	exp.reset();
	const inPtr = exp.alloc(bytes.length);
	const outPtr = exp.alloc(32);
	new Uint8Array(exp.memory.buffer, inPtr, bytes.length).set(bytes);
	exp.hashBlake3(inPtr, bytes.length, outPtr);
	return new Uint8Array(exp.memory.buffer, outPtr, 32).slice(0);
}

/** Resolve the implicit Memory Palace archiform fp (32 bytes). Lazy +
 *  memoized so the wasm load happens once per process. */
export async function memoryPalaceImplicitFp(): Promise<Uint8Array> {
	if (_implicitFpBytes !== null) return _implicitFpBytes;
	const schemaBytes = readFileSync(SCHEMA_PATH);
	_implicitFpBytes = await computeBlake3(new Uint8Array(schemaBytes));
	return _implicitFpBytes;
}

/** Test seam: pre-seed the cached implicit fp. Useful when the
 *  caller has already computed the digest (e.g., from the vendored
 *  pin file) and wants to bypass the wasm round-trip. */
export function setMemoryPalaceImplicitFp(fp: Uint8Array): void {
	if (fp.length !== 32) throw new Error('memoryPalaceImplicitFp: expected 32 bytes');
	_implicitFpBytes = fp;
}

/** Pin-file path consumers (tests, scripts) can read the hex pin from. */
export const MEMORY_PALACE_PIN_PATH = resolve(
	__dirname,
	'..',
	'..',
	'schemas',
	'.pins',
	'memory-palace-0.1.0.fp',
);

/** Hex-encode 32 bytes. Convenience for comparing against pin files. */
export function hex32(bytes: Uint8Array): string {
	if (bytes.length !== 32) throw new Error('hex32: expected 32 bytes');
	return Array.from(bytes)
		.map((b) => b.toString(16).padStart(2, '0'))
		.join('');
}

/**
 * Apply implicit-binding to a decoded envelope's attribute list.
 * Walks the attribute pairs; if `archiform-fp` is present, returns its
 * 32-byte value verbatim. If absent, returns the implicit Memory Palace
 * fp per AC2 (D-017 / FR5).
 *
 * `attrs` shape: array of `[label, value]` pairs as produced by the
 * generic `decodeEnvelope` walker — see src/lib/generated/cbor.ts
 * extractEnvelopeParts.
 */
export async function resolveArchiformFp(
	attrs: ReadonlyArray<readonly [string, unknown]>,
): Promise<Uint8Array> {
	for (const [label, value] of attrs) {
		if (label === 'archiform-fp') {
			if (!(value instanceof Uint8Array)) {
				throw new Error('resolveArchiformFp: archiform-fp must be Uint8Array (32 bytes)');
			}
			if (value.length !== 32) {
				throw new Error(`resolveArchiformFp: archiform-fp wrong length: ${value.length}`);
			}
			return new Uint8Array(value);
		}
	}
	return memoryPalaceImplicitFp();
}

/** Re-export base58 helpers for convenience to genesis-envelope tests. */
export { base58Encode, fromBase58Tagged, toBase58Tagged };
