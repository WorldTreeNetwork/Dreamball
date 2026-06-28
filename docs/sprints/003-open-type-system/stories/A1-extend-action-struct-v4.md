---
id: A1
epic: A
title: Extend the Action struct to v4 (open kind + body + HLC)
status: ready
test_tier: thorough
decisions: [D-037, D-039, D-043]
frs: [FR1, FR5]
closes_beads: []
---

# A1 — Extend the `Action` struct to v4

## Context
Per D-037 we open the closed `ball.action` rather than fork a new type. The Zig
`Action` struct (`src/protocol_v2.zig:231`, format_version 3) carries
`action_kind: ActionKind` (closed 9-value enum at :188), `parent_hashes`, `actor`,
`target_fp?`, `timestamp?`, `deps`, `nacks`. This story changes the **struct
shape** only; encoder/decoder changes are A2.

## Acceptance Criteria
1. `Action.format_version` is `4`.
2. `action_kind: ActionKind` is replaced by `kind: []const u8` (open string). The
   `ActionKind` enum is retained as a convenience/palette helper (e.g. a
   `toWireString()` mapping) but is **not** a struct field of the wire type.
3. New fields added: `body: ?[]const u8 = null` (opaque CBOR bytes) and
   `hlc: [2]u64` (index 0 = `l`, index 1 = `c`).
4. Existing fields preserved: `parent_hashes`, `actor`, `target_fp?`, `timestamp?`,
   `deps`, `nacks`.
5. `type_string` stays `"ball.action"`.
6. `zig build` compiles; no encoder/decoder logic in this story (A2 owns that) —
   only the struct + any helper signatures it requires.

## Task Breakdown
- Edit `src/protocol_v2.zig` `Action` struct: bump version, swap field, add `body`,
  `hlc`.
- Keep `ActionKind` + `toWireString()`; add a doc comment that it is the palace
  profile's conventional kind set, not the wire type.
- Adjust any call sites that construct `Action` literally (palace code, tests) to
  set `kind` + `hlc` (palace authors use `ActionKind.x.toWireString()`); leave
  their behavior on the v3 path until A2 lands v4 encoding.

## Test Plan
- `zig build test` green (compile + existing Action-construction tests updated).
- No wire/golden changes yet (A2/C1).

## Files
`src/protocol_v2.zig` (+ call sites that build `Action`).

## Dependencies
None (first story). Blocks A2, A3, A5, C2.
