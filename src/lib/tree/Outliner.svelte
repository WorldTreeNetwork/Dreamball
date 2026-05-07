<!--
  Outliner — Blender-style hierarchy for the currently-edited DreamBall.
  Phase 0 shows the six-type scaffold + v2 slot surface as a static tree
  with collapsible nodes and keyboard navigation. Selecting a node
  dispatches to the shared Selection context; PropertiesPanel reacts.

  See docs/products/wishing-tree/PHASES.md §5.3 + docs/PROTOCOL.md §12.1.
-->
<script lang="ts">
	import { getContext } from 'svelte';
	import { SELECTION_KEY, type Selection } from './selection.svelte.js';
	import { iconFor } from './icons.js';

	interface Node {
		label: string;
		kind: string;
		detail?: string;
		children?: Node[];
		open?: boolean;
	}

	interface Props {
		dreamType?: 'avatar' | 'agent' | 'tool' | 'relic' | 'field' | 'guild';
		name?: string;
	}

	let { dreamType = 'field', name = 'The Wishing Tree' }: Props = $props();

	const selection = getContext<Selection>(SELECTION_KEY);

	// Build the tree for the current DreamBall type. Static Phase-0 scaffold.
	const tree: Node = $derived({
		label: name,
		kind: dreamType,
		detail: `jelly.dreamball.${dreamType} · rev 0`,
		open: true,
		children: buildScaffold(dreamType)
	});

	function buildScaffold(t: string): Node[] {
		const common: Node[] = [
			{
				label: 'identity',
				kind: 'identity',
				open: true,
				children: [
					{ label: 'fingerprint', kind: 'fingerprint', detail: 'b58:tree_placeholder_fp' },
					{ label: 'genesis-hash', kind: 'genesis-hash', detail: 'b58:tree_placeholder_gh' },
					{ label: 'revision', kind: 'revision', detail: '0' }
				]
			},
			{
				label: 'signatures',
				kind: 'signatures',
				children: [
					{ label: 'ed25519', kind: 'ed25519', detail: 'placeholder · 64B zeros' },
					{ label: 'ml-dsa-87', kind: 'ml-dsa-87', detail: 'placeholder · 4627B zeros' }
				]
			},
			{ label: 'contains (0)', kind: 'contains' },
			{ label: 'derived-from (0)', kind: 'derived-from' }
		];

		const slots: Record<string, Node[]> = {
			avatar: [
				{
					label: 'look',
					kind: 'look',
					open: true,
					children: [
						{ label: 'shader · soulskin', kind: 'shader', detail: '4 layers · canvas v0' },
						{ label: 'mesh · icosphere', kind: 'mesh', detail: 'UV-polar · seam = meridian' },
						{ label: 'graticule · omnispherical', kind: 'graticule', detail: 'res 8 · layer-depth 3' },
						{ label: 'assets (0)', kind: 'asset' },
						{ label: 'preview', kind: 'preview', detail: 'auto-generated thumbnail' }
					]
				},
				{
					label: 'feel',
					kind: 'feel',
					children: [
						{ label: 'personality', kind: 'feel', detail: '—' },
						{ label: 'voice', kind: 'feel', detail: '—' },
						{ label: 'values', kind: 'feel', detail: '[]' },
						{ label: 'tempo', kind: 'feel', detail: '—' }
					]
				}
			],
			agent: [
				{ label: 'look', kind: 'look', children: [{ label: 'assets (0)', kind: 'asset' }] },
				{ label: 'feel', kind: 'feel', children: [{ label: 'personality', kind: 'feel' }] },
				{
					label: 'act',
					kind: 'act',
					open: true,
					children: [
						{ label: 'model', kind: 'model', detail: 'claude-opus-4-7' },
						{ label: 'system-prompt', kind: 'prompt', detail: '—' },
						{ label: 'skills (0)', kind: 'skill' },
						{ label: 'tools (0)', kind: 'tools' },
						{ label: 'scripts (0)', kind: 'script' }
					]
				},
				{ label: 'memory', kind: 'memory', detail: '0 nodes · 0 edges' },
				{ label: 'knowledge-graph', kind: 'knowledge-graph', detail: '0 triples' },
				{ label: 'emotional-register', kind: 'emotional-register', detail: '3 axes' },
				{ label: 'interaction-set', kind: 'interaction-set', detail: '0 turns' },
				{ label: 'personality-master-prompt', kind: 'prompt', detail: '—' },
				{ label: 'secrets (0)', kind: 'secret' }
			],
			tool: [
				{
					label: 'skill',
					kind: 'skill',
					open: true,
					children: [
						{ label: 'name', kind: 'skill', detail: '—' },
						{ label: 'trigger', kind: 'skill', detail: '—' },
						{ label: 'body', kind: 'skill', detail: '—' },
						{ label: 'requires (0)', kind: 'tools' }
					]
				},
				{ label: 'applicable-to', kind: 'skill', detail: '[jelly.dreamball.agent]' }
			],
			relic: [
				{ label: 'sealed-payload-hash', kind: 'sealed', detail: '—' },
				{ label: 'unlock-guild', kind: 'guild', detail: '—' },
				{ label: 'reveal-hint', kind: 'feel', detail: '—' }
			],
			field: [
				{
					label: 'look',
					kind: 'look',
					open: true,
					children: [
						{ label: 'shader · soulskin', kind: 'shader', detail: '4 layers · canvas v0' },
						{ label: 'graticule · omnispherical', kind: 'graticule', detail: 'res 8 · depth 3' }
					]
				},
				{
					label: 'omnispherical-grid',
					kind: 'graticule',
					open: true,
					children: [
						{ label: 'pole-north', kind: 'graticule', detail: '(0, 1, 0)' },
						{ label: 'pole-south', kind: 'graticule', detail: '(0, -1, 0)' },
						{ label: 'camera-ring[3]', kind: 'graticule', detail: '3 cameras · onion-layer' },
						{ label: 'layer-depth', kind: 'graticule', detail: '3' },
						{ label: 'resolution', kind: 'graticule', detail: '8' }
					]
				},
				{ label: 'ambient-palette', kind: 'feel', detail: '3 colours' },
				{ label: 'dream-field-id', kind: 'fingerprint', detail: 'uuid' },
				{ label: 'act (tree agent)', kind: 'act', detail: 'claude-opus-4-7 · invocation.txt' }
			],
			guild: [
				{ label: 'guild-name', kind: 'guild', detail: '—' },
				{ label: 'keyspace-root-hash', kind: 'genesis-hash', detail: '—' },
				{ label: 'members (0)', kind: 'guild' },
				{ label: 'admins (0)', kind: 'guild' },
				{ label: 'policy', kind: 'guild', detail: 'default (public/guild-only/admin-only)' }
			]
		};

		return [...(slots[t] ?? []), ...common];
	}

	function onclick(node: Node, path: string[]) {
		selection.select({ path, label: node.label, kind: node.kind, detail: node.detail });
	}
