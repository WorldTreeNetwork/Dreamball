/**
 * DreamBall WASM loader — single source of truth for `.ball` parsing,
 * Ed25519 verification, and ML-DSA-87 verification in the browser.
 * Compiles from `src/wasm_main.zig` via `zig build wasm`.
 *
 * Why WASM: guarantees byte-for-byte agreement with the Zig CLI. Every
 * new envelope type is parsed by the same code. Current size: ~171 KB
 * uncompressed (ReleaseSmall) / ~50 KB gzipped, including the vendored
 * ML-DSA-87 verify path (see `docs/known-gaps.md §1`).
 *
 * Decode scope (current): the Zig parser typed-decodes the core,
 * signatures, `look`, `feel`, `act` (incl. nested `asset` / `skill`),
 * and `archiform-fp`, plus the scalar/list attributes (name, dates,
 * note, contains, derived-from, guilds). The remaining nested slots —
 * `memory`, `knowledge-graph`, `emotional-register`, `interaction-set`,
 * `guild-policy` — are NOT yet decoded: the decode walk skips unknown
 * assertions, so today they are dropped from the JSON rather than
 * surfaced (there is no raw-passthrough field). Finishing them is
 * tracked as Dreamball-m97 and is done by extending
 * `schemas/root-2.0.0.json` + regenerating (the JSON-Schema-canonical
 * pipeline, D-018/D-030), not by hand-writing decoders. Once a slot
 * lands and the WASM is rebuilt, the browser upgrades for free — the
 * `.wasm` bytes are the interface, and the generated `cbor.ts` decode
 * path regenerates from the same schema in lockstep.
 */

import type { DreamBall } from '../generated/types.js';
import {
	DreamBallSchema,
	type DreamBallValidated,
	type ParseResult
} from '../generated/schemas.js';
import { safeParseDreamBall } from '../parse.js';
import * as v from 'valibot';

interface WasmExports {
	memory: WebAssembly.Memory;
	alloc: (size: number) => number;
	reset: () => void;
	parseBall: (ptr: number, len: number) => bigint;
	verifyBall: (ptr: number, len: number) => number;
	verifyMlDsa: (
		sigPtr: number,
		sigLen: number,
		msgPtr: number,
		msgLen: number,
		pkPtr: number,
		pkLen: number
	) => number;
	hashBlake3: (inputPtr: number, inputLen: number, outPtr: number) => void;
	signActionEnvelope: (
		keypairPtr: number,
		keypairLen: number,
		payloadPtr: number,
		payloadLen: number
	) => bigint;
	resultErrPtr: () => number;
	resultErrLen: () => number;
	// Added by B3 — authorAction wrapper
	authorAction: (
		kind_ptr: number,
		kind_len: number,
		body_ptr: number,
		body_len: number,
		parent_hashes_ptr: number,
		parent_hashes_count: number,
		hlc_l: bigint,
		hlc_c: bigint,
		secret_ptr: number
	) => bigint;
	// Added by B2 — B3 wraps this
	verifyAction: (ptr: number, len: number) => number;
	// Added by B3 (subsumes Dreamball-t2d)
	mintDreamBall: (
		type_id: number,
		name_ptr: number,
		name_len: number,
		created: bigint
	) => bigint;
	growDreamBall: (
		env_ptr: number,
		env_len: number,
		secret_ptr: number,
		secret_len: number,
		new_name_ptr: number,
		new_name_len: number,
		updated: bigint,
		promote_to_dreamball: number
	) => bigint;
	joinGuildWasm: (
		env_ptr: number,
		env_len: number,
		guild_env_ptr: number,
		guild_env_len: number,
		secret_ptr: number,
		secret_len: number,
		updated: bigint
	) => bigint;
	lastSecretPtr: () => number;
	lastSecretLen: () => number;
}

export const VERIFY_OK = 2 as const;
export const VERIFY_NO_ED25519 = 1 as const;
export const VERIFY_FAILED = 0 as const;
export const VERIFY_PARSE_ERROR = -1 as const;

export type VerifyResult =
	| { ok: true; hadEd25519: boolean; code: 1 | 2 }
	| { ok: false; reason: string; code: 0 | -1 };

