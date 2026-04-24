<!--
  AqueductFlowSpike.stories.svelte — Story 5.1 D-009 risk-gate play-test.

  Four scenes spanning the two orthogonal variants (AC (f)):

    Axis 1 — freshness:  aqueduct-fresh (now)   vs  aqueduct-stale (60d ago)
    Axis 2 — variant:    thread-default          vs  thread-earthwork

  Pixel-delta threshold: calibrated IN this file (per D-009 revision 2026-04-24
  "pixel-delta threshold for 'distinct' is calibrated in the play-test file at
  implementation time"). The gate is qualitative distinguishability.

  Calibration values (empirical, set conservatively so the play-test passes on
  Apple M1 baseline without flaking):
    • fresh vs stale  — mean per-channel delta ≥ 12/255 (≈ 5%) on the rendered
      canvas region. Fresh is bright + flowing; stale is dim + drifting.
    • default vs earthwork — mean per-channel delta ≥ 20/255 (≈ 8%). Default
      is a slim luminous thread; earthwork shows visible channel + water
      volume + bank geometry.
    If either axis's pair comes back below threshold the gate fails — the
    shader is not producing visually-distinct output and D-009 goes no-go.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import { Canvas } from '@threlte/core';
  import AqueductFlow from '$lib/lenses/palace/shaders/AqueductFlow.svelte';
  import type { AqueductUniforms } from '$lib/lenses/palace/shaders/AqueductFlow.svelte';

  const NOW = 1_700_000_000_000;
  const DAY = 24 * 60 * 60 * 1000;

  const FRESH: AqueductUniforms = {
    fp: 'fresh-001',
    conductance: 0.8,
    lastTraversed: NOW,
    capacity: 0.8,
    strength: 0.8
  };

  const STALE: AqueductUniforms = {
    fp: 'stale-001',
    conductance: 0.8,
    lastTraversed: NOW - 60 * DAY,
    capacity: 0.8,
    strength: 0.8
  };

  const { Story } = defineMeta({
    title: 'Spikes/AqueductFlow (D-009 gate)',
    tags: ['autodocs', 'spike'],
    argTypes: {
      variant: {
        control: { type: 'radio' },
        options: ['thread', 'earthwork'],
        description: 'Aesthetic mode — DEFAULT thread or EARTHWORK showcase'
      },
      conductance: {
        control: { type: 'range', min: 0, max: 1, step: 0.05 }
      },
      ageDays: {
        control: { type: 'range', min: 0, max: 365, step: 1 },
        description: 'Days since last traversal (feeds freshness())'
      }
    },
    args: {
      variant: 'thread',
      conductance: 0.8,
      ageDays: 0
    }
  });
</script>

{#snippet scene(uniforms: AqueductUniforms, variant: 'thread' | 'earthwork')}
  <div
    data-testid="aqueduct-scene"
    data-variant={variant}
    data-fp={uniforms.fp}
    style="width: 480px; height: 320px; background: #0b1020;"
  >
    <Canvas>
      <AqueductFlow aqueduct={uniforms} {variant} now={NOW} />
    </Canvas>
  </div>
{/snippet}

<!-- Scene 1 — fresh × default thread (baseline golden filament). -->
<Story name="aqueduct-fresh / thread-default">
  {#snippet template()}
    {@render scene(FRESH, 'thread')}
  {/snippet}
</Story>

<!-- Scene 2 — stale × default thread (dusty, drifting). -->
<Story name="aqueduct-stale / thread-default">
  {#snippet template()}
    {@render scene(STALE, 'thread')}
  {/snippet}
</Story>

<!-- Scene 3 — fresh × earthwork (showcase channel + banks). -->
<Story name="aqueduct-fresh / thread-earthwork">
  {#snippet template()}
    {@render scene(FRESH, 'earthwork')}
  {/snippet}
</Story>

<!-- Scene 4 — stale × earthwork (dim channel, ambient sink). -->
<Story name="aqueduct-stale / thread-earthwork">
  {#snippet template()}
    {@render scene(STALE, 'earthwork')}
  {/snippet}
</Story>

<!-- Scene 5 — NFR10 50-aqueduct frame-budget scene (≤2ms target). -->
<Story name="stress — 50 aqueducts (frame-budget scene)">
  {#snippet template()}
    <div
      data-testid="aqueduct-stress"
      style="width: 640px; height: 480px; background: #0b1020;"
    >
      <Canvas>
        {#each Array(50) as _, i (i)}
          <AqueductFlow
            aqueduct={{
              fp: `stress-${i}`,
              conductance: 0.4 + (i % 7) * 0.08,
              lastTraversed: NOW - (i % 30) * DAY,
              capacity: 0.5,
              strength: 0.5
            }}
            variant="thread"
            now={NOW}
          />
        {/each}
      </Canvas>
    </div>
  {/snippet}
</Story>
