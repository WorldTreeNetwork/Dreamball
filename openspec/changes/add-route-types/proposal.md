# add-route-types

> **ACTIVE BUILD**

## Why

Steer on `Dreamball-y4t.21` (2026-09-04) closed the two forks that would
put the wrong types on identikey-protocol's public surface. The core
golden file still lists `memory_connection`; contested still holds
`layout` and `trust_observation`. The 2026-08-07 ADR table also still
lists TrustObservation under archiform, which steer overrode.

## What

- Capability `canonical-types` (ADDED): core goldens are the identikey-protocol
  regression set; they do not include Memory, Layout, or TrustObservation.
- Move `memory_connection` and `layout` into `archiform-manifest.json`.
- Offer `trust_observation` to identikey (identity layer), not palace, not
  this port's core goldens. Empty `contested-manifest.json`.
- Amend `docs/decisions/2026-08-07-substrate-palace-boundary.md` so the
  routing table matches steer. Update `fixtures/goldens/README.md` and the
  export generator so the files are produced, not hand-edited.

## Impact

- Capabilities: ADDED `canonical-types`
- ADRs: amend `docs/decisions/2026-08-07-substrate-palace-boundary.md`

## User journey & surfaces

No new UI because this change only names which golden file is the core
gate. An observer already reaches those bytes via `zig build export-golden-fixtures`
and `fixtures/goldens/`. Empty is a missing core entry, failed is
`GoldenDrift` in the exporter, off is the palace/archiform files which
do not gate the core build.

## Out of scope

- Porting types into identikey-protocol (`Dreamball-y4t.25`)
- Creating the archiform repo (`Dreamball-h7s`) or palace repo (`Dreamball-etk`)
- Projector path (`Dreamball-y4t.27`)
- PROTOCOL.md Gordian audit (`Dreamball-y4t.28`)
- Deleting Zig crypto (`Dreamball-y4t.26`)