/**
 * Verify every signature on a `.ball` file in-browser.
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
export async function verifyBall(bytes: Uint8Array): Promise<VerifyResult> {
	const exp = await getInstance();
	exp.reset();
	const ptr = exp.alloc(bytes.length);
	if (ptr === 0) return { ok: false, code: -1, reason: 'alloc failed (input too large?)' };
	new Uint8Array(exp.memory.buffer, ptr, bytes.length).set(bytes);
	const result = exp.verifyBall(ptr, bytes.length);
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

/**
 * Compute Blake3-256 of `bytes` and return the 64-char lowercase hex digest.
 *
 * Uses the same `std.crypto.hash.Blake3` that the Zig CLI uses, compiled
 * into `dreamball.wasm`. This eliminates the SHA-256 fallback that previously
 * existed in `cypher-utils.ts` for non-Bun runtimes — a field named
 * `source_blake3` is now genuinely Blake3 in every runtime (browser,
 * Bun server, Node tests). See Sprint-1 code review HIGH-2.
 */
export async function blake3Hex(bytes: Uint8Array): Promise<string> {
	const exp = await getInstance();
	exp.reset();
	const inPtr = exp.alloc(bytes.length);
	const outPtr = exp.alloc(32);
	if (inPtr === 0 || outPtr === 0) throw new Error('blake3Hex: alloc failed');
	new Uint8Array(exp.memory.buffer, inPtr, bytes.length).set(bytes);
	exp.hashBlake3(inPtr, bytes.length, outPtr);
	const digest = new Uint8Array(exp.memory.buffer, outPtr, 32);
	return Array.from(digest).map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Synchronous Blake3 — for call sites that cannot await.
 *
 * Only usable after the WASM module has been initialized (i.e., after at
 * least one `await` of any loader export). Throws if the instance is not
 * yet cached.
 */
export function blake3HexSync(bytes: Uint8Array): string {
	if (!cachedInstance) throw new Error('blake3HexSync: WASM not yet initialized — call an async export first');
	const exp = cachedInstance;
	exp.reset();
	const inPtr = exp.alloc(bytes.length);
	const outPtr = exp.alloc(32);
	if (inPtr === 0 || outPtr === 0) throw new Error('blake3HexSync: alloc failed');
	new Uint8Array(exp.memory.buffer, inPtr, bytes.length).set(bytes);
	exp.hashBlake3(inPtr, bytes.length, outPtr);
	const digest = new Uint8Array(exp.memory.buffer, outPtr, 32);
	return Array.from(digest).map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Sign an arbitrary payload with a 64-byte Ed25519 keypair (seed||pubkey).
 *
 * Calls the `signActionEnvelope` WASM export (Story 6.1) — the canonical
 * seam through which all action-envelope signatures are produced (D-023).
 * Ed25519 single signature only per SEC6 + project_dreamball_pq_deferred.
 *
 * Returns the 64-byte raw Ed25519 signature bytes.
 *
 * @param keypairBytes  64 bytes: [seed(32) || pubkey(32)] in Zig key format
 * @param payload       Arbitrary bytes to sign (canonical action payload)
 */
export async function signActionEnvelope(
	keypairBytes: Uint8Array,
	payload: Uint8Array
): Promise<Uint8Array> {
	if (keypairBytes.length !== 64) {
		throw new Error(`signActionEnvelope: keypairBytes must be 64 bytes, got ${keypairBytes.length}`);
	}
	const exp = await getInstance();
	exp.reset();
	const skPtr = exp.alloc(keypairBytes.length);
	const plPtr = exp.alloc(payload.length);
	if (skPtr === 0 || plPtr === 0) {
		throw new Error('signActionEnvelope: alloc failed (input too large?)');
	}
	new Uint8Array(exp.memory.buffer, skPtr, keypairBytes.length).set(keypairBytes);
	new Uint8Array(exp.memory.buffer, plPtr, payload.length).set(payload);
	const packed = exp.signActionEnvelope(skPtr, keypairBytes.length, plPtr, payload.length);
	if (packed === 0n) {
		const ep = exp.resultErrPtr();
		const el = exp.resultErrLen();
		const msg = new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ep, el));
		throw new Error(`signActionEnvelope: wasm returned 0: ${msg || '(no diagnostic)'}`);
	}
	const ptr = Number(packed >> 32n);
	const len = Number(packed & 0xffffffffn);
	return new Uint8Array(exp.memory.buffer, ptr, len).slice();
}

