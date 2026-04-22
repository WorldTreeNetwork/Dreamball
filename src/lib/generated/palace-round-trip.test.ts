// Round-trip parity tests for the 9 palace envelope types (Story 1.5 / AC2).
//
// Strategy:
//   1. Load the golden CBOR fixture bytes written by `zig build export-envelope-fixtures`.
//   2. Decode via the generated typed decoder in cbor.ts.
//   3. Validate the decoded object against the generated Valibot schema in schemas.ts.
//   4. For CLI-path envelopes (Timeline, Action, Aqueduct, Mythos): decode a second
//      time and assert structural equality (AC2 round-trip parity).
//   5. For the remaining envelopes (Layout, ElementTag, TrustObservation, Inscription,
//      Archiform): decode-only + schema validation (AC2 decode-only path).
//
// Fixtures are produced by:
//   zig build export-envelope-fixtures
// which writes fixtures/envelope_golden/<type>.cbor — raw dCBOR bytes from the
// canonical Zig encoder (same inputs as golden.zig §13.11 tests).

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import * as v from 'valibot';

import {
	decodeLayout,
	decodeTimeline,
	decodeAction,
	decodeAqueduct,
	decodeElementTag,
	decodeTrustObservation,
	decodeInscription,
	decodeMythos,
	decodeArchiform
} from './cbor.js';

import {
	LayoutSchema,
	TimelineSchema,
	ActionSchema,
	AqueductSchema,
	ElementTagSchema,
	TrustObservationSchema,
	InscriptionSchema,
	MythosSchema,
	ArchiformSchema
} from './schemas.js';

// Resolve the fixtures relative to the repo root (5 levels up from src/lib/generated/).
const FIXTURES = resolve(__dirname, '..', '..', '..', 'fixtures', 'envelope_golden');

function loadFixture(name: string): Uint8Array {
	return new Uint8Array(readFileSync(resolve(FIXTURES, name)));
}

// ── AC2: CLI-path envelopes — decode + re-decode structural equality ──────────

describe('round-trip parity: Timeline (CLI-path)', () => {
	it('decodes and validates jelly.timeline', () => {
		const bytes = loadFixture('timeline.cbor');
		const decoded = decodeTimeline(bytes);
		expect(decoded.type).toBe('jelly.timeline');
		expect(decoded['format-version']).toBe(3);
		expect(decoded['head-hashes'].length).toBe(1);
		const result = v.safeParse(TimelineSchema, decoded);
		expect(result.success).toBe(true);
	});

	it('re-decode is structurally equal (round-trip parity)', () => {
		const bytes = loadFixture('timeline.cbor');
		const first = decodeTimeline(bytes);
		const second = decodeTimeline(bytes);
		expect(JSON.stringify(first)).toBe(JSON.stringify(second));
	});
});

describe('round-trip parity: Action (CLI-path)', () => {
	it('decodes and validates jelly.action', () => {
		const bytes = loadFixture('action.cbor');
		const decoded = decodeAction(bytes);
		expect(decoded.type).toBe('jelly.action');
		expect(decoded['format-version']).toBe(3);
		expect(decoded['action-kind']).toBe('palace-minted');
		expect(decoded['parent-hashes'].length).toBe(1);
		const result = v.safeParse(ActionSchema, decoded);
		expect(result.success).toBe(true);
	});

	it('re-decode is structurally equal (round-trip parity)', () => {
		const bytes = loadFixture('action.cbor');
		const first = decodeAction(bytes);
		const second = decodeAction(bytes);
		expect(JSON.stringify(first)).toBe(JSON.stringify(second));
	});
});

describe('round-trip parity: Aqueduct (CLI-path)', () => {
	it('decodes and validates jelly.aqueduct', () => {
		const bytes = loadFixture('aqueduct.cbor');
		const decoded = decodeAqueduct(bytes);
		expect(decoded.type).toBe('jelly.aqueduct');
		expect(decoded['format-version']).toBe(2);
		expect(decoded.kind).toBe('gaze');
		expect(decoded.phase).toBe('resonant');
		const result = v.safeParse(AqueductSchema, decoded);
		expect(result.success).toBe(true);
	});

	it('re-decode is structurally equal (round-trip parity)', () => {
		const bytes = loadFixture('aqueduct.cbor');
		const first = decodeAqueduct(bytes);
		const second = decodeAqueduct(bytes);
		expect(JSON.stringify(first)).toBe(JSON.stringify(second));
	});
});

