<!--
  PeelLayer — reveal interior overlay. Phase 0: placeholder node list.
  Right-click the sphere to trigger `open = true`.
  See docs/products/wishing-tree/PHASES.md §2.2.
-->
<script lang="ts">
	import type { Snippet } from 'svelte';
	import { SFX } from '../style/sfx.js';

	interface Props {
		open: boolean;
		title?: string;
		children?: Snippet;
		onclose?: () => void;
	}

	let { open = $bindable(false), title = 'INTERIOR', children, onclose }: Props = $props();

	function close() {
		open = false;
		onclose?.();
		SFX.peel();
	}

	$effect(() => {
		if (open) SFX.peel();
	});
</script>

{#if open}
	<div
		class="peel-backdrop"
		role="presentation"
		onclick={close}
		onkeydown={(e) => e.key === 'Escape' && close()}
	>
		<div
			class="peel"
			role="dialog"
			tabindex="-1"
			aria-label={title}
			onclick={(e) => e.stopPropagation()}
			onkeydown={(e) => e.stopPropagation()}
		>
			<div class="peel-hdr">
				<span class="peel-title">◉ {title}</span>
				<button class="close" type="button" onclick={close} aria-label="close">✕</button>
			</div>
			<div class="peel-body">
				{#if children}
					{@render children()}
				{:else}
					<ul class="tree-list">
						<li>├─ model.glb <span class="muted">(placeholder)</span></li>
						<li>├─ material.json <span class="muted">(soulskin v0)</span></li>
						<li>├─ textures/ <span class="muted">—</span></li>
						<li>├─ script.py <span class="muted">—</span></li>
						<li>└─ manifest.json <span class="muted">(unsigned)</span></li>
					</ul>
					<p class="hint">Phase 0: interior is a stub. Editable tree arrives Phase 1.</p>
				{/if}
			</div>
		</div>
	</div>
{/if}

<style>
	.peel-backdrop {
		position: fixed;
		inset: 0;
		background: color-mix(in srgb, var(--wt-void) 80%, transparent);
		backdrop-filter: blur(6px);
		display: grid;
		place-items: center;
		z-index: 100;
		animation: wt-fade 0.2s ease-out;
	}
	.peel {
		width: min(560px, 92vw);
		background: var(--wt-root);
		border: 1px solid var(--wt-fruit-gold);
		box-shadow:
			0 0 0 2px var(--wt-void),
			0 0 48px rgba(255, 224, 102, 0.15);
		color: var(--wt-haze);
		font-family: var(--wt-font-mono);
	}
	.peel-hdr {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 8px 12px;
		background: linear-gradient(180deg, var(--wt-branch), var(--wt-trunk));
		border-bottom: 1px solid var(--wt-fruit-gold);
		text-transform: uppercase;
		letter-spacing: 0.15em;
		font-size: 11px;
		color: var(--wt-fruit-gold);
	}
	.close {
		all: unset;
		cursor: pointer;
		color: var(--wt-mist);
		padding: 2px 6px;
	}
	.close:hover {
		color: var(--wt-alarm);
	}
	.peel-body {
		padding: 14px 16px;
		font-size: 12px;
	}
	.tree-list {
		list-style: none;
		padding: 0;
		margin: 0 0 10px;
		line-height: 1.7;
		color: var(--wt-haze);
	}
	.muted {
		color: var(--wt-mist);
	}
	.hint {
		color: var(--wt-wish-violet);
		font-size: 11px;
		margin: 0;
	}
	@keyframes wt-fade {
		from {
			opacity: 0;
		}
		to {
			opacity: 1;
		}
	}
</style>
