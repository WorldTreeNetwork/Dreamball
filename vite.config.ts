/// <reference types="vitest/config" />
import { defineConfig } from 'vitest/config';
import { playwright } from '@vitest/browser-playwright';
import { sveltekit } from '@sveltejs/kit/vite';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { storybookTest } from '@storybook/addon-vitest/vitest-plugin';
const dirname =
	typeof __dirname !== 'undefined' ? __dirname : path.dirname(fileURLToPath(import.meta.url));

// More info at: https://storybook.js.org/docs/next/writing-tests/integrations/vitest-addon
export default defineConfig({
	plugins: [sveltekit()],
	test: {
		expect: {
			requireAssertions: true
		},
		projects: [
			{
				extends: './vite.config.ts',
				test: {
					name: 'client',
					browser: {
						enabled: true,
						provider: playwright(),
						instances: [
							{
								browser: 'chromium',
								headless: true
							}
						]
					},
					include: ['src/**/*.svelte.{test,spec}.{js,ts}'],
					exclude: ['src/lib/server/**']
				}
			},
			{
				extends: './vite.config.ts',
				test: {
					name: 'server',
					environment: 'node',
					include: [
						'src/**/*.{test,spec}.{js,ts}',
						'dreamball-server/src/**/*.{test,spec}.{js,ts}',
						'tests/codegen/**/*.{test,spec}.{js,ts}',
						'tests/wasm/host/**/*.{test,spec}.{js,ts}',
						'tests/mcp/**/*.{test,spec}.{js,ts}',
						'tests/capabilities/**/*.{test,spec}.{js,ts}'
					],
					exclude: ['src/**/*.svelte.{test,spec}.{js,ts}'],
					// S6.1: dreamball-server tests must not attempt to start the server
					// or load the Qwen3 model (weights not present in CI).
					// These vars are set here (not only in test files) because ESM
					// top-level await in index.ts runs before test-file assignments.
					env: {
						DREAMBALL_SERVER_NO_LISTEN: '1',
						DREAMBALL_EMBED_MOCK: '1'
					}
				}
			},
			{
				extends: true,
				plugins: [
					// The plugin will run tests for the stories defined in your Storybook config
					// See options at: https://storybook.js.org/docs/next/writing-tests/integrations/vitest-addon#storybooktest
					storybookTest({
						configDir: path.join(dirname, '.storybook')
					})
				],
				test: {
					name: 'storybook',
					// These stories render Threlte/WebGL scenes (AllLensesGrid mounts every
					// lens at once), which is far slower on a 2-core CI runner than locally.
					// The 15s default flaked on two different stories across separate runs —
					// WearerIdle on 30928914073, AllLensesGrid on 30932164374 — each passing
					// on the other runs. Sized for a contended runner, not the happy path;
					// a genuinely hung story still fails well inside the step budget.
					testTimeout: 60_000,
					hookTimeout: 60_000,
					browser: {
						enabled: true,
						headless: true,
						provider: playwright({}),
						instances: [
							{
								browser: 'chromium'
							}
						]
					}
				}
			}
		]
	}
});
