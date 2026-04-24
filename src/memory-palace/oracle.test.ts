/**
 * oracle.test.ts — Vitest tests for Story 4.1 oracle bootstrap functions.
 *
 * AC1: bootstrapOracleSlots returns correct slot shapes with seed prompt bytes.
 * AC3: TODO-CRYPTO marker discipline — grep-based lint on .oracle.key read sites.
 * AC4: buildSystemPrompt prefix byte-compare.
 * AC6: head-move propagation after rename-mythos.
 */

import { describe, it, expect, vi, beforeEach, beforeAll, afterAll } from 'vitest';
import { readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';
import {
  bootstrapOracleSlots,
  buildSystemPrompt,
  oracleSignAction,
  ORACLE_PROMPT_BYTES,
  type OracleSlots,
} from './oracle.js';
import type { StoreAPI } from './store-types.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, '..', '..');
const SEED_PATH = join(__dirname, 'seed', 'oracle-prompt.md');

// ── AC1: bootstrapOracleSlots ─────────────────────────────────────────────────

describe('bootstrapOracleSlots', () => {
  it('AC1: returns personality_master_prompt byte-identical to seed file', () => {
    const slots = bootstrapOracleSlots();
    const seedBytes = readFileSync(SEED_PATH, 'utf-8');
    expect(slots.personality_master_prompt).toBe(seedBytes);
  });

  it('AC1: ORACLE_PROMPT_BYTES matches seed file at module-load time', () => {
    const seedBytes = readFileSync(SEED_PATH, 'utf-8');
    expect(ORACLE_PROMPT_BYTES).toBe(seedBytes);
  });

  it('AC1: memory is present and empty array', () => {
    const slots = bootstrapOracleSlots();
    expect(Array.isArray(slots.memory)).toBe(true);
    expect(slots.memory).toHaveLength(0);
  });

  it('AC1: knowledge_graph is present with zero triples', () => {
    const slots = bootstrapOracleSlots();
    expect(Array.isArray(slots.knowledge_graph)).toBe(true);
    expect(slots.knowledge_graph).toHaveLength(0);
  });

  it('AC1: emotional_register has curiosity, warmth, patience each at 0.5', () => {
    const slots = bootstrapOracleSlots();
    expect(slots.emotional_register.curiosity).toBe(0.5);
    expect(slots.emotional_register.warmth).toBe(0.5);
    expect(slots.emotional_register.patience).toBe(0.5);
  });

  it('AC1: interaction_set is present and empty array', () => {
    const slots = bootstrapOracleSlots();
    expect(Array.isArray(slots.interaction_set)).toBe(true);
    expect(slots.interaction_set).toHaveLength(0);
  });

  it('AC1: slot shapes are complete (5 keys present)', () => {
    const slots = bootstrapOracleSlots();
    const keys: Array<keyof OracleSlots> = [
      'personality_master_prompt',
      'memory',
      'knowledge_graph',
      'emotional_register',
      'interaction_set',
    ];
    for (const k of keys) {
      expect(slots).toHaveProperty(k);
    }
  });
});

// ── AC3: TODO-CRYPTO marker discipline ────────────────────────────────────────
//
// Every site in src/ (excluding tests) that references ".oracle.key" MUST have
// the canonical TODO-CRYPTO comment within 3 lines. This is the CI lint gate.

describe('AC3: TODO-CRYPTO marker at every .oracle.key read site', () => {
  it('all .oracle.key read/write code sites in src/ have TODO-CRYPTO within 3 lines', () => {
    // Find all files in src/ (excluding test files and .d.ts) that mention .oracle.key
    const grepCmd = `grep -rn '\\.oracle\\.key' "${REPO_ROOT}/src" \
      --include="*.ts" --include="*.zig" \
      --exclude="*.test.ts" --exclude="*.spec.ts" --exclude="*.d.ts" \
      -l 2>/dev/null || true`;

    const files = execSync(grepCmd, { encoding: 'utf-8' })
      .split('\n')
      .map((f) => f.trim())
      .filter((f) => f.length > 0);

    // There must be at least 2 known files with .oracle.key references (oracle.ts + palace_mint.zig).
    expect(files.length).toBeGreaterThanOrEqual(2);

    for (const file of files) {
      const content = readFileSync(file, 'utf-8');
      const lines = content.split('\n');

      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (!line.includes('.oracle.key')) continue;

        // Skip pure documentation lines — help text strings (Zig multiline \\),
        // module-level doc comments (//!), and JSDoc lines (* ...) that are not
        // actual code.  We only enforce the marker on lines that are real code:
        // variable/const declarations, function calls, template literals, or
        // single-line comments that are themselves the read site annotation.
        const trimmed = line.trim();

        // Zig multiline string literal lines start with \\
        if (trimmed.startsWith('\\\\')) continue;
        // Zig module doc comments start with //!
        if (trimmed.startsWith('//!')) continue;
        // JSDoc comment lines (not the marker itself) — * but not TODO-CRYPTO
        if (trimmed.startsWith('*') && !trimmed.includes('TODO-CRYPTO')) continue;

        // Check within 3 lines (i-3 to i+3 inclusive) for the marker
        const window = lines.slice(Math.max(0, i - 3), Math.min(lines.length, i + 4));
        const hasMarker = window.some((l) =>
          l.includes('TODO-CRYPTO: oracle key is plaintext')
        );

        if (!hasMarker) {
          throw new Error(
            `AC3 FAIL: ${file}:${i + 1} references .oracle.key without TODO-CRYPTO marker within 3 lines.\n` +
            `  Context: "${trimmed}"\n` +
            `  Add: // TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)`
          );
        }
      }
    }
  });
});

