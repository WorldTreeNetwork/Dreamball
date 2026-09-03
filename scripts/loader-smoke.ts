#!/usr/bin/env bun
/**
 * B3 smoke gate — validates the authorAction + verifyAction WASM ABI
 * and the marshalling patterns implemented in src/lib/wasm/loader.ts.
 *
 * Directly instantiates dreamball.wasm (the Bun-compatible path, same as
 * schemas-pin.ts and spike-wasm-env.ts) and exercises every marshalling
 * step the TS wrappers perform, confirming the ABI is correct end-to-end.
 *
 * Exit 0 = all checks passed. Exit 1 = at least one failure.
 */

import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const WASM_PATH = resolve(__dirname, '..', 'src', 'lib', 'wasm', 'dreamball.wasm');

// ── WASM exports interface (B3 additions) ────────────────────────────────────

interface WasmExports {
	memory: WebAssembly.Memory;
	alloc: (size: number) => number;
	reset: () => void;
	authorAction: (
		kind_ptr: number, kind_len: number,
		body_ptr: number, body_len: number,
		parent_hashes_ptr: number, parent_hashes_count: number,
		hlc_l: bigint, hlc_c: bigint,
		secret_ptr: number,
	) => bigint;
	verifyAction: (ptr: number, len: number) => number;
	mintDreamBall: (type_id: number, name_ptr: number, name_len: number, created: bigint) => bigint;
	growDreamBall: (
		env_ptr: number, env_len: number,
		secret_ptr: number, secret_len: number,
		new_name_ptr: number, new_name_len: number,
		updated: bigint,
		promote_to_dreamball: number,
	) => bigint;
	lastSecretPtr: () => number;
	lastSecretLen: () => number;
	resultErrPtr: () => number;
	resultErrLen: () => number;
}

// ── WASM loader (Bun-compatible; mirrors loader.ts instantiate()) ─────────────

async function loadWasm(): Promise<WasmExports> {
	if (!existsSync(WASM_PATH)) {
		throw new Error(`dreamball.wasm not found at ${WASM_PATH}; run \`zig build wasm\` first.`);
	}
	const bytes = readFileSync(WASM_PATH);
	let inst!: WebAssembly.Instance;
	const env = {
		getRandomBytes(ptr: number, len: number) {
			const mem = (inst.exports.memory as WebAssembly.Memory).buffer;
			crypto.getRandomValues(new Uint8Array(mem, ptr, len));
		},
	};
	const result = await WebAssembly.instantiate(bytes, { env });
	inst = result.instance;
	return inst.exports as unknown as WasmExports;
}

// ── Low-level WASM helpers ────────────────────────────────────────────────────

function readErr(exp: WasmExports): string {
	const ep = exp.resultErrPtr();
	const el = exp.resultErrLen();
	return new TextDecoder().decode(new Uint8Array(exp.memory.buffer, ep, el));
}

function allocCopy(exp: WasmExports, bytes: Uint8Array, label: string): number {
	const ptr = exp.alloc(bytes.length);
	if (ptr === 0) throw new Error(`${label}: alloc failed`);
	new Uint8Array(exp.memory.buffer, ptr, bytes.length).set(bytes);
	return ptr;
}

function unpackResult(packed: bigint, exp: WasmExports): Uint8Array {
	if (packed === 0n) {
		const msg = readErr(exp);
		throw new Error(`WASM returned 0: ${msg || '(no diagnostic)'}`);
	}
	const ptr = Number(packed >> 32n);
	const len = Number(packed & 0xffffffffn);
	return new Uint8Array(exp.memory.buffer, ptr, len).slice();
}

// ── Wrapper implementations (mirror loader.ts wrappers) ──────────────────────

/**
 * authorAction — mirrors loader.ts authorAction().
 * secret must be a proper Zig Ed25519 secret key: [seed(32) || pub(32)] where
 * pub matches the seed. Use the output of mintDreamBall to get a valid secret.
 */
