<!--
  ThumbnailLens — the smallest-surface card. Shows type, name, and the
  fingerprint short form. Works for every DreamBall type; always public.
-->
<script lang="ts">
	import type { DreamBall } from '../generated/types.js';

	interface Props {
		ball: DreamBall;
	}
	let { ball }: Props = $props();

	const typeTag = $derived(
		ball.type === 'jelly.dreamball'
			? 'untyped'
			: ball.type.replace('jelly.dreamball.', '')
	);
	const fpShort = $derived(ball.identity.slice(4, 14));
</script>

<article class="thumb" data-type={typeTag}>
	<header>
		<span class="chip">{typeTag}</span>
	</header>
	<h3>{ball.name ?? '(unnamed)'}</h3>
	<p class="fp" title={ball.identity}>{fpShort}…</p>
	<footer>rev {ball.revision}</footer>
</article>

<style>
	.thumb {
		border-radius: 0.75rem;
		background: linear-gradient(145deg, #1a2240, #0b1020);
		color: #e8ecf8;
		padding: 0.9rem 1rem 0.7rem;
		width: 15rem;
		min-height: 9rem;
		display: grid;
		grid-template-rows: auto 1fr auto;
		gap: 0.25rem;
		font-family: system-ui, sans-serif;
		box-shadow: 0 10px 20px rgba(0, 0, 0, 0.25);
	}
	.thumb[data-type='agent'] {
		background: linear-gradient(145deg, #2a1040, #120820);
	}
	.thumb[data-type='tool'] {
		background: linear-gradient(145deg, #103a30, #071a14);
	}
	.thumb[data-type='relic'] {
		background: linear-gradient(145deg, #402020, #1a0a0a);
	}
	.thumb[data-type='field'] {
		background: linear-gradient(145deg, #102040, #050a20);
	}
	.thumb[data-type='guild'] {
		background: linear-gradient(145deg, #403a10, #1c1a05);
	}
	.chip {
		text-transform: uppercase;
		font-size: 0.65rem;
		letter-spacing: 0.1em;
		opacity: 0.7;
	}
	h3 {
		font-size: 1.1rem;
		margin: 0.2rem 0 0;
		font-weight: 600;
	}
	.fp {
		font-family: ui-monospace, Menlo, monospace;
		opacity: 0.6;
		font-size: 0.8rem;
		margin: 0;
	}
	footer {
		font-size: 0.7rem;
		opacity: 0.5;
	}
</style>
