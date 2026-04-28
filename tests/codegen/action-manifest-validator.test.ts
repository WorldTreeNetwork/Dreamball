/**
 * Story 3.1 — Action Manifest Schema Validator tests.
 *
 * AC1: schema declares all 5 verbs with required fields.
 * AC2: closed `attributes` per D-035 — unknown keys rejected.
 * AC3: closed `effects.kind` enum — unknown values rejected.
 * AC4: closed `idempotency` enum — unknown values rejected.
 * AC6: `implementation.wasm` must match blake3-hex pattern (64 hex chars).
 *
 * The validator here exercises the JSON Schema definitions directly
 * using Ajv (draft 2020-12) since the Valibot generator (gen_valibot.zig)
 * is a shadow-phase generator and the closed-set validator is expressed
 * in the JSON Schema itself via additionalProperties:false and enum.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Ajv2020 } from 'ajv/dist/2020.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');
const SCHEMA_PATH = join(REPO_ROOT, 'schemas', 'memory-palace-0.1.0.json');

const schemaDoc = JSON.parse(readFileSync(SCHEMA_PATH, 'utf8')) as Record<string, unknown>;

// Build a standalone validator for ActionManifestEntry using its $defs.
// We extract the $defs block from the root schema and compile a schema
// that validates a single ActionManifestEntry.
const ajv = new Ajv2020({ strict: false, allErrors: true });

// Register the root schema so $ref resolution works.
ajv.addSchema(schemaDoc, 'dreamball:memory-palace@0.1.0');

// Compiled validator for a single ActionManifestEntry (via $ref).
const validateEntry = ajv.compile({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $ref: 'dreamball:memory-palace@0.1.0#/$defs/ActionManifestEntry',
});

// Compiled validator for ActionManifestAttributes (closed set, AC2).
const validateAttributes = ajv.compile({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $ref: 'dreamball:memory-palace@0.1.0#/$defs/ActionManifestAttributes',
});

// Compiled validator for ActionManifestEffects (closed enum, AC3).
const validateEffects = ajv.compile({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $ref: 'dreamball:memory-palace@0.1.0#/$defs/ActionManifestEffects',
});

// Compiled validator for ActionManifestImplementation (hex pattern, AC6).
const validateImplementation = ajv.compile({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $ref: 'dreamball:memory-palace@0.1.0#/$defs/ActionManifestImplementation',
});

// ── Helpers ───────────────────────────────────────────────────────────────────

/** A fully-valid minimal ActionManifestEntry for use in positive tests. */
function validEntry(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    summary: 'Test verb',
    inputs: {
      type: 'object',
      required: ['foo'],
      additionalProperties: false,
      properties: { foo: { type: 'string' } },
    },
    outputs: {
      type: 'object',
      properties: { bar: { type: 'string' } },
    },
    effects: { kind: 'ActionEnvelope' },
    idempotency: 'creates',
    streaming: false,
    attributes: {
      destructive: false,
      requiresConfirmation: false,
      confirmationMessage: '',
      agentVisible: true,
    },
    implementation: {
      wasm: '0000000000000000000000000000000000000000000000000000000000000000',
    },
    ...overrides,
  };
}

// ── AC1: schema declares all 5 sprint-001 verbs in x-actions ─────────────────

describe('AC1: x-actions map declares all 5 sprint-001 verbs', () => {
  const xActions = (schemaDoc as Record<string, unknown>)['x-actions'] as
    | Record<string, unknown>
    | undefined;

  it('x-actions map exists in schema', () => {
    expect(xActions, 'x-actions must be present in memory-palace schema').toBeDefined();
  });

  const REQUIRED_VERBS = ['mint', 'inscribe', 'add-room', 'rename-mythos', 'move'];
  for (const verb of REQUIRED_VERBS) {
    it(`x-actions declares verb: ${verb}`, () => {
      expect(
        xActions,
        'x-actions must be an object',
      ).toBeDefined();
      expect(
        Object.prototype.hasOwnProperty.call(xActions, verb),
        `x-actions is missing verb: ${verb}`,
      ).toBe(true);
    });
  }
});