function callAuthorAction(
	exp: WasmExports,
	kind: string,
	body: Uint8Array | undefined,
	parents: Uint8Array[],
	hlc: [bigint, bigint],
	secret: Uint8Array,
): Uint8Array {
	if (secret.length !== 64) {
		throw new Error(`authorAction: secret must be 64 bytes, got ${secret.length}`);
	}
	if (kind.length === 0) {
		throw new Error('authorAction: kind must be non-empty');
	}

	exp.reset();

	const kindBytes = new TextEncoder().encode(kind);
	const kindPtr = allocCopy(exp, kindBytes, 'authorAction:kind');

	let bodyPtr = 0, bodyLen = 0;
	if (body && body.length > 0) {
		bodyPtr = allocCopy(exp, body, 'authorAction:body');
		bodyLen = body.length;
	}

	let phPtr = 0;
	const parentCount = parents.length;
	if (parentCount > 0) {
		for (let i = 0; i < parentCount; i++) {
			if (parents[i].length !== 32) {
				throw new Error(`authorAction: parent[${i}] must be 32 bytes, got ${parents[i].length}`);
			}
		}
		const ph = new Uint8Array(parentCount * 32);
		for (let i = 0; i < parentCount; i++) ph.set(parents[i], i * 32);
		phPtr = allocCopy(exp, ph, 'authorAction:parents');
	}

	const secretPtr = allocCopy(exp, secret, 'authorAction:secret');

	const packed = exp.authorAction(
		kindPtr, kindBytes.byteLength,
		bodyPtr, bodyLen,
		phPtr, parentCount,
		hlc[0], hlc[1],
		secretPtr,
	);
	return unpackResult(packed, exp);
}

/** verifyAction — mirrors loader.ts verifyAction(). */
function callVerifyAction(
	exp: WasmExports,
	envelope: Uint8Array,
): { ok: boolean; code: number; reason?: string } {
	exp.reset();
	const ptr = allocCopy(exp, envelope, 'verifyAction:envelope');
	const result = exp.verifyAction(ptr, envelope.length);
	if (result === 2) return { ok: true, code: 2 };
	if (result === 1) return { ok: true, code: 1 };
	const reason = readErr(exp);
	return { ok: false, code: result, reason };
}

/** mintDreamBall — mirrors loader.ts mintDreamBall(). */
function callMintDreamBall(
	exp: WasmExports,
	typeId: number,
	name: string | undefined,
	created: bigint,
): { envelope: Uint8Array; secret: Uint8Array } {
	exp.reset();
	let namePtr = 0, nameLen = 0;
	if (name && name.length > 0) {
		const nameBytes = new TextEncoder().encode(name);
		namePtr = allocCopy(exp, nameBytes, 'mintDreamBall:name');
		nameLen = nameBytes.byteLength;
	}
	const packed = exp.mintDreamBall(typeId, namePtr, nameLen, created);
	const envelope = unpackResult(packed, exp);
	const sPtr = exp.lastSecretPtr();
	const sLen = exp.lastSecretLen();
	const secret = new Uint8Array(exp.memory.buffer, sPtr, sLen).slice();
	return { envelope, secret };
}

// ── Test harness ──────────────────────────────────────────────────────────────

const PASS: string[] = [];
const FAIL: string[] = [];

function pass(label: string): void {
	console.log(`  PASS  ${label}`);
	PASS.push(label);
}

function fail(label: string, detail: string): void {
	console.error(`  FAIL  ${label}: ${detail}`);
	FAIL.push(label);
}

function check(label: string, fn: () => void | Promise<void>): void {
	try {
		const r = fn();
		if (r instanceof Promise) {
			r.then(() => pass(label)).catch((e: unknown) => fail(label, (e as Error).message ?? String(e)));
		} else {
			pass(label);
		}
	} catch (e) {
		fail(label, (e as Error).message ?? String(e));
	}
}

function expectThrows(label: string, fn: () => void, expectedFragment: string): void {
	try {
		fn();
		fail(label, `expected throw containing "${expectedFragment}" but no error was thrown`);
	} catch (e) {
		const msg = (e as Error).message ?? String(e);
		if (msg.includes(expectedFragment)) {
			pass(label);
			console.log(`         message: "${msg}"`);
		} else {
			fail(label, `threw but message "${msg}" does not include "${expectedFragment}"`);
		}
	}
}

// ── Main ──────────────────────────────────────────────────────────────────────

console.log('loader-smoke: B3 authorAction + verifyAction + mint/grow WASM ABI');
console.log();

const exp = await loadWasm();

const KIND = 'worldtree.kanban-card.move';
const BODY = new Uint8Array([0x82, 0x01, 0x02]);
const PARENT = new Uint8Array(32).fill(0x10);
const HLC: [bigint, bigint] = [1_700_000_000_000n, 7n];
const CREATED = BigInt(Math.floor(Date.now() / 1000));

// ── Dreamball-t2d: mintDreamBall — must run first to get a valid secret ───────
// All-zeros for the full 64-byte secret puts zeros in secret[32..64] (the
// embedded actor/pub key), but signing uses the key derived from secret[0..32].
// That mismatch causes verifyAction to fail. Use mintDreamBall to obtain a
// properly-formed [seed(32) || pub(32)] secret where pub matches the seed.

