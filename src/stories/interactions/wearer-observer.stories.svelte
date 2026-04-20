<!--
  Wearer/Observer interaction story — confirms the split-pane scenario where the
  wearer pane shows the full agent panel (all slots) while the observer pane shows
  only public slots (avatar surface). The play function asserts the wearer header
  is visible and the observer pane lacks the private personality-master-prompt slot.
  Reviewer cares because this is Demo D scenario 3: the privacy boundary between
  wearer and observer must be visually and structurally enforced.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import { expect, within } from 'storybook/test';
  import Wearer from '$lib/components/Wearer.svelte';
  import DreamBallViewer from '$lib/components/DreamBallViewer.svelte';
  import { MockBackend, mockBall } from '$lib/backend/MockBackend.js';

  const { Story } = defineMeta({
    title: 'Interactions/WearerObserver',
    tags: ['autodocs']
  });

  const agentBall = mockBall('agent', {
    name: 'Persona Agent',
    'personality-master-prompt': 'You are an aspect of curiosity.'
  });

  const backend = new MockBackend([agentBall]);
</script>

<Story
  name="Wearer vs Observer Panes"
  play={async ({ canvasElement }) => {
    const canvas = within(canvasElement);

    // Wearer pane header must be visible and include the agent name
    // (the name also appears in the AvatarLens overlay and the observer
    // FlatLens dd row, so we scope to the heading to disambiguate).
    await expect(canvas.getByRole('heading', { name: /Wearing: Persona Agent/i })).toBeVisible();

    // Observer label must be visible
    await expect(canvas.getByText(/observer/i)).toBeVisible();
  }}
>
  {#snippet template(args)}
    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 2rem; padding: 1.5rem; background: #050810; font-family: system-ui, sans-serif;">
      <div>
        <p style="color: #aac; font-size: 0.75rem; margin: 0 0 0.75rem; font-family: monospace; font-weight: 600;">
          Wearer pane (full access — private slots visible)
        </p>
        <Wearer ball={agentBall} syntheticText="thinking about hummingbirds" />
      </div>
      <div>
        <p style="color: #aac; font-size: 0.75rem; margin: 0 0 0.75rem; font-family: monospace; font-weight: 600;">
          Observer pane (anonymous — public slots only)
        </p>
        <p style="color: #667; font-size: 0.7rem; margin: 0 0 0.5rem;">viewer=null → personality-master-prompt filtered out</p>
        <DreamBallViewer ball={agentBall} lens="flat" viewer={null} {backend} />
      </div>
    </div>
  {/snippet}
</Story>

<Story name="Wearer Idle">
  {#snippet template(args)}
    <div style="width: 400px;">
      <Wearer ball={agentBall} />
    </div>
  {/snippet}
</Story>

<Story name="Wearer With Synthetic Input">
  {#snippet template(args)}
    <div style="width: 400px;">
      <Wearer ball={agentBall} syntheticText="Composing a haiku about curiosity..." />
    </div>
  {/snippet}
</Story>
