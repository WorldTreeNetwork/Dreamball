<!--
  BloomEffect — additive glow for the avatar canvas via an EffectComposer.

  A star should glow. Threlte renders straight to the screen by default; to add
  post-processing we set autoRender=false and drive our own pipeline on the
  render stage: RenderPass → UnrealBloomPass → OutputPass. The bloom pass picks
  up the brightest parts of the lit mesh (the star's highlights + saturated
  body) and blooms them, while OutputPass applies the renderer's tone mapping +
  colour space exactly once (RenderPass writes a linear HDR target; the final
  conversion happens at OutputPass).

  Sits inside <Canvas>, after the camera. Restores Threlte's auto-render on
  teardown so the lens composes cleanly.
-->
<script lang="ts">
	import { useThrelte, useTask } from '@threlte/core';
	import { onMount } from 'svelte';
	import * as THREE from 'three';
	import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
	import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
	import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
	import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';

	interface Props {
		/** Bloom intensity. */
		strength?: number;
		/** Bloom spread (0–1). */
		radius?: number;
		/** Luminance threshold above which pixels bloom (0–1). */
		threshold?: number;
	}
	let { strength = 0.7, radius = 0.5, threshold = 0.55 }: Props = $props();

	const ctx = useThrelte();
	const { renderer, scene, camera, size, autoRender, renderStage, invalidate } = ctx;

	let composer: EffectComposer | undefined;
	let renderPass: RenderPass | undefined;
	let bloomPass: UnrealBloomPass | undefined;

	onMount(() => {
		const prevAutoRender = autoRender.current;
		autoRender.set(false);

		const { width, height } = size.current;
		const webglRenderer = renderer as unknown as THREE.WebGLRenderer;

		composer = new EffectComposer(webglRenderer);
		composer.setPixelRatio(webglRenderer.getPixelRatio());
		composer.setSize(width, height);

		renderPass = new RenderPass(scene, camera.current);
		composer.addPass(renderPass);

		bloomPass = new UnrealBloomPass(new THREE.Vector2(width, height), strength, radius, threshold);
		composer.addPass(bloomPass);

		composer.addPass(new OutputPass());

		invalidate();

		return () => {
			autoRender.set(prevAutoRender);
			bloomPass?.dispose();
			composer?.dispose();
			composer = renderPass = bloomPass = undefined;
		};
	});

	// Keep the composer + bloom sized to the canvas.
	$effect(() => {
		const { width, height } = $size;
		if (composer) {
			composer.setSize(width, height);
			bloomPass?.setSize(width, height);
			invalidate();
		}
	});

	// Live-tune bloom params.
	$effect(() => {
		if (bloomPass) {
			bloomPass.strength = strength;
			bloomPass.radius = radius;
			bloomPass.threshold = threshold;
			invalidate();
		}
	});

	useTask(
		() => {
			if (!composer || !renderPass || !camera.current) return;
			// Track the active (makeDefault) camera each frame.
			renderPass.camera = camera.current;
			composer.render();
		},
		{ stage: renderStage, autoInvalidate: false }
	);
</script>
