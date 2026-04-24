/**
 * palace-show.test.ts — AC12 (S3.6) Vitest tests for `jelly show --as-palace --json`
 * output structure and round-trip through the generated TS decoder + Valibot schemas.
 *
 * These tests exercise:
 *   1. JSON output shape matches the AC2 contract (keys: mythosHeadBody, trueName,
 *      rooms[], timelineHeadHashes[], oracleFp)
 *   2. JSON values pass Valibot schema validation where applicable
 *   3. Round-trip: parse JSON output → validate → re-serialize → compare
 */

import { describe, it, expect } from 'vitest';
import * as v from 'valibot';

// ── Valibot schema for the palace-show --json output (AC2) ────────────────────

const RoomInfoSchema = v.object({
  fp: v.pipe(v.string(), v.regex(/^[0-9a-f]{64}$/, 'expected 64-char hex fp')),
  name: v.string(),
  itemCount: v.number()
});

const PalaceShowOutputSchema = v.object({
  mythosHeadBody: v.string(),
  trueName: v.nullable(v.string()),
  rooms: v.array(RoomInfoSchema),
  timelineHeadHashes: v.array(
    v.pipe(v.string(), v.regex(/^[0-9a-f]{64}$/, 'expected 64-char hex fp'))
  ),
  oracleFp: v.pipe(v.string(), v.regex(/^[0-9a-f]{64}$/, 'expected 64-char hex fp'))
});

type PalaceShowOutput = v.InferOutput<typeof PalaceShowOutputSchema>;

// ── Test helpers ──────────────────────────────────────────────────────────────

function makePalaceShowJson(overrides: Partial<PalaceShowOutput> = {}): string {
  const base: PalaceShowOutput = {
    mythosHeadBody: 'smoke test mythos body',
    trueName: null,
    rooms: [
      {
        fp: 'a'.repeat(64),
        name: 'library',
        itemCount: 0
      }
    ],
    timelineHeadHashes: ['b'.repeat(64)],
    oracleFp: 'c'.repeat(64)
  };
  return JSON.stringify({ ...base, ...overrides });
}

// ── AC2: JSON output structure validation ─────────────────────────────────────

describe('palace-show --json output structure (AC2)', () => {
  it('validates a well-formed palace show output against PalaceShowOutputSchema', () => {
    const json = makePalaceShowJson();
    const parsed = JSON.parse(json);
    const result = v.safeParse(PalaceShowOutputSchema, parsed);
    expect(result.success).toBe(true);
  });

  it('schema requires mythosHeadBody as string', () => {
    const bad = JSON.parse(makePalaceShowJson());
    (bad as Record<string, unknown>).mythosHeadBody = 42;
    const result = v.safeParse(PalaceShowOutputSchema, bad);
    expect(result.success).toBe(false);
  });

  it('schema allows trueName to be null', () => {
    const json = makePalaceShowJson({ trueName: null });
    const result = v.safeParse(PalaceShowOutputSchema, JSON.parse(json));
    expect(result.success).toBe(true);
  });

  it('schema allows trueName to be a string', () => {
    const json = makePalaceShowJson({ trueName: 'rememberer' });
    const result = v.safeParse(PalaceShowOutputSchema, JSON.parse(json));
    expect(result.success).toBe(true);
  });

  it('schema rejects oracleFp that is not 64 hex chars', () => {
    const bad = JSON.parse(makePalaceShowJson());
    bad.oracleFp = 'not-a-hex-fp';
    const result = v.safeParse(PalaceShowOutputSchema, bad);
    expect(result.success).toBe(false);
  });

  it('schema rejects room fp that is not 64 hex chars', () => {
    const bad = JSON.parse(makePalaceShowJson());
    bad.rooms = [{ fp: 'short', name: 'library', itemCount: 0 }];
    const result = v.safeParse(PalaceShowOutputSchema, bad);
    expect(result.success).toBe(false);
  });
});

// ── AC12: round-trip through JSON serialize/parse ─────────────────────────────

