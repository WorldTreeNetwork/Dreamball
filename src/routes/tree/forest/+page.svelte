<!--
  /tree/forest — Phase 3 constellation view. A small SVG of orbiting
  Trees on the same Guild sky. Click a Tree → mocked traversal placeholder.
-->
<script lang="ts">
	interface OrbitTree {
		name: string;
		fp: string;
		x: number;
		y: number;
		r: number;
		hue: number;
		role: string;
	}

	const trees: OrbitTree[] = [
		{ name: 'WISHING TREE', fp: 'b58:self_tree_xxxx', x: 50, y: 50, r: 7, hue: 280, role: 'self' },
		{ name: 'KITE-FLYER', fp: 'b58:kiteflyer_tree_fp', x: 22, y: 28, r: 5, hue: 60, role: 'sibling' },
		{ name: 'GLASS-OWL', fp: 'b58:glassowl_tree_fp', x: 80, y: 35, r: 5, hue: 200, role: 'sibling' },
		{ name: 'SUGAR-WIND', fp: 'b58:sugarwind_tree_fp', x: 70, y: 78, r: 4.5, hue: 320, role: 'sibling' },
		{ name: 'SLOW-COMET', fp: 'b58:slowcomet_tree_fp', x: 18, y: 70, r: 4, hue: 100, role: 'orphan' },
		{ name: 'NORTH-LANTERN', fp: 'b58:northlantern_tree_fp', x: 50, y: 12, r: 4.5, hue: 30, role: 'sibling' }
	];

	let active: OrbitTree | null = $state(trees[0]);
</script>

<svelte:head>
	<title>The Wishing Tree · Forest</title>
</svelte:head>

