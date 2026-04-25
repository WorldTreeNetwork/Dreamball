/**
 * inscribe-bridge.ts — Orchestrates embedding + store ingestion for `jelly palace inscribe`
 * with `--embed-via` flag (S6.2).
 *
 * Exports:
 *   inscribeWithEmbedding(params) — online path: embed → recordAction → inscribeAvatar (SEC11)
 *   inscribeOffline(params)       — offline path: inscription-pending-embedding action → inscribeAvatar
 *   inferContentType(filePath)    — AC8: content-type from file extension
 *
 * SEC11 ordering (action-before-effect):
 *   1. recordAction('inscription-pending-embedding' or 'avatar-inscribed') FIRST.
 *   2. inscribeAvatar (store effect) SECOND.
 *   3. If recordAction throws → inscribeAvatar never called (rollback: store in pre-inscribe state).
 *
 * D-007: uses domain verbs only (inscribeAvatar, recordAction, upsertEmbedding).
 *        No raw Cypher here.
 * D-012: delegates all HTTP calls to embedFor() in embedding-client.ts.
 *        This module does NOT call fetch() directly.
 * NFR11: embedding-client.embedFor is the single sanctioned network exit.
 * NFR13: opt-in; only called when --embed-via is provided.
 * NFR15: TODO-EMBEDDING markers below.
 *
 * TODO-EMBEDDING: bring-model-local-or-byo
 *   inscribeWithEmbedding orchestrates the call to embedFor(), which is the
 *   live HTTP client for Qwen3-Embedding-0.6B (S6.1). When model weights are
 *   bundled locally (post-MVP), only embedding-client.ts changes — this module
 *   stays the same.
 */

import type { StoreAPI } from './store-types.js';
import { embedFor, EmbeddingServiceUnreachable } from './embedding-client.js';

// ── Content-type inference (AC8) ──────────────────────────────────────────────

/** Map of file extensions to MIME content types accepted by POST /embed. */
const EXTENSION_MAP: Record<string, string> = {
  '.md': 'text/markdown',
  '.markdown': 'text/markdown',
  '.txt': 'text/plain',
  '.adoc': 'text/asciidoc',
  '.asciidoc': 'text/asciidoc',
};

/**
 * Infer a content-type string from a file path's extension.
 *
 * AC8: .md → text/markdown; .txt → text/plain; .adoc → text/asciidoc;
 * anything else → text/plain with a stderr warning.
 *
 * @param filePath  Absolute or relative path to the source file.
 * @returns         MIME content-type string.
 */
export function inferContentType(filePath: string): string {
  const dotIdx = filePath.lastIndexOf('.');
  if (dotIdx !== -1) {
    const ext = filePath.slice(dotIdx).toLowerCase();
    const mapped = EXTENSION_MAP[ext];
    if (mapped) return mapped;
  }
  // AC8 fallback: unknown extension → text/plain with stderr warning
  process.stderr.write(
    `warning: unknown file extension for '${filePath}' — assuming text/plain\n`
  );
  return 'text/plain';
}

// ── InscribeParams ────────────────────────────────────────────────────────────

export interface InscribeParams {
  /** Open StoreAPI instance. */
  store: StoreAPI;
  /** Blake3 fp of the palace. */
  palaceFp: string;
  /** Blake3 fp of the target room. */
  roomFp: string;
  /** Blake3 fp of the inscription (avatar). */
  inscriptionFp: string;
  /** Blake3 fp of the signed action envelope. */
  actionFp: string;
  /** Blake3 hex of the source file bytes. */
  sourceBlake3: string;
  /** Blake3 fp of the actor (custodian). */
  actorFp: string;
  /** Parent action fps (DAG tips). */
  parentHashes: string[];
  /** Source file content as UTF-8 string (for embedding). */
  content: string;
  /** MIME content-type inferred from file extension (AC8). */
  contentType: string;
  /** Full URL for the /embed endpoint (default: http://localhost:9808/embed). */
  embedViaUrl?: string;
  /** Optional archiform fp for inscribeAvatar. */
  archiformFp?: string | null;
  /** ms-epoch timestamp for the action. */
  timestamp?: number;
}

