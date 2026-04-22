/**
 * S2.1 — Cross-runtime vector-parity spike: browser half (AC3, AC6)
 *
 * Runs kuzu-wasm@0.11.3 in Playwright Chromium with the same 100-vector
 * fixture (seed=42) and query vector (seed=43) used by the server test.
 * Compares browser results against the server ground truth embedded here.
 *
 * Outcome classification (D-015):
 *   PASS       — set-equal AND all |Δ| ≤ 0.1
 *   WARN       — set-equal BUT some |Δ| > 0.1  → test passes with annotation
 *   HARD BLOCK — not set-equal               → test fails with literal message
 *
 * After this test runs (pass or fail), the result is written to:
 *   docs/sprints/001-memory-palace-mvp/addenda/S2.1-parity-result.md
 * via a fixture teardown (see globalTeardown below).
 *
 * Run: bun run test:e2e
 */

import { test, expect } from '@playwright/test';
import { writeFileSync, mkdirSync, readFileSync, appendFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..');

// ── Server ground truth (from AC2 vitest run) ────────────────────────────────
// Recorded: 2026-04-22 by S2.1 vitest server test (parity.test.ts AC2)
// Re-run `bun run test:unit -- --run --project=server` to refresh these values.
const SERVER_GROUND_TRUTH: Array<{ fp: string; distance: number }> = [
  { fp: 'v79', distance: 0.7617 },
  { fp: 'v18', distance: 0.8787 },
  { fp: 'v31', distance: 0.8877 },
  { fp: 'v32', distance: 0.8938 },
  { fp: 'v1',  distance: 0.8952 },
  { fp: 'v28', distance: 0.8985 },
  { fp: 'v33', distance: 0.9018 },
  { fp: 'v66', distance: 0.9029 },
  { fp: 'v44', distance: 0.9133 },
  { fp: 'v60', distance: 0.9176 }
];

// ── Parity classification (mirrors parity.test.ts classifyParity) ─────────────

interface KnnRow { fp: string; distance: number }

function classifyParity(
  server: KnnRow[],
  browser: KnnRow[]
): { outcome: 'PASS' | 'WARN' | 'HARD BLOCK'; maxDelta: number; setEqual: boolean } {
  const serverFps = new Set(server.map(r => r.fp));
  const browserFps = new Set(browser.map(r => r.fp));
  const setEqual =
    serverFps.size === browserFps.size &&
    [...serverFps].every(fp => browserFps.has(fp));

  if (!setEqual) {
    return { outcome: 'HARD BLOCK', maxDelta: Infinity, setEqual: false };
  }
  let maxDelta = 0;
  for (const br of browser) {
    const sr = server.find(r => r.fp === br.fp);
    if (sr) {
      const d = Math.abs(br.distance - sr.distance);
      if (d > maxDelta) maxDelta = d;
    }
  }
  return { outcome: maxDelta <= 0.1 ? 'PASS' : 'WARN', maxDelta, setEqual: true };
}

// ── Helper: write addendum ────────────────────────────────────────────────────

function writeAddendum(
  outcome: 'PASS' | 'WARN' | 'HARD BLOCK',
  maxDelta: number,
  setEqual: boolean,
  browserRows: KnnRow[],
  errorMsg?: string
): void {
  const addendaDir = resolve(
    REPO_ROOT,
    'docs/sprints/001-memory-palace-mvp/addenda'
  );
  mkdirSync(addendaDir, { recursive: true });

  const branch =
    outcome === 'HARD BLOCK'
      ? 'HTTP fallback (server-only K-NN): S2.3 must use HTTP route; S6.3 must add /kNN endpoint'
      : 'Local kuzu-wasm kNN: S2.3 uses local QUERY_VECTOR_INDEX; S6.3 no HTTP fallback needed';

  const content = `# S2.1 Parity Result — D-015 R2 Gate

**Date**: ${new Date().toISOString().split('T')[0]}
**Outcome**: ${outcome}
**Set-equal**: ${setEqual ? 'YES' : 'NO'}
**Max |Δ| (cosine distance)**: ${maxDelta === Infinity ? 'N/A (set inequality)' : maxDelta.toFixed(6)}

## Server ground truth (top-10 fps)

\`\`\`
${SERVER_GROUND_TRUTH.map(r => `${r.fp}: ${r.distance.toFixed(4)}`).join('\n')}
\`\`\`

## Browser results (kuzu-wasm@0.11.3 Chromium)

\`\`\`
${browserRows.length > 0 ? browserRows.map(r => `${r.fp}: ${r.distance.toFixed(4)}`).join('\n') : `ERROR: ${errorMsg}`}
\`\`\`

## Routing branch for S2.3 and S6.3

${branch}

${outcome === 'WARN' ? `## WARN detail

Max cosine-distance variance |Δ| = ${maxDelta.toFixed(6)} exceeds 0.1 threshold.
Set equality holds — same fps returned.
TODO-KNN-PARITY-UPSTREAM: file upstream issue if variance is persistent across fixture seeds.
LadybugDB upstream reference: #399 (if applicable — verify before filing).

` : ''}${outcome === 'HARD BLOCK' ? `## HARD BLOCK detail

Browser fps differ from server fps. This is a D-015 R2 HARD BLOCK.
S2.3 must fall back to HTTP K-NN endpoint. S6.3 must implement /kNN route.
NFR11 K-NN relaxation required: see docs/known-gaps.md entry added by this test.

Error: ${errorMsg || 'set inequality — different fps returned'}

` : ''}## Environment

- @ladybugdb/core: 0.15.3 (server, Bun + vitest)
- kuzu-wasm: 0.11.3 (browser, Playwright Chromium)
- Fixture: 100 vectors × 256 dims, seed=42; query seed=43; unit-normalised
- SHA-256 pin: 9ff1615985a29958e9589546a8dda1c4fc64bbfdbef9a2ec5f1b9250c6a0c7b2
`;

  writeFileSync(resolve(addendaDir, 'S2.1-parity-result.md'), content);
  console.log(`[S2.1] Addendum written to docs/sprints/001-memory-palace-mvp/addenda/S2.1-parity-result.md`);
}

// ── Helper: write known-gaps entry on HARD BLOCK ──────────────────────────────

function writeKnownGapsEntry(): void {
  // Append to docs/known-gaps.md
  const gapsPath = resolve(REPO_ROOT, 'docs/known-gaps.md');
  const entry = `
### NFR11 K-NN relaxation (added by S2.1 HARD BLOCK)

**State**: HARD BLOCK detected by S2.1 parity spike (${new Date().toISOString().split('T')[0]}).

**Why**: kuzu-wasm@0.11.3 browser QUERY_VECTOR_INDEX returned fps not matching
@ladybugdb/core server ground truth. D-015 set-equality contract violated.

**NFR11 relaxation**: K-NN queries in the browser must route to jelly-server
HTTP /kNN endpoint. Offline K-NN is degraded for MVP. Epic 6 must add the
/kNN route.

**Path forward**: S2.3 implements HTTP fallback kNN; S6.3 adds /kNN endpoint.
TODO-KNN-FALLBACK markers must be preserved until both stories land.

`;
  const existing = readFileSync(gapsPath, 'utf-8');
  if (!existing.includes('NFR11 K-NN relaxation')) {
    appendFileSync(gapsPath, entry);
    console.log('[S2.1 HARD BLOCK] NFR11 entry appended to docs/known-gaps.md');
  }
}

// ── The test ──────────────────────────────────────────────────────────────────

test.describe('S2.1 — browser parity (AC3)', () => {
  test(
    'kuzu-wasm@0.11.3 Chromium kNN matches server ground truth (D-015)',
    async ({ page }) => {
      // Navigate to the parity test page (served by playwright.config.ts webServer)
      await page.goto('http://localhost:4321/', { waitUntil: 'domcontentloaded' });

      // Wait for kuzu-wasm to complete (window.__parityResult populated)
      // Timeout: 90s — kuzu-wasm WASM init + 100 inserts can be slow
      await page.waitForFunction(
        () => typeof (window as unknown as { __parityResult?: unknown }).__parityResult !== 'undefined',
        { timeout: 90_000 }
      );

      const result = await page.evaluate(() => {
        return (window as unknown as { __parityResult: { status: string; rows?: Array<{ fp: string; distance: number }>; error?: string } }).__parityResult;
      });

      // Capture browser console for diagnosis
      const consoleMsgs: string[] = [];
      page.on('console', msg => consoleMsgs.push(`[browser] ${msg.text()}`));

      if (result.status === 'error') {
        // Browser kuzu-wasm failed entirely — HARD BLOCK
        writeAddendum('HARD BLOCK', Infinity, false, [], result.error);
        writeKnownGapsEntry();
        // AC5: must fail with this literal message
        throw new Error('HARD BLOCK: D-015 parity — kuzu-wasm browser error: ' + result.error);
      }

      const browserRows = result.rows || [];
      console.log(
        '[S2.1 AC3] Browser top-10:',
        browserRows.map(r => `${r.fp}:${r.distance.toFixed(4)}`).join(', ')
      );

      const { outcome, maxDelta, setEqual } = classifyParity(SERVER_GROUND_TRUTH, browserRows);

      writeAddendum(outcome, maxDelta, setEqual, browserRows);

      if (outcome === 'HARD BLOCK') {
        writeKnownGapsEntry();
        // AC5: must fail with this literal string
        throw new Error(
          `HARD BLOCK: D-015 parity — browser fps differ from server ground truth. ` +
          `Server: [${SERVER_GROUND_TRUTH.map(r => r.fp).join(',')}] ` +
          `Browser: [${browserRows.map(r => r.fp).join(',')}]`
        );
      }

      if (outcome === 'WARN') {
        // AC4: test PASSES but annotate
        console.warn(
          `[S2.1 AC4] WARN — set-equal but max |Δ| = ${maxDelta.toFixed(4)} > 0.1. ` +
          `TODO-KNN-PARITY-UPSTREAM: LadybugDB upstream #399 if persistent.`
        );
        test.info().annotations.push({
          type: 'warn',
          description: `D-015 WARN: max |Δ| = ${maxDelta.toFixed(4)} — set-equal but variance > 0.1`
        });
        // Test still passes (no throw)
      }

      // AC3 assertions
      expect(setEqual).toBe(true);
      expect(browserRows).toHaveLength(10);
      if (outcome === 'PASS') {
        // All deltas ≤ 0.1
        for (const br of browserRows) {
          const sr = SERVER_GROUND_TRUTH.find(r => r.fp === br.fp);
          if (sr) {
            expect(Math.abs(br.distance - sr.distance)).toBeLessThanOrEqual(0.1);
          }
        }
      }

      console.log(`[S2.1] Outcome: ${outcome} | max |Δ| = ${maxDelta === Infinity ? 'N/A' : maxDelta.toFixed(6)} | set-equal: ${setEqual}`);
    }
  );
});
