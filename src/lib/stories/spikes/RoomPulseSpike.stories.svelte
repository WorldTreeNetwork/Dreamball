<!--
  RoomPulseSpike.stories.svelte — S5.5 per-shader micro-spike gate.

  Per-shader micro-spike requirement (D-009 revision 2026-04-24):
    ≤60-minute compile + binding smoke proving:
    1. Shader compiles without warnings on WebGL.
    2. One uniform (uCapacitance) changes visibly with a Storybook control.
    3. Play-test captures a pixel-diff.

  This scene: capacitance uniform → pulse period.
  Low capacitance (0.1) → slow 4s period.
  High capacitance (0.9) → fast ~1s period.
  Visually distinct: slow pulse vs fast flicker on the room quad.

  Kept in repo as reference implementation (not deleted after promotion) —
  matches sprint-004-logavatar /spike/splat-* pattern.

  NFR14 note: this spike uses room-pulse only. It does NOT add a 5th shader
  to the 4-shader budget — spikes are separate from the production lens pack.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import { Canvas } from '@threlte/core';
  import RoomPulse from '$lib/lenses/room/shaders/RoomPulse.svelte';

  const NOW = 1_700_000_000_000;
  const DAY = 24 * 60 * 60 * 1000;

  const { Story } = defineMeta({
    title: 'Spikes/RoomPulse (S5.5 micro-spike)',
    tags: ['autodocs', 'spike'],
    argTypes: {
      capacitance: {
        control: { type: 'range', min: 0, max: 1, step: 0.05 },
        description: 'Capacitance → pulse period (high = fast pulse)'
      },
      ageDays: {
        control: { type: 'range', min: 0, max: 400, step: 1 },
        description: 'Days since last traversal → freshness → colour'
      }
    },
    args: { capacitance: 0.5, ageDays: 0 }
  });
</script>

{#snippet scene(capacitance: number, ageDays: number)}
  <div
    data-testid="room-pulse-scene"
    data-capacitance={capacitance}
    data-age-days={ageDays}
    style="width: 480px; height: 320px; background: #060c18;"
  >
    <Canvas>
      <RoomPulse
        {capacitance}
        lastTraversed={NOW - ageDays * DAY}
        now={NOW}
      />
    </Canvas>
  </div>
{/snippet}

<!-- Scene 1 — slow pulse (low capacitance, fresh). -->
<Story name="slow-pulse — capacitance 0.1, fresh">
  {#snippet template()}
    {@render scene(0.1, 0)}
  {/snippet}
</Story>

<!-- Scene 2 — fast pulse (high capacitance, fresh). -->
<Story name="fast-pulse — capacitance 0.9, fresh">
  {#snippet template()}
    {@render scene(0.9, 0)}
  {/snippet}
</Story>

<!-- Scene 3 — cobweb-aged (60 days old, medium capacitance). -->
<Story name="aged — capacitance 0.5, 60d stale">
  {#snippet template()}
    {@render scene(0.5, 60)}
  {/snippet}
</Story>

<!-- Scene 4 — sleeping (400 days old, ghost luminance). -->
<Story name="sleeping — capacitance 0.5, 400d stale">
  {#snippet template()}
    {@render scene(0.5, 400)}
  {/snippet}
</Story>
