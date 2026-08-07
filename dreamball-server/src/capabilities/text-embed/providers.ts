/**
 * text-embed/1 — provider registry (PROTOTYPE).
 *
 * Two providers conform to the `text-embed/1` interface:
 *   - mock    → routes/embed.mock.ts   (deterministic, CI; 256d)
 *   - runpod  → ./runpod.ts            (remote GPU, Ollama qwen3; 1024d)
 *
 * The registry order is the binding priority (decision doc §9): mock → runpod
 * → (none → fail-fast).
 *
 * NO IN-PROCESS MODEL PROVIDER. There used to be a third, `onnx-local`,
 * wrapping `embedding/qwen3.ts`, which pulled `@huggingface/transformers`
 * (onnxruntime-node + sharp, ~600 MB installed) into an otherwise generic
 * protocol server. It was removed on 2026-08-07: hosting a model runtime is an
 * application concern, and this capability seam exists precisely so the model
 * lives on the far side of an interface rather than inside the server. A
 * consumer that wants local weights implements a `text-embed/1` provider in
 * its own process and points the server at it; it does not get to make every
 * `bun install` of the protocol server pay for ONNX. See
 * docs/decisions/2026-08-07-substrate-palace-boundary.md.
 *
 * Mock-import discipline: the mock impl is reached only via a *dynamic* import
 * inside the mock provider's embedRaw, executed solely when the mock provider is
 * selected (DREAMBALL_EMBED_MOCK=1). Nothing in the production import graph (which
 * flows index.ts -> resolver -> this file) statically references embed.mock —
 * the "production never reaches the mock" invariant (embed.mock.ts header)
 * holds, and the AC8 grep on index.ts stays clean.
 */

import {
  readRunpodConfig,
  embedViaRunpod,
  type RunpodConfig,
} from './runpod.js';
import type { TextEmbedProvider } from './interface.js';

// ---------------------------------------------------------------------------
// mock provider — deterministic, no model, CI seam
// ---------------------------------------------------------------------------

const mockProvider: TextEmbedProvider = {
  id: 'mock',
  category: 'service',
  implementsVersion: '1.0',
  nativeDim: 256,
  available: () => process.env.DREAMBALL_EMBED_MOCK === '1',
  load: async () => {
    /* nothing to load */
  },
  embedRaw: async (content) => {
    // Dynamic import keeps embed.mock out of the static production graph.
    const { mockEmbed } = await import('../../routes/embed.mock.js');
    return new Float32Array(await mockEmbed({ content, contentType: 'text/plain' }));
  },
};

// ---------------------------------------------------------------------------
// runpod provider — remote serverless GPU (BYO GPU exit)
//
// This is a ~120-line HTTP client with zero dependencies. It is the shape a
// provider is allowed to have inside the server: a wire adapter, not a runtime.
// ---------------------------------------------------------------------------

let _runpodCfg: RunpodConfig | null = null;

const runpodProvider: TextEmbedProvider = {
  id: 'runpod-serverless',
  category: 'service',
  implementsVersion: '1.0',
  nativeDim: 1024,
  available: () => readRunpodConfig() !== null,
  load: async () => {
    _runpodCfg = readRunpodConfig();
  },
  embedRaw: async (content) => {
    if (!_runpodCfg) throw new Error('runpod provider: load() not called');
    return embedViaRunpod(content, _runpodCfg);
  },
};

// ---------------------------------------------------------------------------
// Registry — order is binding priority
// ---------------------------------------------------------------------------

export const TEXT_EMBED_PROVIDERS: readonly TextEmbedProvider[] = [
  mockProvider,
  runpodProvider,
];
