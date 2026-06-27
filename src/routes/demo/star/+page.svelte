<!--
  Demo — Star Tamagotchi, the first character DreamBall.

  The honest end-to-end path the rest of the character system builds on:

    fetch /characters/star-tamagotchi.ball   (a signed ball/1 capsule)
      → verifyBall(bytes)    (Ed25519 + ML-DSA, via dreamball.wasm)
      → parseBall(bytes)     (wasm decodes the CBOR envelope → typed ball)
      → <DreamBallViewer ball lens="avatar" />
          → AvatarLens reads ball.look.asset → loads the glTF → renders it

  Nothing here knows it's a "star" — it knows it's a DreamBall whose look
  slot points at a glTF mesh. Every future character (and the editor that
  authors them) rides this exact path; today Star is just a textured glTF
  inside a signed ball, tomorrow she carries personality / act / memory
  slots and an AI persona, and the same viewer renders the richer ball.
-->
<script lang="ts">
	import { onMount } from 'svelte';
	import { DreamBallViewer, parseBall, verifyBall, type DreamBall } from '$lib/index.js';

	const BALL_URL = '/characters/star-tamagotchi.ball';

	let ball: DreamBall | null = $state(null);
	let status = $state('Fetching capsule…');
	let verify = $state('');
	let error: string | null = $state(null);

	onMount(async () => {
		try {
			const resp = await fetch(BALL_URL);
			if (!resp.ok) throw new Error(`fetch ${BALL_URL} → ${resp.status}`);
			const bytes = new Uint8Array(await resp.arrayBuffer());

			status = 'Verifying signatures (wasm)…';
			const v = await verifyBall(bytes);
			verify = v.ok ? (v.hadEd25519 ? '✓ signature verified' : '✓ parsed (unsigned)') : `✗ verify failed: ${v.reason ?? v.code}`;

			status = 'Decoding capsule (wasm)…';
			ball = (await parseBall(bytes)) as unknown as DreamBall;
			status = 'Rendering…';
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
		}
	});
</script>

<section>
	<h1>★ Star Tamagotchi — first character DreamBall</h1>
	<p>
		A glTF character wrapped in a signed <code>ball/1</code> capsule. The
		<code>dreamball.wasm</code> module verifies and decodes the ball in the
		browser; <code>AvatarLens</code> reads <code>look.asset</code> and loads
		the mesh. Same path for every character to come.
	</p>

	<div class="meta">
		{#if error}
			<span class="pill bad">error</span> <span class="mono">{error}</span>
		{:else if ball}
			<span class="pill ok">{verify}</span>
			<span class="kv"><b>name</b> {ball.name ?? '(unnamed)'}</span>
			<span class="kv"><b>stage</b> {ball.stage ?? '—'}</span>
			<span class="kv mono"><b>identity</b> {(ball.identity ?? '').slice(0, 22)}…</span>
		{:else}
			<span class="pill">{status}</span>
		{/if}
	</div>

	<div class="stage">
		{#if ball}
			<DreamBallViewer {ball} lens="avatar" />
		{:else if !error}
			<p class="hint">{status}</p>
		{/if}
	</div>

	<h2>Why it matters</h2>
	<ul>
		<li>
			The capsule is the source of truth: identity, signatures, and a
			<code>look.asset</code> pointer to the glTF — verified by the same
			wasm in browser, server, and CLI.
		</li>
		<li>
			<code>AvatarLens</code> auto-fits any character mesh (Blender, Meshy,
			…) into the lens frame, so every character renders consistently.
		</li>
		<li>
			This is the seed of "all characters as DreamBalls" + a DreamBall
			editor — add <code>act</code> / <code>memory</code> / persona slots and
			the same viewer renders the richer ball.
		</li>
	</ul>
</section>

<style>
	section {
		max-width: 52rem;
		margin: 0 auto;
	}
	.meta {
		display: flex;
		gap: 1rem;
		align-items: center;
		flex-wrap: wrap;
		font-family: system-ui, sans-serif;
		font-size: 0.85rem;
		margin: 0.5rem 0 1rem;
	}
	.kv b {
		color: #e0b7ff;
		font-weight: 600;
	}
	.mono {
		font-family: ui-monospace, Menlo, monospace;
	}
	.pill {
		display: inline-block;
		padding: 0.1rem 0.55rem;
		border-radius: 999px;
		background: #1a2240;
		color: #aab;
	}
	.pill.ok {
		background: #14331f;
		color: #a6e3a1;
	}
	.pill.bad {
		background: #3a1420;
		color: #f38ba8;
	}
	.hint {
		opacity: 0.6;
		font-size: 0.85rem;
	}
	.stage {
		margin: 1rem 0;
		max-width: 480px;
		background: #0a0e20;
		padding: 1rem;
		border-radius: 1rem;
	}
	h2 {
		margin-top: 2rem;
		color: #e0b7ff;
	}
	code {
		background: #1a2240;
		padding: 0.1rem 0.35rem;
		border-radius: 0.25rem;
		font-family: ui-monospace, Menlo, monospace;
	}
	ul {
		line-height: 1.5;
	}
</style>
