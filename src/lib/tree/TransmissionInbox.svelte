<!--
  TransmissionInbox — incoming wind-carried seeds. Phase 2.
  Phase 0 ships with a synthetic feed so the panel has something to show.
-->
<script lang="ts">
	import { iconFor } from './icons.js';

	interface Incoming {
		id: string;
		from: string;
		seed: string;
		kind: 'tool' | 'avatar' | 'agent';
		quarantined: boolean;
		acceptedAt?: number;
	}

	let inbox: Incoming[] = $state([
		{
			id: 'in-001',
			from: 'KITE-FLYER',
			seed: 'haiku-compose · skill',
			kind: 'tool',
			quarantined: false
		},
		{
			id: 'in-002',
			from: 'GLASS-OWL',
			seed: 'patient-listener · agent',
			kind: 'agent',
			quarantined: true
		}
	]);

	function accept(id: string) {
		inbox = inbox.map((m) => (m.id === id ? { ...m, acceptedAt: Date.now(), quarantined: false } : m));
	}
	function reject(id: string) {
		inbox = inbox.filter((m) => m.id !== id);
	}
</script>

<div class="inbox">
	{#if inbox.length === 0}
		<p class="empty">no winds yet.</p>
	{:else}
		<ul class="list">
			{#each inbox as m (m.id)}
				<li class:q={m.quarantined} class:done={m.acceptedAt}>
					<span class="ic">{iconFor(m.kind)}</span>
					<span class="meta">
						<span class="seed">{m.seed}</span>
						<span class="from">from {m.from}</span>
						{#if m.quarantined}<span class="badge">QUARANTINED</span>{/if}
						{#if m.acceptedAt}<span class="badge ok">ACCEPTED</span>{/if}
					</span>
					{#if !m.acceptedAt}
						<button class="mini" type="button" onclick={() => accept(m.id)}>✓</button>
						<button class="mini danger" type="button" onclick={() => reject(m.id)}>✕</button>
					{:else}
						<span class="ok">✓</span>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.inbox {
		font-family: var(--wt-font-mono);
		font-size: 11px;
		color: var(--wt-haze);
	}
	.empty {
		color: var(--wt-mist);
		font-style: italic;
	}
	.list {
		list-style: none;
		padding: 0;
		margin: 0;
	}
	.list li {
		display: grid;
		grid-template-columns: 18px 1fr auto auto;
		gap: 6px;
		align-items: center;
		padding: 4px 0;
		border-bottom: 1px dotted var(--wt-branch);
	}
	.list li.done {
		opacity: 0.6;
	}
	.ic {
		color: var(--wt-fruit-gold);
	}
	.meta {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.seed {
		color: var(--wt-haze);
	}
	.from {
		color: var(--wt-mist);
		font-size: 10px;
	}
	.badge {
		display: inline-block;
		padding: 1px 4px;
		font-size: 8px;
		letter-spacing: 0.15em;
		background: var(--wt-alarm);
		color: var(--wt-void);
		margin-top: 2px;
		width: fit-content;
	}
	.badge.ok {
		background: var(--wt-sap-green);
	}
	.mini {
		all: unset;
		cursor: pointer;
		padding: 2px 6px;
		border: 1px solid var(--wt-branch);
		color: var(--wt-sap-green);
		letter-spacing: 0.15em;
		font-size: 10px;
	}
	.mini.danger {
		color: var(--wt-alarm);
	}
	.mini:hover {
		border-color: currentColor;
	}
	.ok {
		color: var(--wt-sap-green);
	}
</style>
