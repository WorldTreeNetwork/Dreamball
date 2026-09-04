# Tasks

- [ ] Move `memory_connection` out of `writeCoreManifest` into the
      archiform writer in `tools/export-golden-fixtures/main.zig`
- [ ] Move `layout` out of the contested writer into the archiform writer
- [ ] File `trust_observation` as identikey-offered (not core, not palace,
      not contested); empty or delete `contested-manifest.json`
- [ ] Re-run `zig build export-golden-fixtures`; core manifest has exactly
      `zero_seed`, `action_v4_unsigned`, `action_v4_signed`; `GoldenDrift` green
- [ ] Update `fixtures/goldens/README.md` partition table
- [ ] Amend `docs/decisions/2026-08-07-substrate-palace-boundary.md`:
      Memory and Layout stay archiform; TrustObservation is identikey-offered
- [ ] Close `Dreamball-y4t.21` when the files and ADR match steer
- [ ] Send-back (sol-arch-review): README partition table names the same core three as the spec delta
- [ ] Send-back (sol-arch-review): ADR destinations table lists TrustObservation as identikey-offered, not archiform
- [ ] ASK: second-family advise with a write-capable CLI (Fable credit exhausted; Sol HTTP could not inspect files)

Findings (not boxes): steer 2026-09-04 is in `steer.md` and the bead design.
`y4t.25` still ports core only. `h7s` / `etk` repos are not this change.
Sol harvest 2026-09-04: core set **may** exclude Memory, Layout, and TrustObservation; send-back is procedural (read-only interface), not an objection to that exclusion.
