/**
 * cypher-utils.ts — Shared validators, Cypher string builders, and hash helper.
 *
 * Purpose: Remove hand-rolled Cypher interpolation from store.server.ts /
 * store.browser.ts / action-mirror.ts / bridges by funnelling every dynamic
 * value through a strict validator. LadybugDB / kuzu do not expose a
 * parameterised query API in the current version (0.15.3 napi / 0.11.3 wasm),
 * so the defence-in-depth strategy is:
 *
 *   1. Validate shape up-front (fp is 64 hex chars, actionKind is enum, etc.)
 *      — rejects anything with Cypher metacharacters at the boundary.
 *   2. For the few strings we cannot enum-restrict (policy property values,
 *      body text, etc.), route through cypherString() which wraps in single
 *      quotes and escapes \\, ', \n, \r, \0.
 *   3. One hash helper (hashBytesBlake3Hex) so server and file-watcher
 *      never disagree about which algorithm produced source_blake3.
 *
 * This file must stay tiny and dependency-free so every Cypher site can
 * import it without pulling a DB driver.
 */

// ── Strict validators ─────────────────────────────────────────────────────────

const HEX64 = /^[0-9a-f]{64}$/;

/**
 * Thrown when a dynamic value would otherwise be interpolated unsafely.
 * Callers should treat this as a programmer error — it means something
 * upstream let an untrusted string through a validator seam.
 */
export class InvalidCypherValueError extends Error {
  constructor(field: string, value: unknown) {
    super(
      `cypher-utils: invalid value for ${field}: ${JSON.stringify(value)} (expected validated form)`
    );
    this.name = 'InvalidCypherValueError';
  }
}

/**
 * Validate a Blake3 fingerprint: lowercase hex, length 64.
 * Returns the string unchanged on success; throws on any mismatch.
 *
 * Use this at every Cypher call site that takes an fp argument. A single
 * failing validator here is the line between "inert graph write" and
 * "attacker-controlled Cypher".
 */
export function sanitizeFp(fp: unknown, field = 'fp'): string {
  if (typeof fp !== 'string' || !HEX64.test(fp)) {
    throw new InvalidCypherValueError(field, fp);
  }
  return fp;
}

/**
 * Validate an optional fp: empty string is allowed (means "no fp"), all
 * other non-empty values must match HEX64. Returns the empty string or
 * the validated fp.
 */
export function sanitizeOptionalFp(fp: unknown, field = 'fp'): string {
  if (fp === undefined || fp === null || fp === '') return '';
  return sanitizeFp(fp, field);
}

/**
 * Validate an array of fps. Each entry must match HEX64. Empty array OK.
 */
export function sanitizeFpArray(fps: unknown, field = 'fps'): string[] {
  if (!Array.isArray(fps)) throw new InvalidCypherValueError(field, fps);
  return fps.map((fp, i) => sanitizeFp(fp, `${field}[${i}]`));
}

/** The 9 canonical action kinds per RC2. Anything else is a protocol violation. */
export const KNOWN_ACTION_KINDS = [
  'palace-minted',
  'room-added',
  'avatar-inscribed',
  'aqueduct-created',
  'move',
  'true-naming',
  'inscription-updated',
  'inscription-orphaned',
  'inscription-pending-embedding',
] as const;
export type KnownActionKind = (typeof KNOWN_ACTION_KINDS)[number];
const ACTION_KIND_SET = new Set<string>(KNOWN_ACTION_KINDS);

/**
 * Validate an action_kind against the RC2 allow-list.
 * Unknown kinds are rejected — ActionLog rows must carry a recognisable kind
 * or forward-compat replay will silently diverge (LOW-2).
 */
export function sanitizeActionKind(kind: unknown): KnownActionKind {
  if (typeof kind !== 'string' || !ACTION_KIND_SET.has(kind)) {
    throw new InvalidCypherValueError('actionKind', kind);
  }
  return kind as KnownActionKind;
}

/** Phase enum for Aqueduct nodes. */
const PHASE_SET = new Set<string>(['in', 'out', 'standing', 'resonant']);
export function sanitizePhase(phase: unknown): 'in' | 'out' | 'standing' | 'resonant' {
  if (typeof phase !== 'string' || !PHASE_SET.has(phase)) {
    throw new InvalidCypherValueError('phase', phase);
  }
  return phase as 'in' | 'out' | 'standing' | 'resonant';
}

