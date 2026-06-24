/**
 * text-embed/1 — provider registry (PROTOTYPE).
 *
 * Three providers conform to the `text-embed/1` interface, wrapping the existing
 * (tested) implementations rather than rewriting them:
 *   - mock        → routes/embed.mock.ts   (deterministic, CI; 256d)
 *   - runpod      → embedding/runpod.ts    (remote GPU, Ollama qwen3; 1024d)
 *   - onnx-local  → embedding/qwen3.ts     (local ONNX weights; 1024d)
 *
 * The registry order is the binding priority (decision doc §9). It reproduces
 * the precedence previously smeared across embed.ts and qwen3.ts's
 * loadQwen3Model: mock → runpod → local → (none → fail-fast).
 *
 * Mock-import discipline: the mock impl is reached only via a *dynamic* import
 * inside the mock provider's embedRaw, executed solely when the mock provider is
 * selected (JELLY_EMBED_MOCK=1). Nothing in the production import graph (which
 * flows index.ts -> resolver -> this file) statically references embed.mock —
 * the "production never reaches the mock" invariant (embed.mock.ts header)
 * holds, and the AC8 grep on index.ts stays clean.
 */

import { existsSync } from 'fs';
import {
  embed as qwen3EmbedRaw,
  loadQwen3Model,
} from '../../embedding/qwen3.js';
import {
  readRunpodConfig,
  embedViaRunpod,
  type RunpodConfig,
} from '../../embedding/runpod.js';
import type { TextEmbedProvider } from './interface.js';

// ---------------------------------------------------------------------------
// mock provider — deterministic, no model, CI seam
// ---------------------------------------------------------------------------

const mockProvider: TextEmbedProvider = {
  id: 'mock',
  category: 'service',
  implementsVersion: '1.0',
  nativeDim: 256,
  available: () => process.env.JELLY_EMBED_MOCK === '1',
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
// onnx-local provider — local ONNX weights (BYO weights exit)
// ---------------------------------------------------------------------------

function localModelPath(): string {
  return process.env.JELLY_EMBED_MODEL_PATH ?? './models/Qwen3-Embedding-0.6B-ONNX';
}

const onnxLocalProvider: TextEmbedProvider = {
  id: 'onnx-local',
  category: 'service',
  implementsVersion: '1.0',
  nativeDim: 1024,
  available: () => existsSync(localModelPath()),
  // Reuse the existing fail-fast singleton loader (keeps AC10's spy target alive).
  load: async () => {
    await loadQwen3Model();
  },
  embedRaw: (content) => qwen3EmbedRaw(content),
};

// ---------------------------------------------------------------------------
// Registry — order is binding priority
// ---------------------------------------------------------------------------

export const TEXT_EMBED_PROVIDERS: readonly TextEmbedProvider[] = [
  mockProvider,
  runpodProvider,
  onnxLocalProvider,
];
