/**
 * Pixel-font / ASCII glyph set. Pure text so it renders everywhere the
 * monospace font does — no sprite sheet to maintain. Each glyph is
 * 1ch wide; fits the 8-bit register.
 */

export const ICON: Record<string, string> = {
	// Envelopes / kinds
	dreamball: '◉',
	avatar: '☻',
	agent: '◇',
	tool: '⚒',
	relic: '▣',
	field: '✧',
	guild: '⚑',
	// Slots
	look: '▓',
	feel: '♥',
	act: '⚡',
	memory: '▤',
	'knowledge-graph': '⁂',
	'emotional-register': '❉',
	'interaction-set': '∿',
	// Sub-slots
	shader: '▒',
	mesh: '▣',
	graticule: '◈',
	asset: '♦',
	preview: '▫',
	skill: '⚐',
	script: '❘',
	model: '◆',
	prompt: '❞',
	tools: '⚙',
	// Graph
	contains: '▸',
	'derived-from': '↺',
	// Identity
	identity: '🔑',
	fingerprint: '⌘',
	'genesis-hash': '⌥',
	revision: '#',
	signatures: '✍',
	ed25519: '⚷',
	'ml-dsa-87': '⚶',
	secret: '🔒',
	// Status
	seed: '✦',
	bud: '❂',
	fruit: '●',
	sealed: '■',
	// Files
	folder: '▾',
	file: '·',
	image: '▢',
	model3d: '◊'
};

export function iconFor(kind: string): string {
	return ICON[kind] ?? '·';
}
