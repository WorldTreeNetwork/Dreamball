import { describe, expect, it } from 'vitest';
import {
	isTransmittableError,
	locatorFromSearchParams,
	TransmittableNotFoundError,
	TransmittableParseError,
	TransmittableVerifyError,
	transmittableLocator
} from './transmittable.js';

describe('transmittableLocator', () => {
	it('trims bucket and filename', () => {
		expect(transmittableLocator('  vault  ', ' star.ball ')).toEqual({
			bucket: 'vault',
			filename: 'star.ball'
		});
	});

	it('rejects empty fields before any fetch', () => {
		expect(() => transmittableLocator('', 'a.ball')).toThrow(TypeError);
		expect(() => transmittableLocator('vault', '   ')).toThrow(TypeError);
	});
});

describe('locatorFromSearchParams', () => {
	it('reads the viewer query encoding', () => {
		const params = new URLSearchParams('bucket=vault&filename=star.ball');
		expect(locatorFromSearchParams(params)).toEqual({
			bucket: 'vault',
			filename: 'star.ball'
		});
	});

	it('returns null when the locator is empty, not a not-found error', () => {
		expect(locatorFromSearchParams(new URLSearchParams())).toBeNull();
		expect(locatorFromSearchParams(new URLSearchParams('bucket=vault'))).toBeNull();
	});
});

describe('error vocabulary', () => {
	const loc = { bucket: 'vault', filename: 'missing.ball' };

	it('names not-found distinctly from decode failures', () => {
		const err = new TransmittableNotFoundError(loc);
		expect(err.code).toBe('transmittable-not-found');
		expect(isTransmittableError(err)).toBe(true);
		expect(err.locator).toEqual(loc);
	});

	it('carries wasm verify/parse reasons without a second parser message', () => {
		const v = new TransmittableVerifyError(loc, 'VERIFY_FAILED');
		const p = new TransmittableParseError(loc, 'bad envelope');
		expect(v.code).toBe('transmittable-verify-failed');
		expect(p.code).toBe('transmittable-parse-failed');
		expect(v.reason).toBe('VERIFY_FAILED');
		expect(p.reason).toBe('bad envelope');
		expect(isTransmittableError(v)).toBe(true);
		expect(isTransmittableError(p)).toBe(true);
		expect(isTransmittableError(new Error('nope'))).toBe(false);
	});
});
