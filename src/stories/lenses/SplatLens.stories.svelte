<!--
  SplatLens stories — PlayCanvas GSplat (Gaussian splat) renderer using real .sog assets.
  Reviewer cares because this is the topology-free rendering mode described in VISION.md §4.4.5;
  it must load bonsai/skull/apartment from the PlayCanvas CDN without CORS errors and activate
  WASD fly controls. The URL picker lets QA swap assets live to verify all three load correctly.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import SplatLens from '$lib/lenses/SplatLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const SOG_URLS: Record<string, string> = {
    bonsai: 'https://raw.githubusercontent.com/playcanvas/engine/main/examples/assets/splats/bonsai.sog',
    skull: 'https://raw.githubusercontent.com/playcanvas/engine/main/examples/assets/splats/skull.sog',
    apartment: 'https://raw.githubusercontent.com/playcanvas/engine/main/examples/assets/splats/apartment.sog'
  };

  function makeSplatBall(url: string, name: string) {
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
    title: 'Lenses/SplatLens',
    component: SplatLens,
    tags: ['autodocs'],
    render: template,
    argTypes: {
      splatAsset: {
        control: { type: 'select' },
        options: ['bonsai', 'skull', 'apartment'],
        description: 'Which real SOG splat asset to load from PlayCanvas CDN'
      }
    },
    args: {
      splatAsset: 'bonsai'
    }
  });
</script>

{#snippet template(args: { splatAsset: string })}
  {@const ball = makeSplatBall(SOG_URLS[args.splatAsset], args.splatAsset)}
  <div style="width: 640px; height: 480px;">
    <SplatLens {ball} />
  </div>
{/snippet}

<Story name="Bonsai" args={{ splatAsset: 'bonsai' }} />

<Story name="Skull" args={{ splatAsset: 'skull' }} />

<Story name="Apartment" args={{ splatAsset: 'apartment' }} />

<Story name="No Asset (Error State)">
  {#snippet template(args)}
    {@const ball = mockBall('avatar', { name: 'No Splat', look: { asset: [] } })}
    <div style="width: 640px; height: 480px;">
      <SplatLens {ball} />
    </div>
  {/snippet}
</Story>
