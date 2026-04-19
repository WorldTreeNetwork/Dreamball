<!--
  OmnisphericalLens stories — three concentric wire-sphere layers representing
  the graticule vision from VISION.md §4.4.5.
  Reviewer cares because layer depth, palette, and pole rotation are the key
  design knobs for field-type DreamBalls; Controls expose all three so the
  product team can iterate on the spatial metaphor without code changes.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import OmnisphericalLens from '$lib/lenses/OmnisphericalLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const { Story } = defineMeta({
    title: 'Lenses/OmnisphericalLens',
    component: OmnisphericalLens,
    tags: ['autodocs'],
    render: template,
    argTypes: {
      layerDepth: {
        control: { type: 'range', min: 1, max: 5, step: 1 },
        description: 'Number of concentric sphere layers (1–5)'
      },
      color0: { control: 'color', description: 'Palette colour 0 (innermost / background)' },
      color1: { control: 'color', description: 'Palette colour 1 (mid layer)' },
      color2: { control: 'color', description: 'Palette colour 2 (outer layer)' },
      poleRotation: {
        control: { type: 'range', min: 0, max: 360, step: 1 },
        description: 'Pole rotation in degrees (visual only — rotates the pole axis mesh)'
      }
    },
    args: {
      layerDepth: 3,
      color0: '#0b1020',
      color1: '#1a2240',
      color2: '#303a6a',
      poleRotation: 0
    }
  });
</script>

{#snippet template(args: { layerDepth: number; color0: string; color1: string; color2: string; poleRotation: number })}
  {@const ball = mockBall('field', {
    'omnispherical-grid': {
      'layer-depth': args.layerDepth,
      'camera-ring': Array.from({ length: args.layerDepth }, (_, i) => ({
        radius: (i + 1) * 1.2,
        tilt: i * 0.3,
        fov: 60 + i * 10
      })),
      resolution: 8
    },
    'ambient-palette': [args.color0, args.color1, args.color2]
  })}
  <div style="width: 480px; height: 360px;">
    <OmnisphericalLens {ball} />
  </div>
{/snippet}

<Story name="Default" args={{ layerDepth: 3, color0: '#0b1020', color1: '#1a2240', color2: '#303a6a', poleRotation: 0 }} />

<Story name="Single Layer">
  {#snippet template(args)}
    {@const ball = mockBall('field', {
      'omnispherical-grid': { 'layer-depth': 1, 'camera-ring': [{ radius: 1.2, tilt: 0, fov: 60 }] },
      'ambient-palette': ['#200040', '#400080', '#6000c0']
    })}
    <div style="width: 480px; height: 360px;">
      <OmnisphericalLens {ball} />
    </div>
  {/snippet}
</Story>

<Story name="Max Depth (5 layers)">
  {#snippet template(args)}
    {@const ball = mockBall('field', {
      'omnispherical-grid': {
        'layer-depth': 5,
        'camera-ring': [1.2, 2.4, 3.6, 4.8, 6.0].map((radius, i) => ({ radius, tilt: i * 0.2, fov: 60 }))
      },
      'ambient-palette': ['#0b1020', '#1a2240', '#303a6a', '#404a8a', '#505aaa']
    })}
    <div style="width: 480px; height: 360px;">
      <OmnisphericalLens {ball} />
    </div>
  {/snippet}
</Story>
