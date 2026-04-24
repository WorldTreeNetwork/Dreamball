<!--
  Deep-link handler for `jelly palace open`.

  Route: /demo/palace/<fp>

  Accepts the palace Blake3 fingerprint from the URL, displays it, and
  reserves the centre slot for Epic 5's PalaceLens (omnispherical renderer).

  Scope: Story 3.5 — placeholder only.  No 3D render here (Epic 5 scope).
  The page must return HTTP 200 so `palace_open.zig`'s reachability poll succeeds.
-->
<script lang="ts">
	import { page } from '$app/stores';

	const fp = $derived($page.params.fp ?? '');
</script>

<svelte:head>
	<title>Palace {fp.slice(0, 8)}… — Dreamball</title>
</svelte:head>

<section>
	<h1>Memory Palace</h1>

	<div class="fp-display">
		<span class="label">Palace fingerprint</span>
		<code class="fp">{fp}</code>
	</div>

	<div class="lens-placeholder" aria-label="PalaceLens placeholder">
		<p class="coming-soon">
			Omnispherical Palace Lens
			<br />
			<span class="note">3D render arrives in Epic 5 (PalaceLens)</span>
		</p>
	</div>

	<p class="hint">
		Opened via <code>jelly palace open</code>. The palace fingerprint above
		identifies which palace bundle is loaded. Once Epic 5 ships, this slot
		will render the full omnispherical room graph.
	</p>
</section>

<style>
	section {
		max-width: 52rem;
		margin: 0 auto;
	}

	h1 {
		color: #e0b7ff;
		margin-bottom: 1.5rem;
	}

	.fp-display {
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
		margin-bottom: 2rem;
	}

	.label {
		font-size: 0.8rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		opacity: 0.6;
	}

	.fp {
		font-family: ui-monospace, Menlo, 'Cascadia Code', monospace;
		font-size: 0.85rem;
		background: #1a2240;
		padding: 0.5rem 0.75rem;
		border-radius: 0.4rem;
		word-break: break-all;
		color: #c8f0ff;
	}

	.lens-placeholder {
		min-height: 18rem;
		border: 2px dashed #3a4060;
		border-radius: 1rem;
		display: flex;
		align-items: center;
		justify-content: center;
		background: #0d1228;
		margin-bottom: 1.5rem;
	}

	.coming-soon {
		text-align: center;
		color: #8090c0;
		font-size: 1.1rem;
		line-height: 1.8;
	}

	.note {
		font-size: 0.8rem;
		opacity: 0.6;
	}

	.hint {
		font-size: 0.85rem;
		opacity: 0.55;
		line-height: 1.6;
	}
</style>
