# palace-head-hashes-wrong fixture

Negative-test palace for `jelly verify` invariant (e) — "timeline head-hashes
are leaves".

A valid `ball.*` palace whose `ball.timeline` lists, as a head-hash, the MINT
action — which is referenced as a `parent-hash` by the room-added action and is
therefore NOT a leaf. `jelly verify` reports:

```
error: head-hash <fp> is not a leaf — it is referenced as parent by another action (invariant e)
```

Note: the timeline encodes `head-hashes` as an ARRAY of byte-strings (the shape
`palace_verify.zig::parseTimelineHeadHashes` reads), so the head set parses
non-empty and the leaf check actually fires.

Used by `scripts/cli-smoke.sh` (palace verify AC9).

## Regeneration

```bash
zig build export-palace-fixtures
```

Produced by `tools/export-palace-fixtures/main.zig` (`.head_not_leaf`
mutation). Do not hand-edit the CAS bytes — regenerate from the generator.
