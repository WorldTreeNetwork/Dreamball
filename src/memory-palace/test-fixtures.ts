/**
 * test-fixtures.ts — Shared test fixture helpers for memory-palace tests.
 *
 * The security hardening pass (2026-04-24) made every fp argument to store
 * verbs pass through sanitizeFp in cypher-utils.ts, which requires 64-char
 * lowercase hex. Tests that hand-rolled short strings like 'palace-1' now
 * throw InvalidCypherValueError.
 *
 * Use fp('friendly-label') everywhere a test needs an fp. Same label always
 * produces the same hex string (SHA-256 over the label), so tests that share
 * fixtures across files converge on identical fps for the same names.
 */

import { createHash } from 'node:crypto';

/**
 * Deterministic 64-char hex fp from a friendly label.
 *
 * Use this EVERYWHERE in tests instead of hand-rolled short strings like
 * 'palace-1'. Production validators require fps to be 64 hex chars; fake
 * short strings throw InvalidCypherValueError.
 *
 * Collision-safe for test purposes: SHA-256 of the label encodes the same
 * label to the same fp across the whole suite, so fp('palace-1') is
 * consistent everywhere.
 */
export function fp(label: string): string {
  return createHash('sha256').update(label).digest('hex');
}
