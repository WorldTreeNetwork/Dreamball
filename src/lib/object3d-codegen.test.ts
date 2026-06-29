/**
 * D1 — ball.object3d cross-runtime codegen proof (sprint-003 stretch).
 *
 * The real FR2 payoff: the GENERATED TypeScript artifacts actually consume the
 * canonical Zig-encoded bytes. We take the golden envelope bytes emitted by the
 * Zig encoder (`encodeObject3d`, src/envelope_v2.zig — mirrored in
 * src/golden.zig GOLDEN_OBJECT3D_BYTES_HEX), decode them via the generated
 * `decodeObject3d`, validate the result against the generated `Object3dSchema`,
 * and assert the decoded fields equal the fixture. This reuses C2's codegen
 * path and C1's Zig↔TS golden-mirror discipline; the shared fixture forces the
 * Zig and TS golden copies to agree (drift fails a gate on one side).
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import * as v from 'valibot';

import { decodeObject3d } from './generated/cbor.js';
import { Object3dSchema } from './generated/schemas.js';

interface Object3dFixture {
	mesh: string;
	position: [number, number, number];
	rotation: [number, number, number, number];
	scale: [number, number, number];
	bytesHex: string;
}

const fixture: Object3dFixture = JSON.parse(
	readFileSync(resolve(__dirname, '__fixtures__', 'object3d.golden.json'), 'utf8'),
);

function hexToBytes(hex: string): Uint8Array {
	const out = new Uint8Array(hex.length / 2);
	for (let i = 0; i < out.length; i++) {
		out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
	}
	return out;
}

describe('ball.object3d generated codegen consumes canonical Zig bytes (D1)', () => {
	it('decodes the golden envelope via generated decodeObject3d', () => {
		const decoded = decodeObject3d(hexToBytes(fixture.bytesHex));
		expect(decoded.type).toBe('ball.object3d');
		expect(decoded['format-version']).toBe(2);
		expect(decoded.mesh).toBe(fixture.mesh);
		expect(decoded.position).toEqual(fixture.position);
		expect(decoded.rotation).toEqual(fixture.rotation);
		expect(decoded.scale).toEqual(fixture.scale);
	});

	it('validates the decoded value against generated Object3dSchema', () => {
		const decoded = decodeObject3d(hexToBytes(fixture.bytesHex));
		const result = v.safeParse(Object3dSchema, decoded);
		expect(result.success).toBe(true);
	});
});
