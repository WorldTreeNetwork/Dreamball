<!--
  Tablet.svelte — Rectangular slab surface (Story 5.4 / FR17 / AC1).

  Renders inscription body text as a 3D stone tablet mesh (BoxGeometry) with a
  troika-three-text Text child centered on the front face.

  Implementation:
    - <T.Mesh> with BoxGeometry slab, stone-coloured MeshStandardMaterial.
    - <Text> from @threlte/extras rendered on the front face (z-offset).
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

  // Tablet slab: wide, tall, shallow depth.
  const slabGeometry = new THREE.BoxGeometry(2.0, 2.8, 0.25);
  const stoneMaterial = new THREE.MeshStandardMaterial({
    color: 0x786958,
    roughness: 0.92,
    metalness: 0.0,
  });
</script>

<!--
  DOM mirror: hidden from visual display, accessible to querySelector.
  Storybook play-tests assert data-surface + textContent here.
-->
<div
  data-surface="tablet"
  aria-hidden="true"
  style="position:absolute;width:1px;height:1px;overflow:hidden;opacity:0;pointer-events:none;"
>{body}</div>

<!-- 3D tablet mesh group, centered at local origin. -->
<T.Group>
  <T.AmbientLight intensity={0.5} />
  <T.DirectionalLight position={[1, 2, 3]} intensity={1.1} />

  <!-- Stone slab body. -->
  <T.Mesh geometry={slabGeometry} material={stoneMaterial} />

  <!-- Troika 3D text on the front face of the slab. -->
  <Text
    text={body}
    color="#f5f0e8"
    fontSize={0.13}
    maxWidth={1.7}
    lineHeight={1.55}
    anchorX="center"
    anchorY="middle"
    position={[0, 0, 0.14]}
    rotation={[0, 0, 0]}
  />
</T.Group>
