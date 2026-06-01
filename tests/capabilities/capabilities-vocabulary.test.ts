/**
 * capabilities-vocabulary.test.ts — green/red gate for the `x-capabilities`
 * vocabulary (docs/decisions/2026-05-31-capabilities-schema-vocabulary.md).
 *
 * Validates the canonical palace fixture (the worked example, vocab §8) and
 * exercises every closed-field / format / presence rule with negative cases.
 * Runs against a FIXTURE, not the pinned memory-palace schema, so no archiform
 * fingerprint changes (see capability-provider-model §2 leak trace).
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateCapabilities } from '../../scripts/capabilities-validate.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const palace = JSON.parse(
  readFileSync(resolve(HERE, 'fixtures/palace.x-capabilities.json'), 'utf8'),
);

/** Assert the block is invalid and some error path ends with `suffix`. */
function expectError(block: unknown, suffix: string) {
  const r = validateCapabilities(block);
  expect(r.ok, `expected invalid for ${suffix}`).toBe(false);
  expect(r.errors.some((e: { path: string }) => e.path.endsWith(suffix)), JSON.stringify(r.errors)).toBe(true);
}

describe('x-capabilities — canonical palace fixture', () => {
  it('the worked palace example is valid', () => {
    const r = validateCapabilities(palace);
    expect(r.errors).toEqual([]);
    expect(r.ok).toBe(true);
  });

  it('two scopes coexist in one block (service + render)', () => {
    expect(palace.requires.store.interface).toMatch(/^service\//);
    expect(palace.requires.scene.interface).toMatch(/^render\//);
    expect(validateCapabilities(palace).ok).toBe(true);
  });

  it('a minimal single-requirement block is valid', () => {
    const r = validateCapabilities({
      requires: { x: { interface: 'service/text-embed', version: '^1' } },
    });
    expect(r.ok).toBe(true);
  });
});

describe('x-capabilities — closed-field + format rules (negative)', () => {
  it('rejects an unknown top-level key', () => {
    expectError({ requires: {}, bogus: {} }, 'x-capabilities.bogus');
  });

  it('rejects an unknown field on a requirement entry', () => {
    expectError(
      { requires: { x: { interface: 'service/text-embed', version: '^1', wat: true } } },
      '.wat',
    );
  });

  it('rejects an interface without a scope', () => {
    expectError({ requires: { x: { interface: 'text-embed', version: '^1' } } }, '.interface');
  });

  it('rejects an interface with an unknown scope', () => {
    expectError({ requires: { x: { interface: 'compute/foo', version: '^1' } } }, '.interface');
  });

  it('rejects a malformed version range', () => {
    expectError({ requires: { x: { interface: 'service/text-embed', version: '^^1' } } }, '.version');
  });

  it('rejects an unknown select policy', () => {
    expectError(
      { requires: { x: { interface: 'service/text-embed', version: '^1', select: 'prefer-magic' } } },
      '.select',
    );
  });

  it('rejects a non-registry/git/local source', () => {
    expectError(
      { requires: { x: { interface: 'service/text-embed', version: '^1', source: 'npm:foo' } } },
      '.source',
    );
  });
});

describe('x-capabilities — presence rules: degradesTo', () => {
  it('requires degradesTo on an optional entry', () => {
    expectError(
      { optional: { k: { interface: 'service/vector-knn', version: '^1' } } },
      '.degradesTo',
    );
  });

  it('forbids degradesTo on a required entry', () => {
    expectError(
      { requires: { x: { interface: 'service/text-embed', version: '^1', degradesTo: 'mock' } } },
      '.degradesTo',
    );
  });

  it('accepts degradesTo on an optional entry', () => {
    const r = validateCapabilities({
      optional: { k: { interface: 'service/vector-knn', version: '^1', degradesTo: 'sequential-replay' } },
    });
    expect(r.ok).toBe(true);
  });
});

describe('x-capabilities — warnings (non-fatal)', () => {
  it('warns (but does not fail) when version is omitted', () => {
    const r = validateCapabilities({ requires: { x: { interface: 'service/text-embed' } } });
    expect(r.ok).toBe(true);
    expect(r.warnings.some((w: { path: string }) => w.path.endsWith('.version'))).toBe(true);
  });
});
