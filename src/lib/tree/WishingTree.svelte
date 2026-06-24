<!--
  WishingTree — top-level Phase 0–4 composer shell.
  Header: brand · TYPE · PHASE tabs · view toggles
  Left  : Wishes (interactive) · Outliner · Phase Tracker
  Center: Sphere (with bud overlay + revision rings) · Inner Graph (split)
  Right : phase-specific panels (Properties / Root Zone / Fruits /
          Horizon / Inbox / Bridges / Deep DNA / Publish)
  Bottom: draggable Boot Log huddle.

  Selection + WishGarden flow via Svelte context. See
  docs/products/wishing-tree/PHASES.md.
-->
<script lang="ts">
	import { setContext } from 'svelte';
	import IntroSequence from './IntroSequence.svelte';
	import SoulskinSphere from './SoulskinSphere.svelte';
	import InnerGraph from './InnerGraph.svelte';
	import Outliner from './Outliner.svelte';
	import PropertiesPanel from './PropertiesPanel.svelte';
	import UploadsDock from './UploadsDock.svelte';
	import DeepDnaInspector from './DeepDnaInspector.svelte';
	import FoldPanel from './primitives/FoldPanel.svelte';
	import Huddle from './primitives/Huddle.svelte';
	import PeelLayer from './primitives/PeelLayer.svelte';
	import Buds from './Buds.svelte';
	import RevisionRings from './RevisionRings.svelte';
	import Fruits from './Fruits.svelte';
	import RootZone from './RootZone.svelte';
	import Horizon from './Horizon.svelte';
	import TransmissionInbox from './TransmissionInbox.svelte';
	import Bridges from './Bridges.svelte';
	import PublishPanel from './PublishPanel.svelte';
	import PhaseTracker from './PhaseTracker.svelte';
	import { PALETTE } from './style/palette.js';
	import { SFX, toggleMute, isMuted } from './style/sfx.js';
	import { Selection, SELECTION_KEY } from './selection.svelte.js';
	import { WishGarden, type Branch } from './wishes.svelte.js';

	const selection = new Selection();
	setContext(SELECTION_KEY, selection);
	const garden = new WishGarden();

	let booted = $state(false);
	let crtOn = $state(true);
	let peelOpen = $state(false);
	let muted = $state(isMuted());

	let hue = $state(280);
	let moodIndex = $state(0);
	let splitView = $state(true);
	let dreamType: 'avatar' | 'agent' | 'tool' | 'relic' | 'field' | 'guild' = $state('field');
	let phaseTab: 0 | 1 | 2 | 3 | 4 = $state(0);
	let published = $state(false);

	const moods: Array<'idle' | 'thinking' | 'wishing' | 'granting' | 'sealing'> = [
		'idle',
		'thinking',
		'wishing',
		'granting',
		'sealing'
	];
	const mood = $derived(moods[moodIndex % moods.length]);
	const sphereSize = $derived(splitView ? 320 : 440);

	// Auto-mood from garden activity
	$effect(() => {
		const ripening = garden.wishes.some((w) => w.state === 'ripening');
		const ripe = garden.wishes.some((w) => w.state === 'ripe');
		if (ripe) moodIndex = 3; // granting
		else if (ripening) moodIndex = 1; // thinking
	});

	let draft = $state('');
	let nextBranch: Branch = $state('N');
	const branches: Branch[] = ['N', 'E', 'S', 'W'];

	function tieWish() {
		const w = garden.tie(draft, nextBranch);
		if (!w) return;
		draft = '';
		nextBranch = branches[(branches.indexOf(nextBranch) + 1) % 4];
		SFX.wish();
		moodIndex = 2;
		setTimeout(() => (moodIndex = 0), 1200);
	}

	function cycleMood() {
		moodIndex = (moodIndex + 1) % moods.length;
		SFX.fold();
	}

	function toggleSound() {
		muted = toggleMute();
	}

	function onPublish() {
		published = true;
	}
</script>

<svelte:head>
	<title>The Wishing Tree · Phase 0</title>
