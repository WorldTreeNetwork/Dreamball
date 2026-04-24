<!--
  Scroll.svelte — Canonical baseline surface (Story 5.4 / FR17 / AC1 / AC2).

  Renders inscription body text as a 3D scroll mesh (CylinderGeometry) with a
  troika-three-text Text child on the unrolled face.

  This is the CANONICAL BASELINE that every lens MUST render
  (per ADR 2026-04-24-surface-registry §3). "scroll" works everywhere, forever.

  Implementation:
    - <T.Mesh> with CylinderGeometry simulates the cylindrical scroll body.
    - Parchment-coloured MeshStandardMaterial on the cylinder hull.
    - <Text> from @threlte/extras (troika-three-text MSDF) renders body on the
      unrolled face (positioned slightly in front of the cylinder, z-offset = radius).
    - A hidden DOM element (aria-hidden, visually off-screen) carries data-surface
      and the body text so Storybook play-tests can assert via querySelector.textContent.
      (JSDOM/WebGL cannot read pixel output; the DOM mirror is the testable surface.)

  Literal depth extrusion of individual glyphs is deferred to Growth tier.

  Typography: troika MSDF font rendering (system sans fallback).

  CROSS-RUNTIME INVARIANT: no @ladybugdb/core or kuzu-wasm imports here.

  Remediation 2026-04-24: replaced HTML overlay with real Three.js mesh + 3D text
  after user review flagged AC scope retreat. See epic-5.md §5.4 Remediation note.
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

  // Scroll cylinder geometry: radius 0.8, height 2, open-ended caps for parchment look.
  const scrollGeometry = new THREE.CylinderGeometry(0.8, 0.8, 2.0, 32, 1, true);
  const parchmentMaterial = new THREE.MeshStandardMaterial({
    color: 0xf5e6c8,
    roughness: 0.85,
    metalness: 0.0,
    side: THREE.BackSide, // render inside of cylinder for scroll interior
  });

  // Cylinder end-cap discs (top + bottom scroll rollers).
  const capGeometry = new THREE.CylinderGeometry(0.85, 0.85, 0.12, 32);
  const capMaterial = new THREE.MeshStandardMaterial({
    color: 0x8b6914,
    roughness: 0.7,
    metalness: 0.1,
  });
</script>

<!--
  DOM mirror: hidden from visual display, accessible to querySelector.
  Storybook play-tests assert data-surface + textContent here.
-->
<div
  data-surface="scroll"
  aria-hidden="true"
  style="position:absolute;width:1px;height:1px;overflow:hidden;opacity:0;pointer-events:none;"
>{body}</div>

<!-- 3D scroll mesh group, centered at local origin. -->
<T.Group>
  <!-- Ambient + directional light for the scroll scene. -->
  <T.AmbientLight intensity={0.6} />
  <T.DirectionalLight position={[2, 3, 2]} intensity={1.0} />

  <!-- Cylinder hull: parchment interior. -->
  <T.Mesh geometry={scrollGeometry} material={parchmentMaterial} />

  <!-- Top roller. -->
  <T.Mesh geometry={capGeometry} material={capMaterial} position={[0, 1.06, 0]} />

  <!-- Bottom roller. -->
  <T.Mesh geometry={capGeometry} material={capMaterial} position={[0, -1.06, 0]} />

  <!-- Troika 3D text rendered on the unrolled face (z-forward of the cylinder). -->
  <Text
    text={body}
    color="#2a1a06"
    fontSize={0.14}
    maxWidth={1.4}
    lineHeight={1.5}
    anchorX="center"
    anchorY="middle"
    position={[0, 0, 0.82]}
    rotation={[0, 0, 0]}
  />
</T.Group>
