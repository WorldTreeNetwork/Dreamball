#!/usr/bin/env bun
/**
 * A0 spike — prove that jelly.wasm can consume host randomness via an
 * env.getRandomBytes import. Success criterion: two consecutive calls to
 * spikeRandom32 return 32 random bytes each, non-zero, and not equal to
 * each other.
 *
 * If this passes, every write-op in Phase A can lean on the same import
 * pattern — no subprocess, no FFI, just WASM.
 */

import { readFileSync } from 'fs';
import { resolve } from 'path';

const wasmPath = resolve(import.meta.dir, '..', 'src', 'lib', 'wasm', 'jelly.wasm');
const wasmBytes = readFileSync(wasmPath);
const mod = await WebAssembly.compile(wasmBytes);

const env = {
	getRandomBytes(ptr: number, len: number) {
		const bytes = new Uint8Array((inst.exports.memory as WebAssembly.Memory).buffer, ptr, len);
		crypto.getRandomValues(bytes);
	}
};

const inst = await WebAssembly.instantiate(mod, { env });
const exports = inst.exports as {
	memory: WebAssembly.Memory;
	reset: () => void;
	spikeRandom32: () => number;
};

function readRandom(): Uint8Array {
	exports.reset();
	const ptr = exports.spikeRandom32();
	if (ptr === 0) throw new Error('spikeRandom32 returned 0 — allocator failed');
	const bytes = new Uint8Array(exports.memory.buffer, ptr, 32);
	return new Uint8Array(bytes); // copy so reset() doesn't clobber
}

const a = readRandom();
const b = readRandom();

const allZero = (buf: Uint8Array) => buf.every((x) => x === 0);
const equal = (x: Uint8Array, y: Uint8Array) => x.every((v, i) => v === y[i]);

if (allZero(a)) {
	console.error('FAIL: first call returned all zeros — host randomness import not wired');
	process.exit(1);
}
if (allZero(b)) {
	console.error('FAIL: second call returned all zeros');
	process.exit(1);
}
if (equal(a, b)) {
	console.error('FAIL: two consecutive calls returned identical bytes — host RNG not reseeding');
	process.exit(1);
}

const hex = (buf: Uint8Array) => Array.from(buf, (x) => x.toString(16).padStart(2, '0')).join('');
console.log('A0 spike PASS — WASM env-import plumbing works on Bun.');
console.log(`  call 1: ${hex(a)}`);
console.log(`  call 2: ${hex(b)}`);
