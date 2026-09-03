/**
 * capabilities-validate.ts — validator for the `x-capabilities` schema block.
 *
 * The executable form of the vocabulary specced in
 * docs/decisions/2026-05-31-capabilities-schema-vocabulary.md. This is the
 * validation pass a future Zig `gen_capabilities` projector will port +
 * extend (it also emits a typed requirements manifest); landed first in TS so
 * the contract is a green/red gate before we mutate any pinned schema.
 *
 * It does NOT touch wire bytes — `x-capabilities` is schema metadata, never on
 * the CBOR envelope (vocabulary §1). Validating a block here changes no
 * archiform fingerprint.
 *
 * CLI:  bun run scripts/capabilities-validate.ts <block.json>
 * Lib:  import { validateCapabilities } from './capabilities-validate.ts'
 */

/// <reference types="node" />
import { readFileSync } from 'node:fs';

// ---------------------------------------------------------------------------
// Closed sets (D-035 discipline: reject anything not enumerated here)
// ---------------------------------------------------------------------------

export const SCOPES = ['service', 'render'] as const;

export const SELECT_POLICIES = [
  'auto',
  'prefer-low-latency',
  'prefer-low-power',
  'prefer-quality',
  'prefer-local',
] as const;

/** `<scope>/<name>` — scope from SCOPES, kebab name. Major lives in `version`. */
const INTERFACE_RE = /^(service|render)\/[a-z][a-z0-9-]*$/;

/** caret/tilde/exact/bare semver range, or `*`. e.g. ^1, ^1.2, ~1.2.3, =1.2.3, 1.2 */
const VERSION_RE = /^(\*|[~^=]?\d+(\.\d+){0,2})$/;

/** discovery refs (vocabulary §6): registry / git / local. */
const SOURCE_RE =
  /^(aspects:(service|render)\/[a-z][a-z0-9-]*|github:[\w.-]+\/[\w.-]+(#[\w./-]+)?|file:.+)$/;

const ENTRY_FIELDS_COMMON = ['interface', 'version', 'params', 'select', 'source'] as const;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ValidationIssue {
  path: string;
  message: string;
}
export interface ValidationResult {
  ok: boolean;
  errors: ValidationIssue[];
  warnings: ValidationIssue[];
}

type Group = 'requires' | 'optional';

// ---------------------------------------------------------------------------
// validateCapabilities
// ---------------------------------------------------------------------------

export function validateCapabilities(block: unknown): ValidationResult {
  const errors: ValidationIssue[] = [];
  const warnings: ValidationIssue[] = [];
  const err = (path: string, message: string) => errors.push({ path, message });
  const warn = (path: string, message: string) => warnings.push({ path, message });

  if (!isObject(block)) {
    return { ok: false, errors: [{ path: 'x-capabilities', message: 'must be an object' }], warnings };
  }

  // Top-level: only `requires` and `optional` permitted.
  for (const key of Object.keys(block)) {
    if (key !== 'requires' && key !== 'optional') {
      err(`x-capabilities.${key}`, `unknown top-level key (allowed: requires, optional)`);
    }
  }

  for (const group of ['requires', 'optional'] as Group[]) {
    const grp = (block as Record<string, unknown>)[group];
    if (grp === undefined) continue;
    if (!isObject(grp)) {
      err(`x-capabilities.${group}`, 'must be an object map keyed by local alias');
      continue;
    }
    for (const [alias, entry] of Object.entries(grp)) {
      validateEntry(`x-capabilities.${group}.${alias}`, entry, group, err, warn);
    }
  }

  return { ok: errors.length === 0, errors, warnings };
}

function validateEntry(
  path: string,
  entry: unknown,
  group: Group,
  err: (p: string, m: string) => void,
  warn: (p: string, m: string) => void,
): void {
  if (!isObject(entry)) {
    err(path, 'requirement entry must be an object');
    return;
  }

  // Closed field set: common fields, plus `degradesTo` only on `optional`.
  const allowed = new Set<string>(ENTRY_FIELDS_COMMON);
  if (group === 'optional') allowed.add('degradesTo');
  for (const key of Object.keys(entry)) {
    if (!allowed.has(key)) {
      const why =
        key === 'degradesTo'
          ? 'degradesTo is only valid on `optional` entries'
          : `unknown field (allowed: ${[...allowed].join(', ')})`;
      err(`${path}.${key}`, why);
    }
  }

  // interface — required, `<scope>/<name>`.
  const iface = (entry as Record<string, unknown>).interface;
  if (iface === undefined) {
    err(`${path}.interface`, 'required');
  } else if (typeof iface !== 'string' || !INTERFACE_RE.test(iface)) {
    err(`${path}.interface`, `must be "<scope>/<name>" with scope in {${SCOPES.join(', ')}} (got ${JSON.stringify(iface)})`);
  }

  // version — optional range; warn if absent (pin a caret), error if malformed.
  const version = (entry as Record<string, unknown>).version;
  if (version === undefined) {
    warn(`${path}.version`, 'no version range — pin a caret (e.g. "^1") for reproducibility');
  } else if (typeof version !== 'string' || !VERSION_RE.test(version)) {
    err(`${path}.version`, `not a valid range (got ${JSON.stringify(version)}; e.g. "^1", "^1.2", "=1.2.3", "*")`);
  }

  // select — optional, closed policy set.
  const select = (entry as Record<string, unknown>).select;
  if (select !== undefined && !(SELECT_POLICIES as readonly unknown[]).includes(select)) {
    err(`${path}.select`, `must be one of: ${SELECT_POLICIES.join(', ')}`);
  }

  // source — optional, registry/git/local form.
  const source = (entry as Record<string, unknown>).source;
  if (source !== undefined && (typeof source !== 'string' || !SOURCE_RE.test(source))) {
    err(`${path}.source`, 'must be a registry (aspects:scope/name), git (github:owner/repo#ref), or local (file:path) ref');
  }

  // params — optional object.
  const params = (entry as Record<string, unknown>).params;
  if (params !== undefined && !isObject(params)) {
    err(`${path}.params`, 'must be an object');
  }

  // degradesTo — required on optional, forbidden on requires (forbidden handled above).
  if (group === 'optional') {
    const dt = (entry as Record<string, unknown>).degradesTo;
    if (dt === undefined) {
      err(`${path}.degradesTo`, 'required on `optional` entries (the fallback when unbound)');
    } else if (typeof dt !== 'string' || dt.length === 0) {
      err(`${path}.degradesTo`, 'must be a non-empty string naming the fallback behavior');
    }
  }
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

// ---------------------------------------------------------------------------
// CLI (Bun; no-op under node/vitest where import.meta.main is undefined)
// ---------------------------------------------------------------------------

if ((import.meta as { main?: boolean }).main) {
  const path = process.argv[2];
  if (!path) {
    console.error('usage: bun run scripts/capabilities-validate.ts <block.json>');
    process.exit(2);
  }
  const raw = JSON.parse(readFileSync(path, 'utf8'));
  // accept either a bare block or a schema with an `x-capabilities` key
  const block = isObject(raw) && 'x-capabilities' in raw ? raw['x-capabilities'] : raw;
  const result = validateCapabilities(block);
  for (const w of result.warnings) console.error(`warn  ${w.path}: ${w.message}`);
  for (const e of result.errors) console.error(`error ${e.path}: ${e.message}`);
  if (result.ok) {
    console.error(`ok    ${path} — x-capabilities valid (${result.warnings.length} warning(s))`);
    process.exit(0);
  }
  process.exit(1);
}
