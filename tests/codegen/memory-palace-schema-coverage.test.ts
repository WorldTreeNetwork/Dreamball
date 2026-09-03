/**
 * Story 2.1 — Memory Palace schema coverage + metaschema-validity test.
 *
 * AC1 + AC3 — every Memory Palace type in `src/protocol_v2.zig` AND
 *   every node/edge table in `src/memory-palace/schema.cypher` MUST
 *   have a corresponding entry in `schemas/memory-palace-0.1.0.json`.
 *   Missing types fail the test naming the gap.
 *
 * AC4 — Triple declares the fp MERGE key with D-028 derivation note;
 *   HAS_KNOWLEDGE rel is present; Agent.knowledge_graph is NOT present.
 *
 * Metaschema — `schemas/memory-palace-0.1.0.json` validates against
 *   JSON Schema draft 2020-12 metaschema with zero errors.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Ajv2020 } from 'ajv/dist/2020.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');
const SCHEMA_PATH = join(REPO_ROOT, 'schemas', 'memory-palace-0.1.0.json');
const CYPHER_PATH = join(REPO_ROOT, 'src', 'memory-palace', 'schema.cypher');

const schemaJson = readFileSync(SCHEMA_PATH, 'utf8');
const schema = JSON.parse(schemaJson) as { $defs?: Record<string, unknown> };

const cypherSrc = readFileSync(CYPHER_PATH, 'utf8');

// ── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Collect all $defs type names from the schema.
 */
function collectDefNames(s: { $defs?: Record<string, unknown> }): Set<string> {
  const out = new Set<string>();
  if (s.$defs) {
    for (const k of Object.keys(s.$defs)) out.add(k);
  }
  return out;
}

/**
 * Collect all property names from a schema def (shallow — just the direct
 * properties object).
 */
function collectDefPropertyNames(
  s: { $defs?: Record<string, unknown> },
  defName: string,
): Set<string> {
  const out = new Set<string>();
  const def = s.$defs?.[defName];
  if (
    def &&
    typeof def === 'object' &&
    'properties' in def &&
    def.properties &&
    typeof def.properties === 'object'
  ) {
    for (const k of Object.keys(def.properties as Record<string, unknown>)) {
      out.add(k);
    }
  }
  return out;
}

/**
 * Extract all node table names from a Cypher DDL source.
 * Matches: CREATE NODE TABLE <Name>(
 */
function extractCypherNodeTables(cypher: string): string[] {
  const re = /CREATE\s+NODE\s+TABLE\s+(\w+)\s*\(/g;
  const out: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(cypher)) !== null) {
    out.push(m[1]);
  }
  return out;
}

/**
 * Extract all rel table names from a Cypher DDL source.
 * Matches: CREATE REL TABLE <Name>(
 */
function extractCypherRelTables(cypher: string): string[] {
  const re = /CREATE\s+REL\s+TABLE\s+(\w+)\s*\(/g;
  const out: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(cypher)) !== null) {
    out.push(m[1]);
  }
  return out;
}

/**
 * Given a cypher table name (e.g. "Palace"), find the schema $defs key
 * that declares it via x-cypher-table. Returns the def key or null.
 */
function findDefForCypherTable(
  s: { $defs?: Record<string, unknown> },
  tableName: string,
): string | null {
  if (!s.$defs) return null;
  for (const [key, def] of Object.entries(s.$defs)) {
    if (
      def &&
      typeof def === 'object' &&
      'x-cypher-table' in def &&
      (def as { 'x-cypher-table': string })['x-cypher-table'] === tableName
    ) {
      return key;
    }
  }
  return null;
}

// ── The required types from the story AC1 ────────────────────────────────────
// These are the canonical type names the story mandates be in the schema.
const REQUIRED_DEF_NAMES: string[] = [
  'InscriptionNode',
  'MythosNode',
  'TripleNode',
  'RoomNode',
  'AqueductNode',
  'PalaceNode',
  'AgentNode',
  'ActionLogNode',
  // Relationship tables
  'ContainsRel',
  'MythosHeadRel',
  'PredecessorRel',
  'LivesInRel',
  'AqueductFromRel',
  'AqueductToRel',
  'KnowsRel',
  'HasKnowledgeRel',
];

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('memory-palace schema: required AC1 types declared', () => {
  const defNames = collectDefNames(schema);

  for (const name of REQUIRED_DEF_NAMES) {
    it(`$defs contains ${name}`, () => {
      expect(defNames.has(name), `schemas/memory-palace-0.1.0.json is missing $defs/${name}`).toBe(
        true,
      );
    });
  }
});