<div class="forest">
	<header>
		<a class="back" href="/tree">◂ BACK TO COMPOSER</a>
		<span class="title">CONSTELLATION · phase 3 preview</span>
	</header>

	<div class="grid">
		<svg viewBox="0 0 100 100" class="sky" preserveAspectRatio="xMidYMid meet">
			<defs>
				<radialGradient id="bg" cx="50%" cy="40%" r="60%">
					<stop offset="0%" stop-color="#1f2a66" stop-opacity="0.45" />
					<stop offset="100%" stop-color="#050714" stop-opacity="0" />
				</radialGradient>
			</defs>
			<rect x="0" y="0" width="100" height="100" fill="#050714" />
			<rect x="0" y="0" width="100" height="100" fill="url(#bg)" />
			<g stroke="#1f2a66" stroke-width="0.18" fill="none">
				{#each Array(20) as _, i (i)}
					<line x1="0" y1={i * 5} x2="100" y2={i * 5} />
					<line x1={i * 5} y1="0" x2={i * 5} y2="100" />
				{/each}
			</g>
			{#each trees as t (t.fp)}
				{#if t.role !== 'self'}
					<line
						x1="50"
						y1="50"
						x2={t.x}
						y2={t.y}
						stroke={`hsl(${t.hue} 80% 55%)`}
						stroke-opacity={t.role === 'orphan' ? 0.15 : 0.45}
						stroke-dasharray={t.role === 'orphan' ? '0.8 1.2' : ''}
						stroke-width="0.4"
					/>
				{/if}
			{/each}
			{#each trees as t (t.fp)}
				<g
					transform="translate({t.x} {t.y})"
					onclick={() => (active = t)}
					onkeydown={(e) => {
						if (e.key === 'Enter') active = t;
					}}
					role="button"
					tabindex="0"
					aria-label={t.name}
				>
					<circle r={t.r + 1} fill="none" stroke={`hsl(${t.hue} 90% 60%)`} stroke-width="0.5" stroke-opacity="0.8" />
					<circle r={t.r} fill={`hsl(${t.hue} 70% 35%)`} stroke={`hsl(${t.hue} 95% 70%)`} stroke-width="0.6" />
					<text y={t.r + 4} text-anchor="middle" font-size="2.6" fill="#c9d0ff" font-family="monospace">
						{t.name}
					</text>
				</g>
			{/each}
		</svg>

		<aside class="info">
			<h2>SELECTED</h2>
			{#if active}
				<dl>
					<dt>name</dt>
					<dd style="color: hsl({active.hue} 90% 70%);">{active.name}</dd>
					<dt>role</dt>
					<dd>{active.role}</dd>
					<dt>fingerprint</dt>
					<dd class="fp">{active.fp}</dd>
				</dl>
				<button class="travel" type="button">TRAVEL → (mock · phase 3)</button>
			{:else}
				<p>click a star.</p>
			{/if}

			<h3 class="legend-h">LEGEND</h3>
			<ul class="legend">
				<li><span class="dot self"></span> self · this tree</li>
				<li><span class="dot sibling"></span> sibling · same guild</li>
				<li><span class="dot orphan"></span> orphan · derived-from only</li>
			</ul>

			<p class="footnote">
				phase 3 wires this to a real WS bridge — clicking a star will load
				its envelope, render its sphere, and let you transmit/receive
				across the Guild.
			</p>
		</aside>
	</div>
</div>

<style>
	.forest {
		min-height: 100vh;
		background: var(--wt-void);
		color: var(--wt-haze);
		font-family: var(--wt-font-mono);
		display: flex;
		flex-direction: column;
	}
	header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 10px 16px;
		border-bottom: 3px solid var(--wt-fruit-gold);
		background: repeating-linear-gradient(90deg, var(--wt-void) 0 3px, var(--wt-root) 3px 6px);
	}
	.back {
		color: var(--wt-frost-cyan);
		text-decoration: none;
		font-size: 11px;
		letter-spacing: 0.25em;
	}
	.back:hover {
		color: var(--wt-fruit-gold);
	}
	.title {
		color: var(--wt-wish-violet);
		font-size: 12px;
		letter-spacing: 0.3em;
		text-shadow: 1px 1px 0 var(--wt-void);
	}
	.grid {
		flex: 1;
		display: grid;
		grid-template-columns: 1fr 320px;
		gap: 12px;
		padding: 12px;
		min-height: 0;
	}
	.sky {
		width: 100%;
		height: 100%;
		max-height: calc(100vh - 80px);
		background: var(--wt-void);
		border: 2px solid var(--wt-fruit-gold);
		box-shadow: inset 1px 1px 0 var(--wt-haze), inset -2px -2px 0 var(--wt-trunk);
	}
	.sky g[role='button'] {
		cursor: pointer;
	}
	.info {
		font-size: 12px;
		color: var(--wt-haze);
		border: 2px solid var(--wt-wish-violet);
		padding: 12px;
		background: var(--wt-root);
		box-shadow: inset 1px 1px 0 var(--wt-haze);
	}
	.info h2,
	.info h3 {
		margin: 0 0 8px;
		font-size: 11px;
		letter-spacing: 0.3em;
		color: var(--wt-fruit-gold);
		text-shadow: 1px 1px 0 var(--wt-void);
	}
	.legend-h {
		margin-top: 14px;
	}
	dl {
		display: grid;
		grid-template-columns: max-content 1fr;
		gap: 4px 10px;
		margin: 0 0 12px;
	}
	dt {
		color: var(--wt-frost-cyan);
		font-size: 10px;
		letter-spacing: 0.1em;
	}
	dd {
		margin: 0;
	}
	.fp {
		word-break: break-all;
		font-size: 10px;
		color: var(--wt-mist);
	}
	.travel {
		all: unset;
		cursor: pointer;
		display: block;
		text-align: center;
		padding: 6px;
		background: var(--wt-fruit-gold);
		color: var(--wt-void);
		font-weight: 700;
		letter-spacing: 0.2em;
		border: 2px solid var(--wt-fruit-gold);
		box-shadow: inset 1px 1px 0 var(--wt-haze), inset -1px -1px 0 var(--wt-amber);
		font-size: 11px;
	}
	.legend {
		list-style: none;
		padding: 0;
		margin: 0 0 12px;
		font-size: 11px;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.dot {
		display: inline-block;
		width: 10px;
		height: 10px;
		margin-right: 6px;
		vertical-align: middle;
	}
	.dot.self {
		background: var(--wt-wish-violet);
	}
	.dot.sibling {
		background: var(--wt-fruit-gold);
	}
	.dot.orphan {
		background: var(--wt-mist);
	}
	.footnote {
		font-size: 10px;
		color: var(--wt-wish-violet);
		margin: 0;
	}
</style>
