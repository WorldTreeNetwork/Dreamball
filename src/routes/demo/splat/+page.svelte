<!--
  Bonus Demo — SplatLens over a PlayCanvas-hosted gaussian splat asset.

  Uses a SOG (SuperSplat Optimized Gaussian) sample from the PlayCanvas
  engine examples CDN as the `look.asset[0].url`. The DreamBallViewer
  sees the splat media-type and routes to SplatLens automatically when
  called with `lens="avatar"`.

  First-class demonstration of: "how a DreamBall becomes a splat cloud
  without carrying a mesh — the topology-free graticule path from
  docs/VISION.md §4.4.5."
-->
<script lang="ts">
	import { DreamBallViewer, mockBall, type DreamBall, type Asset } from '$lib/index.js';

	const BONSAI_ASSET: Asset = {
		'media-type': 'application/vnd.playcanvas.gsplat+sog',
		hash: 'b58:mockBonsaiHash',
		url: [
			'https://raw.githubusercontent.com/playcanvas/engine/main/examples/assets/splats/bonsai.sog'
		]
	};

	const ball: DreamBall = mockBall('avatar', {
		name: 'Bonsai (ordered splat)',
		look: {
			asset: [BONSAI_ASSET],
			background: 'color:#050714'
		}
	});
</script>

<section>
	<h1>Bonus — Splat Lens</h1>
	<p>
		A Gaussian splat scene, rendered via PlayCanvas's native GSplat engine
		(WebGPU primary, WebGL2 fallback). The lens auto-activates when the
		DreamBall's primary <code>look.asset</code> has a splat media type.
	</p>
	<p class="hint">
		Click to lock the pointer. WASD to move. Scroll = speed. This is a
		real 12 MB splat asset loading from the PlayCanvas CDN — it may take a
		few seconds on first render.
	</p>

	<div class="stage">
		<DreamBallViewer {ball} lens="avatar" />
	</div>

	<h2>Why it matters</h2>
	<ul>
		<li>
			Splats are the <strong>topology-free rendering mode</strong> — no
			mesh, no UVs, just spatial distribution of gaussian primitives.
		</li>
		<li>
			SOG (SuperSplat Optimized Gaussian) is the <strong>ordered</strong>
			format — sorted by morton / spatial index so the renderer can stream
			+ draw progressively.
		</li>
		<li>
			This lens is the closest DreamBall comes today to the "omnispherical
			graticule" vision in <code>docs/VISION.md §4.4.5</code>.
		</li>
	</ul>
</section>

<style>
	section {
		max-width: 52rem;
		margin: 0 auto;
	}
	.hint {
		opacity: 0.6;
		font-size: 0.85rem;
	}
	.stage {
		margin: 1.5rem 0;
		background: #0a0e20;
		padding: 1rem;
		border-radius: 1rem;
	}
	h2 {
		margin-top: 2rem;
		color: #e0b7ff;
	}
	code {
		background: #1a2240;
		padding: 0.1rem 0.35rem;
		border-radius: 0.25rem;
		font-family: ui-monospace, Menlo, monospace;
	}
	ul {
		line-height: 1.5;
	}
</style>
