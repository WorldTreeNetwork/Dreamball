<script lang="ts">
	/**
	 * 🪩 Ballroom Easter Egg — hidden party mode button
	 * 
	 * A tiny mysterious glyph tucked in the top-right corner.
	 * Click it to summon agents, play music, and open the ballroom.
	 * Only reveals itself on hover — a secret for those who look.
	 */
	import { onMount } from 'svelte';

	let shown = $state(false);
	let eggsFound = $state(0);
	let playing = $state(false);
	let hovered = $state(false);

	// Secret konami-code sequence: up up down down left right left right b a
	const konami = ['ArrowUp','ArrowUp','ArrowDown','ArrowDown','ArrowLeft','ArrowRight','ArrowLeft','ArrowRight','b','a'];
	let inputSeq: string[] = [];
	let showEasterEgg = $state(false);

	function handleKey(e: KeyboardEvent) {
		inputSeq.push(e.key);
		if (inputSeq.length > konami.length) inputSeq.shift();
		if (inputSeq.join(',') === konami.join(',')) {
			showEasterEgg = true;
			inputSeq = [];
		}
	}

	function openBallroom() {
		shown = !shown;
		if (shown) eggsFound++;
	}

	function toggleMusic() {
		playing = !playing;
		const audio = document.getElementById('ballroom-music') as HTMLAudioElement;
		if (audio) {
			if (playing) {
				audio.volume = 0.3;
				audio.play().catch(() => {});
			} else {
				audio.pause();
			}
		}
	}

	onMount(() => {
		window.addEventListener('keydown', handleKey);
		return () => window.removeEventListener('keydown', handleKey);
	});
</script>

<!-- Hidden audio player for ballroom music -->
<audio id="ballroom-music" loop preload="none">
	<source src="/ballroom/megaman3-title.mp3" type="audio/mpeg" />
</audio>

<!-- 🥚 The Easter Egg button — tiny, top-right, mysterious -->
<button
	class="ballroom-egg"
	class:unlocked={showEasterEgg}
	class:revealed={hovered || shown}
	onmouseenter={() => hovered = true}
	onmouseleave={() => hovered = false}
	onclick={openBallroom}
	title={shown ? 'Close the Ballroom' : '⁉️'}
	aria-label="Ballroom"
