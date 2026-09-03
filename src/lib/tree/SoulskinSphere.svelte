<!--
  SoulskinSphere — Phase-0 canvas implementation of the 4-layer Soulskin
  shader. This gets the *right shape* on screen fast; Phase 1 upgrades to a
  Threlte/WebGL fragment shader (src/lib/tree/shaders/soulskin.{vert,frag}).
  See docs/products/wishing-tree/PHASES.md §5.3.

  Layers (outer→inner):
    1 Chromatic aberration rim (fresnel)
    2 Flowing grid (graticule projection)
    3 Subsurface scattering (inner glow)
    4 Fresnel edge (identity boundary, colour-keyed by `hue`)
-->
<script lang="ts">
	import { PALETTE } from './style/palette.js';

	interface Props {
		/** Diameter in px. */
		size?: number;
		/** Hue shift 0–360. Derived from fingerprint in Phase 1. */
		hue?: number;
		/** Current animation mood. */
		mood?: 'idle' | 'thinking' | 'wishing' | 'granting' | 'sealing';
		/** External trigger — right-click etc. */
		onpeel?: () => void;
	}

	let { size = 420, hue = 280, mood = 'idle', onpeel }: Props = $props();

	let canvas: HTMLCanvasElement | undefined = $state();
	let rafId = 0;

	function draw(t: number) {
		if (!canvas) return;
		const ctx = canvas.getContext('2d');
		if (!ctx) return;
		const dpr = window.devicePixelRatio || 1;
		const w = size;
		const h = size;
		if (canvas.width !== w * dpr) {
			canvas.width = w * dpr;
			canvas.height = h * dpr;
			ctx.scale(dpr, dpr);
		}
		ctx.clearRect(0, 0, w, h);
		const cx = w / 2;
		const cy = h / 2;
		const time = t / 1000;

		// Breath — 4s cycle, 2% amplitude for idle, faster/bigger for other states.
		const breathFreq = mood === 'thinking' ? 0.8 : mood === 'wishing' ? 0.5 : 0.25;
		const breathAmp = mood === 'granting' ? 0.06 : 0.02;
		const breath = 1 + Math.sin(time * Math.PI * 2 * breathFreq) * breathAmp;
		const r = (w * 0.42) * breath;

		// Layer 3: Subsurface body (inner → outer gradient)
		const body = ctx.createRadialGradient(cx - r * 0.25, cy - r * 0.25, r * 0.1, cx, cy, r);
		body.addColorStop(0, `hsla(${hue}, 90%, 78%, 0.9)`);
		body.addColorStop(0.35, `hsla(${hue}, 75%, 52%, 0.7)`);
		body.addColorStop(0.7, PALETTE.trunk);
		body.addColorStop(1, PALETTE.root);
		ctx.fillStyle = body;
		ctx.beginPath();
		ctx.arc(cx, cy, r, 0, Math.PI * 2);
		ctx.fill();

		// Layer 2: Flowing grid — latitude + longitude arcs, animated phase
		ctx.save();
		ctx.globalCompositeOperation = 'screen';
		ctx.strokeStyle = `hsla(${hue + 60}, 90%, 70%, 0.22)`;
		ctx.lineWidth = 1;
		for (let i = -4; i <= 4; i++) {
			const lat = (i / 4) * (Math.PI / 2);
			const y = cy + Math.sin(lat) * r;
			const rx = Math.cos(lat) * r;
			ctx.beginPath();
			ctx.ellipse(cx, y, rx, rx * 0.12, 0, 0, Math.PI * 2);
			ctx.stroke();
		}
		const phase = time * 0.2;
		for (let i = 0; i < 8; i++) {
			const lon = (i / 8) * Math.PI * 2 + phase;
			ctx.beginPath();
			ctx.ellipse(cx, cy, Math.abs(Math.cos(lon)) * r, r, 0, 0, Math.PI * 2);
			ctx.stroke();
		}
		ctx.restore();

		// Layer 1: Chromatic aberration rim — three offset circles
		ctx.save();
		ctx.globalCompositeOperation = 'screen';
		const rimWidth = 2 + Math.sin(time * 2) * 1;
		ctx.lineWidth = rimWidth;
		ctx.strokeStyle = `hsla(${hue - 30}, 95%, 60%, 0.5)`;
		ctx.beginPath();
		ctx.arc(cx - 1.5, cy, r + 2, 0, Math.PI * 2);
		ctx.stroke();
		ctx.strokeStyle = `hsla(${hue + 30}, 95%, 60%, 0.5)`;
		ctx.beginPath();
		ctx.arc(cx + 1.5, cy, r + 2, 0, Math.PI * 2);
		ctx.stroke();
		ctx.strokeStyle = `hsla(${hue}, 100%, 85%, 0.8)`;
		ctx.beginPath();
		ctx.arc(cx, cy, r + 2, 0, Math.PI * 2);
		ctx.stroke();
		ctx.restore();

		// Layer 4: Fresnel edge — outer glow ring
		const glow = ctx.createRadialGradient(cx, cy, r * 0.9, cx, cy, r * 1.25);
		glow.addColorStop(0, 'rgba(0,0,0,0)');
		glow.addColorStop(0.5, `hsla(${hue + 180}, 90%, 60%, 0.15)`);
		glow.addColorStop(1, 'rgba(0,0,0,0)');
		ctx.fillStyle = glow;
		ctx.beginPath();
		ctx.arc(cx, cy, r * 1.25, 0, Math.PI * 2);
		ctx.fill();

		rafId = requestAnimationFrame(draw);
	}

	$effect(() => {
		if (!canvas) return;
		rafId = requestAnimationFrame(draw);
		return () => cancelAnimationFrame(rafId);
	});

	function onContextMenu(e: MouseEvent) {
		e.preventDefault();
		onpeel?.();
	}
</script>

<div
	class="sphere-wrap"
	role="button"
	tabindex="0"
	aria-label="Soulskin sphere — right-click to peel"
	oncontextmenu={onContextMenu}
	onkeydown={(e) => {
		if (e.key === 'F2' || e.key === 'Enter') onpeel?.();
	}}
	style="width: {size}px; height: {size}px;"
>
	<canvas bind:this={canvas} style="width: {size}px; height: {size}px;"></canvas>
	<span class="hint" aria-hidden="true">right-click · F2 · to peel</span>
</div>

<style>
	.sphere-wrap {
		position: relative;
		display: grid;
		place-items: center;
		cursor: pointer;
	}
	.sphere-wrap:focus-visible {
		outline: 2px dashed var(--wt-fruit-gold);
		outline-offset: 12px;
	}
	.hint {
		position: absolute;
		bottom: -28px;
		left: 50%;
		transform: translateX(-50%);
		font-family: var(--wt-font-mono);
		font-size: 10px;
		letter-spacing: 0.2em;
		color: var(--wt-mist);
		text-transform: uppercase;
		opacity: 0.7;
		white-space: nowrap;
	}
	canvas {
		display: block;
	}
</style>
