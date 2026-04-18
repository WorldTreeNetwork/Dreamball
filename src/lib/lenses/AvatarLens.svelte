<!--
  AvatarLens — 3D canvas view of the DreamBall's visual aspect.

  For v2 MVP we render a placeholder: a signed-distance-field-shaped
  crystal that hints at the "jelly bean" metaphor. Real mesh/splat
  loading from the `look.asset` URLs comes post-MVP.
-->
<script lang="ts">
	import { Canvas, T } from '@threlte/core';
	import type { DreamBall } from '../generated/types.js';

	interface Props {
		ball: DreamBall;
		/** If the wearer persona is active, the avatar animates from this
		 *  input stream. Typed loosely for now — the real impl will accept
		 *  a MediaStream or a text-through-time source. */
		sourceTrack?: unknown;
	}
	let { ball, sourceTrack }: Props = $props();
	// Touch sourceTrack so the reactive system picks up changes once
	// Wearer-driven animation lands. The value itself is an escape hatch
	// for the Wearer component.
	$effect(() => {
		void sourceTrack;
	});

	const bgColor = $derived(ball.look?.background ?? 'color:#0b1020');
	const colorHex = $derived(
		bgColor.startsWith('color:') ? bgColor.slice(6) : '#0b1020'
	);
</script>

<div class="wrap" style="--bg:{colorHex}">
	<Canvas>
		<T.PerspectiveCamera makeDefault position={[2.5, 1.5, 3.5]} fov={55} />
		<T.DirectionalLight position={[3, 5, 2]} intensity={1.2} />
		<T.AmbientLight intensity={0.4} />
		<T.Mesh position={[0, 0, 0]}>
			<T.IcosahedronGeometry args={[1, 1]} />
			<T.MeshStandardMaterial color="#e0b7ff" metalness={0.2} roughness={0.35} />
		</T.Mesh>
		<T.Mesh position={[0, -1.1, 0]} rotation={[-Math.PI / 2, 0, 0]}>
			<T.CircleGeometry args={[4, 48]} />
			<T.MeshStandardMaterial color={colorHex} />
		</T.Mesh>
	</Canvas>
	<div class="label">{ball.name ?? '(unnamed)'}</div>
</div>

<style>
	.wrap {
		position: relative;
		width: 100%;
		aspect-ratio: 1;
		background: var(--bg);
		border-radius: 1rem;
		overflow: hidden;
	}
	.label {
		position: absolute;
		left: 1rem;
		bottom: 0.8rem;
		color: #e8ecf8;
		font-family: system-ui, sans-serif;
		opacity: 0.8;
	}
</style>
