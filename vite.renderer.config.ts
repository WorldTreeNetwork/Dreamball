/**
 * Standalone build for the vendorable DreamBall Web renderer.
 *
 *   bun run build:renderer
 *
 * Produces a single self-contained ESM bundle (Svelte runtime + Threlte +
 * three + AvatarLens + the wasm decode path, wasm inlined as base64) in
 * release/dreamball-web-renderer/ — the renderer riding alongside
 * release/dreamball-wasm/.
 *
 * The bundle filename is CONTENT-HASHED (dreamball-renderer-<hash>.js) so the
 * static host's `Cache-Control: immutable` header is actually correct: a new
 * build is a new URL, so consumers never serve a stale renderer (no
 * hard-refresh, no ?v= cache-busting). A manifest.json maps the stable logical
 * name to the current hashed file; the deploy script (scripts/deploy-renderer.sh)
 * reads it to stamp the consuming page.
 *
 * Not part of the SvelteKit app build; this is a plain Vite lib build so the
 * output has no Kit/runtime assumptions and drops into any static host.
 */
import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import type { Plugin } from 'vite';

/** Emit manifest.json mapping the stable logical name → the hashed entry file. */
function emitRendererManifest(): Plugin {
	return {
		name: 'emit-renderer-manifest',
		generateBundle(_options, bundle) {
			const entry = Object.values(bundle).find((c) => c.type === 'chunk' && c.isEntry);
			if (!entry) return;
			this.emitFile({
				type: 'asset',
				fileName: 'manifest.json',
				source: JSON.stringify({ 'dreamball-renderer.js': entry.fileName }, null, 2) + '\n'
			});
		}
	};
}

export default defineConfig({
	// emitCss:false → the Svelte compiler injects component styles via JS, so the
	// bundle is a true single file (no separate .css for consumers to link).
	plugins: [svelte({ emitCss: false, compilerOptions: { runes: true } }), emitRendererManifest()],
	build: {
		lib: {
			entry: 'src/standalone/dreamball-renderer.ts',
			formats: ['es']
		},
		outDir: 'release/dreamball-web-renderer',
		emptyOutDir: true,
		target: 'es2022',
		assetsInlineLimit: 0,
		rollupOptions: {
			output: {
				// Content-hashed entry → correct under an immutable cache header.
				entryFileNames: 'dreamball-renderer-[hash].js',
				assetFileNames: '[name][extname]',
				// Fold the dynamic wasm-loader chunk in → one self-contained file.
				inlineDynamicImports: true
			}
		}
	}
});
