/**
 * MockBackend — in-memory fixtures for Storybook + Vitest.
 *
 * ⚠ TODO-CRYPTO: replace before prod. Nothing here is cryptographically
 * authentic; this exists to let the renderer run without a live
 * `jelly-server` daemon.
 */

import type {
	DreamBall,
	Fingerprint,
	Look,
	Feel,
	Act,
	Memory,
	KnowledgeGraph,
	EmotionalRegister,
	GuildPolicy,
	Asset,
	OmnisphericalGrid,
	DreamBallType
} from '../generated/types.js';
import { ALWAYS_PUBLIC_SLOTS, type JellyBackend } from './JellyBackend.js';

function fakeFp(seed: number): Fingerprint {
	const s = String.fromCharCode(65 + (seed % 26)) + seed.toString(36).padStart(5, '0');
	return `b58:mock${s}${'x'.repeat(Math.max(0, 30 - s.length))}`;
}

function stockLook(): Look {
	const asset: Asset = {
		'media-type': 'model/gltf-binary',
		hash: 'b58:mockHashHummingbird',
		url: ['https://cdn.example/mock/hummingbird.glb']
	};
	return { asset: [asset], background: 'color:#0b1020' };
}

function stockFeel(): Feel {
	return {
		personality: 'playful, quick, precise',
		voice: 'young, curious, fast cadence',
		values: ['curiosity', 'clarity', 'kindness'],
		tempo: 'fast'
	};
}

function stockAct(): Act {
	return {
		model: 'claude-opus-4-7',
		'system-prompt': 'You are an aspect of curiosity.',
		skill: [{ name: 'answer-with-citation', trigger: 'factual question' }],
		tool: ['web.search']
	};
}

function stockMemory(): Memory {
	return {
		nodes: [
			{ id: 1, content: 'saw a hummingbird at sunrise' },
			{ id: 2, content: 'learned the haiku 5-7-5 structure' }
		],
		edges: [{ from: 1, to: 2, kind: 'temporal', strength: 0.6 }]
	};
}

function stockKG(): KnowledgeGraph {
	return {
		triples: [
			{ subject: 'curiosity', predicate: 'inclines-toward', object: 'new-things' },
			{ subject: 'haiku', predicate: 'requires', object: '5-7-5 syllables' }
		]
	};
}

function stockEmotion(): EmotionalRegister {
	return {
		axes: [
			{ name: 'curiosity', value: 0.82 },
			{ name: 'warmth', value: 0.55 },
			{ name: 'urgency', value: 0.1 }
		]
	};
}

function stockPolicy(): GuildPolicy {
	return {
		public: [...ALWAYS_PUBLIC_SLOTS, 'look', 'feel'],
		'guild-only': ['memory', 'knowledge-graph', 'emotional-register', 'interaction-set', 'act'],
		'admin-only': ['secret']
	};
}

function stockGrid(): OmnisphericalGrid {
	return {
		'pole-north': { x: 0, y: 1, z: 0 },
		'pole-south': { x: 0, y: -1, z: 0 },
		'camera-ring': [
			{ radius: 1.0, tilt: 0, fov: 60 },
			{ radius: 2.5, tilt: 0.4, fov: 75 },
			{ radius: 6.0, tilt: 0.9, fov: 90 }
		],
		'layer-depth': 3,
		resolution: 8
	};
}

function baseBall(seed: number, type: DreamBallType, name: string): DreamBall {
	const identity = fakeFp(seed);
	const genesis = fakeFp(seed + 1000);
	return {
		type: `jelly.dreamball.${type}`,
		'format-version': 2,
		stage: 'dreamball',
		identity,
		'genesis-hash': genesis,
		revision: 1,
		name,
		created: '2026-04-18T12:00:00Z'
	};
}

export function mockBall(type: DreamBallType, overrides?: Partial<DreamBall>): DreamBall {
	const seed = Math.floor(Math.random() * 1000);
	const ball = baseBall(seed, type, `Mock ${type}`);
	switch (type) {
		case 'avatar':
			ball.look = stockLook();
			ball.feel = stockFeel();
			break;
		case 'agent':
			ball.look = stockLook();
			ball.feel = stockFeel();
			ball.act = stockAct();
			ball.memory = stockMemory();
			ball['knowledge-graph'] = stockKG();
			ball['emotional-register'] = stockEmotion();
			ball['personality-master-prompt'] = 'You are an aspect of curiosity.';
			break;
		case 'tool':
			ball.skill = { name: 'haiku-compose', trigger: 'user asks for a haiku' };
			ball['applicable-to'] = ['jelly.dreamball.agent'];
			break;
		case 'relic':
			ball['sealed-payload-hash'] = fakeFp(seed + 2000);
			ball['unlock-guild'] = fakeFp(seed + 3000);
			ball['reveal-hint'] = 'Look behind the mirror';
			break;
		case 'field':
			ball['omnispherical-grid'] = stockGrid();
			ball['ambient-palette'] = ['#0b1020', '#1a2240', '#303a6a'];
			ball['dream-field-id'] = '00000000-0000-0000-0000-00000000dream';
			break;
		case 'guild':
			ball['guild-name'] = 'The Hummingbirds';
			ball['keyspace-root-hash'] = fakeFp(seed + 4000);
			ball.member = [fakeFp(seed + 10), fakeFp(seed + 11)];
			ball.admin = [fakeFp(seed + 10)];
			ball.policy = stockPolicy();
			break;
	}
	return { ...ball, ...overrides };
}

export class MockBackend implements JellyBackend {
	private readonly fixtures = new Map<string, DreamBall>();

	constructor(seeded: DreamBall[] = []) {
		for (const b of seeded) this.fixtures.set(b.identity, b);
	}

	async load(reference: string | Fingerprint): Promise<DreamBall> {
		const byId = this.fixtures.get(reference);
		if (byId) return byId;
		// Fallback: synthesize an Avatar.
		return mockBall('avatar', { identity: reference as Fingerprint });
	}

	async list(): Promise<Array<{ fingerprint: Fingerprint; summary: DreamBall }>> {
		return [...this.fixtures.values()].map((b) => ({ fingerprint: b.identity, summary: b }));
	}

	async unlockRelic(relic: DreamBall, _guildKey: Uint8Array): Promise<DreamBall> {
		if (relic.type !== 'jelly.dreamball.relic') {
			throw new Error('not a relic');
		}
		// TODO-CRYPTO: real unlock would decrypt the attached sealed payload
		// using the guild's keyspace credential. Mock just synthesises the
		// "inner" DreamBall from the reveal hint + a fresh Avatar shape.
		return mockBall('avatar', {
			name: 'Unlocked (mock inner)',
			feel: { note: relic['reveal-hint'] ?? 'revealed' }
		});
	}

	async resolvePermittedSlots(ball: DreamBall, viewer: Fingerprint | null): Promise<string[]> {
		const policy = ball.policy ?? stockPolicy();
		if (!viewer) return policy.public;
		// If viewer is listed as a member, include guild-only slots.
		const isMember = (ball.member ?? []).includes(viewer);
		const isAdmin = (ball.admin ?? []).includes(viewer);
		const slots = new Set(policy.public);
		if (isMember || isAdmin) for (const s of policy['guild-only']) slots.add(s);
		if (isAdmin) for (const s of policy['admin-only']) slots.add(s);
		return [...slots];
	}
}
