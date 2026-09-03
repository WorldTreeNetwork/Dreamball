<!--
  IntroSequence — retro 8-bit boot-up before the composer loads.
  Typewriter boot lines, blinking "PRESS START TO DREAM", then the tree
  breathes into view. Click or any key advances.
-->
<script lang="ts">
	import { SFX, unmute } from './style/sfx.js';

	interface Props {
		onready?: () => void;
	}
	let { onready }: Props = $props();

	const lines: string[] = [
		'WISHING TREE  v0.0.1  (c) 2026 dreambals',
		'MEM CHECK ............. OK',
		'ALLOC SOULSKIN ........ OK  [4 LAYERS]',
		'MOUNT ROOT ZONE ....... OK  [VAULT SEALED]',
		'GRAPTICULE RESOLUTION . 8',
		'LENS STACK ............ 8 / 8',
		'PHASES LOADED ......... 0 / 4',
		'',
		'the sphere breathes. it waits.',
		''
	];

	let visible = $state<string[]>([]);
	let ready = $state(false);
	let cursorOn = $state(true);

	$effect(() => {
		let i = 0;
		const iv = setInterval(() => {
			if (i >= lines.length) {
				clearInterval(iv);
				ready = true;
				return;
			}
			visible = [...visible, lines[i]];
			SFX.tick();
			i++;
		}, 120);
		const blink = setInterval(() => (cursorOn = !cursorOn), 500);
		return () => {
			clearInterval(iv);
			clearInterval(blink);
		};
	});

	function advance() {
		if (!ready) {
			visible = [...lines];
			ready = true;
			return;
		}
		unmute();
		SFX.start();
		onready?.();
	}

	function onKey(e: KeyboardEvent) {
		if (e.key === 'Enter' || e.key === ' ' || e.key === 'Escape') {
			e.preventDefault();
			advance();
		}
	}
</script>

<svelte:window onkeydown={onKey} />

<div
	class="boot"
	role="button"
	tabindex="0"
	aria-label="Press Start to Dream"
	onclick={advance}
	onkeydown={onKey}
>
	<div class="scanlines" aria-hidden="true"></div>
	<div class="inner">
		<pre class="ascii" aria-hidden="true">{`
      /\\
     /▓▓\\
    /▓▓▓▓\\
   /▓▓✦▓▓▓\\         T H E   W I S H I N G   T R E E
  /▓▓▓光▓▓▓\\
 /▓▓▓▓▓▓▓▓▓▓\\       >>> INSERT COIN TO DREAM <<<
/____________\\
     ▓▓▓
`}</pre>
		<div class="log" role="log" aria-live="polite">
			{#each visible as line, i (i + '|' + line)}
				<div class="line">&gt; {line}</div>
			{/each}
		</div>
		{#if ready}
			<div class="start" class:blink={cursorOn}>
				▶ PRESS START TO DREAM ◀
			</div>
		{:else}
			<div class="start muted">loading…</div>
		{/if}
	</div>
</div>

<style>
	.boot {
		position: fixed;
		inset: 0;
		background: var(--wt-void);
		color: var(--wt-sap-green);
		font-family: var(--wt-font-mono);
		display: grid;
		place-items: center;
		z-index: 200;
		cursor: pointer;
		padding: 2rem;
	}
	.boot:focus-visible {
		outline: 2px dashed var(--wt-fruit-gold);
		outline-offset: -12px;
	}
	.inner {
		max-width: 640px;
		width: 100%;
	}
	.ascii {
		color: var(--wt-fruit-gold);
		font-size: 14px;
		line-height: 1.1;
		margin: 0 0 24px;
		text-shadow: 0 0 12px rgba(255, 224, 102, 0.25);
	}
	.log {
		margin-bottom: 24px;
	}
	.line {
		font-size: 13px;
		line-height: 1.5;
		color: var(--wt-sap-green);
		text-shadow: 0 0 8px rgba(156, 255, 107, 0.3);
	}
	.start {
		text-align: center;
		font-size: 16px;
		letter-spacing: 0.3em;
		color: var(--wt-wish-violet);
		margin-top: 16px;
		text-shadow: 0 0 14px rgba(224, 183, 255, 0.5);
	}
	.blink {
		animation: wt-blink 1s step-start infinite;
	}
	.muted {
		color: var(--wt-mist);
	}
	@keyframes wt-blink {
		50% {
			opacity: 0;
		}
	}
	.scanlines {
		position: absolute;
		inset: 0;
		pointer-events: none;
		background: repeating-linear-gradient(
			to bottom,
			rgba(0, 0, 0, 0) 0,
			rgba(0, 0, 0, 0) 2px,
			rgba(0, 0, 0, 0.25) 2px,
			rgba(0, 0, 0, 0.25) 3px
		);
		mix-blend-mode: multiply;
	}
	@media (prefers-reduced-motion: reduce) {
		.blink {
			animation: none;
		}
	}
</style>