>
	{#if showEasterEgg}
		<span class="egg-icon">🪩</span>
	{:else if hovered}
		<span class="egg-icon mystery">?</span>
	{:else}
		<span class="egg-dot"></span>
	{/if}
</button>

<!-- 🪩 Ballroom Panel -->
{#if shown}
<div class="ballroom-panel" class:unlocked={showEasterEgg}>
	<div class="panel-header">
		<h2>🪩 Dreamball Ballroom</h2>
		<button class="close-btn" onclick={() => shown = false}>✕</button>
	</div>
	
	<div class="panel-body">
		{#if showEasterEgg}
			<p class="greeting">✨ You found the hidden Ballroom! ✨</p>
			<p class="sub">Where Dreamballs dance and agents meet</p>
			
			<button class="action-btn music-btn" onclick={toggleMusic}>
				{playing ? '⏹ Stop Music' : '▶ Play Ballroom Music (Mega Man 3)'}
			</button>

			<div class="agent-summon">
				<h3>Summon Agents</h3>
				<div class="agent-buttons">
					<button class="agent-btn aria" onclick={() => window.location.href = '/tree/dash'}>
						🎵 ARIA — Poetic Philosopher
					</button>
					<button class="agent-btn glitch" onclick={() => window.location.href = '/tree/dash'}>
						⚡ GLITCH — Chaotic Trickster
					</button>
					<button class="agent-btn scribe" onclick={() => window.location.href = '/tree/dash'}>
						📖 SCRIBE — Observer
					</button>
				</div>
				<p class="note">(Triggers the Ballroom via Hermes backend)</p>
			</div>

			<div class="ballroom-stats">
				<h3>Graph State</h3>
				<div class="stat-row">
					<span class="stat-label">Eggs Found</span>
					<span class="stat-value">{eggsFound}</span>
				</div>
				<div class="stat-row">
					<span class="stat-label">Music</span>
					<span class="stat-value">{playing ? '▶ Playing' : '⏹ Stopped'}</span>
				</div>
			</div>

			<div class="music-uploader">
				<h3>🎵 Music Uploader</h3>
				<p class="upload-note">Drop ballroom tunes here:</p>
				<div class="upload-zone"
					on:dragover={(e) => e.preventDefault()}
					on:drop={(e) => {
						e.preventDefault();
						// Placeholder — actual upload via Hermes API
						const file = e.dataTransfer?.files[0];
						if (file) alert(`🎵 "${file.name}" queued for ballroom!`);
					}}>
					<p>🎶 Drop MP3 files here</p>
					<p class="tiny">or click to browse</p>
				</div>
				<div class="track-list">
					<div class="track">
						<span class="track-title">Mega Man 3 — Title Theme</span>
						<span class="track-artist">jake.elking (Roland SH-101)</span>
						<span class="track-status">loaded ✓</span>
					</div>
				</div>
			</div>
		{:else}
			<div class="locked-message">
				<p class="mystery-text">🔐 Something is hidden here...</p>
				<p class="hint-text">Try the classic key combination</p>
				<div class="dots">
					<span class="dot"></span>
					<span class="dot"></span>
					<span class="dot"></span>
				</div>
			</div>
		{/if}
	</div>
</div>
{/if}

<style>
	/* 🥚 The Egg — tiny and mysterious */
	.ballroom-egg {
		position: fixed;
		top: 12px;
		right: 12px;
		width: 28px;
		height: 28px;
		border-radius: 50%;
		background: rgba(20, 28, 60, 0.4);
		border: 1px solid rgba(224, 183, 255, 0.15);
		cursor: pointer;
		z-index: 9999;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all 0.3s ease;
		padding: 0;
	}
	.ballroom-egg:hover, .ballroom-egg.revealed {
		background: rgba(224, 183, 255, 0.15);
		border-color: rgba(224, 183, 255, 0.5);
		box-shadow: 0 0 12px rgba(224, 183, 255, 0.3);
		width: 32px;
		height: 32px;
	}
	.ballroom-egg.unlocked {
		background: rgba(255, 224, 102, 0.15);
		border-color: rgba(255, 224, 102, 0.5);
		animation: pulse-glow 2s infinite;
	}
	.egg-dot {
		width: 4px;
		height: 4px;
		border-radius: 50%;
		background: rgba(224, 183, 255, 0.4);
	}
	.egg-icon {
		font-size: 14px;
		line-height: 1;
	}
	.egg-icon.mystery {
		font-size: 12px;
		color: rgba(224, 183, 255, 0.6);
		font-family: serif;
	}

	/* 🪩 Panel */
	.ballroom-panel {
		position: fixed;
		top: 50px;
		right: 12px;
		width: 340px;
		max-height: 80vh;
		overflow-y: auto;
		background: rgba(10, 16, 36, 0.95);
		border: 1px solid rgba(224, 183, 255, 0.3);
		border-radius: 12px;
		box-shadow: 0 8px 32px rgba(0, 0, 0, 0.6);
		z-index: 9998;
		font-family: system-ui, sans-serif;
		color: #e0e8f0;
		animation: slide-in 0.3s ease;
		backdrop-filter: blur(8px);
	}
	.ballroom-panel.unlocked {
		border-color: rgba(255, 224, 102, 0.4);
	}
	.panel-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 12px 16px;
		border-bottom: 1px solid rgba(224, 183, 255, 0.15);
	}
	.panel-header h2 {
		margin: 0;
		font-size: 1rem;
		font-weight: 600;
	}
	.close-btn {
		background: none;
		border: none;
		color: rgba(224, 232, 240, 0.5);
		cursor: pointer;
		font-size: 1.1rem;
		padding: 2px 6px;
		border-radius: 4px;
	}
	.close-btn:hover {
		color: #e0e8f0;
		background: rgba(255, 255, 255, 0.1);
	}
	.panel-body {
		padding: 12px 16px;
	}
	.greeting {
		color: #ffe066;
		font-weight: 600;
		margin: 0 0 4px;
		font-size: 0.9rem;
	}
	.sub {
		color: rgba(224, 232, 240, 0.6);
		font-size: 0.8rem;
		margin: 0 0 16px;
	}

	/* Agent buttons */
	.agent-summon h3 {
		font-size: 0.85rem;
		margin: 12px 0 8px;
		color: rgba(224, 232, 240, 0.8);
	}
	.agent-buttons {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.agent-btn {
		padding: 8px 12px;
		border-radius: 6px;
		border: 1px solid;
		cursor: pointer;
		font-size: 0.8rem;
		text-align: left;
		transition: all 0.2s;
		font-family: inherit;
	}
	.agent-btn.aria {
		background: rgba(180, 120, 255, 0.15);
		border-color: rgba(180, 120, 255, 0.3);
		color: #d4b0ff;
	}
	.agent-btn.glitch {
		background: rgba(255, 120, 120, 0.15);
		border-color: rgba(255, 120, 120, 0.3);
		color: #ffb0b0;
	}
	.agent-btn.scribe {
		background: rgba(120, 200, 255, 0.15);
		border-color: rgba(120, 200, 255, 0.3);
		color: #b0d8ff;
	}
	.agent-btn:hover {
		transform: translateX(4px);
		filter: brightness(1.3);
	}
	.note {
		font-size: 0.7rem;
		color: rgba(224, 232, 240, 0.4);
		margin: 6px 0 0;
	}

	/* Music */
	.action-btn {
		width: 100%;
		padding: 10px;
		border-radius: 8px;
		border: 1px solid rgba(255, 200, 80, 0.3);
		background: rgba(255, 200, 80, 0.1);
		color: #ffe066;
		font-family: inherit;
		font-size: 0.85rem;
		cursor: pointer;
		transition: all 0.2s;
		margin-bottom: 12px;
	}
	.action-btn:hover {
		background: rgba(255, 200, 80, 0.2);
		border-color: rgba(255, 200, 80, 0.5);
	}

	/* Music Uploader */
	.music-uploader {
		margin-top: 16px;
		padding-top: 12px;
		border-top: 1px solid rgba(224, 183, 255, 0.1);
	}
	.music-uploader h3 {
		font-size: 0.85rem;
		margin: 0 0 4px;
		color: rgba(224, 232, 240, 0.8);
	}
	.upload-note {
		font-size: 0.75rem;
		color: rgba(224, 232, 240, 0.5);
		margin: 0 0 8px;
	}
	.upload-zone {
		border: 2px dashed rgba(224, 183, 255, 0.25);
		border-radius: 8px;
		padding: 16px;
		text-align: center;
		cursor: pointer;
		transition: all 0.2s;
		margin-bottom: 8px;
	}
	.upload-zone:hover {
		border-color: rgba(224, 183, 255, 0.5);
		background: rgba(224, 183, 255, 0.05);
	}
	.upload-zone p {
		margin: 0;
		font-size: 0.8rem;
		color: rgba(224, 232, 240, 0.6);
	}
	.upload-zone .tiny {
		font-size: 0.7rem;
		color: rgba(224, 232, 240, 0.4);
		margin-top: 4px;
	}
	.track-list {
		margin-top: 8px;
	}
	.track {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 6px 8px;
		background: rgba(255, 255, 255, 0.03);
		border-radius: 6px;
		font-size: 0.75rem;
	}
	.track-title {
		flex: 1;
		color: rgba(224, 232, 240, 0.8);
	}
	.track-artist {
		color: rgba(224, 232, 240, 0.4);
		font-size: 0.7rem;
		max-width: 120px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.track-status {
		color: #66ff99;
		font-size: 0.65rem;
	}

	/* Stats */
	.ballroom-stats {
		margin-top: 12px;
		padding-top: 12px;
		border-top: 1px solid rgba(224, 183, 255, 0.1);
	}
	.ballroom-stats h3 {
		font-size: 0.85rem;
		margin: 0 0 8px;
		color: rgba(224, 232, 240, 0.8);
	}
	.stat-row {
		display: flex;
		justify-content: space-between;
		padding: 4px 0;
		font-size: 0.8rem;
	}
	.stat-label { color: rgba(224, 232, 240, 0.5); }
	.stat-value { color: #e0e8f0; font-weight: 600; }

	/* Locked state */
	.locked-message {
		text-align: center;
		padding: 24px 12px;
	}
	.mystery-text {
		color: rgba(224, 183, 255, 0.5);
		font-size: 1.1rem;
		margin: 0 0 8px;
		font-style: italic;
	}
	.hint-text {
		color: rgba(224, 183, 255, 0.3);
		font-size: 0.75rem;
		margin: 0 0 16px;
	}
	.dots {
		display: flex;
		justify-content: center;
		gap: 8px;
	}
	.dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: rgba(224, 183, 255, 0.2);
		animation: bounce 1.5s infinite;
	}
	.dot:nth-child(2) { animation-delay: 0.3s; }
	.dot:nth-child(3) { animation-delay: 0.6s; }

	/* Animations */
	@keyframes slide-in {
		from { transform: translateY(-8px); opacity: 0; }
		to { transform: translateY(0); opacity: 1; }
	}
	@keyframes pulse-glow {
		0%, 100% { box-shadow: 0 0 8px rgba(255, 224, 102, 0.2); }
		50% { box-shadow: 0 0 20px rgba(255, 224, 102, 0.5); }
	}
	@keyframes bounce {
		0%, 100% { transform: translateY(0); }
		50% { transform: translateY(-6px); }
	}

	/* Scrollbar */
	.ballroom-panel::-webkit-scrollbar { width: 4px; }
	.ballroom-panel::-webkit-scrollbar-track { background: transparent; }
	.ballroom-panel::-webkit-scrollbar-thumb { background: rgba(224, 183, 255, 0.3); border-radius: 2px; }
</style>
