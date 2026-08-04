<!--
  AvatarLens — 3D canvas view of the DreamBall's visual aspect.

  When the ball's `look.asset` carries a mesh (model/gltf-binary or
  model/gltf+json), we load and render it via AvatarModel. Until it's
  ready — or when the ball has no mesh asset at all — we show a
  signed-distance-ish crystal placeholder that hints at the "jelly bean"
  metaphor, so the lens always renders something and never blocks on the
  network.

  Splat assets are NOT handled here: DreamBallViewer routes a ball whose
  primary look.asset is a gaussian splat to SplatLens instead (see
  splat/media-types.ts + DreamBallViewer's effectiveLens). This lens is
  the mesh/glTF path — the one every "character DreamBall" (a static or
  rigged character mesh wrapped in a signed ball) renders through.
-->
<script lang="ts">
	import { Canvas, T } from '@threlte/core';
	import { OrbitControls } from '@threlte/extras';
	import type { Asset, DreamBall } from '../generated/types.js';
	import { isSplatAsset } from '../splat/media-types.js';
	import AvatarModel from './AvatarModel.svelte';
	import StudioEnvironment from './StudioEnvironment.svelte';
	import BloomEffect from './BloomEffect.svelte';

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

	// `ball?.` (not just `ball.look?.`) is deliberate: these deriveds can be
	// re-evaluated once more during teardown, after the prop has been torn down
	// but before the reaction is disposed. Storybook's browser runner surfaced
	// that as an unhandled "Cannot read properties of undefined (reading 'look')"
	// which failed the whole vitest run even though every assertion passed.
	// During normal rendering `ball` is required and always present.
	const bgColor = $derived(ball?.look?.background ?? 'color:#0b1020');
	const colorHex = $derived(
		bgColor.startsWith('color:') ? bgColor.slice(6) : '#0b1020'
	);

	// Pick the first look.asset that is a renderable mesh: an explicit glTF
	// media-type, or (when media-type is absent) a .glb/.gltf URL. Splats are
	// skipped — they belong to SplatLens and the viewer routes them away.
	function isMeshAsset(a: Asset): boolean {
		const mt = a['media-type'];
		if (isSplatAsset(mt)) return false;
		if (mt === 'model/gltf-binary' || mt === 'model/gltf+json') return true;
		const url = a.url?.[0]?.toLowerCase() ?? '';
		return !mt && (url.endsWith('.glb') || url.endsWith('.gltf'));
	}
	const meshAsset = $derived(ball?.look?.asset?.find(isMeshAsset));
	const modelUrl = $derived(meshAsset?.url?.[0]);

	// Track mesh load state for the fallback decision + e2e signals.
	let modelReady = $state(false);
	let modelError: string | null = $state(null);
	// Reset readiness whenever the target URL changes.
	$effect(() => {
		void modelUrl;
		modelReady = false;
		modelError = null;
	});

	// Show the crystal placeholder only when there's genuinely nothing to load
	// (no mesh asset) or the load failed — NOT during a normal load, so a fast
	// mesh never flashes a big crystal before appearing.
	const showPlaceholder = $derived(!modelUrl || !!modelError);
</script>

<div
	class="wrap"
	style="--bg:{colorHex}"
	data-has-mesh={modelUrl ? 'true' : 'false'}
	data-model-ready={modelReady ? 'true' : 'false'}
	data-model-error={modelError ? 'true' : 'false'}
>
	<Canvas>
		<T.PerspectiveCamera makeDefault position={[2.5, 1.5, 3.5]} fov={55}>
			<OrbitControls
				enableDamping
				dampingFactor={0.08}
				autoRotate={!!modelUrl}
				autoRotateSpeed={1.0}
				target={[0, 0, 0]}
			/>
		</T.PerspectiveCamera>
		<!-- Image-based studio lighting so PBR meshes catch light + reflect. -->
		<StudioEnvironment intensity={1.1} exposure={1.1} />
		<!-- Additive bloom so the star glows. Takes over the render loop.
		     Higher threshold + modest strength = a glow concentrated on the
		     bright highlights/edges, not a full-frame haze. -->
		<BloomEffect strength={0.32} radius={0.35} threshold={0.9} />
		<!-- Three-point key/fill/rim on top of the IBL for shape + a soft edge. -->
		<T.DirectionalLight position={[3, 5, 4]} intensity={1.6} />
		<T.DirectionalLight position={[-4, 2, -3]} intensity={0.7} color="#a8c4ff" />
		<T.DirectionalLight position={[0, 3, -5]} intensity={0.8} color="#ffd9f0" />
		<T.HemisphereLight intensity={0.5} groundColor="#1a0a2e" />
		<T.AmbientLight intensity={0.25} />

		{#if modelUrl}
			{#key modelUrl}
				<AvatarModel
					url={modelUrl}
					fit={2}
					onready={() => (modelReady = true)}
					onerror={(m) => (modelError = m)}
				/>
			{/key}
		{/if}

		{#if showPlaceholder}
			<T.Mesh position={[0, 0, 0]}>
				<T.IcosahedronGeometry args={[1, 1]} />
				<T.MeshStandardMaterial color="#e0b7ff" metalness={0.2} roughness={0.35} />
			</T.Mesh>
		{/if}

		<T.Mesh position={[0, -1.1, 0]} rotation={[-Math.PI / 2, 0, 0]}>
			<T.CircleGeometry args={[4, 48]} />
			<T.MeshStandardMaterial color={colorHex} metalness={0.0} roughness={0.8} />
		</T.Mesh>
	</Canvas>
	<!-- ball?. for the same teardown reason as the deriveds above. -->
	<div class="label">{ball?.name ?? '(unnamed)'}</div>
	{#if modelError}
		<div class="err" title={modelError}>mesh failed to load — showing placeholder</div>
	{/if}
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
	.err {
		position: absolute;
		right: 0.8rem;
		bottom: 0.8rem;
		color: #f8b4c0;
		font-family: ui-monospace, Menlo, monospace;
		font-size: 0.7rem;
		opacity: 0.85;
	}
</style>
