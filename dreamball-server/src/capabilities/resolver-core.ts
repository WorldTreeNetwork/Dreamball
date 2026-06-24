/**
 * resolver-core.ts — the generic, manifest-driven capability resolver.
 *
 * Generalizes the text-embed-specific binding into the engine that consumes a
 * capability requirements manifest (the generated `PALACE_CAPABILITIES`) plus a
 * provider registry, and produces a resolution report: per requirement,
 * bound | degraded | unbound.
 *
 * Runtime half of the capability/provider model
 * (docs/decisions/2026-05-31-capability-provider-model.md §3): the manifest
 * declares needs; the resolver binds them to content-addressed providers,
 * matching by enforced-semver range (§10.1). Selection is a *preference*, not a
 * safety call — every in-range provider is conformance-verified — so the
 * report, not a throw, is the primary artifact (the browser app / host reads it
 * to decide what to acquire, §10.6). `assertRequiredBound` is the optional
 * enforcement step.
 */

import type {
  CapabilityRequirement,
  CapabilityScope,
  CapabilityPresence,
} from '../../../src/lib/generated/palace-capabilities.js';

/** A provider that can satisfy one capability interface, content-addressed. */
export interface CapabilityProviderDescriptor {
  /** `<scope>/<name>` interface this provider implements. */
  readonly interface: string;
  /** The interface version it implements (enforced-semver §10.1), e.g. "1.0". */
  readonly implementsVersion: string;
  /** Stable provider id. */
  readonly id: string;
  /** Cheap, synchronous, non-throwing bindability check. */
  available(): boolean;
}

/** interface id → providers offering it (registry order = binding priority). */
export type ProviderRegistry = ReadonlyMap<string, readonly CapabilityProviderDescriptor[]>;

export type ResolutionStatus = 'bound' | 'degraded' | 'unbound';

export interface Resolution {
  readonly alias: string;
  readonly interface: string;
  readonly scope: CapabilityScope;
  readonly presence: CapabilityPresence;
  readonly status: ResolutionStatus;
  readonly providerId?: string;
  readonly implementsVersion?: string;
  readonly degradedTo?: string;
  readonly reason?: string;
}

export interface ResolutionReport {
  readonly resolutions: readonly Resolution[];
  /** true iff every `required` capability is bound. */
  readonly ok: boolean;
}

// ── enforced-semver range matching (§10.1) ────────────────────────────────────

type Triple = readonly [number, number, number];

function parse(s: string): { triple: Triple; parts: number } | null {
  const m = s.trim().match(/^(\d+)(?:\.(\d+))?(?:\.(\d+))?$/);
  if (!m) return null;
  const parts = m[3] !== undefined ? 3 : m[2] !== undefined ? 2 : 1;
  return { triple: [Number(m[1]), Number(m[2] ?? 0), Number(m[3] ?? 0)], parts };
}

function ge(a: Triple, b: Triple): boolean {
  for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] > b[i];
  return true; // equal
}

function eqAtPrecision(a: Triple, b: Triple, parts: number): boolean {
  for (let i = 0; i < parts; i++) if (a[i] !== b[i]) return false;
  return true;
}

/**
 * Does `version` satisfy `range`? Major is the capability discriminator (§10.1):
 *   ^A[.B[.C]]  same major as floor, version >= floor
 *   ~A.B[.C]    same major+minor, version >= floor   (~A behaves like ^A)
 *   =A.B.C      exact at the precision given
 *   A[.B[.C]]   bare: exact at the precision given (A → any minor/patch of A)
 *   *           any
 */
export function satisfies(range: string, version: string): boolean {
  const v = parse(version);
  if (!v) return false;
  const r = range.trim();
  if (r === '*' || r === '') return true;
  const op = r[0] === '^' || r[0] === '~' || r[0] === '=' ? r[0] : '';
  const floor = parse(op ? r.slice(1) : r);
  if (!floor) return false;
  const ver = v.triple;
  const fl = floor.triple;

  if (op === '^') return ver[0] === fl[0] && ge(ver, fl);
  if (op === '~') {
    if (floor.parts >= 2) return ver[0] === fl[0] && ver[1] === fl[1] && ge(ver, fl);
    return ver[0] === fl[0] && ge(ver, fl); // ~A == ^A
  }
  // '=' or bare: exact at the floor's precision.
  return eqAtPrecision(ver, fl, floor.parts);
}

// ── resolution ────────────────────────────────────────────────────────────────

function noProviderReason(registry: ProviderRegistry, req: CapabilityRequirement): string {
  const providers = registry.get(req.interface);
  if (!providers || providers.length === 0) return `no provider registered for ${req.interface}`;
  const versionMatch = providers.filter((p) => satisfies(req.version, p.implementsVersion));
  if (versionMatch.length === 0) return `no provider satisfies ${req.interface}@${req.version}`;
  return `provider(s) for ${req.interface}@${req.version} present but none available`;
}

/**
 * Resolve a requirements manifest against a provider registry. Pure: reads
 * `available()` (sync), never loads. Produces a report; does not throw.
 */
export function resolveCapabilities(
  manifest: readonly CapabilityRequirement[],
  registry: ProviderRegistry,
): ResolutionReport {
  const resolutions: Resolution[] = manifest.map((req): Resolution => {
    const candidates = (registry.get(req.interface) ?? []).filter(
      (p) => satisfies(req.version, p.implementsVersion) && p.available(),
    );
    if (candidates.length > 0) {
      // Selection is preference, not safety (§10.1 Decision A): default = first
      // in registry order (priority). Profile-aware `select` is future work.
      const chosen = candidates[0];
      return {
        alias: req.alias,
        interface: req.interface,
        scope: req.scope,
        presence: req.presence,
        status: 'bound',
        providerId: chosen.id,
        implementsVersion: chosen.implementsVersion,
      };
    }
    const reason = noProviderReason(registry, req);
    if (req.presence === 'optional') {
      return {
        alias: req.alias,
        interface: req.interface,
        scope: req.scope,
        presence: req.presence,
        status: 'degraded',
        degradedTo: req.degradesTo,
        reason,
      };
    }
    return {
      alias: req.alias,
      interface: req.interface,
      scope: req.scope,
      presence: req.presence,
      status: 'unbound',
      reason,
    };
  });
  return { resolutions, ok: resolutions.every((r) => r.status !== 'unbound') };
}

/** Enforcement step: throw if any `required` capability is unbound. */
export function assertRequiredBound(report: ResolutionReport): void {
  const missing = report.resolutions.filter((r) => r.status === 'unbound');
  if (missing.length > 0) {
    const list = missing.map((r) => `${r.alias} (${r.interface}): ${r.reason}`).join('; ');
    throw new Error(`unbound required capabilities: ${list}`);
  }
}
