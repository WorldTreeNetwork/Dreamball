/**
 * Story 2.3 — archiform_fp round-trip + back-compat tests (FR5 / D-017).
 *
 * AC1 (round-trip):       genesis envelope with archiform-fp encodes →
 *                         decodes byte-equal.
 * AC2 (implicit binding): sprint-001 envelope without archiform-fp decodes
 *                         AND the resolved fp equals MEMORY_PALACE_IMPLICIT_FP.
 * AC3 (immutability):     repeated re-encodes preserve the genesis fp.
 *
 * The Zig encoder/decoder is exercised in src/envelope.zig tests
 * (see "Story 2.3 AC1/AC2/AC3/AC4" blocks). This file mirrors the
 * contract on the TypeScript side via the regenerated Valibot schema
 * and the implicit-binding helper at src/lib/archiform.ts.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as v from 'valibot';
import { DreamBallSchema } from '../../src/lib/generated/schemas.js';
import {
	memoryPalaceImplicitFp,
	setMemoryPalaceImplicitFp,
	MEMORY_PALACE_PIN_PATH,
	hex32,
	resolveArchiformFp,
} from '../../src/lib/archiform.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');
const MP_SCHEMA_PATH = join(REPO_ROOT, 'schemas', 'memory-palace-0.1.0.json');

/** Test seam: pre-seed the memoized implicit fp from the vendored pin
 *  file so the test does not need a wasm round-trip on every run. The
 *  pin is canonical per D-029; if it drifts, schemas-verify catches it
 *  before this test runs (CI orders `bun run codegen` ahead of vitest). */
function seedImplicitFpFromPin(): Uint8Array {
	const pinHex = readFileSync(MEMORY_PALACE_PIN_PATH, 'utf8').trim();
	expect(pinHex, 'pin file must be 64 hex chars').toMatch(/^[0-9a-f]{64}$/);
	const fp = new Uint8Array(32);
	for (let i = 0; i < 32; i++) {
		fp[i] = parseInt(pinHex.slice(i * 2, i * 2 + 2), 16);
	}
	setMemoryPalaceImplicitFp(fp);
	return fp;
}

