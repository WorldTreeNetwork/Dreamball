<!--
  Demo D Scenario 2 — Unlock a sealed Relic.
-->
<script lang="ts">
	import { SealedRelic, MockBackend, mockBall, type DreamBall } from '$lib/index.js';

	const backend = new MockBackend();
	const relic: DreamBall = mockBall('relic', {
		name: 'The Mirror Fragment',
		'reveal-hint': 'Look behind the mirror — a hummingbird waits.'
	});

	async function onUnlock() {
		// TODO-CRYPTO: real unlock goes through the Guild keyspace. Mock
		// returns a synthetic inner DreamBall.
		return backend.unlockRelic(relic, new Uint8Array(32));
	}
</script>

<section>
	<h1>Scenario 2 — Unlock a Relic</h1>
	<p class="mocked">⚠ crypto mocked: the "unlock" actually just reads the attachment plaintext.</p>
	<p>
		A sealed Relic is published publicly. Only Guild members holding the
		keyspace credential can open it. On unlock, the renderer animates the
		dragon peeling away and swaps to show the inner DreamBall in the
		omnispherical lens.
	</p>

	<div class="stage">
		<SealedRelic {relic} {onUnlock} />
	</div>
</section>

<style>
	.mocked {
		background: #3a2a10;
		color: #ffd0a0;
		padding: 0.5rem 0.75rem;
		border-radius: 0.5rem;
		font-size: 0.85rem;
	}
	.stage {
		margin-top: 2rem;
		background: #0a0e20;
		padding: 2rem;
		border-radius: 1rem;
	}
</style>