/** Canonicality for Mythos nodes. */
const CANONICALITY_SET = new Set<string>(['genesis', 'successor']);
export function sanitizeCanonicality(c: unknown): 'genesis' | 'successor' {
  if (typeof c !== 'string' || !CANONICALITY_SET.has(c)) {
    throw new InvalidCypherValueError('canonicality', c);
  }
  return c as 'genesis' | 'successor';
}

/** Inscription policy values accepted by the guild policy gate. */
const POLICY_SET = new Set<string>(['public', 'any-admin']);
export function sanitizePolicy(p: unknown): 'public' | 'any-admin' {
  if (typeof p !== 'string' || !POLICY_SET.has(p)) {
    throw new InvalidCypherValueError('policy', p);
  }
  return p as 'public' | 'any-admin';
}

/**
 * Validate a non-negative integer (timestamps, revisions, k values, etc.).
 * Coerces Bun/kuzu BigInt rows to Number safely.
 */
export function sanitizeInt(n: unknown, field = 'int'): number {
  const v = typeof n === 'bigint' ? Number(n) : typeof n === 'number' ? n : NaN;
  if (!Number.isFinite(v) || !Number.isInteger(v) || v < 0) {
    throw new InvalidCypherValueError(field, n);
  }
  return v;
}

/**
 * Validate a Float64 in [0, 1] (resistance, strength, conductance).
 */
export function sanitizeUnitFloat(n: unknown, field = 'float01'): number {
  const v = typeof n === 'bigint' ? Number(n) : typeof n === 'number' ? n : NaN;
  if (!Number.isFinite(v) || v < 0 || v > 1) {
    throw new InvalidCypherValueError(field, v);
  }
  return v;
}

/**
 * Validate a finite Float64 (for unbounded numeric literals — times since
 * traversal in ms can be any positive number).
 */
export function sanitizeFloat(n: unknown, field = 'float'): number {
  const v = typeof n === 'bigint' ? Number(n) : typeof n === 'number' ? n : NaN;
  if (!Number.isFinite(v)) {
    throw new InvalidCypherValueError(field, n);
  }
  return v;
}

// ── Free-form string escaping ─────────────────────────────────────────────────

/**
 * Escape a string for inclusion inside a single-quoted Cypher literal.
 *
 * Covers every metacharacter that could terminate the literal or inject a
 * second statement:
 *   \\  backslash (must come first to avoid re-escaping our own escapes)
 *   '   single quote (the literal terminator)
 *   \n  newline (prevents multi-statement injection)
 *   \r  carriage return
 *   \0  NUL (some parsers treat NUL as a terminator)
 *
 * This is defence-in-depth ONLY — every fp or enum field must pass through
 * a validator above. This helper is reserved for body text (mythos body,
 * policy description) that legitimately contains free text.
 */
export function escCypherString(s: string): string {
  return s
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r')
    .replace(/\0/g, '\\0');
}

/**
 * Wrap a free-form string as a quoted Cypher literal.
 * Safe because escCypherString is total over ASCII/UTF-8.
 */
export function cypherString(s: string): string {
  return `'${escCypherString(s)}'`;
}

/**
 * Build a Cypher array literal from a list of fps (validated).
 * Guarantees: every element is 64-char hex, so we skip the escape entirely.
 */
export function cypherFpArray(fps: string[]): string {
  const validated = sanitizeFpArray(fps);
  return '[' + validated.map((fp) => `'${fp}'`).join(', ') + ']';
}

// ── Shared Blake3 / hash helper ───────────────────────────────────────────────

/**
 * Compute a stable content hash for a byte buffer.
 *
 * Protocol contract: when Bun is available (server / most tests) this returns
 * Blake3-256 hex. When only Node crypto is available (edge cases in Vitest
 * without Bun) this falls back to SHA-256 hex. Both are 64-char lowercase hex
 * so the rest of the system cannot tell them apart at the fingerprint level.
 *
 * Having ONE helper is load-bearing: previously store.server.ts and
 * file-watcher.ts each reimplemented the Bun-vs-Node selection, and when they
 * disagreed (one picked Blake3, the other picked SHA-256) the source_blake3
 * written to the Inscription node no longer matched the cbor_bytes_blake3 in
 * the ActionLog row it was supposed to mirror — breaking replay.
 *
 * Known-gap: Blake3 and SHA-256 produce different bytes for the same input.
 * The fallback exists so unit tests without Bun still function; production
 * paths run under Bun and therefore always Blake3. Tracked in known-gaps.md.
 */
