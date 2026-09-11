import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
	addressKey,
	isTransmittableAddress,
	loadCoverage,
	loadCoverageFromBytes,
	memoryCoverageSource
} from './coverage.js';
import { transmittableLocator } from './transmittable.js';

const FIXTURE = resolve(process.cwd(), 'static/coverage/lightning-fleet.ball');

function fixtureBytes(): Uint8Array {
	return new Uint8Array(readFileSync(FIXTURE));
}

describe('coverage address', () => {
	it('distinguishes fingerprint from transmittable locator', () => {
		expect(isTransmittableAddress({ fingerprint: 'abc' })).toBe(false);
		expect(isTransmittableAddress(transmittableLocator('mesh', 'lightning-fleet.ball'))).toBe(true);
		expect(addressKey({ fingerprint: 'abc' })).toBe('fp:abc');
		expect(addressKey({ bucket: 'mesh', filename: 'lightning-fleet.ball' })).toBe(
			'tx:mesh/lightning-fleet.ball'
		);
	});
});

describe('loadCoverageFromBytes', () => {
	it('verify+parse exposes the four-router fleet and render recipe', async () => {
		const result = await loadCoverageFromBytes(fixtureBytes());
		expect(result.ok).toBe(true);
		if (!result.ok) return;
		const ids = result.coverage.nodes.map((n) => n.id);
		expect(ids).toEqual(['wr3000s-a', 'm3000-b', 'tr3000', 'm3000']);
		expect(result.coverage.nodes[0]?.name).toBe('Front Porch');
		expect(result.coverage.nodes[1]?.name).toBe('Kitchen');
		expect(result.coverage.nodes[2]?.name).toBe('Workshop');
		expect(result.coverage.nodes[3]?.name).toBe('Hill');
		expect(result.coverage.nodes[0]?.['backhaul-addr']).toBe('10.254.242.84');
		expect(result.coverage.render?.paint).toBe('magenta-tiles');
		expect(result.coverage.render?.score).toBe('hud');
		expect(result.coverage.samples?.length).toBeGreaterThan(0);
		expect(result.identity).toMatch(/^b58:/);
		expect(result.ball.look).toBeUndefined();
		expect(result.ball.feel).toBeUndefined();
		expect(result.ball.act).toBeUndefined();
	});

	it('corrupt bytes surface the wasm reason and invent no ball', async () => {
		const result = await loadCoverageFromBytes(new Uint8Array([0xff, 0xff, 0xff, 0xff]));
		expect(result.ok).toBe(false);
		if (result.ok) return;
		expect(result.code === 'verify-failed' || result.code === 'parse-failed').toBe(true);
		expect(result.reason.length).toBeGreaterThan(0);
		expect(result).not.toHaveProperty('ball');
		expect(result).not.toHaveProperty('coverage');
	});

	it('tampered fixture fails verify with a wasm reason', async () => {
		const bytes = fixtureBytes();
		bytes[Math.min(60, bytes.length - 1)] ^= 0x01;
		const result = await loadCoverageFromBytes(bytes);
		expect(result.ok).toBe(false);
		if (result.ok) return;
		expect(result.code).toBe('verify-failed');
		expect(result.reason.length).toBeGreaterThan(0);
	});
});

describe('loadCoverage locator vs fingerprint', () => {
	it('both addresses decode to the same identity', async () => {
		const bytes = fixtureBytes();
		const parsed = await loadCoverageFromBytes(bytes);
		expect(parsed.ok).toBe(true);
		if (!parsed.ok) return;

		const fp = parsed.identity.startsWith('b58:') ? parsed.identity.slice(4) : parsed.identity;
		const locator = transmittableLocator('mesh', 'lightning-fleet.ball');
		const source = memoryCoverageSource(
			new Map([
				[addressKey({ fingerprint: fp }), bytes],
				[addressKey(locator), bytes]
			])
		);

		const byFp = await loadCoverage({ fingerprint: fp }, source);
		const byTx = await loadCoverage(locator, source);
		expect(byFp.ok).toBe(true);
		expect(byTx.ok).toBe(true);
		if (!byFp.ok || !byTx.ok) return;
		expect(byFp.identity).toBe(parsed.identity);
		expect(byTx.identity).toBe(parsed.identity);
		expect(byFp.coverage.nodes.map((n) => n.id)).toEqual(byTx.coverage.nodes.map((n) => n.id));
	});

	it('missing object is not-found, no invented ball', async () => {
		const result = await loadCoverage({ fingerprint: 'missing' }, memoryCoverageSource(new Map()));
		expect(result.ok).toBe(false);
		if (result.ok) return;
		expect(result.code).toBe('not-found');
		expect(result).not.toHaveProperty('ball');
	});
});
