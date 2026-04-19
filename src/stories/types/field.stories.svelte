<!--
  Field type tour — shows a jelly.dreamball.field in every applicable lens.
  Meaningful lenses: thumbnail (field chip), omnispherical (the primary field lens —
  concentric wire spheres representing the graticule), flat (grid + palette slots), phone.
  Skipped: avatar/splat (no look asset), knowledge-graph (no triples),
  emotional-state (no register).
  Reviewer cares because field is the "space" type that defines the 3D arena;
  the omnispherical lens is its canonical representation and must render without errors.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import ThumbnailLens from '$lib/lenses/ThumbnailLens.svelte';
  import OmnisphericalLens from '$lib/lenses/OmnisphericalLens.svelte';
  import FlatLens from '$lib/lenses/FlatLens.svelte';
  import PhoneLens from '$lib/lenses/PhoneLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const { Story } = defineMeta({
    title: 'Types/Field',
    tags: ['autodocs']
  });

  const ball = mockBall('field', { name: 'Dream Field Alpha' });
</script>

<Story name="All Lenses Grid">
  {#snippet template(args)}
    <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1.5rem; padding: 1rem; background: #050810;">
      <div>
        <p style="color: #aac; font-family: monospace; font-size: 0.75rem; margin: 0 0 0.5rem;">thumbnail</p>
        <ThumbnailLens {ball} />
      </div>
      <div>
        <p style="color: #aac; font-family: monospace; font-size: 0.75rem; margin: 0 0 0.5rem;">omnispherical</p>
        <div style="height: 320px;">
          <OmnisphericalLens {ball} />
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

<Story name="Omnispherical Only">
  {#snippet template(args)}
    <div style="width: 480px; height: 360px;">
      <OmnisphericalLens {ball} />
    </div>
  {/snippet}
</Story>
