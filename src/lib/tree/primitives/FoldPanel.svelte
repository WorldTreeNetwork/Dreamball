<!--
  FoldPanel — origami-collapsible panel. Expanded by default.
  Chevron ▾ expanded / ▸ collapsed. Keyboard: Enter/Space toggles.
  See docs/products/wishing-tree/PHASES.md §2.1.
-->
<script lang="ts">
	import type { Snippet } from 'svelte';
	import { SFX } from '../style/sfx.js';

	interface Props {
		title: string;
		open?: boolean;
		children?: Snippet;
		align?: 'left' | 'right';
	}

	let { title, open = $bindable(true), children, align = 'left' }: Props = $props();

	function toggle() {
		open = !open;
		SFX.fold();
	}
</script>

<section class="fold" data-open={open} data-align={align}>
	<button
		class="header"
		type="button"
		aria-expanded={open}
		onclick={toggle}
		onkeydown={(e) => {
			if (e.key === 'Enter' || e.key === ' ') {
				e.preventDefault();
				toggle();
			}
		}}
	>
		<span class="chev" aria-hidden="true">{open ? '▾' : '▸'}</span>
		<span class="title">{title}</span>
	</button>
	{#if open}
		<div class="body">
			{@render children?.()}
		</div>
	{/if}
</section>

<style>
	.fold {
		border: 2px solid var(--wt-fruit-gold);
		background: color-mix(in srgb, var(--wt-root) 92%, transparent);
		box-shadow:
			inset 1px 1px 0 var(--wt-haze),
			inset -2px -2px 0 var(--wt-trunk),
			0 0 0 2px var(--wt-void);
		font-family: var(--wt-font-mono);
		color: var(--wt-haze);
		display: flex;
		flex-direction: column;
		min-width: 0;
		image-rendering: pixelated;
	}
	.fold[data-open='false'] {
		min-width: 32px;
		max-width: 32px;
	}
	.header {
		all: unset;
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 6px 10px;
		background:
			repeating-linear-gradient(90deg, var(--wt-trunk) 0 4px, var(--wt-branch) 4px 8px);
		border-bottom: 2px solid var(--wt-fruit-gold);
		cursor: pointer;
		user-select: none;
		color: var(--wt-fruit-gold);
		font-size: 11px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.18em;
		text-shadow: 1px 1px 0 var(--wt-void);
	}
	.header:hover {
		background: linear-gradient(180deg, var(--wt-branch), var(--wt-trunk));
		color: var(--wt-wish-violet);
	}
	.header:focus-visible {
		outline: 2px solid var(--wt-fruit-gold);
		outline-offset: -2px;
	}
	.fold[data-open='false'] .title {
		display: none;
	}
	.chev {
		width: 10px;
		display: inline-block;
		text-align: center;
		color: var(--wt-fruit-gold);
	}
	.body {
		padding: 10px 12px;
		overflow: auto;
	}
	.fold[data-align='right'] .header {
		justify-content: flex-end;
		flex-direction: row-reverse;
	}
</style>