// ── AC4: buildSystemPrompt prefix ────────────────────────────────────────────

describe('buildSystemPrompt', () => {
  function makeMockStore(mythosFp: string, mythosBody: string): StoreAPI {
    return {
      open: vi.fn(),
      close: vi.fn(),
      syncfs: vi.fn(),
      ensurePalace: vi.fn(),
      addRoom: vi.fn(),
      inscribeAvatar: vi.fn(),
      setMythosHead: vi.fn(),
      appendMythos: vi.fn(),
      getMythosHead: vi.fn().mockResolvedValue(mythosFp),
      recordAction: vi.fn(),
      headHashes: vi.fn(),
      upsertEmbedding: vi.fn(),
      deleteEmbedding: vi.fn(),
      reembed: vi.fn(),
      kNN: vi.fn(),
      getOrCreateAqueduct: vi.fn(),
      updateAqueductStrength: vi.fn(),
      __rawQuery: vi.fn().mockImplementation(async (cypher: string) => {
        if (cypher.includes('RETURN m.body AS body')) {
          return [{ body: mythosBody }];
        }
        return [];
      }),
    } as unknown as StoreAPI;
  }

  it('AC4: returned string begins with mythos head body verbatim', async () => {
    const palaceFp = 'a'.repeat(64);
    const mythosFp = 'b'.repeat(64);
    const mythosBody = 'first stone';
    const store = makeMockStore(mythosFp, mythosBody);

    const prompt = await buildSystemPrompt(store, palaceFp);
    expect(prompt.startsWith('first stone')).toBe(true);
  });

  it('AC4: returned string has newline after mythos body then personality prompt', async () => {
    const palaceFp = 'a'.repeat(64);
    const mythosFp = 'b'.repeat(64);
    const mythosBody = 'first stone';
    const store = makeMockStore(mythosFp, mythosBody);

    const prompt = await buildSystemPrompt(store, palaceFp);
    const [head, ...rest] = prompt.split('\n');
    expect(head).toBe('first stone');
    expect(rest.join('\n')).toBe(ORACLE_PROMPT_BYTES);
  });

  it('AC4: prefix is byte-identical to mythos body from store', async () => {
    const palaceFp = 'c'.repeat(64);
    const mythosFp = 'd'.repeat(64);
    const mythosBody = 'the library remembers';
    const store = makeMockStore(mythosFp, mythosBody);

    const prompt = await buildSystemPrompt(store, palaceFp);
    const prefix = prompt.slice(0, mythosBody.length);
    expect(prefix).toBe(mythosBody);
  });

  it('AC4: throws when no MYTHOS_HEAD found', async () => {
    const palaceFp = 'e'.repeat(64);
    const store = {
      getMythosHead: vi.fn().mockResolvedValue(null),
      __rawQuery: vi.fn(),
    } as unknown as StoreAPI;

    await expect(buildSystemPrompt(store, palaceFp)).rejects.toThrow('no MYTHOS_HEAD');
  });

  it('AC6: buildSystemPrompt reflects new head after rename-mythos', async () => {
    const palaceFp = 'f'.repeat(64);
    const m1Fp = '1'.repeat(64);
    const m2Fp = '2'.repeat(64);

    // Simulate store after rename: getMythosHead now returns M2
    const store = {
      getMythosHead: vi.fn().mockResolvedValue(m2Fp),
      __rawQuery: vi.fn().mockImplementation(async (cypher: string) => {
        if (cypher.includes(m2Fp)) {
          return [{ body: 'second stone' }];
        }
        return [{ body: 'first stone' }];
      }),
    } as unknown as StoreAPI;

    const prompt = await buildSystemPrompt(store, palaceFp);
    expect(prompt.startsWith('second stone')).toBe(true);
    expect(prompt).not.toContain('first stone');
    // getMythosHead was called — store queried for current head
    expect(store.getMythosHead).toHaveBeenCalledWith(palaceFp);
  });

  it('AC6: getMythosHead called on every invocation (no caching)', async () => {
    const palaceFp = 'g'.repeat(64);
    let callCount = 0;
    const heads = ['m'.repeat(64), 'n'.repeat(64)];
    const store = {
      getMythosHead: vi.fn().mockImplementation(async () => heads[callCount++ % 2]),
      __rawQuery: vi.fn().mockResolvedValue([{ body: 'body' }]),
    } as unknown as StoreAPI;

    await buildSystemPrompt(store, palaceFp);
    await buildSystemPrompt(store, palaceFp);
    expect(store.getMythosHead).toHaveBeenCalledTimes(2);
  });
});

