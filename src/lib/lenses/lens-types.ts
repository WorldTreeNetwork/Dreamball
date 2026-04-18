/**
 * The seven lenses defined in the v2 PRD (FR33) + one sentinel for "unknown".
 * Each maps to a component under `src/lib/lenses/*Lens.svelte`.
 */
export const ALL_LENSES = [
	'thumbnail',
	'avatar',
	'knowledge-graph',
	'emotional-state',
	'omnispherical',
	'flat',
	'phone',
	'splat'
] as const;

export type LensName = (typeof ALL_LENSES)[number];
