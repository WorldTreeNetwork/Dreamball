<!--
  KnowledgeGraphLens stories — force-directed SVG graph of knowledge triples.
  Reviewer cares because this is the primary way to inspect an agent's semantic
  relationships; the textarea control lets a reviewer paste subject,predicate,object
  CSV lines and see the graph update live without rebuilding.
-->
<script module lang="ts">
  import { defineMeta } from '@storybook/addon-svelte-csf';
  import KnowledgeGraphLens from '$lib/lenses/KnowledgeGraphLens.svelte';
  import { mockBall } from '$lib/backend/MockBackend.js';

  function parseTriplesCSV(csv: string): { subject: string; predicate: string; object: string }[] {
    return csv
      .split('\n')
      .map((line: string) => line.trim())
      .filter((line: string) => line.length > 0 && !line.startsWith('#'))
      .map((line: string) => {
        const [subject, predicate, object] = line.split(',').map((s: string) => s.trim());
        return { subject: subject ?? '', predicate: predicate ?? '', object: object ?? '' };
      })
      .filter((t: { subject: string; predicate: string; object: string }) => t.subject && t.predicate && t.object);
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
        description: 'Triples as CSV lines: subject,predicate,object — one per line'
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
          { subject: 'A', predicate: 'links', object: 'B' },
          { subject: 'B', predicate: 'links', object: 'C' },
          { subject: 'C', predicate: 'links', object: 'D' },
          { subject: 'D', predicate: 'links', object: 'A' },
          { subject: 'A', predicate: 'relates', object: 'C' },
          { subject: 'E', predicate: 'depends-on', object: 'B' }
        ]
      }
    })}
    <KnowledgeGraphLens {ball} />
  {/snippet}
</Story>