/**
 * Author (encode + sign) an action envelope from JS.
 *
 * Marshals the nine WASM parameters via the bump allocator, concatenates
 * parent hashes into a contiguous run, and returns the signed envelope bytes.
 * The actor fingerprint is derived inside WASM as `secret[32..64]` (D-042) —
 * it is NOT a separate parameter.
 *
 * @param opts.kind     Non-empty action kind string (e.g. "worldtree.kanban-card.move")
 * @param opts.body     Optional body bytes (omit or pass undefined for no body)
 * @param opts.parents  Array of parent content-hash digests, each exactly 32 bytes
 * @param opts.hlc      HLC clock as [hlc_l, hlc_c] BigInts (u64 each)
 * @param opts.secret   64-byte Ed25519 secret: [seed(32) || pub(32)] in Zig wire format
 * @returns             Signed envelope bytes (CBOR) — copied out of bump arena
 */
export async function authorAction(opts: {
	kind: string;
	body?: Uint8Array;
	parents: Uint8Array[];
	hlc: [bigint, bigint];
	secret: Uint8Array;
}): Promise<Uint8Array> {
	// JS-side pre-validation before touching WASM.
	if (opts.secret.length !== 64) {
		throw new Error(
			`authorAction: secret must be 64 bytes, got ${opts.secret.length}`
		);
	}
	if (opts.kind.length === 0) {
		throw new Error('authorAction: kind must be non-empty');
	}

	const exp = await getInstance();
	exp.reset();

	// 1. kind
	const kindBytes = new TextEncoder().encode(opts.kind);
	const kindPtr = exp.alloc(kindBytes.byteLength);
	if (kindPtr === 0) throw new Error('authorAction: alloc failed (input too large?)');
	new Uint8Array(exp.memory.buffer, kindPtr, kindBytes.byteLength).set(kindBytes);

	// 2. body (optional — pass 0,0 if absent)
	let bodyPtr = 0;
	let bodyLen = 0;
	if (opts.body !== undefined && opts.body.length > 0) {
		bodyPtr = exp.alloc(opts.body.length);
		if (bodyPtr === 0) throw new Error('authorAction: alloc failed (input too large?)');
		new Uint8Array(exp.memory.buffer, bodyPtr, opts.body.length).set(opts.body);
		bodyLen = opts.body.length;
	}

	// 3. parent hashes — validate each is exactly 32 bytes, then concatenate
	const parentCount = opts.parents.length;
	let phPtr = 0;
	if (parentCount > 0) {
		for (let i = 0; i < parentCount; i++) {
			if (opts.parents[i].length !== 32) {
				throw new Error(
					`authorAction: parent[${i}] must be 32 bytes, got ${opts.parents[i].length}`
				);
			}
		}
		const ph = new Uint8Array(parentCount * 32);
		for (let i = 0; i < parentCount; i++) {
			ph.set(opts.parents[i], i * 32);
		}
		phPtr = exp.alloc(ph.length);
		if (phPtr === 0) throw new Error('authorAction: alloc failed (input too large?)');
		new Uint8Array(exp.memory.buffer, phPtr, ph.length).set(ph);
	}

	// 4. secret (exactly 64 bytes; NO secret_len param — ABI takes ptr only)
	const secretPtr = exp.alloc(64);
	if (secretPtr === 0) throw new Error('authorAction: alloc failed (input too large?)');
	new Uint8Array(exp.memory.buffer, secretPtr, 64).set(opts.secret);

	// 5. call — hlc params are u64 → BigInt; parent_hashes_count is the count
	//    of 32-byte hashes (not the byte length)
	const packed = exp.authorAction(
		kindPtr,
		kindBytes.byteLength,
		bodyPtr,
		bodyLen,
		phPtr,
		parentCount,
		opts.hlc[0],
		opts.hlc[1],
		secretPtr
	);
	if (packed === 0n) {
		const ep = exp.resultErrPtr();
		const el = exp.resultErrLen();
		const msg = new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ep, el));
		throw new Error(`authorAction: wasm returned 0: ${msg || '(no diagnostic)'}`);
	}

	// 6. unpack and copy out of bump arena before the next reset()
	const ptr = Number(packed >> 32n);
	const len = Number(packed & 0xffffffffn);
	return new Uint8Array(exp.memory.buffer, ptr, len).slice();
}

