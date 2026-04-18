<!--
  DreamBallViewer — the top-level component consumers use to render a
  DreamBall. Switches lens on the `lens` prop, filters slots through
  the backend's permission resolution so the observer persona sees only
  public slots.

  See docs/PROTOCOL.md §12 + docs/VISION.md §12 for the lens semantics.
-->
<script lang="ts">
	import type { DreamBall, Fingerprint } from '../generated/types.js';
	import type { JellyBackend } from '../backend/JellyBackend.js';
	import type { LensName } from '../lenses/lens-types.js';
	import ThumbnailLens from '../lenses/ThumbnailLens.svelte';
	import AvatarLens from '../lenses/AvatarLens.svelte';
	import KnowledgeGraphLens from '../lenses/KnowledgeGraphLens.svelte';
	import EmotionalStateLens from '../lenses/EmotionalStateLens.svelte';
	import OmnisphericalLens from '../lenses/OmnisphericalLens.svelte';
	import FlatLens from '../lenses/FlatLens.svelte';
	import PhoneLens from '../lenses/PhoneLens.svelte';
	import SplatLens from '../lenses/SplatLens.svelte';
	import { isSplatAsset } from '../splat/media-types.js';

	interface Props {
		ball: DreamBall;
		lens?: LensName;
		/** Observer's identity, for guild-policy slot filtering. Null means
		 *  anonymous observer (public slots only). */
		viewer?: Fingerprint | null;
		backend?: JellyBackend | null;
		/** Hint to prefer WebGPU where available (not yet wired). */
		preferGpu?: boolean;
	}

	let { ball, lens = 'thumbnail', viewer = null, backend = null, preferGpu = false }: Props = $props();
	$effect(() => void preferGpu);

	let filteredBall: DreamBall = $state(ball);

	// If the caller asks for the `avatar` lens but the primary look asset is
	// a gaussian splat, auto-upgrade to the `splat` lens. Splats are the
	// topology-free rendering path — the omnispherical "graticule" form.
	const effectiveLens: LensName = $derived(
		lens === 'avatar' && isSplatAsset(filteredBall.look?.asset?.[0]?.['media-type'])
			? 'splat'
			: lens
	);

	$effect(() => {
		const currentBall = ball;
		if (!backend) {
			filteredBall = currentBall;
			return;
		}
		let cancelled = false;
		void backend.resolvePermittedSlots(currentBall, viewer).then((allowed) => {
			if (cancelled) return;
			filteredBall = applyPermissionFilter(currentBall, allowed);
		});
		return () => {
			cancelled = true;
		};
	});

	function applyPermissionFilter(b: DreamBall, allowed: string[]): DreamBall {
		const allowedSet = new Set(allowed);
		const out = { ...b };
		const privateSlots = [
			'memory',
			'knowledge-graph',
			'emotional-register',
			'interaction-set',
			'act',
			'personality-master-prompt',
			'secret',
			'feel'
		];
		for (const s of privateSlots) {
			if (!allowedSet.has(s)) {
				delete (out as Record<string, unknown>)[s];
			}
		}
		return out;
	}
</script>

<div class="viewer" data-lens={effectiveLens}>
	{#if effectiveLens === 'thumbnail'}
		<ThumbnailLens ball={filteredBall} />
	{:else if effectiveLens === 'avatar'}
		<AvatarLens ball={filteredBall} />
	{:else if effectiveLens === 'splat'}
		<SplatLens ball={filteredBall} />
	{:else if effectiveLens === 'knowledge-graph'}
		<KnowledgeGraphLens ball={filteredBall} />
	{:else if effectiveLens === 'emotional-state'}
		<EmotionalStateLens ball={filteredBall} />
	{:else if effectiveLens === 'omnispherical'}
		<OmnisphericalLens ball={filteredBall} />
	{:else if effectiveLens === 'flat'}
		<FlatLens ball={filteredBall} />
	{:else if effectiveLens === 'phone'}
		<PhoneLens ball={filteredBall} />
	{:else}
		<FlatLens ball={filteredBall} />
	{/if}
</div>

<style>
	.viewer {
		display: contents;
	}
</style>
