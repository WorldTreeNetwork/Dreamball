<!--
  Horizon — sibling Trees on the same Guild sky. Phase 2.
  Click a Tree to "transmit" the latest ripe fruit (mocked).
-->
<script lang="ts">
	import { iconFor } from './icons.js';
	import type { WishGarden } from './wishes.svelte.js';
	import { SFX } from './style/sfx.js';

	interface Props {
		garden: WishGarden;
		onsend?: (target: string, fruitName?: string) => void;
	}
	let { garden, onsend }: Props = $props();

	const siblings = [
		{ name: 'KITE-FLYER', fp: 'b58:kiteflyer_tree_fp_xxxxx', dist: 12 },
		{ name: 'GLASS-OWL', fp: 'b58:glassowl_tree_fp_xxxxxx', dist: 28 },
		{ name: 'SUGAR-WIND', fp: 'b58:sugarwind_tree_fp_xxxxx', dist: 41 }
	];

	let lastSent: string = $state('—');

	function send(target: string) {
		const ripe = garden.wishes.find((w) => w.state === 'ripe');
		const name = ripe?.fruit?.name ?? 'untyped seed';
		garden.transmit();
		lastSent = `${name} → ${target}`;
		onsend?.(target, name);
		SFX.peel();
	}
</script>

<div class="horizon">
	<ul class="trees">
		{#each siblings as s (s.fp)}
			<li class="tree">
				<button class="cell" type="button" onclick={() => send(s.name)}>
					<span class="ico">{iconFor('field')}</span>
					<span class="info">
						<span class="name">{s.name}</span>
						<span class="dist">{s.dist} ly · same-guild</span>
					</span>
					<span class="cta">SEND →</span>
				</button>
			</li>
		{/each}
	</ul>
	<div class="status">last wind: <span>{lastSent}</span></div>
	<div class="counter">transmissions: <strong>{garden.transmissions}</strong></div>
</div>

<style>
	.horizon {
		font-family: var(--wt-font-mono);
		font-size: 11px;
		color: var(--wt-haze);
	}
	.trees {
		list-style: none;
		padding: 0;
		margin: 0 0 8px;
	}
	.tree {
		margin-bottom: 4px;
	}
	.cell {
		all: unset;
		cursor: pointer;
		display: grid;
		grid-template-columns: 18px 1fr auto;
		gap: 6px;
		align-items: center;
		padding: 6px 8px;
		border: 2px solid var(--wt-branch);
		background: var(--wt-root);
		width: calc(100% - 16px);
		box-shadow:
			inset 1px 1px 0 var(--wt-haze),
			inset -1px -1px 0 var(--wt-void);
	}
	.cell:hover {
		border-color: var(--wt-wish-violet);
		color: var(--wt-wish-violet);
	}
	.ico {
		color: var(--wt-fruit-gold);
	}
	.info {
		display: flex;
		flex-direction: column;
	}
	.name {
		letter-spacing: 0.2em;
	}
	.dist {
		color: var(--wt-mist);
		font-size: 9px;
		letter-spacing: 0.15em;
	}
	.cta {
		color: var(--wt-frost-cyan);
		font-size: 10px;
		letter-spacing: 0.25em;
	}
	.status,
	.counter {
		color: var(--wt-mist);
		font-size: 10px;
		margin-top: 4px;
	}
	.status span {
		color: var(--wt-wish-violet);
	}
	.counter strong {
		color: var(--wt-fruit-gold);
	}
</style>
