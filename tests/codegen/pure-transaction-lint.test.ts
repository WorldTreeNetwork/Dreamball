/**
 * Story 3.1 — Pure-transaction lint (AC5 / FR6).
 *
 * Per D-019: actions are pure transactions; never interactive.
 * This test walks all x-actions entries in schemas/*.json and rejects:
 *   - input fields named "prompt"
 *   - input fields named "confirm"
 *   - input fields with `format: "tty-interactive"`
 *
 * Passing manifests pass. The lint is wired here as a Vitest so it
 * runs in `bun run test:unit -- --run` and is therefore gated by CI.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname, resolve, extname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');
const SCHEMAS_DIR = join(REPO_ROOT, 'schemas');

// ── Lint rule constants ───────────────────────────────────────────────────────

/** Input field names that indicate interactive intent (FR6). */
const BANNED_FIELD_NAMES = new Set(['prompt', 'confirm']);

/** format value that indicates TTY-interactive input (FR6). */
const BANNED_FORMAT = 'tty-interactive';

// ── Types ─────────────────────────────────────────────────────────────────────

interface ActionEntry {
  inputs?: {
    properties?: Record<string, unknown>;
  };
}

interface SchemaDoc {
  'x-actions'?: Record<string, ActionEntry>;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Collect all lint violations from a single action entry's inputs.
 * Returns array of violation strings, empty = clean.
 */
function lintActionInputs(verbName: string, entry: ActionEntry): string[] {
  const violations: string[] = [];
  const properties = entry.inputs?.properties;
  if (!properties) return violations;

  for (const [fieldName, fieldSchema] of Object.entries(properties)) {
    // Rule 1: banned field name
    if (BANNED_FIELD_NAMES.has(fieldName)) {
      violations.push(
        `verb "${verbName}": input field named "${fieldName}" is banned (interactive field; breaks agent-callability per FR6)`,
      );
    }

    // Rule 2: banned format value
    if (
      fieldSchema &&
      typeof fieldSchema === 'object' &&
      'format' in fieldSchema &&
      (fieldSchema as Record<string, unknown>)['format'] === BANNED_FORMAT
    ) {
      violations.push(
        `verb "${verbName}": input field "${fieldName}" has format: "${BANNED_FORMAT}" (TTY-interactive fields banned per FR6/D-019)`,
      );
    }
  }

  return violations;
}

/**
 * Read and parse all *.json schema files from the schemas/ directory.
 * Returns array of [filename, parsed doc] pairs.
 */
function loadSchemas(): Array<[string, SchemaDoc]> {
  const files = readdirSync(SCHEMAS_DIR).filter(
    (f) => extname(f) === '.json' && !f.startsWith('.'),
  );
  return files.map((f) => {
    const content = readFileSync(join(SCHEMAS_DIR, f), 'utf8');
    return [f, JSON.parse(content) as SchemaDoc];
  });
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('AC5: pure-transaction lint — no interactive input fields in x-actions', () => {
  const schemas = loadSchemas();

  it('at least one schema file has x-actions (sanity check)', () => {
    const hasActions = schemas.some(([, doc]) => doc['x-actions'] != null);
    expect(
      hasActions,
      'expected at least one schema file with x-actions (memory-palace schema should have it)',
    ).toBe(true);
  });

  for (const [filename, doc] of schemas) {
    const xActions = doc['x-actions'];
    if (!xActions) continue;

    describe(`schema: ${filename}`, () => {
      for (const [verbName, entry] of Object.entries(xActions)) {
        it(`verb "${verbName}" has no banned input fields`, () => {
          const violations = lintActionInputs(verbName, entry);
          expect(
            violations,
            `pure-transaction lint failures:\n${violations.join('\n')}`,
          ).toHaveLength(0);
        });
      }
    });
  }
});

// ── AC5: lint correctly identifies violations in synthetic manifests ──────────

describe('AC5: pure-transaction lint — synthetic violation detection', () => {
  it('detects field named "prompt"', () => {
    const entry: ActionEntry = {
      inputs: {
        properties: {
          prompt: { type: 'string', description: 'User prompt text' },
          name: { type: 'string' },
        },
      },
    };
    const violations = lintActionInputs('test-verb', entry);
    expect(violations.length).toBeGreaterThan(0);
    expect(violations[0]).toContain('"prompt"');
  });

  it('detects field named "confirm"', () => {
    const entry: ActionEntry = {
      inputs: {
        properties: {
          confirm: { type: 'boolean' },
          palace: { type: 'string' },
        },
      },
    };
    const violations = lintActionInputs('test-verb', entry);
    expect(violations.length).toBeGreaterThan(0);
    expect(violations[0]).toContain('"confirm"');
  });

  it('detects field with format: "tty-interactive"', () => {
    const entry: ActionEntry = {
      inputs: {
        properties: {
          body: { type: 'string', format: 'tty-interactive' },
        },
      },
    };
    const violations = lintActionInputs('test-verb', entry);
    expect(violations.length).toBeGreaterThan(0);
    expect(violations[0]).toContain(BANNED_FORMAT);
  });

  it('allows "confirmation-message" field (not "confirm")', () => {
    const entry: ActionEntry = {
      inputs: {
        properties: {
          'confirmation-message': { type: 'string' },
          palace: { type: 'string' },
        },
      },
    };
    const violations = lintActionInputs('test-verb', entry);
    expect(violations).toHaveLength(0);
  });

  it('allows "prompted-by" field (not "prompt")', () => {
    const entry: ActionEntry = {
      inputs: {
        properties: {
          'prompted-by': { type: 'string' },
          out: { type: 'string' },
        },
      },
    };
    const violations = lintActionInputs('test-verb', entry);
    expect(violations).toHaveLength(0);
  });

  it('passes cleanly for entry with no properties', () => {
    const entry: ActionEntry = { inputs: { properties: {} } };
    expect(lintActionInputs('test-verb', entry)).toHaveLength(0);
  });

  it('passes cleanly for entry with no inputs', () => {
    const entry: ActionEntry = {};
    expect(lintActionInputs('test-verb', entry)).toHaveLength(0);
  });
});
