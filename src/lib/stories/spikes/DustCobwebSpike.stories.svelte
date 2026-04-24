<!--
  DustCobwebSpike.stories.svelte — S5.5 per-shader micro-spike gate.

  Per-shader micro-spike requirement (D-009 revision 2026-04-24):
    1. Shader compiles without warnings on WebGL.
    2. One uniform (uFreshness) changes visibly with a Storybook control.
    3. Play-test captures a pixel-diff.

  This scene: freshness uniform → cobweb opacity.
  freshness > 0.05 → invisible (above cobweb threshold, fresh aqueduct).
  freshness ≈ 0.02 → semi-transparent cobweb overlay.
  freshness ≈ 0.0  → full cobweb + drift toward ambient sink.

  Visually distinct: clear aqueduct path vs heavy cobweb with drift particles.

  Kept in repo as reference (not deleted after promotion) —
  matches sprint-004-logavatar /spike/splat-* pattern.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import { Canvas } from '@threlte/core';
  import DustCobweb from '$lib/lenses/palace/shaders/DustCobweb.svelte';

  const NOW = 1_700_000_000_000;
  const DAY = 24 * 60 * 60 * 1000;

  const { Story } = defineMeta({
    title: 'Spikes/DustCobweb (S5.5 micro-spike)',
    tags: ['autodocs', 'spike'],
    argTypes: {
      ageDays: {
        control: { type: 'range', min: 0, max: 500, step: 5 },
        description: 'Days since last traversal → freshness → cobweb opacity'
      }
    },
    args: { ageDays: 0 }
  });
</script>

{#snippet scene(ageDays: number, label: string)}
  <div
    data-testid="dust-cobweb-scene"
    data-age-days={ageDays}
    data-label={label}
    style="width: 480px; height: 200px; background: #060c18;"
  >
    <Canvas>
      <DustCobweb
        lastTraversed={NOW - ageDays * DAY}
        now={NOW}
      />
    </Canvas>
  </div>
{/snippet}

<!-- Scene 1 — fresh (no cobweb visible). -->
<Story name="fresh — 0d (invisible, above threshold)">
  {#snippet template()}
    {@render scene(0, 'fresh')}
  {/snippet}
</Story>

<!-- Scene 2 — cobweb threshold (91 days → freshness just below 0.05). -->
<Story name="cobweb-threshold — 91d (cobweb appears)">
  {#snippet template()}
    {@render scene(91, 'cobweb-threshold')}
  {/snippet}
</Story>

<!-- Scene 3 — deep cobweb (200 days). -->
<Story name="deep-cobweb — 200d">
  {#snippet template()}
    {@render scene(200, 'deep-cobweb')}
  {/snippet}
</Story>

<!-- Scene 4 — sleeping / drift (400 days → particle drift toward sink). -->
<Story name="sleeping — 400d (drift toward ambient sink)">
  {#snippet template()}
    {@render scene(400, 'sleeping')}
  {/snippet}
</Story>
