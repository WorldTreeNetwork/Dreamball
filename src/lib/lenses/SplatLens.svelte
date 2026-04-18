<!--
  SplatLens — Gaussian splat renderer.

  When a DreamBall's `look.asset[0]` carries a splat media-type, the
  DreamBallViewer routes here instead of AvatarLens. We use PlayCanvas's
  native GSplat engine (WebGPU primary, WebGL2 fallback) because at the
  time of v2 MVP PlayCanvas is the most production-ready splat renderer
  on the web — it understands `.sog` (ordered, streamable) + compressed
  `.ply` out of the box.

  The ordered (SOG) format is the priority — see docs/VISION.md §4.4.5:
  splats are the topology-free rendering mode that matches the
  omnispherical "graticule" vision. A splat cloud is the most honest
  expression of "space distribution without a mesh."

  WASD + pointer-lock fly controls are cribbed verbatim from web3d-space
  (the sister project the user pointed at) — same feel across both
  projects is a feature.
-->
<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import type { Asset, DreamBall } from '../generated/types.js';
	import { isSplatAsset, mediaTypeFromUrl } from '../splat/media-types.js';

	interface Props {
		ball: DreamBall;
		/** Optional explicit asset pick — otherwise uses ball.look.asset[0]. */
		asset?: Asset;
		/** Starting camera position. Same convention as web3d-space's SplatScene.camera. */
		cameraPosition?: [number, number, number];
		cameraYaw?: number;
		cameraPitch?: number;
	}
	let {
		ball,
		asset,
		cameraPosition = [0, 1.5, 3],
		cameraYaw = 180,
		cameraPitch = -5
	}: Props = $props();

	let canvas: HTMLCanvasElement;
	let loading = $state(true);
	let loadStatus = $state('Initialising…');
	let err: string | null = $state(null);
	let pcState: import('../playcanvas/create-app.js').PlayCanvasApp | null = null;

	const pickedAsset: Asset | undefined = $derived(asset ?? ball.look?.asset?.[0]);
	const splatUrl: string | undefined = $derived(pickedAsset?.url?.[0]);
	const splatMediaType: string | undefined = $derived(
		pickedAsset?.['media-type'] ?? (splatUrl ? mediaTypeFromUrl(splatUrl) : undefined)
	);

	function cleanup() {
		if (pcState) {
			pcState.app.destroy();
			pcState = null;
		}
	}
	onDestroy(cleanup);

	onMount(() => {
		let destroyed = false;

		async function init() {
			if (!splatUrl) {
				err = 'No splat URL on the DreamBall look.asset';
				loading = false;
				return;
			}
			if (!isSplatAsset(splatMediaType)) {
				err = `Not a splat media type: ${splatMediaType ?? '(unknown)'}`;
				loading = false;
				return;
			}

			try {
				const mod = await import('../playcanvas/create-app.js');
				pcState = await mod.createPlayCanvasApp({ canvas });
			} catch (e) {
				err = `PlayCanvas init failed: ${(e as Error).message}`;
				loading = false;
				return;
			}

			if (destroyed || !pcState) {
				cleanup();
				return;
			}

			const { pc, app } = pcState;
			loadStatus = 'Loading splat…';

			const splat = new pc.Asset('splat', 'gsplat', { url: splatUrl });
			const loader = new pc.AssetListLoader([splat], app.assets);
			loader.load(() => {
				if (destroyed || !pcState) return;

				const entity = new pc.Entity('splat');
				entity.addComponent('gsplat', { asset: splat });
				entity.setLocalEulerAngles(180, 0, 0);
				app.root.addChild(entity);

				const camera = new pc.Entity('camera');
				camera.addComponent('camera', {
					clearColor: new pc.Color(0.04, 0.05, 0.08),
					toneMapping: pc.TONEMAP_ACES,
					farClip: 500
				});
				camera.setLocalPosition(...cameraPosition);
				camera.setEulerAngles(cameraPitch, cameraYaw, 0);
				app.root.addChild(camera);

				// Optional post effects — matches web3d-space's baseline preset.
				// Newer playcanvas versions (2.18+) moved some properties around;
				// we set only the ones that cleanly survive typecheck. Deeper
				// tuning (bloom/vignette toggles) can return behind a helper once
				// the PC API stabilises.
				const cam = camera.camera;
				if (cam) {
					const frame = new pc.CameraFrame(app, cam);
					frame.rendering.toneMapping = pc.TONEMAP_ACES;
					frame.rendering.sharpness = 0.5;
					frame.bloom.intensity = 0.02;
					frame.vignette.intensity = 0.3;
					frame.enabled = true;
					frame.update();
				}

				// Fly-around controls — WASD + pointer lock (mobile: one-finger drag).
				let yaw = cameraYaw;
				let pitch = cameraPitch;
				const sensitivity = 0.15;
				let speed = 3;
				let locked = false;
				const keys = new Set<string>();

				canvas.addEventListener('click', () => {
					if (locked) document.exitPointerLock();
					else canvas.requestPointerLock();
				});
				document.addEventListener('pointerlockchange', () => {
					locked = document.pointerLockElement === canvas;
					if (!locked) keys.clear();
				});
				window.addEventListener('mousemove', (e) => {
					if (!locked) return;
					yaw -= e.movementX * sensitivity;
					pitch = Math.max(-89, Math.min(89, pitch - e.movementY * sensitivity));
					camera.setEulerAngles(pitch, yaw, 0);
				});
				canvas.addEventListener('wheel', (e) => {
					e.preventDefault();
					speed = Math.max(1, Math.min(30, speed - e.deltaY * 0.01));
				}, { passive: false });
				canvas.addEventListener('keydown', (e) => keys.add(e.code));
				canvas.addEventListener('keyup', (e) => keys.delete(e.code));
				if (!canvas.hasAttribute('tabindex')) canvas.setAttribute('tabindex', '0');

				let last = performance.now();
				const tick = () => {
					if (destroyed) return;
					const now = performance.now();
					const dt = (now - last) / 1000;
					last = now;
					const amt = speed * dt;
					const pos = camera.getPosition().clone();
					const forward = camera.forward.clone();
					const right = camera.right.clone();
					if (keys.has('KeyW')) pos.add(forward.clone().mulScalar(amt));
					if (keys.has('KeyS')) pos.add(forward.clone().mulScalar(-amt));
					if (keys.has('KeyD')) pos.add(right.clone().mulScalar(amt));
					if (keys.has('KeyA')) pos.add(right.clone().mulScalar(-amt));
					if (keys.has('Space') || keys.has('KeyE')) pos.y += amt;
					if (keys.has('ShiftLeft') || keys.has('KeyQ')) pos.y -= amt;
					camera.setPosition(pos);
					requestAnimationFrame(tick);
				};
				requestAnimationFrame(tick);

				loading = false;
			});
		}

		init();

		return () => {
			destroyed = true;
			cleanup();
		};
	});
