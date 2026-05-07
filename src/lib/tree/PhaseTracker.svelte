<!--
  PhaseTracker — visual progress across the five phases. Computed from
  the WishGarden's lived counters: wishes tied → buds → fruits → plucks →
  transmissions → publish. A dot lights when its phase has had any
  activity. Adds visible progression to the otherwise-myth-only PHASES
  document.
-->
<script lang="ts">
	import type { WishGarden } from './wishes.svelte.js';

	interface Props {
		garden: WishGarden;
		published: boolean;
	}
	let { garden, published }: Props = $props();

	const phases = $derived([
		{ name: 'SAPLING', lit: true, hint: 'composer shell · sphere · primitives' },
		{ name: 'AGENT TREE', lit: garden.wishes.length > 0, hint: 'wishes · germination · pluck' },
		{ name: 'FOREST', lit: garden.transmissions > 0, hint: 'wind-carried seeds · guild' },
		{ name: 'WORLD TREE', lit: garden.plucks > 2, hint: 'bridges · constellation · real crypto' },
		{ name: 'SELF-PLANT', lit: published, hint: 'tree publishes the tree' }
	]);
</script>

<ol class="track">
	{#each phases as p, i (i)}
		<li class:lit={p.lit}>
			<span class="num">{i}</span>
			<span class="name">{p.name}</span>
			<span class="hint">{p.hint}</span>
			<span class="bar"><span class="fill" class:on={p.lit}></span></span>
		</li>
	{/each}
</ol>

<style>
	.track {
		list-style: none;
		padding: 0;
		margin: 0;
		font-family: var(--wt-font-mono);
		font-size: 10px;
		display: grid;
		grid-template-columns: 1fr;
		gap: 4px;
	}
	.track li {
		display: grid;
		grid-template-columns: 18px 1fr auto;
		grid-template-rows: auto auto;
		gap: 4px 8px;
		padding: 4px 0;
		border-bottom: 1px dotted var(--wt-branch);
	}
	.num {
		grid-row: 1 / span 2;
		text-align: center;
		font-weight: 700;
		color: var(--wt-mist);
		font-size: 14px;
	}
	.lit .num {
		color: var(--wt-fruit-gold);
	}
	.name {
		letter-spacing: 0.25em;
		color: var(--wt-mist);
	}
	.lit .name {
		color: var(--wt-fruit-gold);
	}
	.hint {
		grid-column: 2 / span 2;
		color: var(--wt-mist);
		font-size: 9px;
	}
	.lit .hint {
		color: var(--wt-haze);
	}
	.bar {
		width: 60px;
		height: 6px;
		background: var(--wt-root);
		border: 1px solid var(--wt-branch);
		display: block;
		grid-column: 3;
	}
	.fill {
		display: block;
		height: 100%;
		width: 0;
		background: repeating-linear-gradient(
			90deg,
			var(--wt-fruit-gold) 0 4px,
			var(--wt-amber) 4px 8px
		);
		transition: width 0.3s ease-out;
	}
	.fill.on {
		width: 100%;
	}
</style>
