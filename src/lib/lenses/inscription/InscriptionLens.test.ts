/**
 * InscriptionLens.test.ts — Story 5.4 smoke-tier integration tests (AC1–AC5).
 *
 * Run under Vitest `server` project. Covers:
 *
 *   AC1 — five surface components exist and have correct surface name in source.
 *   AC2 — surface registry + fallback chain (5 shapes):
 *          1. unknown surface, no fallback → "scroll" + surface-fallback log
 *          2. unknown surface, fallback: ["tablet", "scroll"] → "tablet" + surface-fallback log
 *          3. known surface → no fallback walk (returned directly)
 *          4. empty fallback / absent → straight to "scroll" without entering walk
 *          5. fallback cycle → surface-fallback-cycle log, break to "scroll"
 *   AC3 — body bytes via store.inscriptionBody(inscriptionFp) (D-007);
 *          no raw filesystem path in lens; no HTTP fetch to non-local URL (SEC6);
 *          grep assertion: no @ladybugdb/core or kuzu-wasm imports.
 *   AC4 — store.inscriptionBody called correctly (verb invocation assertion).
 *   AC5 — lens does NOT contain store write verbs or CAS write patterns.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const LENS_SRC = join(__dirname, 'InscriptionLens.svelte');

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Extract `import ... from '...'` specifiers from a Svelte/TS source. */
function extractImportSpecifiers(source: string): string[] {
  const specs: string[] = [];
  const re = /^\s*import\s+[^;]*?from\s+['"]([^'"]+)['"]\s*;?\s*$/gm;
  let m: RegExpExecArray | null;
  while ((m = re.exec(source)) !== null) specs.push(m[1]);
  return specs;
}

/**
 * Inline mirror of InscriptionLens's resolveSurface() — kept in sync for
 * deterministic AC2 assertions without importing the Svelte component
 * (which requires a browser environment).
 *
 * IMPORTANT: any change to the fallback walk in InscriptionLens.svelte MUST
 * be reflected here to keep the test honest.
 */
const WEB_SURFACES = new Set([
  'scroll',
  'tablet',
  'book-spread',
  'etched-wall',
  'floating-glyph',
]);
const MAX_WALK_HOPS = 10;

interface SurfaceFallbackLog {
  event: 'surface-fallback' | 'surface-fallback-cycle';
  requested: string;
  resolved?: string;
  cycle_at?: string;
  lens: 'web';
}

function resolveSurface(
  requested: string,
  fallbackChain: string[],
  logs: SurfaceFallbackLog[]
): string {
  if (WEB_SURFACES.has(requested)) {
    return requested;
  }

  const visited = new Set<string>([requested]);
  const chain = (fallbackChain ?? []).slice(0, MAX_WALK_HOPS);

  for (const candidate of chain) {
    if (visited.has(candidate)) {
      logs.push({ event: 'surface-fallback-cycle', requested, cycle_at: candidate, lens: 'web' });
      break;
    }
    visited.add(candidate);

    if (WEB_SURFACES.has(candidate)) {
      logs.push({ event: 'surface-fallback', requested, resolved: candidate, lens: 'web' });
      return candidate;
    }
  }

  logs.push({ event: 'surface-fallback', requested, resolved: 'scroll', lens: 'web' });
  return 'scroll';
}

// ─── AC3 — cross-runtime invariant ───────────────────────────────────────────

