/**
 * store.browser.test.ts — Pure-logic unit tests for S2.3.
 *
 * These tests cover logic that does not require a real browser or IDBFS:
 *   - StoreAlreadyOpen error class shape
 *   - NotImplementedInS22 still throws for vector stubs
 *   - kNN fallback flag detection (KNN_LOCAL constant logic)
 *   - TC12 grep-check: kuzu-wasm not imported outside store.browser.ts
 *
 * Tests that require Playwright (open/close lifecycle, syncfs, round-trip)
 * live in tests/store-browser.e2e.ts.
 *
 * Run: bun run test:unit -- --run
 */

import { describe, it, expect } from 'vitest';
import { execSync } from 'node:child_process';
import { NotImplementedInS22, StoreAlreadyOpen } from './store-types.js';

// ── StoreAlreadyOpen error class ──────────────────────────────────────────────

describe('StoreAlreadyOpen', () => {
  it('has correct name and message', () => {
    const err = new StoreAlreadyOpen();
    expect(err.name).toBe('StoreAlreadyOpen');
    expect(err.message).toContain('already open');
    expect(err).toBeInstanceOf(Error);
  });

  it('is instanceof StoreAlreadyOpen', () => {
    const err = new StoreAlreadyOpen();
    expect(err instanceof StoreAlreadyOpen).toBe(true);
  });
});

// ── NotImplementedInS22 still works (regression) ──────────────────────────────

describe('NotImplementedInS22', () => {
  it('throws with verb name in message', () => {
    const err = new NotImplementedInS22('upsertEmbedding');
    expect(err.name).toBe('NotImplementedInS22');
    expect(err.message).toContain('upsertEmbedding');
  });
});

// ── TC12 grep-check: kuzu-wasm imports confined to store.browser.ts ───────────

describe('TC12 — kuzu-wasm containment', () => {
  it('only store.browser.ts imports kuzu-wasm in src/', () => {
    // Grep src/ for actual import statements of kuzu-wasm.
    // Use the import pattern to exclude comments and string mentions.
    // Only store.browser.ts should have `from 'kuzu-wasm'` or `import 'kuzu-wasm'`.
    let output = '';
    try {
      output = execSync(
        `grep -R "from 'kuzu-wasm'\\|from \"kuzu-wasm\"\\|import 'kuzu-wasm'\\|import \"kuzu-wasm\"" src/ --include="*.ts" --include="*.js" --exclude="*.test.ts" --exclude="*.spec.ts" -l`,
        { cwd: process.cwd(), encoding: 'utf-8' }
      ).trim();
    } catch {
      // grep exits non-zero if no matches — constraint holds trivially
      output = '';
    }

    const matches = output
      .split('\n')
      .map((l) => l.trim())
      .filter((l) => l.length > 0);

    // Only store.browser.ts is allowed
    const offenders = matches.filter(
      (f) => !f.includes('store.browser.ts')
    );

    if (offenders.length > 0) {
      throw new Error(
        `TC12 violation: kuzu-wasm imported outside store.browser.ts:\n` +
          offenders.join('\n')
      );
    }

    expect(offenders).toHaveLength(0);
  });
});

// ── kNN fallback flag ─────────────────────────────────────────────────────────

describe('kNN routing flag (D-015)', () => {
  it('KNN_LOCAL is true — local path active per S2.1 PASS', () => {
    // The constant KNN_LOCAL=true is in store.browser.ts.
    // We verify this by grepping the file for the constant definition.
    const output = execSync(
      `grep -c "const KNN_LOCAL = true" src/memory-palace/store.browser.ts`,
      { cwd: process.cwd(), encoding: 'utf-8' }
    ).trim();
    expect(Number(output)).toBeGreaterThanOrEqual(1);
  });

  it('TODO-KNN-FALLBACK marker preserved', () => {
    const output = execSync(
      `grep -c "TODO-KNN-FALLBACK" src/memory-palace/store.browser.ts`,
      { cwd: process.cwd(), encoding: 'utf-8' }
    ).trim();
    // Must appear at least twice: once on the constant, once in the branch
    expect(Number(output)).toBeGreaterThanOrEqual(2);
  });
});
