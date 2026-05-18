<script lang="ts">
	/**
	 * 🌍 BFF Trust Tile — TLC Sign-Up + BFF↔BFFZ Isomorphism Dashboard
	 * 
	 * Shows the living bridge between benclark10's Bioregional Financing Facilities
	 * and Ding Dong's Friendship Engine (BFFZ) protocol.
	 * 
	 * Two fractal scales of the same regenerative truth.
	 */
	import { onMount } from 'svelte';

	let tlcCount = $state(42);  // placeholder — real count from ladybugdb
	let trustRaised = $state(125000);
	let trustTarget = $state(30000000);
	let bffActive = $state(false);
	let pulses = $state(false);
	let bioRegion = $state('🌎');

	const bioregions = [
		{ name: 'Barichaga', emoji: '🌴', loc: 'Colombia', desc: '500K hectares reforestation' },
		{ name: 'Cascadia', emoji: '🌲', loc: 'NA Pacific Rim', desc: '435 watersheds' },
		{ name: 'Forests NE', emoji: '🍁', loc: 'USA/Canada', desc: 'New England + Nova Scotia' },
		{ name: 'GTB', emoji: '🌊', loc: 'Greater Tkaronto', desc: '21% Earth\'s fresh water' },
		{ name: 'N. Andes', emoji: '⛰️', loc: 'Colombia', desc: '7 territories' },
		{ name: 'Ogallala', emoji: '🌾', loc: 'Great Plains', desc: 'Feeds 1B people' }
	];

	// Pulse animation on mount
	onMount(() => {
		setInterval(() => {
			pulses = !pulses;
		}, 3000);
	});

	function signTLC() {
		bffActive = !bffActive;
		if (bffActive) tlcCount++;
	}

	function formatUSD(n: number): string {
		if (n >= 1_000_000) return `$${(n / 1_000_000).toFixed(1)}M`;
		if (n >= 1_000) return `$${(n / 1_000).toFixed(0)}K`;
		return `$${n}`;
	}
</script>

