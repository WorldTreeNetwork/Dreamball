<!--
  Wearer stories — drives an Avatar DreamBall's visual representation from live input.
  Reviewer cares because this is Demo D scenario 3; the "live stream attached" vs
  "synthetic input" vs "idle pulse" status text in the header must reflect the prop state,
  and the AvatarLens 3D canvas must render without errors regardless of which input mode.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import Wearer from '$lib/components/Wearer.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const { Story } = defineMeta({
    title: 'Components/Wearer',
    component: Wearer,
    tags: ['autodocs'],
    argTypes: {
      syntheticText: {
        control: 'text',
        description: 'Synthetic text input to simulate wearer activity without a webcam'
      }
    },
    args: {
      syntheticText: ''
    }
  });
</script>

<Story name="Idle (No Input)">
  {#snippet template(args)}
    {@const ball = mockBall('avatar', { name: 'Idle Wearer' })}
    <div style="width: 400px;">
      <Wearer {ball} />
    </div>
  {/snippet}
</Story>

<Story name="Synthetic Text Input" args={{ syntheticText: '' }}>
  {#snippet template(args: any)}
    {@const ball = mockBall('avatar', { name: 'Text-driven Wearer' })}
    <div style="width: 400px;">
      <Wearer {ball} syntheticText={args.syntheticText || 'Hello, I am thinking about hummingbirds...'} />
    </div>
  {/snippet}
</Story>

<Story name="No MediaStream (Observer View)">
  {#snippet template(args)}
    {@const ball = mockBall('avatar', { name: 'Observer View Avatar' })}
    <div style="width: 400px;">
      <Wearer {ball} sourceTrack={null} syntheticText="" />
    </div>
  {/snippet}
</Story>
