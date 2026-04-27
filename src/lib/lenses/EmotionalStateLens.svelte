<!--
  EmotionalStateLens — radial intensity plot of each `emotional-register`
  axis. SVG; simple but expressive.
-->
<script lang="ts">
	import type { DreamBall } from '../generated/types.js';

	interface Props {
		ball: DreamBall;
	}
	let { ball }: Props = $props();

	const axes = $derived(ball['emotional-register']?.axes ?? []);
	const size = 220;
	const center = size / 2;
	const ringRadius = 80;
	// Labels sit at `ringRadius + labelPad` from center; the viewBox expands by
	// that same amount plus a text-width allowance so "arousal 0.40"-class
	// labels on the extreme left/right can't clip against the canvas edge.
	const labelPad = 20;
	const labelMargin = 44;
</script>

<div class="es-wrap">
	{#if axes.length === 0}
		<p class="empty">No emotional register on this DreamBall.</p>
	{:else}
		<svg
			viewBox={`${-labelMargin} ${-labelPad} ${size + labelMargin * 2} ${size + labelPad * 2}`}
			xmlns="http://www.w3.org/2000/svg"
		>
			<circle cx={center} cy={center} r={ringRadius} stroke="#333" fill="none" />
			<circle cx={center} cy={center} r={ringRadius / 2} stroke="#222" fill="none" />
			{#each axes as axis, i (axis.name)}
				{@const angle = (i / axes.length) * Math.PI * 2 - Math.PI / 2}
				{@const normalized = (axis.value - (axis.min ?? 0)) / ((axis.max ?? 1) - (axis.min ?? 0))}
				{@const r = ringRadius * normalized}
				{@const x = center + r * Math.cos(angle)}
				{@const y = center + r * Math.sin(angle)}
				{@const labelX = center + (ringRadius + labelPad) * Math.cos(angle)}
				{@const labelY = center + (ringRadius + labelPad) * Math.sin(angle)}
				{@const cosA = Math.cos(angle)}
				{@const sinA = Math.sin(angle)}
				{@const anchor = cosA > 0.3 ? 'start' : cosA < -0.3 ? 'end' : 'middle'}
				{@const baseline = sinA > 0.3 ? 'hanging' : sinA < -0.3 ? 'auto' : 'middle'}
				<line x1={center} y1={center} x2={x} y2={y} stroke="#e0b7ff" stroke-width="2" />
				<circle cx={x} cy={y} r="4" fill="#e0b7ff" />
				<text
					x={labelX}
					y={labelY}
					fill="#e8ecf8"
					font-size="10"
					text-anchor={anchor}
					dominant-baseline={baseline}
				>
					{axis.name} {axis.value.toFixed(2)}
				</text>
			{/each}
		</svg>
	{/if}
</div>

<style>
	.es-wrap {
		background: #0b1020;
		border-radius: 1rem;
		padding: 0.5rem;
		max-width: 360px;
	}
	.empty {
		padding: 2rem;
		text-align: center;
		color: #e8ecf8;
		opacity: 0.6;
	}
	svg {
		width: 100%;
		height: auto;
		display: block;
	}
</style>
