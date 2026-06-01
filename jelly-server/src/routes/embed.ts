/**
 * POST /embed — Qwen3-Embedding-0.6B endpoint (S6.1).
 *
 * Wire shape per D-012 (authoritative):
 *   Request:  { content: string, contentType: SupportedContentType }
 *   Response: { vector: number[], model: string, dimension: number, truncation: string }
 *
 * The model is loaded ONCE at server boot via loadQwen3Model() in index.ts.
 * MRL truncation to 256d happens here, opaque to the client (AC3).
 *
 * Content-type allowlist (AC4): text/markdown, text/plain, text/asciidoc.
 * 415 on any unsupported value; 413 if content > 1 MB (AC5).
 * No batch or streaming endpoint exists (D-012 negative, AC6).
 *
 * TODO-EMBEDDING: bring-model-local-or-byo
 *   This route hosts Qwen3-Embedding-0.6B via onnxruntime-node.
 *   The model weights must be placed at JELLY_EMBED_MODEL_PATH before boot.
 *   See docs/decisions/2026-04-24-qwen3-embedding-loader.md.
 *
 * Decisions: D-012, D-002; NFR11 (sanctioned exit), NFR13, SEC6, SEC7.
 */

import Elysia, { t } from 'elysia';
import { resolveTextEmbed } from '../capabilities/text-embed/resolver.js';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
// model / dimension / truncation now come from the bound text-embed/1
// capability (capabilities/text-embed/interface.ts), not hardcoded here.

const MAX_CONTENT_BYTES = 1_048_576; // 1 MB

const SUPPORTED_CONTENT_TYPES = ['text/markdown', 'text/plain', 'text/asciidoc'] as const;

// ---------------------------------------------------------------------------
// Route
// ---------------------------------------------------------------------------

export const embedRoute = new Elysia().post(
  '/embed',
  async ({ body, set }) => {
    const { content, contentType } = body;

    // AC4: content-type allowlist (Elysia t.Union handles unknown values with 422,
    // but we want 415 — use runtime check for unsupported types in case of bypass)
    if (!(SUPPORTED_CONTENT_TYPES as readonly string[]).includes(contentType)) {
      set.status = 415;
      return {
        error: 'Unsupported Media Type',
        message: `contentType "${contentType}" is not supported`,
        supported: SUPPORTED_CONTENT_TYPES,
      };
    }

    // AC5: oversize guard (content is a string; byte length may differ from char count)
    const byteLength = new TextEncoder().encode(content).length;
    if (byteLength > MAX_CONTENT_BYTES) {
      set.status = 413;
      return {
        error: 'Content Too Large',
        message: `content exceeds the 1 MB limit (${byteLength} bytes > ${MAX_CONTENT_BYTES} bytes)`,
        limit_bytes: MAX_CONTENT_BYTES,
      };
    }

    // Resolve the text-embed/1 capability to its bound provider, then embed.
    // Selection (mock / runpod / onnx-local) happens once in the resolver, not
    // here — the route is provider-agnostic. resolveTextEmbed() is idempotent:
    // boot binds eagerly, this covers the lazy/test path.
    // TODO-EMBEDDING: bring-model-local-or-byo
    //   Provider binding lives in capabilities/text-embed/resolver.ts. See
    //   docs/decisions/2026-05-31-capability-provider-model.md.
    const embedder = await resolveTextEmbed();
    const vec256 = await embedder.embed(content); // Float32Array, MRL-truncated

    // D-012 response schema (shape declared by the text-embed/1 interface)
    return {
      vector: Array.from(vec256),
      model: embedder.modelIdentity,
      dimension: embedder.outputDim,
      truncation: embedder.truncation,
    };
  },
  {
    // D-012 request schema: content is t.String (scalar — no batch, no stream, AC6).
    // contentType is t.String (not t.Union) so unsupported values reach the 415 handler
    // rather than being rejected with Elysia's 422 schema-validation error (AC4).
    // The allowlist is enforced inside the handler via SUPPORTED_CONTENT_TYPES.
    body: t.Object({
      content: t.String({ minLength: 1 }),
      contentType: t.String(),
    }),
    detail: {
      summary: 'Compute a 256d embedding (Qwen3-Embedding-0.6B, MRL-truncated)',
      description:
        'Single POST /embed — one content string in, one 256d vector out (D-012). ' +
        'Sanctioned network exit for the memory-palace (NFR11). ' +
        'No batch or streaming variants exist by design.',
      tags: ['embedding'],
    },
  }
);
