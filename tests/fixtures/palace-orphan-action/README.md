# palace-orphan-action fixture

Negative-test palace for `jelly verify` invariant (c) — "action parent-hashes
resolve".

A valid `ball.*` palace whose room-added `ball.action` carries a
`parent-hashes` entry (`0xDE × 32`) that is NOT present in the CAS.
`jelly verify` reports:

```
error: action <fp> has unresolvable parent-hash dede…dede (invariant c)
```

Used by `scripts/cli-smoke.sh` (palace verify AC7).

## Regeneration

```bash
zig build export-palace-fixtures
```

Produced by `tools/export-palace-fixtures/main.zig` (`.orphan_action`
mutation). Do not hand-edit the CAS bytes — regenerate from the generator.
