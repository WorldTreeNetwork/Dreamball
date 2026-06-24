# palace-oracle-actor-mismatch fixture

Demonstrates the structural shape behind palace verify invariant (f / AC10)
"oracle actor-fp provenance".

A full, valid `ball.*` palace whose room-added action declares its `actor` as
the oracle **envelope** fp (the content-address of the oracle agent envelope)
rather than the key-derived oracle fp. AC10 compares an action actor against
the fp derived from `<palace>.oracle.key`.

**No `palace.oracle.key` is shipped with this fixture**, so `dreamball verify`
skips the AC10 provenance check entirely and the palace verifies as `palace ok`.
The fixture exists to pin the structural arrangement that *would* fail AC10 if a
real `oracle.key` with identity fp ≠ the envelope fp were present. It is not
referenced by `scripts/cli-smoke.sh`.

## Regeneration

```bash
zig build export-palace-fixtures
```

Produced by `tools/export-palace-fixtures/main.zig` (the `.oracle_mismatch`
mutation), alongside the five sibling negative-test palace fixtures. Do not
hand-edit the CAS bytes — regenerate from the generator.