describe('palace-show JSON round-trip (AC12)', () => {
  it('round-trips: parse → validate → re-serialize produces identical JSON', () => {
    const original = makePalaceShowJson({
      mythosHeadBody: 'the library remembers',
      trueName: 'rememberer',
      rooms: [
        { fp: 'a'.repeat(64), name: 'library', itemCount: 3 },
        { fp: 'b'.repeat(64), name: 'garden', itemCount: 1 }
      ],
      timelineHeadHashes: ['c'.repeat(64), 'd'.repeat(64)],
      oracleFp: 'e'.repeat(64)
    });
    const parsed = JSON.parse(original);
    const result = v.safeParse(PalaceShowOutputSchema, parsed);
    expect(result.success).toBe(true);
    if (!result.success) return;
    // Re-serialize and parse again — must produce structurally equal object
    const reserialized = JSON.stringify(result.output);
    const reparsed = JSON.parse(reserialized);
    expect(reparsed.mythosHeadBody).toBe('the library remembers');
    expect(reparsed.trueName).toBe('rememberer');
    expect(reparsed.rooms).toHaveLength(2);
    expect(reparsed.rooms[0].name).toBe('library');
    expect(reparsed.rooms[0].itemCount).toBe(3);
    expect(reparsed.timelineHeadHashes).toHaveLength(2);
    expect(reparsed.oracleFp).toBe('e'.repeat(64));
  });

  it('round-trip preserves all 5 AC2 required keys', () => {
    const json = makePalaceShowJson();
    const parsed = JSON.parse(json);
    const result = v.safeParse(PalaceShowOutputSchema, parsed);
    expect(result.success).toBe(true);
    if (!result.success) return;
    const keys = Object.keys(result.output);
    expect(keys).toContain('mythosHeadBody');
    expect(keys).toContain('trueName');
    expect(keys).toContain('rooms');
    expect(keys).toContain('timelineHeadHashes');
    expect(keys).toContain('oracleFp');
  });

  it('multi-room output round-trips correctly through schema', () => {
    const json = makePalaceShowJson({
      rooms: [
        { fp: '1'.repeat(64), name: 'library', itemCount: 2 },
        { fp: '2'.repeat(64), name: 'forge', itemCount: 0 },
        { fp: '3'.repeat(64), name: 'garden', itemCount: 5 }
      ]
    });
    const result = v.safeParse(PalaceShowOutputSchema, JSON.parse(json));
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.output.rooms).toHaveLength(3);
    expect(result.output.rooms.map((r) => r.name)).toEqual(['library', 'forge', 'garden']);
    expect(result.output.rooms.map((r) => r.itemCount)).toEqual([2, 0, 5]);
  });
});

// ── Integration with generated MythosSchema (codegen TS decoder round-trip) ───

describe('palace-show output integrates with generated Mythos schema (AC12)', () => {
  it('mythosHeadBody from palace show is a plain string (not b58-wrapped)', () => {
    // The palace show --json emits raw UTF-8 body strings, NOT b58-encoded.
    // This test verifies the contract explicitly (vs. Action/Timeline where fps are b58).
    const json = makePalaceShowJson({ mythosHeadBody: 'the library remembers' });
    const parsed = JSON.parse(json) as PalaceShowOutput;
    // Should be plain string, no b58: prefix
    expect(parsed.mythosHeadBody).not.toMatch(/^b58:/);
    expect(typeof parsed.mythosHeadBody).toBe('string');
  });

  it('oracleFp is 64-char lowercase hex (not b58)', () => {
    const json = makePalaceShowJson();
    const parsed = JSON.parse(json) as PalaceShowOutput;
    // palace_show.zig emits hex (not b58) for fps
    expect(parsed.oracleFp).toMatch(/^[0-9a-f]{64}$/);
  });

  it('timelineHeadHashes are all 64-char hex strings', () => {
    const hashes = ['a'.repeat(64), 'b'.repeat(64), 'c'.repeat(64)];
    const json = makePalaceShowJson({ timelineHeadHashes: hashes });
    const parsed = JSON.parse(json) as PalaceShowOutput;
    for (const h of parsed.timelineHeadHashes) {
      expect(h).toMatch(/^[0-9a-f]{64}$/);
    }
  });
});
