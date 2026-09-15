# dreamball-coverage

Living capability. Folded from `add-dreamball-coverage` on 2026-09-10.

Coverage is a labeled assertion on a signed `ball/1` envelope: mesh
nodes, last-known coordinates, radio snapshots or coverage samples, and
a render recipe. It is not a fourth look/feel/act axis.

## Requirements

### Requirement: Coverage is a labeled attribute on a signed ball

A DreamBall SHALL be allowed to carry a coverage document as a labeled
attribute on a `ball/1` envelope: mesh nodes, last-known coordinates,
radio snapshots or coverage samples, and a render recipe. This SHALL NOT
add a fourth look/feel/act axis. Decode SHALL be `dreamball.wasm`
`verifyBall` then `parseBall` only. TypeScript SHALL NOT hand-decode
CBOR.

#### Scenario: Fixture ball

- GIVEN a signed fixture `.ball` whose attributes include coverage of
  the four-router fleet
- WHEN wasm verify+parse succeeds
- THEN the typed DreamBall exposes those nodes and any render recipe
  without TypeScript reading CBOR

#### Scenario: Corrupt bytes

- GIVEN bytes that fail verify or parse
- WHEN the data-input handles them
- THEN the caller receives the wasm reason and no DreamBall is invented

#### Scenario: Identity unchanged

- GIVEN the same coverage ball addressed by transmittable locator and
  by fingerprint
- WHEN both decode
- THEN identity is still the Ed25519 fingerprint
