<!--
  DustCobweb.svelte — Threlte material wrapper for the dust-cobweb shader.

  Story 5.5 / NFR14 (shader 4 of 4 in the sprint-001 pack).

  Responsibilities:
    • Overlays a cobweb texture on an aqueduct path.
    • Opacity proportional to decay depth when freshness < 90-day threshold.
    • At freshness floor (< 365d sleeping), particles drift toward ambient sink
      per Vril ADR §9 "return-to-zero-point is visual, not destructive".
    • Computes freshness by importing from src/memory-palace/aqueduct.ts (R7).

  CROSS-RUNTIME INVARIANT: no @ladybugdb/core / kuzu-wasm imports.
  Grep asserts this boundary in traversal.test.ts (RT5/RT6).

  Visual behaviour:
    freshness > 0.05 (< 90d)  → invisible (discard in fragment shader)
    0.001 < f ≤ 0.05           → cobweb overlay opacity ramps up
    f ≤ 0.001 (> 365d)         → full cobweb + drift toward zero-point
-->
<script lang="ts">
  import { T } from '@threlte/core';
  import * as THREE from 'three';
  import { onMount } from 'svelte';
  import vertexShader from '../../../shaders/dust-cobweb.vert.glsl?raw';
  import fragmentShader from '../../../shaders/dust-cobweb.frag.glsl?raw';
  import { freshness, DUSTY_MS } from '../../../../memory-palace/aqueduct.js';

  interface Props {
    /** Last-traversed timestamp ms — feeds freshness() for opacity. */
    lastTraversed?: number;
    /** Current wall-clock ms; injectable for tests. */
    now?: number;
    /** Ebbinghaus tau (ms); defaults to DUSTY_MS (30d). */
    tau?: number;
    /** Callback after first draw — NFR10 measurement. */
    onFirstFrame?: (t_ms: number) => void;
  }

  const {
    lastTraversed = Date.now(),
    now = Date.now(),
    tau = DUSTY_MS,
    onFirstFrame,
  }: Props = $props();

  // R7 parity: imported from aqueduct.ts, not copied.
  const freshnessValue = $derived(freshness(now, lastTraversed, tau));

  const material = new THREE.ShaderMaterial({
    vertexShader,
    fragmentShader,
    uniforms: {
      uTime: { value: 0 },
      uFreshness: { value: 1.0 },
    },
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
    blending: THREE.NormalBlending,
  });

  /** Expose material for tests. */
  export function getMaterial(): THREE.ShaderMaterial {
    return material;
  }

  $effect(() => {
    material.uniforms.uFreshness.value = freshnessValue;
  });

  let rafId = 0;
  let firstFrameFired = false;
  const t0 = typeof performance !== 'undefined' ? performance.now() : Date.now();

  onMount(() => {
    const tick = () => {
      const t = typeof performance !== 'undefined' ? performance.now() : Date.now();
      material.uniforms.uTime.value = (t - t0) / 1000;
      if (!firstFrameFired) {
        firstFrameFired = true;
        onFirstFrame?.(t - t0);
      }
      rafId = typeof requestAnimationFrame !== 'undefined' ? requestAnimationFrame(tick) : 0;
    };
    rafId = typeof requestAnimationFrame !== 'undefined' ? requestAnimationFrame(tick) : 0;
    return () => {
      if (rafId && typeof cancelAnimationFrame !== 'undefined') cancelAnimationFrame(rafId);
      material.dispose();
      geometry.dispose();
    };
  });

  // Quad covering the aqueduct path (full path geometry is Growth tier).
  const geometry = new THREE.PlaneGeometry(2, 0.15);
</script>

<T.Mesh {geometry} {material} />
