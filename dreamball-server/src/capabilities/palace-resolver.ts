/**
 * palace-resolver.ts — binds the Memory Palace's declared capability needs.
 *
 * Wires the generated requirements manifest (`PALACE_CAPABILITIES`) to the
 * server's provider registry via the generic resolver (resolver-core.ts).
 *
 * The dreamball-server runtime currently offers two capability provider families —
 * `service/text-embed` (mock / runpod / onnx-local) and `service/graph-store`
 * (the in-memory reference provider, conformance-verified). So:
 *   - `service/text-embed` (embed) → bound
 *   - `service/graph-store` (store) → bound (in-memory; ladybug-napi is next)
 *   - `render/omnispherical` (scene) → unbound  ← renderer-scope, browser-side
 *   - `service/vector-knn` (knn, optional) → degraded → "sequential-replay"
 *
 * The resolver REPORTS rather than throws (§10.6); callers choose when to
 * enforce via `assertRequiredBound`. We intentionally do NOT enforce at server
 * boot yet — the palace currently runs on its embedded store, not a resolved
 * `graph-store` provider; enforcing would falsely fail a working server.
 */

import { PALACE_CAPABILITIES } from '../../../src/lib/generated/palace-capabilities.js';
import {
  resolveCapabilities,
  type CapabilityProviderDescriptor,
  type ProviderRegistry,
  type ResolutionReport,
} from './resolver-core.js';
import { TEXT_EMBED_PROVIDERS } from './text-embed/providers.js';

/** Provider descriptors the dreamball-server runtime offers (service scope). */
export function buildServerRegistry(): ProviderRegistry {
  const textEmbed: CapabilityProviderDescriptor[] = TEXT_EMBED_PROVIDERS.map((p) => ({
    interface: 'service/text-embed',
    implementsVersion: p.implementsVersion,
    id: p.id,
    available: () => p.available(),
  }));
  // graph-store: the always-available in-memory reference provider (conformance-
  // verified in ./graph-store/conformance.ts). The persistent ladybug-napi
  // provider (preferred when LadybugDB's vector extension is present — Dreamball-7bc)
  // is a later increment and would register ahead of in-memory in priority order.
  const graphStore: CapabilityProviderDescriptor[] = [
    { interface: 'service/graph-store', implementsVersion: '1.0', id: 'in-memory', available: () => true },
  ];
  return new Map([
    ['service/graph-store', graphStore],
    ['service/text-embed', textEmbed],
  ]);
}

/** Resolve the palace's declared capability needs against the server registry. */
export function resolvePalaceCapabilities(): ResolutionReport {
  return resolveCapabilities(PALACE_CAPABILITIES, buildServerRegistry());
}
