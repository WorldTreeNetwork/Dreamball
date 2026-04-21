/**
 * Jelly WASM loader — single source of truth for `.jelly` parsing,
 * Ed25519 verification, and ML-DSA-87 verification in the browser.
 * Compiles from `src/wasm_main.zig` via `zig build wasm`.
 *
 * Why WASM: guarantees byte-for-byte agreement with the Zig CLI. Every
 * new envelope type is parsed by the same code. Current size: ~171 KB
 * uncompressed (ReleaseSmall) / ~50 KB gzipped, including the vendored
 * ML-DSA-87 verify path (see `docs/known-gaps.md §1`).
 *
 * Caveat (v2 MVP scope): the Zig parser currently decodes the core
 * + signatures. Nested look / feel / act / memory / knowledge-graph /
 * emotional-register / interaction-set / guild-policy / etc. round-trip
 * as `__cborTag` wrappers inside the JSON until the full envelope
 * decoder lands in Zig. Once that lands, rebuild the WASM and the
 * browser side upgrades for free — the `.wasm` bytes are the interface.
 */

import type { DreamBall } from '../generated/types.js';
import {
	DreamBallSchema,
	safeParseDreamBall,
	type DreamBallValidated,
	type ParseResult
} from '../generated/schemas.js';
import * as v from 'valibot';

interface WasmExports {
	memory: WebAssembly.Memory;
	alloc: (size: number) => number;
	reset: () => void;
	parseJelly: (ptr: number, len: number) => bigint;
	verifyJelly: (ptr: number, len: number) => number;
	verifyMlDsa: (
		sigPtr: number,
		sigLen: number,
		msgPtr: number,
		msgLen: number,
		pkPtr: number,
		pkLen: number
	) => number;
	resultErrPtr: () => number;
	resultErrLen: () => number;
}

export const VERIFY_OK = 2 as const;
export const VERIFY_NO_ED25519 = 1 as const;
export const VERIFY_FAILED = 0 as const;
export const VERIFY_PARSE_ERROR = -1 as const;

export type VerifyResult =
	| { ok: true; hadEd25519: boolean; code: 1 | 2 }
	| { ok: false; reason: string; code: 0 | -1 };

/**
 * Verify every signature on a `.jelly` file in-browser.
 *
 * Both Ed25519 AND ML-DSA-87 signatures are checked — the WASM module
 * ships with liboqs's ML-DSA-87 verify path linked in (see
 * `docs/known-gaps.md §1`). Policy is "all present must verify, no
 * minimum count" per `docs/PROTOCOL.md §2.3`. An Ed25519 signature is
 * checked against the envelope's `identity`; an ML-DSA signature is
 * checked against `identity-pq`. An ML-DSA signature with no
 * `identity-pq` in the core is a hard failure.
 *
 * - `{ ok: true, hadEd25519: true }` — every signature verified.
 * - `{ ok: true, hadEd25519: false }` — parsed OK but no Ed25519
 *   signature present (rare; typically a draft).
 * - `{ ok: false, code: 0, ... }` — one or more signatures failed.
 * - `{ ok: false, code: -1, ... }` — parse failure.
 */
export async function verifyJelly(bytes: Uint8Array): Promise<VerifyResult> {
	const exp = await getInstance();
	exp.reset();
	const ptr = exp.alloc(bytes.length);
	if (ptr === 0) return { ok: false, code: -1, reason: 'alloc failed (input too large?)' };
	new Uint8Array(exp.memory.buffer, ptr, bytes.length).set(bytes);
	const result = exp.verifyJelly(ptr, bytes.length);
	if (result === 2) return { ok: true, hadEd25519: true, code: 2 };
	if (result === 1) return { ok: true, hadEd25519: false, code: 1 };
	const ep = exp.resultErrPtr();
	const el = exp.resultErrLen();
	const reason = new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ep, el));
	if (result === 0) return { ok: false, code: 0, reason };
	return { ok: false, code: -1, reason };
}

/**
 * Standalone ML-DSA-87 verification. Direct binding to the liboqs-backed
 * verify function; doesn't touch any DreamBall envelope parsing. Useful
 * when you already have the canonical unsigned bytes and just need to
 * check one signature against one public key.
 *
 * Signature MUST be 4627 bytes, public key MUST be 2592 bytes
 * (FIPS-204 Category 5). Returns `true` on verify, `false` on mismatch
 * or length error (check `err` for the diagnostic).
 */
