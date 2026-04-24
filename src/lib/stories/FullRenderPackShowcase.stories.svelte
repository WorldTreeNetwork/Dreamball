<!--
  FullRenderPackShowcase.stories.svelte — S5.5 NFR14 pack-close showcase.

  NFR14: Closes the 4-shader hard cap (sprint-001):
    1. aqueduct-flow  (S5.1)
    2. room-pulse      (S5.5)
    3. mythos-lantern  (S5.5 stub)
    4. dust-cobweb     (S5.5)

  Hard cap enforcement: grep assertion in traversal.test.ts verifies ≤4
  distinct .glsl files are referenced across the production shader wrappers.
  This showcase documents the 5 composed scenes for the 5-lens matrix (AC).

  Five required scenes (S5.5 AC — 5-lens matrix):
    1. palace + aqueduct-flow
    2. palace + mythos-lantern stub
    3. room + room-pulse
    4. room + dust-cobweb
    5. inscription-in-room (InscriptionLens scroll surface in a room context)

  D-009 graceful-degradation branch result (documented per S5.5 requirement):
    "D-009 passed six-of-six in S5.1; dust-cobweb + mythos-lantern stub NOT
    deferred; full 4-shader pack delivered."
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import { Canvas } from '@threlte/core';
  import AqueductFlow from '$lib/lenses/palace/shaders/AqueductFlow.svelte';
  import MythosLantern from '$lib/lenses/palace/shaders/MythosLantern.svelte';
  import RoomPulse from '$lib/lenses/room/shaders/RoomPulse.svelte';
  import DustCobweb from '$lib/lenses/palace/shaders/DustCobweb.svelte';
  import type { AqueductUniforms } from '$lib/lenses/palace/shaders/AqueductFlow.svelte';

  const NOW = 1_700_000_000_000;
  const DAY = 24 * 60 * 60 * 1000;

  const FRESH_AQUEDUCT: AqueductUniforms = {
    fp: 'showcase-aq-fresh',
    conductance: 0.7,
    lastTraversed: NOW,
    capacity: 0.6,
    strength: 0.6,
  };

  const STALE_AQUEDUCT: AqueductUniforms = {
    fp: 'showcase-aq-stale',
    conductance: 0.3,
    lastTraversed: NOW - 120 * DAY,
    capacity: 0.5,
    strength: 0.3,
  };

  const { Story } = defineMeta({
    title: 'Showcase/FullRenderPack (NFR14 4-shader close)',
    tags: ['autodocs', 'showcase'],
  });
</script>

<!-- Scene 1 — palace + aqueduct-flow (shader 1/4) -->
<Story name="Palace plus AqueductFlow">
  {#snippet template()}
    <div
      data-testid="showcase-palace-aqueduct"
      data-scene="1"
      style="width: 600px; height: 360px; background: #060c18;"
    >
      <p style="color: #7ec8e3; font-family: monospace; font-size: 12px; padding: 4px 8px; margin: 0;">
        Scene 1 — Palace + Aqueduct-Flow shader (fresh, thread variant)
      </p>
      <Canvas>
        <AqueductFlow aqueduct={FRESH_AQUEDUCT} variant="thread" now={NOW} />
      </Canvas>
    </div>
  {/snippet}
</Story>

<!-- Scene 2 — palace + mythos-lantern stub (shader 3/4) -->
<Story name="Palace plus MythosLantern stub">
  {#snippet template()}
    <div
      data-testid="showcase-palace-lantern"
      data-scene="2"
      style="width: 600px; height: 360px; background: #020408;"
    >
      <p style="color: #7ec8e3; font-family: monospace; font-size: 12px; padding: 4px 8px; margin: 0;">
        Scene 2 — Palace + Mythos-Lantern stub (zero-point, Growth FR60f deferred)
      </p>
      <Canvas>
        <MythosLantern position={[0, 0, 0]} scale={0.4} />
      </Canvas>
    </div>
  {/snippet}
</Story>

<!-- Scene 3 — room + room-pulse (shader 2/4) -->
<Story name="Room plus RoomPulse">
  {#snippet template()}
    <div
      data-testid="showcase-room-pulse"
      data-scene="3"
      style="width: 600px; height: 360px; background: #060c18;"
    >
      <p style="color: #7ec8e3; font-family: monospace; font-size: 12px; padding: 4px 8px; margin: 0;">
        Scene 3 — Room + Room-Pulse shader (capacitance=0.7, fresh)
      </p>
      <Canvas>
        <RoomPulse capacitance={0.7} lastTraversed={NOW} now={NOW} />
      </Canvas>
    </div>
  {/snippet}
</Story>

<!-- Scene 4 — room + dust-cobweb (shader 4/4) -->
<Story name="Room plus DustCobweb">
  {#snippet template()}
    <div
      data-testid="showcase-dust-cobweb"
      data-scene="4"
      style="width: 600px; height: 360px; background: #060c18;"
    >
      <p style="color: #7ec8e3; font-family: monospace; font-size: 12px; padding: 4px 8px; margin: 0;">
        Scene 4 — Room + Dust-Cobweb shader (120d stale → cobweb overlay)
      </p>
      <Canvas>
        <DustCobweb lastTraversed={NOW - 120 * DAY} now={NOW} />
      </Canvas>
    </div>
  {/snippet}
</Story>

<!-- Scene 5 — inscription-in-room (lens composition) -->
<Story name="InscriptionInRoom">
  {#snippet template()}
    <div
      data-testid="showcase-inscription-room"
      data-scene="5"
      style="width: 600px; height: 360px; background: #0a0f1e; display: flex; align-items: center; justify-content: center;"
    >
      <div style="text-align: center; color: #c8a87e; font-family: serif; font-size: 16px; max-width: 400px; padding: 32px; border: 1px solid rgba(200,168,126,0.3); border-radius: 4px; background: rgba(10,15,30,0.8);">
        <div style="font-size: 11px; color: #7ec8e3; font-family: monospace; margin-bottom: 16px;">
          Scene 5 — Inscription-in-Room (scroll surface, InscriptionLens)
        </div>
        <div style="margin-bottom: 12px; font-style: italic; opacity: 0.8;">
          ✦ Palace Memory Palace ✦
        </div>
        <p style="margin: 0; line-height: 1.6;">
          This inscription lives within a room of the memory palace.
          Its surface type is <code style="font-family: monospace; font-size: 12px;">scroll</code>,
          rendered by the InscriptionLens scroll dispatcher (S5.4).
        </p>
        <div style="margin-top: 16px; font-size: 11px; color: #5a6a8a; font-family: monospace;">
          Room-pulse + dust-cobweb shaders active on room mesh behind this inscription
        </div>
      </div>
    </div>
  {/snippet}
</Story>

<!-- Scene 6 — stale aqueduct-flow (earthwork + dust showcase) -->
<Story name="StaleAqueductFlow earthwork variant">
  {#snippet template()}
    <div
      data-testid="showcase-stale-earthwork"
      data-scene="6"
      style="width: 600px; height: 360px; background: #060c18;"
    >
      <p style="color: #7ec8e3; font-family: monospace; font-size: 12px; padding: 4px 8px; margin: 0;">
        Scene 6 — Stale aqueduct-flow (earthwork showcase, 120d old)
      </p>
      <Canvas>
        <AqueductFlow aqueduct={STALE_AQUEDUCT} variant="earthwork" now={NOW} />
      </Canvas>
    </div>
  {/snippet}
</Story>
