/**
 * policy.ts — Guild policy gate + oracle bypass logic (Story 4.2).
 *
 * Exports:
 *   evaluateGuildPolicy(slot, requesterFp, palaceFp, opts) → PolicyResult
 *   evaluateWritePolicy(verb, requesterFp, palaceFp, opts)  → PolicyResult
 *   evaluateMythosPolicy(palaceFp, requesterFp, opts)       → PolicyResult
 *   PolicyAuditLog — in-memory ring buffer for policy audit events
 *
 * Decisions: D-007 (store-layer concern), D-016, D-011; SEC4, SEC5, SEC6.
 *
 * TODO-CRYPTO: requester identity un-challenged in MVP; next sprint adds signed-query envelopes.
 * The oracle fp is accepted at face value from the caller — no signature challenge in S4.2.
 * The MVP threat model is local-first single-custodian; an attacker reaching the store
 * in-process already has the .oracle.key file per D-011. See docs/known-gaps.md §7.
 * TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)
 */

// ── Types ─────────────────────────────────────────────────────────────────────

/** A policy "slot" — describes the Guild policy attached to one inscription. */
export interface PolicySlot {
  /** Avatar fp being accessed */
  fp: string;
  /** Palace that owns the avatar */
  palaceFp: string;
  /**
   * Policy kind:
   * - 'any-admin'  → only Guild members and the oracle may read
   * - 'public'     → any requester allowed
   */
  policy: 'any-admin' | 'public';
  /** Fps of known Guild members for this palace (SEC4). */
  guildFps: string[];
}

/** Result returned by every policy evaluator. */
export interface PolicyResult {
  allow: boolean;
  reason:
    | 'oracle-bypass'
    | 'guild-member'
    | 'guild-policy-denied'
    | 'public-read'
    | 'oracle-writes-restricted-to-file-watcher'
    | 'oracle-file-watcher-path'
    | 'mythos-always-public'
    | 'write-allowed';
}

/** One entry in the policy audit log. */
export interface PolicyAuditEntry {
  timestamp: number;
  palaceFp: string;
  requesterFp: string;
  slotFp?: string;
  reason: PolicyResult['reason'];
  verb?: string;
}

// ── PolicyAuditLog ────────────────────────────────────────────────────────────

/**
 * In-memory ring buffer for policy audit events (MVP).
 *
 * TODO: persist audit log to durable store (S4.3+ or ops hardening sprint).
 * Size cap is noted here; overflow silently drops oldest entries.
 */
export class PolicyAuditLog {
  private _entries: PolicyAuditEntry[] = [];
  private readonly _maxEntries: number;

  constructor(maxEntries = 1000) {
    this._maxEntries = maxEntries;
  }

  record(entry: Omit<PolicyAuditEntry, 'timestamp'>): void {
    if (this._entries.length >= this._maxEntries) {
      // Drop oldest entry (ring-buffer eviction)
      this._entries.shift();
    }
    this._entries.push({ ...entry, timestamp: Date.now() });
  }

  entries(): readonly PolicyAuditEntry[] {
    return this._entries;
  }

  clear(): void {
    this._entries = [];
  }
}

// ── Module-level default audit log (MVP singleton) ────────────────────────────

/** Default audit log — shared by the module unless a custom one is passed. */
export const defaultAuditLog = new PolicyAuditLog();

// ── evaluateGuildPolicy ───────────────────────────────────────────────────────

export interface GuildPolicyOpts {
  /** The oracle fp for this palace — used to detect oracle-bypass (SEC5). */
  oracleFp: string;
  /** Optional audit log; defaults to defaultAuditLog. */
  auditLog?: PolicyAuditLog;
}

/**
 * Evaluate read access for an inscription slot.
 *
 * Decision path (in order):
 *   1. If policy is 'public' → allow (reason: 'public-read').
 *   2. If requesterFp === oracleFp → oracle bypass (SEC5) (reason: 'oracle-bypass').
 *      TODO-CRYPTO: requester identity un-challenged in MVP; next sprint adds signed-query envelopes.
 *   3. If requesterFp is in slot.guildFps → guild member (SEC4) (reason: 'guild-member').
 *   4. Otherwise → deny (reason: 'guild-policy-denied').
 *
 * @param slot         Policy slot describing the inscription's access control
 * @param requesterFp  Blake3 fp of the agent requesting access (REQUIRED — no anonymous default)
 * @param palaceFp     Blake3 fp of the palace being queried
 * @param opts         Oracle fp + optional audit log
 */
