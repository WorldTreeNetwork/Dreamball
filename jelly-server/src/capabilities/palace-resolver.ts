/**
 * palace-resolver.ts — binds the Memory Palace's declared capability needs.
 *
 * Wires the generated requirements manifest (`PALACE_CAPABILITIES`) to the
 * server's provider registry via the generic resolver (resolver-core.ts).
 *
 * Today the jelly-server runtime offers one capability provider family —
 * `service/text-embed` (mock / runpod / onnx-local) — so `embed` binds. The
 * other declared needs have no provider yet, and the report is honest about it:
 *   - `service/graph-store` (store) → unbound   ← roadmap: graph-store extraction
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

/** Provider descriptors the jelly-server runtime offers (service scope). */
export function buildServerRegistry(): ProviderRegistry {
  const textEmbed: CapabilityProviderDescriptor[] = TEXT_EMBED_PROVIDERS.map((p) => ({
    interface: 'service/text-embed',
    implementsVersion: p.implementsVersion,
    id: p.id,
    available: () => p.available(),
  }));
  return new Map([['service/text-embed', textEmbed]]);
}

/** Resolve the palace's declared capability needs against the server registry. */
export function resolvePalaceCapabilities(): ResolutionReport {
  return resolveCapabilities(PALACE_CAPABILITIES, buildServerRegistry());
}
