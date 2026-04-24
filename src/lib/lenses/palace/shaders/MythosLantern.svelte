<!--
  MythosLantern.svelte — Threlte material wrapper for the mythos-lantern stub.

  Story 5.5 / NFR14 (shader 3 of 4 in the sprint-001 pack).

  STUB MVP: Single lantern-like light source at the palace fountain zero-point.
  No dynamic uniforms required at this tier.

  Growth FR60f acceptance note (documented here per S5.5 AC requirement):
    Full lantern-ring implementation is explicitly deferred to Growth FR60f.
    Items NOT in sprint-001 scope:
      - Polar lantern ring (N orbs orbiting zero-point)
      - Halo / bloom post-process pass
      - Mythos-chain heat: lantern brightness driven by recent true-naming count
      - Animated flicker correlated with oracle activity rate
    These are reserved Growth-tier deliverables. The stub is kept as a reference
    implementation matching the sprint-004-logavatar /spike/* pattern.

  D-009 graceful-degradation note (documented per S5.5 requirement):
    S5.1's D-009 gate passed six-of-six; dust-cobweb + mythos-lantern stub NOT
    deferred. Full 4-shader pack delivered as per epic-5.md § Story 5.5.

  CROSS-RUNTIME INVARIANT: no @ladybugdb/core / kuzu-wasm imports here.
  No freshness prop needed for this stub (Growth FR60f will add mythos-heat).
-->
<script lang="ts">
  import { T } from '@threlte/core';
  import * as THREE from 'three';
  import { onMount } from 'svelte';
  import vertexShader from '../../../shaders/mythos-lantern.vert.glsl?raw';
  import fragmentShader from '../../../shaders/mythos-lantern.frag.glsl?raw';

  interface Props {
    /** Position of the lantern in world space (default: palace zero-point). */
    position?: [number, number, number];
    /** Lantern scale (default: 0.3m radius sphere). */
    scale?: number;
    /** Callback after first draw — NFR10 first-frame measurement. */
    onFirstFrame?: (t_ms: number) => void;
  }

  const {
    position = [0, 0, 0] as [number, number, number],
    scale = 0.3,
    onFirstFrame,
  }: Props = $props();

  // Static material — no dynamic uniforms in MVP stub.
  const material = new THREE.ShaderMaterial({
    vertexShader,
    fragmentShader,
    uniforms: {},
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    side: THREE.FrontSide,
  });

  /** Expose material for tests. */
  export function getMaterial(): THREE.ShaderMaterial {
    return material;
  }

  // Lantern sphere geometry (low-poly — it's a background element).
  const geometry = new THREE.SphereGeometry(1, 16, 12);

  let firstFrameFired = false;
  const t0 = typeof performance !== 'undefined' ? performance.now() : Date.now();

  onMount(() => {
    // Fire onFirstFrame on the next tick (no rAF loop needed — static scene).
    const raf = typeof requestAnimationFrame !== 'undefined'
      ? requestAnimationFrame(() => {
          if (!firstFrameFired) {
            firstFrameFired = true;
            const elapsed = (typeof performance !== 'undefined' ? performance.now() : Date.now()) - t0;
            onFirstFrame?.(elapsed);
          }
        })
      : 0;
    return () => {
      if (raf && typeof cancelAnimationFrame !== 'undefined') cancelAnimationFrame(raf);
      material.dispose();
      geometry.dispose();
    };
  });
</script>

<!-- Lantern sphere at the palace zero-point (or prop-injected position). -->
<T.Mesh
  {geometry}
  {material}
  position={position}
  scale={[scale, scale, scale]}
/>
