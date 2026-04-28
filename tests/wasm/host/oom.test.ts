/**
 * Story 5.3 AC5 / AC8 — OOM / memory-limit fixture test.
 *
 * Given a guest that declares memory beyond the 64 MiB hard ceiling,
 * When the host checks the memory limit BEFORE instantiation,
 * Then the host rejects with a structured event indicating
 * `{scenario: "oom", outcome: "memory_limit_exceeded", initial_pages, max_mib}`.
 *
 * Per NFR7: hard ceiling is non-negotiable at 64 MiB (1024 pages).
 * This test uses a 1025-page (65 MiB) guest.
 *
 * This test invokes the `wasm-host-failure-test` Zig binary (built by
 * `zig build wasm-host-failure-test`) and parses its JSON output.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { execSync } from 'child_process';
import { resolve } from 'path';

const REPO_ROOT = resolve(__dirname, '..', '..', '..');
const BINARY = resolve(REPO_ROOT, 'zig-out', 'bin', 'wasm-host-failure-test');

const HARD_CEILING_MIB = 64;
const PAGE_SIZE = 65536;

interface OomEvent {
	scenario: 'oom';
	outcome: 'memory_limit_exceeded';
	initial_pages: number;
	max_mib: number;
	attempted_alloc_bytes: number;
}

function runFailureTest(): OomEvent | null {
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
			if (obj.scenario === 'oom') {
				return obj as unknown as OomEvent;
			}
		} catch {
			// skip non-JSON lines
		}
	}
	return null;
}

describe('OOM / memory-limit failure path (AC3, AC5, NFR7)', () => {
	let event: OomEvent;

	beforeAll(() => {
		const result = runFailureTest();
		if (!result) {
			throw new Error('oom scenario not found in wasm-host-failure-test output');
		}
		event = result;
	});

	it('emits outcome=memory_limit_exceeded', () => {
		expect(event.outcome).toBe('memory_limit_exceeded');
	});

	it('initial_pages exceeds the hard ceiling of 64 MiB (1024 pages)', () => {
		const hardCeilingPages = (HARD_CEILING_MIB * 1024 * 1024) / PAGE_SIZE;
		expect(event.initial_pages).toBeGreaterThan(hardCeilingPages);
	});

	it('max_mib matches the NFR7 hard ceiling of 64 MiB', () => {
		expect(event.max_mib).toBe(HARD_CEILING_MIB);
	});

	it('attempted_alloc_bytes matches initial_pages * PAGE_SIZE', () => {
		expect(event.attempted_alloc_bytes).toBe(event.initial_pages * PAGE_SIZE);
	});
});
