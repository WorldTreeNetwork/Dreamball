/**
 * aqueduct.ts — Canonical home for FR26 Hebbian + Ebbinghaus formulas.
 *
 * Date: 2026-04-21 (Vril ADR date)
 *
 * Status: **tunable; in flux** — formula constants are early proposals grounded
 * in brain research (Hebbian plasticity, Ebbinghaus forgetting curve). Numbers
 * are provisional and expected to be tuned based on user experience.
 *
 * Authoritative references:
 *   D4 steering decision (phase-state.json): "Aqueduct strength/conductance/phase
 *     formulas — Hebbian saturating + Ebbinghaus decay + qualitative phase enum;
 *     explicitly in flux; grounded in brain research."
 *   docs/decisions/2026-04-21-vril-flow-model.md — Vril is monotone on the
 *     signed chain; freshness is renderer-side; default half-life 30 days.
 *
 * ─── Formulas ───────────────────────────────────────────────────────────────
 *
 * 1. Strength (Hebbian saturating):
 *      strength_new = strength + α × (1 − strength)
 *    Converges to 1 from above; never exceeds 1.0; never decremented (wire
 *    monotone per Vril ADR §4). α is the learning rate (MVP default: 0.1).
 *    After n steps from 0:  s_n = 1 − (1 − α)^n
 *
 * 2. Conductance (Ebbinghaus decay, inverse-resistance electrical analogue):
 *      conductance = (1 − resistance) × strength × exp(−t / τ)
 *    The (1 − R) term makes higher resistance reduce conductance — matches the
 *    electrical analogue where resistance opposes flow. See
 *    docs/decisions/2026-04-22-aqueduct-conductance-formula.md for the
 *    derivation that chose (1 − R) over R.
 *    τ (tau) is the Ebbinghaus time constant (MVP default: 30 days in ms).
 *
 * 3. Phase (qualitative classification of traversal window):
 *      'out'      — all traversals are out-direction
 *      'in'       — all traversals are in-direction
 *      'resonant' — mixed, count ≥ 4, symmetry_ratio = min(in,out)/max(in,out) ∈ [0.4, 0.6]
 *      'standing' — all other mixed cases
 *    Resonance threshold: count ≥ 4 AND symmetry_ratio ∈ [0.4, 0.6].
 *    Open Question (b) from story 2.5: this threshold is a proposed default;
 *    further tuning expected as usage data accumulates.
 *
 * 4. Freshness (renderer-side, monotone-decreasing in t):
 *      freshnessForRender(strength, t, τ) = exp(−t / τ)
 *    Returns [0, 1]; at t=0 returns exactly 1.0; strictly decreasing in t.
 *    The strength parameter is not used in the decay shape — it is encoded
 *    separately in the aqueduct row. The freshness function is a pure decay
 *    function so that the renderer receives a [0,1] uniform that is
 *    bit-identical regardless of which call site invokes it (R7 mitigation).
 *
 * ─── Purity guarantee (AC3) ─────────────────────────────────────────────────
 * Every exported function is pure: no shared state, no mutation, no I/O,
 * no Math.random. Given identical Float64 inputs they return bit-identical
 * Float64 outputs across any number of call sites or workers (R7).
 */

// ── Types ─────────────────────────────────────────────────────────────────────

/** Qualitative phase of an aqueduct derived from its traversal window. */
export type Phase = 'in' | 'out' | 'standing' | 'resonant';

/**
 * A window of traversal events used to classify an aqueduct's phase.
 * Defined here; Epic 3 imports from this module.
 */
export interface TraversalWindow {
  events: { direction: 'in' | 'out'; t_ms: number }[];
}

// ── updateStrength ────────────────────────────────────────────────────────────

