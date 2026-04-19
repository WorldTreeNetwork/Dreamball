<!--
  ThumbnailLens stories — smallest-surface card that shows type, name, and fingerprint.
  Reviewer cares because this is the primary listing unit across every ball type;
  Controls let you verify that each type gets its correct gradient and that truncated
  fingerprints still read cleanly at any name length.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import ThumbnailLens from '$lib/lenses/ThumbnailLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';
  import type { Stage, DreamBallType } from '$lib/generated/types.js';

  const { Story } = defineMeta({
    title: 'Lenses/ThumbnailLens',
    component: ThumbnailLens,
    tags: ['autodocs'],
    render: template,
    argTypes: {
      name: { control: 'text', description: 'Display name of the DreamBall' },
      stage: {
        control: { type: 'select' },
        options: ['seed', 'dreamball', 'dragonball'],
        description: 'Lifecycle stage'
      },
      revision: { control: { type: 'number', min: 1, max: 99 }, description: 'Revision counter' },
      type: {
        control: { type: 'select' },
        options: ['avatar', 'agent', 'tool', 'relic', 'field', 'guild'],
        description: 'DreamBall type — drives background gradient'
      }
    },
    args: {
      name: 'Mock Avatar',
      stage: 'dreamball',
      revision: 1,
      type: 'avatar'
    }
  });
</script>

{#snippet template(args: { type: DreamBallType; name: string; stage: Stage; revision: number })}
  {@const ball = mockBall(args.type, { name: args.name, stage: args.stage, revision: args.revision })}
  <ThumbnailLens {ball} />
{/snippet}

<Story name="Default" args={{ type: 'avatar', name: 'Mock Avatar', stage: 'dreamball', revision: 1 }} />

<Story name="Agent" args={{ type: 'agent', name: 'Curiosity Agent', stage: 'dreamball', revision: 1 }} />

<Story name="Relic" args={{ type: 'relic', name: 'Hidden Memory', stage: 'dreamball', revision: 1 }} />

<Story name="Long Name" args={{ type: 'tool', name: 'A very long DreamBall name that might overflow', stage: 'dreamball', revision: 1 }} />
