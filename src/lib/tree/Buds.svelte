<!--
  Buds — overlay of wish glyphs positioned around the Soulskin sphere
  according to their branch direction. Each lifecycle state animates
  differently (tied: still, budding: bouncing, ripening: glowing,
  ripe: pulsing gold, plucked: fades).
-->
<script lang="ts">
	import type { Wish } from './wishes.svelte.js';
	import { branchAngle } from './wishes.svelte.js';

	interface Props {
		wishes: Wish[];
		size: number;
	}
	let { wishes, size }: Props = $props();

	function position(w: Wish, idx: number): { left: string; top: string } {
		const angle = (branchAngle(w.branch) + idx * 12) * (Math.PI / 180);
		const r = size * 0.55;
		const cx = size / 2;
		const cy = size / 2;
		const x = cx + Math.cos(angle) * r;
		const y = cy + Math.sin(angle) * r;
		return { left: `${x}px`, top: `${y}px` };
	}

	function glyph(w: Wish): string {
		switch (w.state) {
			case 'tied':
				return '✦';
			case 'budding':
				return '❂';
			case 'ripening':
				return '◐';
			case 'ripe':
				return '●';
			default:
				return '·';
		}
	}
</script>

<div class="buds" style="width: {size}px; height: {size}px;" aria-hidden="true">
	{#each wishes.slice(0, 24) as w, i (w.id)}
		{@const p = position(w, i)}
		<span
			class="bud state-{w.state}"
			style="left: {p.left}; top: {p.top};"
			title={w.text}
		>
			{glyph(w)}
		</span>
	{/each}
</div>

<style>
	.buds {
		position: absolute;
		inset: 0;
		pointer-events: none;
	}
	.bud {
		position: absolute;
		transform: translate(-50%, -50%);
		font-size: 14px;
		font-family: var(--wt-font-mono);
		text-shadow: 0 0 8px currentColor;
	}
	.bud.state-tied {
		color: var(--wt-mist);
	}
	.bud.state-budding {
		color: var(--wt-sap-green);
		animation: bud-bounce 1s ease-in-out infinite;
	}
	.bud.state-ripening {
		color: var(--wt-amber);
		animation: bud-spin 2s linear infinite;
		display: inline-block;
	}
	.bud.state-ripe {
		color: var(--wt-fruit-gold);
		font-size: 18px;
		animation: bud-pulse 1.4s ease-in-out infinite;
	}
	.bud.state-plucked {
		color: var(--wt-mist);
		opacity: 0.3;
	}
	@keyframes bud-bounce {
		0%,
		100% {
			transform: translate(-50%, -55%);
		}
		50% {
			transform: translate(-50%, -45%);
		}
	}
	@keyframes bud-spin {
		to {
			transform: translate(-50%, -50%) rotate(360deg);
		}
	}
	@keyframes bud-pulse {
		0%,
		100% {
			text-shadow: 0 0 8px var(--wt-fruit-gold);
		}
		50% {
			text-shadow: 0 0 18px var(--wt-fruit-gold);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.bud {
			animation: none !important;
		}
	}
</style>
