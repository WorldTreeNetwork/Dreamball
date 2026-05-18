/**
 * Typography tokens — pixel-first. Fallback is monospace so the retro
 * register never collapses into a sans-serif even when the pixel font
 * hasn't loaded yet.
 */

export const FONT_STACK = {
	pixel:
		'"Press Start 2P", "VT323", "IBM Plex Mono", ui-monospace, Menlo, Consolas, monospace',
	mono: '"IBM Plex Mono", ui-monospace, Menlo, Consolas, monospace'
} as const;

export const TYPE_SCALE = {
	xs: '10px',
	sm: '12px',
	base: '14px',
	lg: '18px',
	xl: '24px',
	xxl: '32px',
	title: '48px'
} as const;