/**
 * Verify every signature on a signed action envelope.
 *
 * Mirrors `verifyBall` but targets the `verifyAction` WASM export (B2).
 * The actor (verify key) is embedded in the envelope — no key parameter.
 *
 * Return codes follow the same 2/1/0/-1 convention as `verifyBall`:
 * - `{ ok: true, hadEd25519: true, code: 2 }` — signature verified
 * - `{ ok: true, hadEd25519: false, code: 1 }` — unsigned/draft (no signature)
 * - `{ ok: false, code: 0, ... }` — signature verification failed
 * - `{ ok: false, code: -1, ... }` — parse failure
 */
export async function verifyAction(envelope: Uint8Array): Promise<VerifyResult> {
	const exp = await getInstance();
	exp.reset();
	const ptr = exp.alloc(envelope.length);
	if (ptr === 0) return { ok: false, code: -1, reason: 'alloc failed (input too large?)' };
	new Uint8Array(exp.memory.buffer, ptr, envelope.length).set(envelope);
	const result = exp.verifyAction(ptr, envelope.length);
	if (result === 2) return { ok: true, hadEd25519: true, code: 2 };
	if (result === 1) return { ok: true, hadEd25519: false, code: 1 };
	const ep = exp.resultErrPtr();
	const el = exp.resultErrLen();
	const reason = new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ep, el));
	if (result === 0) return { ok: false, code: 0, reason };
	return { ok: false, code: -1, reason };
}

/**
 * Mint a new DreamBall and return its signed envelope bytes + the generated
 * Ed25519 secret key.
 *
 * The WASM export generates a fresh Ed25519 keypair via `env.getRandomBytes`
 * and stores the 64-byte secret in the WASM-internal `last_secret` buffer.
 * This wrapper reads it out immediately (before any subsequent reset) and
 * returns it alongside the signed envelope.
 *
 * @param opts.typeId   0=avatar 1=agent 2=tool 3=relic 4=field 5=guild 6=untyped(v1)
 * @param opts.name     Optional display name
 * @param opts.created  Unix seconds as BigInt (i64)
 * @returns             `{ envelope, secret }` — both copied out of WASM memory
 */
export async function mintDreamBall(opts: {
	typeId: number;
	name?: string;
	created: bigint;
}): Promise<{ envelope: Uint8Array; secret: Uint8Array }> {
	const exp = await getInstance();
	exp.reset();

	let namePtr = 0;
	let nameLen = 0;
	if (opts.name && opts.name.length > 0) {
		const nameBytes = new TextEncoder().encode(opts.name);
		namePtr = exp.alloc(nameBytes.byteLength);
		if (namePtr === 0) throw new Error('mintDreamBall: alloc failed (input too large?)');
		new Uint8Array(exp.memory.buffer, namePtr, nameBytes.byteLength).set(nameBytes);
		nameLen = nameBytes.byteLength;
	}

	const packed = exp.mintDreamBall(opts.typeId, namePtr, nameLen, opts.created);
	if (packed === 0n) {
		const ep = exp.resultErrPtr();
		const el = exp.resultErrLen();
		const msg = new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ep, el));
		throw new Error(`mintDreamBall: wasm returned 0: ${msg || '(no diagnostic)'}`);
	}

	const ptr = Number(packed >> 32n);
	const len = Number(packed & 0xffffffffn);
	const envelope = new Uint8Array(exp.memory.buffer, ptr, len).slice();

	// Read the generated secret from the WASM-internal last_secret buffer.
	// Must be read before the next reset() call.
	const sPtr = exp.lastSecretPtr();
	const sLen = exp.lastSecretLen();
	const secret = new Uint8Array(exp.memory.buffer, sPtr, sLen).slice();

	return { envelope, secret };
}

