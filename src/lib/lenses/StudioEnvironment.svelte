<!--
  StudioEnvironment — file-free image-based lighting for the avatar canvas.

  PBR character meshes (model/gltf-binary with metallic-roughness materials)
  look flat and dark under bare directional lights — they need an environment
  to reflect. Rather than ship an HDRI asset, we generate three's built-in
  RoomEnvironment into a PMREM and set it as scene.environment: soft, neutral
  studio lighting with no external file and no protocol cost. We also pin a
  filmic tone-mapping curve so the result is consistent regardless of the
  Threlte/three default.

  Sits inside <Canvas> (needs the Threlte context). Restores the previous
  environment + tone-mapping on teardown so it composes cleanly.
-->
<script lang="ts">
	import { useThrelte } from '@threlte/core';
	import { onMount } from 'svelte';
	import * as THREE from 'three';
	import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';

	interface Props {
		/** Environment intensity (how strongly IBL lights the scene). */
		intensity?: number;
		/** Tone-mapping exposure. */
		exposure?: number;
		/** Tone mapping curve. ACES filmic by default. */
		toneMapping?: THREE.ToneMapping;
	}
	let { intensity = 1, exposure = 1.05, toneMapping = THREE.ACESFilmicToneMapping }: Props =
		$props();

	const { renderer, scene, invalidate } = useThrelte();

	onMount(() => {
		const prevEnv = scene.environment;
		const prevIntensity = scene.environmentIntensity;
		const prevToneMapping = renderer.toneMapping;
		const prevExposure = renderer.toneMappingExposure;

		const pmrem = new THREE.PMREMGenerator(renderer);
		const envTexture = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;

		scene.environment = envTexture;
		scene.environmentIntensity = intensity;
		renderer.toneMapping = toneMapping;
		renderer.toneMappingExposure = exposure;
		invalidate();

		return () => {
			scene.environment = prevEnv;
			scene.environmentIntensity = prevIntensity;
			renderer.toneMapping = prevToneMapping;
			renderer.toneMappingExposure = prevExposure;
			envTexture.dispose();
			pmrem.dispose();
		};
	});
</script>
