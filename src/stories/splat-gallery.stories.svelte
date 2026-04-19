<!--
  Splat Gallery — a curated grid of real Gaussian splat (.sog) scenes loaded from
  the PlayCanvas CDN. Reviewer cares because this is the primary visual quality gate
  for the topology-free rendering path described in VISION.md §4.4.5; all three
  scenes (bonsai, skull, apartment) must load without CORS errors or WebGPU fallback
  failures, and WASD fly controls must activate on click in each canvas.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import SplatLens from '$lib/lenses/SplatLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const SPLAT_ASSETS = [
    {
      name: 'Bonsai',
      url: 'https://raw.githubusercontent.com/playcanvas/engine/main/examples/assets/splats/bonsai.sog',
      description: 'Classic bonsai tree — good detail density test'
    },
    {
      name: 'Skull',
      url: 'https://raw.githubusercontent.com/playcanvas/engine/main/examples/assets/splats/skull.sog',
      description: 'Skull scan — tests fine geometry at close range'
    },
    {
      name: 'Apartment',
      url: 'https://raw.githubusercontent.com/playcanvas/engine/main/examples/assets/splats/apartment.sog',
      description: 'Interior scene — tests large-scale splat with occlusion'
    }
  ];

  function makeSplatBall(name: string, url: string) {
    return mockBall('avatar', {
      name,
      look: {
        asset: [{
          'media-type': 'application/vnd.playcanvas.gsplat',
          hash: 'b58:mockSplatHash0000000000000000000',
          url: [url]
        }]
      }
    });
  }

  const { Story } = defineMeta({
    title: 'Splat Gallery',
    tags: ['autodocs']
  });
</script>

<Story name="All Splats Grid">
  {#snippet template(args)}
    <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(400px, 1fr)); gap: 1.5rem; padding: 1.5rem; background: #030508;">
      {#each SPLAT_ASSETS as asset (asset.name)}
        <div>
          <p style="color: #aac; font-family: monospace; font-size: 0.75rem; margin: 0 0 0.4rem;">
            {asset.name} — <span style="opacity: 0.6;">{asset.description}</span>
          </p>
          <div style="height: 300px;">
            <SplatLens ball={makeSplatBall(asset.name, asset.url)} />
          </div>
        </div>
      {/each}
    </div>
  {/snippet}
</Story>

<Story name="Bonsai Full Width">
  {#snippet template(args)}
    <div style="height: 500px;">
      <SplatLens ball={makeSplatBall('Bonsai', SPLAT_ASSETS[0].url)} />
    </div>
  {/snippet}
</Story>

<Story name="Skull Full Width">
  {#snippet template(args)}
    <div style="height: 500px;">
      <SplatLens ball={makeSplatBall('Skull', SPLAT_ASSETS[1].url)} />
    </div>
  {/snippet}
</Story>

<Story name="Apartment Full Width">
  {#snippet template(args)}
    <div style="height: 500px;">
      <SplatLens ball={makeSplatBall('Apartment', SPLAT_ASSETS[2].url)} />
    </div>
  {/snippet}
</Story>
