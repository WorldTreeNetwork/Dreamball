<!--
  PropertiesPanel — context-sensitive editor for the Outliner's selection.
  Mirrors Blender's Properties Editor / N-panel: shows fields appropriate
  to the kind of the selected item. Phase 0 is read-mostly; Phase 1 makes
  the inputs write-through to the DreamBall envelope.
-->
<script lang="ts">
	import { getContext } from 'svelte';
	import { SELECTION_KEY, type Selection } from './selection.svelte.js';
	import { iconFor } from './icons.js';

	const selection = getContext<Selection>(SELECTION_KEY);

	const fields = $derived(buildFields(selection.kind));

	function buildFields(kind: string): Array<{ k: string; v: string; kind?: 'text' | 'number' | 'color' | 'readonly' }> {
		switch (kind) {
			case 'shader':
				return [
					{ k: 'format', v: 'soulskin.v0 (canvas)' },
					{ k: 'layers', v: '4' },
					{ k: 'layer 1', v: 'chromatic aberration rim' },
					{ k: 'layer 2', v: 'flowing graticule grid' },
					{ k: 'layer 3', v: 'subsurface scattering' },
					{ k: 'layer 4', v: 'fresnel identity edge' }
				];
			case 'mesh':
				return [
					{ k: 'base', v: 'icosphere · subdiv 3' },
					{ k: 'uv', v: 'polar-unwrapped (seam at meridian)' },
					{ k: 'verts', v: '642' },
					{ k: 'tris', v: '1280' }
				];
			case 'graticule':
				return [
					{ k: 'type', v: 'omnispherical-grid' },
					{ k: 'resolution', v: '8' },
					{ k: 'layer-depth', v: '3' },
					{ k: 'camera-rings', v: '3 (onion layers)' },
					{ k: 'float-exception', v: 'yes (v1 no-float rule relaxed · §12.2)' }
				];
			case 'asset':
				return [{ k: 'count', v: '0' }, { k: 'media-types', v: 'drop GLB · PNG · SOG · PLY · TXT' }];
			case 'feel':
				return [
					{ k: 'personality', v: '—' },
					{ k: 'voice', v: '—' },
					{ k: 'values', v: '[]' },
					{ k: 'tempo', v: '—' }
				];
			case 'act':
				return [
					{ k: 'model', v: 'claude-opus-4-7' },
					{ k: 'system-prompt', v: 'see invocation.txt' },
					{ k: 'skills', v: '0' },
					{ k: 'tools', v: '0' }
				];
			case 'model':
				return [
					{ k: 'id', v: 'claude-opus-4-7' },
					{ k: 'cache', v: 'prompt caching enabled' },
					{ k: 'budget', v: 'emotional-register.urgency-gated' }
				];
			case 'prompt':
				return [{ k: 'text', v: 'You are the Wishing Tree. (see invocation.txt)' }];
			case 'memory':
				return [{ k: 'nodes', v: '0' }, { k: 'edges', v: '0' }, { k: 'edge-kinds', v: 'semantic · emotional · temporal' }];
			case 'knowledge-graph':
				return [{ k: 'triples', v: '0' }, { k: 'shape', v: '[subject, predicate, object]' }];
			case 'emotional-register':
				return [
					{ k: 'axes', v: '3' },
					{ k: 'axis 1', v: 'curiosity (0.82 / 0.0–1.0)' },
					{ k: 'axis 2', v: 'warmth (0.55)' },
					{ k: 'axis 3', v: 'urgency (0.10)' }
				];
			case 'interaction-set':
				return [{ k: 'turns', v: '0' }, { k: 'kinds', v: 'speak · listen · act · receive' }];
			case 'fingerprint':
			case 'genesis-hash':
				return [{ k: 'encoding', v: 'b58:{32 bytes blake3}' }, { k: 'value', v: selection.detail || 'b58:tree_placeholder' }];
			case 'revision':
				return [{ k: 'current', v: selection.detail || '0' }, { k: 'rule', v: 'monotonic · bumped on every signed update' }];
			case 'ed25519':
				return [{ k: 'length', v: '64 bytes' }, { k: 'status', v: selection.detail || 'placeholder' }];
			case 'ml-dsa-87':
				return [{ k: 'length', v: '4627 bytes' }, { k: 'status', v: selection.detail || 'placeholder · awaiting liboqs' }];
			case 'secret':
				return [{ k: 'count', v: '0' }, { k: 'storage', v: 'ball.secret-ref · IndexedDB (encrypted)' }];
			case 'field':
			case 'avatar':
			case 'agent':
			case 'tool':
			case 'relic':
			case 'guild':
				return [
					{ k: 'type', v: `ball.dreamball.${kind}` },
					{ k: 'stage', v: 'seed' },
					{ k: 'format-version', v: '2' }
				];
			default:
				return [];
		}
	}
</script>

<div class="props">
	<div class="hdr">
		<span class="icon">{iconFor(selection.kind || 'dreamball')}</span>
		<span class="name">{selection.label}</span>
	</div>
	<div class="path">
		{selection.pathString()}
	</div>
	{#if fields.length === 0}
		<div class="empty">select an item in the outliner.</div>
	{:else}
		<dl class="kv">
			{#each fields as f, i (i + '|' + f.k)}
				<dt>{f.k}</dt>
				<dd>{f.v}</dd>
			{/each}
		</dl>
	{/if}
</div>

<style>
	.props {
		font-family: var(--wt-font-mono);
		font-size: 12px;
		color: var(--wt-haze);
	}
	.hdr {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 13px;
		color: var(--wt-wish-violet);
		padding-bottom: 6px;
		border-bottom: 1px solid var(--wt-branch);
		margin-bottom: 8px;
	}
	.hdr .icon {
		color: var(--wt-fruit-gold);
	}
	.path {
		font-size: 10px;
		letter-spacing: 0.08em;
		color: var(--wt-mist);
		margin-bottom: 10px;
		word-break: break-all;
	}
	.empty {
		color: var(--wt-mist);
		font-style: italic;
	}
	.kv {
		display: grid;
		grid-template-columns: max-content 1fr;
		gap: 4px 10px;
		margin: 0;
	}
	dt {
		color: var(--wt-frost-cyan);
		font-size: 11px;
		letter-spacing: 0.05em;
	}
	dd {
		margin: 0;
		color: var(--wt-haze);
		font-size: 11px;
		word-break: break-word;
	}
</style>
