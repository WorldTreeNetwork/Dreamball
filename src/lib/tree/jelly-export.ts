/**
 * jelly-export — produces a downloadable JSON-shaped DreamBall. NOT real
 * dCBOR / not signed; clearly labelled mock so consumers don't mistake it
 * for a verifiable artefact. Phase 1+ swaps this for a call into the Zig
 * `jelly` CLI via MCP, which produces a real `.jelly`.
 */

import type { SynthesisedFruit } from './agent/MockAgent.js';

export function fruitToJellyJson(fruit: SynthesisedFruit): unknown {
	return {
		_warning: 'mock — not real dCBOR, not signed. Phase 0/1 placeholder.',
		type: `ball.dreamball.${fruit.type}`,
		'format-version': 2,
		stage: fruit.stage,
		identity: fruit.identityFp,
		'genesis-hash': fruit.genesisHash,
		revision: fruit.revision,
		name: fruit.name,
		created: new Date(fruit.createdAt).toISOString(),
		look: {
			background: fruit.look.palette[0],
			note: fruit.look.personality,
			'media-type-hint': fruit.look.mediaTypeHint
		},
		feel: {
			personality: fruit.feel.personality,
			voice: fruit.feel.voice,
			values: fruit.feel.values,
			tempo: fruit.feel.tempo
		},
		act: {
			model: fruit.act.model,
			'system-prompt': fruit.act.systemPrompt,
			skill: fruit.act.skills.map((n) => ({ name: n })),
			tool: fruit.act.tools
		},
		signatures: [
			{ alg: 'ed25519', value: 'b58:placeholder_ed25519_signature' },
			{ alg: 'ml-dsa-87', value: 'b58:placeholder_ml_dsa_87_signature' }
		]
	};
}

export function downloadFruit(fruit: SynthesisedFruit): void {
	const json = fruitToJellyJson(fruit);
	const blob = new Blob([JSON.stringify(json, null, 2)], { type: 'application/jelly+json' });
	const url = URL.createObjectURL(blob);
	const a = document.createElement('a');
	a.href = url;
	const safe = fruit.name.replace(/[^a-z0-9]+/gi, '-').toLowerCase();
	a.download = `${safe || fruit.id}.jelly.json`;
	document.body.appendChild(a);
	a.click();
	a.remove();
	setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** Phase-4: serialise the Tree itself as a DreamBall. Produces a self-
 *  describing JSON (still mock — real CBOR via Zig CLI lands later). */
export function downloadTreeBundle(meta: {
	wishes: number;
	plucks: number;
	transmissions: number;
	revision: number;
	dreamType: string;
}): void {
	const env = {
		_warning: 'mock — not real dCBOR. Phase-4 self-publish placeholder.',
		type: 'ball.dreamball.field',
		'format-version': 2,
		stage: 'dreamball',
		identity: 'b58:tree_identity_placeholder',
		'genesis-hash': 'b58:tree_genesis_placeholder',
		revision: meta.revision,
		name: 'The Wishing Tree',
		'omnispherical-grid': {
			'pole-north': { x: 0, y: 1, z: 0 },
			'pole-south': { x: 0, y: -1, z: 0 },
			'camera-ring': [
				{ radius: 1.0, tilt: 0, fov: 60 },
				{ radius: 2.5, tilt: 0.4, fov: 75 },
				{ radius: 6.0, tilt: 0.9, fov: 90 }
			],
			'layer-depth': 3,
			resolution: 8
		},
		'ambient-palette': ['#0b1020', '#1f2a66', '#e0b7ff'],
		act: {
			model: 'claude-opus-4-7',
			'system-prompt': '(see invocation.txt)'
		},
		'self-stats': meta,
		signatures: [
			{ alg: 'ed25519', value: 'b58:placeholder' },
			{ alg: 'ml-dsa-87', value: 'b58:placeholder' }
		]
	};
	const blob = new Blob([JSON.stringify(env, null, 2)], { type: 'application/jelly+json' });
	const url = URL.createObjectURL(blob);
	const a = document.createElement('a');
	a.href = url;
	a.download = `wishing-tree.jelly.json`;
	document.body.appendChild(a);
	a.click();
	a.remove();
	setTimeout(() => URL.revokeObjectURL(url), 1000);
}
