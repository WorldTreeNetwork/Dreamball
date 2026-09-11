# add-dreamball-coverage

> **ACTIVE BUILD**

Bead `mjolnir-mesh-6hn.3` (lightning-mesh intend). Human activated
2026-09-10. Depends on `add-coverage-survey`.

## Why

web3d-space `/mesh` currently simulates radio.json. The coverage game
needs a signed, portable snapshot of mesh coverage plus render hints
that a viewer data-input can verify without a live overlay.

## What

- Capability `dreamball-coverage`.
- A labeled attribute on a `ball/1` envelope carries the coverage
  document (nodes, last-known coords, radio snapshots or samples) and
  a render recipe. Not a fourth look/feel/act axis.
- Verify+parse only through `dreamball.wasm`. TypeScript SHALL NOT
  hand-decode CBOR.
- Viewer data-input (consumed by web3d-space `/mesh`) loads a
  transmittable or fingerprint and feeds the visualizer.

## Impact

- Capabilities: ADDED `dreamball-coverage`
- ADRs: none (follows lightning-mesh `add-coverage-survey`)
- `transmittable` unchanged (locator, not a wire type)

## User journey & surfaces

Duke pipes a DreamBall into the `/mesh` data-input.

1. **Working** — `/demo/star` already verify+parses a signed capsule
   and renders `look.asset`.
2. **Empty** — no coverage attribute; `/mesh` only has the simulated
   fixture.
3. **Failed** — missing object, unsigned, or parse failure is the wasm
   reason; no invented ball.
4. **Off** — `/mesh` still runs the local simulate.ts walk.

## Out of scope

- Live directory gossip (lightning-mesh `add-node-coordinates`)
- `/mesh` paint implementation (web3d-space `add-coverage-world-viz`)
- Adding look/feel/act as a fourth axis
- Hand-rolled CBOR in TypeScript
