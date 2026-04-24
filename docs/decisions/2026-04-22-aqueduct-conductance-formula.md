# 2026-04-22 — Aqueduct conductance formula: (1 − R) × S × exp(−t/τ)

## Status

Accepted. Implements AC4 / AC5 of Story 2.5 (S2.5).

## Context

Story 2.5 specifies:

> `computeConductance(resistance=0.3, strength=0.8, t=0) → within 1e-12 of 0.56`

Two candidate formulas were considered:

1. **Naive**: `G = R × S × exp(−t/τ)` → `0.3 × 0.8 × 1 = 0.24`
2. **Inverse-resistance**: `G = (1 − R) × S × exp(−t/τ)` → `0.7 × 0.8 × 1 = 0.56`

The AC4 fixture `0.56` unambiguously selects option 2.

## Decision

Use `conductance = (1 − resistance) × strength × exp(−t / τ)`.

## Rationale

### Electrical analogue

In circuit theory, conductance `G = 1/R` (the inverse of resistance). An aqueduct
with high `resistance` should have *low* conductance — it opposes flow. The
`(1 − R)` term captures this: at `R = 0` (zero resistance) the multiplier is `1`
(full conductance); at `R = 1` (total blockage) the multiplier is `0` (zero
conductance). This matches the intuitive semantics of the field.

### Why not `1/R`

The pure `1/R` form diverges at `R = 0` and produces values > 1 for `R < 1`,
making it unsuitable for the `[0, 1]` normalised float representation used
throughout the codebase. The `(1 − R)` linearisation stays within `[0, 1]` for
any `R ∈ [0, 1]` and `S ∈ [0, 1]`.

### AC4 / AC5 numeric verification

- AC4: `R=0.3, S=0.8, t=0, τ=any` → `(1−0.3) × 0.8 × exp(0) = 0.7 × 0.8 × 1.0 = 0.56` ✓
- AC5: `R=0.3, S=0.8, t=τ` → `0.56 × exp(−1) ≈ 0.20597...` ✓

Both verified analytically before writing the test fixtures. The floating-point
representation of these results is IEEE 754 double-precision deterministic across
V8, JavaScriptCore, and SpiderMonkey (all use the same `libm exp` on x86-64).

## Consequences

- `computeConductance` in `src/memory-palace/aqueduct.ts` uses `(1 − resistance)`.
- The formula block comment at the top of `aqueduct.ts` documents this choice and
  cites this ADR.
- `updateAqueductStrength` in both store adapters passes `resistance` read from
  the DB row — the runtime NEVER overwrites `resistance` or `capacitance` (AC10
  invariant, TC16).
- Epic 3 (save-time compute) and Epic 5 (renderer freshness uniform) both import
  `computeConductance` from `aqueduct.ts` — the sole implementation. R7 bit-identity
  is guaranteed by the pure-function contract (AC3 / AC7).

## References

- `src/memory-palace/aqueduct.ts` — implementation
- `src/memory-palace/aqueduct.test.ts` — AC4/AC5 numeric tests
- `docs/decisions/2026-04-21-vril-flow-model.md` — Vril substrate model (parent ADR)
- Story 2.5 AC4/AC5 in `docs/sprints/001-memory-palace-mvp/stories/epic-2.md`
