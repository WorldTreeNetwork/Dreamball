/**
 * Lenses dispatched by DreamBallViewer. v2 PRD (FR33) plus splat, palace,
 * room, inscription, and shell (canonical container mesh).
 */
export const ALL_LENSES = [
	'thumbnail',
	'avatar',
	'knowledge-graph',
	'emotional-state',
	'omnispherical',
	'flat',
	'phone',
	'splat',
	'palace',
	'room',
	'inscription',
	'shell'
] as const;

export type LensName = (typeof ALL_LENSES)[number];
