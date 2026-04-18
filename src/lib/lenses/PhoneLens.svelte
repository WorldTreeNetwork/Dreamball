<!--
  PhoneLens — portrait-optimised summary. Stacks thumbnail + feel + a
  collapsed action row. Sized for mobile viewports but works on desktop
  as a vertical card.
-->
<script lang="ts">
	import type { DreamBall } from '../generated/types.js';
	import ThumbnailLens from './ThumbnailLens.svelte';

	interface Props {
		ball: DreamBall;
	}
	let { ball }: Props = $props();
</script>

<section class="phone">
	<ThumbnailLens {ball} />
	{#if ball.feel}
		<div class="feel">
			{#if ball.feel.personality}<p>{ball.feel.personality}</p>{/if}
			{#if ball.feel.voice}<p class="sub">voice: {ball.feel.voice}</p>{/if}
		</div>
	{/if}
	<div class="actions">
		<button type="button" disabled>Wear</button>
		<button type="button" disabled>Transmit</button>
		<button type="button" disabled>Seal</button>
	</div>
</section>

<style>
	.phone {
		display: grid;
		gap: 1rem;
		max-width: 18rem;
		padding: 1rem;
		background: #07080f;
		border-radius: 1.5rem;
		color: #e8ecf8;
		font-family: system-ui, sans-serif;
	}
	.feel {
		background: #101630;
		padding: 0.7rem 0.9rem;
		border-radius: 0.6rem;
	}
	.feel p {
		margin: 0 0 0.3rem;
		font-size: 0.9rem;
	}
	.feel .sub {
		opacity: 0.65;
		font-size: 0.8rem;
	}
	.actions {
		display: flex;
		gap: 0.5rem;
	}
	.actions button {
		flex: 1;
		padding: 0.5rem 0.6rem;
		border-radius: 0.5rem;
		border: 1px solid #303a6a;
		background: transparent;
		color: inherit;
		opacity: 0.5;
	}
</style>