export function evaluateGuildPolicy(
  slot: PolicySlot,
  requesterFp: string,
  palaceFp: string,
  opts: GuildPolicyOpts
): PolicyResult {
  const auditLog = opts.auditLog ?? defaultAuditLog;

  // 1. Public policy: anyone can read
  if (slot.policy === 'public') {
    const result: PolicyResult = { allow: true, reason: 'public-read' };
    auditLog.record({ palaceFp, requesterFp, slotFp: slot.fp, reason: result.reason });
    return result;
  }

  // 2. Oracle bypass (SEC5) — accept at face value in MVP
  //    TODO-CRYPTO: requester identity un-challenged in MVP; next sprint adds signed-query envelopes.
  if (opts.oracleFp.length > 0 && requesterFp === opts.oracleFp) {
    const result: PolicyResult = { allow: true, reason: 'oracle-bypass' };
    auditLog.record({ palaceFp, requesterFp, slotFp: slot.fp, reason: result.reason });
    return result;
  }

  // 3. Guild member check (SEC4)
  if (slot.guildFps.includes(requesterFp)) {
    const result: PolicyResult = { allow: true, reason: 'guild-member' };
    auditLog.record({ palaceFp, requesterFp, slotFp: slot.fp, reason: result.reason });
    return result;
  }

  // 4. Deny
  const result: PolicyResult = { allow: false, reason: 'guild-policy-denied' };
  auditLog.record({ palaceFp, requesterFp, slotFp: slot.fp, reason: result.reason });
  return result;
}

// ── evaluateWritePolicy ───────────────────────────────────────────────────────

export interface WritePolicyOpts {
  /** The oracle fp for this palace — oracle is blocked from all writes except file-watcher path. */
  oracleFp: string;
  /** Optional audit log. */
  auditLog?: PolicyAuditLog;
  /**
   * Origin context — only the file-watcher path may write with the oracle fp.
   *
   * S4.4: when origin === 'file-watcher' AND requesterFp === oracleFp, allow with
   * reason: 'oracle-file-watcher-path'. All other oracle-fp write attempts still
   * deny with reason: 'oracle-writes-restricted-to-file-watcher'.
   *
   * The S4.2 AC5 guard remains intact: any oracle-fp write NOT from 'file-watcher'
   * origin is still blocked.
   */
  ctx?: {
    origin: 'file-watcher' | 'custodian' | 'stranger';
  };
}

/**
 * AC5 (S4.2): Ensure oracle-bypass does NOT leak into mutation verbs.
 *
 * If requesterFp === oracleFp AND origin is NOT 'file-watcher': reject with
 * reason: 'oracle-writes-restricted-to-file-watcher'.
 *
 * If requesterFp === oracleFp AND origin IS 'file-watcher': allow with
 * reason: 'oracle-file-watcher-path' (S4.4 legitimate path).
 *
 * All other requesters are allowed through (write authorisation is handled
 * by the custodian-signed action path, not by this function).
 *
 * @param verb        Name of the write verb being called (for audit context)
 * @param requesterFp Blake3 fp of the agent attempting the write
 * @param palaceFp    Blake3 fp of the palace
 * @param opts        Oracle fp + optional audit log + optional origin context
 */
export function evaluateWritePolicy(
  verb: string,
  requesterFp: string,
  palaceFp: string,
  opts: WritePolicyOpts
): PolicyResult {
  const auditLog = opts.auditLog ?? defaultAuditLog;

  if (opts.oracleFp.length > 0 && requesterFp === opts.oracleFp) {
    // S4.4: file-watcher is the ONLY legitimate oracle write path
    if (opts.ctx?.origin === 'file-watcher') {
      const result: PolicyResult = { allow: true, reason: 'oracle-file-watcher-path' };
      auditLog.record({ palaceFp, requesterFp, reason: result.reason, verb });
      return result;
    }
    // All other oracle-fp writes are blocked (S4.2 AC5 guard)
    const result: PolicyResult = {
      allow: false,
      reason: 'oracle-writes-restricted-to-file-watcher',
    };
    auditLog.record({ palaceFp, requesterFp, reason: result.reason, verb });
    return result;
  }

  const result: PolicyResult = { allow: true, reason: 'write-allowed' };
  auditLog.record({ palaceFp, requesterFp, reason: result.reason, verb });
  return result;
}

// ── evaluateMythosPolicy ──────────────────────────────────────────────────────

export interface MythosPolicyOpts {
  /** Optional audit log. */
  auditLog?: PolicyAuditLog;
}

/**
 * AC6 / SEC3: The canonical mythos chain is always public regardless of Guild policy.
 *
 * Always returns {allow: true, reason: 'mythos-always-public'}.
 * The reason is explicitly NOT 'oracle-bypass' — this is a SEC3 invariant,
 * not an oracle privilege.
 *
 * @param palaceFp    Blake3 fp of the palace
 * @param requesterFp Blake3 fp of the requester (any value — always allowed)
 * @param opts        Optional audit log
 */
export function evaluateMythosPolicy(
  palaceFp: string,
  requesterFp: string,
  opts: MythosPolicyOpts = {}
): PolicyResult {
  const auditLog = opts.auditLog ?? defaultAuditLog;
  const result: PolicyResult = { allow: true, reason: 'mythos-always-public' };
  auditLog.record({ palaceFp, requesterFp, reason: result.reason });
  return result;
}
