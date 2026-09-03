<!--
  Huddle — grouped container. Draggable via header. Phase 0: positional
  drag only; serialise/reparent semantics arrive in Phase 1.
  See docs/products/wishing-tree/PHASES.md §2.3.
-->
<script lang="ts">
	import type { Snippet } from 'svelte';

	interface Props {
		name: string;
		children?: Snippet;
		x?: number;
		y?: number;
		draggable?: boolean;
	}

	let { name, children, x = $bindable(40), y = $bindable(40), draggable = true }: Props = $props();

	let dragging = $state(false);
	let startX = 0;
	let startY = 0;
	let originX = 0;
	let originY = 0;

	function onPointerDown(e: PointerEvent) {
		if (!draggable) return;
		dragging = true;
		startX = e.clientX;
		startY = e.clientY;
		originX = x;
		originY = y;
		(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
	}
	function onPointerMove(e: PointerEvent) {
		if (!dragging) return;
		x = originX + (e.clientX - startX);
		y = originY + (e.clientY - startY);
	}
	function onPointerUp(e: PointerEvent) {
		dragging = false;
		(e.currentTarget as HTMLElement).releasePointerCapture(e.pointerId);
	}
</script>

<div class="huddle" data-dragging={dragging} style="--x: {x}px; --y: {y}px;">
	<div
		class="header"
		role="toolbar"
		tabindex="0"
		aria-label={name}
		onpointerdown={onPointerDown}
		onpointermove={onPointerMove}
		onpointerup={onPointerUp}
		onpointercancel={onPointerUp}
	>
		<span class="grip" aria-hidden="true">▚▚</span>
		<span class="name">{name}</span>
	</div>
	<div class="body">
		{@render children?.()}
	</div>
</div>

<style>
	.huddle {
		position: absolute;
		left: var(--x);
		top: var(--y);
		min-width: 12rem;
		background: var(--wt-trunk);
		border: 2px solid var(--wt-wish-violet);
		box-shadow:
			inset 1px 1px 0 var(--wt-haze),
			inset -2px -2px 0 var(--wt-void),
			0 0 0 2px var(--wt-void),
			0 10px 40px rgba(0, 0, 0, 0.8);
		font-family: var(--wt-font-mono);
		color: var(--wt-haze);
		user-select: none;
		image-rendering: pixelated;
	}
	.huddle[data-dragging='true'] {
		border-color: var(--wt-fruit-gold);
		box-shadow:
			inset 1px 1px 0 var(--wt-haze),
			inset -2px -2px 0 var(--wt-void),
			0 0 0 2px var(--wt-void),
			0 12px 60px rgba(255, 224, 102, 0.25);
	}
	.header {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 4px 8px;
		background: repeating-linear-gradient(
			90deg,
			var(--wt-branch) 0 4px,
			var(--wt-trunk) 4px 8px
		);
		border-bottom: 2px solid var(--wt-wish-violet);
		cursor: grab;
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.2em;
		color: var(--wt-wish-violet);
		text-shadow: 1px 1px 0 var(--wt-void);
	}
	.huddle[data-dragging='true'] .header {
		cursor: grabbing;
	}
	.grip {
		color: var(--wt-mist);
	}
	.body {
		padding: 8px 10px;
		font-size: 12px;
	}
</style>
