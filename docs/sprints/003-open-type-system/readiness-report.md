---
sprint: sprint-003
created: 2026-06-28
validation_status: ready
beads_mode: true
---

# Readiness Report — Sprint 003: Open Type System

## Verdict: READY (beads is the source of truth)

Materialized into beads: **3 epics** (Dreamball-79y/68e/0hg) + **13 stories**
(12 in-scope + 1 stretch), parented and dependency-wired. `bd ready` surfaces
**A1** (Dreamball-o3o) and **A4** (Dreamball-kbn) as the unblocked entry points.

## Coverage
- **FR1–FR11 all mapped** to stories (see `epics.md` FR disposition). No orphan FRs.
- **Decisions D-037–D-043 all consumed** by stories (D-037 → A1/A2; D-038/D-039 →
  A4/A2; D-041 → A3; D-042 → B1; D-043 → A2/C1).
- **5 flagged stories have full specs** (`stories/A1,A2,A4,B1,C1`); 8 remain stubs in
  beads, slated for the **enrichment pass after the flagged ones land**.
- Cross-linked & superseded standalone beads: `hp6`→B1, `fch`→A4, `t2d`→B3.

## Dependency sanity
A1→A2→{A3,A5,B1,C2}; B1→{B2,B3,B4,C1}; C1→C3; C2→D1. No cycles. Critical path:
A1 → A2 → B1 → C1 → C3.

## Risks carried into execution
- **HLC freeze (A4) must precede C1's golden vectors** — sequence A4 before C1
  locks the wire. Flagged in `epics.md`.
- **envelope_v2 → WASM size** (B1) — relaxed (NFR5); record raw+gz; soft 300 KB-gz flag.
- **Manual codegen propagation** (C2, TC5) — byte-equivalence gate is the guard.
- **`action-kind`→`kind` rename** is a real v3→v4 wire change — v3 path preserved as
  the palace profile; v3 goldens are a regression gate (A2/C1).

## Requirements conflicts (from Phase 2A)
1. Stale D-018/JSON-Schema-canonical reference in PROTOCOL.md → fixed in **C3**.
2. `action-kind`→`kind` rename documented in **A4**, gated by v3 regression goldens.
No unresolved conflicts.

## Gate discipline
Every story keeps `zig build test`/`smoke`, `server-smoke.sh`, Vitest,
`svelte-check` green (TC4). "Verified" requires `zig build smoke`.

## Next steps
1. Execute from beads: `bd ready` → start **A1** (Dreamball-o3o) and **A4**
   (Dreamball-kbn) in parallel.
2. After the 5 flagged stories land: **pause for the stub-enrichment pass** (A3, A5,
   B2, B3, B4, C2, C3, D1) before continuing — per the Phase 3.5 decision.
