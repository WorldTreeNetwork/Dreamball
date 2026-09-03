<!--
  DeepDnaInspector — the deepest layer: the envelope bytes themselves.
  Blender has the Python console + BPY inspector for reaching below the UI;
  the Wishing Tree has this — CBOR byte preview, hash tree, signature
  fingerprints. Phase 0 shows a synthesised placeholder; Phase 1 wires it
  to the real `dreamball show --format=bytes`.
-->
<script lang="ts">
	const bytes = buildFakeBytes();
	const hashes = buildFakeHashes();

	function buildFakeBytes(): string[] {
		const seed = 0xb01;
		const rows: string[] = [];
		for (let row = 0; row < 8; row++) {
			let s = (row * 16).toString(16).padStart(4, '0') + '  ';
			for (let col = 0; col < 16; col++) {
				const v = (seed + row * 16 + col) & 0xff;
				s += v.toString(16).padStart(2, '0') + ' ';
				if (col === 7) s += ' ';
			}
			rows.push(s);
		}
		return rows;
	}

	function buildFakeHashes() {
		return [
			{ label: 'envelope (blake3)', value: 'b58:env_placeholder_0000' },
			{ label: 'subject leaf', value: 'b58:leaf_placeholder_0000' },
			{ label: 'look assertion', value: 'b58:look_placeholder_0000' },
			{ label: 'feel assertion', value: 'b58:feel_placeholder_0000' },
			{ label: 'act assertion', value: 'b58:act__placeholder_0000' }
		];
	}

	let tab: 'bytes' | 'hashes' | 'sigs' = $state('bytes');
</script>

<div class="dna">
	<div class="tabs" role="tablist">
		<button class="tab" class:active={tab === 'bytes'} onclick={() => (tab = 'bytes')} role="tab">
			BYTES
		</button>
		<button class="tab" class:active={tab === 'hashes'} onclick={() => (tab = 'hashes')} role="tab">
			HASH TREE
		</button>
		<button class="tab" class:active={tab === 'sigs'} onclick={() => (tab = 'sigs')} role="tab">
			SIGNATURES
		</button>
	</div>

	{#if tab === 'bytes'}
		<pre class="pane hex">{bytes.join('\n')}
(phase 0 · placeholder CBOR · phase 1 wires to `dreamball show --format=bytes`)</pre>
	{:else if tab === 'hashes'}
		<ul class="pane list">
			{#each hashes as h, i (i + '|' + h.label)}
				<li>
					<span class="label">{h.label}</span>
					<span class="v">{h.value}</span>
				</li>
			{/each}
		</ul>
	{:else}
		<div class="pane sigs">
			<div class="sig">
				<span class="label">ed25519 ·</span>
				<span class="bar placeholder">
					<span class="fill"></span>
				</span>
				<span class="status">placeholder (64B zeros)</span>
			</div>
			<div class="sig">
				<span class="label">ml-dsa-87 ·</span>
				<span class="bar placeholder">
					<span class="fill"></span>
				</span>
				<span class="status">placeholder · awaiting liboqs</span>
			</div>
			<p class="hint">
				real dual-signing lands in Phase 3 (World Tree). Every DreamBall exported from Phase 0
				is dev-signed only — verifiers must pass
				<code>allow_mldsa_placeholder</code>.
			</p>
		</div>
	{/if}
</div>

<style>
	.dna {
		font-family: var(--wt-font-mono);
		font-size: 11px;
		color: var(--wt-haze);
	}
	.tabs {
		display: flex;
		gap: 2px;
		margin-bottom: 6px;
	}
	.tab {
		all: unset;
		cursor: pointer;
		padding: 4px 8px;
		font-size: 10px;
		letter-spacing: 0.2em;
		color: var(--wt-mist);
		border: 1px solid var(--wt-branch);
		background: var(--wt-root);
	}
	.tab.active {
		color: var(--wt-fruit-gold);
		border-color: var(--wt-fruit-gold);
		background: color-mix(in srgb, var(--wt-fruit-gold) 10%, transparent);
	}
	.pane {
		border: 1px solid var(--wt-branch);
		padding: 8px;
		background: var(--wt-void);
		color: var(--wt-sap-green);
		overflow: auto;
		max-height: 200px;
	}
	.hex {
		font-size: 10px;
		line-height: 1.35;
		margin: 0;
		white-space: pre;
	}
	.list {
		list-style: none;
		padding: 0;
		margin: 0;
	}
	.list li {
		display: flex;
		justify-content: space-between;
		gap: 10px;
		padding: 3px 0;
		border-bottom: 1px dotted var(--wt-branch);
		font-size: 10px;
	}
	.label {
		color: var(--wt-frost-cyan);
	}
	.v {
		color: var(--wt-sap-green);
		font-size: 10px;
		word-break: break-all;
	}
	.sigs {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.sig {
		display: grid;
		grid-template-columns: 80px 1fr auto;
		gap: 8px;
		align-items: center;
		font-size: 10px;
	}
	.bar {
		position: relative;
		height: 10px;
		background: var(--wt-root);
		border: 1px solid var(--wt-branch);
		display: block;
	}
	.bar .fill {
		display: block;
		width: 40%;
		height: 100%;
		background: repeating-linear-gradient(
			90deg,
			var(--wt-fruit-gold) 0 4px,
			var(--wt-amber) 4px 8px
		);
	}
	.bar.placeholder .fill {
		background: repeating-linear-gradient(
			90deg,
			var(--wt-mist) 0 4px,
			var(--wt-branch) 4px 8px
		);
	}
	.status {
		color: var(--wt-mist);
	}
	.hint {
		font-size: 10px;
		color: var(--wt-wish-violet);
		margin: 4px 0 0;
	}
	code {
		color: var(--wt-frost-cyan);
		background: var(--wt-root);
		padding: 0 4px;
	}
</style>