let mintedEnvelope: Uint8Array;
let mintedSecret: Uint8Array;

check('mintDreamBall returns envelope + 64-byte secret (avatar)', () => {
	const result = callMintDreamBall(exp, 0 /* avatar */, 'Smoke Avatar', CREATED);
	if (!(result.envelope instanceof Uint8Array) || result.envelope.length === 0) {
		throw new Error(`envelope empty: length=${result.envelope?.length}`);
	}
	if (result.secret.length !== 64) {
		throw new Error(`expected 64-byte secret, got ${result.secret.length}`);
	}
	mintedEnvelope = result.envelope;
	mintedSecret = result.secret;
	console.log(`         envelope: ${result.envelope.length} bytes, secret: ${result.secret.length} bytes`);
});

// ── AC1: authorAction round-trip ─────────────────────────────────────────────

let signedEnvelope: Uint8Array | undefined;

check('authorAction returns non-empty Uint8Array', () => {
	// Use the secret from mintDreamBall — a valid [seed(32)||pub(32)] where
	// pub correctly matches the seed, so the actor embedded in the action
	// matches the signing key and verifyAction can validate it.
	signedEnvelope = callAuthorAction(exp, KIND, BODY, [PARENT], HLC, mintedSecret);
	if (!(signedEnvelope instanceof Uint8Array) || signedEnvelope.length === 0) {
		throw new Error(`expected non-empty Uint8Array, got length ${signedEnvelope?.length}`);
	}
	console.log(`         envelope length: ${signedEnvelope.length} bytes`);
});

// ── AC2: verifyAction on valid envelope ──────────────────────────────────────

check('verifyAction(signed) → ok: true, code: 2', () => {
	if (!signedEnvelope) throw new Error('signedEnvelope not set (AC1 failed)');
	const r = callVerifyAction(exp, signedEnvelope);
	if (!r.ok) throw new Error(`expected ok:true, got code=${r.code} reason=${r.reason}`);
	if (r.code !== 2) throw new Error(`expected code 2 (verified), got ${r.code}`);
	console.log(`         code: ${r.code}`);
});

// ── AC2: verifyAction on tampered envelope ───────────────────────────────────

check('verifyAction(tampered byte 0) → ok: false', () => {
	if (!signedEnvelope) throw new Error('signedEnvelope not set (AC1 failed)');
	const tampered = signedEnvelope.slice();
	tampered[0] ^= 0xff;
	const r = callVerifyAction(exp, tampered);
	if (r.ok) throw new Error(`expected ok:false on tampered envelope, got ok:true`);
	console.log(`         code: ${r.code}  reason: ${r.reason}`);
});

// ── AC3: JS-side pre-validation (secret length) ──────────────────────────────

expectThrows(
	'authorAction guard: secret.length !== 64 → descriptive Error',
	() => callAuthorAction(exp, KIND, BODY, [PARENT], HLC, new Uint8Array(63)),
	'secret must be 64 bytes',
);

// ── AC3: JS-side pre-validation (empty kind) ─────────────────────────────────

expectThrows(
	'authorAction guard: empty kind → descriptive Error',
	() => callAuthorAction(exp, '', BODY, [PARENT], HLC, mintedSecret),
	'kind must be non-empty',
);

// ── Dreamball-t2d: growDreamBall ──────────────────────────────────────────────

check('growDreamBall(minted envelope) → non-empty Uint8Array', () => {
	exp.reset();
	const envPtr = allocCopy(exp, mintedEnvelope, 'growDreamBall:env');
	const secretPtr = allocCopy(exp, mintedSecret, 'growDreamBall:secret');
	const newNameBytes = new TextEncoder().encode('Grown Avatar');
	const newNamePtr = allocCopy(exp, newNameBytes, 'growDreamBall:name');
	const updated = BigInt(Math.floor(Date.now() / 1000));

	const packed = exp.growDreamBall(
		envPtr, mintedEnvelope.length,
		secretPtr, 64,
		newNamePtr, newNameBytes.byteLength,
		updated,
		1, // promote to dreamball
	);
	const grown = unpackResult(packed, exp);
	if (grown.length === 0) throw new Error('growDreamBall returned empty bytes');
	console.log(`         grown envelope: ${grown.length} bytes`);
});

// ── Summary ───────────────────────────────────────────────────────────────────

console.log();
console.log(`loader-smoke: ${PASS.length} passed, ${FAIL.length} failed`);
if (FAIL.length > 0) {
	console.error(`Failed checks: ${FAIL.join(', ')}`);
	process.exit(1);
}
console.log('loader-smoke: OK');
