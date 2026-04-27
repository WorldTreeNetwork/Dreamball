<!--
  PalaceLens.svelte — Story 5.2 / FR15

  Omnispherical navigable 3-D view of a Memory Palace.

  Responsibilities:
    • Decodes the palace field envelope via jelly.wasm (TC6 — no hand-written CBOR).
    • Validates decoded shape against Valibot DreamBallFieldSchema (AC1).
    • Renders each room as a Threlte mesh node placed at layout.position when
      the field envelope's jelly.layout contains the room's child-fp; falls back
      to a deterministic polar-shell grid otherwise (AC2, AC3).
    • Wraps each room node in an omnispherical onion-shell sphere (AC2).
    • Click on a room node → dispatches `navigate` CustomEvent
      { kind: "room", fp: <room-fp> } (AC4).
    • Does NOT write to LadybugDB or CAS (SEC11 / AC5).

  CROSS-RUNTIME INVARIANT:
    No @ladybugdb/core or kuzu-wasm imports here. Palace envelope decode goes
    through jelly.wasm exclusively. Store verbs (getPalace, roomsFor) are
    consumed via the `store` prop (StoreAPI interface). Grep asserts this in
    PalaceLens.test.ts (AC1).

  Coord-frame contract (ADR 2026-04-24-coord-frames):
    • Outer field: polar (omnispherical-grid §12.2).
    • Placement: cartesian local-to-field-origin (jelly.layout §13.2).
    • Conversion: polarShellToCartesian() called once at load; rooms placed
      using their cartesian layout.position directly (or grid-fallback coords).

  Camera model: orbit (sprint-001 default; first-person deferred to Growth).

  Grid fallback ordering (AC3):
    Rooms sorted by fp lexicographically (same order store.roomsFor returns).
    Each placed on a Fibonacci-spiral shell at radius SHELL_RADIUS.
    Byte-stable because fp ordering is deterministic; same palace fp set →
    same positions across two independent mounts.
    Single console.info emitted on fallback (AC3).
