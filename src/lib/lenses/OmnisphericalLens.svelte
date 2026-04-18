<!--
  OmnisphericalLens — renders the three-camera onion-layer grid defined in
  docs/VISION.md §4.4.5. A simplified placeholder: three concentric wire
  spheres with visible pole axes, no real optic-nerve remapping.
-->
<script lang="ts">
	import { Canvas, T } from '@threlte/core';
	import type { DreamBall } from '../generated/types.js';

	interface Props {
		ball: DreamBall;
	}
	let { ball }: Props = $props();

	const grid = $derived(ball['omnispherical-grid']);
	const cameraRings = $derived(grid?.['camera-ring'] ?? []);
	const layerDepth = $derived(grid?.['layer-depth'] ?? 3);
	const palette = $derived(
		ball['ambient-palette'] ?? ['#0b1020', '#1a2240', '#303a6a']
	);
</script>

<div class="omni-wrap" style="--bg:{palette[0]}">
	<Canvas>
		<T.PerspectiveCamera makeDefault position={[0, 0, 6]} fov={60} />
		<T.DirectionalLight position={[3, 5, 2]} intensity={1} />
		<T.AmbientLight intensity={0.35} />
		{#each Array(layerDepth) as _, i (i)}
			{@const radius = cameraRings[i]?.radius ?? (i + 1) * 1.2}
			<T.Mesh>
				<T.SphereGeometry args={[radius, 24, 16]} />
				<T.MeshBasicMaterial
					color={palette[i % palette.length]}
					wireframe
					transparent
					opacity={0.4 - i * 0.08}
				/>
			</T.Mesh>
		{/each}
		<!-- Pole axes -->
		<T.Mesh rotation={[0, 0, 0]}>
			<T.CylinderGeometry args={[0.02, 0.02, 4, 6]} />
			<T.MeshBasicMaterial color="#e0b7ff" />
		</T.Mesh>
	</Canvas>
	<div class="caption">
		depth {layerDepth} · {cameraRings.length} rings · res {grid?.resolution ?? '—'}
	</div>
</div>

<style>
	.omni-wrap {
		position: relative;
		width: 100%;
		aspect-ratio: 4 / 3;
		background: var(--bg);
		border-radius: 1rem;
		overflow: hidden;
	}
	.caption {
		position: absolute;
		left: 1rem;
		bottom: 0.8rem;
		color: #e8ecf8;
		font-family: ui-monospace, Menlo, monospace;
		font-size: 0.8rem;
		opacity: 0.8;
	}
</style>
