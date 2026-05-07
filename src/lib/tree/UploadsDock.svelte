<!--
  UploadsDock — drop-zone for authoring payloads. Files become
  `jelly.asset` envelopes attached to the current DreamBall's `look`
  (visual) or `act.script` (executable) slot based on media type.
  Phase 0 accepts files into a local staging list; no envelope write yet.
-->
<script lang="ts">
	import { iconFor } from './icons.js';

	interface Staged {
		name: string;
		size: number;
		type: string;
		bucket: 'look' | 'act' | 'memory' | 'unknown';
	}

	let staged: Staged[] = $state([]);
	let dragging: boolean = $state(false);

	function classify(type: string, name: string): Staged['bucket'] {
		const t = type || '';
		const n = name.toLowerCase();
		if (t.startsWith('model/') || n.endsWith('.glb') || n.endsWith('.gltf') || n.endsWith('.ply') || n.endsWith('.sog'))
			return 'look';
		if (t.startsWith('image/')) return 'look';
		if (n.endsWith('.py') || n.endsWith('.js') || n.endsWith('.ts') || n.endsWith('.wasm')) return 'act';
		if (n.endsWith('.json') || n.endsWith('.txt') || n.endsWith('.md')) return 'memory';
		return 'unknown';
	}

	function accept(files: FileList | null) {
		if (!files) return;
		const arr: Staged[] = [];
		for (let i = 0; i < files.length; i++) {
			const f = files[i];
			arr.push({ name: f.name, size: f.size, type: f.type, bucket: classify(f.type, f.name) });
		}
		staged = [...staged, ...arr];
	}

	function onDrop(e: DragEvent) {
		e.preventDefault();
		dragging = false;
		accept(e.dataTransfer?.files ?? null);
	}
	function onDragOver(e: DragEvent) {
		e.preventDefault();
		dragging = true;
	}
	function onDragLeave() {
		dragging = false;
	}

	function prettySize(b: number): string {
		if (b < 1024) return b + ' B';
		if (b < 1024 * 1024) return (b / 1024).toFixed(1) + ' K';
		return (b / 1024 / 1024).toFixed(1) + ' M';
	}
</script>

<div
	class="dock"
	class:dragging
	role="region"
	aria-label="Uploads drop zone"
	ondrop={onDrop}
	ondragover={onDragOver}
	ondragleave={onDragLeave}
>
	<label class="zone">
		<input
			type="file"
			multiple
			onchange={(e) => accept((e.currentTarget as HTMLInputElement).files)}
		/>
		<span class="zone-inner">
			<span class="big">▽</span>
			<span class="prompt">DROP · GLB · PNG · SOG · PY · MD</span>
			<span class="sub">or click to browse · phase 0 stages locally</span>
		</span>
	</label>
	{#if staged.length}
		<ul class="staged">
			{#each staged as f, i (i + '|' + f.name)}
				<li>
					<span class="icon">{iconFor(f.bucket === 'look' ? 'asset' : f.bucket === 'act' ? 'script' : 'file')}</span>
					<span class="fname">{f.name}</span>
					<span class="bucket">→ {f.bucket}</span>
					<span class="fsize">{prettySize(f.size)}</span>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.dock {
		font-family: var(--wt-font-mono);
		font-size: 11px;
		color: var(--wt-haze);
	}
	.zone {
		display: block;
		border: 2px dashed var(--wt-branch);
		padding: 14px 8px;
		text-align: center;
		cursor: pointer;
		background: color-mix(in srgb, var(--wt-void) 70%, transparent);
	}
	.dragging .zone,
	.zone:hover {
		border-color: var(--wt-fruit-gold);
		background: color-mix(in srgb, var(--wt-fruit-gold) 6%, transparent);
	}
	.zone input {
		display: none;
	}
	.zone-inner {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.big {
		font-size: 24px;
		color: var(--wt-fruit-gold);
	}
	.prompt {
		letter-spacing: 0.2em;
		color: var(--wt-frost-cyan);
	}
	.sub {
		color: var(--wt-mist);
		font-size: 10px;
	}
	.staged {
		list-style: none;
		padding: 0;
		margin: 10px 0 0;
	}
	.staged li {
		display: grid;
		grid-template-columns: 16px 1fr auto auto;
		gap: 8px;
		align-items: baseline;
		padding: 3px 0;
		border-bottom: 1px dotted var(--wt-branch);
	}
	.icon {
		color: var(--wt-sap-green);
	}
	.bucket {
		color: var(--wt-wish-violet);
	}
	.fsize {
		color: var(--wt-mist);
	}
</style>