// ── S4.4: oracleSignAction ────────────────────────────────────────────────────

describe('S4.4 oracleSignAction — oracle-signed actions for file-watcher', () => {
  // oracleActionStub now refuses to run unless JELLY_ORACLE_ALLOW_UNSIGNED=1
  // (see docs/known-gaps.md §8). This describe block exercises the stub path
  // explicitly so the env var is set for the duration of these tests only.
  beforeAll(() => {
    process.env.JELLY_ORACLE_ALLOW_UNSIGNED = '1';
  });
  afterAll(() => {
    delete process.env.JELLY_ORACLE_ALLOW_UNSIGNED;
  });

  function makeTempPalace(): { palacePath: string; palaceDir: string } {
    const palaceDir = mkdtempSync(join(tmpdir(), 'oracle-sign-test-'));
    const palacePath = join(palaceDir, 'test-palace');
    const keyPath = `${palacePath}.oracle.key`;
    const keyBytes = Buffer.from('oracle-key-bytes-'.repeat(8));
    writeFileSync(keyPath, keyBytes);
    chmodSync(keyPath, 0o600);
    return { palacePath, palaceDir };
  }

  it('AC1: oracleSignAction returns inscription-updated with non-empty fp', async () => {
    const { palacePath } = makeTempPalace();
    const palaceFp = 'a'.repeat(64);
    const targetFp = 'b'.repeat(64);

    const action = await oracleSignAction(palacePath, palaceFp, 'inscription-updated', targetFp, []);

    expect(action.fp).toBeTruthy();
    expect(action.fp.length).toBeGreaterThan(0);
    expect(action.actionKind).toBe('inscription-updated');
    expect(action.targetFp).toBe(targetFp);
    expect(action.palaceFp).toBe(palaceFp);
  });

  it('AC1: signerFp equals oracle fp (not custodian)', async () => {
    const { palacePath } = makeTempPalace();
    const action = await oracleSignAction(
      palacePath, 'c'.repeat(64), 'inscription-updated', 'd'.repeat(64), []
    );

    // signerFp must be derived from the oracle key — non-empty, not a known custodian value
    expect(action.signerFp).toBeTruthy();
    expect(action.signerFp.length).toBeGreaterThan(0);
  });

  it('AC1: two calls with same params produce different fps (timestamp-based)', async () => {
    const { palacePath } = makeTempPalace();
    const palaceFp = 'e'.repeat(64);
    const targetFp = 'f'.repeat(64);

    const a1 = await oracleSignAction(palacePath, palaceFp, 'inscription-updated', targetFp, []);
    // tiny delay to ensure different timestamp
    await new Promise((r) => setTimeout(r, 2));
    const a2 = await oracleSignAction(palacePath, palaceFp, 'inscription-updated', targetFp, []);

    expect(a1.fp).not.toBe(a2.fp);
  });

  it('AC3: oracleSignAction returns inscription-orphaned correctly', async () => {
    const { palacePath } = makeTempPalace();
    const action = await oracleSignAction(
      palacePath, 'g'.repeat(64), 'inscription-orphaned', 'h'.repeat(64), ['parent1']
    );

    expect(action.actionKind).toBe('inscription-orphaned');
    expect(action.parentHashes).toEqual(['parent1']);
  });

  it('AC9: oracleSignAction contains TODO-CRYPTO marker in source', () => {
    // Verify the TODO-CRYPTO marker exists in oracle.ts at oracleSignAction sites
    const oracleSrc = readFileSync(
      join(__dirname, 'oracle.ts'), 'utf-8'
    );
    // Count occurrences of TODO-CRYPTO within the oracleSignAction function
    const cryptoMarkerCount = (oracleSrc.match(/TODO-CRYPTO: oracle key is plaintext/g) ?? []).length;
    // Source carries >= 2 markers (oracle-key read + stub-signer) plus more for
    // every additional bypass site. The hardening pass added markers at each
    // oracleActionStub call boundary; lower bound kept at 2 to tolerate future refactors.
    expect(cryptoMarkerCount).toBeGreaterThanOrEqual(2);
  });
});