<div class="bff-trust-tile" class:active={bffActive}>
	<div class="tile-header">
		<span class="icon">🌍</span>
		<h3>BFF Trust</h3>
		<span class="badge" class:pulse={pulses}>{tlcCount} TLC</span>
	</div>

	<div class="mantra">
		<p>Fund the <em>new systems</em>.</p>
		<p>Those systems fund the projects.</p>
	</div>

	<div class="isomorphism-row">
		<div class="node bff">
			<span class="label">BFF</span>
			<span class="desc">Bioregional Financing</span>
		</div>
		<div class="bridge">↔</div>
		<div class="node bffz">
			<span class="label">BFFZ</span>
			<span class="desc">Friendship Engine</span>
		</div>
	</div>

	<div class="trust-bar">
		<div class="bar-bg">
			<div class="bar-fill" style="width: {(trustRaised / trustTarget * 100).toFixed(1)}%"></div>
		</div>
		<div class="trust-label">
			<span>{formatUSD(trustRaised)} raised</span>
			<span>Target: {formatUSD(trustTarget)}</span>
		</div>
	</div>

	<div class="bioregion-scroll">
		{#each bioregions as region}
			<div class="bioregion-chip">
				<span>{region.emoji}</span>
				<span class="name">{region.name}</span>
			</div>
		{/each}
	</div>

	<div class="action-row">
		<button class="tlc-btn" onclick={signTLC}>
			{bffActive ? '✅ TLC Signed' : '📝 Sign TLC'}
		</button>
		<button class="bff-btn" onclick={() => window.location.href = '/tree/dash'}>
			🤝 BFF Handshake
		</button>
	</div>

	<div class="footer-note">
		<p class="isomorphic-note">BFF ↔ BFFZ — same truth, different fractal scale</p>
		<p class="tlc-call">Comment "TLC" to join. Insert quarter to transmit.</p>
	</div>
</div>

<style>
	.bff-trust-tile {
		background: rgba(10, 20, 40, 0.9);
		border: 1px solid rgba(120, 200, 100, 0.3);
		border-radius: 12px;
		padding: 16px;
		font-family: system-ui, sans-serif;
		color: #d0e8d0;
		transition: all 0.3s ease;
	}
	.bff-trust-tile.active {
		border-color: rgba(255, 224, 100, 0.5);
		box-shadow: 0 0 20px rgba(120, 200, 100, 0.15);
	}

	.tile-header {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-bottom: 12px;
	}
	.tile-header h3 {
		margin: 0;
		font-size: 1rem;
		font-weight: 600;
		flex: 1;
	}
	.icon { font-size: 1.2rem; }
	.badge {
		background: rgba(120, 200, 100, 0.2);
		border: 1px solid rgba(120, 200, 100, 0.3);
		border-radius: 12px;
		padding: 2px 10px;
		font-size: 0.75rem;
		font-weight: 600;
		transition: all 0.3s;
	}
	.badge.pulse { background: rgba(255, 224, 100, 0.3); }

	.mantra {
		text-align: center;
		padding: 12px;
		margin-bottom: 12px;
		background: rgba(120, 200, 100, 0.05);
		border-radius: 8px;
		border: 1px solid rgba(120, 200, 100, 0.1);
	}
	.mantra p {
		margin: 2px 0;
		font-size: 0.85rem;
		font-style: italic;
		color: rgba(200, 230, 200, 0.8);
	}
	.mantra em {
		color: #ffe066;
		font-style: normal;
		font-weight: 600;
	}

	.isomorphism-row {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 12px;
		margin-bottom: 12px;
	}
	.node {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
	}
	.node .label {
		font-size: 1.1rem;
		font-weight: 700;
		letter-spacing: 0.05em;
	}
	.node.bff .label { color: #78c864; }
	.node.bffz .label { color: #e0b7ff; }
	.node .desc {
		font-size: 0.65rem;
		color: rgba(200, 230, 200, 0.5);
	}
	.bridge {
		font-size: 1.4rem;
		color: rgba(255, 224, 100, 0.6);
		animation: bridge-pulse 2s infinite;
	}
	@keyframes bridge-pulse {
		0%, 100% { opacity: 0.4; }
		50% { opacity: 1; }
	}

	.trust-bar {
		margin-bottom: 12px;
	}
	.bar-bg {
		height: 6px;
		background: rgba(120, 200, 100, 0.1);
		border-radius: 3px;
		overflow: hidden;
		margin-bottom: 4px;
	}
	.bar-fill {
		height: 100%;
		background: linear-gradient(90deg, #78c864, #ffe066);
		border-radius: 3px;
		transition: width 1s ease;
	}
	.trust-label {
		display: flex;
		justify-content: space-between;
		font-size: 0.7rem;
		color: rgba(200, 230, 200, 0.5);
	}

	.bioregion-scroll {
		display: flex;
		gap: 6px;
		flex-wrap: wrap;
		margin-bottom: 12px;
	}
	.bioregion-chip {
		display: flex;
		align-items: center;
		gap: 4px;
		padding: 3px 8px;
		background: rgba(120, 200, 100, 0.1);
		border-radius: 12px;
		font-size: 0.7rem;
	}
	.bioregion-chip .name {
		color: rgba(200, 230, 200, 0.7);
	}

	.action-row {
		display: flex;
		gap: 8px;
		margin-bottom: 12px;
	}
	.tlc-btn, .bff-btn {
		flex: 1;
		padding: 8px 12px;
		border-radius: 8px;
		border: 1px solid;
		font-family: inherit;
		font-size: 0.8rem;
		cursor: pointer;
		transition: all 0.2s;
	}
	.tlc-btn {
		background: rgba(120, 200, 100, 0.15);
		border-color: rgba(120, 200, 100, 0.3);
		color: #78c864;
	}
	.tlc-btn:hover { background: rgba(120, 200, 100, 0.25); }
	.bff-btn {
		background: rgba(224, 183, 255, 0.15);
		border-color: rgba(224, 183, 255, 0.3);
		color: #e0b7ff;
	}
	.bff-btn:hover { background: rgba(224, 183, 255, 0.25); }

	.footer-note {
		text-align: center;
	}
	.isomorphic-note {
		font-size: 0.7rem;
		color: rgba(200, 230, 200, 0.4);
		margin: 0 0 4px;
		font-style: italic;
	}
	.tlc-call {
		font-size: 0.75rem;
		color: rgba(255, 224, 100, 0.6);
		margin: 0;
		font-weight: 500;
	}
</style>