/**
 * Grow a DreamBall — bump revision, set updated timestamp, optionally rename,
 * re-sign, and return the updated signed envelope bytes.
 *
 * @param opts.envelope          Current signed DreamBall envelope (CBOR bytes)
 * @param opts.secret            64-byte Ed25519 secret: [seed(32) || pub(32)]
 * @param opts.newName           Optional new display name (omit to leave unchanged)
 * @param opts.updated           Updated timestamp as Unix seconds BigInt (i64)
 * @param opts.promoteToDreamball  If true, promote from seed→dreamball stage
 */
export async function growDreamBall(opts: {
	envelope: Uint8Array;
	secret: Uint8Array;
	newName?: string;
	updated: bigint;
	promoteToDreamball?: boolean;
}): Promise<Uint8Array> {
	if (opts.secret.length !== 64) {
		throw new Error(
			`growDreamBall: secret must be 64 bytes, got ${opts.secret.length}`
		);
	}

	const exp = await getInstance();
	exp.reset();

	const envPtr = exp.alloc(opts.envelope.length);
	if (envPtr === 0) throw new Error('growDreamBall: alloc failed (input too large?)');
	new Uint8Array(exp.memory.buffer, envPtr, opts.envelope.length).set(opts.envelope);

	const secretPtr = exp.alloc(64);
	if (secretPtr === 0) throw new Error('growDreamBall: alloc failed (input too large?)');
	new Uint8Array(exp.memory.buffer, secretPtr, 64).set(opts.secret);

	let newNamePtr = 0;
	let newNameLen = 0;
	if (opts.newName && opts.newName.length > 0) {
		const newNameBytes = new TextEncoder().encode(opts.newName);
		newNamePtr = exp.alloc(newNameBytes.byteLength);
		if (newNamePtr === 0) throw new Error('growDreamBall: alloc failed (input too large?)');
		new Uint8Array(exp.memory.buffer, newNamePtr, newNameBytes.byteLength).set(newNameBytes);
		newNameLen = newNameBytes.byteLength;
	}

	const packed = exp.growDreamBall(
		envPtr,
		opts.envelope.length,
		secretPtr,
		64,
		newNamePtr,
		newNameLen,
		opts.updated,
		opts.promoteToDreamball ? 1 : 0
	);
	if (packed === 0n) {
		const ep = exp.resultErrPtr();
		const el = exp.resultErrLen();
		const msg = new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ep, el));
		throw new Error(`growDreamBall: wasm returned 0: ${msg || '(no diagnostic)'}`);
	}

	const ptr = Number(packed >> 32n);
	const len = Number(packed & 0xffffffffn);
	return new Uint8Array(exp.memory.buffer, ptr, len).slice();
}

/**
 * Add a Guild membership to an existing DreamBall and return the re-signed
 * envelope bytes.
 *
 * @param opts.envelope       Current signed DreamBall envelope (CBOR bytes)
 * @param opts.guildEnvelope  Signed Guild DreamBall envelope (CBOR bytes)
 * @param opts.secret         64-byte Ed25519 secret: [seed(32) || pub(32)]
 * @param opts.updated        Updated timestamp as Unix seconds BigInt (i64)
 */
