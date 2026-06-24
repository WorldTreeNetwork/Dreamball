#!/usr/bin/env bun
/**
 * Story 1.2 / D-029 — pre-codegen pin-verification gate.
 *
 * Reads every `schemas/*.json` in the repo, computes blake3 over each
 * file as-vendored, and compares to the pin recorded at
 * `schemas/.pins/<basename>.fp`. Exits non-zero on mismatch with a
 * structured error (schema path, expected pin, computed pin) BEFORE
 * any generator dispatches.
 *
 * Wired into `bun run codegen` per AC4.
 */

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, basename, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..');
const SCHEMAS_DIR = join(REPO_ROOT, 'schemas');
const PINS_DIR = join(SCHEMAS_DIR, '.pins');
const WASM_PATH = join(REPO_ROOT, 'src', 'lib', 'wasm', 'dreamball.wasm');

interface JellyExports {
	memory: WebAssembly.Memory;
	alloc(n: number): number;
	free(ptr: number, n: number): void;
	reset(): void;
	hashBlake3(inPtr: number, inLen: number, outPtr: number): void;
}

let cachedExports: JellyExports | null = null;

async function getExports(): Promise<JellyExports> {
	if (cachedExports) return cachedExports;
	if (!existsSync(WASM_PATH)) {
		throw new Error(
			`schemas-verify: dreamball.wasm not found at ${WASM_PATH}; run \`zig build wasm\`.`,
		);
	}
	const bytes = readFileSync(WASM_PATH);
	let inst: WebAssembly.Instance;
	const env = {
		getRandomBytes(ptr: number, len: number) {
			const mem = (inst.exports.memory as WebAssembly.Memory).buffer;
			crypto.getRandomValues(new Uint8Array(mem, ptr, len));
		},
	};
	const result = await WebAssembly.instantiate(bytes, { env });
	inst = result.instance;
	cachedExports = inst.exports as unknown as JellyExports;
	return cachedExports;
}

async function blake3Hex(bytes: Uint8Array): Promise<string> {
	const exp = await getExports();
	exp.reset();
	const inPtr = exp.alloc(bytes.length);
	const outPtr = exp.alloc(32);
	if (inPtr === 0 || outPtr === 0) throw new Error('schemas-verify: alloc failed');
	new Uint8Array(exp.memory.buffer, inPtr, bytes.length).set(bytes);
	exp.hashBlake3(inPtr, bytes.length, outPtr);
	const digest = new Uint8Array(exp.memory.buffer, outPtr, 32);
	return Array.from(digest)
		.map((b) => b.toString(16).padStart(2, '0'))
		.join('');
}

interface Mismatch {
	schemaPath: string;
	pinPath: string;
	expected: string;
	computed: string;
	reason: 'mismatch' | 'pin-missing';
}

async function verifyAll(): Promise<Mismatch[]> {
	if (!existsSync(SCHEMAS_DIR)) {
		// No schemas directory yet — nothing to verify.
		return [];
	}
	const files = readdirSync(SCHEMAS_DIR).filter((f) => f.endsWith('.json'));
	const mismatches: Mismatch[] = [];
	for (const f of files) {
		const schemaPath = join(SCHEMAS_DIR, f);
		const pinName = basename(f).replace(/\.json$/, '') + '.fp';
		const pinPath = join(PINS_DIR, pinName);
		const fileBytes = readFileSync(schemaPath);
		const computed = await blake3Hex(new Uint8Array(fileBytes));
		if (!existsSync(pinPath)) {
			mismatches.push({
				schemaPath,
				pinPath,
				expected: '<missing>',
				computed,
				reason: 'pin-missing',
			});
			continue;
		}
		const expected = readFileSync(pinPath, 'utf8');
		if (expected !== computed) {
			mismatches.push({
				schemaPath,
				pinPath,
				expected,
				computed,
				reason: 'mismatch',
			});
		}
	}
	return mismatches;
}

const mismatches = await verifyAll();
if (mismatches.length === 0) {
	console.log('schemas-verify: all schema pins match');
	process.exit(0);
}

console.error('schemas-verify: PIN VERIFICATION FAILED');
console.error('');
for (const m of mismatches) {
	console.error(`  schema:    ${m.schemaPath}`);
	console.error(`  pin file:  ${m.pinPath}`);
	console.error(`  expected:  ${m.expected}`);
	console.error(`  computed:  ${m.computed}`);
	console.error(`  reason:    ${m.reason}`);
	console.error('');
}
console.error(
	'Run `bun run schemas:pin <schema-path>` to refresh the pin if the schema change is intentional (D-029).',
);
process.exit(1);
