---
id: A4
epic: A
title: Protocol spec — HLC specification + kind namespace convention (freeze fch)
status: ready
test_tier: smoke
decisions: [D-038, D-039]
frs: [FR10]
closes_beads: [Dreamball-fch]
---

# A4 — HLC + kind-namespace protocol spec

## Context
The HLC shape and the open-kind convention are **protocol commitments** that get
frozen into `content_hash`; they must be written down before A2's encoding is
treated as canonical. Resolves beads `Dreamball-fch`. Prescriptive register lives
in `docs/PROTOCOL.md` (VISION.md stays descriptive).

## Acceptance Criteria
1. `docs/PROTOCOL.md` gains an **"HLC Specification"** section: `hlc = [l, c]`,
   `l` = uint64 ms wall-clock advanced to `max(local_ms, last_l)+1`, `c` = uint64
   counter reset on `l` advance; total order `(l1,c1) < (l2,c2)`; concurrency when
   equal is resolved by the **consumer's** merge rule (protocol imposes none);
   **mandatory** in v4 `ball.action`. Wire = 2-int CBOR array, no tag.
2. `docs/PROTOCOL.md` gains a **"Kind Namespace Convention"** section: `kind` is a
   bare UTF-8 string; recommended (not enforced) dot convention
   `<namespace>.<noun>.<verb>` (e.g. `worldtree.kanban-card.move`,
   `palace.room-added`); zero-length kind is illegal.
3. The **v3→v4 wire change** is documented: `action-kind`→`kind`, added `body`,
   added `hlc`, `format-version` 3→4; v3 remains the palace profile.
4. The stale D-018/JSON-Schema-canonical claim flagged in Requirements Conflict #1
   is corrected wherever it appears in PROTOCOL.md (cross-ref C3).

## Task Breakdown
- Write the two PROTOCOL.md sections + the v3→v4 change note.
- `bd close Dreamball-fch` referencing this story once merged.

## Test Plan
- Doc review; `markdownlint` clean; cross-links resolve. (No code.)

## Files
`docs/PROTOCOL.md`.

## Dependencies
Parallel to A1–A3, but **must freeze before A2's encoding is locked by C1's golden
vectors**.
