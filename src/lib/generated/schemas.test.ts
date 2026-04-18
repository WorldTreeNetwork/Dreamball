import { describe, it, expect } from 'vitest';
import * as v from 'valibot';
import {
	DreamBallSchema,
	DreamBallAgentSchema,
	DreamBallUntypedSchema,
	SignatureSchema,
	AssetSchema,
	safeParseDreamBall,
	parseDreamBall
} from './schemas.js';

describe('Valibot schemas', () => {
	it('validates a minimal untyped v1 DreamBall', () => {
		const ok = {
			type: 'jelly.dreamball',
			'format-version': 1,
			stage: 'seed',
			identity: 'b58:abcABC',
			'genesis-hash': 'b58:defDEF',
			revision: 0
		};
		const result = v.safeParse(DreamBallUntypedSchema, ok);
		expect(result.success).toBe(true);
	});

	it('validates a v2 agent DreamBall with nested slots', () => {
		const ok = {
			type: 'jelly.dreamball.agent',
			'format-version': 2,
			stage: 'dreamball',
			identity: 'b58:aaaa',
			'genesis-hash': 'b58:bbbb',
			revision: 3,
			name: 'Curious',
			feel: { personality: 'playful' },
			'emotional-register': {
				axes: [{ name: 'curiosity', value: 0.82 }]
			}
		};
		const result = v.safeParse(DreamBallAgentSchema, ok);
		expect(result.success).toBe(true);
	});

	it('discriminates on `type` field via DreamBallSchema', () => {
		const toolBall = {
			type: 'jelly.dreamball.tool',
			'format-version': 2,
			stage: 'dreamball',
			identity: 'b58:zzz',
			'genesis-hash': 'b58:yyy',
			revision: 0,
			skill: { name: 'haiku-compose' }
		};
		const r = v.safeParse(DreamBallSchema, toolBall);
		expect(r.success).toBe(true);
		if (r.success) expect(r.output.type).toBe('jelly.dreamball.tool');
	});

	it('rejects a DreamBall with bad base58 identity', () => {
		const bad = {
			type: 'jelly.dreamball',
			'format-version': 1,
			stage: 'seed',
			identity: 'not-b58-prefix',
			'genesis-hash': 'b58:abc',
			revision: 0
		};
		const r = v.safeParse(DreamBallUntypedSchema, bad);
		expect(r.success).toBe(false);
	});

	it('rejects a signature with wrong alg', () => {
		const bad = { alg: 'rsa-2048', value: 'b58:abc' };
		const r = v.safeParse(SignatureSchema, bad);
		expect(r.success).toBe(false);
	});

	it('AssetSchema requires media-type + hash', () => {
		const missing = { url: ['https://example'] };
		const r = v.safeParse(AssetSchema, missing);
		expect(r.success).toBe(false);
	});

	it('parseDreamBall throws on malformed input', () => {
		expect(() =>
			parseDreamBall(
				JSON.stringify({ type: 'jelly.dreamball', 'format-version': 1, stage: 'BAD' })
			)
		).toThrow();
	});

	it('safeParseDreamBall returns issues for malformed input', () => {
		const r = safeParseDreamBall('{"type":"jelly.dreamball","format-version":1,"stage":"BAD"}');
		expect(r.success).toBe(false);
		if (!r.success) expect(r.issues.length).toBeGreaterThan(0);
	});

	it('safeParseDreamBall returns issues for invalid JSON', () => {
		const r = safeParseDreamBall('not-json');
		expect(r.success).toBe(false);
	});
});