describe('memory-palace schema: cypher node tables covered (AC3)', () => {
  const nodeTables = extractCypherNodeTables(cypherSrc);

  for (const table of nodeTables) {
    it(`node table ${table} has a $defs entry with x-cypher-table: "${table}"`, () => {
      const found = findDefForCypherTable(schema, table);
      expect(
        found,
        `schemas/memory-palace-0.1.0.json is missing a $defs entry with x-cypher-table: "${table}" (src/memory-palace/schema.cypher defines node table ${table})`,
      ).not.toBeNull();
    });
  }
});

describe('memory-palace schema: cypher rel tables covered (AC3)', () => {
  const relTables = extractCypherRelTables(cypherSrc);

  for (const table of relTables) {
    it(`rel table ${table} has a $defs entry with x-cypher-table: "${table}"`, () => {
      const found = findDefForCypherTable(schema, table);
      expect(
        found,
        `schemas/memory-palace-0.1.0.json is missing a $defs entry with x-cypher-table: "${table}" (src/memory-palace/schema.cypher defines rel table ${table})`,
      ).not.toBeNull();
    });
  }
});

describe('memory-palace schema: Aqueduct AC1 — all 6 required properties (AC1)', () => {
  const required6 = [
    'resistance',
    'capacitance',
    'strength',
    'conductance',
    'phase',
    'last_traversal_ts',
  ];

  it('AqueductNode declares all 6 AC1-required properties', () => {
    const props = collectDefPropertyNames(schema, 'AqueductNode');
    const missing = required6.filter((p) => !props.has(p));
    expect(
      missing,
      `AqueductNode is missing AC1-required properties: ${missing.join(', ')}`,
    ).toEqual([]);
  });
});

describe('memory-palace schema: Agent extensions (AC1)', () => {
  const requiredAgentFields = [
    'personality_master_prompt',
    'memory',
    'emotional_register',
    'interaction_set',
  ];

  it('AgentNode declares all 4 AC1-required extension fields', () => {
    const props = collectDefPropertyNames(schema, 'AgentNode');
    const missing = requiredAgentFields.filter((p) => !props.has(p));
    expect(
      missing,
      `AgentNode is missing AC1-required extension fields: ${missing.join(', ')}`,
    ).toEqual([]);
  });
});

describe('memory-palace schema: D-028 Triple as schema citizen (AC4)', () => {
  it('TripleNode has fp property declared as MERGE key', () => {
    const props = collectDefPropertyNames(schema, 'TripleNode');
    expect(props.has('fp'), 'TripleNode.fp (MERGE key) must be declared').toBe(true);
  });

  it('TripleNode x-merge-key-derivation records the D-028 blake3 formula', () => {
    const def = schema.$defs?.['TripleNode'] as Record<string, unknown> | undefined;
    expect(def, 'TripleNode $defs entry must exist').toBeDefined();
    const derivation = def?.['x-merge-key-derivation'] as string | undefined;
    expect(
      derivation,
      'TripleNode must declare x-merge-key-derivation',
    ).toBeDefined();
    // The derivation string must reference all four components per D-028.
    expect(derivation, 'derivation must mention agent_fp').toMatch(/agent_fp/);
    expect(derivation, 'derivation must mention subject').toMatch(/subject/);
    expect(derivation, 'derivation must mention predicate').toMatch(/predicate/);
    expect(derivation, 'derivation must mention object').toMatch(/object/);
    expect(derivation, 'derivation must mention blake3').toMatch(/blake3/);
  });

  it('HAS_KNOWLEDGE rel is declared (D-028 — Agent to Triple)', () => {
    const found = findDefForCypherTable(schema, 'HAS_KNOWLEDGE');
    expect(
      found,
      'schemas/memory-palace-0.1.0.json must declare HAS_KNOWLEDGE rel (D-028)',
    ).not.toBeNull();
  });

  it('AgentNode does NOT have knowledge_graph property (removed per D-028)', () => {
    const props = collectDefPropertyNames(schema, 'AgentNode');
    expect(
      props.has('knowledge_graph'),
      'AgentNode must NOT have knowledge_graph (removed per D-028 — use Triple nodes + HAS_KNOWLEDGE rel)',
    ).toBe(false);
  });
});

describe('memory-palace schema metaschema validity (AC1)', () => {
  it('validates against JSON Schema draft 2020-12', () => {
    // strict: false keeps Ajv from complaining about x-* extension keys.
    const ajv = new Ajv2020({ strict: false, allErrors: true });
    expect(() => ajv.compile(schema)).not.toThrow();
  });
});
