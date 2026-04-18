import { describe, it, expect } from 'vitest';
import { base58Encode, base58Decode, decodeEnvelope } from './cbor.js';

describe('base58', () => {
	it('round-trips "Hello World!" to the canonical value', () => {
		const enc = base58Encode(new TextEncoder().encode('Hello World!'));
		expect(enc).toBe('2NEpo7TZRRrLZSi2U');
	});

	it('preserves leading zero bytes as 1s', () => {
		const bytes = new Uint8Array([0, 0, 0, 0xab]);
		const enc = base58Encode(bytes);
		expect(enc.startsWith('1110')).toBe(false);
		expect(enc.startsWith('111')).toBe(true);
		const dec = base58Decode(enc);
		expect(Array.from(dec)).toEqual([0, 0, 0, 0xab]);
	});

	it('round-trips a 32-byte buffer', () => {
		const input = new Uint8Array(32);
		for (let i = 0; i < 32; i++) input[i] = i;
		const enc = base58Encode(input);
		const dec = base58Decode(enc);
		expect(Array.from(dec)).toEqual(Array.from(input));
	});

	it('throws on invalid characters', () => {
		expect(() => base58Decode('abc0')).toThrow();
	});
});

describe('decodeEnvelope', () => {
	it('reads a minimal tag-200 envelope wrapping a leaf map', () => {
		// tag 200 → tag 201 → map { "type": "jelly.test" }
		// CBOR bytes: 0xD8 0xC8 | 0xD8 0xC9 | 0xA1 | text("type") | text("jelly.test")
		const bytes = new Uint8Array([
			0xd8, 0xc8,
			0xd8, 0xc9,
			0xa1,
			0x64, 0x74, 0x79, 0x70, 0x65,
			0x6a, 0x6a, 0x65, 0x6c, 0x6c, 0x79, 0x2e, 0x74, 0x65, 0x73, 0x74
		]);
		const decoded = decodeEnvelope(bytes) as { __cborTag: number; value: unknown };
		expect(decoded.__cborTag).toBe(200);
		const inner = (decoded.value as { __cborTag: number; value: unknown });
		expect(inner.__cborTag).toBe(201);
		const leaf = inner.value as Record<string, unknown>;
		expect(leaf.type).toBe('jelly.test');
	});
});
