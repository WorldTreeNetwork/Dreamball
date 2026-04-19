<!--
  Tool type tour — shows a jelly.dreamball.tool in every applicable lens.
  Meaningful lenses: thumbnail (skill name + type chip), flat (slot dump showing
  skill.name, skill.trigger, applicable-to), phone (mobile listing).
  Skipped: avatar/splat (no look on tool), knowledge-graph (no triples),
  emotional-state (no register), omnispherical (no grid).
  Reviewer cares because tools are the transmittable capability unit;
  the flat lens must render skill.trigger and applicable-to without wrapping.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import ThumbnailLens from '$lib/lenses/ThumbnailLens.svelte';
  import FlatLens from '$lib/lenses/FlatLens.svelte';
  import PhoneLens from '$lib/lenses/PhoneLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const { Story } = defineMeta({
    title: 'Types/Tool',
    tags: ['autodocs']
  });

  const ball = mockBall('tool', { name: 'Haiku Composer' });
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
