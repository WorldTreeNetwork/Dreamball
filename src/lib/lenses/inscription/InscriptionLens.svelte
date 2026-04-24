<!--
  InscriptionLens.svelte — Story 5.4 / FR17

  Renders an inscription in 3D by dispatching to one of five surface components.
  Implements the surface registry + fallback chain per ADR 2026-04-24-surface-registry.

  Responsibilities:
    • Reads `surface` tag from the Inscription (D-016 consumer).
    • Fetches body bytes via store.inscriptionBody(inscriptionFp) (D-007 / AC3 / TC13).
    • Decodes bytes as UTF-8 text (MVP; binary bodies deferred).
    • Dispatches to a registered surface component; walks fallback chain when needed (AC2).
    • Does NOT write to LadybugDB or CAS (SEC11).

  Surface registry (ADR 2026-04-24-surface-registry §2):
    WEB_SURFACES lists the five surfaces this Web lens natively renders.
    `scroll` is the canonical baseline — always registered, always the final fallback.

  Fallback chain walk (ADR §4, normative):
    Given inscription with surface "splat-scene" and fallback: ["tablet", "scroll"]:
      1. "splat-scene" not in WEB_SURFACES → walk fallback array.
      2. "tablet" in WEB_SURFACES → render Tablet; emit surface-fallback log.
    Given unknown surface with no fallback / empty fallback:
      → render Scroll; emit surface-fallback log.
    Given cycle (surface lists itself or predecessor):
      → emit surface-fallback-cycle log; render Scroll.
    Local walk bound: ≤ 10 hops (DoS guard per ADR implementation note).

  CROSS-RUNTIME INVARIANT:
    No @ladybugdb/core or kuzu-wasm imports here. All store access via `store` prop.
    Grep asserts this in InscriptionLens.test.ts (AC3).

  Coord-frame: position is cartesian local-to-room-origin (ADR 2026-04-24-coord-frames §2).

  AC4 latency budget: first visible text frame <300ms on mid-range laptop.
  The store.inscriptionBody call and UTF-8 decode happen in onMount; the Canvas
  renders synchronously with a loading placeholder until body is ready.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import { Canvas } from '@threlte/core';
  import type { StoreAPI } from '../../../memory-palace/store-types.js';
  import Scroll from './surfaces/Scroll.svelte';
  import Tablet from './surfaces/Tablet.svelte';
  import BookSpread from './surfaces/BookSpread.svelte';
  import EtchedWall from './surfaces/EtchedWall.svelte';
  import FloatingGlyph from './surfaces/FloatingGlyph.svelte';

  // ─── Surface registry (ADR 2026-04-24-surface-registry §2) ──────────────────

  /**
   * The five surfaces this Web lens natively renders.
   * `scroll` is the canonical baseline and MUST always be included.
   * Order is not significant; registration membership is what matters.
   */
  const WEB_SURFACES = new Set([
    'scroll',
    'tablet',
    'book-spread',
    'etched-wall',
    'floating-glyph',
  ]);

  /** Maximum fallback walk hops (DoS guard per ADR implementation note). */
  const MAX_WALK_HOPS = 10;

  // ─── Props ───────────────────────────────────────────────────────────────────

  interface Props {
    /**
     * Blake3 fp of the inscription to render.
     * Used as argument to store.inscriptionBody(inscriptionFp) (D-007 / AC3).
     */
    inscriptionFp: string;

    /**
     * Surface tag from the inscription envelope (D-016 / Inscription.surface).
     * Open-enum string: "scroll" | "tablet" | "book-spread" | "etched-wall" |
     * "floating-glyph" | any future surface.
     */
    surface: string;

    /**
     * Optional fallback chain from the inscription envelope (ADR §4).
     * Ordered list of surfaces to try if `surface` is not registered.
     * Absent or empty → walk straight to "scroll" baseline.
     */
    fallback?: string[];

    /**
     * StoreAPI instance — MUST be store.server.ts or store.browser.ts.
     * Never @ladybugdb/core or kuzu-wasm directly (D-007 / TC12 / AC3).
     */
    store?: StoreAPI | null;

    /**
     * Callback fired after first body render — used by play-test for
     * NFR10 first-visible-frame latency (target <300ms per AC4).
     */
    onFirstFrame?: (t_ms: number) => void;

    /** Canvas width in pixels (default: 640). */
    width?: number;

    /** Canvas height in pixels (default: 480). */
    height?: number;
  }

  const {
    inscriptionFp,
    surface,
    fallback = [],
    store = null,
    onFirstFrame,
    width = 640,
    height = 480,
  }: Props = $props();

  // ─── State ───────────────────────────────────────────────────────────────────

  /** Decoded body text (UTF-8). Populated by inscriptionBody() on mount. */
  let bodyText = $state('');

  /** Whether the store fetch has completed. */
  let loadComplete = $state(false);

  /** The resolved surface name after fallback walk. */
  let resolvedSurface = $state('scroll');

  let firstFrameFired = false;
  const t0 = typeof performance !== 'undefined' ? performance.now() : Date.now();

  // ─── Fallback chain walk (ADR 2026-04-24-surface-registry, normative) ────────

  /**
   * Walk the surface registry + fallback chain to find the first registered
   * surface. Returns the resolved surface name.
   *
   * Algorithm (normative per ADR):
   *   1. If `requested` is in WEB_SURFACES → return it directly (no walk needed).
   *   2. If fallback is empty/absent → return "scroll" baseline; emit surface-fallback.
   *   3. Walk fallback array: for each entry, if registered → return it; emit surface-fallback.
   *   4. Detect cycles: if a surface appears twice in the walk sequence → emit
   *      surface-fallback-cycle and break to "scroll".
   *   5. Walk bound: stop after MAX_WALK_HOPS to guard against pathological chains.
   *   6. If walk exhausted with no match → return "scroll" baseline; emit surface-fallback.
   */
  function resolveSurface(requested: string, fallbackChain: string[]): string {
    // Case 1: known surface — no fallback walk needed.
    if (WEB_SURFACES.has(requested)) {
      return requested;
    }

    // Cases 2–6: unknown surface — walk the fallback chain.
    const visited = new Set<string>([requested]);
    const chain = (fallbackChain ?? []).slice(0, MAX_WALK_HOPS);

    for (const candidate of chain) {
      // Cycle detection: candidate already visited.
      if (visited.has(candidate)) {
        console.warn(JSON.stringify({
          level: 'warn',
          event: 'surface-fallback-cycle',
          requested,
          cycle_at: candidate,
          lens: 'web',
        }));
        // Break walk; fall through to scroll baseline.
        break;
      }
      visited.add(candidate);

      if (WEB_SURFACES.has(candidate)) {
        // Found a registered surface in the fallback chain.
        console.info(JSON.stringify({
          level: 'info',
          event: 'surface-fallback',
          requested,
          resolved: candidate,
          lens: 'web',
        }));
        return candidate;
      }
    }

    // No match in fallback chain (or empty chain) → scroll baseline.
    console.info(JSON.stringify({
      level: 'info',
      event: 'surface-fallback',
      requested,
      resolved: 'scroll',
      lens: 'web',
    }));
    return 'scroll';
  }

  // ─── Mount logic ─────────────────────────────────────────────────────────────

  onMount(() => {
    // Resolve surface synchronously (before store fetch).
    resolvedSurface = resolveSurface(surface, fallback);

    (async () => {
      if (store) {
        try {
          const bytes = await store.inscriptionBody(inscriptionFp);
          bodyText = new TextDecoder('utf-8').decode(bytes);
        } catch (e) {
          console.warn('[InscriptionLens] store.inscriptionBody failed:', e);
          bodyText = '';
        }
      }
      loadComplete = true;
    })();
  });

  // Fire onFirstFrame once body is loaded.
  $effect(() => {
    if (loadComplete && !firstFrameFired) {
      firstFrameFired = true;
      const elapsed = (typeof performance !== 'undefined' ? performance.now() : Date.now()) - t0;
      onFirstFrame?.(elapsed);
    }
  });
