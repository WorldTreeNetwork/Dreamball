<!--
  Demo — DreamBall shell lens. Canonical container mesh (Star Tamagotchi),
  not the inner look.asset path used by /demo/star.
-->
<script lang="ts">
	import { DreamBallViewer, mockBall } from '$lib/index.js';

	const ball = mockBall('avatar', { name: 'Star Tamagotchi' });
</script>

<section>
	<h1>DreamBall shell</h1>
	<p>
		The container mesh is always Star Tamagotchi
		(<code>/characters/star-tamagotchi.glb</code>), framed by AvatarModel
		auto-fit. Inner contents and bucket/filename fetch land in later
		changes. The character-from-capsule path is still
		<a href="/demo/star">/demo/star</a> with <code>lens="avatar"</code>.
	</p>
	<div class="stage">
		<DreamBallViewer {ball} lens="shell" />
	</div>
</section>

<style>
	section {
		max-width: 52rem;
		margin: 0 auto;
	}
	.stage {
		max-width: 28rem;
		margin: 1.5rem 0;
	}
	code {
		font-family: ui-monospace, Menlo, monospace;
		font-size: 0.9em;
	}
	a {
		color: #e0b7ff;
	}
</style>
