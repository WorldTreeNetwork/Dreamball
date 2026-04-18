<!--
  FlatLens — the universal fallback. A structured 2D card showing every
  slot that's present. Works for every type; used especially for Tool
  and Transmission-receipt views where a 3D scene makes no sense.
-->
<script lang="ts">
	import type { DreamBall } from '../generated/types.js';

	interface Props {
		ball: DreamBall;
	}
	let { ball }: Props = $props();

	// Build a flat key → summary table from the DreamBall.
	const rows = $derived.by(() => {
		const out: Array<{ key: string; value: string }> = [];
		const push = (k: string, v: unknown) => {
			if (v === undefined || v === null) return;
			out.push({ key: k, value: typeof v === 'string' ? v : JSON.stringify(v) });
		};
		push('type', ball.type);
		push('stage', ball.stage);
		push('format-version', ball['format-version']);
		push('identity', ball.identity);
		push('genesis-hash', ball['genesis-hash']);
		push('revision', ball.revision);
		push('name', ball.name);
		push('created', ball.created);
		push('updated', ball.updated);
		push('note', ball.note);
		push('personality-master-prompt', ball['personality-master-prompt']);
		push('guild-name', ball['guild-name']);
		push('sealed-payload-hash', ball['sealed-payload-hash']);
		push('unlock-guild', ball['unlock-guild']);
		push('reveal-hint', ball['reveal-hint']);
		push('skill', ball.skill);
		push('guild', ball.guild);
		push('contains', ball.contains);
		push('derived-from', ball['derived-from']);
		return out;
	});
</script>

<section class="flat">
	<dl>
		{#each rows as row (row.key)}
			<dt>{row.key}</dt>
			<dd>{row.value}</dd>
		{/each}
	</dl>
</section>

<style>
	.flat {
		background: #0b1020;
		color: #e8ecf8;
		border-radius: 1rem;
		padding: 1rem 1.25rem;
		font-family: system-ui, sans-serif;
	}
	dl {
		display: grid;
		grid-template-columns: minmax(auto, 15ch) 1fr;
		gap: 0.3rem 1rem;
		margin: 0;
	}
	dt {
		font-family: ui-monospace, Menlo, monospace;
		opacity: 0.6;
		font-size: 0.85rem;
	}
	dd {
		margin: 0;
		word-break: break-word;
		font-size: 0.9rem;
	}
</style>
