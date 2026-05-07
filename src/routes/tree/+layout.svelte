<script lang="ts">
	import { paletteToCss } from '$lib/tree/style/palette.js';
	import { FONT_STACK } from '$lib/tree/style/typography.js';
	import '$lib/tree/style/crt.css';

	const style = `${paletteToCss()} --wt-font-mono: ${FONT_STACK.mono}; --wt-font-pixel: ${FONT_STACK.pixel};`;

	let { children } = $props();
</script>

<div class="wt-root" style={style}>
	{@render children?.()}
</div>

<style>
	.wt-root {
		min-height: 100vh;
		background: var(--wt-void);
	}
	:global(html, body) {
		margin: 0;
		padding: 0;
		background: #050714;
		color: #c9d0ff;
		overscroll-behavior: none;
	}
</style>
