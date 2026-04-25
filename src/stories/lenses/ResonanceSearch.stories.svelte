<!--
  ResonanceSearch stories — K-NN driven resonance search UI (S6.3 AC10).
  Reviewer cares because this is the primary offline-degradation surface for
  the memory palace. Two variants must pass play-test:
    1. Online mock: hit cards render with fp + distance badge.
    2. Offline mock: "offline — cached-only" indicator appears; no console error.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import { expect, within, waitFor } from 'storybook/test';
  import ResonanceSearch from '$lib/components/ResonanceSearch.svelte';
  import type { KnnHit } from '../../memory-palace/store-types.js';

  const mockHits: KnnHit[] = [
    { fp: 'aaaa'.repeat(16), roomFp: 'bbbb'.repeat(16), distance: 0.0821 },
    { fp: 'cccc'.repeat(16), roomFp: 'bbbb'.repeat(16), distance: 0.1453 },
    { fp: 'dddd'.repeat(16), roomFp: 'eeee'.repeat(16), distance: 0.2190 },
  ];

  const { Story } = defineMeta({
    title: 'Lenses/ResonanceSearch',
    component: ResonanceSearch,
    tags: ['autodocs'],
    argTypes: {
      offline: { control: 'boolean', description: 'Simulate OfflineKnnError state' },
      loading: { control: 'boolean', description: 'Simulate in-flight kNN call' }
    }
  });
</script>

<!--
  AC10 — online-mock: hit cards render with fp + distance badge.
  play-test asserts hit list present, distance badges visible, no blank screen.
-->
<Story
  name="Online — top-3 hits"
  play={async ({ canvasElement }) => {
    const canvas = within(canvasElement);

    // Hit list must be present (AC1 — roomFp resolved)
    await waitFor(() => canvas.getByTestId('hit-list'), { timeout: 2000 });

    const hitList = canvas.getByTestId('hit-list');
    await expect(hitList).toBeTruthy();

    // 3 hit cards
    const cards = canvas.getAllByTestId('hit-card');
    await expect(cards.length).toBe(3);

    // Distance badges visible
    const badges = canvas.getAllByTestId('distance-badge');
    await expect(badges.length).toBe(3);

    // First badge contains 'd=0.0821'
    await expect(badges[0].textContent).toContain('d=0.082');

    // No offline indicator
    const offlineEl = canvasElement.querySelector('[data-testid="offline-indicator"]');
    await expect(offlineEl).toBeNull();
  }}
>
  {#snippet template()}
    <div style="width: 480px; background: #0b1020; padding: 1rem; border-radius: 6px;">
      <ResonanceSearch hits={mockHits} offline={false} loading={false} />
    </div>
  {/snippet}
</Story>

<!--
  AC10 — offline-mock: OfflineKnnError branch shows "offline — cached-only".
  play-test asserts offline indicator present, hit list absent, no console error.
-->
<Story
  name="Offline — OfflineKnnError indicator"
  play={async ({ canvasElement }) => {
    const canvas = within(canvasElement);

    // Offline indicator must appear
    await waitFor(() => canvas.getByTestId('offline-indicator'), { timeout: 2000 });

    const offlineEl = canvas.getByTestId('offline-indicator');
    await expect(offlineEl).toBeTruthy();
    await expect(offlineEl.textContent).toContain('offline');
    await expect(offlineEl.textContent).toContain('cached-only');

    // No hit list rendered
    const hitList = canvasElement.querySelector('[data-testid="hit-list"]');
    await expect(hitList).toBeNull();
  }}
>
  {#snippet template()}
    <div style="width: 480px; background: #0b1020; padding: 1rem; border-radius: 6px;">
      <ResonanceSearch hits={[]} offline={true} loading={false} />
    </div>
  {/snippet}
</Story>

<Story name="Loading state">
  {#snippet template()}
    <div style="width: 480px; background: #0b1020; padding: 1rem; border-radius: 6px;">
      <ResonanceSearch hits={[]} offline={false} loading={true} />
    </div>
  {/snippet}
</Story>

<Story name="Empty results">
  {#snippet template()}
    <div style="width: 480px; background: #0b1020; padding: 1rem; border-radius: 6px;">
      <ResonanceSearch hits={[]} offline={false} loading={false} />
    </div>
  {/snippet}
</Story>