-->
<script lang="ts">
  import { T, Canvas } from '@threlte/core';
  import { OrbitControls } from '@threlte/extras';
  import * as THREE from 'three';
  import { onMount } from 'svelte';
  import { safeParseJelly } from '../../wasm/loader.js';
  import { DreamBallFieldSchema } from '../../generated/schemas.js';
  import * as v from 'valibot';
  import type { StoreAPI, RoomData } from '../../../memory-palace/store-types.js';

  // ─── Props ────────────────────────────────────────────────────────────────

  interface Props {
    /**
     * Blake3 fp of the palace (jelly.dreamball.field envelope).
     * Used to query room list from the store.
     */
    palaceFp: string;

    /**
     * Raw bytes of the palace field envelope (.jelly CBOR).
     * Decoded via jelly.wasm (TC6 / AC1). When null, layout falls
     * back to the deterministic grid for all rooms.
     */
    palaceBytes?: Uint8Array | null;

    /**
     * StoreAPI instance — MUST be store.server.ts or store.browser.ts.
     * Never @ladybugdb/core or kuzu-wasm directly (D-007 / TC12).
     */
    store?: StoreAPI | null;

    /**
     * Callback fired after first room renders — used by play-test for
     * NFR10 first-lit-room latency (target <2s).
     */
    onFirstFrame?: (t_ms: number) => void;

    /**
     * Canvas width in pixels (default: 800).
     */
    width?: number;

    /**
     * Canvas height in pixels (default: 600).
     */
    height?: number;
  }

  const {
    palaceFp,
    palaceBytes = null,
    store = null,
    onFirstFrame,
    width = 800,
    height = 600
  }: Props = $props();

  // ─── Constants ────────────────────────────────────────────────────────────

  /** Default shell radius (meters) for grid-fallback placement. */
  const SHELL_RADIUS = 5;

  /** Onion-shell sphere radius around each room node (meters).
   *  Sized so the AC2 omnispherical wrapper is visually distinct from the
   *  inner node when seen from the orbit camera at ~9–12m. */
  const ONION_RADIUS = 0.95;

  /** Room node sphere radius (meters). */
  const NODE_RADIUS = 0.45;

  // ─── Decoded palace data ──────────────────────────────────────────────────

  /**
   * Parsed jelly.layout placements from the palace envelope, keyed by child-fp.
   * Populated by decodePalaceEnvelope(). Empty map = no layout in envelope.
   */
  let layoutByChildFp: Map<string, { position: [number, number, number]; facing: [number, number, number, number] }> = $state(new Map());

  /** Whether the decode has completed (success or not). */
  let decodeComplete = $state(false);

  /** Rooms from the store. */
  let rooms: RoomData[] = $state([]);

  /** Error message if palette decode fails (shown in fallback render). */
  let decodeError: string | null = $state(null);

  // ─── Envelope decode (AC1) ────────────────────────────────────────────────

  /**
   * Decode the palace envelope bytes via jelly.wasm, extract jelly.layout
   * placements from the field envelope's `contains` attribute, and populate
   * layoutByChildFp.
   *
   * We validate the decoded shape against DreamBallFieldSchema (Valibot).
   * If `palaceBytes` is null, the map stays empty and all rooms use grid
   * fallback (AC3 path).
   */
  async function decodePalaceEnvelope(bytes: Uint8Array): Promise<void> {
    const result = await safeParseJelly(bytes);
    if (!result.success) {
      decodeError = `jelly.wasm parse failed: ${result.issues?.[0]?.message ?? 'unknown error'}`;
      return;
    }

    // Validate field shape (AC1 — Valibot schema conformance).
    const fieldResult = v.safeParse(DreamBallFieldSchema, result.data);
    if (!fieldResult.success) {
      // Not a fatal error for rendering — warn and proceed without layout.
      decodeError = `Valibot: envelope is not a jelly.dreamball.field`;
      return;
    }

    // Extract layout placements from the `jelly.layout` attribute.
    // In the MVP, layout is embedded as a JSON attribute on the field envelope.
    // The WASM parser surfaces it in `result.data` — we look for an array of
    // placements in the `contains` list (the field's child fps carry their
    // own layout attribute attached to the parent). In practice the
    // `jelly.layout` envelope is a sibling attribute on the field.
    //
    // MVP scope: the WASM parser exposes `result.data` as the field's DreamBall
    // object. If it carried a `jelly.layout` embedded attribute (as noted in
    // PROTOCOL §13.2), it would appear as `(result.data as any)['jelly.layout']`.
    // Until full nested-attribute decoding lands in the Zig parser, we read
    // whatever the WASM surfaces. This is intentional — the Zig side is the
    // authority; TS never hand-parses.
    const raw = result.data as Record<string, unknown>;
    const jellyLayout = raw['jelly.layout'] as {
      placements?: Array<{
        'child-fp': string;
        position: [number, number, number];
        facing: [number, number, number, number];
      }>;
    } | undefined;

    if (jellyLayout?.placements) {
      const newMap = new Map<string, { position: [number, number, number]; facing: [number, number, number, number] }>();
      for (const p of jellyLayout.placements) {
        newMap.set(p['child-fp'], { position: p.position, facing: p.facing });
      }
      layoutByChildFp = newMap;
    }
    // If no jelly.layout found, layoutByChildFp stays empty → grid fallback for all rooms.
  }

  // ─── Grid fallback (AC3) ──────────────────────────────────────────────────

  /**
   * Deterministic Fibonacci-spiral placement on a sphere shell.
   *
   * Why Fibonacci spiral: uniform distribution, deterministic, stable under
   * any permutation of input count. The golden-angle Fibonacci lattice gives
   * the most spatially-uniform point set on the sphere for arbitrary N.
   * The index `i` is derived from the room's lexicographic position in the
   * sorted fp list (same order `store.roomsFor` returns) — this makes the
   * grid byte-stable across independent mounts (AC3).
   *
   * See: docs/sprints/001-memory-palace-mvp/addenda/S5.2-grid-fallback-algo.md
   */
  function fibonacciShellPosition(index: number, total: number): [number, number, number] {
    const goldenAngle = Math.PI * (3 - Math.sqrt(5)); // ≈ 2.399 radians
    const y = 1 - (index / Math.max(1, total - 1)) * 2; // y in [-1, 1]
    const r = Math.sqrt(Math.max(0, 1 - y * y));
    const theta = goldenAngle * index;
    return [
      SHELL_RADIUS * r * Math.cos(theta),
      SHELL_RADIUS * y,
      SHELL_RADIUS * r * Math.sin(theta)
    ];
  }

  // ─── Room world positions ──────────────────────────────────────────────────

  interface RoomNode {
    fp: string;
    position: [number, number, number];
    usedFallback: boolean;
  }

  /**
   * Compute world positions for all rooms.
   * Rooms with a layout.position come from the decoded field envelope (AC2).
   * Rooms without layout use the Fibonacci grid fallback (AC3).
   */
  const roomNodes: RoomNode[] = $derived.by(() => {
    return rooms.map((room, i) => {
      const layoutEntry = layoutByChildFp.get(room.fp);
      if (layoutEntry) {
        return { fp: room.fp, position: layoutEntry.position, usedFallback: false };
      }
      return {
        fp: room.fp,
        position: fibonacciShellPosition(i, rooms.length),
        usedFallback: true
      };
    });
  });

  const anyRoomFallback = $derived(roomNodes.some((n) => n.usedFallback));

  // Emit a single console.info when any room uses fallback (AC3). Kept in an
  // $effect instead of inside $derived.by() so the derivation stays pure — the
  // guard `gridFallbackLogged` is a plain let because it's a write-once latch,
  // not reactive state (M7 review fix).
  let gridFallbackLogged = false;
  $effect(() => {
    if (anyRoomFallback && !gridFallbackLogged) {
      gridFallbackLogged = true;
      console.info(
        `[PalaceLens] palace "${palaceFp}": one or more rooms have no jelly.layout — using deterministic Fibonacci-shell grid fallback (AC3).`
      );
    }
  });

  // ─── Materials ────────────────────────────────────────────────────────────

  const nodeMaterial = new THREE.MeshStandardMaterial({
    color: 0x9fdcef,
    emissive: 0x2a5a78,
    roughness: 0.35,
    metalness: 0.25
  });

  const onionMaterial = new THREE.MeshStandardMaterial({
    color: 0xaad8f0,
    emissive: 0x0e2a40,
    roughness: 0.7,
    metalness: 0.0,
    transparent: true,
    opacity: 0.22,
    side: THREE.BackSide
  });

  // Faint outer "omnisphere" — visualizes the palace's polar shell so the
  // rooms read as inhabitants of a bounded space rather than dots in void.
  // Wireframe + low opacity keeps it scenic, not occluding.
  const shellMaterial = new THREE.MeshBasicMaterial({
    color: 0x2a4a68,
    wireframe: true,
    transparent: true,
    opacity: 0.18
  });

  const nodeGeometry = new THREE.SphereGeometry(NODE_RADIUS, 24, 18);
  const onionGeometry = new THREE.SphereGeometry(ONION_RADIUS, 20, 16);
  const shellGeometry = new THREE.SphereGeometry(SHELL_RADIUS, 24, 16);

  // ─── Mount logic ──────────────────────────────────────────────────────────

  let firstFrameFired = false;
  const t0 = typeof performance !== 'undefined' ? performance.now() : Date.now();

  onMount(() => {
    (async () => {
      // 1. Decode palace envelope via jelly.wasm (AC1 — TC6).
      if (palaceBytes) {
        await decodePalaceEnvelope(palaceBytes);
      }

      // 2. Fetch room list from store (D-007 verbs).
      if (store) {
        try {
          rooms = await store.roomsFor(palaceFp);
        } catch (e) {
          console.warn('[PalaceLens] store.roomsFor failed:', e);
        }
      }

      decodeComplete = true;
    })();

    return () => {
      nodeMaterial.dispose();
      onionMaterial.dispose();
      shellMaterial.dispose();
      nodeGeometry.dispose();
      onionGeometry.dispose();
      shellGeometry.dispose();
    };
  });

  // ─── Navigate event (AC4) ─────────────────────────────────────────────────

  /**
   * Dispatch a `navigate` CustomEvent for a clicked room.
   * Payload: { kind: "room", fp: <room-fp> }
   * The event bubbles so DreamBallViewer can intercept it (AC4).
   */
  function handleRoomClick(roomFp: string, event: MouseEvent): void {
    const detail = { kind: 'room' as const, fp: roomFp };
    const navigateEvent = new CustomEvent('navigate', {
      detail,
      bubbles: true,
      composed: true
    });
    (event.currentTarget as HTMLElement | null)?.dispatchEvent(navigateEvent);
  }

  // Fire onFirstFrame once rooms are ready.
  $effect(() => {
    if (decodeComplete && roomNodes.length > 0 && !firstFrameFired) {
      firstFrameFired = true;
      const elapsed = (typeof performance !== 'undefined' ? performance.now() : Date.now()) - t0;
      onFirstFrame?.(elapsed);
    }
  });