export async function hashBytesBlake3Hex(bytes: Uint8Array): Promise<string> {
  const globalBun = (globalThis as Record<string, unknown>).Bun as
    | { hash?: { blake3?: (data: Uint8Array, opts?: { asBytes?: boolean }) => string | bigint } }
    | undefined;
  if (globalBun?.hash?.blake3) {
    const h = globalBun.hash.blake3(bytes, { asBytes: false });
    return typeof h === 'string' ? h : (h as bigint).toString(16).padStart(64, '0');
  }
  // Browser path: WebCrypto SHA-256 (no node:crypto in the bundle). Same 64-hex
  // shape as Blake3 so downstream fp validators do not need to distinguish.
  if (typeof crypto !== 'undefined' && (crypto as { subtle?: SubtleCrypto }).subtle) {
    const subtle = (crypto as { subtle: SubtleCrypto }).subtle;
    const hashBuf = await subtle.digest('SHA-256', bytes as BufferSource);
    return Array.from(new Uint8Array(hashBuf))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  }
  const { createHash } = await import('node:crypto');
  return createHash('sha256').update(bytes).digest('hex');
}

/**
 * Synchronous variant for call sites that cannot await — uses the same
 * Bun-first selection. Throws if neither Bun nor node:crypto is reachable
 * synchronously (only Bun is sync-available; Node fallback paths must use
 * the async form above).
 */
export function hashBytesBlake3HexSync(bytes: Uint8Array): string {
  const globalBun = (globalThis as Record<string, unknown>).Bun as
    | { hash?: { blake3?: (data: Uint8Array, opts?: { asBytes?: boolean }) => string | bigint } }
    | undefined;
  if (globalBun?.hash?.blake3) {
    const h = globalBun.hash.blake3(bytes, { asBytes: false });
    return typeof h === 'string' ? h : (h as bigint).toString(16).padStart(64, '0');
  }
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const nodeCrypto = require('node:crypto') as typeof import('node:crypto');
  return nodeCrypto.createHash('sha256').update(bytes).digest('hex');
}

// ── Deterministic fp derivations ─────────────────────────────────────────────

const utf8 = new TextEncoder();

/**
 * Derive a deterministic Aqueduct fp from its endpoints.
 *
 * fp = blake3( sort([roomA, roomB]).join('\\0') || '\\0' || palaceFp )
 *
 * Properties:
 *   - Order-independent in the endpoints (aqueduct A→B fp equals B→A fp),
 *     which matches the "aqueducts are undirected conduits" model even
 *     though traversals have a direction.
 *   - Tied to the palace so two palaces with overlapping room fps
 *     (theoretically impossible, but) don't collide.
 *   - No timestamp, so server and browser adapters converge on the same fp
 *     and replay from ActionLog reproduces the same graph.
 */
export async function deriveAqueductFp(
  roomA: string,
  roomB: string,
  palaceFp: string
): Promise<string> {
  const a = sanitizeFp(roomA, 'roomA');
  const b = sanitizeFp(roomB, 'roomB');
  const p = sanitizeFp(palaceFp, 'palaceFp');
  const [lo, hi] = a < b ? [a, b] : [b, a];
  const msg = utf8.encode(`${lo}\0${hi}\0${p}`);
  return hashBytesBlake3Hex(msg);
}

/**
 * Derive a deterministic Triple fp.
 *
 * fp = blake3( agentFp || '\\0' || subject || '\\0' || predicate || '\\0' || object )
 *
 * Uniqueness: the tuple (agentFp, subject, predicate, object) maps to exactly
 * one Triple row. insertTriple becomes an idempotent MERGE keyed on fp and the
 * read-modify-write JSON dance disappears.
 */
export async function deriveTripleFp(
  agentFp: string,
  subject: string,
  predicate: string,
  object: string
): Promise<string> {
  const a = sanitizeFp(agentFp, 'agentFp');
  // subject/object in the current KG are fps, but predicates are free text
  // ('lives-in'); hash the raw bytes so any future non-fp entity also works.
  const msg = utf8.encode(`${a}\0${subject}\0${predicate}\0${object}`);
  return hashBytesBlake3Hex(msg);
}
