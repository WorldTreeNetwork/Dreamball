<!--
  EmotionalStateLens stories — radial intensity plot of emotional-register axes.
  Reviewer cares because this visualization communicates an agent's personality
  at a glance; sliders let designers and product owners explore edge cases
  (all-zero, single-axis spike, balanced) without touching fixture data.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import EmotionalStateLens from '$lib/lenses/EmotionalStateLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const { Story } = defineMeta({
    title: 'Lenses/EmotionalStateLens',
    component: EmotionalStateLens,
    tags: ['autodocs'],
    render: template,
    argTypes: {
      curiosity: { control: { type: 'range', min: 0, max: 1, step: 0.01 }, description: 'Curiosity axis (0–1)' },
      warmth: { control: { type: 'range', min: 0, max: 1, step: 0.01 }, description: 'Warmth axis (0–1)' },
      urgency: { control: { type: 'range', min: 0, max: 1, step: 0.01 }, description: 'Urgency axis (0–1)' },
      valence: { control: { type: 'range', min: 0, max: 1, step: 0.01 }, description: 'Valence axis (0–1)' },
      arousal: { control: { type: 'range', min: 0, max: 1, step: 0.01 }, description: 'Arousal axis (0–1)' }
    },
    args: {
      curiosity: 0.82,
      warmth: 0.55,
      urgency: 0.1,
      valence: 0.7,
      arousal: 0.4
    }
  });
</script>

{#snippet template(args: { curiosity: number; warmth: number; urgency: number; valence: number; arousal: number })}
  {@const ball = mockBall('agent', {
    'emotional-register': {
      axes: [
        { name: 'curiosity', value: args.curiosity, min: 0, max: 1 },
        { name: 'warmth', value: args.warmth, min: 0, max: 1 },
        { name: 'urgency', value: args.urgency, min: 0, max: 1 },
        { name: 'valence', value: args.valence, min: 0, max: 1 },
        { name: 'arousal', value: args.arousal, min: 0, max: 1 }
      ]
    }
  })}
  <EmotionalStateLens {ball} />
{/snippet}

<Story name="Default" args={{ curiosity: 0.82, warmth: 0.55, urgency: 0.1, valence: 0.7, arousal: 0.4 }} />

<Story name="Highly Curious" args={{ curiosity: 0.98, warmth: 0.3, urgency: 0.05, valence: 0.8, arousal: 0.6 }} />

<Story name="All Zero (Edge Case)" args={{ curiosity: 0, warmth: 0, urgency: 0, valence: 0, arousal: 0 }} />

<Story name="No Emotional Register">
  {#snippet template(args)}
    {@const ball = mockBall('tool')}
    <EmotionalStateLens {ball} />
  {/snippet}
</Story>