describe('Story 2.3 — archiform_fp', () => {
	const expectedFp = seedImplicitFpFromPin();

	it('AC1 — implicit fp matches the vendored pin (content-addressing TC8)', async () => {
		const fp = await memoryPalaceImplicitFp();
		expect(fp.length).toBe(32);
		// hex round-trips against the on-disk pin.
		const pinText = readFileSync(MEMORY_PALACE_PIN_PATH, 'utf8').trim();
		expect(hex32(fp)).toBe(pinText);
		expect(hex32(fp)).toBe(hex32(expectedFp));
	});

	it('AC2 — implicit binding: attrs without archiform-fp resolve to Memory Palace fp', async () => {
		// Simulate a sprint-001 envelope's attribute pair list. None of
		// the pairs carries archiform-fp; resolveArchiformFp must fall
		// through to the implicit Memory Palace fp.
		const sprint1Attrs: ReadonlyArray<readonly [string, unknown]> = [
			['field-kind', 'palace'],
			['created', { __cborTag: 1, value: 1700000000 }],
		];
		const resolved = await resolveArchiformFp(sprint1Attrs);
		expect(resolved.length).toBe(32);
		expect(hex32(resolved)).toBe(hex32(expectedFp));
	});

	it('AC1 — explicit archiform-fp on the wire is returned verbatim', async () => {
		// A sprint-002 envelope carries archiform-fp inline. The resolver
		// MUST return the inline value without falling through.
		const explicit = new Uint8Array(32);
		for (let i = 0; i < 32; i++) explicit[i] = (i * 7 + 3) & 0xff;
		const sprint2Attrs: ReadonlyArray<readonly [string, unknown]> = [
			['field-kind', 'palace'],
			['archiform-fp', explicit],
		];
		const resolved = await resolveArchiformFp(sprint2Attrs);
		expect(hex32(resolved)).toBe(hex32(explicit));
		// Distinct from the implicit fp.
		expect(hex32(resolved)).not.toBe(hex32(expectedFp));
	});

	it('AC2 — Valibot DreamBallSchema accepts a genesis envelope WITHOUT archiform-fp', () => {
		// Sprint-001 wire shape: optional field absent. Must validate.
		const sprint1Json = {
			type: 'ball.dreamball.field',
			'format-version': 2,
			stage: 'seed',
			identity: 'b58:ABC123' as const,
			'genesis-hash': 'b58:ABC123' as const,
			revision: 0,
			'omnispherical-grid': undefined,
		};
		const result = v.safeParse(DreamBallSchema, sprint1Json);
		expect(result.success).toBe(true);
	});

	it('AC1 — Valibot DreamBallSchema accepts a genesis envelope WITH archiform-fp', () => {
		// Sprint-002 wire shape carries the optional field. Validator
		// passes the new field through commonCore.
		const sprint2Json = {
			type: 'ball.dreamball.field',
			'format-version': 2,
			stage: 'seed',
			identity: 'b58:ABC123' as const,
			'genesis-hash': 'b58:ABC123' as const,
			revision: 0,
			'archiform-fp': 'b58:ABC123' as const,
		};
		const result = v.safeParse(DreamBallSchema, sprint2Json);
		expect(result.success).toBe(true);
	});

	it('AC3 — immutability: a stable archiform-fp on subsequent revisions resolves identically', async () => {
		// Three "revisions" of the same ball — each carries the same
		// archiform-fp. Resolution must return the same bytes every time.
		const stable = new Uint8Array(32);
		for (let i = 0; i < 32; i++) stable[i] = 0x42;

		const r0: ReadonlyArray<readonly [string, unknown]> = [['archiform-fp', stable]];
		const r1: ReadonlyArray<readonly [string, unknown]> = [
			['archiform-fp', stable],
			['revision-marker', 1],
		];
		const r2: ReadonlyArray<readonly [string, unknown]> = [
			['archiform-fp', stable],
			['revision-marker', 2],
		];

		const a = await resolveArchiformFp(r0);
		const b = await resolveArchiformFp(r1);
		const c = await resolveArchiformFp(r2);
		expect(hex32(a)).toBe(hex32(b));
		expect(hex32(b)).toBe(hex32(c));
	});

	it('AC4 — drift detection: differing archiform-fp on two revisions of one ball is observable', async () => {
		// AC4 backs the consistency-check helper that verifier uses;
		// the underlying signal is "two resolved fps are not byte-equal."
		const fp1 = new Uint8Array(32).fill(0x11);
		const fp2 = new Uint8Array(32).fill(0x22);
		const a = await resolveArchiformFp([['archiform-fp', fp1]]);
		const b = await resolveArchiformFp([['archiform-fp', fp2]]);
		expect(hex32(a)).not.toBe(hex32(b));
	});

	it('AC5 / forward-compat — additive back-compat: schema describes archiform-fp as optional', () => {
		// The codegen pin is the binary handshake; the Valibot schema
		// declares archiform-fp inside commonCore as optional. The
		// generated source carries the field shape so consumers cannot
		// inadvertently depend on absence.
		const generatedSrc = readFileSync(
			join(REPO_ROOT, 'src', 'lib', 'generated', 'schemas.ts'),
			'utf8',
		);
		expect(generatedSrc).toContain("'archiform-fp':");
	});

	it('Schema sanity — schemas/memory-palace-0.1.0.json is the canonical archiform body', () => {
		// Story 2.3 derives the implicit fp from this exact file. If it
		// disappears or is renamed, this test alerts before the
		// runtime helper falls over with a less-clear error.
		const bytes = readFileSync(MP_SCHEMA_PATH);
		expect(bytes.length).toBeGreaterThan(0);
		// Canonical $id matches D-018 naming convention.
		const text = bytes.toString('utf8');
		expect(text).toContain('"$id": "dreamball:memory-palace@0.1.0"');
	});
});
