#!/usr/bin/env bun
/**
 * Story 1.2 / D-029 — pin a JSON Schema by writing the blake3 of the
 * file as-vendored to `schemas/.pins/<basename>.fp`.
 *
 * Usage: `bun run scripts/schemas-pin.ts <schema-path>`
 *   e.g. `bun run schemas:pin schemas/root-2.0.0.json`
 *
 * D-029 Option A pin format: plain text, single line, hex-encoded
 * blake3, NO trailing newline. The pin is computed over the bytes
 * exactly as written to disk (LF endings preserved). The vendored
 * file IS the canonical form; no canonicalization step.
 *
 * Implementation note: blake3 is exposed via dreamball.wasm. We require
 * the wasm artifact to be present (see `zig build wasm`); the script
 * loads it directly via `WebAssembly.instantiate` to avoid the
 * Vite-flavored import in `src/lib/wasm/loader.ts`.
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, basename, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..');
const WASM_PATH = join(REPO_ROOT, 'src', 'lib', 'wasm', 'dreamball.wasm');

interface JellyExports {
	memory: WebAssembly.Memory;
	alloc(n: number): number;
	free(ptr: number, n: number): void;
	reset(): void;
	hashBlake3(inPtr: number, inLen: number, outPtr: number): void;
}

async function loadWasm(): Promise<JellyExports> {
	if (!existsSync(WASM_PATH)) {
		throw new Error(
			`dreamball.wasm not found at ${WASM_PATH}; run \`zig build wasm\` first.`,
		);
	}
	const bytes = readFileSync(WASM_PATH);
	// Two-phase instantiation so env.getRandomBytes can close over the
	// instance's memory (mirrors src/lib/wasm/loader.ts).
	let inst: WebAssembly.Instance;
	const env = {
		getRandomBytes(ptr: number, len: number) {
			const mem = (inst.exports.memory as WebAssembly.Memory).buffer;
			crypto.getRandomValues(new Uint8Array(mem, ptr, len));
		},
	};
	const result = await WebAssembly.instantiate(bytes, { env });
	inst = result.instance;
	return inst.exports as unknown as JellyExports;
}

async function blake3Hex(bytes: Uint8Array): Promise<string> {
	const exp = await loadWasm();
	exp.reset();
	const inPtr = exp.alloc(bytes.length);
	const outPtr = exp.alloc(32);
	if (inPtr === 0 || outPtr === 0) {
		throw new Error('schemas-pin: wasm alloc failed');
	}
	new Uint8Array(exp.memory.buffer, inPtr, bytes.length).set(bytes);
	exp.hashBlake3(inPtr, bytes.length, outPtr);
	const digest = new Uint8Array(exp.memory.buffer, outPtr, 32);
	return Array.from(digest)
		.map((b) => b.toString(16).padStart(2, '0'))
		.join('');
}

async function main() {
	const schemaPath = process.argv[2];
	if (!schemaPath) {
		console.error('usage: bun run schemas:pin <schema-path>');
		process.exit(2);
	}
	const absSchema = resolve(schemaPath);
	if (!existsSync(absSchema)) {
		console.error(`schemas-pin: schema not found: ${absSchema}`);
		process.exit(2);
	}
	const fileBytes = readFileSync(absSchema);
	const hex = await blake3Hex(new Uint8Array(fileBytes));

	// Pin lives at schemas/.pins/<basename>.fp where <basename> is the
	// schema filename minus its `.json` extension. Per D-029 Option A.
	const schemaBase = basename(absSchema).replace(/\.json$/, '');
	const pinDir = join(REPO_ROOT, 'schemas', '.pins');
	mkdirSync(pinDir, { recursive: true });
	const pinPath = join(pinDir, `${schemaBase}.fp`);

	// CRITICAL: NO trailing newline — D-029 pin format requires exactly
	// the hex digest as the file contents. Bun's `writeFileSync` does
	// NOT add one; verified by reading back below.
	writeFileSync(pinPath, hex);

	const back = readFileSync(pinPath, 'utf8');
	if (back !== hex) {
		console.error(
			`schemas-pin: post-write check failed — pin file has trailing whitespace or extra content`,
		);
		process.exit(3);
	}

	console.log(`pinned ${schemaPath}`);
	console.log(`  -> ${pinPath}`);
	console.log(`     ${hex}`);
}

await main();
