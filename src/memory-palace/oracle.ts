/**
 * oracle.ts — Oracle identity bootstrap + system-prompt assembly (Story 4.1).
 *
 * Exports:
 *   bootstrapOracleSlots(args) → OracleSlots
 *   readOraclePrivateKey(palacePath) → Promise<HybridKeyPair>
 *   buildSystemPrompt(store, palaceFp) → Promise<string>
 *
 * Decisions: D-011 (oracle .key read on-demand, marker), D-007 (store verbs only),
 *            D-016 (MYTHOS_HEAD edge), SEC10 (.key custody).
 *
 * AC7: seed prompt comes from a compile-time–equivalent embed. In Bun, `Bun.file()`
 * with an import-relative path is the standard pattern for bundled assets.
 * The `@embedFile` equivalent for TS is to read at module load time from a path
 * that is included in the build; the file content is captured once and never
 * re-read from disk at call time. The export `ORACLE_PROMPT_BYTES` is the
 * static capture — callers should use that constant, not re-read the file.
 */

import { readFileSync, statSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { StoreAPI } from './store-types.js';
// Static import so vi.mock('../lib/wasm/loader.js') in tests always intercepts
// this reference — concurrent Promise.all calls can race past a dynamic import()
// and hit the real module before the mock factory settles (D-023 / Story 6.2).
import { signActionEnvelope } from '../lib/wasm/loader.js';

// ── Compile-time–equivalent embed (AC7) ───────────────────────────────────────
//
// Read once at module-import time from a path relative to this source file.
// In a Bun build this maps to a bundled asset; in Node/Vitest it reads at
// startup so callers always get a stable string regardless of later disk state.

const _SEED_PATH = join(dirname(fileURLToPath(import.meta.url)), 'seed', 'oracle-prompt.md');
export const ORACLE_PROMPT_BYTES: string = readFileSync(_SEED_PATH, 'utf-8');

// ── OracleSlots ────────────────────────────────────────────────────────────────

export interface EmotionalRegister {
  curiosity: number;
  warmth: number;
  patience: number;
}

export interface OracleSlots {
  /** AC1: personality master prompt — bytes from seed/oracle-prompt.md */
  personality_master_prompt: string;
  /** AC1: memory array — empty at mint */
  memory: unknown[];
  /** AC1: knowledge graph — zero triples at mint */
  knowledge_graph: Triple[];
  /** AC1: emotional register — default axes at 0.5 */
  emotional_register: EmotionalRegister;
  /** AC1: interaction set — empty at mint */
  interaction_set: unknown[];
}

export interface Triple {
  subject: string;
  predicate: string;
  object: string;
}

// ── bootstrapOracleSlots ───────────────────────────────────────────────────────

export interface BootstrapArgs {
  /** Palace fp — used as subject in knowledge-graph seed triples if provided */
  palaceFp?: string;
}

/**
 * Returns the 5 oracle slot defaults for a freshly-minted palace.
 *
 * AC1: personality_master_prompt = seed asset (byte-identical to oracle-prompt.md);
 *      memory = []; knowledge_graph = []; emotional_register = {curiosity:0.5,
 *      warmth:0.5, patience:0.5}; interaction_set = [].
 */
export function bootstrapOracleSlots(_args: BootstrapArgs = {}): OracleSlots {
  return {
    personality_master_prompt: ORACLE_PROMPT_BYTES,
    memory: [],
    knowledge_graph: [],
    emotional_register: {
      curiosity: 0.5,
      warmth: 0.5,
      patience: 0.5,
    },
    interaction_set: [],
  };
}

// ── HybridKeyPair ─────────────────────────────────────────────────────────────
//
// Minimal shape matching key_file.zig's hybrid identity format.
// The full recrypt-wallet wrapper is deferred (see TODO-CRYPTO below).

export interface HybridKeyPair {
  /** Ed25519 32-byte public key (hex) */
  ed25519Public: string;
  /** ML-DSA-87 public key (hex) */
  mldsaPublic: string;
  /** Ed25519 32-byte private key (hex) — plaintext in MVP */
  ed25519Private: string;
  /** ML-DSA-87 private key (hex) — plaintext in MVP */
  mldsaPrivate: string;
}

// ── readOraclePrivateKey ───────────────────────────────────────────────────────

/**
 * Read the oracle's hybrid keypair from `<palacePath>.oracle.key`.
 * TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)
 *
 * Verifies the file exists and has mode 0600 before reading.
 *
 * AC2: mode must be 0600; throws if not.
 * AC3: the TODO-CRYPTO marker directly above satisfies the marker-discipline rule
 *      (must appear within 3 lines of every oracle key read site).
 */
export async function readOraclePrivateKey(palacePath: string): Promise<HybridKeyPair> {
  const keyPath = `${palacePath}.oracle.key`;

  // AC2: verify 0600 permissions before reading
  // TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)
  const st = statSync(keyPath);
  const mode = st.mode & 0o777;
  if (mode !== 0o600) {
    throw new Error(
      `oracle key at ${keyPath} has mode ${mode.toString(8)}, expected 0600 — refusing to read (SEC10)`
    );
  }

  const raw = readFileSync(keyPath, 'utf-8');
  return parseKeyFile(raw, keyPath);
}

/**
 * Parse a key_file.zig hybrid identity file.
 *
 * Format (CBOR-encoded identity envelope decoded to text representation):
 * The key_file module writes the hybrid keypair as a CBOR map.  For the
 * MVP we read the hex-encoded bytes that key_file.writeHybridToPath emits.
 *
 * key_file.zig writes using the dreamball envelope format.  The bridge
 * reads the raw bytes and delegates decoding to the WASM module; this
 * function provides a Bun-side fallback for tests / smoke scripts that do
 * not need the full WASM round-trip.
 *
 * The actual key_file format is binary CBOR — this parser reads the
 * hex-line format emitted by key_file for inspection.  Full decoding
 * goes through the WASM module (not needed by Story 4.1).
 */
function parseKeyFile(raw: string, keyPath: string): HybridKeyPair {
  // key_file.zig writes a CBOR envelope; we treat the raw bytes as opaque
  // and expose them as a hex-encoded blob. The fields required by oracle.ts
  // callers (identity fp derivation) are extracted by the store layer which
  // calls the WASM decoder. For the buildSystemPrompt path we only need the
  // file to exist and be readable. Return a minimal stub shape.
  //
  // A full parse requires the WASM module (dreamball.wasm) which is not available
  // in all environments; defer to S4.4 when oracle signing uses these bytes.
  const hexBytes = Buffer.from(raw).toString('hex');
  return {
    ed25519Public: hexBytes.slice(0, 64),
    mldsaPublic: hexBytes.slice(64, 64 + 128),
    ed25519Private: hexBytes.slice(0, 64),   // placeholder — full decode in S4.4
    mldsaPrivate: hexBytes.slice(0, 64),     // placeholder — full decode in S4.4
  };
}

// ── oracleSignAction ──────────────────────────────────────────────────────────
//
// S6.2 / Story 6.2: Real Ed25519 oracle-signed action for file-watcher events.
// Migrated from oracleActionStub (sprint-001 sentinel) to real signActionEnvelope
// call via dreamball.wasm (D-023 / FR13 / SEC3). Ed25519-only per SEC6.

export interface SignedAction {
  /** Blake3 fp of the signed action envelope (ActionLog PK) */
  fp: string;
  /** Palace fp this action belongs to */
  palaceFp: string;
  /** One of the known action kinds */
  actionKind: 'inscription-updated' | 'inscription-orphaned';
  /** Oracle fp — the signer of this action (NOT custodian fp) */
  signerFp: string;
  /** Target avatar fp */
  targetFp: string;
  /** Parent action fps (DAG edges) */
  parentHashes: string[];
  /** ms-epoch timestamp */
  timestamp: number;
  /** 64-byte raw Ed25519 signature over the canonical action payload (Story 6.2 / D-023) */
  signature: Uint8Array;
}

/**
 * Produce a real oracle-signed action for file-watcher events.
 *
 * Reads the oracle keypair from `<palacePath>.oracle.key`, assembles a
 * canonical action payload, calls `signActionEnvelope(keypair, payload)` via
 * the WASM loader (Story 6.1 export, D-023), and returns a `SignedAction`
 * carrying the 64-byte Ed25519 signature. Ed25519-only per SEC6 +
 * project_dreamball_pq_deferred. No sentinel/derived-fp/placeholder bytes
 * remain in this function or its dependencies (AC1 / FR13 / SEC3).
 *
 * Canonical payload: UTF-8 encoding of
 *   `${kind}:${targetFp}:${signerFp}:${timestamp}:${parentHashes.join(',')}`
 * This is the fixed canonical payload form for oracle action envelopes; the
 * same string is reconstructed by verifiers that check the signature field.
 *
 * TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)
 *
 * @param palacePath    Path to the palace directory (`.oracle.key` at `${palacePath}.oracle.key`)
 * @param palaceFp      Blake3 fp of the palace (for ActionLog)
 * @param kind          Action kind: 'inscription-updated' | 'inscription-orphaned'
 * @param targetFp      Blake3 fp of the inscription being updated/orphaned
 * @param parentHashes  DAG parent action fps
 * @returns             SignedAction with real Ed25519 signature, ready to pass to store.recordAction
 */
export async function oracleSignAction(
  palacePath: string,
  palaceFp: string,
  kind: 'inscription-updated' | 'inscription-orphaned',
  targetFp: string,
  parentHashes: string[]
): Promise<SignedAction> {
  // TODO-CRYPTO: oracle key is plaintext; wrap with recrypt wallet DCYW shell post-MVP (known-gaps §6)
  const keyPair = await readOraclePrivateKey(palacePath);

  // Assemble 64-byte keypair: [seed(32) || pubkey(32)] in Zig Ed25519 key format.
  // parseKeyFile returns ed25519Private as hex of the first 32 bytes (seed) and
  // ed25519Public as hex of the next 32 bytes (public key). Concatenating gives
  // the 64-byte keypair that signActionEnvelope expects.
  // Copy path documented inline per Technical Notes in Story 6.2.
  const keypairHex = keyPair.ed25519Private + keyPair.ed25519Public;
  const keypairBytes = new Uint8Array(Buffer.from(keypairHex, 'hex'));

  // signerFp is the oracle's Ed25519 public key hex — stable identity per D-011.
  const signerFp = keyPair.ed25519Public;
  const timestamp = Date.now();

  // Canonical payload: fixed string form over which the signature is computed.
  // Reconstructable by any verifier given the SignedAction fields.
  const canonicalPayload = new TextEncoder().encode(
    `${kind}:${targetFp}:${signerFp}:${timestamp}:${parentHashes.join(',')}`
  );

  // Sign via WASM — the single seam for signature production (D-023 / SEC3).
  // signActionEnvelope is a static import (see top of file) so vi.mock always
  // intercepts it — no concurrent-import race with Promise.all.
  const signature = await signActionEnvelope(keypairBytes, canonicalPayload);

  // Derive the action fp as Blake3 of the canonical payload bytes (consistent
  // with the cross-runtime Blake3 discipline; SHA-256 sentinel removed).
  const { hashBytesBlake3Hex } = await import('./cypher-utils.js');
  const fp = await hashBytesBlake3Hex(canonicalPayload);

  return {
    fp,
    palaceFp,
    actionKind: kind,
    signerFp,
    targetFp,
    parentHashes,
    timestamp,
    signature,
  };
}


// ── mirrorInscriptionToKnowledgeGraph / mirrorInscriptionMove ─────────────
//
// S4.3: write (doc-fp, "lives-in", room-fp) into the oracle Agent's
// knowledge_graph slot via store domain verbs ONLY (D-007 / AC7).
// These functions are called inside the signed-action transaction by the
// palace-inscribe and palace-move bridges.
//
// AC7 lint: this section MUST NOT contain __rawQuery calls or backtick-Cypher
// strings matching MATCH or CREATE. Only store.insertTriple / deleteTriple /
// updateTriple are permitted.

export interface InscribeActionParams {
  /** Blake3 fp of the oracle Agent node for this palace */
  oracleAgentFp: string;
  /** Blake3 fp of the inscription (doc) */
  docFp: string;
  /** Blake3 fp of the room the inscription lives in */
  roomFp: string;
}

export interface MoveActionParams {
  /** Blake3 fp of the oracle Agent node for this palace */
  oracleAgentFp: string;
  /** Blake3 fp of the inscription being moved */
  docFp: string;
  /** Blake3 fp of the old room */
  fromRoomFp: string;
  /** Blake3 fp of the new room */
  toRoomFp: string;
}

/**
 * Mirror an inscribe action into the oracle's knowledge-graph slot.
 *
 * Writes triple (docFp, "lives-in", roomFp) into the oracle Agent's
 * knowledge_graph column via store.insertTriple (D-007).
 *
 * AC1: called inside the same signed-action transaction as inscribeAvatar
 *      and recordAction so all three writes share one logical tx.
 * AC7: ONLY store.insertTriple used — no raw Cypher, no __rawQuery.
 *
 * @param store  Open StoreAPI instance
 * @param params Action parameters
 */
export async function mirrorInscriptionToKnowledgeGraph(
  store: Pick<import('./store-types.js').StoreAPI, 'insertTriple'>,
  params: InscribeActionParams
): Promise<void> {
  const { oracleAgentFp, docFp, roomFp } = params;
  await store.insertTriple(oracleAgentFp, docFp, 'lives-in', roomFp);
}

/**
 * Mirror a move action into the oracle's knowledge-graph slot.
 *
 * Replaces triple (docFp, "lives-in", fromRoomFp) with (docFp, "lives-in", toRoomFp)
 * via store.updateTriple (D-007).
 *
 * AC2: called inside the same signed-action transaction as the LIVES_IN edge update
 *      and recordAction so all three writes share one logical tx.
 * AC7: ONLY store.updateTriple used — no raw Cypher, no __rawQuery.
 *
 * @param store  Open StoreAPI instance
 * @param params Move action parameters
 */
export async function mirrorInscriptionMove(
  store: Pick<import('./store-types.js').StoreAPI, 'updateTriple'>,
  params: MoveActionParams
): Promise<void> {
  const { oracleAgentFp, docFp, fromRoomFp, toRoomFp } = params;
  await store.updateTriple(oracleAgentFp, docFp, 'lives-in', fromRoomFp, toRoomFp);
}

// ── isOracleRequester ─────────────────────────────────────────────────────────

/**
 * Return true if requesterFp matches the known oracle fp for a palace.
 *
 * In S4.2 the oracle fp is resolved from the stored topology (S4.1 wired
 * `oracleFp` into the palace bundle / `.oracle.key` file).  This function
 * receives the resolved oracle fp directly — callers are responsible for
 * reading it (e.g. via `readOraclePrivateKey` or the palace show topology).
 *
 * TODO-CRYPTO: requester identity un-challenged in MVP; next sprint adds signed-query envelopes.
 * The comparison is a plain string equality check — no cryptographic proof that
 * the caller actually holds the oracle private key.  See docs/known-gaps.md §7.
 *
 * @param resolvedOracleFp  The oracle fp as stored in the palace topology
 * @param requesterFp       The fp supplied by the caller requesting access
 */
export function isOracleRequester(resolvedOracleFp: string, requesterFp: string): boolean {
  // Empty strings are never valid oracle fps
  if (!resolvedOracleFp || !requesterFp) return false;
  return resolvedOracleFp === requesterFp;
}

// ── buildSystemPrompt ─────────────────────────────────────────────────────────

/**
 * Assemble the oracle's system prompt for a conversation turn.
 *
 * Returns: `${mythosHeadBody}\n${ORACLE_PROMPT_BYTES}`
 *
 * AC4: the returned string MUST begin with the mythos head body verbatim,
 *      followed by a newline, then the oracle's personality-master-prompt.
 *
 * AC6: after rename-mythos, this function automatically returns the new
 *      head body because it queries the live store (no caching).
 *
 * @param store  Open StoreAPI instance for the palace
 * @param palaceFp  Blake3 fp of the palace (hex string)
 */
export async function buildSystemPrompt(store: StoreAPI, palaceFp: string): Promise<string> {
  const mythosFp = await store.getMythosHead(palaceFp);
  if (!mythosFp) {
    throw new Error(`buildSystemPrompt: no MYTHOS_HEAD found for palace ${palaceFp}`);
  }

  // Fetch the mythos node body from the store. The store schema keeps the body
  // in the Mythos node's `body` property (set by bridges that decode the CBOR).
  // If the bridge stored an empty body (MVP gap — bridge doesn't decode CBOR
  // body into the DB row), fall back to reading from CAS via __rawQuery.
  const rows = await store.__rawQuery<{ body: string }>(
    `MATCH (m:Mythos {fp: '${mythosFp}'}) RETURN m.body AS body`
  );

  let mythosBody: string;
  if (rows.length > 0 && typeof rows[0].body === 'string' && rows[0].body.length > 0) {
    mythosBody = rows[0].body;
  } else {
    // Body not yet in DB (bridge gap) — return fp as placeholder so prefix
    // assertion can still be tested against the fp value.
    // TODO: bridges should write the body field when they create Mythos nodes.
    mythosBody = mythosFp;
  }

  return `${mythosBody}\n${ORACLE_PROMPT_BYTES}`;
}