</svelte:head>

{#if !booted}
	<IntroSequence onready={() => (booted = true)} />
{:else}
	<div class="wt" class:wt-crt={crtOn} data-off={!crtOn}>
		<header class="top">
			<div class="brand">
				<span class="logo">▲</span>
				<span class="name">THE WISHING TREE</span>
				<span class="phase">REV {garden.revision}</span>
			</div>
			<nav class="phase-tabs" aria-label="Phase tabs">
				{#each [0, 1, 2, 3, 4] as p (p)}
					<button
						class="ptab"
						class:active={phaseTab === p}
						type="button"
						onclick={() => (phaseTab = p as 0 | 1 | 2 | 3 | 4)}
					>
						P{p}
					</button>
				{/each}
			</nav>
			<div class="controls">
				<label class="sel">
					TYPE
					<select bind:value={dreamType}>
						<option value="field">FIELD</option>
						<option value="avatar">AVATAR</option>
						<option value="agent">AGENT</option>
						<option value="tool">TOOL</option>
						<option value="relic">RELIC</option>
						<option value="guild">GUILD</option>
					</select>
				</label>
				<button class="ctrl" type="button" onclick={() => (splitView = !splitView)} aria-pressed={splitView}>
					{splitView ? '◐ SPLIT' : '◯ OUTER'}
				</button>
				<button class="ctrl" type="button" onclick={() => (crtOn = !crtOn)} aria-pressed={crtOn}>
					CRT {crtOn ? 'ON' : 'OFF'}
				</button>
				<button class="ctrl" type="button" onclick={toggleSound} aria-pressed={!muted}>
					SFX {muted ? 'OFF' : 'ON'}
				</button>
				<button class="ctrl" type="button" onclick={cycleMood}>
					MOOD · {mood.toUpperCase()}
				</button>
			</div>
		</header>

		<main class="grid">
			<aside class="rail left">
				<FoldPanel title="WISHES ({garden.wishes.length})">
					<div class="wish-form">
						<input
							class="wish-input"
							placeholder="tie a wish…"
							bind:value={draft}
							onkeydown={(e) => {
								if (e.key === 'Enter') tieWish();
							}}
						/>
						<select bind:value={nextBranch} class="branch-sel" aria-label="branch">
							{#each branches as b (b)}
								<option value={b}>{b}</option>
							{/each}
						</select>
						<button class="wish-btn" type="button" onclick={tieWish}>TIE</button>
					</div>
					<div class="wish-counts">
						<span>tied <strong>{garden.count('tied')}</strong></span>
						<span>budding <strong>{garden.count('budding')}</strong></span>
						<span>ripening <strong>{garden.count('ripening')}</strong></span>
						<span>ripe <strong>{garden.count('ripe')}</strong></span>
						<span>plucked <strong>{garden.count('plucked')}</strong></span>
					</div>
				</FoldPanel>

				<FoldPanel title="OUTLINER · {dreamType}">
					<Outliner {dreamType} name="The Wishing Tree" />
				</FoldPanel>

				<FoldPanel title="PHASE TRACKER">
					<PhaseTracker {garden} {published} />
				</FoldPanel>
			</aside>

			<section class="stage">
				<div class="viewport" class:split={splitView}>
					<div class="outer-view">
						<div class="viewtag">OUTER · SHELL</div>
						<div class="sphere-stack" style="width: {sphereSize}px; height: {sphereSize}px;">
							<RevisionRings count={garden.revision} size={sphereSize} />
							<SoulskinSphere size={sphereSize} {hue} {mood} onpeel={() => (peelOpen = true)} />
							<Buds wishes={garden.wishes} size={sphereSize} />
						</div>
					</div>
					{#if splitView}
						<div class="inner-view">
							<div class="viewtag">INNER · GRAPH</div>
							<InnerGraph />
						</div>
					{/if}
				</div>
				<div class="stage-footer">
					<span class="tag">SOULSKIN · 4 LAYERS</span>
					<span class="tag">RES 8 · LAYER-DEPTH 3</span>
					<span class="tag">STAGE · SEED</span>
					<span class="tag">REV · {garden.revision}</span>
					<button class="tag-btn" type="button" onclick={() => (peelOpen = true)}>
						⌕ PEEL (modal)
					</button>
				</div>
			</section>

			<aside class="rail right">
				{#if phaseTab === 0}
					<FoldPanel title="P0 · PROPERTIES" align="right">
						<PropertiesPanel />
					</FoldPanel>
					<FoldPanel title="P0 · UPLOADS" align="right">
						<UploadsDock />
					</FoldPanel>
					<FoldPanel title="P0 · CANOPY" align="right">
						<label class="knob">
							HUE
							<input type="range" min="0" max="360" bind:value={hue} />
							<span class="val">{hue}°</span>
						</label>
						<div class="swatches">
							{#each Object.entries(PALETTE) as [k, v] (k)}
								<span class="sw" title="{k} {v}" style="background:{v}" aria-label={k}></span>
							{/each}
						</div>
					</FoldPanel>
				{:else if phaseTab === 1}
					<FoldPanel title="P1 · FRUITS · pluck → .ball.json" align="right">
						<Fruits {garden} />
					</FoldPanel>
					<FoldPanel title="P1 · ROOT ZONE · keys" align="right">
						<RootZone />
					</FoldPanel>
					<FoldPanel title="P1 · PROPERTIES" align="right">
						<PropertiesPanel />
					</FoldPanel>
				{:else if phaseTab === 2}
					<FoldPanel title="P2 · HORIZON · sibling trees" align="right">
						<Horizon {garden} />
					</FoldPanel>
					<FoldPanel title="P2 · INBOX · wind-carried seeds" align="right">
						<TransmissionInbox />
					</FoldPanel>
					<FoldPanel title="P2 · UPLOADS" align="right">
						<UploadsDock />
					</FoldPanel>
				{:else if phaseTab === 3}
					<FoldPanel title="P3 · BRIDGES · blender / unreal / ws" align="right">
						<Bridges />
					</FoldPanel>
					<FoldPanel title="P3 · DEEP DNA · bytes / hashes / sigs" align="right">
						<DeepDnaInspector />
					</FoldPanel>
					<FoldPanel title="P3 · CONSTELLATION" align="right">
						<p class="link">
							<a href="/tree/forest">▶ open the constellation view → /tree/forest</a>
						</p>
					</FoldPanel>
				{:else if phaseTab === 4}
					<FoldPanel title="P4 · PUBLISH · the tree publishes the tree" align="right">
						<PublishPanel {garden} {dreamType} />
						<button
							class="quiet"
							type="button"
							onclick={onPublish}
							style="margin-top: 6px;"
						>
							mark phase 4 active
						</button>
					</FoldPanel>
					<FoldPanel title="P4 · DEEP DNA" align="right">
						<DeepDnaInspector />
					</FoldPanel>
				{/if}
			</aside>
		</main>

		<Huddle name="BOOT LOG">
			<ul class="boot-log">
				<li>&gt; phase 0 online</li>
				<li>&gt; soulskin alive · mood: {mood}</li>
				<li>&gt; outliner · {dreamType}</li>
				<li>&gt; selection · {selection.label}</li>
				<li>&gt; wishes {garden.wishes.length} · plucks {garden.plucks} · winds {garden.transmissions}</li>
				<li>&gt; revision {garden.revision} · published {published ? 'yes' : 'no'}</li>
			</ul>
		</Huddle>

		<PeelLayer bind:open={peelOpen} title="DEEP PEEL · recursive interior">
			<p class="peel-hint">use SPLIT view up top for inline inner graph. this modal is for nested DreamBalls (Phase 1+).</p>
			<InnerGraph />
		</PeelLayer>
	</div>
{/if}

<style>
	.wt {
		position: fixed;
		inset: 0;
		background:
			radial-gradient(circle at 50% 40%, color-mix(in srgb, var(--wt-trunk) 30%, transparent), transparent 60%),
			var(--wt-void);
		color: var(--wt-haze);
		font-family: var(--wt-font-mono);
		display: flex;
		flex-direction: column;
		overflow: hidden;
	}
	.top {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 14px;
		padding: 8px 14px;
		border-bottom: 3px solid var(--wt-fruit-gold);
		background: repeating-linear-gradient(90deg, var(--wt-void) 0 3px, var(--wt-root) 3px 6px);
		z-index: 2;
		flex-wrap: wrap;
	}
	.brand {
		display: flex;
		align-items: baseline;
		gap: 12px;
	}
	.logo {
		color: var(--wt-fruit-gold);
		font-size: 22px;
		text-shadow: 2px 2px 0 var(--wt-void);
	}
	.name {
		letter-spacing: 0.32em;
		color: var(--wt-wish-violet);
		font-size: 13px;
		font-weight: 700;
		text-shadow: 1px 1px 0 var(--wt-void);
	}
	.phase {
		font-size: 10px;
		color: var(--wt-mist);
		letter-spacing: 0.25em;
	}
	.phase-tabs {
		display: flex;
		gap: 0;
	}
	.ptab {
		all: unset;
		cursor: pointer;
		font-size: 11px;
		font-weight: 700;
		letter-spacing: 0.25em;
		padding: 6px 10px;
		color: var(--wt-mist);
		border: 2px solid var(--wt-branch);
		border-right: 0;
		background: var(--wt-root);
	}
	.ptab:last-child {
		border-right: 2px solid var(--wt-branch);
	}
	.ptab.active {
		color: var(--wt-void);
		background: var(--wt-fruit-gold);
		border-color: var(--wt-fruit-gold);
		box-shadow: inset 1px 1px 0 var(--wt-haze);
	}
	.ptab:hover {
		color: var(--wt-fruit-gold);
	}
	.ptab.active:hover {
		color: var(--wt-void);
	}
	.controls {
		display: flex;
		gap: 6px;
		align-items: center;
		flex-wrap: wrap;
	}
	.sel {
		display: flex;
		gap: 4px;
		font-size: 10px;
		letter-spacing: 0.2em;
		color: var(--wt-frost-cyan);
		align-items: center;
	}
	.sel select {
		background: var(--wt-root);
		color: var(--wt-fruit-gold);
		border: 2px solid var(--wt-fruit-gold);
		font-family: inherit;
		font-size: 10px;
		padding: 3px 6px;
		letter-spacing: 0.15em;
	}
	.ctrl {
		all: unset;
		cursor: pointer;
		font-family: inherit;
		font-size: 10px;
		letter-spacing: 0.25em;
		padding: 4px 8px;
		color: var(--wt-frost-cyan);
		border: 2px solid var(--wt-branch);
		background: var(--wt-root);
		box-shadow: inset 1px 1px 0 var(--wt-haze), inset -1px -1px 0 var(--wt-void);
	}
	.ctrl[aria-pressed='true'] {
		color: var(--wt-fruit-gold);
		border-color: var(--wt-fruit-gold);
	}
	.ctrl:hover {
		color: var(--wt-wish-violet);
		border-color: var(--wt-wish-violet);
	}
	.grid {
		flex: 1;
		display: grid;
		grid-template-columns: minmax(260px, 1fr) 2.4fr minmax(280px, 1fr);
		gap: 10px;
		padding: 12px;
		min-height: 0;
	}
	.rail {
		display: flex;
		flex-direction: column;
		gap: 8px;
		min-width: 0;
		overflow: auto;
	}
	.stage {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 22px;
		position: relative;
	}
	.viewport {
		display: grid;
		grid-template-columns: 1fr;
		gap: 18px;
		align-items: center;
		justify-items: center;
		width: 100%;
	}
	.viewport.split {
		grid-template-columns: 1fr 1fr;
	}
	.outer-view,
	.inner-view {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 10px;
		width: 100%;
	}
	.inner-view {
		max-width: 340px;
	}
	.viewtag {
		font-size: 10px;
		letter-spacing: 0.3em;
		color: var(--wt-fruit-gold);
		padding: 3px 10px;
		background: var(--wt-void);
		border: 2px solid var(--wt-fruit-gold);
		text-shadow: 1px 1px 0 var(--wt-void);
	}
	.sphere-stack {
		position: relative;
		display: grid;
		place-items: center;
	}
	.stage-footer {
		display: flex;
		gap: 6px;
		flex-wrap: wrap;
		justify-content: center;
	}
	.tag,
	.tag-btn {
		font-size: 10px;
		letter-spacing: 0.25em;
		padding: 3px 8px;
		border: 2px solid var(--wt-branch);
		color: var(--wt-frost-cyan);
		background: rgba(5, 7, 20, 0.8);
		box-shadow: inset 1px 1px 0 var(--wt-haze);
	}
	.tag-btn {
		all: unset;
		cursor: pointer;
		border: 2px solid var(--wt-wish-violet);
		color: var(--wt-wish-violet);
		padding: 3px 8px;
		font-size: 10px;
		letter-spacing: 0.25em;
	}
	.tag-btn:hover {
		color: var(--wt-fruit-gold);
		border-color: var(--wt-fruit-gold);
	}
	.wish-form {
		display: grid;
		grid-template-columns: 1fr auto auto;
		gap: 6px;
		margin-bottom: 8px;
	}
	.wish-input,
	.branch-sel {
		background: var(--wt-void);
		border: 2px solid var(--wt-branch);
		color: var(--wt-haze);
		font-family: inherit;
		font-size: 12px;
		padding: 6px 8px;
	}
	.branch-sel {
		color: var(--wt-fruit-gold);
		border-color: var(--wt-fruit-gold);
	}
	.wish-input:focus {
		outline: none;
		border-color: var(--wt-fruit-gold);
	}
	.wish-btn {
		all: unset;
		cursor: pointer;
		font-size: 11px;
		letter-spacing: 0.2em;
		padding: 6px 10px;
		color: var(--wt-void);
		background: var(--wt-fruit-gold);
		border: 2px solid var(--wt-fruit-gold);
		box-shadow: inset 1px 1px 0 var(--wt-haze), inset -1px -1px 0 var(--wt-amber);
		font-weight: 700;
	}
	.wish-counts {
		display: grid;
		grid-template-columns: repeat(5, 1fr);
		gap: 4px;
		font-size: 9px;
		text-align: center;
		color: var(--wt-mist);
	}
	.wish-counts strong {
		display: block;
		color: var(--wt-fruit-gold);
		font-size: 12px;
	}
	.knob {
		display: flex;
		flex-direction: column;
		gap: 6px;
		font-size: 11px;
		letter-spacing: 0.2em;
		color: var(--wt-frost-cyan);
	}
	.knob .val {
		color: var(--wt-fruit-gold);
		font-size: 12px;
	}
	.swatches {
		display: grid;
		grid-template-columns: repeat(8, 1fr);
		gap: 3px;
		margin-top: 10px;
	}
	.sw {
		aspect-ratio: 1;
		border: 2px solid var(--wt-void);
		box-shadow: inset 1px 1px 0 rgba(255, 255, 255, 0.3);
	}
	.boot-log {
		list-style: none;
		padding: 0;
		margin: 0;
		color: var(--wt-sap-green);
		font-size: 10px;
		line-height: 1.6;
	}
	.peel-hint {
		color: var(--wt-wish-violet);
		font-size: 11px;
		margin: 0 0 10px;
	}
	.link a {
		color: var(--wt-frost-cyan);
		font-size: 11px;
	}
	.quiet {
		all: unset;
		cursor: pointer;
		display: block;
		text-align: center;
		font-size: 10px;
		color: var(--wt-mist);
		letter-spacing: 0.2em;
		border: 1px dashed var(--wt-branch);
		padding: 4px;
	}
	.quiet:hover {
		color: var(--wt-wish-violet);
		border-color: var(--wt-wish-violet);
	}
</style>
