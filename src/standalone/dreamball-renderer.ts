/**
 * Standalone DreamBall Web renderer — the lens layer, bundled to ride
 * alongside dreamball.wasm.
 *
 * This is the "Web rendering engine" from docs/prd-rendering-engines.md as a
 * portable artifact: the lens IS the renderer, and here it's vendored exactly
 * like the wasm. One self-contained ESM file (Svelte 5 runtime + Threlte +
 * three + AvatarLens + the wasm decode path) drops next to dreamball.wasm on
 * any static host and renders a signed character ball with no build step:
 *
 *   <script type="module">
 *     import { mountDreamBall } from '/vendor/dreamball-renderer.js';
 *     const h = await mountDreamBall(
 *       document.getElementById('stage'),
 *       '/vendor/star-tamagotchi.ball'
 *     );
 *     console.log(h.verified, h.ball.name);  // true "Star Tamagotchi"
 *   </script>
 *
 * It mounts AvatarLens directly (not DreamBallViewer) so the bundle stays the
 * mesh/glTF path only — no PlayCanvas (splat) or kuzu (palace) pulled in.
 */
import { mount, unmount } from 'svelte';
import AvatarLens from '../lib/lenses/AvatarLens.svelte';
import { parseBall, verifyBall } from '../lib/wasm/loader.js';
import type { DreamBall } from '../lib/generated/types.js';

export interface DreamBallHandle {
	/** The decoded, validated DreamBall (from dreamball.wasm parseBall). */
	ball: DreamBall;
	/** True if signatures verified (Ed25519, plus ML-DSA when present). */
	verified: boolean;
	/** Human-readable verification status for HUD/badges. */
	verifyStatus: string;
	/** Tear down the renderer and release the canvas. */
	destroy(): void;
}

async function toBytes(src: string | Uint8Array | ArrayBuffer): Promise<Uint8Array> {
	if (src instanceof Uint8Array) return src;
	if (src instanceof ArrayBuffer) return new Uint8Array(src);
	const resp = await fetch(src);
	if (!resp.ok) throw new Error(`dreamball: fetch ${src} -> ${resp.status}`);
	return new Uint8Array(await resp.arrayBuffer());
}

/**
 * Decode a signed .ball through dreamball.wasm and mount AvatarLens into
 * `target`. `src` may be a URL, raw bytes, or an ArrayBuffer.
 *
 * The capsule is the source of truth: we verify + decode it with the same
 * wasm used on the server and CLI, then hand the typed ball to the lens,
 * which reads look.asset and loads the glTF.
 */
export async function mountDreamBall(
	target: HTMLElement,
	src: string | Uint8Array | ArrayBuffer
): Promise<DreamBallHandle> {
	const bytes = await toBytes(src);

	const v = await verifyBall(bytes);
	const verifyStatus = v.ok
		? v.hadEd25519
			? 'signature verified'
			: 'parsed (unsigned)'
		: `verify failed: ${v.reason ?? v.code}`;

	const ball = (await parseBall(bytes)) as unknown as DreamBall;

	const app = mount(AvatarLens, { target, props: { ball } });

	return {
		ball,
		verified: v.ok,
		verifyStatus,
		destroy() {
			unmount(app);
		}
	};
}

// Also expose on window for plain <script type="module"> pages that prefer a
// global over an import binding.
declare global {
	interface Window {
		DreamBallRenderer?: { mountDreamBall: typeof mountDreamBall };
	}
}
if (typeof window !== 'undefined') {
	window.DreamBallRenderer = { mountDreamBall };
}
