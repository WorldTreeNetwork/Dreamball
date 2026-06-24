<!--
  PublishPanel — Phase 4. The Tree publishes the Tree.
  Phase 0 generates a mock JSON DragonBall. Real CBOR-sealed bundle lands
  via the Zig CLI in Phase 3+.
-->
<script lang="ts">
	import type { WishGarden } from './wishes.svelte.js';
	import { downloadTreeBundle } from './dreamball-export.js';
	import { SFX } from './style/sfx.js';

	interface Props {
		garden: WishGarden;
		dreamType: string;
	}
	let { garden, dreamType }: Props = $props();

	let lastPublishedAt: number | null = $state(null);

	function publish() {
		downloadTreeBundle({
			wishes: garden.wishes.length,
			plucks: garden.plucks,
			transmissions: garden.transmissions,
			revision: garden.revision,
			dreamType
		});
		lastPublishedAt = Date.now();
		SFX.start();
	}
</script>

<div class="pub">
	<button class="big" type="button" onclick={publish}>
		▲ PUBLISH TREE → wishing-tree.jelly.json
	</button>
	<div class="meta">
		<span>wishes <strong>{garden.wishes.length}</strong></span>
		<span>plucks <strong>{garden.plucks}</strong></span>
		<span>winds <strong>{garden.transmissions}</strong></span>
		<span>rev <strong>{garden.revision}</strong></span>
	</div>
	{#if lastPublishedAt}
		<p class="stamp">last published: {new Date(lastPublishedAt).toLocaleTimeString()}</p>
	{/if}
	<details class="plant">
		<summary>plant preview · how a recipient grows this</summary>
		<pre class="cmd">$ dreamball unseal wishing-tree.jelly --out tree.cbor
$ dreamball plant tree.cbor
  ▸ scaffolding workspace…
  ▸ unsealing attachments → src/, docs/, scripts/
  ▸ writing package.json (svelte-kit + threlte)
  ▸ writing README from invocation.txt
  ▸ npm install
  ▸ npm run dev
  → http://localhost:5173/tree</pre>
	</details>
</div>

<style>
	.pub {
		font-family: var(--wt-font-mono);
		font-size: 11px;
		color: var(--wt-haze);
	}
	.big {
		all: unset;
		cursor: pointer;
		display: block;
		text-align: center;
		padding: 10px;
		font-size: 12px;
		letter-spacing: 0.25em;
		font-weight: 700;
		background: var(--wt-wish-violet);
		color: var(--wt-void);
		border: 2px solid var(--wt-wish-violet);
		box-shadow:
			inset 1px 1px 0 var(--wt-haze),
			inset -1px -1px 0 var(--wt-void);
		margin-bottom: 8px;
	}
	.big:hover {
		background: var(--wt-blossom);
		border-color: var(--wt-blossom);
	}
	.meta {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: 6px;
		font-size: 10px;
		text-align: center;
		color: var(--wt-mist);
	}
	.meta strong {
		display: block;
		color: var(--wt-fruit-gold);
		font-size: 14px;
	}
	.stamp {
		margin: 6px 0 0;
		color: var(--wt-sap-green);
		font-size: 10px;
		text-align: center;
	}
	details.plant {
		margin-top: 10px;
		font-size: 10px;
	}
	summary {
		cursor: pointer;
		color: var(--wt-frost-cyan);
		letter-spacing: 0.15em;
		padding: 4px 0;
	}
	.cmd {
		background: var(--wt-void);
		color: var(--wt-sap-green);
		padding: 8px;
		border: 1px solid var(--wt-branch);
		font-size: 10px;
		line-height: 1.5;
		margin: 4px 0 0;
		overflow: auto;
	}
</style>
