<!--
  RoomLens.svelte — Story 5.3 / FR16

  Interior layout view of a Memory Palace room.

  Responsibilities:
    • Fetches room contents via store.roomContents(roomFp) (D-007 / AC3).
    • Positions inscribed avatars at placement.position (cartesian local-to-room).
    • Orients avatars by placement.facing quaternion [qx, qy, qz, qw] (glTF 2.0 order).
    • Deterministic-grid fallback when placement is absent (AC2).
    • First visible frame within 500ms on a 50-inscription room (AC4 / NFR10).
    • Does NOT write to LadybugDB or CAS (SEC11).

  CROSS-RUNTIME INVARIANT:
    No @ladybugdb/core or kuzu-wasm imports here. All store access is through the
    `store` prop (StoreAPI interface). Grep asserts this in RoomLens.test.ts (AC3).

  Coord-frame contract (ADR 2026-04-24-coord-frames §2):
    placement.position is cartesian local-to-room-origin; passed directly to
    T.Group position with no additional conversion (no polar math needed here).
    Quaternion [qx, qy, qz, qw] maps to THREE.Quaternion(qx, qy, qz, qw) directly.

  Default-facing convention (Open question, epic-5.md §5.3):
    When placement.facing is absent, the inscription faces the room centroid
    (average of all placed/fallback positions). This is more semantically correct
    than facing [0,0,0] — a room centroid is the natural "looking inward" point.
    Camera-origin facing was rejected because: the camera moves (orbit controls),
    so a static facing toward the camera origin would be wrong on any non-trivial
    view. Centroid is a stable geometric property of the room's contents.

  Grid fallback shape (AC2):
    A flat planar grid in the XZ plane at Y=0. Rooms are interior-scale, so a
    small NxM grid is more natural than a shell (which suits a large outer-palace
    view). Items are sorted by fp lexicographically (same order store.roomContents
    returns) then arranged row-major in a square grid with GRID_SPACING between them.
    The grid is byte-stable: same fp set → same indices → same positions.
    See addendum S5.3-room-grid-fallback-algo.md for rationale.
