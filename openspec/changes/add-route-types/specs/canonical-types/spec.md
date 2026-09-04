## ADDED Requirements

### Requirement: Core goldens are the identikey-protocol gate

The core golden file `fixtures/goldens/manifest.json` SHALL be the only
golden set that gates identikey-protocol encode/decode. It SHALL contain
exactly the substrate vectors: `zero_seed`, `action_v4_unsigned`,
`action_v4_signed`. It SHALL NOT contain Memory, Layout, or
TrustObservation.

#### Scenario: Core set after routing

- GIVEN `zig build export-golden-fixtures` has run
- WHEN a reader lists `fixtures/goldens/manifest.json` entry names
- THEN the names are `zero_seed`, `action_v4_unsigned`, and
  `action_v4_signed`, in that file only as the core gate

#### Scenario: Memory is not a core gate

- GIVEN the `memory_connection` vector
- WHEN goldens are partitioned
- THEN it lives in `fixtures/goldens/archiform-manifest.json` and does
  not appear in the core manifest

### Requirement: Layout files with archiform; TrustObservation is offered to identikey

`layout` SHALL be filed with the archiform golden set. `trust_observation`
SHALL be filed as an identikey identity-layer offer, not as a core gate
and not as a palace gate. The contested holding pen SHALL NOT retain
those two entries.

#### Scenario: Layout

- GIVEN the `layout` vector
- WHEN goldens are partitioned
- THEN it lives in `fixtures/goldens/archiform-manifest.json`

#### Scenario: TrustObservation

- GIVEN the `trust_observation` vector
- WHEN goldens are partitioned
- THEN it does not live in `manifest.json`, `palace-manifest.json`,
  `palace-v3-manifest.json`, or `contested-manifest.json`

#### Scenario: Contested pen empty

- GIVEN both contested entries have been routed
- WHEN a reader opens `fixtures/goldens/contested-manifest.json`
- THEN the file is absent or has an empty `entries` array
