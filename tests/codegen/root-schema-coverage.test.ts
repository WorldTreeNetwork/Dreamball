/**
 * Story 1.2 — root schema coverage + metaschema-validity test.
 *
 * AC1 + AC5 — every root field name in `src/protocol_v2.zig`
 *   (and the core types in `src/protocol.zig`) MUST appear in
 *   `schemas/root-2.0.0.json`. Missing field => test fails naming
 *   the field.
 *
 * AC3 — `schemas/root-2.0.0.json` validates against the JSON Schema
 *   draft 2020-12 metaschema with zero errors.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Ajv2020 } from 'ajv/dist/2020.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');
const SCHEMA_PATH = join(REPO_ROOT, 'schemas', 'root-2.0.0.json');
const PROTOCOL_V2_PATH = join(REPO_ROOT, 'src', 'protocol_v2.zig');
const PROTOCOL_PATH = join(REPO_ROOT, 'src', 'protocol.zig');

const schemaJson = readFileSync(SCHEMA_PATH, 'utf8');
const schema = JSON.parse(schemaJson);

/**
 * Convert a Zig snake_case field name to the kebab-case wire form
 * conventional in this protocol (e.g. `last_recalled` -> `last-recalled`).
 * Non-snake fields pass through unchanged.
 */
function toWireName(zigName: string): string {
	return zigName.replaceAll('_', '-');
}

/**
 * Walk a nested schema object and collect every property name that
 * appears under a `properties` block (recursively, including inside
 * `$defs`, `oneOf`, `items`).
 */
function collectAllPropertyNames(node: unknown, acc: Set<string>): void {
	if (!node || typeof node !== 'object') return;
	const obj = node as Record<string, unknown>;
	if (obj.properties && typeof obj.properties === 'object') {
		for (const key of Object.keys(obj.properties as object)) {
			acc.add(key);
			collectAllPropertyNames((obj.properties as Record<string, unknown>)[key], acc);
		}
	}
	if (obj.$defs) {
		for (const v of Object.values(obj.$defs as Record<string, unknown>)) {
			collectAllPropertyNames(v, acc);
		}
	}
	if (obj.items) collectAllPropertyNames(obj.items, acc);
	if (obj.oneOf && Array.isArray(obj.oneOf)) {
		for (const v of obj.oneOf) collectAllPropertyNames(v, acc);
	}
	if (obj.anyOf && Array.isArray(obj.anyOf)) {
		for (const v of obj.anyOf) collectAllPropertyNames(v, acc);
	}
}

/**
 * Walk the schema and collect every `$defs` type name (e.g. "Memory",
 * "Action"). These represent root types each Zig struct must map to.
 */
function collectDefNames(s: unknown): Set<string> {
	const out = new Set<string>();
	if (s && typeof s === 'object' && '$defs' in s) {
		const defs = (s as { $defs: Record<string, unknown> }).$defs;
		for (const k of Object.keys(defs)) out.add(k);
	}
	return out;
}

/**
 * Lightweight Zig struct extractor. Finds `pub const <Name> = struct {`
 * blocks and each field declared inside them up to the matching closing
 * brace. Skips fields inside method bodies by ignoring `pub fn` blocks.
 *
 * NOT a full Zig parser; sufficient for the canonical struct-shape
 * declarations in protocol.zig + protocol_v2.zig.
 */
interface ZigStruct {
	name: string;
	fields: string[];
}

function extractZigStructs(zigSource: string): ZigStruct[] {
	const out: ZigStruct[] = [];
	// Match `pub const Name = struct {` or `pub const Name = enum {` —
	// for coverage we only need the struct fields. Enums are matched in
	// the schema as `$defs` types (closed enums) and don't have field
	// names to cross-check.
	const structHeader = /pub const (\w+) = struct \{/g;
	let m: RegExpExecArray | null;
	while ((m = structHeader.exec(zigSource)) !== null) {
		const name = m[1];
		const startIdx = m.index + m[0].length;
		// Find the matching closing brace, handling nested `{}` pairs.
		let depth = 1;
		let i = startIdx;
		while (i < zigSource.length && depth > 0) {
			const ch = zigSource[i];
			if (ch === '{') depth += 1;
			else if (ch === '}') depth -= 1;
			i += 1;
		}
		const body = zigSource.slice(startIdx, i - 1);

		// Strip method bodies. `pub fn name(...) ... { ... }` blocks
		// contain unrelated code; skip them so we don't pick up local
		// variable names as fields.
		const noMethods = stripMethodBodies(body);

		// A "field" is `name: type [= default],` at the top level of
		// the struct body. Pattern: identifier (snake or single-word)
		// followed by a colon and type expression, terminating in `,`
		// at this depth.
		const fields: string[] = [];
		const fieldRe = /(?:^|\n)\s*(?!pub\b|const\b|fn\b|test\b|comptime\b)([a-z_][a-z0-9_]*)\s*:/gi;
		let fm: RegExpExecArray | null;
		while ((fm = fieldRe.exec(noMethods)) !== null) {
			fields.push(fm[1]);
		}
		out.push({ name, fields });
	}
	return out;
}

/**
 * Remove `pub fn ... { ... }` and `fn ... { ... }` blocks from a struct
 * body so the field-extraction pass doesn't pick up locals.
 */
function stripMethodBodies(src: string): string {
	let out = '';
	let i = 0;
	while (i < src.length) {
		// Detect `pub fn`, `fn `, or top-level `test "..."` (Zig test blocks).
		const rest = src.slice(i);
		const fnMatch = /^(?:pub\s+)?fn\s+\w+\s*\([^)]*\)/.exec(rest);
		const testMatch = /^test\s+"[^"]*"\s*/.exec(rest);
		const mm = fnMatch ?? testMatch;
		if (mm) {
			// Skip past the signature/header to the opening brace.
			let j = i + mm[0].length;
			while (j < src.length && src[j] !== '{') j += 1;
			if (j === src.length) break;
			let depth = 1;
			j += 1;
			while (j < src.length && depth > 0) {
				if (src[j] === '{') depth += 1;
				else if (src[j] === '}') depth -= 1;
				j += 1;
			}
			i = j;
			out += '\n';
			continue;
		}
		out += src[i];
		i += 1;
	}
	return out;
}

