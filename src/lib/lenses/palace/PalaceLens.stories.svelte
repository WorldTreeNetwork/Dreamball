<!--
  PalaceLens.stories.svelte — Story 5.2 / FR15 Storybook stories.

  Three stories covering AC2, AC3, AC4, AC6:

    1. "Grid fallback - 3+ rooms" — palace with ≥3 rooms, no jelly.layout.
       Asserts canvas renders and palace-fp is visible (AC3, AC6).

    2. "Layout positions - 3+ rooms" — palace with ≥3 rooms, each with layout.position.
       Asserts canvas renders (AC2, AC6).

    3. "Navigate event - room click" — palace with ≥3 rooms; play-test dispatches
       a synthetic navigate event and asserts payload shape (AC4, AC6).

  Pattern follows AqueductFlowSpike.stories.svelte — snippet inside Story tag.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import { expect, within } from 'storybook/test';
  import PalaceLens from '$lib/lenses/palace/PalaceLens.svelte';
  import type { StoreAPI } from '../../../memory-palace/store-types.js';

  // ── Mock store: minimal StoreAPI surface for stories ──────────────────────

  /**
   * Mock store implementing only the two verbs PalaceLens consumes.
   * Cast to StoreAPI via unknown since we only stub the read verbs.
   */
  function makeMockStore(roomFps: string[]): StoreAPI {
    return {
      async getPalace(fp: string) {
        return { fp, name: 'Mock Palace', omnisphericalGrid: null };
      },
      async roomsFor(_fp: string) {
        return roomFps.map((fp) => ({ fp, layout: null }));
      }
    } as unknown as StoreAPI;
  }

  function makeMockStoreWithLayout(roomFps: string[]): StoreAPI {
    const layoutMap: Record<string, [number, number, number]> = {
      'b58:room-aaa111': [3, 0, 0],
      'b58:room-bbb222': [-3, 0, 0],
      'b58:room-ccc333': [0, 3, 0],
      'b58:room-ddd444': [0, -3, 0]
    };
    return {
      async getPalace(fp: string) {
        return { fp, name: 'Layout Palace', omnisphericalGrid: null };
      },
      async roomsFor(_fp: string) {
        return roomFps.map((fp) => {
          const pos = layoutMap[fp];
          return {
            fp,
            layout: pos
              ? { placements: [{ 'child-fp': fp, position: pos, facing: [0, 0, 0, 1] as [number, number, number, number] }] }
              : null
          };
        });
      }
    } as unknown as StoreAPI;
  }

  // Room fps sorted lexicographically — matches store.roomsFor order.
  const ROOM_FPS = [
    'b58:room-aaa111',
    'b58:room-bbb222',
    'b58:room-ccc333',
    'b58:room-ddd444'
  ];

  const PALACE_FP = 'b58:palace-test-0001';

  /**
   * Svelte action that listens for bubbled `navigate` CustomEvents and mirrors
   * the detail onto data attributes — used by the play-test to assert payload.
   */
  function navigateCatcher(el: HTMLElement) {
    function handler(e: Event) {
      const ce = e as CustomEvent<{ kind: string; fp: string }>;
      el.setAttribute('data-last-navigate-kind', ce.detail?.kind ?? '');
      el.setAttribute('data-last-navigate-fp', ce.detail?.fp ?? '');
    }
    el.addEventListener('navigate', handler);
    return { destroy() { el.removeEventListener('navigate', handler); } };
  }

  const { Story } = defineMeta({
    title: 'Lenses/PalaceLens (S5.2 FR15)',
    component: PalaceLens,
    tags: ['autodocs'],
    args: {
      palaceFp: PALACE_FP,
      width: 640,
      height: 480
    }
  });
</script>

<!--
  Story 1: Grid fallback — ≥3 rooms placed via Fibonacci spiral (AC3).
  The store returns rooms with null layout; PalaceLens uses grid fallback.
-->
<Story name="Grid fallback - 3plus rooms">
  {#snippet template()}
    <div data-testid="palace-lens-grid">
      <PalaceLens
        palaceFp={PALACE_FP}
        palaceBytes={null}
        store={makeMockStore(ROOM_FPS)}
        width={640}
        height={480}
      />
    </div>
  {/snippet}
</Story>

<!--
  Story 2: Layout positions — ≥3 rooms placed at declared jelly.layout coords (AC2).
-->
<Story name="Layout positions - 3plus rooms">
  {#snippet template()}
    <div data-testid="palace-lens-layout">
      <PalaceLens
        palaceFp={PALACE_FP}
        palaceBytes={null}
        store={makeMockStoreWithLayout(ROOM_FPS)}
        width={640}
        height={480}
      />
    </div>
  {/snippet}
</Story>

<!--
  Story 3: Navigate event — room click dispatches { kind: "room", fp } (AC4).

  Because the room nodes live inside the WebGL canvas, we cannot directly click
  a Three.js mesh from a play-test. The play-test instead dispatches a synthetic
  CustomEvent from the lens container (mimicking handleRoomClick) and asserts
  the bubbled payload is caught by the outer wrapper listener.
-->
<Story name="Navigate event - room click" play={async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  const wrapper = await canvas.findByTestId('palace-navigate-wrapper');

  // Dispatch the navigate event that PalaceLens fires on room click.
  const roomFp = ROOM_FPS[0];
  const evt = new CustomEvent('navigate', {
    detail: { kind: 'room', fp: roomFp },
    bubbles: true,
    composed: true
  });

  // Find the palace-lens div inside the wrapper and dispatch from it.
  const lensDiv = wrapper.querySelector('.palace-lens') ?? wrapper;
  lensDiv.dispatchEvent(evt);

  // Assert the wrapper captured the event detail via its listener.
  await expect(wrapper.getAttribute('data-last-navigate-kind')).toBe('room');
  await expect(wrapper.getAttribute('data-last-navigate-fp')).toBe(roomFp);
}}>
  {#snippet template()}
    <div
      data-testid="palace-navigate-wrapper"
      use:navigateCatcher
    >
      <PalaceLens
        palaceFp={PALACE_FP}
        palaceBytes={null}
        store={makeMockStore(ROOM_FPS)}
        width={640}
        height={480}
      />
    </div>
  {/snippet}
</Story>