export async function joinGuild(opts: {
	envelope: Uint8Array;
	guildEnvelope: Uint8Array;
	secret: Uint8Array;
	updated: bigint;
}): Promise<Uint8Array> {
	if (opts.secret.length !== 64) {
		throw new Error(
			`joinGuild: secret must be 64 bytes, got ${opts.secret.length}`
		);
	}

	const exp = await getInstance();
	exp.reset();

	const envPtr = exp.alloc(opts.envelope.length);
	if (envPtr === 0) throw new Error('joinGuild: alloc failed (input too large?)');
	new Uint8Array(exp.memory.buffer, envPtr, opts.envelope.length).set(opts.envelope);

	const guildPtr = exp.alloc(opts.guildEnvelope.length);
	if (guildPtr === 0) throw new Error('joinGuild: alloc failed (input too large?)');
	new Uint8Array(exp.memory.buffer, guildPtr, opts.guildEnvelope.length).set(opts.guildEnvelope);

	const secretPtr = exp.alloc(64);
	if (secretPtr === 0) throw new Error('joinGuild: alloc failed (input too large?)');
	new Uint8Array(exp.memory.buffer, secretPtr, 64).set(opts.secret);

	const packed = exp.joinGuildWasm(
		envPtr,
		opts.envelope.length,
		guildPtr,
		opts.guildEnvelope.length,
		secretPtr,
		64,
		opts.updated
	);
	if (packed === 0n) {
		const ep = exp.resultErrPtr();
		const el = exp.resultErrLen();
		const msg = new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ep, el));
		throw new Error(`joinGuild: wasm returned 0: ${msg || '(no diagnostic)'}`);
	}

	const ptr = Number(packed >> 32n);
	const len = Number(packed & 0xffffffffn);
	return new Uint8Array(exp.memory.buffer, ptr, len).slice();
}

let modulePromise: Promise<WebAssembly.Module> | null = null;

async function getModule(): Promise<WebAssembly.Module> {
	if (!modulePromise) {
		modulePromise = (async () => {
			// Resolve the wasm URL via Vite's asset handling. `?url` makes
			// Vite copy the file into the build output and return its
			// resolved URL, which works in dev + production alike.
			const { default: wasmUrl } = await import('./dreamball.wasm?url');
			const resp = await fetch(wasmUrl);
			if (!resp.ok) throw new Error(`fetch dreamball.wasm: ${resp.status}`);
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
 * Parse a `.ball` byte array (bare CBOR envelope, sealed BALL wrapper,
 * or canonical JSON text) into a **fully validated** DreamBall.
 *
 * The WASM parser does the heavy lifting (CBOR → JSON); Valibot validates
 * the shape against `DreamBallSchema`. Throws `ValiError` on schema
 * mismatch, `Error` on parse failure.
 *
 * For a non-throwing variant, use `safeParseBall`.
 */
export async function parseBall(bytes: Uint8Array): Promise<DreamBallValidated> {
	const jsonText = await parseBallToJsonRaw(bytes);
	return v.parse(DreamBallSchema, JSON.parse(jsonText));
}

/**
 * Parse + validate, returning a tagged result instead of throwing.
 */
export async function safeParseBall(bytes: Uint8Array): Promise<ParseResult<DreamBallValidated>> {
	let jsonText: string;
	try {
		jsonText = await parseBallToJsonRaw(bytes);
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
 * Like `parseBall` but returns the validated JSON string (not a parsed
 * object). Useful for piping into other systems.
 */
export async function parseBallToJson(bytes: Uint8Array): Promise<string> {
	const db = await parseBall(bytes);
	return JSON.stringify(db);
}

/** Internal — bytes → WASM → JSON string, no schema validation. */
async function parseBallToJsonRaw(bytes: Uint8Array): Promise<string> {
	const exp = await getInstance();

	exp.reset();

	const inPtr = exp.alloc(bytes.length);
	if (inPtr === 0) throw new Error('dreamball-wasm: alloc failed (input too large?)');
	new Uint8Array(exp.memory.buffer, inPtr, bytes.length).set(bytes);

	const packed = exp.parseBall(inPtr, bytes.length);

	if (packed === 0n) {
		const ep = exp.resultErrPtr();
		const el = exp.resultErrLen();
		const msg = new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ep, el));
		throw new Error(`dreamball-wasm parse failed: ${msg || '(no diagnostic)'}`);
	}

	const resultPtr = Number(packed >> 32n);
	const resultLen = Number(packed & 0xffffffffn);
	return new TextDecoder().decode(new Uint8Array(exp.memory.buffer, resultPtr, resultLen));
}

/** Retained export for back-compat with any callers that want the unvalidated shape. */
export async function parseBallUnvalidated(bytes: Uint8Array): Promise<DreamBall> {
	const jsonText = await parseBallToJsonRaw(bytes);
	return JSON.parse(jsonText) as DreamBall;
}
