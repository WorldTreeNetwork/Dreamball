<script lang="ts">
	import { onMount } from 'svelte';
	import { parseBall, verifyBall } from '$lib/wasm/loader.js';
	import type { DreamBall } from '$lib/generated/types.js';
	import StarStage from '$lib/animation/StarStage.svelte';
	let ball: DreamBall | null = $state(null);
	let modelUrl = $state('');
	let error = $state('');
	onMount(() => {
		const abort = new AbortController();
		(async () => {
			const response = await fetch('/characters/star-tamagotchi.ball', { signal: abort.signal });
			if (!response.ok) throw new Error(`Capsule fetch failed (${response.status})`);
			const bytes = new Uint8Array(await response.arrayBuffer());
			const verification = await verifyBall(bytes);
			if (!verification.ok || !verification.hadEd25519)
				throw new Error('Star’s capsule signature could not be verified.');
			const parsed = (await parseBall(bytes)) as unknown as DreamBall;
			const mesh = parsed.look?.asset?.find((asset) => asset['media-type'] === 'model/gltf-binary');
			if (!mesh?.url?.[0]) throw new Error('Star’s capsule has no GLB asset.');
			if (!abort.signal.aborted) {
				modelUrl = mesh.url[0];
				ball = parsed;
			}
		})().catch((e: unknown) => {
			if (!abort.signal.aborted) error = e instanceof Error ? e.message : String(e);
		});
		return () => abort.abort();
	});
</script>

<svelte:head
	><title>Star — a little company · Dreamball</title><meta
		name="description"
		content="A tiny stage for Star. Float, pause, and say hello."
	/></svelte:head
>
<section>
	<header>
		<div>
			<p class="eyebrow">DREAMBALL / CHARACTER STUDY</p>
			<h1>A little company.</h1>
		</div>
		<p class="intro">Meet Star.<br />A small presence with a little joy to share.</p>
	</header>
	{#if error}<p role="alert">{error}</p>
	{:else if ball}<StarStage url={modelUrl} />
	{:else}<div class="loading" role="status">Opening Star’s Dreamball…</div>{/if}
	<footer>
		<span>Star / 001</span><span>{ball ? 'Signed character capsule' : 'Dreamball'}</span>
	</footer>
</section>

<style>
	section {
		max-width: 850px;
		margin: 2rem auto;
		color: #e1e9df;
	}
	header {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		margin-bottom: 1.75rem;
	}
	.eyebrow {
		font-size: 0.65rem;
		letter-spacing: 0.17em;
		color: #bace92;
	}
	h1 {
		font-family: 'Iowan Old Style', 'Palatino Linotype', 'Book Antiqua', Palatino, serif;
		font-weight: 400;
		font-size: clamp(2.8rem, 7vw, 4.7rem);
		letter-spacing: -0.055em;
		margin: 0.5rem 0;
		line-height: 1.05;
	}
	.intro {
		color: #a8b7b1;
		line-height: 1.6;
		font-size: 1rem;
	}
	footer {
		display: flex;
		justify-content: space-between;
		gap: 1rem;
		padding-top: 1.5rem;
		margin-top: 1.5rem;
		border-top: 1px solid #34443e;
		font-size: 0.75rem;
		color: #a8b7b1;
	}
	.loading {
		min-height: 360px;
		display: grid;
		place-items: center;
	}
	@media (min-width: 700px) {
		header {
			flex-direction: row;
			align-items: flex-end;
			justify-content: space-between;
		}
	}
</style>