describe('round-trip parity: Mythos (CLI-path)', () => {
	it('decodes and validates jelly.mythos', () => {
		const bytes = loadFixture('mythos.cbor');
		const decoded = decodeMythos(bytes);
		expect(decoded.type).toBe('jelly.mythos');
		expect(decoded['format-version']).toBe(2);
		expect(decoded['is-genesis']).toBe(true);
		expect(decoded['true-name']).toBe('The Palace of Remembered Light');
		const result = v.safeParse(MythosSchema, decoded);
		expect(result.success).toBe(true);
	});

	it('re-decode is structurally equal (round-trip parity)', () => {
		const bytes = loadFixture('mythos.cbor');
		const first = decodeMythos(bytes);
		const second = decodeMythos(bytes);
		expect(JSON.stringify(first)).toBe(JSON.stringify(second));
	});
});

// ── AC2: decode-only envelopes — decode succeeds + schema validates ────────────

describe('decode-only: Layout', () => {
	it('decodes and validates jelly.layout', () => {
		const bytes = loadFixture('layout.cbor');
		const decoded = decodeLayout(bytes);
		expect(decoded.type).toBe('jelly.layout');
		expect(decoded['format-version']).toBe(2);
		expect(decoded.placements.length).toBe(2);
		const result = v.safeParse(LayoutSchema, decoded);
		expect(result.success).toBe(true);
	});
});

describe('decode-only: ElementTag', () => {
	it('decodes and validates jelly.element-tag', () => {
		const bytes = loadFixture('element_tag.cbor');
		const decoded = decodeElementTag(bytes);
		expect(decoded.type).toBe('jelly.element-tag');
		expect(decoded.element).toBe('fire');
		expect(decoded.phase).toBe('yang');
		const result = v.safeParse(ElementTagSchema, decoded);
		expect(result.success).toBe(true);
	});
});

describe('decode-only: TrustObservation', () => {
	it('decodes and validates jelly.trust-observation', () => {
		const bytes = loadFixture('trust_observation.cbor');
		const decoded = decodeTrustObservation(bytes);
		expect(decoded.type).toBe('jelly.trust-observation');
		expect(decoded.axes?.length).toBe(2);
		expect(decoded.signatures?.length).toBe(1);
		const result = v.safeParse(TrustObservationSchema, decoded);
		expect(result.success).toBe(true);
	});
});

describe('decode-only: Inscription', () => {
	it('decodes and validates jelly.inscription', () => {
		const bytes = loadFixture('inscription.cbor');
		const decoded = decodeInscription(bytes);
		expect(decoded.type).toBe('jelly.inscription');
		expect(decoded.surface).toBe('scroll');
		expect(decoded.placement).toBe('curator');
		expect(decoded.note).toContain('markdown');
		const result = v.safeParse(InscriptionSchema, decoded);
		expect(result.success).toBe(true);
	});
});

describe('decode-only: Archiform', () => {
	it('decodes and validates jelly.archiform', () => {
		const bytes = loadFixture('archiform.cbor');
		const decoded = decodeArchiform(bytes);
		expect(decoded.type).toBe('jelly.archiform');
		expect(decoded.form).toBe('library');
		expect(decoded.tradition).toBe('hermetic');
		expect(decoded['parent-form']).toBe('forge');
		const result = v.safeParse(ArchiformSchema, decoded);
		expect(result.success).toBe(true);
	});
});

// ── AC3: Valibot validation rejects malformed input ────────────────────────────

describe('AC3: Valibot rejects malformed palace envelopes', () => {
	it('LayoutSchema rejects missing placements', () => {
		const r = v.safeParse(LayoutSchema, { type: 'jelly.layout', 'format-version': 2 });
		expect(r.success).toBe(false);
	});

	it('TimelineSchema rejects wrong type literal', () => {
		const r = v.safeParse(TimelineSchema, {
			type: 'jelly.NOT-timeline',
			'format-version': 3,
			'palace-fp': 'b58:abc',
			'head-hashes': []
		});
		expect(r.success).toBe(false);
	});

	it('ActionSchema rejects unknown action-kind', () => {
		const r = v.safeParse(ActionSchema, {
			type: 'jelly.action',
			'format-version': 3,
			'action-kind': 'unknown-kind',
			actor: 'b58:abc',
			'parent-hashes': []
		});
		expect(r.success).toBe(false);
	});

	it('AqueductSchema rejects missing required numeric fields', () => {
		const r = v.safeParse(AqueductSchema, {
			type: 'jelly.aqueduct',
			'format-version': 2,
			from: 'b58:abc',
			to: 'b58:def',
			kind: 'gaze'
			// missing capacity, strength, resistance, capacitance
		});
		expect(r.success).toBe(false);
	});

	it('MythosSchema rejects missing is-genesis', () => {
		const r = v.safeParse(MythosSchema, {
			type: 'jelly.mythos',
			'format-version': 2
			// missing is-genesis
		});
		expect(r.success).toBe(false);
	});
});