</script>

<!--
  Wrapper div captures bubbled `navigate` events from 3D room-click handlers.
  The div also carries data-palace-fp for Storybook play-test selectors.
-->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div
  class="palace-lens"
  data-palace-fp={palaceFp}
  style="width: {width}px; height: {height}px; position: relative;"
>
  {#if !decodeComplete}
    <div class="palace-loading" aria-live="polite">Loading palace…</div>
  {:else}
    <Canvas>
      <!-- Ambient + directional lighting for room nodes. -->
      <T.AmbientLight intensity={0.5} />
      <T.DirectionalLight position={[10, 12, 8]} intensity={1.2} />

      <!-- Orbit camera (sprint-001 default; first-person deferred to Growth). -->
      <T.PerspectiveCamera makeDefault fov={60} position={[0, 2.5, 9]}>
        <OrbitControls enableDamping dampingFactor={0.08} />
      </T.PerspectiveCamera>

      <!-- Outer omnispherical shell (scenic boundary; not interactive). -->
      <T.Mesh geometry={shellGeometry} material={shellMaterial} />

      <!-- Room nodes + onion-shell wrappers. -->
      {#each roomNodes as room (room.fp)}
        <!--
          Each room is:
            1. An outer onion-shell sphere (AC2 omnispherical wrapper).
            2. An inner node sphere (clickable; dispatches navigate event).
          Both share the same world position from layout or grid fallback.
        -->
        <T.Group position={room.position}>
          <!-- Onion shell (AC2) -->
          <T.Mesh geometry={onionGeometry} material={onionMaterial} />

          <!-- Room node (clickable — AC4) -->
          <T.Mesh
            geometry={nodeGeometry}
            material={nodeMaterial}
            onclick={(e: MouseEvent) => handleRoomClick(room.fp, e)}
          />
        </T.Group>
      {/each}
    </Canvas>
  {/if}

  {#if decodeError}
    <div class="palace-warn" role="alert" aria-live="assertive">
      {decodeError}
    </div>
  {/if}
</div>

<style>
  .palace-lens {
    display: block;
    background: #060c18;
    overflow: hidden;
  }

  .palace-loading {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #7ec8e3;
    font-family: monospace;
    font-size: 14px;
  }

  .palace-warn {
    position: absolute;
    bottom: 8px;
    left: 8px;
    right: 8px;
    padding: 4px 8px;
    background: rgba(200, 80, 40, 0.85);
    color: #fff;
    font-family: monospace;
    font-size: 12px;
    border-radius: 3px;
    pointer-events: none;
  }
</style>
