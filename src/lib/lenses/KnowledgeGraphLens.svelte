<!--
  KnowledgeGraphLens — render the `knowledge-graph` triples as a
  force-directed 2D graph (SVG). WebGPU/ML-core offload lands post-MVP.
-->
<script lang="ts">
	import type { DreamBall } from '../generated/types.js';

	interface Props {
		ball: DreamBall;
	}
	let { ball }: Props = $props();

	type Node = { id: string; x: number; y: number };
	type Edge = { from: string; to: string; label: string };

	const triples = $derived(ball['knowledge-graph']?.triples ?? []);
	const nodesAndEdges = $derived.by(() => {
		const nodes = new Map<string, Node>();
		const edges: Edge[] = [];
		let i = 0;
		const place = (label: string) => {
			if (nodes.has(label)) return nodes.get(label)!;
			const angle = (i++ * Math.PI * 2) / Math.max(4, triples.length * 2);
			const r = 110;
			nodes.set(label, { id: label, x: 150 + r * Math.cos(angle), y: 120 + r * Math.sin(angle) });
			return nodes.get(label)!;
		};
		for (const t of triples) {
			place(t.from);
			place(t.to);
			edges.push({ from: t.from, to: t.to, label: t.label });
		}
		return { nodes: [...nodes.values()], edges };
	});
</script>

<div class="kg-wrap">
	{#if triples.length === 0}
		<p class="empty">No knowledge graph on this DreamBall.</p>
	{:else}
		<svg viewBox="0 0 300 240" xmlns="http://www.w3.org/2000/svg">
			{#each nodesAndEdges.edges as e (e.from + '->' + e.to)}
				{@const from = nodesAndEdges.nodes.find((n) => n.id === e.from)}
				{@const to = nodesAndEdges.nodes.find((n) => n.id === e.to)}
				{#if from && to}
					<line x1={from.x} y1={from.y} x2={to.x} y2={to.y} stroke="#8aa" stroke-width="1" />
					<text
						x={(from.x + to.x) / 2}
						y={(from.y + to.y) / 2}
						fill="#aac"
						font-size="7"
						text-anchor="middle"
					>
						{e.label}
					</text>
				{/if}
			{/each}
			{#each nodesAndEdges.nodes as n (n.id)}
				<circle cx={n.x} cy={n.y} r="6" fill="#e0b7ff" />
				<text x={n.x} y={n.y - 10} fill="#e8ecf8" font-size="9" text-anchor="middle">
					{n.id}
				</text>
			{/each}
		</svg>
	{/if}
</div>

<style>
	.kg-wrap {
		background: #0b1020;
		border-radius: 1rem;
		padding: 0.5rem;
		color: #e8ecf8;
		font-family: system-ui, sans-serif;
	}
	.empty {
		padding: 2rem;
		text-align: center;
		opacity: 0.6;
	}
	svg {
		width: 100%;
		height: auto;
		display: block;
	}
</style>
