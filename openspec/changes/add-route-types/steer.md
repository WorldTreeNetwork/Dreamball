# steer add-route-types

**When.** 2026-09-04
**Depth.** lean

## Decided

- memory_connection: move to archiform-manifest (user 1A)
  Why: ADR already routes Memory to archiform. A Memory type in
  identikey-protocol is a semver event to undo.
- contested split (user 2B): layout → archiform-manifest; trust_observation
  offered to identikey as identity-layer, not palace, not this port's
  core goldens. Contested file empties.

## Skipped

- none

## Feeds change

Core goldens become `zero_seed` + `action_v4_unsigned` + `action_v4_signed`.
`memory_connection` and `layout` land in archiform-manifest. `trust_observation`
leaves contested as an identikey offer, not a core gate. Amend the 2026-08-07
routing table so TrustObservation is no longer listed under archiform.
