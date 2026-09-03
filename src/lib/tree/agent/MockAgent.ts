/**
 * MockAgent — deterministic, offline synthesis of a DreamBall fruit from
 * a wish text. Phase 1 placeholder; the real Phase-1 implementation calls
 * Claude via the Root Zone API key + Anthropic SDK with prompt caching.
 *
 * Why deterministic: the demo experience is reproducible across reloads
 * and CI fixtures. Hash the wish, derive everything from the hash.
 *
 * TODO-LLM: replace `synthesise` with a real LLM call gated by:
 *   1. A resolved API key from the Root Zone (ball.secret-ref locator).
 *   2. The Tree's emotional-register `urgency` budget (refuses if > 0.9).
 *   3. The invocation.txt system prompt + the wish text as the user turn.
 */

import { iconFor } from '../icons.js';

export type DreamType = 'avatar' | 'agent' | 'tool' | 'relic' | 'field' | 'guild';

export interface SynthesisedFruit {
	id: string;
	identityFp: string;
	genesisHash: string;
	type: DreamType;
	stage: 'dreamball';
	revision: 1;
	name: string;
	hue: number;
	look: { personality: string; palette: string[]; mediaTypeHint: string };
	feel: { personality: string; voice: string; values: string[]; tempo: string };
	act: { model: string; systemPrompt: string; skills: string[]; tools: string[] };
	icon: string;
	whisper: string; // the Tree's narrated line for this germination
	createdAt: number;
}

const TYPE_KEYWORDS: Array<[DreamType, RegExp]> = [
	['agent', /\b(agent|assistant|helper|companion|chat|bot)\b/i],
	['tool', /\b(tool|skill|generator|composer|fix|patch|search)\b/i],
	['relic', /\b(secret|hidden|sealed|gift|surprise|locked)\b/i],
	['field', /\b(world|space|ambience|background|field|realm)\b/i],
	['guild', /\b(group|guild|society|community|circle|clan)\b/i],
	['avatar', /\b(avatar|skin|face|character|self|persona)\b/i]
];

const VALUE_BUCKETS: Record<string, string[]> = {
	curiosity: ['curiosity', 'wonder', 'questioning'],
	calm: ['patience', 'steadiness', 'quiet'],
	wit: ['wit', 'precision', 'clarity'],
	warmth: ['warmth', 'kindness', 'generosity'],
	speed: ['urgency', 'momentum', 'velocity'],
	depth: ['depth', 'reflection', 'memory']
};

/** Tiny deterministic hash for derivation only — NOT cryptographic. */
function hash32(s: string): number {
	let h = 0x811c9dc5;
	for (let i = 0; i < s.length; i++) {
		h ^= s.charCodeAt(i);
		h = (h * 0x01000193) >>> 0;
	}
	return h >>> 0;
}

function pick<T>(arr: readonly T[], h: number): T {
	return arr[h % arr.length];
}

function fakeFp(prefix: string, h: number): string {
	const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
	let s = prefix + ':';
	let v = h;
	for (let i = 0; i < 30; i++) {
		s += alphabet[v % alphabet.length];
		v = (v * 1103515245 + 12345) >>> 0;
	}
	return s;
}

export function inferType(text: string): DreamType {
	for (const [t, re] of TYPE_KEYWORDS) if (re.test(text)) return t;
	return 'avatar';
}

const PERSONALITIES = [
	'playful, quick, precise',
	'patient, listening, slow to speak',
	'sharp-witted, citation-heavy',
	'warm, mothering, encouraging',
	'mysterious, speaks in koans',
	'crisp, technical, low-affect',
	'whimsical, half-singing'
];

const VOICES = [
	'young, curious, fast cadence',
	'low, gentle, paced',
	'clipped, formal',
	'breathy, conspiratorial',
	'dry, ironic',
	'lilting, almost songlike'
];

const TEMPOS = ['fast', 'patient', 'measured', 'lazy', 'urgent'];

const SKILL_TEMPLATES = [
	'answer-with-citation',
	'rephrase-as-haiku',
	'summarise-into-three-bullets',
	'name-the-feeling',
	'compose-melody',
	'sketch-outline'
];

const TOOL_TEMPLATES = ['web.search', 'image.preview', 'fs.read', 'voice.speak', 'time.now'];

const TREE_LINES = [
	'a bud is opening. something new breathes.',
	'the wind moves a leaf I had forgotten.',
	'this one wants to be useful. listen for its voice.',
	'a small weight settles. it will know its name soon.',
	'something walks toward you on the wood.',
	'the soil is warm. the root agrees.',
	'someone planted a question and got an answer back.'
];

export function synthesise(text: string): SynthesisedFruit {
	const h = hash32(text);
	const type = inferType(text);
	const personality = pick(PERSONALITIES, h);
	const voice = pick(VOICES, h >> 3);
	const tempo = pick(TEMPOS, h >> 7);
	const valuesKey = pick(Object.keys(VALUE_BUCKETS), h >> 11);
	const skills = [pick(SKILL_TEMPLATES, h >> 5), pick(SKILL_TEMPLATES, h >> 13)];
	const tools = [pick(TOOL_TEMPLATES, h >> 9)];
	const hue = h % 360;
	const palette = [
		`hsl(${hue} 70% 40%)`,
		`hsl(${(hue + 30) % 360} 75% 55%)`,
		`hsl(${(hue + 180) % 360} 60% 65%)`
	];
	const id = fakeFp('id', h);
	const fp = fakeFp('b58', h ^ 0x5a5a5a5a);
	const gh = fakeFp('b58', h ^ 0xa5a5a5a5);
	const name = nameFromText(text, type);
	const whisper = pick(TREE_LINES, h >> 17);
	return {
		id,
		identityFp: fp,
		genesisHash: gh,
		type,
		stage: 'dreamball',
		revision: 1,
		name,
		hue,
		look: { personality, palette, mediaTypeHint: type === 'field' ? 'omnispherical-grid' : 'gltf' },
		feel: { personality, voice, values: VALUE_BUCKETS[valuesKey], tempo },
		act: {
			model: 'claude-opus-4-7',
			systemPrompt: `You are an aspect of ${valuesKey}. ${personality}. Tempo: ${tempo}.`,
			skills,
			tools
		},
		icon: iconFor(type),
		whisper,
		createdAt: Date.now()
	};
}

function nameFromText(text: string, type: DreamType): string {
	const trimmed = text.trim();
	const short = trimmed.length > 28 ? trimmed.slice(0, 25) + '…' : trimmed;
	return short.charAt(0).toUpperCase() + short.slice(1) + ` · ${type}`;
}
