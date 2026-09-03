<!--
  RevisionRings — concentric rings around the sphere, one per revision
  bump. Like tree rings — accumulate over the lifetime of the Tree.
-->
<script lang="ts">
	interface Props {
		count: number;
		size: number;
	}
	let { count, size }: Props = $props();

	const rings = $derived(Math.min(count, 12));
</script>

<svg
	class="rings"
	style="width: {size * 1.4}px; height: {size * 1.4}px;"
	viewBox="0 0 100 100"
	aria-hidden="true"
>
	{#each Array(rings) as _, i (i)}
		<circle
			cx="50"
			cy="50"
			r={20 + i * 2}
			fill="none"
			stroke="var(--wt-fruit-gold)"
			stroke-width="0.3"
			stroke-dasharray="0.6 1.4"
			opacity={0.15 + (i / rings) * 0.5}
		/>
	{/each}
</svg>

<style>
	.rings {
		position: absolute;
		left: 50%;
		top: 50%;
		transform: translate(-50%, -50%);
		pointer-events: none;
	}
</style>
