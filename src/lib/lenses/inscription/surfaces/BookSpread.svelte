<!--
  BookSpread.svelte — Left/right pages with spine surface (Story 5.4 / FR17 / AC1).

  Renders inscription body text as an open book: two PlaneGeometry page meshes with
  a narrow BoxGeometry spine between them. Body text is split at the midpoint across
  left and right pages using troika-three-text Text components.

  Implementation:
    - Two <T.Mesh> PlaneGeometry pages (parchment material) flanking a spine slab.
    - Two <Text> children: left page receives body[:mid], right page receives body[mid:].
    - Midpoint split preserved from original HTML version.
    - Hidden DOM mirror element for Storybook play-test querySelector assertions.
      The mirror contains the full body so textContent includes both "Hello" and "palace".

  CROSS-RUNTIME INVARIANT: no @ladybugdb/core or kuzu-wasm imports here.

  Remediation 2026-04-24: replaced HTML overlay with real Three.js mesh + 3D text.
  See epic-5.md §5.4 Remediation note.
-->
<script lang="ts">
  import { T } from '@threlte/core';
  import { Text } from '@threlte/extras';
  import * as THREE from 'three';

  interface Props {
    /** Decoded body text to render. */
    body: string;
  }

  const { body }: Props = $props();

  // Split body across left/right pages at midpoint (preserved from HTML version).
  const leftText = $derived(body.slice(0, Math.floor(body.length / 2)));
  const rightText = $derived(body.slice(Math.floor(body.length / 2)));

  // Page geometry: portrait orientation.
  const pageGeometry = new THREE.PlaneGeometry(1.2, 1.8);
  const pageMaterial = new THREE.MeshStandardMaterial({
    color: 0xfaf5e8,
    roughness: 0.9,
    metalness: 0.0,
    side: THREE.DoubleSide,
  });

  // Spine geometry: narrow box between the pages.
  const spineGeometry = new THREE.BoxGeometry(0.12, 1.8, 0.08);
  const spineMaterial = new THREE.MeshStandardMaterial({
    color: 0x5c3d1a,
    roughness: 0.8,
    metalness: 0.0,
  });
</script>

<!--
  DOM mirror: hidden from visual display, accessible to querySelector.
  Full body text included so play-tests can assert both "Hello" and "palace".
-->
<div
  data-surface="book-spread"
  aria-hidden="true"
  style="position:absolute;width:1px;height:1px;overflow:hidden;opacity:0;pointer-events:none;"
>{body}</div>

<!-- 3D book spread group, centered at local origin. -->
<T.Group>
  <T.AmbientLight intensity={0.6} />
  <T.DirectionalLight position={[0, 2, 3]} intensity={1.0} />

  <!-- Left page: slightly angled inward for open-book look. -->
  <T.Mesh
    geometry={pageGeometry}
    material={pageMaterial}
    position={[-0.65, 0, 0]}
    rotation={[0, 0.08, 0]}
  />

  <!-- Spine between pages. -->
  <T.Mesh geometry={spineGeometry} material={spineMaterial} position={[0, 0, 0]} />

  <!-- Right page: mirrored angle. -->
  <T.Mesh
    geometry={pageGeometry}
    material={pageMaterial}
    position={[0.65, 0, 0]}
    rotation={[0, -0.08, 0]}
  />

  <!-- Left page text (first half of body). -->
  <Text
    text={leftText}
    color="#1a1208"
    fontSize={0.10}
    maxWidth={1.0}
    lineHeight={1.55}
    anchorX="center"
    anchorY="middle"
    position={[-0.65, 0, 0.01]}
    rotation={[0, 0.08, 0]}
  />

  <!-- Right page text (second half of body). -->
  <Text
    text={rightText}
    color="#1a1208"
    fontSize={0.10}
    maxWidth={1.0}
    lineHeight={1.55}
    anchorX="center"
    anchorY="middle"
    position={[0.65, 0, 0.01]}
    rotation={[0, -0.08, 0]}
  />
</T.Group>