// ── AC1: all 5 verb entries are valid ActionManifestEntry instances ────────────

describe('AC1: each x-actions verb entry validates against ActionManifestEntry', () => {
  const xActions = (schemaDoc as Record<string, unknown>)['x-actions'] as
    Record<string, unknown> | undefined;

  const REQUIRED_VERBS = ['mint', 'inscribe', 'add-room', 'rename-mythos', 'move'];

  for (const verb of REQUIRED_VERBS) {
    it(`${verb} entry is a valid ActionManifestEntry`, () => {
      const entry = xActions?.[verb];
      expect(entry, `x-actions.${verb} must exist`).toBeDefined();
      const valid = validateEntry(entry);
      expect(
        valid,
        `x-actions.${verb} failed validation: ${JSON.stringify(validateEntry.errors)}`,
      ).toBe(true);
    });
  }
});

// ── AC1: metaschema validity (extended from Story 2.1) ─────────────────────────

describe('AC1: schema validates against JSON Schema draft 2020-12 metaschema', () => {
  it('compiles without errors (Ajv 2020-12 strict:false)', () => {
    const freshAjv = new Ajv2020({ strict: false, allErrors: true });
    expect(() => freshAjv.compile(schemaDoc)).not.toThrow();
  });
});

// ── AC2: closed `attributes` — happy path ─────────────────────────────────────

describe('AC2: closed attributes set — happy paths', () => {
  it('accepts exactly the 4 known attribute keys', () => {
    const attrs = {
      destructive: true,
      requiresConfirmation: true,
      confirmationMessage: 'Are you sure?',
      agentVisible: true,
    };
    const valid = validateAttributes(attrs);
    expect(valid, `valid attributes rejected: ${JSON.stringify(validateAttributes.errors)}`).toBe(
      true,
    );
  });

  it('accepts attributes with all false/empty values', () => {
    const attrs = {
      destructive: false,
      requiresConfirmation: false,
      confirmationMessage: '',
      agentVisible: false,
    };
    expect(validateAttributes(attrs)).toBe(true);
  });
});

// ── AC2: closed `attributes` — reject unknown keys (D-035) ────────────────────

describe('AC2: closed attributes set — unknown keys rejected (D-035)', () => {
  it('rejects x-experimental: true (x- prefix banned in sprint-002)', () => {
    const attrs = {
      destructive: true,
      requiresConfirmation: false,
      confirmationMessage: '',
      agentVisible: true,
      'x-experimental': true,
    };
    const valid = validateAttributes(attrs);
    expect(
      valid,
      'attributes with x-experimental must be rejected (additionalProperties: false)',
    ).toBe(false);
    const errorMessages = (validateAttributes.errors ?? []).map((e) => JSON.stringify(e));
    expect(
      errorMessages.some((m) => m.includes('additionalProperties') || m.includes('additional')),
      `expected additionalProperties error, got: ${errorMessages.join(', ')}`,
    ).toBe(true);
  });

  it('rejects unknown key: custom-flag', () => {
    const attrs = {
      destructive: false,
      requiresConfirmation: false,
      confirmationMessage: '',
      agentVisible: true,
      'custom-flag': 'yes',
    };
    expect(validateAttributes(attrs)).toBe(false);
  });
});

// ── AC3: closed `effects.kind` enum — happy paths ────────────────────────────

describe('AC3: closed effects.kind enum — happy paths', () => {
  for (const kind of ['ActionEnvelope', 'Read', 'Derived']) {
    it(`accepts effects.kind: "${kind}"`, () => {
      const effects = { kind };
      const valid = validateEffects(effects);
      expect(
        valid,
        `effects.kind "${kind}" was rejected: ${JSON.stringify(validateEffects.errors)}`,
      ).toBe(true);
    });
  }
});

// ── AC3: closed `effects.kind` enum — unknown values rejected ────────────────

