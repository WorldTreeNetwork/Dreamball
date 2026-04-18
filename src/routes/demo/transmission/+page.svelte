<!--
  Demo D Scenario 1 — Transmission.
  Alice has a Tool. Bob has an Agent. Both join a Guild. Alice transmits.
  Bob's Agent now shows the new skill in its act.skill list.
-->
<script lang="ts">
	import { DreamBallViewer, MockBackend, mockBall, type DreamBall } from '$lib/index.js';

	const backend = new MockBackend();

	let step = $state(0);
	const guild: DreamBall = $state(mockBall('guild', { name: 'The Hummingbird Guild' }));
	const alice: DreamBall = $state(mockBall('tool', { name: "Alice's haiku-compose" }));
	let bob: DreamBall = $state(
		mockBall('agent', {
			name: "Bob's Curious Mind",
			act: {
				model: 'claude-opus-4-7',
				'system-prompt': 'You are curious.',
				skill: [],
				tool: ['web.search']
			}
		})
	);

	function advance() {
		step = Math.min(step + 1, 3);
		if (step === 2) {
			// Alice transmits.
			const newSkill = alice.skill ?? { name: 'haiku-compose' };
			bob = {
				...bob,
				act: { ...bob.act, skill: [...(bob.act?.skill ?? []), newSkill] },
				revision: bob.revision + 1
			};
		}
	}
	function reset() {
		step = 0;
		bob = {
			...bob,
			act: { ...bob.act, skill: [] },
			revision: bob.revision
		};
	}
</script>

<section>
	<h1>Scenario 1 — Transmission</h1>
	<p class="mocked">⚠ crypto mocked: signatures fake; no proxy-recryption. Protocol shapes real.</p>

	<ol class="steps">
		<li class:active={step >= 0} class:done={step > 0}>
			Alice mints a Tool DreamBall. Bob mints an Agent. They both join the Hummingbird Guild.
		</li>
		<li class:active={step >= 1} class:done={step > 1}>
			Alice issues <code>jelly transmit</code>. A <code>jelly.transmission</code> receipt is produced.
		</li>
		<li class:active={step >= 2} class:done={step > 2}>
			Bob's Agent custodian re-fetches the Agent. The new skill appears in <code>act.skill</code>.
		</li>
		<li class:active={step >= 3}>
			Renderer shows all three DreamBalls in their primary lenses.
		</li>
	</ol>

	<div class="controls">
		<button type="button" onclick={advance} disabled={step >= 3}>Next step</button>
		<button type="button" onclick={reset}>Reset</button>
	</div>

	<div class="stage">
		<div class="card">
			<h3>Guild</h3>
			<DreamBallViewer ball={guild} lens="flat" {backend} />
		</div>
		<div class="card">
			<h3>Alice's Tool</h3>
			<DreamBallViewer ball={alice} lens="flat" {backend} />
		</div>
		<div class="card">
			<h3>Bob's Agent ({bob.act?.skill?.length ?? 0} skill{(bob.act?.skill?.length ?? 0) === 1 ? '' : 's'})</h3>
			<DreamBallViewer ball={bob} lens="knowledge-graph" {backend} />
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
	.steps {
		padding-left: 1.2rem;
	}
	.steps li {
		opacity: 0.4;
		margin-bottom: 0.5rem;
	}
	.steps li.active {
		opacity: 1;
	}
	.steps li.done {
		opacity: 0.7;
	}
	.controls {
		display: flex;
		gap: 0.75rem;
		margin: 1rem 0 2rem;
	}
	.controls button {
		padding: 0.6rem 1rem;
		border: 1px solid #303a6a;
		background: #0f1430;
		color: inherit;
		border-radius: 0.5rem;
		cursor: pointer;
	}
	.controls button:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}
	.stage {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(18rem, 1fr));
		gap: 1rem;
	}
	.stage .card {
		background: #0a0e20;
		border-radius: 0.75rem;
		padding: 1rem;
	}
	.stage h3 {
		margin: 0 0 0.5rem;
		font-size: 1rem;
		color: #e0b7ff;
	}
	code {
		background: #1a2240;
		padding: 0.1rem 0.3rem;
		border-radius: 0.25rem;
	}
</style>
