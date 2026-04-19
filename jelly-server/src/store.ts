/**
 * Content-addressed filesystem store for DreamBalls and secret keys.
 *
 * Layout:
 *   data/dreamballs/<fingerprint>.jelly  — JSON-encoded DreamBall (readable)
 *   data/keys/<fingerprint>.key          — base58 secret key, mode 0600
 *
 * Fingerprint is the base58 encoding of the identity field extracted from
 * the DreamBall JSON (the "identity" field is already a "b58:..." string;
 * we strip the prefix to use as a filesystem-safe filename).
 */

import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, chmodSync } from 'fs';
import { resolve, join } from 'path';

const DATA_DIR = resolve(import.meta.dir, '../data');
const DREAMBALL_DIR = join(DATA_DIR, 'dreamballs');
const KEY_DIR = join(DATA_DIR, 'keys');

function ensureDirs() {
  for (const dir of [DREAMBALL_DIR, KEY_DIR]) {
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  }
}

ensureDirs();

export interface DreamBallRecord {
  fingerprint: string;
  dreamball: Record<string, unknown>;
  created_at: string;
}

/** Derive a filesystem fingerprint from a DreamBall's identity field. */
export function fingerprintFrom(dreamball: Record<string, unknown>): string {
  const identity = dreamball['identity'];
  if (typeof identity !== 'string') throw new Error('DreamBall missing identity field');
  // identity is "b58:..." — strip prefix for use as filename
  return identity.startsWith('b58:') ? identity.slice(4) : identity;
}

/** Store a DreamBall. Returns the fingerprint. */
export function storeDreamBall(dreamball: Record<string, unknown>): string {
  const fp = fingerprintFrom(dreamball);
  const path = join(DREAMBALL_DIR, `${fp}.jelly`);
  writeFileSync(path, JSON.stringify(dreamball, null, 2), { encoding: 'utf-8' });
  return fp;
}

/** Store a secret key (0600 permissions). */
export function storeSecretKey(fingerprint: string, secretKeyB58: string): void {
  const path = join(KEY_DIR, `${fingerprint}.key`);
  writeFileSync(path, secretKeyB58, { encoding: 'utf-8', mode: 0o600 });
  try {
    chmodSync(path, 0o600);
  } catch {
    // chmod may fail on some platforms — not fatal
  }
}

/** Load a DreamBall by fingerprint. Returns null if not found. */
export function loadDreamBall(fingerprint: string): Record<string, unknown> | null {
  const path = join(DREAMBALL_DIR, `${fingerprint}.jelly`);
  if (!existsSync(path)) return null;
  const text = readFileSync(path, 'utf-8');
  return JSON.parse(text) as Record<string, unknown>;
}

/** List all stored DreamBalls. */
export function listDreamBalls(): Array<{ fingerprint: string; dreamball: Record<string, unknown> }> {
  if (!existsSync(DREAMBALL_DIR)) return [];
  return readdirSync(DREAMBALL_DIR)
    .filter((f) => f.endsWith('.jelly'))
    .map((f) => {
      const fp = f.slice(0, -6); // strip .jelly
      const text = readFileSync(join(DREAMBALL_DIR, f), 'utf-8');
      return { fingerprint: fp, dreamball: JSON.parse(text) as Record<string, unknown> };
    });
}

/** Check if a fingerprint exists in the store. */
export function hasDreamBall(fingerprint: string): boolean {
  return existsSync(join(DREAMBALL_DIR, `${fingerprint}.jelly`));
}
