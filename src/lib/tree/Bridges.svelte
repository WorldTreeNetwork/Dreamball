<!--
  Bridges — Phase 3 readiness panel. Real-time integrations with Blender,
  Unreal, and a generic WS bridge. Phase 0 shows OFFLINE statuses; the
  panel exists so the path is visible from day one.
-->
<script lang="ts">
	type Status = 'offline' | 'connecting' | 'online' | 'error';
	interface Bridge {
		id: string;
		name: string;
		role: string;
		status: Status;
		hint: string;
	}

	let bridges: Bridge[] = $state([
		{
			id: 'blender',
			name: 'BLENDER',
			role: 'mesh ↔ shader sync',
			status: 'offline',
			hint: 'pip install dreambals-bridge && bpy-launch'
		},
		{
			id: 'unreal',
			name: 'UNREAL',
			role: 'material observer',
			status: 'offline',
			hint: 'plugins/DreamBallsBridge in 5.4+'
		},
		{
			id: 'ws',
			name: 'WS',
			role: 'browser ↔ tree daemon',
			status: 'offline',
			hint: 'ws://localhost:8080/ball · phase 1+'
		},
		{
			id: 'mcp',
			name: 'MCP',
			role: 'agent authoring',
			status: 'offline',
			hint: 'tools/mcp-server (already in repo)'
		}
	]);

	function ping(id: string) {
		bridges = bridges.map((b) => (b.id === id ? { ...b, status: 'connecting' } : b));
		setTimeout(() => {
			bridges = bridges.map((b) => (b.id === id ? { ...b, status: 'error' } : b));
		}, 800);
	}

	function color(s: Status): string {
		return {
			offline: 'var(--wt-mist)',
			connecting: 'var(--wt-amber)',
			online: 'var(--wt-sap-green)',
			error: 'var(--wt-alarm)'
		}[s];
	}
</script>

<ul class="bridges">
	{#each bridges as b (b.id)}
		<li>
			<span class="dot" style="background: {color(b.status)}; box-shadow: 0 0 6px {color(b.status)}"></span>
			<span class="meta">
				<span class="name">{b.name}</span>
				<span class="role">{b.role}</span>
				<span class="hint">{b.hint}</span>
			</span>
			<button type="button" class="ping" onclick={() => ping(b.id)}>PING</button>
		</li>
	{/each}
</ul>
<p class="note">phase 0 stubs · live in phase 3 (world tree)</p>

<style>
	.bridges {
		list-style: none;
		padding: 0;
		margin: 0;
		font-family: var(--wt-font-mono);
		font-size: 11px;
	}
	.bridges li {
		display: grid;
		grid-template-columns: 12px 1fr auto;
		gap: 8px;
		align-items: center;
		padding: 6px 0;
		border-bottom: 1px dotted var(--wt-branch);
	}
	.dot {
		width: 10px;
		height: 10px;
	}
	.meta {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.name {
		color: var(--wt-fruit-gold);
		letter-spacing: 0.2em;
	}
	.role {
		color: var(--wt-haze);
	}
	.hint {
		color: var(--wt-mist);
		font-size: 9px;
	}
	.ping {
		all: unset;
		cursor: pointer;
		padding: 3px 8px;
		font-size: 10px;
		letter-spacing: 0.2em;
		color: var(--wt-frost-cyan);
		border: 2px solid var(--wt-branch);
	}
	.ping:hover {
		color: var(--wt-fruit-gold);
		border-color: var(--wt-fruit-gold);
	}
	.note {
		font-size: 10px;
		color: var(--wt-wish-violet);
		margin-top: 6px;
	}
</style>