/**
 * Whitelist of Zig struct names that are intentionally NOT root wire
 * types. Internal helpers, capability-policy enums attached to other
 * structs, etc. Anything in this list does not require a corresponding
 * `$defs` entry.
 */
const NON_ROOT_STRUCTS = new Set<string>([
	// `MemoryNode.LookupEntry` is a sub-type carried inside MemoryNode;
	// it lives as `$defs/MemoryNodeLookupEntry` in the schema. The Zig
	// extractor sees it as `LookupEntry` because it's declared as a
	// top-level child within MemoryNode.
	'LookupEntry',
	// `SignedPolicy` is a runtime policy enum on DreamBall; not a wire
	// type. Lives entirely in src/protocol.zig isFullySigned().
	'SignedPolicy',
]);

/**
 * Recrypt naming inheritance (TC9). Zig struct name -> schema $defs
 * type name when they differ. The schema name follows the recrypt
 * wire-protocol naming verbatim; the Zig side keeps the historical
 * name. Mapping is exhaustive — anything not listed is expected to
 * match by name.
 */
const ZIG_TO_SCHEMA_ALIAS = new Map<string, string>([
	// `Signature` lives in the schema as `SignatureTierWrapper` per the
	// codegen-spike findings (Story 1.1) — the wrapper name carries the
	// Stage-tier wrapping semantics that the Zig struct name elides.
	['Signature', 'SignatureTierWrapper'],
]);

/**
 * Whitelist of Zig field names exempt from coverage. Used for fields
 * that exist only as in-memory plumbing and have no wire surface.
 * Empty for now; recorded here as the documented escape hatch per AC5.
 */
const NON_WIRE_FIELDS = new Map<string, Set<string>>([
	// `<StructName>` -> set of field names allowed to skip coverage.
]);

const protocolV2Src = readFileSync(PROTOCOL_V2_PATH, 'utf8');
const protocolSrc = readFileSync(PROTOCOL_PATH, 'utf8');
const allStructs = [
	...extractZigStructs(protocolSrc),
	...extractZigStructs(protocolV2Src),
];

const schemaPropNames = new Set<string>();
collectAllPropertyNames(schema, schemaPropNames);
const schemaDefNames = collectDefNames(schema);

describe('root schema coverage (AC1 + AC5)', () => {
	for (const s of allStructs) {
		if (NON_ROOT_STRUCTS.has(s.name)) continue;
		it(`Zig struct ${s.name}: every field appears in schemas/root-2.0.0.json`, () => {
			const exempt = NON_WIRE_FIELDS.get(s.name) ?? new Set<string>();
			const missing: string[] = [];
			for (const f of s.fields) {
				if (exempt.has(f)) continue;
				const wire = toWireName(f);
				if (!schemaPropNames.has(wire)) missing.push(`${s.name}.${f} (wire: ${wire})`);
			}
			expect(
				missing,
				`schemas/root-2.0.0.json is missing root field(s): ${missing.join(', ')}`,
			).toEqual([]);
		});
	}

	it('every struct is represented as a $defs type (or whitelisted)', () => {
		const missingDefs: string[] = [];
		for (const s of allStructs) {
			if (NON_ROOT_STRUCTS.has(s.name)) continue;
			const expected = ZIG_TO_SCHEMA_ALIAS.get(s.name) ?? s.name;
			if (!schemaDefNames.has(expected)) missingDefs.push(`${s.name} (expected $defs/${expected})`);
		}
		expect(
			missingDefs,
			`schemas/root-2.0.0.json $defs is missing struct(s): ${missingDefs.join(', ')}`,
		).toEqual([]);
	});
});

describe('root schema metaschema validity (AC3)', () => {
	it('validates against JSON Schema draft 2020-12', () => {
		// `strict: false` keeps Ajv from complaining about our `x-*`
		// extension keys (they are explicitly allowed by JSON Schema's
		// extension rules per spike Gap commitments).
		const ajv = new Ajv2020({ strict: false, allErrors: true });
		// `compile` runs metaschema validation on the schema document
		// itself. If draft 2020-12 rejects the schema, compile throws
		// or `ajv.errors` is populated.
		expect(() => ajv.compile(schema)).not.toThrow();
	});
});
