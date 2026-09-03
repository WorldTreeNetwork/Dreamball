/**
 * Wishing Tree palette — 16 entries, locked.
 * See docs/products/wishing-tree/PHASES.md §3.
 * Drift requires PR discussion. Retheming is a one-file edit here.
 */

export const PALETTE = {
	void: '#050714',
	root: '#0b1020',
	trunk: '#121a3c',
	branch: '#1f2a66',
	leaf: '#30489a',
	sky: '#5a7be0',
	haze: '#c9d0ff',
	mist: '#8a93c8',
	wishViolet: '#e0b7ff',
	blossom: '#ff77c8',
	fruitGold: '#ffe066',
	sapGreen: '#9cff6b',
	frostCyan: '#6bf5ff',
	starlight: '#ffffff',
	alarm: '#ff5a5a',
	amber: '#ff9e2a'
} as const;

export type PaletteKey = keyof typeof PALETTE;

/** CSS custom properties: one --wt-<name> variable per palette entry. */
export function paletteToCss(): string {
	return Object.entries(PALETTE)
		.map(([k, v]) => `--wt-${k.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}: ${v};`)
		.join(' ');
}
