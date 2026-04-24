import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import { CborReader, base58Encode, base58Decode, decodeEnvelope } from './cbor.js';

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

describe('HIGH-1: CborReader rejects non-canonical (padded) integers', () => {
	it('rejects info-24 encoding for value < 24 (e.g. 0x18 0x05 for 5)', () => {
		// Canonical encoding of uint 5 is 0x05 (1 byte).
		// 0x18 0x05 is the padded 2-byte form — must be rejected.
		const padded = new Uint8Array([0x18, 0x05]);
		const reader = new CborReader(padded);
		expect(() => reader.readAny()).toThrow('non-canonical');
	});

	it('rejects info-25 encoding for value < 256 (e.g. 0x19 0x00 0xFF for 255)', () => {
		// Canonical: 0x18 0xFF. Padded: 0x19 0x00 0xFF.
		const padded = new Uint8Array([0x19, 0x00, 0xff]);
		const reader = new CborReader(padded);
		expect(() => reader.readAny()).toThrow('non-canonical');
	});

	it('rejects info-26 encoding for value < 65536', () => {
		// Canonical: 0x19 0x01 0x00 (256). Padded: 0x1A 0x00 0x00 0x01 0x00.
		const padded = new Uint8Array([0x1a, 0x00, 0x00, 0x01, 0x00]);
		const reader = new CborReader(padded);
		expect(() => reader.readAny()).toThrow('non-canonical');
	});

	it('accepts smallest-form uint at each boundary', () => {
		// 23 → inline (0x17)
		expect(new CborReader(new Uint8Array([0x17])).readAny()).toBe(23);
		// 24 → info-24 (0x18 0x18)
		expect(new CborReader(new Uint8Array([0x18, 0x18])).readAny()).toBe(24);
		// 256 → info-25 (0x19 0x01 0x00)
		expect(new CborReader(new Uint8Array([0x19, 0x01, 0x00])).readAny()).toBe(256);
	});
});

// ── LOW-5: base58 round-trip property test (Sprint-1 code review) ────────────

describe('LOW-5: base58 round-trip property test', () => {
	it('decode(encode(x)) === x for 1000 random byte buffers (length 0..256)', () => {
		fc.assert(
			fc.property(
				fc.uint8Array({ minLength: 0, maxLength: 256 }),
				(bytes) => {
					const encoded = base58Encode(bytes);
					const decoded = base58Decode(encoded);
					expect(Array.from(decoded)).toEqual(Array.from(bytes));
				}
			),
			{ numRuns: 1000 }
		);
	});

	it('empty input round-trips correctly', () => {
		const enc = base58Encode(new Uint8Array(0));
		expect(enc).toBe('');
		const dec = base58Decode('');
		expect(dec.length).toBe(0);
	});

	it('leading-zero bytes round-trip correctly', () => {
		// base58 has special leading-zero handling: each leading 0x00 byte
		// maps to a '1' character.
		const cases = [
			new Uint8Array([0]),
			new Uint8Array([0, 0]),
			new Uint8Array([0, 0, 0]),
			new Uint8Array([0, 0, 0, 1]),
			new Uint8Array([0, 0, 0, 0, 0xff]),
		];
		for (const input of cases) {
			const enc = base58Encode(input);
			const dec = base58Decode(enc);
			expect(Array.from(dec)).toEqual(Array.from(input));
		}
	});

	it('decode of non-alphabet characters throws', () => {
		// '0', 'O', 'I', 'l' are NOT in the Bitcoin base58 alphabet.
		expect(() => base58Decode('0')).toThrow();
		expect(() => base58Decode('O')).toThrow();
		expect(() => base58Decode('I')).toThrow();
		expect(() => base58Decode('l')).toThrow();
		expect(() => base58Decode('abc!def')).toThrow();
		expect(() => base58Decode('hello world')).toThrow(); // space
	});
});