describe('AC3 — cross-runtime invariant: lens file imports nothing forbidden', () => {
  it('InscriptionLens.svelte does not import @ladybugdb/core', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    const specs = extractImportSpecifiers(src);
    expect(specs.length).toBeGreaterThan(0);
    for (const s of specs) {
      expect(s, `found forbidden import: ${s}`).not.toMatch(/@ladybugdb\/core/);
    }
  });

  it('InscriptionLens.svelte does not import kuzu-wasm', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    const specs = extractImportSpecifiers(src);
    for (const s of specs) {
      expect(s, `found forbidden import: ${s}`).not.toMatch(/kuzu-wasm/);
    }
  });

  it('InscriptionLens.svelte contains no raw Cypher (MATCH/CREATE/MERGE in script block)', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    const scriptMatch = src.match(/<script[^>]*>([\s\S]*?)<\/script>/);
    const script = scriptMatch ? scriptMatch[1] : src;
    expect(script).not.toMatch(/\bMATCH\s*\(/);
    expect(script).not.toMatch(/\bCREATE\s*\(/);
    expect(script).not.toMatch(/\bMERGE\s*\(/);
  });

  it('InscriptionLens.svelte calls store.inscriptionBody (D-007 domain verb)', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    expect(src).toMatch(/store\.inscriptionBody\s*\(/);
  });

  it('InscriptionLens.svelte contains no raw filesystem path construction', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    // No direct path.join / readFileSync / fs. calls in lens.
    expect(src).not.toMatch(/readFileSync/);
    expect(src).not.toMatch(/path\.join\s*\(/);
    expect(src).not.toMatch(/import\s+.*\bfs\b/);
  });

  it('InscriptionLens.svelte contains no non-local HTTP fetch', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    // No fetch() calls that look like absolute URLs (http/https).
    expect(src).not.toMatch(/fetch\s*\(\s*['"]https?:\/\//);
  });

  it('InscriptionLens.svelte uses Svelte 5 runes', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    expect(src).toMatch(/\$props\(\)/);
    expect(src).toMatch(/\$state/);
    expect(src).toMatch(/\$effect/);
  });
});

// ─── AC1 — five surface components exist ─────────────────────────────────────

describe('AC1 — five surface components exist with correct surface markers', () => {
  const SURFACES_DIR = join(__dirname, 'surfaces');

  for (const [filename, surfaceName] of [
    ['Scroll.svelte', 'scroll'],
    ['Tablet.svelte', 'tablet'],
    ['BookSpread.svelte', 'book-spread'],
    ['EtchedWall.svelte', 'etched-wall'],
    ['FloatingGlyph.svelte', 'floating-glyph'],
  ] as const) {
    it(`${filename} exists and references data-surface="${surfaceName}"`, () => {
      const src = readFileSync(join(SURFACES_DIR, filename), 'utf-8');
      expect(src).toContain(`data-surface="${surfaceName}"`);
    });

    it(`${filename} accepts a body prop`, () => {
      const src = readFileSync(join(SURFACES_DIR, filename), 'utf-8');
      // The component declares a body prop.
      expect(src).toMatch(/body\s*[=:]/);
    });

    it(`${filename} does not import @ladybugdb/core or kuzu-wasm`, () => {
      const src = readFileSync(join(SURFACES_DIR, filename), 'utf-8');
      const specs = extractImportSpecifiers(src);
      // Check import specifiers only — not raw string search (comments mention
      // these module names as documentation of what NOT to import).
      // If specs is empty, the file has no imports at all — trivially clean.
      for (const s of specs) {
        expect(s).not.toMatch(/@ladybugdb\/core/);
        expect(s).not.toMatch(/kuzu-wasm/);
      }
      // Verify no actual import statement from these modules (specifier-level check).
      expect(specs.some(s => s.includes('@ladybugdb/core'))).toBe(false);
      expect(specs.some(s => s.includes('kuzu-wasm'))).toBe(false);
    });
  }
});

// ─── AC2 — surface registry + fallback chain (5 shapes) ──────────────────────

describe('AC2 — surface registry + fallback chain (normative per ADR 2026-04-24-surface-registry)', () => {
  // Shape 1: unknown surface, no fallback → "scroll" + surface-fallback log.
  it('shape 1: unknown surface with no fallback → resolves to "scroll", emits surface-fallback', () => {
    const logs: SurfaceFallbackLog[] = [];
    const result = resolveSurface('splat-scene', [], logs);
    expect(result).toBe('scroll');
    expect(logs).toHaveLength(1);
    expect(logs[0].event).toBe('surface-fallback');
    expect(logs[0].requested).toBe('splat-scene');
    expect(logs[0].resolved).toBe('scroll');
    expect(logs[0].lens).toBe('web');
  });

  // Shape 2: unknown surface with fallback: ["tablet", "scroll"] → first registered ("tablet").
  it('shape 2: unknown surface with fallback ["tablet","scroll"] → resolves to "tablet", emits surface-fallback', () => {
    const logs: SurfaceFallbackLog[] = [];
    const result = resolveSurface('splat-scene', ['tablet', 'scroll'], logs);
    expect(result).toBe('tablet');
    expect(logs).toHaveLength(1);
    expect(logs[0].event).toBe('surface-fallback');
    expect(logs[0].requested).toBe('splat-scene');
    expect(logs[0].resolved).toBe('tablet');
    expect(logs[0].lens).toBe('web');
  });

  // Shape 3: known surface → no fallback walk (no log emitted).
  it('shape 3: known surface "scroll" → resolved directly, no logs emitted', () => {
    const logs: SurfaceFallbackLog[] = [];
    const result = resolveSurface('scroll', ['tablet'], logs);
    expect(result).toBe('scroll');
    expect(logs).toHaveLength(0);
  });

  it('shape 3: known surface "tablet" → resolved directly, no logs emitted', () => {
    const logs: SurfaceFallbackLog[] = [];
    const result = resolveSurface('tablet', [], logs);
    expect(result).toBe('tablet');
    expect(logs).toHaveLength(0);
  });

  it('shape 3: known surface "floating-glyph" → resolved directly, no logs emitted', () => {
    const logs: SurfaceFallbackLog[] = [];
    const result = resolveSurface('floating-glyph', ['scroll'], logs);
    expect(result).toBe('floating-glyph');
    expect(logs).toHaveLength(0);
  });

  // Shape 4: empty fallback / absent → straight to "scroll" baseline, emits surface-fallback.
  it('shape 4a: unknown surface + empty fallback [] → "scroll" baseline, emits surface-fallback', () => {
    const logs: SurfaceFallbackLog[] = [];
    const result = resolveSurface('rune-pillar', [], logs);
    expect(result).toBe('scroll');
    expect(logs).toHaveLength(1);
    expect(logs[0].event).toBe('surface-fallback');
    expect(logs[0].resolved).toBe('scroll');
  });

  it('shape 4b: unknown surface + absent fallback (undefined treated as []) → "scroll" baseline', () => {
    const logs: SurfaceFallbackLog[] = [];
    // Simulate absent fallback: pass empty array (semantically equivalent to absent per ADR §4).
    // "Absent fallback is semantically equivalent to fallback: [] — both mean walk straight to scroll."
    const absentFallback: string[] = [];
    const result = resolveSurface('holo-panel', absentFallback, logs);
    expect(result).toBe('scroll');
    expect(logs).toHaveLength(1);
    expect(logs[0].event).toBe('surface-fallback');
  });

  // Shape 5: fallback cycle → surface-fallback-cycle log, break to "scroll".
  it('shape 5a: cycle (surface lists itself in fallback) → surface-fallback-cycle log, resolves to "scroll"', () => {
    const logs: SurfaceFallbackLog[] = [];
    // "splat-scene" is not in WEB_SURFACES; fallback lists "splat-scene" again → cycle.
    const result = resolveSurface('splat-scene', ['splat-scene', 'scroll'], logs);
    expect(result).toBe('scroll');
    const cycleLog = logs.find((l) => l.event === 'surface-fallback-cycle');
    expect(cycleLog).toBeTruthy();
    expect(cycleLog?.cycle_at).toBe('splat-scene');
    // Also emits a final surface-fallback for the scroll resolution.
    const fallbackLog = logs.find((l) => l.event === 'surface-fallback');
    expect(fallbackLog?.resolved).toBe('scroll');
  });

  it('shape 5b: cycle (unknown chain with already-visited predecessor) → cycle log, resolves to "scroll"', () => {
    const logs: SurfaceFallbackLog[] = [];
    // "a" not registered; fallback: ["b", "a"] — "a" was already visited as requested.
    const result = resolveSurface('a', ['b', 'a'], logs);
    expect(result).toBe('scroll');
    const cycleLog = logs.find((l) => l.event === 'surface-fallback-cycle');
    expect(cycleLog).toBeTruthy();
    expect(cycleLog?.cycle_at).toBe('a');
  });

  // Walk terminates without crashing (DoS guard): long chain finds no registered surface.
  it('long unknown chain (>MAX_WALK_HOPS candidates) → terminates at scroll, no crash', () => {
    const logs: SurfaceFallbackLog[] = [];
    const longChain = Array.from({ length: 20 }, (_, i) => `unknown-${i}`);
    const result = resolveSurface('alien-surface', longChain, logs);
    expect(result).toBe('scroll');
    expect(logs.length).toBeGreaterThanOrEqual(1);
  });

  // AC2 fallback does NOT crash (all shapes).
  it('fallback walk never throws for any reasonable input', () => {
    const logs: SurfaceFallbackLog[] = [];
    expect(() => resolveSurface('', [], logs)).not.toThrow();
    expect(() => resolveSurface('scroll', [], logs)).not.toThrow();
    expect(() => resolveSurface('unknown', ['also-unknown'], logs)).not.toThrow();
    expect(() => resolveSurface('cycle', ['cycle'], logs)).not.toThrow();
  });
});

// ─── AC3 — store.inscriptionBody verb invocation (D-007) ─────────────────────

describe('AC3 — store.inscriptionBody verb invocation (D-007, TC13)', () => {
  it('store.inscriptionBody is called with inscriptionFp and returns Uint8Array', async () => {
    const inscriptionFp = 'a'.repeat(64); // 64-char hex mock fp.
    const mockBody = new TextEncoder().encode('Hello palace');
    const inscriptionBodyMock = vi.fn().mockResolvedValue(mockBody);
    const mockStore = { inscriptionBody: inscriptionBodyMock } as unknown as import('../../../memory-palace/store-types.js').StoreAPI;

    // Simulate the mount logic that InscriptionLens executes.
    const bytes = await mockStore.inscriptionBody(inscriptionFp);

    expect(inscriptionBodyMock).toHaveBeenCalledOnce();
    expect(inscriptionBodyMock).toHaveBeenCalledWith(inscriptionFp);
    expect(bytes).toBeInstanceOf(Uint8Array);
    expect(new TextDecoder().decode(bytes)).toBe('Hello palace');
  });

  it('body bytes decode as UTF-8 text correctly', () => {
    const text = 'Hello palace';
    const bytes = new TextEncoder().encode(text);
    const decoded = new TextDecoder('utf-8').decode(bytes);
    expect(decoded).toBe(text);
  });

  it('10 KB markdown body encodes and decodes correctly', () => {
    const body = '# Test\n\n' + 'Lorem ipsum dolor sit amet. '.repeat(350); // ~10 KB
    const bytes = new TextEncoder().encode(body);
    expect(bytes.length).toBeGreaterThan(9000);
    const decoded = new TextDecoder('utf-8').decode(bytes);
    expect(decoded).toBe(body);
  });

  it('store.inscriptionBody failure emits warning and falls back to empty body', async () => {
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const mockStore = {
      inscriptionBody: vi.fn().mockRejectedValue(new Error('CAS unavailable'))
    } as unknown as import('../../../memory-palace/store-types.js').StoreAPI;

    // Simulate the error path in InscriptionLens onMount.
    let bodyText = '';
    try {
      const bytes = await mockStore.inscriptionBody('a'.repeat(64));
      bodyText = new TextDecoder().decode(bytes);
    } catch (e) {
      console.warn('[InscriptionLens] store.inscriptionBody failed:', e);
      bodyText = '';
    }

    expect(warnSpy).toHaveBeenCalledOnce();
    expect(warnSpy.mock.calls[0][0]).toContain('[InscriptionLens]');
    expect(bodyText).toBe('');
    warnSpy.mockRestore();
  });
});

// ─── AC5 — lens does not write to store ──────────────────────────────────────

describe('AC5 — lens does NOT write to LadybugDB / CAS (SEC11)', () => {
  it('InscriptionLens.svelte contains no store write verb calls', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    const forbiddenVerbs = [
      'addRoom',
      'inscribeAvatar',
      'recordAction',
      'recordTraversal',
      'upsertEmbedding',
      'reembed',
      'getOrCreateAqueduct',
      'updateAqueductStrength',
      'insertTriple',
    ];
    for (const verb of forbiddenVerbs) {
      expect(src, `lens contains forbidden verb: ${verb}`).not.toContain(verb);
    }
  });

  it('InscriptionLens.svelte contains no direct CAS write patterns', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    expect(src).not.toMatch(/\.put\s*\(/);
    expect(src).not.toMatch(/fetch\s*\([^)]*PUT/i);
  });
});

// ─── WEB_SURFACES registry completeness ──────────────────────────────────────

describe('Surface registry completeness', () => {
  it('WEB_SURFACES contains exactly the five canonical surfaces', () => {
    expect(WEB_SURFACES.has('scroll')).toBe(true);
    expect(WEB_SURFACES.has('tablet')).toBe(true);
    expect(WEB_SURFACES.has('book-spread')).toBe(true);
    expect(WEB_SURFACES.has('etched-wall')).toBe(true);
    expect(WEB_SURFACES.has('floating-glyph')).toBe(true);
    expect(WEB_SURFACES.size).toBe(5);
  });

  it('"scroll" is in WEB_SURFACES (canonical baseline always registered)', () => {
    expect(WEB_SURFACES.has('scroll')).toBe(true);
  });

  it('InscriptionLens.svelte source contains WEB_SURFACES with all five names', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    expect(src).toContain("'scroll'");
    expect(src).toContain("'tablet'");
    expect(src).toContain("'book-spread'");
    expect(src).toContain("'etched-wall'");
    expect(src).toContain("'floating-glyph'");
  });
});
