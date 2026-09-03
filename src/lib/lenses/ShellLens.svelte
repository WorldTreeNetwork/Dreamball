<!--
  ShellLens — 3D container for a DreamBall. Always loads the canonical
  shell mesh (Star Tamagotchi), not the inner look slot. AvatarLens still
  owns the character/look path. Studio lighting, orbit, bloom, and the
  crystal placeholder match AvatarLens so the two sit in the same frame.
-->
<script lang="ts">
	import { Canvas, T } from '@threlte/core';
	import { OrbitControls } from '@threlte/extras';
	import type { DreamBall } from '../generated/types.js';
	import AvatarModel from './AvatarModel.svelte';
	import StudioEnvironment from './StudioEnvironment.svelte';
	import BloomEffect from './BloomEffect.svelte';
	import { SHELL_MESH_URL } from './shell-mesh.js';

	interface Props {
		ball?: DreamBall | null;
		/** Test/story seam. Defaults to the canonical shell glTF. */
		meshUrl?: string;
	}
	let { ball = null, meshUrl = SHELL_MESH_URL }: Props = $props();

	const bgColor = $derived(ball?.look?.background ?? 'color:#0b1020');
	const colorHex = $derived(bgColor.startsWith('color:') ? bgColor.slice(6) : '#0b1020');

	let modelReady = $state(false);
	let modelError: string | null = $state(null);
	$effect(() => {
		void meshUrl;
		modelReady = false;
		modelError = null;
	});

	const showPlaceholder = $derived(!meshUrl || !!modelError);
</script>

<div
	class="wrap"
	style="--bg:{colorHex}"
	data-lens="shell"
	data-has-mesh={meshUrl ? 'true' : 'false'}
	data-model-ready={modelReady ? 'true' : 'false'}
	data-model-error={modelError ? 'true' : 'false'}
>
	<Canvas>
		<T.PerspectiveCamera makeDefault position={[2.5, 1.5, 3.5]} fov={55}>
			<OrbitControls
				enableDamping
				dampingFactor={0.08}
				autoRotate={!!meshUrl && !modelError}
				autoRotateSpeed={1.0}
				target={[0, 0, 0]}
			/>
		</T.PerspectiveCamera>
		<StudioEnvironment intensity={1.1} exposure={1.1} />
		<BloomEffect strength={0.32} radius={0.35} threshold={0.9} />
		<T.DirectionalLight position={[3, 5, 4]} intensity={1.6} />
		<T.DirectionalLight position={[-4, 2, -3]} intensity={0.7} color="#a8c4ff" />
		<T.DirectionalLight position={[0, 3, -5]} intensity={0.8} color="#ffd9f0" />
		<T.HemisphereLight intensity={0.5} groundColor="#1a0a2e" />
		<T.AmbientLight intensity={0.25} />

		{#if meshUrl}
			{#key meshUrl}
				<AvatarModel
					url={meshUrl}
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
	<div class="label">{ball?.name ?? 'DreamBall'}</div>
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
