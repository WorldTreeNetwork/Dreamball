/**
 * policy.test.ts — TDD tests for S4.2 oracle bypass + Guild policy gate.
 *
 * AC1: oracle requester reads Guild-restricted inscription → returns inscription,
 *      audit log reason: 'oracle-bypass'.
 * AC2: non-oracle non-Guild denied → {allow:false, reason:'guild-policy-denied'}.
 * AC3: Guild member passes → audit log reason: 'guild-member' (NOT oracle-bypass).
 * AC4: TODO-CRYPTO marker exists AND known-gaps.md entry documented.
 * AC5: bypass does NOT leak into mutation verbs → rejects with
 *      reason: 'oracle-writes-restricted-to-file-watcher'.
 * AC6: mythosChainTriples always public → audit log reason: 'mythos-always-public'.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  evaluateGuildPolicy,
  evaluateWritePolicy,
  evaluateMythosPolicy,
  PolicyAuditLog,
  type PolicySlot,
  type PolicyResult,
} from './policy.js';
import { isOracleRequester } from './oracle.js';
import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');

// ── Helpers ────────────────────────────────────────────────────────────────────

function makePalaceFp(): string { return 'palace'.padEnd(64, '0'); }
function makeOracleFp(): string { return 'oracle'.padEnd(64, '0'); }
function makeGuildFp(): string  { return 'guild'.padEnd(64, '0'); }
function makeStrangerFp(): string { return 'stranger'.padEnd(64, '0'); }

// A slot that requires guild membership
const GUILD_SLOT: PolicySlot = {
  fp: 'avatar'.padEnd(64, '0'),
  palaceFp: makePalaceFp(),
  policy: 'any-admin',
  guildFps: [makeGuildFp()],
};

// ── AC1: oracle bypass ─────────────────────────────────────────────────────────

describe('AC1 — oracle requester gets guild-restricted inscription via oracle-bypass', () => {
  it('evaluateGuildPolicy returns {allow:true, reason:"oracle-bypass"} for oracle fp', () => {
    const auditLog = new PolicyAuditLog();
    const result = evaluateGuildPolicy(GUILD_SLOT, makeOracleFp(), makePalaceFp(), {
      oracleFp: makeOracleFp(),
      auditLog,
    });
    expect(result.allow).toBe(true);
    expect(result.reason).toBe('oracle-bypass');
  });

  it('AC1: audit log records one entry with reason oracle-bypass', () => {
    const auditLog = new PolicyAuditLog();
    evaluateGuildPolicy(GUILD_SLOT, makeOracleFp(), makePalaceFp(), {
      oracleFp: makeOracleFp(),
      auditLog,
    });
    const entries = auditLog.entries();
    expect(entries).toHaveLength(1);
    expect(entries[0].reason).toBe('oracle-bypass');
    expect(entries[0].requesterFp).toBe(makeOracleFp());
  });
});

// ── AC2: non-oracle non-Guild denied ──────────────────────────────────────────

describe('AC2 — non-oracle non-Guild requester is denied', () => {
  it('evaluateGuildPolicy returns {allow:false, reason:"guild-policy-denied"} for stranger', () => {
    const auditLog = new PolicyAuditLog();
    const result = evaluateGuildPolicy(GUILD_SLOT, makeStrangerFp(), makePalaceFp(), {
      oracleFp: makeOracleFp(),
      auditLog,
    });
    expect(result.allow).toBe(false);
    expect(result.reason).toBe('guild-policy-denied');
  });

  it('AC2: audit log records denial reason', () => {
    const auditLog = new PolicyAuditLog();
    evaluateGuildPolicy(GUILD_SLOT, makeStrangerFp(), makePalaceFp(), {
      oracleFp: makeOracleFp(),
      auditLog,
    });
    const entries = auditLog.entries();
    expect(entries).toHaveLength(1);
    expect(entries[0].reason).toBe('guild-policy-denied');
    expect(entries[0].requesterFp).toBe(makeStrangerFp());
  });
});

// ── AC3: Guild member passes via normal path ───────────────────────────────────

describe('AC3 — Guild member passes with reason guild-member, not oracle-bypass', () => {
  it('evaluateGuildPolicy returns {allow:true, reason:"guild-member"} for guild member', () => {
    const auditLog = new PolicyAuditLog();
    const result = evaluateGuildPolicy(GUILD_SLOT, makeGuildFp(), makePalaceFp(), {
      oracleFp: makeOracleFp(),
      auditLog,
    });
    expect(result.allow).toBe(true);
    expect(result.reason).toBe('guild-member');
  });

  it('AC3: audit log reason is guild-member, NOT oracle-bypass', () => {
    const auditLog = new PolicyAuditLog();
    evaluateGuildPolicy(GUILD_SLOT, makeGuildFp(), makePalaceFp(), {
      oracleFp: makeOracleFp(),
      auditLog,
    });
    const entries = auditLog.entries();
    expect(entries[0].reason).toBe('guild-member');
    expect(entries[0].reason).not.toBe('oracle-bypass');
  });
});

// ── AC4: MVP limitation — un-challenged oracle-fp spoofing ────────────────────

describe('AC4 — MVP oracle-fp spoofing un-challenged: marker + known-gaps.md', () => {
  it('TODO-CRYPTO marker exists in policy.ts at the oracle-bypass site', () => {
    const policyPath = join(__dirname, 'policy.ts');
    const content = readFileSync(policyPath, 'utf-8');
    expect(content).toContain(
      'TODO-CRYPTO: requester identity un-challenged in MVP; next sprint adds signed-query envelopes'
    );
  });

  it('known-gaps.md documents MVP oracle-fp spoofing limitation', () => {
    const gapsPath = join(REPO_ROOT, 'docs', 'known-gaps.md');
    const content = readFileSync(gapsPath, 'utf-8');
    expect(content).toContain('oracle-fp spoofing');
  });
});

// ── AC5: bypass does NOT leak into mutation verbs ─────────────────────────────

describe('AC5 — oracle fp as requester on mutation verb is rejected', () => {
  it('evaluateWritePolicy returns denied for oracle requester on write verb', () => {
    const result = evaluateWritePolicy('inscribeAvatar', makeOracleFp(), makePalaceFp(), {
      oracleFp: makeOracleFp(),
    });
    expect(result.allow).toBe(false);
    expect(result.reason).toBe('oracle-writes-restricted-to-file-watcher');
  });

  it('AC5: non-oracle write is allowed through', () => {
    const result = evaluateWritePolicy('inscribeAvatar', makeGuildFp(), makePalaceFp(), {
      oracleFp: makeOracleFp(),
    });
    expect(result.allow).toBe(true);
  });
});

// ── AC6: mythos chain always public ───────────────────────────────────────────

describe('AC6 — mythosChainTriples always public for any requester', () => {
  it('evaluateMythosPolicy returns {allow:true, reason:"mythos-always-public"} for stranger', () => {
    const auditLog = new PolicyAuditLog();
    const result = evaluateMythosPolicy(makePalaceFp(), makeStrangerFp(), { auditLog });
    expect(result.allow).toBe(true);
    expect(result.reason).toBe('mythos-always-public');
  });

  it('AC6: evaluateMythosPolicy returns mythos-always-public even for oracle fp', () => {
    const auditLog = new PolicyAuditLog();
    const result = evaluateMythosPolicy(makePalaceFp(), makeOracleFp(), { auditLog });
    expect(result.allow).toBe(true);
    expect(result.reason).toBe('mythos-always-public');
    // Reason must NOT be oracle-bypass
    expect(result.reason).not.toBe('oracle-bypass');
  });

  it('AC6: audit log records mythos-always-public', () => {
    const auditLog = new PolicyAuditLog();
    evaluateMythosPolicy(makePalaceFp(), makeGuildFp(), { auditLog });
    const entries = auditLog.entries();
    expect(entries).toHaveLength(1);
    expect(entries[0].reason).toBe('mythos-always-public');
  });
});

// ── isOracleRequester ─────────────────────────────────────────────────────────

describe('isOracleRequester', () => {
  it('returns true when requesterFp matches oracleFp', () => {
    const oracleFp = makeOracleFp();
    expect(isOracleRequester(oracleFp, oracleFp)).toBe(true);
  });

  it('returns false when requesterFp does not match oracleFp', () => {
    expect(isOracleRequester(makeOracleFp(), makeStrangerFp())).toBe(false);
  });

  it('returns false for empty strings', () => {
    expect(isOracleRequester('', '')).toBe(false);
  });
});

// ── PolicyAuditLog ring-buffer behaviour ──────────────────────────────────────

describe('PolicyAuditLog ring-buffer', () => {
  it('stores multiple entries in insertion order', () => {
    const log = new PolicyAuditLog();
    const slot: PolicySlot = { fp: 'x'.repeat(64), palaceFp: makePalaceFp(), policy: 'any-admin', guildFps: [makeGuildFp()] };
    evaluateGuildPolicy(slot, makeOracleFp(), makePalaceFp(), { oracleFp: makeOracleFp(), auditLog: log });
    evaluateGuildPolicy(slot, makeStrangerFp(), makePalaceFp(), { oracleFp: makeOracleFp(), auditLog: log });
    evaluateGuildPolicy(slot, makeGuildFp(), makePalaceFp(), { oracleFp: makeOracleFp(), auditLog: log });
    const entries = log.entries();
    expect(entries[0].reason).toBe('oracle-bypass');
    expect(entries[1].reason).toBe('guild-policy-denied');
    expect(entries[2].reason).toBe('guild-member');
  });

  it('caps at MAX_ENTRIES when overfilled', () => {
    const log = new PolicyAuditLog(5);
    const slot: PolicySlot = { fp: 'x'.repeat(64), palaceFp: makePalaceFp(), policy: 'any-admin', guildFps: [] };
    for (let i = 0; i < 10; i++) {
      evaluateGuildPolicy(slot, makeStrangerFp(), makePalaceFp(), { oracleFp: makeOracleFp(), auditLog: log });
    }
    expect(log.entries().length).toBeLessThanOrEqual(5);
  });
});

// ── S4.4: file-watcher origin whitelist in evaluateWritePolicy ────────────────

describe('S4.4 AC — evaluateWritePolicy: file-watcher origin allows oracle writes', () => {
  it('oracle fp + origin:file-watcher → allow with reason oracle-file-watcher-path', () => {
    const log = new PolicyAuditLog();
    const result = evaluateWritePolicy(
      'reembed',
      makeOracleFp(),
      makePalaceFp(),
      { oracleFp: makeOracleFp(), auditLog: log, ctx: { origin: 'file-watcher' } }
    );
    expect(result.allow).toBe(true);
    expect(result.reason).toBe('oracle-file-watcher-path');
  });

  it('oracle fp + origin:file-watcher → audit log records oracle-file-watcher-path', () => {
    const log = new PolicyAuditLog();
    evaluateWritePolicy(
      'recordAction',
      makeOracleFp(),
      makePalaceFp(),
      { oracleFp: makeOracleFp(), auditLog: log, ctx: { origin: 'file-watcher' } }
    );
    const entries = log.entries();
    expect(entries).toHaveLength(1);
    expect(entries[0].reason).toBe('oracle-file-watcher-path');
  });

  it('oracle fp WITHOUT file-watcher origin → still blocked (S4.2 AC5 guard intact)', () => {
    const log = new PolicyAuditLog();
    const result = evaluateWritePolicy(
      'inscribeAvatar',
      makeOracleFp(),
      makePalaceFp(),
      { oracleFp: makeOracleFp(), auditLog: log }
    );
    expect(result.allow).toBe(false);
    expect(result.reason).toBe('oracle-writes-restricted-to-file-watcher');
  });

  it('oracle fp + origin:custodian → blocked (only file-watcher is exempt)', () => {
    const log = new PolicyAuditLog();
    const result = evaluateWritePolicy(
      'inscribeAvatar',
      makeOracleFp(),
      makePalaceFp(),
      { oracleFp: makeOracleFp(), auditLog: log, ctx: { origin: 'custodian' } }
    );
    expect(result.allow).toBe(false);
    expect(result.reason).toBe('oracle-writes-restricted-to-file-watcher');
  });

  it('oracle fp + origin:stranger → blocked', () => {
    const log = new PolicyAuditLog();
    const result = evaluateWritePolicy(
      'inscribeAvatar',
      makeOracleFp(),
      makePalaceFp(),
      { oracleFp: makeOracleFp(), auditLog: log, ctx: { origin: 'stranger' } }
    );
    expect(result.allow).toBe(false);
    expect(result.reason).toBe('oracle-writes-restricted-to-file-watcher');
  });

  it('non-oracle fp is always allowed regardless of origin ctx', () => {
    const log = new PolicyAuditLog();
    const result = evaluateWritePolicy(
      'inscribeAvatar',
      makeStrangerFp(),
      makePalaceFp(),
      { oracleFp: makeOracleFp(), auditLog: log, ctx: { origin: 'file-watcher' } }
    );
    expect(result.allow).toBe(true);
    expect(result.reason).toBe('write-allowed');
  });
});
