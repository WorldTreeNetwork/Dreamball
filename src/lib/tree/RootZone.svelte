<!--
  RootZone — south-pole API key vault UI. Phase 1.
  Keys are wrapped client-side via a passphrase-derived key (mocked here as
  a hash); raw key text is never stored. The list shows wrapped tendrils.

  ⚠ TODO-CRYPTO: real implementation uses Argon2id passphrase + AES-GCM
  wrap, persisted only via IndexedDB encrypted blobs, surfaced as
  ball.secret-ref envelopes whose locator points at the local store.
-->
<script lang="ts">
	import { iconFor } from './icons.js';

	interface KeyTendril {
		id: string;
		provider: 'anthropic' | 'openai' | 'huggingface' | 'replicate' | 'custom';
		label: string;
		fingerprint: string;
		createdAt: number;
		usage: number;
	}

	let tendrils: KeyTendril[] = $state([]);
	let provider: KeyTendril['provider'] = $state('anthropic');
	let label: string = $state('');
	let pass: string = $state('');
	let raw: string = $state('');

	function fakeWrap(s: string): string {
		// not real — visualises a wrapped fingerprint deterministically.
		let h = 0x9e3779b9;
		for (let i = 0; i < s.length; i++) h = ((h * 0x01000193) ^ s.charCodeAt(i)) >>> 0;
		const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
		let v = h;
		let s2 = '';
		for (let i = 0; i < 16; i++) {
			s2 += alphabet[v & 31];
			v = (v >>> 5) | (v << 27);
		}
		return 'wrap:' + s2;
	}

	function add() {
		if (!raw.trim() || !label.trim()) return;
		const t: KeyTendril = {
			id: 'kt-' + Math.random().toString(36).slice(2, 8),
			provider,
			label: label.trim(),
			fingerprint: fakeWrap((pass || 'no-pass') + ':' + raw),
			createdAt: Date.now(),
			usage: 0
		};
		tendrils = [t, ...tendrils];
		raw = '';
		pass = '';
		label = '';
	}

	function remove(id: string) {
		tendrils = tendrils.filter((t) => t.id !== id);
	}

	function bump(id: string) {
		tendrils = tendrils.map((t) => (t.id === id ? { ...t, usage: t.usage + 1 } : t));
	}

	function providerHue(p: KeyTendril['provider']): string {
		return {
			anthropic: 'var(--wt-fruit-gold)',
			openai: 'var(--wt-frost-cyan)',
			huggingface: 'var(--wt-wish-violet)',
			replicate: 'var(--wt-sap-green)',
			custom: 'var(--wt-mist)'
		}[p];
	}
</script>

<div class="rootzone">
	<div class="banner" aria-hidden="true">⚠ ROOT · keys wrapped only · raw text is never persisted</div>
	<form
		class="form"
		onsubmit={(e) => {
			e.preventDefault();
			add();
		}}
	>
		<select bind:value={provider} aria-label="provider">
			<option value="anthropic">ANTHROPIC</option>
			<option value="openai">OPENAI</option>
			<option value="huggingface">HUGGINGFACE</option>
			<option value="replicate">REPLICATE</option>
			<option value="custom">CUSTOM</option>
		</select>
		<input bind:value={label} placeholder="label (e.g. main / dev)" />
		<input bind:value={pass} placeholder="passphrase" type="password" />
		<input bind:value={raw} placeholder="key (hidden, wrapped on add)" type="password" />
		<button type="submit">ADD ROOT</button>
	</form>
	<ul class="tendrils">
		{#each tendrils as t (t.id)}
			<li class="tendril" style="--clr: {providerHue(t.provider)}">
				<span class="root-icon">{iconFor('secret')}</span>
				<span class="info">
					<span class="lbl">{t.label}</span>
					<span class="prov">{t.provider}</span>
					<span class="fp">{t.fingerprint}</span>
				</span>
				<span class="usage" title="usage">{t.usage}×</span>
				<button class="mini" type="button" onclick={() => bump(t.id)}>USE</button>
				<button class="mini danger" type="button" onclick={() => remove(t.id)}>✕</button>
			</li>
		{:else}
			<li class="empty">no roots planted yet.</li>
		{/each}
	</ul>
</div>

<style>
	.rootzone {
		font-family: var(--wt-font-mono);
		font-size: 11px;
		color: var(--wt-haze);
	}
	.banner {
		background: repeating-linear-gradient(
			-45deg,
			var(--wt-amber) 0 8px,
			var(--wt-void) 8px 16px
		);
		color: var(--wt-void);
		font-weight: 700;
		text-align: center;
		padding: 4px 6px;
		font-size: 9px;
		letter-spacing: 0.2em;
		border: 2px solid var(--wt-amber);
		margin-bottom: 8px;
	}
	.form {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 4px;
		margin-bottom: 10px;
	}
	.form input,
	.form select {
		background: var(--wt-void);
		color: var(--wt-haze);
		border: 2px solid var(--wt-branch);
		font-family: inherit;
		font-size: 11px;
		padding: 4px 6px;
	}
	.form button {
		grid-column: 1 / -1;
		all: unset;
		cursor: pointer;
		text-align: center;
		padding: 6px;
		background: var(--wt-fruit-gold);
		color: var(--wt-void);
		font-weight: 700;
		letter-spacing: 0.2em;
		border: 2px solid var(--wt-fruit-gold);
		box-shadow:
			inset 1px 1px 0 var(--wt-haze),
			inset -1px -1px 0 var(--wt-amber);
	}
	.tendrils {
		list-style: none;
		padding: 0;
		margin: 0;
	}
	.tendril {
		display: grid;
		grid-template-columns: 18px 1fr auto auto auto;
		gap: 6px;
		align-items: center;
		padding: 4px 0;
		border-bottom: 1px dotted var(--wt-branch);
	}
	.root-icon {
		color: var(--clr);
	}
	.info {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.lbl {
		color: var(--clr);
	}
	.prov {
		color: var(--wt-mist);
		font-size: 9px;
		letter-spacing: 0.2em;
	}
	.fp {
		color: var(--wt-frost-cyan);
		font-size: 9px;
		word-break: break-all;
	}
	.usage {
		color: var(--wt-sap-green);
		font-size: 10px;
	}
	.mini {
		all: unset;
		cursor: pointer;
		font-size: 9px;
		padding: 2px 6px;
		border: 1px solid var(--wt-branch);
		color: var(--wt-frost-cyan);
		letter-spacing: 0.15em;
	}
	.mini:hover {
		color: var(--wt-fruit-gold);
		border-color: var(--wt-fruit-gold);
	}
	.mini.danger:hover {
		color: var(--wt-alarm);
		border-color: var(--wt-alarm);
	}
	.empty {
		color: var(--wt-mist);
		font-style: italic;
	}
</style>
