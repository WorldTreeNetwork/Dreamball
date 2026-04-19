<!--
  Unlock Reveal interaction story — play function clicks the "Unlock with Guild Key"
  button on a SealedRelic, waits for the opening animation, then asserts the inner
  DreamBall name appears in the revealed state.
  Reviewer cares because this is the core Demo D scenario 2 automated test;
  if the animation plays but the inner ball never renders, this story fails.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import { expect, within, userEvent, waitFor } from 'storybook/test';
  import SealedRelic from '$lib/components/SealedRelic.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const { Story } = defineMeta({
    title: 'Interactions/UnlockReveal',
    component: SealedRelic,
    tags: ['autodocs']
  });

  function makeUnlockHandler() {
    return async () => {
      await new Promise((r) => setTimeout(r, 100));
      return mockBall('avatar', { name: 'Inner Hummingbird' });
    };
  }
</script>

<Story
  name="Click Unlock and Assert Reveal"
  play={async ({ canvasElement }) => {
    const canvas = within(canvasElement);

    // Assert initial sealed state
    const unlockBtn = canvas.getByRole('button', { name: /unlock/i });
    await expect(unlockBtn).not.toBeDisabled();

    // Click the unlock button
    await userEvent.click(unlockBtn);

    // Wait for the opening phase text to appear
    await waitFor(() => canvas.getByText(/peeling/i), { timeout: 3000 });

    // Wait for the reveal to complete (inner ball name appears)
    await waitFor(() => canvas.getByText(/inner hummingbird/i), { timeout: 5000 });
  }}
>
  {#snippet template(args)}
    {@const relic = mockBall('relic', {
      name: 'Test Relic',
      'reveal-hint': 'A hummingbird waits inside'
    })}
    <SealedRelic {relic} onUnlock={makeUnlockHandler()} />
  {/snippet}
</Story>

<Story name="Disabled State (No Handler)">
  {#snippet template(args)}
    {@const relic = mockBall('relic', {
      name: 'Locked Relic',
      'reveal-hint': 'No key provided'
    })}
    <SealedRelic {relic} />
  {/snippet}
</Story>
