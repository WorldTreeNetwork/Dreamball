<!--
  DreamBallCard — listing-surface thumbnail. Uses the ThumbnailLens under
  the hood and adds an onSelect callback for listing UIs.
-->
<script lang="ts">
	import type { DreamBall } from '../generated/types.js';
	import ThumbnailLens from '../lenses/ThumbnailLens.svelte';

	interface Props {
		ball: DreamBall;
		onSelect?: (ball: DreamBall) => void;
	}
	let { ball, onSelect }: Props = $props();
</script>

<button class="card-button" type="button" onclick={() => onSelect?.(ball)}>
	<ThumbnailLens {ball} />
</button>

<style>
	.card-button {
		background: transparent;
		border: none;
		padding: 0;
		cursor: pointer;
		display: inline-block;
		transition: transform 120ms ease;
	}
	.card-button:hover {
		transform: translateY(-2px);
	}
</style>
