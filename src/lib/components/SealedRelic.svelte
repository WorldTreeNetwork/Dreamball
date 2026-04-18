<!--
  SealedRelic — shows a sealed Relic card and plays a reveal animation
  when the unlock handler resolves to an inner DreamBall.

  Demo D scenario 2: user clicks "Unlock", the handler calls the
  backend's unlockRelic with a Guild key, we animate the dragon peeling
  open, and then swap to showing the inner DreamBall in the
  omnispherical lens.
-->
<script lang="ts">
	import type { DreamBall } from '../generated/types.js';
	import ThumbnailLens from '../lenses/ThumbnailLens.svelte';
	import OmnisphericalLens from '../lenses/OmnisphericalLens.svelte';

	interface Props {
		relic: DreamBall;
		onUnlock?: () => Promise<DreamBall>;
	}
	let { relic, onUnlock }: Props = $props();

	type RevealState =
		| { phase: 'sealed' }
		| { phase: 'opening' }
		| { phase: 'opened'; inner: DreamBall };
	let reveal: RevealState = $state({ phase: 'sealed' });
	let error: string | null = $state(null);

	async function unlock() {
		if (!onUnlock) return;
		reveal = { phase: 'opening' };
		error = null;
		try {
			const inner = await onUnlock();
			// Keep the animation visible for a beat before swapping.
			await new Promise((r) => setTimeout(r, 1200));
			reveal = { phase: 'opened', inner };
		} catch (e) {
			error = (e as Error).message;
			reveal = { phase: 'sealed' };
		}
	}
</script>

<section class="relic">
	{#if reveal.phase === 'sealed'}
		<div class="sealed">
			<ThumbnailLens ball={relic} />
			<p class="hint">{relic['reveal-hint'] ?? 'Sealed until the right key is found.'}</p>
			<button class="unlock-btn" type="button" onclick={unlock} disabled={!onUnlock}>
				Unlock with Guild Key
			</button>
			{#if error}
				<p class="err">{error}</p>
			{/if}
		</div>
	{:else if reveal.phase === 'opening'}
		<div class="opening">
			<div class="shell" aria-hidden="true"></div>
			<p>Peeling the seal…</p>
		</div>
	{:else if reveal.phase === 'opened'}
		<div class="opened">
			<OmnisphericalLens ball={reveal.inner} />
			<p class="revealed">Revealed: <strong>{reveal.inner.name ?? '(inner dreamball)'}</strong></p>
		</div>
	{/if}
</section>

<style>
	.relic {
		display: grid;
		gap: 1rem;
		padding: 1rem;
	}
	.sealed {
		display: grid;
		gap: 0.8rem;
		justify-items: center;
	}
	.hint {
		font-family: system-ui, sans-serif;
		opacity: 0.7;
		font-style: italic;
		max-width: 24rem;
		text-align: center;
	}
	.unlock-btn {
		background: linear-gradient(90deg, #e0b7ff, #ffd0a0);
		border: none;
		padding: 0.7rem 1.2rem;
		border-radius: 2rem;
		font-weight: 600;
		cursor: pointer;
	}
	.unlock-btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}
	.opening {
		display: grid;
		gap: 1rem;
		justify-items: center;
		font-family: system-ui, sans-serif;
	}
	.shell {
		width: 10rem;
		height: 10rem;
		border-radius: 50%;
		background: radial-gradient(circle at 35% 30%, #ffd0a0, #e0b7ff 60%, #402060 100%);
		animation: peel 1.2s ease-in-out forwards;
	}
	@keyframes peel {
		0% {
			transform: scale(1) rotate(0deg);
			opacity: 1;
		}
		70% {
			transform: scale(1.15) rotate(25deg);
			opacity: 0.85;
		}
		100% {
			transform: scale(1.6) rotate(45deg);
			opacity: 0;
		}
	}
	.opened {
		display: grid;
		gap: 1rem;
	}
	.revealed {
		text-align: center;
		opacity: 0.9;
	}
	.err {
		color: #f66;
		font-family: system-ui, sans-serif;
	}
</style>
