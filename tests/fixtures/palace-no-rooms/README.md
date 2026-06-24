# palace-no-rooms fixture

Negative-test palace for `jelly verify` invariant (a) — "≥1 direct room".

A valid `ball.*` palace minted WITHOUT any `ball.dreamball.field` of
`field-kind: "room"` (and without the room-added action). `jelly verify`
reports:

```
error: palace has no rooms (invariant a: ≥1 direct room required)
```

Used by `scripts/cli-smoke.sh` (palace verify AC5).

## Regeneration

```bash
zig build export-palace-fixtures
```

Produced by `tools/export-palace-fixtures/main.zig` (`.no_room` mutation).
Do not hand-edit the CAS bytes — regenerate from the generator.
