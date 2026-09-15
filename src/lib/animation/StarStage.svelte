<script lang="ts">
	import { onMount } from 'svelte';
	import { createStageRenderer, type StageState } from './stage-renderer.js';
	let { url }: { url: string } = $props();
	let canvas: HTMLCanvasElement;
	let controller: ReturnType<typeof createStageRenderer> | undefined;
	let playback: StageState = $state({
		time: 0,
		playing: false,
		reacting: false,
		ready: false,
		reduced: false,
		frames: 0
	});
	let error = $state('');
	let greeting = $state(false);
	onMount(() => {
		try {
			controller = createStageRenderer(
				canvas,
				url,
				(next) => (playback = next),
				(message) => (error = message)
			);
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
		}
		return () => controller?.dispose();
	});
	function touch() {
		greeting = true;
		controller?.touch();
	}
</script>

<div
	class="stage"
	data-ready={playback.ready}
	data-frames={playback.frames}
	data-reacting={playback.reacting}
>
	<div class="caption">
		<span>01 / A LITTLE COMPANY</span><span
			>{playback.reduced ? 'Still mode' : playback.playing ? 'In motion' : 'Paused'}</span
		>
	</div>
	<button
		class="scene"
		onclick={touch}
		disabled={!playback.ready || !!error}
		aria-label="Say hello to Star"
	>
		<canvas bind:this={canvas} aria-label="Star floating on a softly lit stage"></canvas>
	</button>
	<div class="message" aria-live="polite">
		{#if error}<p role="alert">Star couldn’t appear. {error}</p>
		{:else if !playback.ready}<p>Bringing Star here…</p>
		{:else if playback.reacting}<p>A little joy, just for you.</p>
		{:else if greeting}<p>Star is happy you’re here.</p>
		{:else}<p>Touch Star. Say hello.</p>{/if}
	</div>
</div>
<div class="transport">
	<button
		onclick={() => controller?.toggle()}
		disabled={!playback.ready || playback.reduced || !!error}
		aria-label={playback.playing ? 'Pause animation' : 'Play animation'}
		>{playback.playing ? 'Pause' : 'Play'}</button
	>
	<button class="hello" onclick={touch} disabled={!playback.ready || playback.reacting || !!error}
		>Say hello ↗</button
	>
</div>
{#if playback.reduced}<p class="note">Reduced motion is on. Star answers without moving.</p>{/if}

<style>
	.stage {
		position: relative;
		border-radius: 1.5rem;
		overflow: hidden;
		background: radial-gradient(ellipse at 50% 40%, #f4eee0, #d8e2de 75%);
		color: #29423d;
	}
	.caption {
		position: absolute;
		top: 1.5rem;
		left: 1.5rem;
		right: 1.5rem;
		display: flex;
		justify-content: space-between;
		gap: 1rem;
		font-size: 0.65rem;
		letter-spacing: 0.13em;
		pointer-events: none;
	}
	.scene {
		display: block;
		width: 100%;
		border: 0;
		padding: 0;
		background: transparent;
		cursor: pointer;
	}
	canvas {
		display: block;
		width: 100%;
		height: clamp(340px, 55vw, 530px);
	}
	.scene:focus-visible {
		outline: 3px solid #286852;
		outline-offset: -5px;
	}
	.message {
		position: absolute;
		bottom: 0.75rem;
		left: 1rem;
		right: 1rem;
		text-align: center;
		pointer-events: none;
	}
	.message p {
		font-size: 1rem;
	}
	.transport {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 0.75rem;
		margin-top: 1rem;
	}
	.transport button {
		min-height: 44px;
		padding: 0.6rem 1rem;
		border: 1px solid #73847a;
		border-radius: 2rem;
		background: transparent;
		color: inherit;
		font: inherit;
		cursor: pointer;
	}
	.transport .hello {
		background: #dcedaa;
		color: #213922;
		border-color: #dcedaa;
		margin-left: auto;
	}
	button:disabled {
		opacity: 0.5;
		cursor: default;
	}
	.note {
		font-size: 0.85rem;
		opacity: 0.8;
	}
	@media (prefers-color-scheme: dark) {
		.stage {
			background: radial-gradient(ellipse at 50% 40%, #34454b, #172a30 75%);
			color: #dfebe1;
		}
	}
	:global([data-theme='dark']) .stage {
		background: radial-gradient(ellipse at 50% 40%, #34454b, #172a30 75%);
		color: #dfebe1;
	}
</style>