/**
 * Apply one Hebbian saturating update step.
 *
 *   strength_new = s + α × (1 − s)
 *
 * Properties:
 *   - Monotone-increasing (TC17): s_new > s when α > 0 and s < 1.
 *   - Converges to 1.0 asymptotically; never exceeds 1.0.
 *   - Pure function: no side effects, no shared state.
 *
 * @param strength  Current strength in [0, 1].
 * @param alpha     Learning rate (α), typically 0.1 for MVP.
 * @returns         Updated strength in [0, 1].
 */
export function updateStrength(strength: number, alpha: number): number {
  return strength + alpha * (1 - strength);
}

// ── computeConductance ────────────────────────────────────────────────────────

/**
 * Compute Ebbinghaus-decayed conductance.
 *
 *   conductance = (1 − resistance) × strength × exp(−t / τ)
 *
 * The (1 − R) factor makes higher resistance reduce conductance. This matches
 * the electrical analogue where resistance opposes current flow. See
 * docs/decisions/2026-04-22-aqueduct-conductance-formula.md.
 *
 * Reference check (AC4): R=0.3, S=0.8, t=0, τ=any
 *   → (1 − 0.3) × 0.8 × exp(0) = 0.7 × 0.8 × 1 = 0.56 ✓
 *
 * Reference check (AC5): same with t=τ
 *   → 0.56 × exp(−1) ≈ 0.2060 ✓
 *
 * @param resistance  Aqueduct resistance in [0, 1].
 * @param strength    Aqueduct strength in [0, 1].
 * @param t_ms        Time since last traversal in milliseconds.
 * @param tau_ms      Ebbinghaus time constant in milliseconds (default: 30 days).
 * @returns           Conductance in [0, 1].
 */
export function computeConductance(
  resistance: number,
  strength: number,
  t_ms: number,
  tau_ms: number
): number {
  return (1 - resistance) * strength * Math.exp(-t_ms / tau_ms);
}

// ── derivePhase ───────────────────────────────────────────────────────────────

/**
 * Classify the qualitative phase of an aqueduct from its traversal window.
 *
 * Classification rules (applied in order):
 *   1. If all events are 'out' (or window is empty-out): 'out'
 *   2. If all events are 'in': 'in'
 *   3. If mixed AND count ≥ 4 AND symmetry_ratio ∈ [0.4, 0.6]: 'resonant'
 *   4. Otherwise (mixed, below resonance threshold): 'standing'
 *
 * Resonance threshold (Open Question b — baked in for MVP):
 *   count ≥ 4 AND symmetry_ratio = min(in_count, out_count) / max(in_count, out_count) ∈ [0.4, 0.6]
 *
 * @param window  Traversal event window.
 * @returns       Phase classification.
 */
export function derivePhase(window: TraversalWindow): Phase {
  const { events } = window;

  if (events.length === 0) return 'standing';

  const inCount = events.filter((e) => e.direction === 'in').length;
  const outCount = events.filter((e) => e.direction === 'out').length;

  if (inCount === 0) return 'out';
  if (outCount === 0) return 'in';

  // Mixed — check resonance threshold
  const total = events.length;
  if (total >= 4) {
    const symmetryRatio = Math.min(inCount, outCount) / Math.max(inCount, outCount);
    if (symmetryRatio >= 0.4 && symmetryRatio <= 0.6) {
      return 'resonant';
    }
  }

  return 'standing';
}

// ── freshnessForRender ────────────────────────────────────────────────────────

