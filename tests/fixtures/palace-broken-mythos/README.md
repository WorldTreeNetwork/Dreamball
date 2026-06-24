# palace-broken-mythos fixture

Negative-test palace bundle used by `scripts/cli-smoke.sh` — the
`rename-mythos AC4` presence check and the `palace verify AC8` invariant (d)
("mythos chain to single genesis") path.

## Structure

A full, valid `ball.*` palace whose **mythos is deliberately broken**:

```
palace.bundle       — ordered fp manifest (line 0 = palace field fp);
                      line 3 is the broken mythos fp (sed -n '3p' contract)
palace.cas/         — content-addressed CBOR envelopes (Blake3-named):
                        palace field, oracle agent, broken mythos,
                        archiform-registry asset, mint action, timeline,
                        room field, room-added action
broken-mythos.cbor  — standalone copy of the broken mythos envelope bytes
                      (identical to the palace.cas/<mythos-fp> entry)
```

## What makes it broken

The single `ball.mythos` envelope is a valid dCBOR mythos with:

- `is-genesis: false`
- `predecessor: deadbeefdeadbeef…deadbeef` (32 bytes — `0xDEADBEEF × 8`, a
  sentinel value NOT present in the CAS)

When `walkToGenesis` (from `src/memory-palace/mythos-chain.zig`) tries to
resolve the predecessor fp from the CAS it finds nothing and returns
`unresolvable_predecessor`. `dreamball verify` reports invariant (d):

```
error: mythos chain has unresolvable predecessor at <fp> (invariant d)
```

Every other envelope (palace field, oracle agent, room, actions, timeline) is
a correctly-signed, correctly-content-addressed `ball.*` envelope, so the only
invariant that trips is (d) — no coincidental invariant-(a) "no rooms" stop.

## Usage

```bash
dreamball verify tests/fixtures/palace-broken-mythos/palace.bundle
# exit non-zero; stderr: "... unresolvable predecessor ... (invariant d)"
```

## Regeneration

This fixture (and the five sibling negative-test palaces) is produced by a
compiled Zig generator wired into the build:

```bash
zig build export-palace-fixtures
```

The generator mints a real valid `ball.*` palace via the same `dreamball`
encoders the CLI uses, then swaps the genesis mythos for the broken
non-genesis one above. See `tools/export-palace-fixtures/main.zig`. Never
hand-roll these bytes — regenerate from the generator instead.
