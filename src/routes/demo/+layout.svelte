<script lang="ts">
	import type { Snippet } from 'svelte';
	interface Props { children: Snippet; }
	let { children }: Props = $props();
</script>

<nav>
	<a href="/">← DreamBall home</a>
	<a href="/demo/transmission">Transmission</a>
	<a href="/demo/unlock">Unlock</a>
	<a href="/demo/wearer">Wearer</a>
	<a href="/demo/splat">Splat</a>
</nav>

<div class="demo-wrap">
	{@render children()}
</div>

<style>
	nav {
		display: flex;
		gap: 1rem;
		padding: 1rem 2rem;
		background: #0a0e20;
		color: #e8ecf8;
		font-family: system-ui, sans-serif;
	}
	nav a {
		color: #e0b7ff;
		text-decoration: none;
	}
	nav a:hover {
		text-decoration: underline;
	}
	.demo-wrap {
		max-width: 64rem;
		margin: 2rem auto;
		padding: 0 1.5rem;
		color: #e8ecf8;
		font-family: system-ui, sans-serif;
	}
	:global(body) {
		background: #050714;
		margin: 0;
	}
</style>
