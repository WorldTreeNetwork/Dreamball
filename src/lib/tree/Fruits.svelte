<!--
  Fruits — list of ripe DreamBalls awaiting pluck. Phase 1.
  Pluck → mock .jelly.json downloads + revision bumps.
-->
<script lang="ts">
	import { iconFor } from './icons.js';
	import type { WishGarden } from './wishes.svelte.js';
	import { downloadFruit } from './dreamball-export.js';
	import { SFX } from './style/sfx.js';

	interface Props {
		garden: WishGarden;
	}
	let { garden }: Props = $props();

	function pluck(id: string) {
		const fruit = garden.pluck(id);
		if (!fruit) return;
		downloadFruit(fruit);
		SFX.start();
	}
</script>

<div class="fruits">
	{#if garden.wishes.length === 0}
		<p class="empty">no fruits yet — tie a wish, watch it ripen.</p>
	{:else}
		<ul class="list">
			{#each garden.wishes as w (w.id)}
				<li class="row state-{w.state}">
					<span class="state-mark" aria-hidden="true">
						{#if w.state === 'tied'}✦
						{:else if w.state === 'budding'}❂
						{:else if w.state === 'ripening'}◐
						{:else if w.state === 'ripe'}●
						{:else}□{/if}
					</span>
					<span class="text">
						<span class="title">{w.text}</span>
						<span class="meta">
							{w.state.toUpperCase()} · branch {w.branch}
							{#if w.fruit}· {w.fruit.icon} {w.fruit.type}{/if}
						</span>
						{#if w.fruit && w.state === 'ripe'}
							<span class="whisper">“{w.fruit.whisper}”</span>
						{/if}
					</span>
					{#if w.state === 'ripe' && w.fruit}
						<button class="pluck" type="button" onclick={() => pluck(w.id)}>
							PLUCK ↓
						</button>
					{:else if w.state === 'plucked'}
						<span class="done">✓</span>
					{:else}
						<span class="wait">…</span>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.fruits {
		font-family: var(--wt-font-mono);
		font-size: 11px;
		color: var(--wt-haze);
	}
	.empty {
		color: var(--wt-mist);
		font-style: italic;
		margin: 0;
	}
	.list {
		list-style: none;
		padding: 0;
		margin: 0;
		max-height: 240px;
		overflow: auto;
	}
	.row {
		display: grid;
		grid-template-columns: 18px 1fr auto;
		gap: 8px;
		padding: 6px 4px;
		border-bottom: 1px dotted var(--wt-branch);
		align-items: center;
	}
	.state-mark {
		text-align: center;
		font-size: 14px;
	}
	.row.state-tied .state-mark {
		color: var(--wt-mist);
	}
	.row.state-budding .state-mark {
		color: var(--wt-sap-green);
		animation: wt-pulse 1s ease-in-out infinite;
	}
	.row.state-ripening .state-mark {
		color: var(--wt-amber);
		animation: wt-spin 1.5s linear infinite;
		display: inline-block;
	}
	.row.state-ripe .state-mark {
		color: var(--wt-fruit-gold);
		text-shadow: 0 0 8px var(--wt-fruit-gold);
	}
	.row.state-plucked {
		opacity: 0.5;
	}
	.text {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.title {
		color: var(--wt-haze);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.meta {
		color: var(--wt-mist);
		font-size: 10px;
		letter-spacing: 0.05em;
	}
	.whisper {
		color: var(--wt-wish-violet);
		font-style: italic;
		font-size: 10px;
	}
	.pluck {
		all: unset;
		cursor: pointer;
		font-size: 10px;
		letter-spacing: 0.2em;
		padding: 4px 8px;
		color: var(--wt-void);
		background: var(--wt-fruit-gold);
		border: 2px solid var(--wt-fruit-gold);
		font-weight: 700;
		box-shadow:
			inset 1px 1px 0 var(--wt-haze),
			inset -1px -1px 0 var(--wt-amber);
	}
	.pluck:hover {
		background: var(--wt-amber);
	}
	.wait {
		color: var(--wt-mist);
		font-size: 12px;
	}
	.done {
		color: var(--wt-sap-green);
	}
	@keyframes wt-pulse {
		0%,
		100% {
			opacity: 1;
		}
		50% {
			opacity: 0.4;
		}
	}
	@keyframes wt-spin {
		to {
			transform: rotate(360deg);
		}
	}
</style>