-->
<script lang="ts">
  import { T, Canvas } from '@threlte/core';
  import { OrbitControls } from '@threlte/extras';
  import * as THREE from 'three';
  import { onMount } from 'svelte';
  import type { StoreAPI, RoomContentsItem } from '../../../memory-palace/store-types.js';

  // ─── Props ────────────────────────────────────────────────────────────────

  interface Props {
    /**
     * Blake3 fp of the room whose contents we are displaying.
     * Used as the argument to store.roomContents(roomFp) (D-007 / AC3).
     */
    roomFp: string;

    /**
     * StoreAPI instance — MUST be store.server.ts or store.browser.ts.
     * Never @ladybugdb/core or kuzu-wasm directly (D-007 / TC12).
     */
    store?: StoreAPI | null;

    /**
     * Callback fired after first inscription renders — used by play-test for
     * NFR10 first-visible-frame latency (target <500ms per AC4).
     */
    onFirstFrame?: (t_ms: number) => void;

    /** Canvas width in pixels (default: 800). */
    width?: number;

    /** Canvas height in pixels (default: 600). */
    height?: number;
  }

  const {
    roomFp,
    store = null,
    onFirstFrame,
    width = 800,
    height = 600
  }: Props = $props();

  // ─── Constants ────────────────────────────────────────────────────────────

  /** Spacing between items in the planar grid fallback (meters). */
  const GRID_SPACING = 1.5;

  /** Height of inscription meshes in world coords (meters).
   *  Sized so a placement at y=0.5 stands the inscription's base on the floor
   *  (centre at 0.5, half-height 0.5 → base at 0). */
  const INSCRIPTION_HEIGHT = 1.0;

  /** Width of inscription placeholder mesh (meters). */
  const INSCRIPTION_WIDTH = 0.9;

  /** Depth of inscription placeholder mesh (meters). */
  const INSCRIPTION_DEPTH = 0.08;

  /** Interior dimensions of the visible room shell (meters). */
  const ROOM_HALF_X = 5;
  const ROOM_HALF_Z = 4.5;
  const ROOM_HEIGHT = 4;
  const WALL_THICKNESS = 0.1;

  // ─── State ────────────────────────────────────────────────────────────────

  /** All inscriptions loaded from the store. Populated by roomContents(). */
  let contents: RoomContentsItem[] = $state([]);

  /** Whether the store fetch has completed. */
  let loadComplete = $state(false);

  let firstFrameFired = false;
  const t0 = typeof performance !== 'undefined' ? performance.now() : Date.now();

  // ─── Grid fallback algorithm (AC2) ───────────────────────────────────────

  /**
   * Compute a deterministic planar grid position for an inscription.
   *
   * Layout: a square NxM grid in the XZ plane at Y=0.5 (inscription mid-height).
   * Index `i` comes from the lexicographically-sorted fp order that
   * store.roomContents returns — so position is byte-stable across re-mounts.
   *
   * Square root grid: cols = ceil(sqrt(total)); rows determined by total/cols.
   * Items are placed row-major: left-to-right, front-to-back.
   * Grid is centred at the room origin.
   */
  function gridFallbackPosition(index: number, total: number): [number, number, number] {
    const cols = Math.ceil(Math.sqrt(Math.max(1, total)));
    const row = Math.floor(index / cols);
    const col = index % cols;
    const totalRows = Math.ceil(total / cols);
    // Centre the grid at origin.
    const xOffset = (col - (cols - 1) / 2) * GRID_SPACING;
    const zOffset = (row - (totalRows - 1) / 2) * GRID_SPACING;
    return [xOffset, 0.5, zOffset];
  }

  // ─── Centroid helper (for default-facing convention) ─────────────────────

  /**
   * Compute the centroid of all inscription world positions (placed or fallback).
   * Used as the "look-at" target when placement.facing is absent — inscriptions
   * face the centroid rather than the camera origin.
   */
  function computeCentroid(positions: Array<[number, number, number]>): [number, number, number] {
    if (positions.length === 0) return [0, 0, 0];
    let sx = 0, sy = 0, sz = 0;
    for (const [x, y, z] of positions) { sx += x; sy += y; sz += z; }
    const n = positions.length;
    return [sx / n, sy / n, sz / n];
  }

  // ─── Derived inscription nodes ────────────────────────────────────────────

  interface InscriptionNode {
    fp: string;
    position: [number, number, number];
    quaternion: [number, number, number, number]; // [qx, qy, qz, qw]
    usedFallback: boolean;
  }

  /**
   * Compute world positions and orientations for all inscriptions.
   *
   * Items with placement.position use the stored cartesian coords directly.
   * Items without placement use the flat planar grid fallback.
   * Items without placement.facing are oriented toward the room centroid.
   */
  const inscriptionNodes: InscriptionNode[] = $derived.by(() => {
    const total = contents.length;

    // First pass: collect positions (for centroid computation).
    const positions: Array<[number, number, number]> = contents.map((item, i) => {
      if (item.placement) return item.placement.position;
      return gridFallbackPosition(i, total);
    });
    const centroid = computeCentroid(positions);

    return contents.map((item, i) => {
      const hasPlacement = item.placement !== null;

      const pos: [number, number, number] = hasPlacement
        ? item.placement!.position
        : gridFallbackPosition(i, total);

      let quat: [number, number, number, number];
      if (hasPlacement && item.placement!.facing) {
        // Use stored quaternion directly (ADR: [qx,qy,qz,qw] order).
        quat = item.placement!.facing;
      } else {
        // Compute a quaternion that rotates the default +Z-forward orientation
        // to look at the room centroid (default-facing convention, see JSDoc above).
        const from = new THREE.Vector3(...pos);
        const target = new THREE.Vector3(...centroid);
        const dir = new THREE.Vector3().subVectors(target, from);
        if (dir.lengthSq() < 1e-10) {
          quat = [0, 0, 0, 1];
        } else {
          dir.normalize();
          const q = new THREE.Quaternion().setFromUnitVectors(
            new THREE.Vector3(0, 0, 1),
            dir
          );
          quat = [q.x, q.y, q.z, q.w];
        }
      }

      return { fp: item.fp, position: pos, quaternion: quat, usedFallback: !hasPlacement };
    });
  });

  const anyInscriptionFallback = $derived(inscriptionNodes.some((n) => n.usedFallback));

  // Emit a single console.info when any inscription uses fallback (AC2). Kept
  // out of $derived.by() so the derivation stays pure (M7 review fix).
  let gridFallbackLogged = false;
  $effect(() => {
    if (anyInscriptionFallback && !gridFallbackLogged) {
      gridFallbackLogged = true;
      console.info(
        `[RoomLens] room "${roomFp}": one or more inscriptions have no placement — ` +
        `using deterministic planar-grid fallback (AC2). Default facing: room centroid.`
      );
    }
  });

  // ─── Materials / Geometry ──────────────────────────────────────────────────

  const inscriptionMaterial = new THREE.MeshStandardMaterial({
    color: 0xd4c89a,
    emissive: 0x2a2010,
    roughness: 0.6,
    metalness: 0.05
  });

  const floorMaterial = new THREE.MeshStandardMaterial({
    color: 0x2a2a3a,
    roughness: 0.9,
    metalness: 0.0
  });

  // Walls: a touch lighter than the floor so the room volume is legible without
  // pulling focus from the inscriptions. Front wall is omitted so the orbit
  // camera can look in from +Z.
  const wallMaterial = new THREE.MeshStandardMaterial({
    color: 0x363a4d,
    roughness: 0.95,
    metalness: 0.0
  });

  const inscriptionGeometry = new THREE.BoxGeometry(
    INSCRIPTION_WIDTH,
    INSCRIPTION_HEIGHT,
    INSCRIPTION_DEPTH
  );

  const floorGeometry = new THREE.PlaneGeometry(ROOM_HALF_X * 2, ROOM_HALF_Z * 2);

  const backWallGeometry = new THREE.BoxGeometry(
    ROOM_HALF_X * 2,
    ROOM_HEIGHT,
    WALL_THICKNESS
  );
  const sideWallGeometry = new THREE.BoxGeometry(
    WALL_THICKNESS,
    ROOM_HEIGHT,
    ROOM_HALF_Z * 2
  );

  // ─── Mount logic ──────────────────────────────────────────────────────────

  onMount(() => {
    (async () => {
      // Fetch room contents via the single domain verb (D-007 / AC3).
      if (store) {
        try {
          contents = await store.roomContents(roomFp);
        } catch (e) {
          console.warn('[RoomLens] store.roomContents failed:', e);
        }
      }
      loadComplete = true;
    })();

    return () => {
      inscriptionMaterial.dispose();
      floorMaterial.dispose();
      wallMaterial.dispose();
      inscriptionGeometry.dispose();
      floorGeometry.dispose();
      backWallGeometry.dispose();
      sideWallGeometry.dispose();
    };
  });

  // Fire onFirstFrame once inscriptions are placed.
  $effect(() => {
    if (loadComplete && !firstFrameFired) {
      firstFrameFired = true;
      const elapsed = (typeof performance !== 'undefined' ? performance.now() : Date.now()) - t0;
      onFirstFrame?.(elapsed);
    }
  });
