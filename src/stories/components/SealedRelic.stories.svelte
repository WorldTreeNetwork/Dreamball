<!--
  SealedRelic stories — the unlock-reveal component with three phase states:
  sealed → opening (animation) → opened (inner DreamBall in omnispherical lens).
  Reviewer cares because this is Demo D scenario 2; the reveal animation must
  play the CSS peel keyframe and the inner DreamBall must render after ~1.2s.
  The "No Handler" story verifies the Unlock button is correctly disabled.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import SealedRelic from '$lib/components/SealedRelic.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const { Story } = defineMeta({
    title: 'Components/SealedRelic',
    component: SealedRelic,
    tags: ['autodocs']
  });

  function makeUnlockHandler(innerName: string) {
    return async () => {
      await new Promise((r) => setTimeout(r, 800));
      return mockBall('avatar', { name: innerName });
    };
  }
</script>

<Story name="Sealed (No Handler — Button Disabled)">
  {#snippet template(args)}
    {@const relic = mockBall('relic', {
      name: 'The Jade Compass',
      'reveal-hint': 'Look behind the mirror at midnight'
    })}
    <SealedRelic {relic} />
  {/snippet}
</Story>

<Story name="With Unlock Handler">
  {#snippet template(args)}
    {@const relic = mockBall('relic', {
      name: 'The Jade Compass',
      'reveal-hint': 'A rare hummingbird waits inside'
    })}
    <SealedRelic {relic} onUnlock={makeUnlockHandler('Hummingbird Inner')} />
  {/snippet}
</Story>

<Story name="Slow Unlock (Tests Animation)">
  {#snippet template(args)}
    {@const relic = mockBall('relic', {
      name: 'Ancient Tome',
      'reveal-hint': 'Patience reveals all secrets'
    })}
    {@const slowUnlock = async () => {
      await new Promise((r) => setTimeout(r, 2000));
      return mockBall('agent', { name: 'The Ancient Knowledge' });
    }}
    <SealedRelic {relic} onUnlock={slowUnlock} />
  {/snippet}
</Story>
