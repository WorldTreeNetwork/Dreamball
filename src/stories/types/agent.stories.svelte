<!--
  Agent type tour — shows a jelly.dreamball.agent in every applicable lens.
  Meaningful lenses: all 8 — agent has look (avatar/splat), knowledge-graph triples,
  emotional-register axes, personality-master-prompt (flat), phone, omnispherical (if grid present).
  Skipped: splat (base mock uses gltf, not sog), omnispherical (agent has no grid by default).
  Reviewer cares because agent is the richest DreamBall type and is the primary
  focus of persona + knowledge rendering — all cognitive lenses must handle it cleanly.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import ThumbnailLens from '$lib/lenses/ThumbnailLens.svelte';
  import AvatarLens from '$lib/lenses/AvatarLens.svelte';
  import KnowledgeGraphLens from '$lib/lenses/KnowledgeGraphLens.svelte';
  import EmotionalStateLens from '$lib/lenses/EmotionalStateLens.svelte';
  import FlatLens from '$lib/lenses/FlatLens.svelte';
  import PhoneLens from '$lib/lenses/PhoneLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  const { Story } = defineMeta({
    title: 'Types/Agent',
    tags: ['autodocs']
  });

  const ball = mockBall('agent', { name: 'Curiosity Agent' });
</script>

<Story name="All Lenses Grid">
  {#snippet template(args)}
    <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1.5rem; padding: 1rem; background: #050810;">
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
        <p style="color: #aac; font-family: monospace; font-size: 0.75rem; margin: 0 0 0.5rem;">knowledge-graph</p>
        <KnowledgeGraphLens {ball} />
      </div>
      <div>
        <p style="color: #aac; font-family: monospace; font-size: 0.75rem; margin: 0 0 0.5rem;">emotional-state</p>
        <EmotionalStateLens {ball} />
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