</script>

<!--
  Wrapper div carries data-room-fp for Storybook play-test selectors.
  Interior background is dark to match the memory-palace aesthetic.
-->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div
  class="room-lens"
  data-room-fp={roomFp}
  style="width: {width}px; height: {height}px; position: relative;"
>
  {#if !loadComplete}
    <div class="room-loading" aria-live="polite">Loading room…</div>
  {:else}
    <Canvas>
      <!-- Ambient + soft directional lighting for interior. -->
      <T.AmbientLight intensity={0.6} />
      <T.DirectionalLight position={[4, 8, 4]} intensity={1.0} />
      <T.DirectionalLight position={[-4, 6, -4]} intensity={0.4} />

      <!-- Orbit camera for interior (sprint-001 default). -->
      <T.PerspectiveCamera makeDefault fov={60} position={[0, 2.2, 6.5]}>
        <OrbitControls enableDamping dampingFactor={0.08} target={[0, 0.8, 0]} />
      </T.PerspectiveCamera>

      <!-- Room floor plane for spatial reference. -->
      <T.Mesh
        geometry={floorGeometry}
        material={floorMaterial}
        rotation={[-Math.PI / 2, 0, 0]}
        position={[0, 0, 0]}
      />

      <!-- Three walls (back + sides; front omitted so the orbit camera can look in). -->
      <T.Mesh
        geometry={backWallGeometry}
        material={wallMaterial}
        position={[0, ROOM_HEIGHT / 2, -ROOM_HALF_Z]}
      />
      <T.Mesh
        geometry={sideWallGeometry}
        material={wallMaterial}
        position={[-ROOM_HALF_X, ROOM_HEIGHT / 2, 0]}
      />
      <T.Mesh
        geometry={sideWallGeometry}
        material={wallMaterial}
        position={[ROOM_HALF_X, ROOM_HEIGHT / 2, 0]}
      />

      <!-- Inscription nodes. -->
      {#each inscriptionNodes as node (node.fp)}
        <!--
          Each inscription is a BoxGeometry placeholder oriented by its quaternion.
          Real surfaces (scroll, tablet, etc.) are rendered by InscriptionLens in S5.4.
          The quaternion is decomposed into rotation via THREE.Euler for Threlte's
          rotation prop: we pass via a T.Group with a THREE.Quaternion-based matrix.
        -->
        <T.Group
          position={node.position}
          quaternion={node.quaternion}
        >
          <T.Mesh
            geometry={inscriptionGeometry}
            material={inscriptionMaterial}
          />
        </T.Group>
      {/each}
    </Canvas>
  {/if}
</div>

<style>
  .room-lens {
    display: block;
    background: #080b14;
    overflow: hidden;
  }

  .room-loading {
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
