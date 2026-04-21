# Vendored: recrypt `recrypt.identity` envelope fixtures

**Source:** `/Users/dukejones/work/Identikey/recrypt/tests/fixtures/identity/`
**Upstream commit:** `255a177` (`v0.1.0-42-g255a177`) — 2026-04-21
**Copied files:** `identity-ed25519-only.{envelope,json}`, `identity-hybrid-no-pre.{envelope,json}`, `identity-full.{envelope,json}`, `README.md`

These are the canonical byte-level interop fixtures for the
`recrypt.identity` Gordian Envelope. Dreamball's `src/identity_envelope.zig`
decoder/encoder MUST reproduce the `.envelope` bytes byte-for-byte when
round-tripping the content described in the sidecar `.json` files.

See `docs/dcbor-determinism.md` in the recrypt repo for the encoding
rules these fixtures exercise.

## Refresh procedure

If the recrypt format spec changes (new mandatory field, new dCBOR rule,
`bc-envelope` bump that alters output) the upstream fixtures will be
regenerated. To resync Dreamball:

```sh
# In recrypt repo, regenerate fixtures:
cd ../recrypt
cargo test -p recrypt-wire --test fixture_regenerate -- --ignored --nocapture

# Verify they still pass on recrypt's side:
cargo test -p recrypt-wire --test fixture_regenerate

# In Dreamball repo, resync:
cd ../Dreamball
cp ../recrypt/tests/fixtures/identity/*.{envelope,json} vendor/recrypt-identity-fixtures/
cp ../recrypt/tests/fixtures/identity/README.md vendor/recrypt-identity-fixtures/

# Update this file with the new recrypt commit hash.
# Re-run Dreamball fixture tests:
zig build test
```

If the Dreamball tests now fail after resync, one of two things is true:

1. **recrypt's format spec changed** — update `src/identity_envelope.zig`
   and `docs/decisions/2026-04-21-identity-envelope.md` to reflect the
   new rule.
2. **One side has a silent bug** — compare the diff between our bytes
   and theirs, locate the disagreement, fix whichever side is wrong per
   the `docs/dcbor-determinism.md` spec.

## Why vendor rather than symlink or submodule

- **Symlinks** break CI (the recrypt checkout isn't guaranteed on
  builders).
- **Submodules** tie Dreamball CI to the whole recrypt workspace
  (~gigabytes of OpenFHE) for a few KB of fixtures.
- **Vendoring** is explicit: the commit hash pin is human-readable, the
  refresh step is a one-command copy, and diffs show up in review.

## Related

- `docs/decisions/2026-04-21-identity-envelope.md` — ADR that adopts
  this format.
- `.omc/plans/2026-04-21-dreamball-identity-envelope.md` — plan that
  specifies fixture-test expectations.
