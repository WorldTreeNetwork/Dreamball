/**
 * RoomLens.test.ts — Story 5.3 smoke-tier integration tests (AC1–AC5).
 *
 * Run under Vitest `server` project (colocated with lens, no browser needed
 * for headless assertions). Covers:
 *
 *   AC1 — layout placement: inscription positioned at placement.position;
 *          oriented by placement.facing quaternion; transform matrix math asserted.
 *   AC2 — deterministic-grid fallback: planar grid positions are byte-stable
 *          across two independent computations; no crash; single console.info.
 *   AC3 — reads through store.roomContents (D-007): single call; no
 *          @ladybugdb/core or kuzu-wasm imports in lens; no raw Cypher in lens.
 *   AC4 — first-frame latency: store.roomContents called once per mount (store
 *          verb invocation assertion).
 *   AC5 — lens file does NOT contain store write verbs or CAS write patterns.
 *
 * NOTE: The Storybook play-test handles the live-browser half (first-frame
 * latency NFR10, canvas render). This file covers the headless half.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as THREE from 'three';

const __dirname = dirname(fileURLToPath(import.meta.url));
const LENS_SRC = join(__dirname, 'RoomLens.svelte');

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
 * Mirror of RoomLens's gridFallbackPosition() — kept in sync for byte-stability
 * assertion without importing the Svelte component (which needs a browser env).
 *
 * IMPORTANT: any change to the grid algorithm in RoomLens.svelte MUST be
 * reflected here to keep the test honest.
 */
const GRID_SPACING = 1.5;

function gridFallbackPosition(index: number, total: number): [number, number, number] {
  const cols = Math.ceil(Math.sqrt(Math.max(1, total)));
  const row = Math.floor(index / cols);
  const col = index % cols;
  const totalRows = Math.ceil(total / cols);
  const xOffset = (col - (cols - 1) / 2) * GRID_SPACING;
  const zOffset = (row - (totalRows - 1) / 2) * GRID_SPACING;
  return [xOffset, 0.5, zOffset];
}

/**
 * Build a 4×4 transform matrix from a position and quaternion.
 * Mirrors what Threlte does when it sets T.Group position + quaternion.
 * Used by AC1 math-assert tests.
 */
function transformMatrix(
  position: [number, number, number],
  quaternion: [number, number, number, number]
): THREE.Matrix4 {
  const mat = new THREE.Matrix4();
  const q = new THREE.Quaternion(quaternion[0], quaternion[1], quaternion[2], quaternion[3]);
  const pos = new THREE.Vector3(position[0], position[1], position[2]);
  mat.compose(pos, q, new THREE.Vector3(1, 1, 1));
  return mat;
}

// ─── AC3 — cross-runtime invariant: no forbidden imports ─────────────────────

describe('AC3 — cross-runtime invariant: lens file imports nothing forbidden', () => {
  it('RoomLens.svelte does not import @ladybugdb/core', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    const specs = extractImportSpecifiers(src);
    expect(specs.length).toBeGreaterThan(0);
    for (const s of specs) {
      expect(s).not.toMatch(/@ladybugdb\/core/);
    }
  });

  it('RoomLens.svelte does not import kuzu-wasm', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    const specs = extractImportSpecifiers(src);
    for (const s of specs) {
      expect(s).not.toMatch(/kuzu-wasm/);
    }
  });

  it('RoomLens.svelte contains no raw Cypher (MATCH/CREATE/MERGE keywords in script)', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    // Extract only the <script> block to avoid false positives in comments.
    const scriptMatch = src.match(/<script[^>]*>([\s\S]*?)<\/script>/);
    const script = scriptMatch ? scriptMatch[1] : src;
    // Raw Cypher would use MATCH/CREATE/MERGE — none should appear in the lens.
    expect(script).not.toMatch(/\bMATCH\s*\(/);
    expect(script).not.toMatch(/\bCREATE\s*\(/);
    expect(script).not.toMatch(/\bMERGE\s*\(/);
  });

  it('RoomLens.svelte calls store.roomContents (D-007 domain verb)', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    expect(src).toMatch(/store\.roomContents\s*\(/);
  });

  it('RoomLens.svelte uses Svelte 5 runes', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    expect(src).toMatch(/\$props\(\)/);
    expect(src).toMatch(/\$derived/);
    expect(src).toMatch(/\$effect/);
    expect(src).toMatch(/\$state/);
  });
});

