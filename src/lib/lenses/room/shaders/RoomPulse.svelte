<!--
  RoomPulse.svelte — Threlte material wrapper for the room-pulse shader.

  Story 5.5 / NFR14 (shader 2 of 4 in the sprint-001 pack).

  Responsibilities:
    • Receives capacitance + lastTraversed props from the lens (store-derived).
    • Computes freshness by importing from src/memory-palace/aqueduct.ts
      — NEVER copies the formula (R7 parity single-source).
    • Constructs a THREE.ShaderMaterial with room-pulse.{vert,frag}.glsl.
    • Drives uTime via rAF loop; updates uCapacitance + uFreshness reactively.
    • Canvas-resize safe: ShaderMaterial.version kept stable (no needsUpdate=true).

  CROSS-RUNTIME INVARIANT: this file MUST NOT import from @ladybugdb/core,
  kuzu-wasm, or any store-adapter module. Props carry already-decoded values.
  Grep asserts this boundary in traversal.test.ts (RT5/RT6).

  Micro-spike gate (S5.5 per-shader): RoomPulseSpike.stories.svelte proves
  compile + live-uniform binding before promotion. This wrapper is the promoted
  production form.

  Growth deferred: full room-mesh geometry integration (current MVP renders on
  a PlaneGeometry quad; a proper room mesh would use the room's archiform).
-->
<script lang="ts">
  import { T } from '@threlte/core';
  import * as THREE from 'three';
  import { onMount } from 'svelte';
  import vertexShader from '../../../shaders/room-pulse.vert.glsl?raw';
  import fragmentShader from '../../../shaders/room-pulse.frag.glsl?raw';
  import { freshness, DUSTY_MS } from '../../../../memory-palace/aqueduct.js';

  interface Props {
    /** Aqueduct capacitance in [0,1] — drives pulse period. */
    capacitance?: number;
    /** Last-traversed timestamp ms — feeds freshness(). */
    lastTraversed?: number;
    /** Current wall-clock; injectable for determinism in tests. */
    now?: number;
    /** Callback after first draw (NFR10 first-frame latency measurement). */
    onFirstFrame?: (t_ms: number) => void;
  }

  const {
    capacitance = 0.5,
    lastTraversed = Date.now(),
    now = Date.now(),
    onFirstFrame,
  }: Props = $props();

  // R7 parity: freshness imported from Epic-2 module, not copied.
  const freshnessValue = $derived(freshness(now, lastTraversed, DUSTY_MS));

  // Build ShaderMaterial once with neutral defaults; $effect pushes real values.
  const material = new THREE.ShaderMaterial({
    vertexShader,
    fragmentShader,
    uniforms: {
      uTime: { value: 0 },
      uCapacitance: { value: 0.5 },
      uFreshness: { value: 1.0 },
    },
  });

  /** Expose material for tests (program-id stability, uniform peek). */
  export function getMaterial(): THREE.ShaderMaterial {
    return material;
  }

  // Push prop-derived values into uniforms on each reactive tick.
  $effect(() => {
    material.uniforms.uCapacitance.value = capacitance;
    material.uniforms.uFreshness.value = freshnessValue;
  });

  // rAF clock; fires onFirstFrame on first tick.
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

  // Simple quad geometry for MVP (full room-mesh integration is Growth tier).
  const geometry = new THREE.PlaneGeometry(2, 2);
</script>

<T.Mesh {geometry} {material} />
