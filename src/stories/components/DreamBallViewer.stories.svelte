<!--
  DreamBallViewer stories — the top-level consumer-facing component that switches
  lens based on the `lens` prop and applies permission filtering via backend.
  Reviewer cares because this is the single entry point for all rendering;
  stories verify that every lens selection routes correctly and that switching
  the lens prop live re-renders without unmount errors.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import DreamBallViewer from '$lib/components/DreamBallViewer.svelte';
  import { MockBackend, mockBall } from '$lib/backend/MockBackend.js';
  import type { LensName } from '$lib/lenses/lens-types.js';
  import type { DreamBallType } from '$lib/generated/types.js';

  const backend = new MockBackend();

  const { Story } = defineMeta({
    title: 'Components/DreamBallViewer',
    component: DreamBallViewer,
    tags: ['autodocs'],
    render: template,
    argTypes: {
      lens: {
        control: { type: 'select' },
        options: ['thumbnail', 'avatar', 'knowledge-graph', 'emotional-state', 'omnispherical', 'flat', 'phone', 'splat'],
        description: 'Active lens to render'
      },
      ballType: {
        control: { type: 'select' },
        options: ['avatar', 'agent', 'tool', 'relic', 'field', 'guild'],
        description: 'DreamBall type to render'
      }
    },
    args: {
      lens: 'thumbnail',
      ballType: 'agent'
    }
  });
</script>

{#snippet template(args: { lens: LensName; ballType: DreamBallType })}
  {@const ball = mockBall(args.ballType, { name: 'Viewer Demo' })}
  <DreamBallViewer {ball} lens={args.lens} {backend} />
{/snippet}

<Story name="Default (Thumbnail)" args={{ lens: 'thumbnail', ballType: 'agent' }} />

<Story name="Flat Lens">
  {#snippet template(args)}
    {@const ball = mockBall('agent', { name: 'Agent in Flat View' })}
    <DreamBallViewer {ball} lens="flat" {backend} />
  {/snippet}
</Story>

<Story name="Knowledge Graph Lens">
  {#snippet template(args)}
    {@const ball = mockBall('agent', { name: 'KG Agent' })}
    <DreamBallViewer {ball} lens="knowledge-graph" {backend} />
  {/snippet}
</Story>

<Story name="Emotional State Lens">
  {#snippet template(args)}
    {@const ball = mockBall('agent', { name: 'Emotional Agent' })}
    <DreamBallViewer {ball} lens="emotional-state" {backend} />
  {/snippet}
</Story>

<Story name="Phone Lens">
  {#snippet template(args)}
    {@const ball = mockBall('avatar', { name: 'Mobile Avatar' })}
    <div style="max-width: 320px;">
      <DreamBallViewer {ball} lens="phone" {backend} />
    </div>
  {/snippet}
</Story>
