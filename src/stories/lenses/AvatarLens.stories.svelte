<!--
  AvatarLens stories — 3D canvas view of a DreamBall's visual aspect using Threlte.
  Reviewer cares because the background colour comes from ball.look.background and
  the icosahedron placeholder needs to render without WebGL errors in Storybook's
  sandboxed iframe. Controls expose the background colour picker and name text input
  so designers can iterate on the visual without touching code.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import AvatarLens from '$lib/lenses/AvatarLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

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

<Story name="Default" args={{ background: '#0b1020', name: 'Mock Avatar' }} />

<Story name="Dark Background" args={{ background: '#030408', name: 'Midnight Avatar' }} />

<Story name="Purple Tint" args={{ background: '#200840', name: 'Cosmic Avatar' }} />