describe('AC3: closed effects.kind enum — unknown values rejected', () => {
  it('rejects effects.kind: "Mutation"', () => {
    const effects = { kind: 'Mutation' };
    const valid = validateEffects(effects);
    expect(valid, 'effects.kind "Mutation" must be rejected (closed enum)').toBe(false);
  });

  it('rejects effects.kind: "SideEffect"', () => {
    const effects = { kind: 'SideEffect' };
    expect(validateEffects(effects)).toBe(false);
  });

  it('rejects effects.kind: "" (empty string)', () => {
    const effects = { kind: '' };
    expect(validateEffects(effects)).toBe(false);
  });
});

// ── AC4: closed `idempotency` enum — happy paths ─────────────────────────────

describe('AC4: closed idempotency enum — happy paths', () => {
  for (const idempotency of ['creates', 'updates', 'idempotent']) {
    it(`accepts idempotency: "${idempotency}"`, () => {
      const entry = validEntry({ idempotency });
      const valid = validateEntry(entry);
      expect(
        valid,
        `idempotency "${idempotency}" was rejected: ${JSON.stringify(validateEntry.errors)}`,
      ).toBe(true);
    });
  }
});

// ── AC4: closed `idempotency` enum — unknown values rejected ─────────────────

describe('AC4: closed idempotency enum — unknown values rejected', () => {
  it('rejects idempotency: "rerunnable"', () => {
    const entry = validEntry({ idempotency: 'rerunnable' });
    const valid = validateEntry(entry);
    expect(valid, 'idempotency "rerunnable" must be rejected (closed enum)').toBe(false);
  });

  it('rejects idempotency: "once"', () => {
    const entry = validEntry({ idempotency: 'once' });
    expect(validateEntry(entry)).toBe(false);
  });

  it('rejects idempotency: "" (empty string)', () => {
    const entry = validEntry({ idempotency: '' });
    expect(validateEntry(entry)).toBe(false);
  });
});

// ── AC6: implementation.wasm must be blake3-hex pattern ──────────────────────

describe('AC6: implementation.wasm hex pattern enforcement', () => {
  it('accepts 64-char lowercase hex string (all zeros placeholder)', () => {
    const impl = {
      wasm: '0000000000000000000000000000000000000000000000000000000000000000',
    };
    expect(validateImplementation(impl)).toBe(true);
  });

  it('accepts 64-char lowercase hex string (real-looking fp)', () => {
    const impl = {
      wasm: 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1',
    };
    expect(validateImplementation(impl)).toBe(true);
  });

  it('rejects URL: "https://example.com/mint.wasm"', () => {
    const impl = { wasm: 'https://example.com/mint.wasm' };
    const valid = validateImplementation(impl);
    expect(valid, 'URL must be rejected — only blake3 hex fps allowed').toBe(false);
  });

  it('rejects path: "/dist/mint.wasm"', () => {
    const impl = { wasm: '/dist/mint.wasm' };
    expect(validateImplementation(impl)).toBe(false);
  });

  it('rejects uppercase hex (pattern requires lowercase)', () => {
    const impl = {
      wasm: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    };
    expect(validateImplementation(impl)).toBe(false);
  });

  it('rejects 63-char hex (too short)', () => {
    const impl = {
      wasm: '000000000000000000000000000000000000000000000000000000000000000',
    };
    expect(validateImplementation(impl)).toBe(false);
  });

  it('rejects 65-char hex (too long)', () => {
    const impl = {
      wasm: '00000000000000000000000000000000000000000000000000000000000000000',
    };
    expect(validateImplementation(impl)).toBe(false);
  });
});

// ── Full entry happy-path ─────────────────────────────────────────────────────

describe('ActionManifestEntry: full valid entry passes', () => {
  it('validEntry() helper itself validates cleanly', () => {
    const entry = validEntry();
    const valid = validateEntry(entry);
    expect(
      valid,
      `validEntry() failed: ${JSON.stringify(validateEntry.errors)}`,
    ).toBe(true);
  });
});
