<!--
  Demo D Scenario 3 — Wearer + Observer.
  The wearer sees the full Agent panel. The observer pane (below) sees
  only the public slots (filtered through the backend's permission resolver).
-->
<script lang="ts">
	import {
		Wearer,
		DreamBallViewer,
		MockBackend,
		mockBall,
		type DreamBall,
		type Fingerprint
	} from '$lib/index.js';

	// The wearer is a member of the Avatar's Guild — without this, MockBackend
	// treats the wearer as an anonymous observer and the agent panel below
	// renders empty. Adding the wearer fingerprint to `member` unlocks the
	// guild-only slots (memory, knowledge-graph, emotional-register) in the
	// wearer pane while leaving the observer pane anonymous. Flagged in the
	// v2 architect review.
	const WEARER_FP: Fingerprint = 'b58:mockWearerAAAAAAAAAAAAAAAAAAA' as Fingerprint;

	const avatar: DreamBall = mockBall('avatar', {
		name: 'Hummingbird Hat',
		guild: ['b58:guildHummingbird' as Fingerprint],
		member: [WEARER_FP],
		// The agent panel (only visible to the wearer) — carries memory + emotion.
		'emotional-register': {
			axes: [
				{ name: 'curiosity', value: 0.82 },
				{ name: 'warmth', value: 0.55 }
			]
		},
		'knowledge-graph': {
			triples: [
				{ from: 'curiosity', label: 'inclines-toward', to: 'new-things' }
			]
		},
		feel: {
			personality: 'playful, curious, precise',
			voice: 'young, fast cadence',
			values: ['curiosity', 'clarity']
		}
	});

	const backend = new MockBackend([avatar]);
	const wearerFp: Fingerprint = WEARER_FP;

	let synthetic = $state('Hello, world.');
	let stream: MediaStream | null = $state(null);
	let streamError: string | null = $state(null);

	async function attachWebcam() {
		try {
			stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
			streamError = null;
		} catch (e) {
			streamError = (e as Error).message;
		}
	}

	function detach() {
		stream?.getTracks().forEach((t) => t.stop());
		stream = null;
	}
</script>

<section>
	<h1>Scenario 3 — Wearer + Observer</h1>
	<p class="mocked">⚠ crypto mocked. Observer filtering uses MockBackend's policy resolver.</p>

	<div class="input-row">
		<label>
			Synthetic input:
			<input bind:value={synthetic} type="text" />
		</label>
		<button type="button" onclick={attachWebcam} disabled={!!stream}>
			Attach webcam
		</button>
		<button type="button" onclick={detach} disabled={!stream}>
			Detach
		</button>
		{#if streamError}
			<span class="err">{streamError}</span>
		{/if}
	</div>

	<div class="split">
		<div class="pane wearer-pane">
			<h3>Wearer view — full slots</h3>
			<Wearer ball={avatar} sourceTrack={stream} syntheticText={synthetic} />
			<div class="agent-panel">
				<h4>Agent panel (wearer-only)</h4>
				<DreamBallViewer ball={avatar} lens="emotional-state" viewer={wearerFp} {backend} />
				<DreamBallViewer ball={avatar} lens="knowledge-graph" viewer={wearerFp} {backend} />
			</div>
		</div>
		<div class="pane observer-pane">
			<h3>Observer view — public slots only</h3>
			<DreamBallViewer ball={avatar} lens="avatar" viewer={null} {backend} />
			<p class="note">
				No memory, no knowledge graph, no emotional register visible — the observer sees only
				the Avatar's public surface.
			</p>
		</div>
	</div>
</section>

<style>
	.mocked {
		background: #3a2a10;
		color: #ffd0a0;
		padding: 0.5rem 0.75rem;
		border-radius: 0.5rem;
		font-size: 0.85rem;
	}
	.input-row {
		display: flex;
		gap: 0.75rem;
		align-items: center;
		margin: 1rem 0 2rem;
		flex-wrap: wrap;
	}
	.input-row input {
		padding: 0.4rem 0.6rem;
		border-radius: 0.4rem;
		border: 1px solid #303a6a;
		background: #0a0e20;
		color: inherit;
	}
	.input-row button {
		padding: 0.4rem 0.9rem;
		border: 1px solid #303a6a;
		background: #0f1430;
		color: inherit;
		border-radius: 0.4rem;
		cursor: pointer;
	}
	.input-row button:disabled {
		opacity: 0.4;
	}
	.err {
		color: #f66;
	}
	.split {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 1.5rem;
	}
	@media (max-width: 48rem) {
		.split {
			grid-template-columns: 1fr;
		}
	}
	.pane {
		background: #0a0e20;
		padding: 1rem;
		border-radius: 0.75rem;
	}
	.pane h3 {
		margin: 0 0 0.75rem;
		color: #e0b7ff;
	}
	.pane h4 {
		margin: 1rem 0 0.5rem;
		font-size: 0.9rem;
		opacity: 0.8;
	}
	.agent-panel {
		display: grid;
		gap: 0.75rem;
	}
	.note {
		font-size: 0.85rem;
		opacity: 0.65;
		font-style: italic;
	}
</style>
