<!--
  AvatarModel — loads a glTF/GLB mesh from a URL and auto-fits it into the
  lens's unit frame.

  Split out of AvatarLens so the loader hook (`useGltf`) gets a clean
  component lifecycle keyed on `url`: when the DreamBall's look.asset
  changes, the parent re-mounts this with the new URL and the previous
  graph is disposed. AvatarLens owns the camera/lights/fallback; this
  component owns "turn a URL into a centred, sensibly-scaled object."

  Auto-fit (rather than trusting the author's export scale) is deliberate:
  characters come from many DCC tools (Blender, Meshy, …) with wildly
  different unit scales and origins. The lens guarantees every character
  DreamBall lands centred and ~`fit` units tall, so the shared camera
  frames them all. The GLB's own materials/animations are untouched.

  Textures: three's GLTFLoader decodes EXT_texture_webp natively, so the
  webp-compressed character GLBs render without a custom decoder. No Draco
  loader is wired here — add `useDraco()` and pass `dracoLoader` if/when a
  character ships Draco-compressed geometry.
-->
<script lang="ts">
	import { T } from '@threlte/core';
	import { useGltf } from '@threlte/extras';
	import { untrack } from 'svelte';
	import * as THREE from 'three';

	interface Props {
		/** Absolute or site-relative URL to a .glb / .gltf. */
		url: string;
		/** Target size (largest bounding-box dimension) in world units. */
		fit?: number;
		/** Fired once the mesh is loaded, fitted, and ready to display. */
		onready?: () => void;
		/** Fired if the load fails. */
		onerror?: (message: string) => void;
	}
	let { url, fit = 2, onready, onerror }: Props = $props();

	// Capture the URL once: the parent re-mounts this component (keyed on the
	// look.asset URL) when the model changes, so a one-shot load is correct and
	// we don't want useGltf to re-fire on unrelated reactive reads.
	const gltf = useGltf(untrack(() => url));

	// The fitted object we actually mount. Built once the gltf resolves:
	// recentre on the origin and uniformly scale so the tallest axis == `fit`,
	// then lift so the model's base sits on y = 0 (it "stands on the floor").
	let fitted: THREE.Group | undefined = $state();

	$effect(() => {
		const loaded = $gltf;
		if (!loaded?.scene) return;
		const scene = loaded.scene;
		const box = new THREE.Box3().setFromObject(scene);
		const size = box.getSize(new THREE.Vector3());
		const center = box.getCenter(new THREE.Vector3());
		const maxDim = Math.max(size.x, size.y, size.z) || 1;
		const scale = fit / maxDim;

		const group = new THREE.Group();
		scene.position.sub(center);
		group.add(scene);
		group.scale.setScalar(scale);
		group.position.y = (size.y / 2) * scale;
		fitted = group;
		onready?.();
	});

	// useGltf returns an AsyncWritable (also a thenable) — surface load failures
	// so the parent can fall back to the placeholder instead of hanging.
	$effect(() => {
		let cancelled = false;
		Promise.resolve(gltf).catch((e: unknown) => {
			if (!cancelled) onerror?.(e instanceof Error ? e.message : String(e));
		});
		return () => {
			cancelled = true;
		};
	});
</script>

{#if fitted}
	<T is={fitted} />
{/if}
