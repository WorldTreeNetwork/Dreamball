/**
 * Publish-boundary parse helpers for DreamBall envelopes.
 *
 * NFR8 (Story 1.3 / D-018): validate-on-publish, not validate-on-decode.
 * The generated `src/lib/generated/schemas.ts` exports Valibot
 * validators; the generated `src/lib/generated/cbor.ts` decodes raw
 * CBOR without invoking Valibot. This file is the *publish-boundary*
 * caller of those validators — dreamball-server ingest, mint-time
 * authoring, manual replay tools, and Story-1.3 AC7's grep audit
 * (`grep -R 'Valibot.parse|safeParse' src/lib/generated/`) MUST
 * remain zero, which is why these helpers live here, NOT in
 * `src/lib/generated/`.
 */

import * as v from 'valibot';
import { DreamBallSchema, type DreamBallValidated, type ParseResult } from './generated/schemas.js';

/** Parse a JSON string to a validated DreamBall. Throws on invalid. */
export function parseDreamBall(jsonText: string): DreamBallValidated {
	const parsed = JSON.parse(jsonText);
	return v.parse(DreamBallSchema, parsed);
}

/** Same as parseDreamBall but returns a tagged result. */
export function safeParseDreamBall(jsonText: string): ParseResult<DreamBallValidated> {
	let raw: unknown;
	try {
		raw = JSON.parse(jsonText);
	} catch (e) {
		return {
			success: false,
			issues: [
				{
					kind: 'schema',
					type: 'json',
					input: jsonText,
					expected: 'valid JSON',
					received: (e as Error).message,
					message: `invalid JSON: ${(e as Error).message}`,
					requirement: undefined,
					path: undefined,
					issues: undefined,
					lang: 'en',
					abortEarly: undefined,
					abortPipeEarly: undefined
				} as v.BaseIssue<unknown>
			]
		};
	}
	const result = v.safeParse(DreamBallSchema, raw);
	if (result.success) return { success: true, data: result.output };
	return { success: false, issues: result.issues };
}
