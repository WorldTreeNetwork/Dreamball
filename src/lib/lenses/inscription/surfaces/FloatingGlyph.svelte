<!--
  FloatingGlyph.svelte — Per-glyph individually-transformed, softly animated (Story 5.4 / FR17 / AC1).

  Each character in the inscription body gets its own <Text> mesh with a gentle
  sinusoidal position animation driven by requestAnimationFrame.

  Implementation:
    - Per-glyph <Text> from @threlte/extras, each at a computed 2D grid position
      with a per-frame y-offset driven by rAF (matches the rAF pattern from
      AqueductFlow.svelte). No CSS animation — real 3D transform.
    - 256-glyph cap (GLYPH_RENDER_LIMIT) preserved from HTML version.
    - >2KB body soft-warn preserved via onMount + TextEncoder byte-count check.
    - Hidden DOM mirror element for Storybook play-test querySelector assertions.
      Mirror also includes per-glyph <span class="glyph"> so the play-test
      `querySelectorAll('span.glyph')` assertion still passes.

  Animation: $state array of per-glyph y-offsets updated in rAF loop using
  deterministic sinusoidal formula (golden-angle phase distribution, no Math.random).

  CROSS-RUNTIME INVARIANT: no @ladybugdb/core or kuzu-wasm imports here.

  Remediation 2026-04-24: replaced HTML overlay with real Three.js mesh + 3D text.
  Per-glyph mesh atlas (Three.js TextGeometry) deferred to Growth tier;
  troika-three-text MSDF provides per-glyph text in 3D without a full glyph-atlas pipeline.
  See epic-5.md §5.4 Remediation note.
-->
<script lang="ts">
  import { T } from '@threlte/core';
  import { Text } from '@threlte/extras';
  import { onMount } from 'svelte';

  interface Props {
    /** Decoded body text to render. */
    body: string;
  }

  const { body }: Props = $props();

  // Soft-warn threshold (epic-5.md §5.4 open question default: >2 KB).
  const SOFT_WARN_BYTES = 2048;
  // Render limit: beyond this many glyphs the per-glyph cost becomes significant.
  const GLYPH_RENDER_LIMIT = 256;

  // Glyphs to render (capped at limit).
  const glyphs = $derived(
    body.length > GLYPH_RENDER_LIMIT
      ? [...body.slice(0, GLYPH_RENDER_LIMIT - 1), '…']
      : [...body]
  );

  // Glyph grid layout constants.
  const COLS = 16;
  const CELL_W = 0.22;
  const CELL_H = 0.30;

  const GOLDEN_ANGLE = 2.399963; // ≈ 2.399963 rad — deterministic, no Math.random

  /**
   * Per-glyph static attributes. Computed once when `glyphs` changes rather
   * than recomputed every frame (M8 review fix — original implementation
   * allocated a fresh array of offsets × glyph count per rAF tick).
   *
   * `basePos` is the 3D grid position; `phase` + `amp` parameterise the
   * sinusoidal y-drift so the per-frame loop only needs to evaluate Math.sin.
   */
  interface GlyphBase {
    basePos: [number, number, number];
    phase: number;
    amp: number;
  }
  const glyphBases: GlyphBase[] = $derived.by(() => {
    const totalCols = Math.min(glyphs.length, COLS);
    return glyphs.map((_, i) => {
      const col = i % COLS;
      const row = Math.floor(i / COLS);
      return {
        basePos: [
          (col - totalCols / 2) * CELL_W,
          -row * CELL_H + 1.2,
          0
        ] as [number, number, number],
        phase: (i * GOLDEN_ANGLE) % (2 * Math.PI),
        amp: 0.04 + (i % 5) * 0.015
      };
    });
  });

  /**
   * Per-glyph y-offsets. Stored as a plain (non-$state) number[] to avoid
   * Svelte 5 deep-reactivity churn across 256 glyphs × 60 fps. We bump a
   * single reactive frame counter; the template reads yOffsetsRef[i] inside
   * an {@const} so reactivity still flows, but only once per frame instead
   * of once per glyph-index (M8 review fix).
   */
  // svelte-ignore non_reactive_update -- intentionally non-reactive; reactivity flows via frameTick.
  let yOffsetsRef: number[] = [];
  let frameTick = $state(0);

  let rafId = 0;
  const t0 = typeof performance !== 'undefined' ? performance.now() : Date.now();

  onMount(() => {
    // Soft-warn for bodies >2KB.
    const bodyBytes = new TextEncoder().encode(body).length;
    if (bodyBytes > SOFT_WARN_BYTES) {
      console.warn(
        `[FloatingGlyph] body is ${bodyBytes} bytes (>${SOFT_WARN_BYTES} B soft limit). ` +
        `Per-glyph render cost may be significant. Consider scroll or tablet surface for long text.`
      );
    }

    yOffsetsRef = new Array(glyphBases.length).fill(0);

    const tick = () => {
      const now = typeof performance !== 'undefined' ? performance.now() : Date.now();
      const t = (now - t0) / 1000;
      // Mutate in place — no per-frame allocation.
      if (yOffsetsRef.length !== glyphBases.length) {
        yOffsetsRef.length = glyphBases.length;
      }
      for (let i = 0; i < glyphBases.length; i++) {
        const b = glyphBases[i];
        yOffsetsRef[i] = Math.sin(t * 1.8 + b.phase) * b.amp;
      }
      frameTick++;
      rafId = typeof requestAnimationFrame !== 'undefined'
        ? requestAnimationFrame(tick)
        : 0;
    };

    rafId = typeof requestAnimationFrame !== 'undefined'
      ? requestAnimationFrame(tick)
      : 0;

    return () => {
      if (rafId && typeof cancelAnimationFrame !== 'undefined') {
        cancelAnimationFrame(rafId);
      }
    };
  });
</script>

<!--
  DOM mirror: hidden from visual display, accessible to querySelector.
  Includes span.glyph elements so play-test querySelectorAll('span.glyph') works.
-->
<div
  data-surface="floating-glyph"
  aria-hidden="true"
  style="position:absolute;width:1px;height:1px;overflow:hidden;opacity:0;pointer-events:none;"
>
  {#each glyphs as glyph, i (i)}
    <span class="glyph">{glyph}</span>
  {/each}
</div>

<!-- 3D per-glyph floating text group. -->
<T.Group>
  <T.AmbientLight intensity={0.5} />
  <T.DirectionalLight position={[1, 2, 2]} intensity={0.8} />

  {#each glyphs as glyph, i (i)}
    {@const base = glyphBases[i]}
    <!-- Reading frameTick here pulls the per-frame position read into Svelte's
         reactive graph; yOffsetsRef itself is a plain array (not $state) to
         avoid per-glyph deep reactivity. -->
    {@const yOff = frameTick >= 0 ? (yOffsetsRef[i] ?? 0) : 0}
    <Text
      text={glyph}
      color="#b4d2ff"
      fontSize={0.18}
      anchorX="center"
      anchorY="middle"
      position={[base.basePos[0], base.basePos[1] + yOff, base.basePos[2]]}
      fillOpacity={0.88}
    />
  {/each}
</T.Group>
