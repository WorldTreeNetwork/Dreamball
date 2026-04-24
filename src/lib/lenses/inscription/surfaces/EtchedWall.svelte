<!--
  EtchedWall.svelte — Text inset into wall mesh, low-contrast (Story 5.4 / FR17 / AC1).

  Renders inscription body text as a 3D stone wall (PlaneGeometry) with troika-three-text
  Text in a low-opacity, low-contrast colour that evokes physical etching.

  Implementation:
    - <T.Mesh> PlaneGeometry wall, stone-coloured MeshStandardMaterial.
    - <Text> from @threlte/extras with ~0.75 opacity color simulating etched inset.
      Text illusion achieved via color/lighting, NOT literal depth extrusion —
      literal glyph depth is deferred to Growth tier (requires signed-distance geometry).
    - Hidden DOM mirror element for Storybook play-test querySelector assertions.

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

  // Wall plane geometry: wide stone slab.
  const wallGeometry = new THREE.PlaneGeometry(3.0, 2.4);
  const stoneMaterial = new THREE.MeshStandardMaterial({
    color: 0x584c42,
    roughness: 0.95,
    metalness: 0.0,
  });
</script>

<!--
  DOM mirror: hidden from visual display, accessible to querySelector.
  Storybook play-tests assert data-surface + textContent here.
-->
<div
  data-surface="etched-wall"
  aria-hidden="true"
  style="position:absolute;width:1px;height:1px;overflow:hidden;opacity:0;pointer-events:none;"
>{body}</div>

<!-- 3D etched wall group. -->
<T.Group>
  <!-- Dim ambient light — etched walls are shadowy. -->
  <T.AmbientLight intensity={0.4} />
  <!-- Raking directional light to accentuate surface texture. -->
  <T.DirectionalLight position={[-2, 1, 2]} intensity={0.8} />

  <!-- Stone wall plane. -->
  <T.Mesh geometry={wallGeometry} material={stoneMaterial} />

  <!--
    Troika 3D text: low-contrast color (~0.75 visible against the stone wall).
    Text color is only slightly lighter than the wall to simulate etching.
    Literal depth extrusion deferred to Growth tier.
  -->
  <Text
    text={body}
    color="#c8beb4"
    fontSize={0.13}
    maxWidth={2.6}
    lineHeight={1.6}
    letterSpacing={0.04}
    anchorX="center"
    anchorY="middle"
    position={[0, 0, 0.005]}
    rotation={[0, 0, 0]}
    fillOpacity={0.75}
  />
</T.Group>