</script>

<!--
  Wrapper div carries data-inscription-fp and data-surface for Storybook play-test selectors.
-->
<div
  class="inscription-lens"
  data-inscription-fp={inscriptionFp}
  data-surface={resolvedSurface}
  style="width: {width}px; height: {height}px; position: relative;"
>
  {#if !loadComplete}
    <div class="inscription-loading" aria-live="polite">Loading inscription…</div>
  {:else}
    <!--
      Surface dispatch: wrapped in a Threlte <Canvas> so surface components can use
      <T.*> and <Text> (troika-three-text) as real Three.js meshes in the scene graph.
      Each surface renders its body via @threlte/extras Text on a 3D mesh, plus a
      hidden DOM mirror element for play-test querySelector assertions (JSDOM/WebGL
      cannot read pixel output; the DOM mirror is the testable surface).
      All five surfaces accept `body` as the decoded text string.
    -->
    <Canvas>
      {#if resolvedSurface === 'scroll'}
        <Scroll body={bodyText} />
      {:else if resolvedSurface === 'tablet'}
        <Tablet body={bodyText} />
      {:else if resolvedSurface === 'book-spread'}
        <BookSpread body={bodyText} />
      {:else if resolvedSurface === 'etched-wall'}
        <EtchedWall body={bodyText} />
      {:else if resolvedSurface === 'floating-glyph'}
        <FloatingGlyph body={bodyText} />
      {:else}
        <!-- Defensive: should not reach here — resolveSurface always returns a known name. -->
        <Scroll body={bodyText} />
      {/if}
    </Canvas>
  {/if}
</div>

<style>
  .inscription-lens {
    display: block;
    background: #0a0c16;
    overflow: hidden;
    position: relative;
  }

  .inscription-loading {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #c8d4a3;
    font-family: monospace;
    font-size: 14px;
  }
</style>