export async function verifyMlDsa(
	signature: Uint8Array,
	message: Uint8Array,
	publicKey: Uint8Array
): Promise<{ ok: boolean; err?: string }> {
	const exp = await getInstance();
	exp.reset();
	const sigPtr = exp.alloc(signature.length);
	const msgPtr = exp.alloc(message.length);
	const pkPtr = exp.alloc(publicKey.length);
	if (sigPtr === 0 || msgPtr === 0 || pkPtr === 0) {
		return { ok: false, err: 'alloc failed (input too large?)' };
	}
	new Uint8Array(exp.memory.buffer, sigPtr, signature.length).set(signature);
	new Uint8Array(exp.memory.buffer, msgPtr, message.length).set(message);
	new Uint8Array(exp.memory.buffer, pkPtr, publicKey.length).set(publicKey);
	const rc = exp.verifyMlDsa(sigPtr, signature.length, msgPtr, message.length, pkPtr, publicKey.length);
	if (rc === 1) return { ok: true };
	const ep = exp.resultErrPtr();
	const el = exp.resultErrLen();
	const err = new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ep, el));
	return { ok: false, err };
}

let modulePromise: Promise<WebAssembly.Module> | null = null;

async function getModule(): Promise<WebAssembly.Module> {
	if (!modulePromise) {
		modulePromise = (async () => {
			// Resolve the wasm URL via Vite's asset handling. `?url` makes
			// Vite copy the file into the build output and return its
			// resolved URL, which works in dev + production alike.
			const { default: wasmUrl } = await import('./jelly.wasm?url');
			const resp = await fetch(wasmUrl);
			if (!resp.ok) throw new Error(`fetch jelly.wasm: ${resp.status}`);
			return WebAssembly.compile(await resp.arrayBuffer());
		})();
	}
	return modulePromise;
}

async function instantiate(): Promise<WasmExports> {
	const mod = await getModule();
	// Mutable reference so the env import can see the instance's memory
	// once it's constructed (circular dep: env.getRandomBytes writes into
	// inst.exports.memory, but we need env to instantiate inst).
	let inst!: WebAssembly.Instance;
	const env = {
		getRandomBytes(ptr: number, len: number) {
			const mem = (inst.exports.memory as WebAssembly.Memory).buffer;
			crypto.getRandomValues(new Uint8Array(mem, ptr, len));
		}
	};
	inst = await WebAssembly.instantiate(mod, { env });
	return inst.exports as unknown as WasmExports;
}

let cachedInstance: WasmExports | null = null;
async function getInstance(): Promise<WasmExports> {
	if (!cachedInstance) cachedInstance = await instantiate();
	return cachedInstance;
}

/**
 * Parse a `.jelly` byte array (bare CBOR envelope, sealed JELY wrapper,
 * or canonical JSON text) into a **fully validated** DreamBall.
 *
 * The WASM parser does the heavy lifting (CBOR → JSON); Valibot validates
 * the shape against `DreamBallSchema`. Throws `ValiError` on schema
 * mismatch, `Error` on parse failure.
 *
 * For a non-throwing variant, use `safeParseJelly`.
 */
export async function parseJelly(bytes: Uint8Array): Promise<DreamBallValidated> {
	const jsonText = await parseJellyToJsonRaw(bytes);
	return v.parse(DreamBallSchema, JSON.parse(jsonText));
}

/**
 * Parse + validate, returning a tagged result instead of throwing.
 */
export async function safeParseJelly(bytes: Uint8Array): Promise<ParseResult<DreamBallValidated>> {
	let jsonText: string;
	try {
		jsonText = await parseJellyToJsonRaw(bytes);
	} catch (e) {
		return {
			success: false,
			issues: [
				{
					kind: 'schema',
					type: 'wasm',
					message: (e as Error).message
				} as unknown as v.BaseIssue<unknown>
			]
		};
	}
	return safeParseDreamBall(jsonText);
}

/**
 * Like `parseJelly` but returns the validated JSON string (not a parsed
 * object). Useful for piping into other systems.
 */
export async function parseJellyToJson(bytes: Uint8Array): Promise<string> {
	const db = await parseJelly(bytes);
	return JSON.stringify(db);
}

/** Internal — bytes → WASM → JSON string, no schema validation. */
async function parseJellyToJsonRaw(bytes: Uint8Array): Promise<string> {
	const exp = await getInstance();

	exp.reset();

	const inPtr = exp.alloc(bytes.length);
	if (inPtr === 0) throw new Error('jelly-wasm: alloc failed (input too large?)');
	new Uint8Array(exp.memory.buffer, inPtr, bytes.length).set(bytes);

	const packed = exp.parseJelly(inPtr, bytes.length);

	if (packed === 0n) {
		const ep = exp.resultErrPtr();
		const el = exp.resultErrLen();
		const msg = new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ep, el));
		throw new Error(`jelly-wasm parse failed: ${msg || '(no diagnostic)'}`);
	}

	const resultPtr = Number(packed >> 32n);
	const resultLen = Number(packed & 0xffffffffn);
	return new TextDecoder().decode(new Uint8Array(exp.memory.buffer, resultPtr, resultLen));
}

/** Retained export for back-compat with any callers that want the unvalidated shape. */
export async function parseJellyUnvalidated(bytes: Uint8Array): Promise<DreamBall> {
	const jsonText = await parseJellyToJsonRaw(bytes);
	return JSON.parse(jsonText) as DreamBall;
}
