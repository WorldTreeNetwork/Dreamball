<!--
  Avatar type tour — shows a jelly.dreamball.avatar in every applicable lens.
  Meaningful lenses: thumbnail (listing), avatar (3D visual), flat (slot dump), phone (mobile).
  Skipped: knowledge-graph (no triples on avatar), emotional-state (no emotional-register),
  omnispherical (no grid), splat (no splat asset on base mock).
  Reviewer cares because avatar is the human-representation type and visual fidelity
  of the 3D icosahedron placeholder matters before real mesh loading ships.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import ThumbnailLens from '$lib/lenses/ThumbnailLens.svelte';
  import AvatarLens from '$lib/lenses/AvatarLens.svelte';
  import FlatLens from '$lib/lenses/FlatLens.svelte';
  import PhoneLens from '$lib/lenses/PhoneLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const { Story } = defineMeta({
    title: 'Types/Avatar',
    tags: ['autodocs']
  });

  const ball = mockBall('avatar', { name: 'Hummingbird Avatar' });
</script>

<Story name="All Lenses Grid">
  {#snippet template(args)}
    <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 1.5rem; padding: 1rem; background: #050810;">
      <div>
        <p style="color: #aac; font-family: monospace; font-size: 0.75rem; margin: 0 0 0.5rem;">thumbnail</p>
        <ThumbnailLens {ball} />
      </div>
      <div>
        <p style="color: #aac; font-family: monospace; font-size: 0.75rem; margin: 0 0 0.5rem;">avatar (3D)</p>
        <div style="height: 280px;">
          <AvatarLens {ball} />
        </div>
      </div>
      <div>
        <p style="color: #aac; font-family: monospace; font-size: 0.75rem; margin: 0 0 0.5rem;">flat</p>
        <FlatLens {ball} />
      </div>
      <div>
        <p style="color: #aac; font-family: monospace; font-size: 0.75rem; margin: 0 0 0.5rem;">phone</p>
        <PhoneLens {ball} />
      </div>
    </div>
  {/snippet}
</Story>

<Story name="Thumbnail Only">
  {#snippet template(args)}
    <ThumbnailLens {ball} />
  {/snippet}
</Story>
