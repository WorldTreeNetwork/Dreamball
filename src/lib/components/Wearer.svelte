<!--
  Wearer — drives an Avatar DreamBall's visual representation from the
  wearer's live input (webcam stream, typed text, etc.). For Demo D
  scenario 3: wearer view shows the full agent panel; observer view
  shows only the avatar surface.

  This is a lean placeholder for v2 MVP: we render the AvatarLens and
  pass the `sourceTrack` through for downstream consumers to pick up.
  Face-tracking + rig animation is a follow-up; for now we animate a
  simple scale pulse bound to input presence.
-->
<script lang="ts">
	import type { DreamBall } from '../generated/types.js';
	import AvatarLens from '../lenses/AvatarLens.svelte';

	interface Props {
		ball: DreamBall;
		sourceTrack?: MediaStream | null;
		/** Optional synthesized input for environments without a webcam. */
		syntheticText?: string;
	}
	let { ball, sourceTrack = null, syntheticText = '' }: Props = $props();

	let pulse = $state(0);
	let intervalHandle: ReturnType<typeof setInterval> | null = null;

	$effect(() => {
		if (intervalHandle) clearInterval(intervalHandle);
		// A simple animating scalar the AvatarLens can read via $effect of
		// sourceTrack. Real rigging comes later.
		intervalHandle = setInterval(() => {
			pulse = (pulse + 1) % 60;
		}, 100);
		return () => {
			if (intervalHandle) clearInterval(intervalHandle);
		};
	});
	$effect(() => {
		void sourceTrack;
		void syntheticText;
		void pulse;
	});
</script>

<section class="wearer">
	<header>
		<h3>Wearing: {ball.name ?? '(unnamed)'}</h3>
		<p class="sub">
			{sourceTrack ? 'live stream attached' : syntheticText ? 'synthetic input' : 'no input — idle pulse'}
		</p>
	</header>
	<AvatarLens {ball} {sourceTrack} />
</section>

<style>
	.wearer {
		display: grid;
		gap: 0.75rem;
		color: #e8ecf8;
		font-family: system-ui, sans-serif;
	}
	header h3 {
		margin: 0;
		font-size: 1rem;
	}
	.sub {
		margin: 0;
		opacity: 0.6;
		font-size: 0.8rem;
	}
</style>
