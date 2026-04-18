<script lang="ts">
	import { DreamBallCard, MockBackend, mockBall } from '$lib/index.js';

	const backend = new MockBackend();
	const gallery = [
		mockBall('avatar'),
		mockBall('agent'),
		mockBall('tool'),
		mockBall('relic'),
		mockBall('field'),
		mockBall('guild')
	];
	void backend;
</script>

<main>
	<header>
		<h1>DreamBall</h1>
		<p>Six MTG-style types, one protocol, one renderer.</p>
	</header>

	<section class="demos">
		<h2>Demo D</h2>
		<ul>
			<li><a href="/demo/transmission">Scenario 1 — Transmission</a></li>
			<li><a href="/demo/unlock">Scenario 2 — Unlock a Relic</a></li>
			<li><a href="/demo/wearer">Scenario 3 — Wearer + Observer</a></li>
			<li><a href="/demo/splat">Bonus — Gaussian Splat Lens</a></li>
		</ul>
	</section>

	<section class="gallery">
		<h2>Gallery — one of each type</h2>
		<div class="grid">
			{#each gallery as ball (ball.identity)}
				<DreamBallCard {ball} />
			{/each}
		</div>
	</section>
</main>

<style>
	main {
		max-width: 56rem;
		margin: 2rem auto;
		padding: 0 1.5rem;
		font-family: system-ui, sans-serif;
		color: #e8ecf8;
		background: #050714;
		min-height: 100vh;
	}
	header h1 {
		font-size: 2.5rem;
		margin: 0.5rem 0 0.2rem;
	}
	header p {
		opacity: 0.7;
		margin: 0 0 2rem;
	}
	.demos ul {
		list-style: none;
		padding: 0;
		display: grid;
		gap: 0.5rem;
	}
	.demos a {
		color: #e0b7ff;
		text-decoration: none;
		padding: 0.75rem 1rem;
		background: #0f1430;
		border-radius: 0.5rem;
		display: block;
	}
	.demos a:hover {
		background: #1a2240;
	}
	.gallery {
		margin-top: 3rem;
	}
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
		gap: 1rem;
	}
</style>