// ── inscribeWithEmbedding (online path, AC1) ──────────────────────────────────

/**
 * Online path: compute embedding THEN record action THEN inscribe.
 *
 * SEC11 ordering:
 *   1. embedFor() — pure HTTP, no store effect.
 *   2. store.recordAction('avatar-inscribed') — action BEFORE effect.
 *   3. store.inscribeAvatar(... { embedding }) — store effect AFTER action.
 *   If step 2 throws → step 3 never runs.
 *
 * TODO-EMBEDDING: bring-model-local-or-byo
 *   embedFor is the live call to Qwen3-Embedding-0.6B /embed (S6.1 contract).
 *   When model weights are local, only embedding-client.ts changes here.
 *
 * @throws EmbeddingServiceUnreachable if embedViaUrl is unreachable — caller should
 *         fall back to inscribeOffline() for AC4 graceful degradation.
 */
export async function inscribeWithEmbedding(params: InscribeParams): Promise<void> {
  const {
    store,
    palaceFp,
    roomFp,
    inscriptionFp,
    actionFp,
    sourceBlake3,
    actorFp,
    parentHashes,
    content,
    contentType,
    embedViaUrl = 'http://localhost:9808/embed',
    archiformFp,
    timestamp,
  } = params;

  // Step 1: compute embedding (pure HTTP — no store effect yet)
  // TODO-EMBEDDING: bring-model-local-or-byo
  const vector = await embedFor(content, contentType, embedViaUrl);
  const embedding = new Float32Array(vector);

  const now = timestamp ?? Date.now();

  // SEC11 step 2: record action BEFORE any store effect
  await store.recordAction({
    fp: actionFp,
    palaceFp,
    actionKind: 'avatar-inscribed',
    actorFp,
    targetFp: inscriptionFp,
    parentHashes,
    timestamp: now,
    cborBytesBlake3: sourceBlake3,
  });

  // SEC11 step 3: store effect — only runs if recordAction succeeded
  await store.inscribeAvatar(roomFp, inscriptionFp, sourceBlake3, {
    embedding,
    archiform: archiformFp ?? undefined,
  });

  // Upsert embedding into vector index (D-007 verb — FR21)
  // TODO-EMBEDDING: bring-model-local-or-byo
  await store.upsertEmbedding(inscriptionFp, embedding);
}

// ── inscribeOffline (offline path, AC4) ───────────────────────────────────────

/**
 * Offline path: record inscription-pending-embedding action THEN inscribe WITHOUT embedding.
 *
 * SEC11 ordering:
 *   1. store.recordAction('inscription-pending-embedding') — action BEFORE effect.
 *   2. store.inscribeAvatar(... no embedding) — store effect AFTER action.
 *   If step 1 throws → step 2 never runs.
 *
 * AC4: inscription node committed WITHOUT embedding property (null/absent).
 * Palace verifies clean; open still renders the inscription (dimmed/untagged).
 */
export async function inscribeOffline(params: Omit<InscribeParams, 'content' | 'contentType' | 'embedViaUrl'>): Promise<void> {
  const {
    store,
    palaceFp,
    roomFp,
    inscriptionFp,
    actionFp,
    sourceBlake3,
    actorFp,
    parentHashes,
    archiformFp,
    timestamp,
  } = params;

  const now = timestamp ?? Date.now();

  // SEC11 step 1: record inscription-pending-embedding action BEFORE store effect
  await store.recordAction({
    fp: actionFp,
    palaceFp,
    actionKind: 'inscription-pending-embedding',
    actorFp,
    targetFp: inscriptionFp,
    parentHashes,
    timestamp: now,
    cborBytesBlake3: sourceBlake3,
  });

  // SEC11 step 2: store effect — only runs if recordAction succeeded
  // inscription committed WITHOUT embedding (null) — AC4
  await store.inscribeAvatar(roomFp, inscriptionFp, sourceBlake3, {
    embedding: null,
    archiform: archiformFp ?? undefined,
  });
}

// ── Re-export EmbeddingServiceUnreachable for bridge convenience ──────────────
export { EmbeddingServiceUnreachable };