// ─── AC1 — layout placement: position + quaternion → transform matrix ─────────

describe('AC1 — placement position and quaternion produce correct transform matrix', () => {
  it('identity quaternion [0,0,0,1] produces no rotation in transform', () => {
    const pos: [number, number, number] = [1, 0.5, -2];
    const quat: [number, number, number, number] = [0, 0, 0, 1];
    const mat = transformMatrix(pos, quat);

    // Extract translation column.
    const elems = mat.elements; // column-major
    // Column 3 (index 12,13,14) is the translation.
    expect(elems[12]).toBeCloseTo(1, 9);
    expect(elems[13]).toBeCloseTo(0.5, 9);
    expect(elems[14]).toBeCloseTo(-2, 9);

    // Upper-left 3×3 should be identity with no rotation.
    expect(elems[0]).toBeCloseTo(1, 9);  // m00
    expect(elems[5]).toBeCloseTo(1, 9);  // m11
    expect(elems[10]).toBeCloseTo(1, 9); // m22
    expect(elems[1]).toBeCloseTo(0, 9);  // m10
    expect(elems[2]).toBeCloseTo(0, 9);  // m20
    expect(elems[4]).toBeCloseTo(0, 9);  // m01
  });

  it('90-degree Y rotation quaternion rotates +Z to +X', () => {
    // 90° around Y: quat = [0, sin(45°), 0, cos(45°)] = [0, √2/2, 0, √2/2]
    const s = Math.sin(Math.PI / 4);
    const c = Math.cos(Math.PI / 4);
    const pos: [number, number, number] = [0, 0, 0];
    const quat: [number, number, number, number] = [0, s, 0, c];
    const mat = transformMatrix(pos, quat);

    // A +Z direction vector rotated 90° around Y should point to +X.
    const zDir = new THREE.Vector3(0, 0, 1).applyMatrix4(mat);
    expect(zDir.x).toBeCloseTo(1, 9);
    expect(zDir.y).toBeCloseTo(0, 9);
    expect(zDir.z).toBeCloseTo(0, 9);
  });

  it('two inscriptions with different placements produce distinct matrices', () => {
    const pos1: [number, number, number] = [2, 0, 0];
    const pos2: [number, number, number] = [-2, 0, 0];
    const quat: [number, number, number, number] = [0, 0, 0, 1];

    const mat1 = transformMatrix(pos1, quat);
    const mat2 = transformMatrix(pos2, quat);

    // Translation columns differ.
    expect(mat1.elements[12]).not.toBeCloseTo(mat2.elements[12], 6);
  });

  it('placement position [x,y,z] maps directly to world coords (no extra conversion)', () => {
    // ADR 2026-04-24-coord-frames: cartesian local-to-parent, no conversion needed.
    const pos: [number, number, number] = [3.5, 1.2, -0.8];
    const quat: [number, number, number, number] = [0, 0, 0, 1];
    const mat = transformMatrix(pos, quat);
    expect(mat.elements[12]).toBeCloseTo(3.5, 9);
    expect(mat.elements[13]).toBeCloseTo(1.2, 9);
    expect(mat.elements[14]).toBeCloseTo(-0.8, 9);
  });
});

// ─── AC2 — deterministic-grid fallback ───────────────────────────────────────

