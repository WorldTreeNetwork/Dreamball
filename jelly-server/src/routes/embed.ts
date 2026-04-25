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
import { embed as qwen3Embed, truncateMrl } from '../embedding/qwen3.js';
import { mockEmbed } from './embed.mock.js';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MODEL_NAME = 'qwen3-embedding-0.6b';
const OUTPUT_DIM = 256;
const TRUNCATION = 'mrl-256';
const MAX_CONTENT_BYTES = 1_048_576; // 1 MB

const SUPPORTED_CONTENT_TYPES = ['text/markdown', 'text/plain', 'text/asciidoc'] as const;
type SupportedContentType = typeof SUPPORTED_CONTENT_TYPES[number];

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

    // Compute embedding: mock mode or real Qwen3
    let vec256: number[];

    if (process.env.JELLY_EMBED_MOCK === '1') {
      // Test seam: use deterministic mock (AC8)
      vec256 = await mockEmbed({ content, contentType });
    } else {
      // Production: Qwen3-Embedding-0.6B via onnxruntime-node (AC1, AC3)
      // TODO-EMBEDDING: bring-model-local-or-byo
      //   The model is loaded at boot by loadQwen3Model() in index.ts.
      //   If JELLY_EMBED_MODEL_PATH is absent, boot will have already failed.
      const raw1024 = await qwen3Embed(content);
      const truncated = truncateMrl(raw1024, OUTPUT_DIM);
      vec256 = Array.from(truncated);
    }

    // D-012 response schema
    return {
      vector: vec256,
      model: MODEL_NAME,
      dimension: OUTPUT_DIM,
      truncation: TRUNCATION,
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
