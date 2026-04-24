/**
 * schema.test.ts — Pure-parse checks for schema.cypher (S2.4 AC1 + AC2)
 *
 * AC1: node-table set is exactly {Palace, Room, Inscription, Agent, Mythos, Aqueduct, ActionLog}
 *      Inscription.embedding FLOAT[256]; ActionLog.parent_hashes STRING[];
 *      no Action node label exists.
 * AC2: rel-table set is exactly {CONTAINS, MYTHOS_HEAD, PREDECESSOR, LIVES_IN,
 *                                AQUEDUCT_FROM, AQUEDUCT_TO, KNOWS}
 *      DISCOVERED_IN appears only as Mythos.discovered_in_action_fp STRING property,
 *      NOT as a relationship.
 *
 * Also checks RC1 (Inscription.orphaned), RC3 (Inscription.source_blake3 not body_hash).
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const schemaPath = join(import.meta.dirname, 'schema.cypher');
const raw = readFileSync(schemaPath, 'utf-8');

// Strip comments and split into non-empty statements
const statements = raw
  .split('\n')
  .filter((line) => !line.trimStart().startsWith('--'))
  .join('\n')
  .split(';')
  .map((s) => s.trim())
  .filter((s) => s.length > 0);

// Extract CREATE NODE TABLE names
const nodeTableNames = statements
  .map((s) => s.match(/CREATE\s+NODE\s+TABLE\s+(\w+)/i)?.[1])
  .filter(Boolean) as string[];

// Extract CREATE REL TABLE names
const relTableNames = statements
  .map((s) => s.match(/CREATE\s+REL\s+TABLE\s+(\w+)/i)?.[1])
  .filter(Boolean) as string[];

// ── AC1: Node table set ───────────────────────────────────────────────────────

describe('AC1 — schema.cypher node-table completeness', () => {
  const EXPECTED_NODES = new Set([
    'Palace', 'Room', 'Inscription', 'Agent', 'Mythos', 'Aqueduct', 'ActionLog', 'Triple'
  ]);

  it('has exactly the 8 required node tables', () => {
    expect(new Set(nodeTableNames)).toEqual(EXPECTED_NODES);
  });

  it('Triple table exists for native KG storage (2026-04-24 ADR)', () => {
    const tStmt = statements.find((s) =>
      /CREATE\s+NODE\s+TABLE\s+Triple/i.test(s)
    );
    expect(tStmt).toBeTruthy();
    expect(tStmt).toMatch(/agent_fp\s+STRING/i);
    expect(tStmt).toMatch(/subject\s+STRING/i);
    expect(tStmt).toMatch(/predicate\s+STRING/i);
    expect(tStmt).toMatch(/object\s+STRING/i);
  });

  it('Agent node no longer declares knowledge_graph column', () => {
    const aStmt = statements.find((s) =>
      /CREATE\s+NODE\s+TABLE\s+Agent/i.test(s)
    );
    expect(aStmt).toBeTruthy();
    expect(aStmt).not.toMatch(/knowledge_graph/i);
  });

  it('Inscription includes policy STRING DEFAULT public and revision INT64 columns', () => {
    const iStmt = statements.find((s) =>
      /CREATE\s+NODE\s+TABLE\s+Inscription/i.test(s)
    );
    expect(iStmt).toMatch(/policy\s+STRING\s+DEFAULT\s+'public'/i);
    expect(iStmt).toMatch(/revision\s+INT64/i);
  });

  it('has no Action node label (only ActionLog)', () => {
    expect(nodeTableNames).not.toContain('Action');
    expect(nodeTableNames).toContain('ActionLog');
  });

  it('Inscription has embedding FLOAT[256] column', () => {
    const inscStmt = statements.find((s) =>
      /CREATE\s+NODE\s+TABLE\s+Inscription/i.test(s)
    );
    expect(inscStmt).toBeTruthy();
    expect(inscStmt).toMatch(/embedding\s+FLOAT\[256\]/i);
  });

  it('Inscription has orphaned BOOL column (RC1 — S4.4 file-watcher)', () => {
    const inscStmt = statements.find((s) =>
      /CREATE\s+NODE\s+TABLE\s+Inscription/i.test(s)
    );
    expect(inscStmt).toMatch(/orphaned\s+BOOL/i);
  });

  it('Inscription has source_blake3 STRING column (RC3 — not body_hash)', () => {
    const inscStmt = statements.find((s) =>
      /CREATE\s+NODE\s+TABLE\s+Inscription/i.test(s)
    );
    expect(inscStmt).toMatch(/source_blake3\s+STRING/i);
    expect(inscStmt).not.toMatch(/body_hash/i);
  });

  it('ActionLog has parent_hashes STRING[] column', () => {
    const alStmt = statements.find((s) =>
      /CREATE\s+NODE\s+TABLE\s+ActionLog/i.test(s)
    );
    expect(alStmt).toBeTruthy();
    expect(alStmt).toMatch(/parent_hashes\s+STRING\[\]/i);
  });

  it('ActionLog has timestamp INT64 (ms epoch, not TIMESTAMP type)', () => {
    const alStmt = statements.find((s) =>
      /CREATE\s+NODE\s+TABLE\s+ActionLog/i.test(s)
    );
    expect(alStmt).toMatch(/timestamp\s+INT64/i);
  });

  it('ActionLog has cbor_bytes_blake3 STRING (TC13 — hash pointer, not bytes)', () => {
    const alStmt = statements.find((s) =>
      /CREATE\s+NODE\s+TABLE\s+ActionLog/i.test(s)
    );
    expect(alStmt).toMatch(/cbor_bytes_blake3\s+STRING/i);
  });

  it('Mythos has canonicality STRING column (genesis/successor/poetic)', () => {
    const mStmt = statements.find((s) =>
      /CREATE\s+NODE\s+TABLE\s+Mythos/i.test(s)
    );
    expect(mStmt).toBeTruthy();
    expect(mStmt).toMatch(/canonicality\s+STRING/i);
  });

  it('Mythos has discovered_in_action_fp STRING property (NOT a relationship)', () => {
    const mStmt = statements.find((s) =>
      /CREATE\s+NODE\s+TABLE\s+Mythos/i.test(s)
    );
    expect(mStmt).toMatch(/discovered_in_action_fp\s+STRING/i);
  });

  it('Aqueduct has D3 defaults: resistance 0.3, capacitance 0.5', () => {
    const aqStmt = statements.find((s) =>
      /CREATE\s+NODE\s+TABLE\s+Aqueduct/i.test(s)
    );
    expect(aqStmt).toBeTruthy();
    expect(aqStmt).toMatch(/resistance\s+DOUBLE\s+DEFAULT\s+0\.3/i);
    expect(aqStmt).toMatch(/capacitance\s+DOUBLE\s+DEFAULT\s+0\.5/i);
  });
});

// ── AC2: Relationship table set ───────────────────────────────────────────────

describe('AC2 — schema.cypher rel-table completeness', () => {
  const EXPECTED_RELS = new Set([
    'CONTAINS', 'MYTHOS_HEAD', 'PREDECESSOR', 'LIVES_IN',
    'AQUEDUCT_FROM', 'AQUEDUCT_TO', 'KNOWS', 'HAS_KNOWLEDGE'
  ]);

  it('has exactly the 8 required rel tables', () => {
    expect(new Set(relTableNames)).toEqual(EXPECTED_RELS);
  });

  it('HAS_KNOWLEDGE connects Agent to Triple (native KG storage, 2026-04-24 ADR)', () => {
    const hkStmt = statements.find((s) =>
      /CREATE\s+REL\s+TABLE\s+HAS_KNOWLEDGE/i.test(s)
    );
    expect(hkStmt).toBeTruthy();
    expect(hkStmt).toMatch(/FROM\s+Agent\s+TO\s+Triple/i);
  });

  it('has no DISCOVERED_IN rel table (it is a property on Mythos)', () => {
    expect(relTableNames).not.toContain('DISCOVERED_IN');
  });

  it('CONTAINS covers Palace→Room and Room→Inscription pairs', () => {
    const cStmt = statements.find((s) =>
      /CREATE\s+REL\s+TABLE\s+CONTAINS/i.test(s)
    );
    expect(cStmt).toBeTruthy();
    expect(cStmt).toMatch(/FROM\s+Palace\s+TO\s+Room/i);
    expect(cStmt).toMatch(/FROM\s+Room\s+TO\s+Inscription/i);
  });

  it('MYTHOS_HEAD connects Palace to Mythos', () => {
    const mhStmt = statements.find((s) =>
      /CREATE\s+REL\s+TABLE\s+MYTHOS_HEAD/i.test(s)
    );
    expect(mhStmt).toBeTruthy();
    expect(mhStmt).toMatch(/FROM\s+Palace\s+TO\s+Mythos/i);
  });

  it('PREDECESSOR connects Mythos to Mythos', () => {
    const pStmt = statements.find((s) =>
      /CREATE\s+REL\s+TABLE\s+PREDECESSOR/i.test(s)
    );
    expect(pStmt).toBeTruthy();
    expect(pStmt).toMatch(/FROM\s+Mythos\s+TO\s+Mythos/i);
  });

  it('LIVES_IN connects Inscription to Room', () => {
    const liStmt = statements.find((s) =>
      /CREATE\s+REL\s+TABLE\s+LIVES_IN/i.test(s)
    );
    expect(liStmt).toBeTruthy();
    expect(liStmt).toMatch(/FROM\s+Inscription\s+TO\s+Room/i);
  });

  it('AQUEDUCT_FROM and AQUEDUCT_TO both connect Aqueduct to Room', () => {
    const afStmt = statements.find((s) =>
      /CREATE\s+REL\s+TABLE\s+AQUEDUCT_FROM/i.test(s)
    );
    const atStmt = statements.find((s) =>
      /CREATE\s+REL\s+TABLE\s+AQUEDUCT_TO/i.test(s)
    );
    expect(afStmt).toMatch(/FROM\s+Aqueduct\s+TO\s+Room/i);
    expect(atStmt).toMatch(/FROM\s+Aqueduct\s+TO\s+Room/i);
  });

  it('KNOWS connects Agent to Agent (oracle/quorum reserved)', () => {
    const kStmt = statements.find((s) =>
      /CREATE\s+REL\s+TABLE\s+KNOWS/i.test(s)
    );
    expect(kStmt).toBeTruthy();
    expect(kStmt).toMatch(/FROM\s+Agent\s+TO\s+Agent/i);
  });
});

// ── Additional schema integrity checks ───────────────────────────────────────

describe('schema.cypher structural integrity', () => {
  it('total statement count is exactly 16 (8 node + 8 rel tables, 2026-04-24 ADR adds Triple + HAS_KNOWLEDGE)', () => {
    expect(nodeTableNames).toHaveLength(8);
    expect(relTableNames).toHaveLength(8);
  });

  it('Palace has created_at INT64 and mythos_head_fp STRING', () => {
    const pStmt = statements.find((s) =>
      /CREATE\s+NODE\s+TABLE\s+Palace/i.test(s)
    );
    expect(pStmt).toMatch(/created_at\s+INT64/i);
    expect(pStmt).toMatch(/mythos_head_fp\s+STRING/i);
  });

  it('no table uses TIMESTAMP type (all timestamps are INT64 ms epoch)', () => {
    // Each CREATE TABLE statement must not use TIMESTAMP as a column type
    const allTableStmts = statements.filter((s) =>
      /CREATE\s+(NODE|REL)\s+TABLE/i.test(s)
    );
    for (const stmt of allTableStmts) {
      // Allow "TIMESTAMP" to appear in comments but not as a column type definition
      // Column type pattern: "columnName TIMESTAMP" — check there's no such definition
      expect(stmt).not.toMatch(/\w+\s+TIMESTAMP\b(?!\s*\()/i);
    }
  });
});
