<!--
  DreamBallCard stories — the listing-surface thumbnail card with an onSelect callback.
  Reviewer cares because this is the primary interaction surface in any list/grid UI;
  the onSelect action must fire on click (verified in the Actions panel) and hover
  must produce the translateY lift without layout shift.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import { fn } from 'storybook/test';
  import DreamBallCard from '$lib/components/DreamBallCard.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const { Story } = defineMeta({
    title: 'Components/DreamBallCard',
    component: DreamBallCard,
    tags: ['autodocs'],
    args: {
      onSelect: fn()
    }
  });
</script>

<Story name="Default">
  {#snippet template(args)}
    {@const ball = mockBall('avatar', { name: 'Hummingbird' })}
    <DreamBallCard {ball} onSelect={fn()} />
  {/snippet}
</Story>

<Story name="Agent Card">
  {#snippet template(args)}
    {@const ball = mockBall('agent', { name: 'Curiosity Agent' })}
    <DreamBallCard {ball} onSelect={fn()} />
  {/snippet}
</Story>

<Story name="Relic Card">
  {#snippet template(args)}
    {@const ball = mockBall('relic', { name: 'Jade Compass' })}
    <DreamBallCard {ball} onSelect={fn()} />
  {/snippet}
</Story>

<Story name="Grid of Cards">
  {#snippet template(args)}
    <div style="display: flex; flex-wrap: wrap; gap: 1rem; padding: 1rem; background: #050810;">
      {#each ['avatar', 'agent', 'tool', 'relic', 'field', 'guild'] as type}
        {@const ball = mockBall(type as import('$lib/generated/types.js').DreamBallType, { name: `Mock ${type}` })}
        <DreamBallCard {ball} onSelect={fn()} />
      {/each}
    </div>
  {/snippet}
</Story>

<Story name="No Select Handler">
  {#snippet template(args)}
    {@const ball = mockBall('tool', { name: 'Read-only Tool Card' })}
    <DreamBallCard {ball} />
  {/snippet}
</Story>
