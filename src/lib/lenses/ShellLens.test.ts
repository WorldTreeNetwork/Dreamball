import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ALL_LENSES } from './lens-types.js';
import { SHELL_MESH_URL } from './shell-mesh.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const LENS_SRC = join(__dirname, 'ShellLens.svelte');
const VIEWER_SRC = join(__dirname, '../components/DreamBallViewer.svelte');

describe('shell lens contract', () => {
	it('registers shell on LensName', () => {
		expect(ALL_LENSES).toContain('shell');
	});

	it('canonical mesh is the Star Tamagotchi glTF', () => {
		expect(SHELL_MESH_URL).toBe('/characters/star-tamagotchi.glb');
	});

	it('ShellLens loads the canonical URL via AvatarModel, not look.asset', () => {
		const src = readFileSync(LENS_SRC, 'utf-8');
		expect(src).toMatch(/SHELL_MESH_URL/);
		expect(src).toMatch(/AvatarModel/);
		expect(src).not.toMatch(/look\?\.asset/);
		expect(src).not.toMatch(/look\.asset\?/);
		expect(src).toMatch(/\$props\(\)/);
	});

	it('DreamBallViewer dispatches lens="shell"', () => {
		const src = readFileSync(VIEWER_SRC, 'utf-8');
		expect(src).toMatch(/effectiveLens === 'shell'/);
		expect(src).toMatch(/ShellLens/);
	});
});
