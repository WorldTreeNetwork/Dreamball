<!--
  FlatLens stories — universal 2D structured data card showing every populated slot.
  Reviewer cares because this is the fallback for Tool and Transmission-receipt views
  where 3D doesn't make sense; the type dropdown lets QA confirm that each DreamBall
  type's slot set renders correctly in the flat view without wrapping or overflow.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import FlatLens from '$lib/lenses/FlatLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';
  import type { DreamBallType } from '$lib/generated/types.js';

  const { Story } = defineMeta({
    title: 'Lenses/FlatLens',
    component: FlatLens,
    tags: ['autodocs'],
    render: template,
    argTypes: {
      ballType: {
        control: { type: 'select' },
        options: ['avatar', 'agent', 'tool', 'relic', 'field', 'guild'],
        description: 'Which DreamBall type to render in the flat view'
      }
    },
    args: {
      ballType: 'agent'
    }
  });
</script>

{#snippet template(args: { ballType: DreamBallType })}
  {@const ball = mockBall(args.ballType)}
  <FlatLens {ball} />
{/snippet}

<Story name="Default" args={{ ballType: 'agent' }} />

<Story name="Avatar">
  {#snippet template(args)}
    {@const ball = mockBall('avatar', { name: 'Flat Avatar' })}
    <FlatLens {ball} />
  {/snippet}
</Story>

<Story name="Tool">
  {#snippet template(args)}
    {@const ball = mockBall('tool', { name: 'Haiku Composer' })}
    <FlatLens {ball} />
  {/snippet}
</Story>

<Story name="Relic">
  {#snippet template(args)}
    {@const ball = mockBall('relic', { name: 'Secret Relic', 'reveal-hint': 'Look behind the mirror' })}
    <FlatLens {ball} />
  {/snippet}
</Story>

<Story name="Guild">
  {#snippet template(args)}
    {@const ball = mockBall('guild', { name: 'The Hummingbirds' })}
    <FlatLens {ball} />
  {/snippet}
</Story>

<Story name="Field">
  {#snippet template(args)}
    {@const ball = mockBall('field', { name: 'Dream Field Alpha' })}
    <FlatLens {ball} />
  {/snippet}
</Story>
