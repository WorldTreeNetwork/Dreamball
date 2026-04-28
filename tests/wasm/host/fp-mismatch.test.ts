/**
 * Story 5.3 AC1 / AC8 — fp-mismatch fixture test.
 *
 * Given a fixture wasm module + a deliberately-wrong fp,
 * When the host attempts instantiation,
 * Then the host rejects BEFORE any guest code runs and emits a structured
 * event with `{outcome: "fp_mismatch", expected, actual, module_fp}`.
 *
 * This test invokes the `wasm-host-failure-test` Zig binary (built by
 * `zig build wasm-host-failure-test`) and parses its JSON output.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { execSync } from 'child_process';
import { resolve } from 'path';

const REPO_ROOT = resolve(__dirname, '..', '..', '..');
const BINARY = resolve(REPO_ROOT, 'zig-out', 'bin', 'wasm-host-failure-test');

interface FpMismatchEvent {
	scenario: 'fp_mismatch';
	outcome: 'fp_mismatch';
	expected: string;
	actual: string;
}

function runFailureTest(): FpMismatchEvent | null {
	let stdout: string;
	try {
		stdout = execSync(BINARY, { encoding: 'utf8' });
	} catch (e: unknown) {
		const err = e as { stdout?: string; stderr?: string; status?: number };
		throw new Error(
			`wasm-host-failure-test exited ${err.status}.\nstdout: ${err.stdout}\nstderr: ${err.stderr}`
		);
	}

	for (const line of stdout.split('\n')) {
		const trimmed = line.trim();
		if (!trimmed) continue;
		try {
			const obj = JSON.parse(trimmed) as Record<string, unknown>;
			if (obj.scenario === 'fp_mismatch') {
				return obj as unknown as FpMismatchEvent;
			}
		} catch {
			// skip non-JSON lines
		}
	}
	return null;
}

describe('fp-mismatch failure path (AC1, SEC4, D-031)', () => {
	let event: FpMismatchEvent;

	beforeAll(() => {
		const result = runFailureTest();
		if (!result) {
			throw new Error('fp_mismatch scenario not found in wasm-host-failure-test output');
		}
		event = result;
	});

	it('emits outcome=fp_mismatch', () => {
		expect(event.outcome).toBe('fp_mismatch');
	});

	it('expected and actual fields are 64-char lowercase hex strings', () => {
		expect(event.expected).toMatch(/^[0-9a-f]{64}$/);
		expect(event.actual).toMatch(/^[0-9a-f]{64}$/);
	});

	it('expected and actual differ (wrong fp was deliberately passed)', () => {
		expect(event.expected).not.toBe(event.actual);
	});
});
