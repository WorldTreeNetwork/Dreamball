<!--
  AvatarLens stories — 3D canvas view of a DreamBall's visual aspect using Threlte.
  Reviewer cares because the background colour comes from ball.look.background and
  the icosahedron placeholder needs to render without WebGL errors in Storybook's
  sandboxed iframe. Controls expose the background colour picker and name text input
  so designers can iterate on the visual without touching code.

  The "Star Tamagotchi" story exercises the real glTF path: its look.asset
  points at /characters/star-tamagotchi.glb (served from static/), so the lens
  loads + auto-fits an actual character mesh instead of the placeholder. This is
  the first character DreamBall — the template every future character follows.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import AvatarLens from '$lib/lenses/AvatarLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';
  import type { Asset } from '$lib/generated/types.js';

  const STAR_ASSET: Asset = {
    'media-type': 'model/gltf-binary',
    hash: 'b58:AS4ZAd6dCtGmmGZ6ppK66T7adzMEVKG24XRoo57JVEXL',
    url: ['/characters/star-tamagotchi.glb'],
    size: 1047560,
    note: 'Star Tamagotchi avatar mesh (optimized GLB, 18k tris, webp 1024)'
  };

  const { Story } = defineMeta({
    title: 'Lenses/AvatarLens',
    component: AvatarLens,
    tags: ['autodocs'],
    render: template,
    argTypes: {
      background: {
        control: 'color',
        description: 'Background colour (fed into ball.look.background as "color:#rrggbb")'
      },
      name: { control: 'text', description: 'Display name shown in the overlay label' }
    },
    args: {
      background: '#0b1020',
      name: 'Mock Avatar'
    }
  });
</script>

{#snippet template(args: { background: string; name: string })}
  {@const ball = mockBall('avatar', {
    name: args.name,
    look: { background: `color:${args.background}`, asset: [] }
  })}
  <div style="width: 400px; height: 400px;">
    <AvatarLens {ball} />
  </div>
{/snippet}

<Story name="Star Tamagotchi (glTF mesh)">
  {#snippet children()}
    {@const ball = mockBall('avatar', {
      name: 'Star Tamagotchi',
      look: { background: 'color:#1a0a2e', asset: [STAR_ASSET] }
    })}
    <div style="width: 400px; height: 400px;">
      <AvatarLens {ball} />
    </div>
  {/snippet}
</Story>

<Story name="Default" args={{ background: '#0b1020', name: 'Mock Avatar' }} />

<Story name="Dark Background" args={{ background: '#030408', name: 'Midnight Avatar' }} />

<Story name="Purple Tint" args={{ background: '#200840', name: 'Cosmic Avatar' }} />
