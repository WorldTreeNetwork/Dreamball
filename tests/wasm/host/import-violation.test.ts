/**
 * Story 5.3 AC2 / AC8 — import-violation fixture test.
 *
 * Given a guest module that imports `env.malicious_function`
 * (any name outside `dreamball.*`),
 * When the host validates imports at module load,
 * Then validation fails BEFORE instantiation and a structured event is
 * emitted with `{outcome: "import_violation", offending_import, module_fp}`.
 *
 * This test invokes the `wasm-host-failure-test` Zig binary (built by
 * `zig build wasm-host-failure-test`) and parses its JSON output.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { execSync } from 'child_process';
import { resolve } from 'path';

const REPO_ROOT = resolve(__dirname, '..', '..', '..');
const BINARY = resolve(REPO_ROOT, 'zig-out', 'bin', 'wasm-host-failure-test');

interface ImportViolationEvent {
	scenario: 'import_violation';
	outcome: 'import_violation';
	offending_import: string;
	module_fp: string;
}

function runFailureTest(): ImportViolationEvent | null {
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
			if (obj.scenario === 'import_violation') {
				return obj as unknown as ImportViolationEvent;
			}
		} catch {
			// skip non-JSON lines
		}
	}
	return null;
}

describe('import-violation failure path (AC2, SEC1, D-033)', () => {
	let event: ImportViolationEvent;

	beforeAll(() => {
		const result = runFailureTest();
		if (!result) {
			throw new Error('import_violation scenario not found in wasm-host-failure-test output');
		}
		event = result;
	});

	it('emits outcome=import_violation', () => {
		expect(event.outcome).toBe('import_violation');
	});

	it('identifies the offending import as env.malicious_function', () => {
		expect(event.offending_import).toBe('env.malicious_function');
	});

	it('module_fp is a 64-char lowercase hex string', () => {
		expect(event.module_fp).toMatch(/^[0-9a-f]{64}$/);
	});
});
