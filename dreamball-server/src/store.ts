/**
 * Content-addressed filesystem store for DreamBall envelopes + secret keys.
 *
 * Layout:
 *   data/dreamballs/<fingerprint>.jelly       — RAW CBOR envelope bytes (authoritative)
 *   data/dreamballs/<fingerprint>.jelly.json  — JSON rendering (convenience, recomputable)
 *   data/keys/<fingerprint>.key               — 64 raw bytes, mode 0600
 *
 * Why store both CBOR and JSON: CBOR is authoritative (the bytes that were
 * signed). JSON is a cheap cache so `GET /dreamballs/:fp` doesn't have to
 * re-parse through WASM every request. If the JSON cache is missing we
 * rebuild it from CBOR on demand.
 *
 * Fingerprint is the base58 of the identity bytes (same filename format as
 * the CLI uses).
 */

import {
  readFileSync,
  writeFileSync,
  readdirSync,
  existsSync,
  mkdirSync,
  chmodSync
} from 'fs';
import { resolve, join } from 'path';
import { moduleDir } from './paths.js';

const DATA_DIR =
  process.env.JELLY_SERVER_DATA_DIR ??
  resolve(moduleDir(import.meta.url, import.meta.dir), '../data');
const DREAMBALL_DIR = join(DATA_DIR, 'dreamballs');
const KEY_DIR = join(DATA_DIR, 'keys');

function ensureDirs(): void {
  for (const dir of [DREAMBALL_DIR, KEY_DIR]) {
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  }
}

ensureDirs();

/** Derive the filesystem fingerprint from a parsed DreamBall JSON. */
export function fingerprintFrom(dreamball: Record<string, unknown>): string {
  const identity = dreamball['identity'];
  if (typeof identity !== 'string') throw new Error('DreamBall missing identity field');
  return identity.startsWith('b58:') ? identity.slice(4) : identity;
}

/** Store a DreamBall — writes both the raw CBOR bytes (.jelly) and the
 *  parsed JSON cache (.jelly.json). Returns the fingerprint. */
export function storeDreamBall(
  envelopeBytes: Uint8Array,
  dreamball: Record<string, unknown>
): string {
  const fp = fingerprintFrom(dreamball);
  const cborPath = join(DREAMBALL_DIR, `${fp}.jelly`);
  const jsonPath = join(DREAMBALL_DIR, `${fp}.jelly.json`);
  writeFileSync(cborPath, envelopeBytes);
  writeFileSync(jsonPath, JSON.stringify(dreamball, null, 2), 'utf-8');
  return fp;
}

/** Store the 64-byte Ed25519 secret key. Mode 0600. */
export function storeSecretKey(fingerprint: string, secretBytes: Uint8Array): void {
  const path = join(KEY_DIR, `${fingerprint}.key`);
  writeFileSync(path, secretBytes, { mode: 0o600 });
  try {
    chmodSync(path, 0o600);
  } catch {
    // chmod may fail on some platforms — not fatal
  }
}

/** Read the raw 64-byte secret back by fingerprint. Null if missing. */
export function loadSecretKey(fingerprint: string): Uint8Array | null {
  const path = join(KEY_DIR, `${fingerprint}.key`);
  if (!existsSync(path)) return null;
  return new Uint8Array(readFileSync(path));
}

/** Load a DreamBall's parsed JSON. Null if not found. */
export function loadDreamBall(fingerprint: string): Record<string, unknown> | null {
  const jsonPath = join(DREAMBALL_DIR, `${fingerprint}.jelly.json`);
  if (!existsSync(jsonPath)) return null;
  const text = readFileSync(jsonPath, 'utf-8');
  return JSON.parse(text) as Record<string, unknown>;
}

/** Load the raw CBOR envelope bytes by fingerprint. */
export function loadEnvelopeBytes(fingerprint: string): Uint8Array | null {
  const cborPath = join(DREAMBALL_DIR, `${fingerprint}.jelly`);
  if (!existsSync(cborPath)) return null;
  return new Uint8Array(readFileSync(cborPath));
}

/** List every stored DreamBall (parsed JSON form). */
export function listDreamBalls(): Array<{
  fingerprint: string;
  dreamball: Record<string, unknown>;
}> {
  if (!existsSync(DREAMBALL_DIR)) return [];
  return readdirSync(DREAMBALL_DIR)
    .filter((f) => f.endsWith('.jelly.json'))
    .map((f) => {
      const fp = f.slice(0, -'.jelly.json'.length);
      const text = readFileSync(join(DREAMBALL_DIR, f), 'utf-8');
      return { fingerprint: fp, dreamball: JSON.parse(text) as Record<string, unknown> };
    });
}

export function hasDreamBall(fingerprint: string): boolean {
  return existsSync(join(DREAMBALL_DIR, `${fingerprint}.jelly`));
}
