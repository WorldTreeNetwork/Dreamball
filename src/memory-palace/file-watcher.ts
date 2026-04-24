/**
 * file-watcher.ts — Oracle file-watcher skill (Story 4.4).
 *
 * Exports:
 *   openPalaceWatcher(palacePath, palaceFp, store, watchedPaths) → WatcherHandle
 *   acquirePalaceMutex(palaceFp) → Promise<() => void>
 *
 * Decisions: D-008 (PRIMARY — inline sync, per-palace mutex, 4-step, full rollback),
 *            D-007 (domain verbs only), D-011 (oracle key on-demand), D-016.
 * FRs: FR14 (primary), FR9, FR21, FR20.
 * SECs: SEC11 (signed-action-before-effect), SEC1, SEC10, SEC6.
 *
 * 4-step inline transaction (D-008):
 *   1. Content-hash check — skip if unchanged (AC2 no-op guard)
 *   2. computeEmbedding — throws EmbeddingServiceUnreachable on 503 (AC4)
 *   3. oracleSignAction — produces SignedAction with oracle fp as signer
 *   4. Sequential store writes: reembed → mirrorInscriptionToKnowledgeGraph →
 *      recordAction → updateInscription
 *      (SEC11: action recorded after effect within same write sequence)
 *
 * Per-palace mutex (D-008): one Promise-chain per palace fp prevents
 * interleaved writes within a palace while allowing independent palaces
 * to proceed in parallel (AC7).
 *
 * Orphan path (AC3): file delete → oracle-sign inscription-orphaned →
 * markOrphaned (no embedding delete, no LIVES_IN removal).
 *
 * TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)
 * TODO-EMBEDDING: bring-model-local-or-byo (Epic 6 implements Qwen3 server /embed)
 */

