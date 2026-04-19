<!--
  Guild type tour — shows a jelly.dreamball.guild in every applicable lens.
  Meaningful lenses: thumbnail (guild chip), flat (guild-name, keyspace-root-hash,
  member list, policy slots), phone.
  Skipped: avatar/splat (no look), knowledge-graph (no triples by default),
  emotional-state (no register), omnispherical (no grid).
  Reviewer cares because guild is the trust-boundary type; the flat lens must render
  the full policy table (public/guild-only/admin-only) and member fingerprints legibly.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import ThumbnailLens from '$lib/lenses/ThumbnailLens.svelte';
  import FlatLens from '$lib/lenses/FlatLens.svelte';
  import PhoneLens from '$lib/lenses/PhoneLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const { Story } = defineMeta({
    title: 'Types/Guild',
    tags: ['autodocs']
  });

  const ball = mockBall('guild', { name: 'The Hummingbirds' });
</script>

<Story name="All Lenses Grid">
  {#snippet template(args)}
    <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 1.5rem; padding: 1rem; background: #050810;">
      <div>
        <p style="color: #aac; font-family: monospace; font-size: 0.75rem; margin: 0 0 0.5rem;">thumbnail</p>
        <ThumbnailLens {ball} />
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