</script>

{#snippet row(node: Node, depth: number, path: string[])}
	<!-- eslint-disable-next-line svelte/valid-compile -->
	{@const isSel = selection.path.join('/') === path.join('/')}
	<div class="row" class:sel={isSel} style="--depth: {depth};">
		{#if node.children && node.children.length}
			<button
				class="chev"
				type="button"
				aria-expanded={!!node.open}
				onclick={(e) => {
					e.stopPropagation();
					node.open = !node.open;
				}}
			>
				{node.open ? '▼' : '▸'}
			</button>
		{:else}
			<span class="chev-space">·</span>
		{/if}
		<button class="label" type="button" onclick={() => onclick(node, path)}>
			<span class="icon" style="color: var(--wt-fruit-gold);">{iconFor(node.kind)}</span>
			<span class="name">{node.label}</span>
			{#if node.detail}<span class="dim"> — {node.detail}</span>{/if}
		</button>
	</div>
	{#if node.open && node.children}
		{#each node.children as child, i (i + '|' + child.label)}
			{@render row(child, depth + 1, [...path, child.label])}
		{/each}
	{/if}
{/snippet}

<div class="outliner" role="tree" aria-label="DreamBall outliner">
	{@render row(tree, 0, [])}
</div>

<style>
	.outliner {
		font-family: var(--wt-font-mono);
		font-size: 12px;
		color: var(--wt-haze);
		max-height: 50vh;
		overflow: auto;
		padding: 2px;
	}
	.row {
		display: flex;
		align-items: center;
		gap: 2px;
		padding-left: calc(var(--depth, 0) * 14px);
		line-height: 1.5;
		border-left: 2px solid transparent;
	}
	.row.sel {
		background: color-mix(in srgb, var(--wt-fruit-gold) 18%, transparent);
		border-left-color: var(--wt-fruit-gold);
	}
	.chev,
	.chev-space {
		all: unset;
		width: 14px;
		text-align: center;
		color: var(--wt-mist);
		cursor: pointer;
	}
	.chev:hover {
		color: var(--wt-fruit-gold);
	}
	.label {
		all: unset;
		cursor: pointer;
		display: inline-flex;
		align-items: baseline;
		gap: 6px;
		padding: 2px 4px;
		flex: 1;
		min-width: 0;
	}
	.label:hover {
		color: var(--wt-wish-violet);
	}
	.label:focus-visible {
		outline: 2px solid var(--wt-fruit-gold);
		outline-offset: -2px;
	}
	.icon {
		width: 1em;
		display: inline-block;
		text-align: center;
	}
	.name {
		white-space: nowrap;
	}
	.dim {
		color: var(--wt-mist);
		font-size: 11px;
	}
</style>
