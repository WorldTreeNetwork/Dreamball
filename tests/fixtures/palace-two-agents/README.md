# palace-two-agents fixture

Negative-test palace for `dreamball verify` invariant (b) — "oracle is the sole
direct Agent".

A valid `ball.*` palace whose `contains` set holds TWO
`ball.dreamball.agent` envelopes. `dreamball verify` reports:

```
error: multiple Agents directly contained; exactly one (oracle) permitted (invariant b)
```

Used by `scripts/cli-smoke.sh` (palace verify AC6).

## Regeneration

```bash
zig build export-palace-fixtures
```

Produced by `tools/export-palace-fixtures/main.zig` (`.two_agents` mutation).
Do not hand-edit the CAS bytes — regenerate from the generator.
