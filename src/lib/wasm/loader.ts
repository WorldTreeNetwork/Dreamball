/**
 * Jelly WASM loader — single source of truth for `.jelly` parsing in
 * the browser. Compiles from `src/wasm_main.zig` via `zig build wasm`.
 *
 * Why WASM: guarantees byte-for-byte agreement with the Zig CLI. Every
 * new envelope type is parsed by the same code. Ships at ~29 KB
 * uncompressed (ReleaseSmall) for the v2 surface — gzips well below
 * 15 KB.
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
 * Verify the Ed25519 signature(s) on a `.jelly` file in-browser.
 *
 * - Returns `{ ok: true, hadEd25519: true }` when every Ed25519 signature
 *   verified cleanly against the envelope's identity.
 * - Returns `{ ok: true, hadEd25519: false }` when the envelope parsed
 *   but carried no Ed25519 signature (e.g., a draft or a relic wrapper).
 * - Returns `{ ok: false, code: 0, ... }` on signature mismatch.
 * - Returns `{ ok: false, code: -1, ... }` on parse failure.
 *
 * ML-DSA-87 signatures are structurally acknowledged but not verified
 * here — no pure-Zig ML-DSA lives on freestanding-wasm yet. Real ML-DSA
 * verification stays CLI-side until a binding lands.
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
