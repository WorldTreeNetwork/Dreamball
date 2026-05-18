<!--
  InnerGraph — the view INSIDE the sphere. Lives next to SoulskinSphere
  (not modal). Shows node sprites + geodesic connection lines as a
  flat 8-bit diagram. Phase 0 is a static diagram; Phase 1 makes the
  nodes addressable + editable.
-->
<script lang="ts">
	interface NodeDot {
		id: string;
		label: string;
		x: number;
		y: number;
		kind: string;
	}
	interface Edge {
		from: string;
		to: string;
		kind: 'data' | 'execute' | 'reference' | 'inherit';
	}

	const nodes: NodeDot[] = [
		{ id: 'shader', label: 'soulskin', x: 0.5, y: 0.18, kind: 'shader' },
		{ id: 'mesh', label: 'icosphere', x: 0.78, y: 0.4, kind: 'mesh' },
		{ id: 'grat', label: 'graticule', x: 0.82, y: 0.7, kind: 'graticule' },
		{ id: 'model', label: 'claude-opus', x: 0.5, y: 0.55, kind: 'model' },
		{ id: 'prompt', label: 'invocation', x: 0.2, y: 0.4, kind: 'prompt' },
		{ id: 'key', label: 'root-key', x: 0.15, y: 0.85, kind: 'secret' }
	];
	const edges: Edge[] = [
		{ from: 'shader', to: 'mesh', kind: 'data' },
		{ from: 'shader', to: 'grat', kind: 'data' },
		{ from: 'model', to: 'prompt', kind: 'execute' },
		{ from: 'model', to: 'shader', kind: 'reference' },
		{ from: 'key', to: 'model', kind: 'inherit' }
	];

	function nodePos(id: string): NodeDot {
		return nodes.find((n) => n.id === id)!;
	}

	function edgeDash(k: Edge['kind']): string {
		return { data: '', execute: '6 4', reference: '2 4', inherit: '10 2' }[k];
	}
	function edgeColor(k: Edge['kind']): string {
		return {
			data: 'var(--wt-sap-green)',
			execute: 'var(--wt-fruit-gold)',
			reference: 'var(--wt-mist)',
			inherit: 'var(--wt-wish-violet)'
		}[k];
	}

	function glyph(k: string): string {
		return { shader: '▒', mesh: '▣', graticule: '◈', model: '◆', prompt: '❞', secret: '🔒' }[k] ?? '·';
	}
</script>

<figure class="inner" aria-label="Sphere interior — node graph">
	<figcaption>
		<span class="lbl">INTERIOR · node graph</span>
		<span class="legend">
			<span class="sw data"></span>data
			<span class="sw exe"></span>exec
			<span class="sw ref"></span>ref
			<span class="sw inh"></span>inherit
		</span>
	</figcaption>
	<svg viewBox="0 0 200 200" preserveAspectRatio="xMidYMid meet" role="img">
		<rect x="0" y="0" width="200" height="200" fill="var(--wt-void)" />
		<g stroke="var(--wt-branch)" stroke-width="0.6" fill="none">
			{#each Array(8) as _, i (i)}
				<line x1="0" y1={i * 25} x2="200" y2={i * 25} />
				<line x1={i * 25} y1="0" x2={i * 25} y2="200" />
			{/each}
		</g>
		<circle cx="100" cy="100" r="80" fill="none" stroke="var(--wt-trunk)" stroke-width="1" />
		<circle cx="100" cy="100" r="60" fill="none" stroke="var(--wt-branch)" stroke-width="0.6" stroke-dasharray="3 3" />
		{#each edges as e, i (i)}
			{@const a = nodePos(e.from)}
			{@const b = nodePos(e.to)}
			<line
				x1={a.x * 200}
				y1={a.y * 200}
				x2={b.x * 200}
				y2={b.y * 200}
				stroke={edgeColor(e.kind)}
				stroke-width="1.4"
				stroke-dasharray={edgeDash(e.kind)}
				opacity="0.85"
			/>
		{/each}
		{#each nodes as n, i (i)}
			<g transform="translate({n.x * 200} {n.y * 200})">
				<rect x="-12" y="-10" width="24" height="20" fill="var(--wt-root)" stroke="var(--wt-fruit-gold)" stroke-width="1.5" />
				<text x="0" y="4" text-anchor="middle" font-size="12" fill="var(--wt-fruit-gold)" font-family="monospace">
					{glyph(n.kind)}
				</text>
				<text x="0" y="20" text-anchor="middle" font-size="7" fill="var(--wt-haze)" font-family="monospace">
					{n.label}
				</text>
			</g>
		{/each}
	</svg>
</figure>

<style>
	.inner {
		margin: 0;
		padding: 0;
		background: var(--wt-void);
		border: 2px solid var(--wt-fruit-gold);
		box-shadow:
			inset 1px 1px 0 var(--wt-haze),
			inset -2px -2px 0 var(--wt-root);
		display: flex;
		flex-direction: column;
		font-family: var(--wt-font-mono);
	}
	figcaption {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 4px 8px;
		font-size: 10px;
		letter-spacing: 0.25em;
		color: var(--wt-frost-cyan);
		background: linear-gradient(180deg, var(--wt-branch), var(--wt-trunk));
		border-bottom: 1px solid var(--wt-fruit-gold);
	}
	.legend {
		display: flex;
		gap: 8px;
		text-transform: none;
		letter-spacing: 0.05em;
		color: var(--wt-mist);
		font-size: 9px;
		align-items: center;
	}
	.sw {
		display: inline-block;
		width: 8px;
		height: 3px;
		margin-right: 3px;
	}
	.sw.data {
		background: var(--wt-sap-green);
	}
	.sw.exe {
		background: var(--wt-fruit-gold);
	}
	.sw.ref {
		background: var(--wt-mist);
	}
	.sw.inh {
		background: var(--wt-wish-violet);
	}
	svg {
		width: 100%;
		height: auto;
		display: block;
	}
</style>
