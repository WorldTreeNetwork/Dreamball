<!--
  MythosLanternSpike.stories.svelte — S5.5 per-shader micro-spike gate.

  Per-shader micro-spike requirement (D-009 revision 2026-04-24):
    1. Shader compiles without warnings on WebGL.
    2. Static lantern at zero-point — no uniform required (stub MVP).
    3. Play-test captures pixel-diff (lantern visible against dark background).

  This scene: static lantern sphere at palace zero-point.
  No uniform changes (this is the stub MVP per S5.5 requirement:
  "MythosLanternSpike.stories.svelte — static lantern at zero-point; no uniform").

  Growth FR60f deferred: lantern ring, halo, mythos-chain heat.
  See MythosLantern.svelte header for full Growth deferred list.

  Kept in repo as reference (not deleted after promotion).
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import { Canvas } from '@threlte/core';
  import * as THREE from 'three';
  import MythosLantern from '$lib/lenses/palace/shaders/MythosLantern.svelte';

  const { Story } = defineMeta({
    title: 'Spikes/MythosLantern (S5.5 micro-spike)',
    tags: ['autodocs', 'spike'],
    argTypes: {
      scale: {
        control: { type: 'range', min: 0.1, max: 2.0, step: 0.1 },
        description: 'Lantern sphere scale'
      }
    },
    args: { scale: 0.3 }
  });
</script>

{#snippet scene(scale: number, label: string)}
  <div
    data-testid="mythos-lantern-scene"
    data-label={label}
    data-scale={scale}
    style="width: 480px; height: 320px; background: #020408;"
  >
    <Canvas>
        <MythosLantern position={[0, 0, 0]} {scale} />
    </Canvas>
  </div>
{/snippet}

<!-- Scene 1 — default stub lantern at zero-point. -->
<Story name="lantern-stub — static at zero-point">
  {#snippet template()}
    {@render scene(0.3, 'default')}
  {/snippet}
</Story>

<!-- Scene 2 — larger lantern for visibility inspection. -->
<Story name="lantern-stub — large scale (0.8)">
  {#snippet template()}
    {@render scene(0.8, 'large')}
  {/snippet}
</Story>

<!-- Scene 3 — trio of lanterns (manual, Growth FR60f would be orbital). -->
<Story name="lantern-stub — three at positions (Growth preview)">
  {#snippet template()}
    <div
      data-testid="mythos-lantern-trio"
      style="width: 480px; height: 320px; background: #020408;"
    >
      <Canvas>
        <MythosLantern position={[-2, 0, 0]} scale={0.3} />
        <MythosLantern position={[0, 0, 0]} scale={0.3} />
        <MythosLantern position={[2, 0, 0]} scale={0.3} />
      </Canvas>
    </div>
  {/snippet}
</Story>
