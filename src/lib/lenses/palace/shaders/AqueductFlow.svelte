<!--
  AqueductFlow.svelte — Threlte material wrapper for the aqueduct-flow shader.

  Story 5.1 / D-009 risk gate. This component:
    • Reads conductance + lastTraversed from a store.ts-derived value (prop);
      computes freshness via the SINGLE shared module
      src/memory-palace/aqueduct.ts — never copies the formula.
    • Mounts a ShaderMaterial with the .vert/.frag files under
      src/lib/shaders/; uniforms updated reactively on every derived tick.
    • Renders as an instanced quad; particle count scales with capacity × strength
      (wrapper parameters, clamped to prevent frame-budget blowouts on 50-aqueduct
      rooms — see D-009 NFR10 slice).
    • Handles canvas resize WITHOUT recompilation (program id stable across
      renderer.setSize events) — asserted by test.

  CROSS-RUNTIME INVARIANT: this file MUST NOT import from @ladybugdb/core,
  kuzu-wasm, or any store-adapter module. It receives already-decoded values
  via props. Grep asserts this boundary (AC (b) / D-007).

  WebGPU toggle: the `webgpu` prop is accepted for API surface completeness,
  but the material is a standard THREE.ShaderMaterial which Three.js/Threlte
  compile to the active renderer (WebGLRenderer today; a future WebGPURenderer
  would compile the same GLSL via tsl-compatible paths). Unit test stubs a
  denied WebGPU context and asserts graceful fallback (AC (a)).