</script>

<div class="splat-wrap">
	<canvas bind:this={canvas} aria-label="Gaussian splat viewer"></canvas>

	{#if loading}
		<div class="overlay">
			<p>{loadStatus}</p>
			<p class="detail">{splatUrl ?? ''}</p>
		</div>
	{/if}
	{#if err}
		<div class="overlay err">
			<p>Error</p>
			<p>{err}</p>
		</div>
	{/if}

	<div class="hud">
		<span class="name">{ball.name ?? '(unnamed)'}</span>
		{#if splatMediaType}
			<span class="media">{splatMediaType.replace('application/vnd.playcanvas.', '').replace('model/', '')}</span>
		{/if}
		<span class="hint">click · WASD · scroll=speed</span>
	</div>
</div>

<style>
	.splat-wrap {
		position: relative;
		width: 100%;
		aspect-ratio: 4 / 3;
		background: #0a0e20;
		border-radius: 1rem;
		overflow: hidden;
	}
	canvas {
		display: block;
		width: 100%;
		height: 100%;
		outline: none;
	}
	.overlay {
		position: absolute;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		background: rgba(5, 7, 20, 0.8);
		color: #aac;
		font-family: system-ui, sans-serif;
		gap: 0.4rem;
	}
	.overlay.err {
		background: #1a0a0a;
		color: #f88;
	}
	.overlay .detail {
		opacity: 0.5;
		font-size: 0.75rem;
		font-family: ui-monospace, Menlo, monospace;
	}
	.hud {
		position: absolute;
		left: 1rem;
		bottom: 0.75rem;
		display: flex;
		gap: 0.75rem;
		align-items: center;
		color: #e8ecf8;
		font-family: system-ui, sans-serif;
		font-size: 0.8rem;
	}
	.hud .name {
		font-weight: 600;
	}
	.hud .media {
		font-family: ui-monospace, Menlo, monospace;
		opacity: 0.6;
		font-size: 0.75rem;
	}
	.hud .hint {
		opacity: 0.45;
		font-size: 0.7rem;
	}
</style>