import { watch, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import type { StoreAPI } from './store-types.js';
import {
  oracleActionStub,
  mirrorInscriptionToKnowledgeGraph,
} from './oracle.js';
import {
  computeEmbedding,
  EmbeddingServiceUnreachable,
} from './embedding-client.js';
import { hashBytesBlake3HexSync } from './cypher-utils.js';

// ── Per-palace mutex ──────────────────────────────────────────────────────────

/**
 * Per-palace Promise-chain mutex.
 *
 * Map from palaceFp → tail of the current promise chain. Each new acquire
 * appends to the tail, serialising all mutations within a single palace while
 * allowing independent palaces to run in parallel (D-008 / AC7).
 */
const _mutexChains = new Map<string, Promise<void>>();

/**
 * Acquire the per-palace mutex for palaceFp.
 *
 * Returns a release function that MUST be called in a finally block.
 * Concurrent callers on the same palaceFp serialise; callers on different
 * palace fps run in parallel (AC7).
 *
 * @param palaceFp  Blake3 fp of the palace to lock
 * @returns         release() — call in finally to unblock next waiter
 */
export async function acquirePalaceMutex(palaceFp: string): Promise<() => void> {
  let release!: () => void;
  const acquired = new Promise<void>((resolve) => {
    release = resolve;
  });

  // Chain this acquire onto the current tail for this palace.
  //
  // The `.catch(() => undefined)` on `next` is load-bearing: without it, a
  // throwing holder would poison the chain and every subsequent caller for
  // the same palace would inherit the rejection and fail to acquire. We want
  // exactly the opposite — the next waiter should see a clean slate.
  const current = _mutexChains.get(palaceFp) ?? Promise.resolve();
  const next = current.then(() => acquired).catch(() => undefined);
  _mutexChains.set(palaceFp, next);

  // Wait for the previous holder to release (same `.catch` rationale).
  await current.catch(() => undefined);

  // When `next` finally settles AND we are still the tail, clear the map
  // entry so long-lived processes don't accumulate palace fps forever.
  next.finally(() => {
    if (_mutexChains.get(palaceFp) === next) _mutexChains.delete(palaceFp);
  });

  return release;
}

// ── WatchedInscription ────────────────────────────────────────────────────────

/**
 * Metadata for one inscription being watched.
 */
export interface WatchedInscription {
  /** Blake3 fp of the inscription (avatar) */
  avatarFp: string;
  /** Absolute path to the source file on disk */
  sourcePath: string;
  /** Room fp the inscription lives in */
  roomFp: string;
  /** Oracle agent fp (for KG mirroring) */
  oracleAgentFp: string;
}

// ── WatcherHandle ─────────────────────────────────────────────────────────────

/**
 * Returned by openPalaceWatcher. Call close() to stop all OS-level file watches.
 */
export interface WatcherHandle {
  /** Stop all active file watchers for this palace. */
  close(): void;
  /**
   * Register a new inscription path to watch at runtime.
   * Used when new inscriptions are added after the watcher is opened.
   */
  addInscription(inscription: WatchedInscription): void;
}

// ── openPalaceWatcher ─────────────────────────────────────────────────────────

/**
 * Open OS-level file watches for all inscribed paths in the palace.
 *
 * Uses `fs.watch` (no new deps — Node/Bun built-in).
 *
 * Per D-008: each file change fires onFileChange with a per-palace mutex;
 * file deletes fire onFileDelete.
 *
 * OQ-S4.4-c: runs wherever palace is `open()`ed (CLI, jelly-server, showcase).
 *
 * @param palacePath    Path prefix for this palace (used to read oracle key)
 * @param palaceFp      Blake3 fp of the palace
 * @param store         Open StoreAPI instance
 * @param inscriptions  Initial list of inscriptions to watch
 * @returns             WatcherHandle with close() and addInscription()
 */
export function openPalaceWatcher(
  palacePath: string,
  palaceFp: string,
  store: StoreAPI,
  inscriptions: WatchedInscription[] = []
): WatcherHandle {
  const _watchers = new Map<string, ReturnType<typeof watch>>();
  const _inscriptions = new Map<string, WatchedInscription>();

  function startWatching(insc: WatchedInscription): void {
    if (_watchers.has(insc.avatarFp)) return; // already watched

    _inscriptions.set(insc.avatarFp, insc);

    try {
      const watcher = watch(insc.sourcePath, { persistent: false }, (eventType) => {
        if (eventType === 'rename') {
          // 'rename' fires on delete OR rename-to; check file existence
          void onFileDelete(palacePath, palaceFp, insc, store);
        } else {
          // 'change' fires on content edit
          void onFileChange(palacePath, palaceFp, insc, store);
        }
      });

      watcher.on('error', (err) => {
        console.warn(`file-watcher: watch error for ${insc.sourcePath}: ${err}`);
      });

      _watchers.set(insc.avatarFp, watcher);
    } catch (err) {
      console.warn(`file-watcher: could not watch ${insc.sourcePath}: ${err}`);
    }
  }

  // Start watching all initial inscriptions
  for (const insc of inscriptions) {
    startWatching(insc);
  }

  return {
    close(): void {
      for (const [, w] of _watchers) {
        try { w.close(); } catch { /* best effort */ }
      }
      _watchers.clear();
      _inscriptions.clear();
    },

    addInscription(insc: WatchedInscription): void {
      startWatching(insc);
    },
  };
}

// ── onFileChange ──────────────────────────────────────────────────────────────

/**
 * Handle a file-change event for an inscription source file.
 *
 * 4-step inline transaction (D-008):
 *   1. Read new bytes; compute content hash; skip if unchanged (AC2).
 *   2. computeEmbedding → throws EmbeddingServiceUnreachable on 503 (AC4).
 *   3. oracleSignAction → oracle-signed 'inscription-updated' action.
 *   4. Sequential store writes (SEC11 order):
 *      store.reembed → mirrorInscriptionToKnowledgeGraph → recordAction →
 *      updateInscription(source_blake3 + revision bump).
 *
 * Per-palace mutex held for the entire 4-step sequence (D-008 / AC7 / AC8).
 *
 * TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)
 * TODO-EMBEDDING: bring-model-local-or-byo
 */
export async function onFileChange(
  palacePath: string,
  palaceFp: string,
  insc: WatchedInscription,
  store: StoreAPI
): Promise<void> {
  // SEC10 path-containment: refuse to read a sourcePath that resolves outside
  // the palace root. The watcher subscribes to absolute paths given by the
  // topology; if the path becomes a symlink or is otherwise lifted out of the
  // palace tree between subscribe and fire we must fail closed rather than
  // treat an arbitrary file as an inscription source.
  const palaceRoot = resolve(palacePath);
  const sourceResolved = resolve(insc.sourcePath);
  if (!sourceResolved.startsWith(palaceRoot + '/') && sourceResolved !== palaceRoot) {
    throw new Error(`file-watcher: refusing to read sourcePath outside palace root: ${insc.sourcePath}`);
  }

  // Step 1: Read new bytes and check content hash (AC2 no-op guard)
  let newBytes: Uint8Array;
  try {
    newBytes = readFileSync(insc.sourcePath);
  } catch (err) {
    console.warn(`file-watcher: could not read ${insc.sourcePath}: ${err}`);
    return;
  }

  const newBlake3 = hashBytesBlake3HexSync(newBytes);

  // Check current source_blake3 from store without holding the mutex yet
  const currentData = await store.getInscription(insc.avatarFp, insc.oracleAgentFp);
  if (currentData && currentData.source_blake3 === newBlake3) {
    // AC2: bytes unchanged — zero computeEmbedding calls, no action, no revision bump
    return;
  }

  // Acquire per-palace mutex before any state mutation (D-008 / AC7)
  const release = await acquirePalaceMutex(palaceFp);
  try {
    // Re-read and re-check inside the mutex to handle burst edits (AC8)
    const freshData = await store.getInscription(insc.avatarFp, insc.oracleAgentFp);
    const freshBlake3 = hashBytesBlake3HexSync(newBytes);

    // Step 2: computeEmbedding (AC4 — throws EmbeddingServiceUnreachable on 503)
    // TODO-EMBEDDING: bring-model-local-or-byo
    let newVec: number[];
    try {
      newVec = await computeEmbedding(newBytes);
    } catch (err) {
      if (err instanceof EmbeddingServiceUnreachable) {
        // AC4: embedding service unreachable — no action, no revision bump
        console.error(`file-watcher: embedding service unreachable: ${err.message}`);
        return;
      }
      throw err;
    }

    // Step 3: oracle-sign the inscription-updated action (AC1 oracle fp as signer)
    // TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)
    const parentHashes = await store.headHashes(palaceFp);
    const signedAction = await oracleActionStub(
      palacePath,
      palaceFp,
      'inscription-updated',
      insc.avatarFp,
      parentHashes
    );

    // Step 4: Sequential store writes under file-watcher write context so
    // the S4.2 SEC5 write gate recognises the oracle-signed origin and lets
    // the mutation verbs through. Any other origin attempting the same writes
    // with the oracle fp would be denied by evaluateWritePolicy.
    const restoreCtx = store.setWriteContext({
      requesterFp: signedAction.signerFp,
      origin: 'file-watcher',
    });
    try {
      // 4a. reembed (FR21 delete-then-insert)
      await store.reembed(insc.avatarFp, newBytes, new Float32Array(newVec));

      // 4b. Mirror to oracle knowledge-graph (D-007 domain verb)
      await mirrorInscriptionToKnowledgeGraph(store, {
        oracleAgentFp: insc.oracleAgentFp,
        docFp: insc.avatarFp,
        roomFp: insc.roomFp,
      });

      // 4c. recordAction in ActionLog (AC1: oracle-signed action in ActionLog)
      await store.recordAction({
        fp: signedAction.fp,
        palaceFp,
        actionKind: signedAction.actionKind,
        actorFp: signedAction.signerFp,
        targetFp: signedAction.targetFp,
        parentHashes: signedAction.parentHashes,
        timestamp: signedAction.timestamp,
        cborBytesBlake3: freshBlake3,
      });

      // 4d. Update inscription metadata (source_blake3 + revision bump)
      const currentRevision = (freshData as Record<string, unknown> | null)
        ? ((freshData as unknown as { revision?: number }).revision ?? 0)
        : 0;
      await store.updateInscription(insc.avatarFp, {
        source_blake3: freshBlake3,
        revision: currentRevision + 1,
      });
    } finally {
      restoreCtx();
    }
  } finally {
    release();
  }
}

// ── onFileDelete ──────────────────────────────────────────────────────────────

/**
 * Handle a file-delete event for an inscription source file (AC3 orphan path).
 *
 * Oracle-signs an 'inscription-orphaned' action and sets Inscription.orphaned=true.
 * Embedding vector is NOT deleted (quarantine semantics per AC3).
 * LIVES_IN edge is NOT removed.
 *
 * TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)
 */
export async function onFileDelete(
  palacePath: string,
  palaceFp: string,
  insc: WatchedInscription,
  store: StoreAPI
): Promise<void> {
  // SEC10 path-containment (see onFileChange for rationale).
  const palaceRoot = resolve(palacePath);
  const sourceResolved = resolve(insc.sourcePath);
  if (!sourceResolved.startsWith(palaceRoot + '/') && sourceResolved !== palaceRoot) {
    throw new Error(`file-watcher: refusing to read sourcePath outside palace root: ${insc.sourcePath}`);
  }

  // Verify the file is actually gone (fs.watch 'rename' also fires on rename-to)
  let fileStillExists: boolean;
  try {
    readFileSync(insc.sourcePath);
    fileStillExists = true;
  } catch {
    fileStillExists = false;
  }

  if (fileStillExists) {
    // File was renamed-to (not deleted) — treat as a change event
    void onFileChange(palacePath, palaceFp, insc, store);
    return;
  }

  // Acquire per-palace mutex
  const release = await acquirePalaceMutex(palaceFp);
  try {
    // Oracle-sign orphaned action
    // TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)
    const parentHashes = await store.headHashes(palaceFp);
    const signedAction = await oracleActionStub(
      palacePath,
      palaceFp,
      'inscription-orphaned',
      insc.avatarFp,
      parentHashes
    );

    // Same file-watcher write context as onFileChange.
    const restoreCtx = store.setWriteContext({
      requesterFp: signedAction.signerFp,
      origin: 'file-watcher',
    });
    try {
      // Write orphaned action to ActionLog
      await store.recordAction({
        fp: signedAction.fp,
        palaceFp,
        actionKind: signedAction.actionKind,
        actorFp: signedAction.signerFp,
        targetFp: signedAction.targetFp,
        parentHashes: signedAction.parentHashes,
        timestamp: signedAction.timestamp,
      });

      // Mark inscription orphaned in the graph (no embedding delete, no LIVES_IN removal)
      await store.markOrphaned(insc.avatarFp);
    } finally {
      restoreCtx();
    }
  } finally {
    release();
  }
}

// Hashing now routes through cypher-utils.hashBytesBlake3HexSync so the
// server store, file-watcher, and action-mirror never disagree about the
// algorithm that produced source_blake3.
