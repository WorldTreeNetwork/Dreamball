<!--
  PhoneLens stories — portrait-optimised summary that stacks thumbnail + feel + action row.
  Reviewer cares because this is the primary mobile surface; the type dropdown lets QA
  verify that each DreamBall type renders correctly at narrow viewport widths and that
  the action buttons are visible and accessible.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import PhoneLens from '$lib/lenses/PhoneLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';
  import type { DreamBallType } from '$lib/generated/types.js';

  const { Story } = defineMeta({
    title: 'Lenses/PhoneLens',
    component: PhoneLens,
    tags: ['autodocs'],
    render: template,
    argTypes: {
      ballType: {
        control: { type: 'select' },
        options: ['avatar', 'agent', 'tool', 'relic', 'field', 'guild'],
        description: 'Which DreamBall type to render in portrait view'
      }
    },
    args: {
      ballType: 'avatar'
    }
  });
</script>

{#snippet template(args: { ballType: DreamBallType })}
  {@const ball = mockBall(args.ballType)}
  <div style="max-width: 320px;">
    <PhoneLens {ball} />
  </div>
{/snippet}

<Story name="Default" args={{ ballType: 'avatar' }} />

<Story name="Avatar with Feel">
  {#snippet template(args)}
    {@const ball = mockBall('avatar', {
      name: 'Hummingbird',
      feel: { personality: 'playful, quick, precise', voice: 'young, curious, fast cadence' }
    })}
    <div style="max-width: 320px;">
      <PhoneLens {ball} />
    </div>
  {/snippet}
</Story>

<Story name="Agent Full">
  {#snippet template(args)}
    {@const ball = mockBall('agent', { name: 'Deep Thinker' })}
    <div style="max-width: 320px;">
      <PhoneLens {ball} />
    </div>
  {/snippet}
</Story>

<Story name="Relic (No Feel)">
  {#snippet template(args)}
    {@const ball = mockBall('relic', { name: 'Sealed Relic' })}
    <div style="max-width: 320px;">
      <PhoneLens {ball} />
    </div>
  {/snippet}
</Story>
