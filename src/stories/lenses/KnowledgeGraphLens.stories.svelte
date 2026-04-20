<!--
  KnowledgeGraphLens stories — force-directed SVG graph of knowledge triples.
  Reviewer cares because this is the primary way to inspect an agent's semantic
  relationships; the textarea control lets a reviewer paste from,label,to
  CSV lines and see the graph update live without rebuilding.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import KnowledgeGraphLens from '$lib/lenses/KnowledgeGraphLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  function parseTriplesCSV(csv: string): { from: string; label: string; to: string }[] {
    return csv
      .split('\n')
      .map((line: string) => line.trim())
      .filter((line: string) => line.length > 0 && !line.startsWith('#'))
      .map((line: string) => {
        const [from, label, to] = line.split(',').map((s: string) => s.trim());
        return { from: from ?? '', label: label ?? '', to: to ?? '' };
      })
      .filter((t: { from: string; label: string; to: string }) => t.from && t.label && t.to);
  }

  const defaultTriples = `curiosity,inclines-toward,new-things
haiku,requires,5-7-5 syllables
creativity,feeds,curiosity
simplicity,enables,clarity`;

  const { Story } = defineMeta({
    title: 'Lenses/KnowledgeGraphLens',
    component: KnowledgeGraphLens,
    tags: ['autodocs'],
    render: template,
    argTypes: {
      triplesCSV: {
        control: 'text',
        description: 'Triples as CSV lines: from,label,to — one per line'
      }
    },
    args: {
      triplesCSV: defaultTriples
    }
  });
</script>

{#snippet template(args: { triplesCSV: string })}
  {@const ball = mockBall('agent', {
    'knowledge-graph': { triples: parseTriplesCSV(args.triplesCSV) }
  })}
  <KnowledgeGraphLens {ball} />
{/snippet}

<Story name="Default" args={{ triplesCSV: defaultTriples }} />

<Story name="Empty Graph">
  {#snippet template(args)}
    {@const ball = mockBall('agent', { 'knowledge-graph': { triples: [] } })}
    <KnowledgeGraphLens {ball} />
  {/snippet}
</Story>

<Story name="Dense Graph">
  {#snippet template(args)}
    {@const ball = mockBall('agent', {
      'knowledge-graph': {
        triples: [
          { from: 'A', label: 'links', to: 'B' },
          { from: 'B', label: 'links', to: 'C' },
          { from: 'C', label: 'links', to: 'D' },
          { from: 'D', label: 'links', to: 'A' },
          { from: 'A', label: 'relates', to: 'C' },
          { from: 'E', label: 'depends-on', to: 'B' }
        ]
      }
    })}
    <KnowledgeGraphLens {ball} />
  {/snippet}
</Story>
