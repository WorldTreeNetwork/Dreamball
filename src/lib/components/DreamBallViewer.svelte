<!--
  DreamBallViewer — the top-level component consumers use to render a
  DreamBall. Switches lens on the `lens` prop, filters slots through
  the backend's permission resolution so the observer persona sees only
  public slots.

  S5.5 addition: `store` prop wires PalaceLens `navigate` events into
  store.recordTraversal (D-007 boundary — SEC11 ordering). The lens
  dispatches CustomEvent('navigate', {kind:'room', fp}); this viewer
  intercepts it, calls recordTraversal, and the renderer arc is painted
  only after the returned promise resolves (SEC11).

  See docs/PROTOCOL.md §12 + docs/VISION.md §12 for the lens semantics.
-->
<script lang="ts">
	import type { DreamBall, Fingerprint } from '../generated/types.js';
	import type { JellyBackend } from '../backend/JellyBackend.js';
	import type { LensName } from '../lenses/lens-types.js';
	import type { StoreAPI } from '../../memory-palace/store-types.js';
	import ThumbnailLens from '../lenses/ThumbnailLens.svelte';
	import AvatarLens from '../lenses/AvatarLens.svelte';
	import KnowledgeGraphLens from '../lenses/KnowledgeGraphLens.svelte';
	import EmotionalStateLens from '../lenses/EmotionalStateLens.svelte';
	import OmnisphericalLens from '../lenses/OmnisphericalLens.svelte';
	import FlatLens from '../lenses/FlatLens.svelte';
	import PhoneLens from '../lenses/PhoneLens.svelte';
	import SplatLens from '../lenses/SplatLens.svelte';
	import PalaceLens from '../lenses/palace/PalaceLens.svelte';
	import RoomLens from '../lenses/room/RoomLens.svelte';
	import InscriptionLens from '../lenses/inscription/InscriptionLens.svelte';
	import { isSplatAsset } from '../splat/media-types.js';
	import { untrack } from 'svelte';

	/**
	 * Svelte action: attaches a `navigate` event listener to the mounted node.
	 * Used on the palace-lens wrapper div to capture bubbled navigate events
	 * from PalaceLens without using the non-standard `onnavigate` HTML attribute
	 * (Svelte 5 enforces known HTML attributes — S5.2 AC5 pattern).
	 */
	function navigateCatcher(node: HTMLElement) {
		node.addEventListener('navigate', handleNavigate);
		return {
			destroy() {
				node.removeEventListener('navigate', handleNavigate);
			}
		};
	}

	interface Props {
		ball: DreamBall;
		lens?: LensName;
		/** Observer's identity, for guild-policy slot filtering. Null means
		 *  anonymous observer (public slots only). */
		viewer?: Fingerprint | null;
		backend?: JellyBackend | null;
		/** Hint to prefer WebGPU where available (not yet wired). */
		preferGpu?: boolean;
		/**
		 * StoreAPI instance for palace-walk traversal events (S5.5 — FR18).
		 *
		 * When provided, the viewer intercepts `navigate` CustomEvents from
		 * PalaceLens and routes them into store.recordTraversal (D-007 verb).
		 * The traversal arc is painted only after recordTraversal resolves
		 * (SEC11 ordering — renderer awaits Blake3 persistence).
		 *
		 * When null, navigate events bubble to the parent uncaptured.
		 */
		store?: StoreAPI | null;
		/**
		 * Palace fp for the current palace session (required for recordTraversal
		 * when store is provided). When null, traversal events are not recorded.
		 */
		palaceFp?: string | null;
		/**
		 * Callback invoked after a traversal arc is painted (SEC11: called only
		 * after recordTraversal resolves). Receives the traversal result so the
		 * parent can update aqueduct-flow uniforms.
		 */
		onTraversal?: (result: import('../../memory-palace/store-types.js').RecordTraversalResult) => void;
	}

	let {
		ball,
		lens = 'thumbnail',
		viewer = null,
		backend = null,
		preferGpu = false,
		store = null,
		palaceFp = null,
		onTraversal,
	}: Props = $props();
	$effect(() => void preferGpu);

	/**
	 * Track the "current room" fp so subsequent navigate events carry a valid
	 * fromFp. Starts null (no previous room) — on first navigate fromFp defaults
	 * to the palace fp itself (matching Zig CLI convention for the first move).
	 */
	let currentRoomFp: string | null = $state(null);

	/**
	 * Handle navigate CustomEvent from PalaceLens (AC4 S5.2).
	 * Routes into store.recordTraversal (D-007) — SEC11 ordering.
	 *
	 * The lens dispatches: CustomEvent('navigate', {detail: {kind:'room', fp}}).
	 * This handler:
	 *   1. Extracts toFp from the event detail.
	 *   2. Calls store.recordTraversal — only after this resolves does the arc paint.
	 *   3. Updates currentRoomFp so the next navigate has a valid fromFp.
	 *   4. Invokes onTraversal callback with the result (for arc repaint).
	 */
	async function handleNavigate(event: Event): Promise<void> {
		const detail = (event as CustomEvent<{ kind: string; fp: string }>).detail;
		if (!detail || detail.kind !== 'room') return;

		const toFp = detail.fp;
		const fromFp = currentRoomFp ?? palaceFp ?? toFp;

		if (!store || !palaceFp) {
			// No store → let event bubble to parent for external handling.
			return;
		}

		// fromFp === toFp on first navigate (no-op traversal is fine — store is idempotent-ish).
		try {
			const result = await store.recordTraversal({
				palaceFp,
				fromFp,
				toFp,
			});
			// SEC11: only update state + fire callback after promise resolves
			currentRoomFp = toFp;
			onTraversal?.(result);
		} catch (err) {
			// Log but don't crash the renderer — graceful degradation.
			console.warn('[DreamBallViewer] recordTraversal failed:', err);
			// Still update currentRoomFp so subsequent navigates work.
			currentRoomFp = toFp;
		}
	}

	let filteredBall: DreamBall = $state(untrack(() => ball));

	/**
	 * Inscription dispatch meta (S5.4) — populated via store.inscriptionMeta when
	 * lens === 'inscription'. Null until resolved; InscriptionLens renders its
	 * own loading placeholder in the meantime. Kept on the viewer rather than
	 * the lens so we don't cast through `unknown` to read fields that don't live
	 * on DreamBall.
	 */
	let inscriptionMeta: { surface: string; fallback: string[] } | null = $state(null);

	// If the caller asks for the `avatar` lens but the primary look asset is
	// a gaussian splat, auto-upgrade to the `splat` lens. Splats are the
	// topology-free rendering path — the omnispherical "graticule" form.
	const effectiveLens: LensName = $derived(
		lens === 'avatar' && isSplatAsset(filteredBall.look?.asset?.[0]?.['media-type'])
			? 'splat'
			: lens
	);

	// Fetch inscription dispatch meta when lens resolves to 'inscription' + a store is wired.
	$effect(() => {
		if (effectiveLens !== 'inscription' || !store) {
			inscriptionMeta = null;
			return;
		}
		const fp = filteredBall.identity;
		let cancelled = false;
		void store.inscriptionMeta(fp).then((meta) => {
			if (cancelled) return;
			inscriptionMeta = meta
				? { surface: meta.surface, fallback: meta.fallback }
				: { surface: 'scroll', fallback: [] };
		}).catch((err) => {
			if (cancelled) return;
			console.warn('[DreamBallViewer] store.inscriptionMeta failed:', err);
			inscriptionMeta = { surface: 'scroll', fallback: [] };
		});
		return () => { cancelled = true; };
	});

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
	{:else if effectiveLens === 'palace'}
		<div use:navigateCatcher>
			<PalaceLens palaceFp={filteredBall.identity} {store} />
		</div>
	{:else if effectiveLens === 'room'}
		<RoomLens roomFp={filteredBall.identity} {store} />
	{:else if effectiveLens === 'inscription'}
		<InscriptionLens
			inscriptionFp={filteredBall.identity}
			surface={inscriptionMeta?.surface ?? 'scroll'}
			fallback={inscriptionMeta?.fallback ?? []}
			{store}
		/>
	{:else}
		<FlatLens ball={filteredBall} />
	{/if}
</div>

<style>
	.viewer {
		display: contents;
	}
</style>
