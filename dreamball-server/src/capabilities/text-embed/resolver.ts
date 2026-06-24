/**
 * text-embed/1 — resolver (PROTOTYPE).
 *
 * The single binding point — the `ld.so` of this capability. It replaces the
 * env-var if/else that was previously split between routes/embed.ts (mock vs
 * qwen3) and embedding/qwen3.ts's loadQwen3Model (mock vs runpod vs local).
 *
 * resolveTextEmbed() walks the provider registry in priority order, binds the
 * first available provider, loads it, and caches the bound embedder. It is
 * idempotent: boot calls it eagerly (fail-fast); the route calls it lazily on
 * first request (covers test mode, where boot is skipped). Repeated calls reuse
 * the cached binding — so e.g. loadQwen3Model() is invoked at most once.
 *
 * The bound embedder normalizes any provider's raw vector to the interface's
 * OUTPUT_DIM via MRL prefix truncation (reusing qwen3.ts's truncateMrl — the
 * single truncation path). The route then sees one provider-agnostic call.
 *
 * See docs/decisions/2026-05-31-capability-provider-model.md §3, §9.
 */

import { truncateMrl } from '../../embedding/qwen3.js';
import { TEXT_EMBED_PROVIDERS } from './providers.js';
import {
  INTERFACE,
  OUTPUT_DIM,
  TRUNCATION,
  MODEL_IDENTITY,
  type BoundTextEmbedder,
} from './interface.js';

let _bound: BoundTextEmbedder | null = null;

/** Structured one-line log of a resolution outcome (matches server log style). */
function logResolution(providerId: string): void {
  process.stderr.write(
    JSON.stringify({
      ts: new Date().toISOString(),
      event: 'capability_resolved',
      capability: INTERFACE,
      provider: providerId,
    }) + '\n',
  );
}

/**
 * Bind a provider for `text-embed/1`. Idempotent — caches the first binding.
 *
 * @throws if no provider in the registry is available. The message names the
 *   degrade path the way the old loadQwen3Model fail-fast did.
 */
export async function resolveTextEmbed(): Promise<BoundTextEmbedder> {
  if (_bound) return _bound;

  const provider = TEXT_EMBED_PROVIDERS.find((p) => p.available());
  if (!provider) {
    throw new Error(
      `no provider available for capability ${INTERFACE}\n` +
        `bind one of: DREAMBALL_EMBED_MOCK=1 (mock), ` +
        `RUNPOD_SERVERLESS_ENDPOINT_ID+RUNPOD_API_KEY (runpod), ` +
        `or DREAMBALL_EMBED_MODEL_PATH (local ONNX; run scripts/download-embed-model.ts)`,
    );
  }

  await provider.load();

  _bound = {
    providerId: provider.id,
    modelIdentity: MODEL_IDENTITY,
    outputDim: OUTPUT_DIM,
    truncation: TRUNCATION,
    embed: async (content: string) => {
      const raw = await provider.embedRaw(content);
      return truncateMrl(raw, OUTPUT_DIM);
    },
  };

  logResolution(provider.id);
  return _bound;
}

/** Test/utility seam: drop the cached binding so the next resolve re-selects. */
export function resetTextEmbedBinding(): void {
  _bound = null;
}
