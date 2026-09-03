import adapter from '@sveltejs/adapter-auto';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	compilerOptions: {
		// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
		runes: ({ filename }) => (filename.split(/[/\\]/).includes('node_modules') ? undefined : true)
	},
	kit: {
		// adapter-auto only supports some environments, see https://svelte.dev/docs/kit/adapter-auto for a list.
		// If your environment is not supported, or you settled on a specific environment, switch out the adapter.
		// See https://svelte.dev/docs/kit/adapters for more information about adapters.
		adapter: adapter(),
		// Story 4.1 — `@dreamball/palace-client` is the path alias for the
		// generated TS client at `src/lib/generated/palace-client.ts`. Using
		// `kit.alias` rather than tsconfig `paths` because SvelteKit
		// auto-manages `paths` and overriding it triggers a noisy warning
		// (and can desync svelte-kit's generated tsconfig at sync time).
		// No real npm package ships in sprint-002 — this is a path import
		// dressed up as a package alias for caller ergonomics (D-034).
		alias: {
			'@dreamball/palace-client': 'src/lib/generated/palace-client.ts'
		}
	}
};

export default config;