-->
<script lang="ts">
  import { T } from '@threlte/core';
  import * as THREE from 'three';
  import { onMount } from 'svelte';
  import vertexShader from '../../../shaders/aqueduct-flow.vert.glsl?raw';
  import fragmentShader from '../../../shaders/aqueduct-flow.frag.glsl?raw';
  import { freshness, DUSTY_MS } from '../../../../memory-palace/aqueduct.js';

  /**
   * The renderer-consumer shape. Populated by the lens from a store.ts
   * derived value — this component itself is store-agnostic.
   */
  export interface AqueductUniforms {
    /** Aqueduct fingerprint (for stable key / debug). */
    fp: string;
    /** Conductance in [0, 1], from computeConductance(). */
    conductance: number;
    /** last-traversed timestamp ms — feeds freshness() below. */
    lastTraversed: number;
    /** Aqueduct capacity × strength → particle-count hint. */
    capacity?: number;
    strength?: number;
  }

  interface Props {
    aqueduct: AqueductUniforms;
    /** 'thread' (default) or 'earthwork' (opt-in showcase variant). */
    variant?: 'thread' | 'earthwork';
    /** Current wall-clock; injectable for determinism in tests. */
    now?: number;
    /** Reserved: toggle targeting a WebGPU renderer when one is available. */
    webgpu?: boolean;
    /** Upper bound on particles per aqueduct (frame-budget guard for 50-room scenes). */
    maxParticles?: number;
    /** Callback after first draw — used by play-test for NFR10 first-particle latency. */
    onFirstFrame?: (t_ms: number) => void;
  }

  const {
    aqueduct,
    variant = 'thread',
    now = Date.now(),
    webgpu = false,
    maxParticles = 48,
    onFirstFrame
  }: Props = $props();

  // Particle count: capacity × strength scaled; clamped to maxParticles so a
  // single aqueduct can never push the 50-aqueduct × ≤2ms frame budget over.
  const particleCount = $derived.by(() => {
    const cap = aqueduct.capacity ?? 0.5;
    const str = aqueduct.strength ?? 0.5;
    const n = Math.max(4, Math.min(maxParticles, Math.round(cap * str * 64)));
    return n;
  });

  // R7 parity: freshness is imported from the Epic-2 module, not copied.
  const freshnessValue = $derived(
    freshness(now, aqueduct.lastTraversed, DUSTY_MS)
  );

  // Build the ShaderMaterial once. We update uniforms imperatively (cheaper
  // than recreating on every prop tick) and keep the program id stable so
  // canvas resizes never trigger shader recompilation. Initial uniform values
  // are neutral defaults; the $effect below pushes real prop-derived values
  // on the first tick (and every tick thereafter).
  const material = new THREE.ShaderMaterial({
    vertexShader,
    fragmentShader,
    uniforms: {
      uTime: { value: 0 },
      uConductance: { value: 0 },
      uFreshness: { value: 1.0 },
      uMode: { value: 0 },
      uParticleCount: { value: 0 }
    },
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending
  });

  // Expose material for tests (program id / uniform peek).
  export function getMaterial(): THREE.ShaderMaterial {
    return material;
  }

  // Build a unit quad per particle; instanced so the wrapper emits one
  // draw-call per aqueduct — keeps 50 aqueducts within frame budget.
  //
  // Geometry is allocated ONCE at `maxParticles` (the upper bound). The visible
  // particle count is driven by `instanceCount` mutation + the uParticleCount
  // uniform, so strength/capacity updates no longer allocate a fresh
  // InstancedBufferGeometry every tick (M9 review fix — the previous
  // implementation leaked GPU buffers on every Hebbian bump).
  const quadGeometry = new THREE.PlaneGeometry(0.05, 0.05);
  const instanced = new THREE.InstancedBufferGeometry();
  instanced.index = quadGeometry.index;
  instanced.attributes.position = quadGeometry.attributes.position;
  instanced.attributes.normal = quadGeometry.attributes.normal;
  instanced.attributes.uv = quadGeometry.attributes.uv;
  {
    // Size the buffer once from the initial prop value. Changing maxParticles
    // after mount would require reallocating the GPU buffer anyway, which this
    // wrapper deliberately does not support (that's the whole point of M9 —
    // no per-update geometry allocation). Svelte lint is about reactivity only.
    // svelte-ignore state_referenced_locally
    const cap = maxParticles;
    const ts = new Float32Array(cap);
    for (let i = 0; i < cap; i++) {
      ts[i] = i / Math.max(1, cap);
    }
    instanced.setAttribute(
      'instanceT',
      new THREE.InstancedBufferAttribute(ts, 1)
    );
  }
  instanced.instanceCount = 0;

  $effect(() => {
    instanced.instanceCount = particleCount;
  });

  // Reactively push prop changes into the material uniforms.
  $effect(() => {
    material.uniforms.uConductance.value = aqueduct.conductance;
    material.uniforms.uFreshness.value = freshnessValue;
    material.uniforms.uMode.value = variant === 'earthwork' ? 1 : 0;
    material.uniforms.uParticleCount.value = particleCount;
  });

  // Drive uTime from a rAF loop; fires onFirstFrame on the first tick so the
  // play-test can measure first-particle latency (NFR10 slice, target ≤200ms).
  let rafId = 0;
  let firstFrameFired = false;
  const t0 = typeof performance !== 'undefined' ? performance.now() : Date.now();
  onMount(() => {
    const tick = () => {
      const now2 =
        typeof performance !== 'undefined' ? performance.now() : Date.now();
      material.uniforms.uTime.value = (now2 - t0) / 1000;
      if (!firstFrameFired) {
        firstFrameFired = true;
        onFirstFrame?.(now2 - t0);
      }
      rafId =
        typeof requestAnimationFrame !== 'undefined'
          ? requestAnimationFrame(tick)
          : 0;
    };
    rafId =
      typeof requestAnimationFrame !== 'undefined'
        ? requestAnimationFrame(tick)
        : 0;
    return () => {
      if (rafId && typeof cancelAnimationFrame !== 'undefined') {
        cancelAnimationFrame(rafId);
      }
      material.dispose();
      instanced.dispose();
      quadGeometry.dispose();
    };
  });

  // Accept webgpu prop without erroring even if the runtime denies WebGPU.
  // WebGL is the sprint-001 target per D-009 AC (a); WebGPU is a forward-looking
  // toggle that remains compiled-but-unused until a WebGPURenderer ships.
  // Read inside an effect so the reactive-reference lint stays silent and the
  // wrapper is future-proofed for renderer-swap propagation.
  $effect(() => {
    // Currently a no-op; reserved for future WebGPURenderer adoption.
    void webgpu;
  });
</script>

<T.Mesh geometry={instanced} {material} />