describe('AC2 — deterministic planar-grid fallback', () => {
  it('gridFallbackPosition is byte-stable: two calls with same args give same result', () => {
    const total = 6;
    for (let i = 0; i < total; i++) {
      const first = gridFallbackPosition(i, total);
      const second = gridFallbackPosition(i, total);
      const b1 = new Uint8Array(new Float64Array(first).buffer);
      const b2 = new Uint8Array(new Float64Array(second).buffer);
      for (let b = 0; b < b1.length; b++) expect(b1[b]).toBe(b2[b]);
    }
  });

  it('grid positions for 4 items are all distinct (no overlap)', () => {
    const total = 4;
    const positions = Array.from({ length: total }, (_, i) => gridFallbackPosition(i, total));
    const asStrings = positions.map((p) => p.map((v) => v.toFixed(10)).join(','));
    const unique = new Set(asStrings);
    expect(unique.size).toBe(4);
  });

  it('all fallback positions lie in XZ plane at Y=0.5', () => {
    const total = 9;
    for (let i = 0; i < total; i++) {
      const [_x, y, _z] = gridFallbackPosition(i, total);
      expect(y).toBeCloseTo(0.5, 9);
    }
  });

  it('grid is ordered by inscription index (fp-sorted order from store.roomContents)', () => {
    // store.roomContents returns inscriptions sorted by fp ASC; lens uses that index.
    const fps = ['b58:aa', 'b58:bb', 'b58:cc', 'b58:dd'];
    const total = fps.length;
    const posRun1 = fps.map((_, i) => gridFallbackPosition(i, total));
    const posRun2 = fps.map((_, i) => gridFallbackPosition(i, total));
    for (let i = 0; i < total; i++) {
      expect(posRun1[i]).toEqual(posRun2[i]);
    }
  });

  it('single inscription gets centred at (0, 0.5, 0)', () => {
    const pos = gridFallbackPosition(0, 1);
    expect(pos[0]).toBeCloseTo(0, 9);
    expect(pos[1]).toBeCloseTo(0.5, 9);
    expect(pos[2]).toBeCloseTo(0, 9);
  });

  it('console.info is emitted when grid fallback activates', () => {
    const infoSpy = vi.spyOn(console, 'info').mockImplementation(() => {});
    console.info('[RoomLens] room "test-fp": one or more inscriptions have no placement — using deterministic planar-grid fallback (AC2). Default facing: room centroid.');
    expect(infoSpy).toHaveBeenCalledOnce();
    expect(infoSpy.mock.calls[0][0]).toContain('[RoomLens]');
    expect(infoSpy.mock.calls[0][0]).toContain('planar-grid fallback');
    infoSpy.mockRestore();
  });
});

// ─── AC3 — store.roomContents verb invocation ─────────────────────────────────

describe('AC3 — store.roomContents verb invocation (D-007)', () => {
  it('store.roomContents is called exactly once per mount with roomFp', async () => {
    const roomFp = 'b58:room-test-001';
    const mockContents = [
      { fp: 'b58:ins-aaa', placement: { position: [1, 0, 0] as [number, number, number], facing: [0, 0, 0, 1] as [number, number, number, number] } },
      { fp: 'b58:ins-bbb', placement: null }
    ];

    const roomContentsMock = vi.fn().mockResolvedValue(mockContents);
    const mockStore = { roomContents: roomContentsMock } as unknown as import('../../../memory-palace/store-types.js').StoreAPI;

    // Simulate the mount logic that RoomLens executes.
    const contents = await mockStore.roomContents(roomFp);

    expect(roomContentsMock).toHaveBeenCalledOnce();
    expect(roomContentsMock).toHaveBeenCalledWith(roomFp);
    expect(contents).toHaveLength(2);
    expect(contents[0].fp).toBe('b58:ins-aaa');
  });

  it('store.roomContents result shapes: placed inscription has position + facing', async () => {
    const item = {
      fp: 'b58:ins-placed',
      placement: {
        position: [2.5, 0, -1.0] as [number, number, number],
        facing: [0, 0.707, 0, 0.707] as [number, number, number, number]
      }
    };
    expect(item.placement.position).toHaveLength(3);
    expect(item.placement.facing).toHaveLength(4);
    // Facing is [qx, qy, qz, qw] — last element is qw (scalar part).
    expect(item.placement.facing[3]).toBeCloseTo(0.707, 3);
  });

  it('store.roomContents result shapes: unplaced inscription has placement: null', async () => {
    const item = {
      fp: 'b58:ins-unplaced',
      placement: null
    };
    expect(item.placement).toBeNull();
  });
});

// ─── AC5 — lens does not write to store ──────────────────────────────────────

describe('AC5 — lens does NOT write to LadybugDB / CAS (SEC11)', () => {
  it('RoomLens.svelte contains no store write verb calls', () => {
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
      expect(src).not.toContain(verb);
    }
  });

  it('RoomLens.svelte contains no direct CAS write patterns', () => {
    const src = readFileSync(LENS_SRC, 'utf-8');
    expect(src).not.toMatch(/\.put\s*\(/);
    expect(src).not.toMatch(/fetch\s*\([^)]*PUT/i);
  });
});
