/**
 * manifest-resolver.test.ts — green/red gate for the manifest-driven resolver
 * (jelly-server/src/capabilities/resolver-core.ts + palace-resolver.ts).
 *
 * Exercises:
 *   - satisfies() — enforced-semver range matching (§10.1), incl. major discrim.
 *   - resolvePalaceCapabilities() against the REAL generated PALACE_CAPABILITIES:
 *       embed → bound (mock, in JELLY_EMBED_MOCK mode); knn → degraded;
 *       store + scene → unbound (no provider yet) ⇒ report.ok === false.
 *   - a synthetic all-providers registry ⇒ everything bound, ok === true.
 *   - version mismatch (provider implements 2.0 for a ^1 need) ⇒ unbound.
 */

// Mock the text-embed provider so `embed` binds in CI without a model.
process.env.JELLY_EMBED_MOCK = '1';

import { describe, it, expect } from 'vitest';
import {
  satisfies,
  resolveCapabilities,
  assertRequiredBound,
  type ProviderRegistry,
  type CapabilityProviderDescriptor,
  type Resolution,
} from '../../jelly-server/src/capabilities/resolver-core.js';
import { resolvePalaceCapabilities } from '../../jelly-server/src/capabilities/palace-resolver.js';
import { PALACE_CAPABILITIES } from '../../src/lib/generated/palace-capabilities.js';

const find = (report: { resolutions: readonly Resolution[] }, alias: string): Resolution => {
  const r = report.resolutions.find((x) => x.alias === alias);
  if (!r) throw new Error(`no resolution for alias ${alias}`);
  return r;
};

const prov = (iface: string, version: string, id: string): CapabilityProviderDescriptor => ({
  interface: iface,
  implementsVersion: version,
  id,
  available: () => true,
});

describe('satisfies() — enforced-semver range matching (§10.1)', () => {
  const cases: Array<[string, string, boolean]> = [
    ['^1', '1.0.0', true],
    ['^1', '1.5.2', true],
    ['^1', '2.0.0', false], // major is the discriminator
    ['^1', '0.9.0', false],
    ['^1.2', '1.2.0', true],
    ['^1.2', '1.4.0', true],
    ['^1.2', '1.1.0', false], // below floor
    ['~1.2', '1.2.5', true],
    ['~1.2', '1.3.0', false],
    ['=1.2.3', '1.2.3', true],
    ['=1.2.3', '1.2.4', false],
    ['1', '1.7.0', true], // bare major
    ['1.2', '1.2.9', true],
    ['1.2', '1.3.0', false],
    ['*', '9.9.9', true],
  ];
  for (const [range, version, expected] of cases) {
    it(`${range} ∋ ${version} → ${expected}`, () => {
      expect(satisfies(range, version)).toBe(expected);
    });
  }
});

describe('resolvePalaceCapabilities() against the generated manifest', () => {
  const report = resolvePalaceCapabilities();

  it('binds embed to the mock text-embed provider', () => {
    const embed = find(report, 'embed');
    expect(embed.status).toBe('bound');
    expect(embed.providerId).toBe('mock');
    expect(embed.interface).toBe('service/text-embed');
  });

  it('degrades the optional knn to its declared fallback', () => {
    const knn = find(report, 'knn');
    expect(knn.status).toBe('degraded');
    expect(knn.degradedTo).toBe('sequential-replay');
  });

  it('binds store to the in-memory graph-store provider', () => {
    const store = find(report, 'store');
    expect(store.status).toBe('bound');
    expect(store.providerId).toBe('in-memory');
  });

  it('reports scene as unbound (no render provider yet) — honestly', () => {
    expect(find(report, 'scene').status).toBe('unbound');
    expect(find(report, 'scene').reason).toMatch(/no provider registered/);
  });

  it('report.ok is false while required capabilities lack providers', () => {
    expect(report.ok).toBe(false);
  });

  it('assertRequiredBound throws, naming only the remaining unbound (scene)', () => {
    expect(() => assertRequiredBound(report)).toThrow(/scene/);
  });
});

describe('resolveCapabilities() with a complete synthetic registry', () => {
  const full: ProviderRegistry = new Map([
    ['service/graph-store', [prov('service/graph-store', '1.0', 'kuzu'), prov('service/graph-store', '1.2', 'sqlite')]],
    ['service/text-embed', [prov('service/text-embed', '1.0', 'mock')]],
    ['service/vector-knn', [prov('service/vector-knn', '1.0', 'kuzu-knn')]],
    ['render/omnispherical', [prov('render/omnispherical', '1.0', 'threlte')]],
  ]);

  it('binds every requirement when providers exist; ok === true', () => {
    const report = resolveCapabilities(PALACE_CAPABILITIES, full);
    expect(report.ok).toBe(true);
    expect(report.resolutions.every((r) => r.status === 'bound')).toBe(true);
    expect(() => assertRequiredBound(report)).not.toThrow();
    // a SECOND engine (sqlite) qualifies for graph-store alongside kuzu —
    // the interface is the contract, not the engine.
    expect(find(report, 'store').providerId).toBe('kuzu'); // registry order = priority
  });

  it('leaves a requirement unbound when only a wrong-major provider exists', () => {
    const wrongMajor: ProviderRegistry = new Map([
      ['service/graph-store', [prov('service/graph-store', '2.0', 'kuzu-v2')]],
    ]);
    const report = resolveCapabilities(PALACE_CAPABILITIES, wrongMajor);
    const store = find(report, 'store');
    expect(store.status).toBe('unbound');
    expect(store.reason).toMatch(/no provider satisfies/);
  });
});