/**
 * Compute the renderer-side freshness value for an aqueduct.
 *
 *   freshnessForRender(strength, t, τ) = exp(−t / τ)
 *
 * Returns a value in [0, 1]:
 *   - At t = 0: exactly 1.0.
 *   - Strictly monotone-decreasing in t.
 *   - The strength parameter is accepted for call-site symmetry with
 *     computeConductance but does not affect the decay shape — freshness
 *     is a pure time-decay function so that Epic 3 (save-time) and Epic 5
 *     (renderer uniform) produce bit-identical Float64 values (R7 mitigation).
 *
 * Visual decay thresholds (from Vril ADR §7, renderer-side tunables):
 *   t = 30 days → "dusty" threshold (freshness ≈ e^-1 ≈ 0.368)
 *   t = 90 days → "cobwebs" (τ adjusted by renderer)
 *   t = 365 days → "sleeping" (ghost-luminance only)
 *
 * @param _strength  Ignored in decay shape; kept for call-site parity with computeConductance.
 * @param t_ms       Time since last traversal in milliseconds.
 * @param tau_ms     Ebbinghaus time constant in milliseconds (default: 30 days).
 * @returns          Freshness value in [0, 1].
 */
export function freshnessForRender(
  _strength: number,
  t_ms: number,
  tau_ms: number
): number {
  return Math.exp(-t_ms / tau_ms);
}

// ── Constants ─────────────────────────────────────────────────────────────────

/** Default Hebbian learning rate (α). Tunable; in flux. */
export const DEFAULT_ALPHA = 0.1;

/** Default Ebbinghaus time constant: 30 days in milliseconds. */
export const DEFAULT_TAU_MS = 30 * 24 * 60 * 60 * 1000;

// ── Vril ADR renderer-side thresholds (half-life constants) ───────────────────
//
// Per docs/decisions/2026-04-21-vril-flow-model.md §7, the renderer uses three
// visual-threshold constants derived from time-since-last-traversal. These are
// renderer-side tunables — NOT wire-format values — and they are exported from
// THIS module (not copied into shader wrappers) so Epic 5 shaders and any
// parity unit test (S5.5 R7) import bit-identical Float64 numerics.
//
//   DUSTY_MS    = 30d  → "dusty" threshold (τ): freshness ≈ exp(-1) ≈ 0.368
//   COBWEBS_MS  = 90d  → "cobwebs" — dust-cobweb overlay engages
//   SLEEPING_MS = 365d → "sleeping" — ghost-luminance only
//
// The shader uses these as visual anchors; changing them here reshapes the
// palace's lived-in feeling globally.

/** Vril-ADR "dusty" threshold: 30 days in ms. Also the default Ebbinghaus τ. */
export const DUSTY_MS = 30 * 24 * 60 * 60 * 1000;

/** Vril-ADR "cobwebs" threshold: 90 days in ms. dust-cobweb overlay engages. */
export const COBWEBS_MS = 90 * 24 * 60 * 60 * 1000;

/** Vril-ADR "sleeping" threshold: 365 days in ms. Ghost-luminance only. */
export const SLEEPING_MS = 365 * 24 * 60 * 60 * 1000;

// ── freshness (renderer-consumer-facing wrapper) ──────────────────────────────

/**
 * Compute renderer-side freshness from (now, lastTraversed).
 *
 * This is the call-site shape Epic 5 lenses use directly:
 *
 *   const f = freshness(Date.now(), aqueduct.last_traversed)
 *
 * Under the hood it is freshnessForRender(1.0, now - lastTraversed, tau),
 * preserving the R7 pure-function bit-identity contract. We export this as
 * a thin alias rather than copying the decay formula into the shader wrapper
 * so there is ONE implementation of freshness in the codebase
 * (docs/decisions/2026-04-21-vril-flow-model.md §7).
 *
 * @param now_ms          Current wall-clock in ms (Date.now()).
 * @param lastTraversed_ms Last-traversal timestamp in ms (from Aqueduct row).
 * @param tau_ms          Ebbinghaus time constant; defaults to DUSTY_MS (30d).
 * @returns               Freshness ∈ [0, 1]; 1.0 at now == lastTraversed.
 */
export function freshness(
  now_ms: number,
  lastTraversed_ms: number,
  tau_ms: number = DUSTY_MS
): number {
  const t = Math.max(0, now_ms - lastTraversed_ms);
  return freshnessForRender(1.0, t, tau_ms);
}
