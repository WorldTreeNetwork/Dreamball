<!--
  Transmit Skill interaction story — demonstrates the transmission demo state
  after a successful skill transmit, showing the tool DreamBall alongside the
  target agent in a before/after layout. The play function verifies both
  the tool name and the "transmitted" status text are visible.
  Reviewer cares because this is Demo D scenario 1: tool transmission must
  be legible in both the tool card and the agent's updated state.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import { expect, within } from 'storybook/test';
  import ThumbnailLens from '$lib/lenses/ThumbnailLens.svelte';
  import FlatLens from '$lib/lenses/FlatLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const { Story } = defineMeta({
    title: 'Interactions/TransmitSkill',
    tags: ['autodocs']
  });

  const toolBall = mockBall('tool', { name: 'Haiku Composer' });
  const agentBall = mockBall('agent', { name: 'Curiosity Agent' });
</script>

<Story
  name="Post-Transmit State"
  play={async ({ canvasElement }) => {
    const canvas = within(canvasElement);

    // Assert tool and target agent names appear in their thumbnail headings
    // (both also appear in the transmission banner and FlatLens rows, so we
    // scope to role=heading to disambiguate).
    await expect(canvas.getByRole('heading', { name: 'Haiku Composer' })).toBeVisible();
    await expect(canvas.getByRole('heading', { name: 'Curiosity Agent' })).toBeVisible();

    // Assert the "Transmitted" banner label is visible (case-sensitive to
    // avoid matching the "Tool being transmitted" caption).
    await expect(canvas.getByText('Transmitted')).toBeVisible();
  }}
>
  {#snippet template(args)}
    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 2rem; padding: 1.5rem; background: #050810; font-family: system-ui, sans-serif;">
      <div>
        <p style="color: #aac; font-size: 0.75rem; margin: 0 0 0.75rem; font-family: monospace;">Tool being transmitted</p>
        <ThumbnailLens ball={toolBall} />
      </div>
      <div>
        <p style="color: #aac; font-size: 0.75rem; margin: 0 0 0.75rem; font-family: monospace;">Target agent</p>
        <ThumbnailLens ball={agentBall} />
      </div>
      <div style="grid-column: 1 / -1; text-align: center; padding: 0.75rem; background: rgba(224, 183, 255, 0.1); border-radius: 0.5rem; border: 1px solid rgba(224, 183, 255, 0.3);">
        <span style="color: #e0b7ff; font-weight: 600;">Transmitted</span>
        <span style="color: #aac; font-size: 0.85rem; margin-left: 0.5rem;">Haiku Composer → Curiosity Agent via mock guild</span>
      </div>
      <div style="grid-column: 1 / -1;">
        <p style="color: #aac; font-size: 0.75rem; margin: 0 0 0.75rem; font-family: monospace;">Agent flat view (updated skill list)</p>
        <FlatLens ball={agentBall} />
      </div>
    </div>
  {/snippet}
</Story>
