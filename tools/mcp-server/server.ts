#!/usr/bin/env bun
/**
 * jelly MCP server — stdio transport, JSON-RPC 2.0.
 *
 * Exposes the Zig `jelly` CLI as a set of MCP tools so AI agents +
 * scripting workflows can compose DreamBalls interactively. Every tool
 * maps to a subprocess invocation of the CLI. Output is returned as
 * structured JSON.
 *
 * Usage — add to ~/.claude/.mcp.json or project-local:
 * {
 *   "mcpServers": {
 *     "jelly": {
 *       "command": "bun",
 *       "args": ["run", "/path/to/Dreamball/tools/mcp-server/server.ts"]
 *     }
 *   }
 * }
 *
 * MCP tools exposed:
 *   - mint_dreamball    — create a new typed DreamBall
 *   - transmit_skill    — send a Tool to an Agent via a Guild
 *   - seal_relic        — wrap a DreamBall in a sealed Relic
 *   - unlock_relic      — open a sealed Relic (MOCKED)
 *   - join_guild        — add a Guild membership
 *   - list_dreamballs   — scan a directory for .jelly files
 *   - show_dreamball    — pretty-print a .jelly file
 *   - verify_dreamball  — Ed25519 signature check
 *   - describe_protocol — return the v2 type taxonomy for LLMs
 *
 * The server is intentionally thin: the CLI holds the protocol knowledge;
 * this server is just a JSON-RPC shim. If you need richer composition
 * (multi-step workflows), use the MCP client to orchestrate calls.
 */

import { spawnSync } from 'child_process';
import { resolve } from 'path';
import { existsSync, readdirSync, statSync } from 'fs';

// ---------------------------------------------------------------------------
// CLI location — defaults to repo-relative zig-out/bin/jelly. Override with
// JELLY_CLI env var when invoking from an install location.
// ---------------------------------------------------------------------------

const REPO_ROOT = resolve(import.meta.dir, '..', '..');
const DEFAULT_JELLY = resolve(REPO_ROOT, 'zig-out', 'bin', 'jelly');
const JELLY = process.env.JELLY_CLI ?? DEFAULT_JELLY;

function runJelly(args: string[]): { stdout: string; stderr: string; code: number } {
	if (!existsSync(JELLY)) {
		return {
			stdout: '',
			stderr: `jelly CLI not found at ${JELLY}; run \`zig build\` first or set JELLY_CLI`,
			code: 127
		};
	}
	const res = spawnSync(JELLY, args, { encoding: 'utf-8' });
	return { stdout: res.stdout ?? '', stderr: res.stderr ?? '', code: res.status ?? -1 };
}

// ---------------------------------------------------------------------------
// MCP tool registry
// ---------------------------------------------------------------------------

interface ToolSpec {
	name: string;
	description: string;
	inputSchema: {
		type: 'object';
		properties: Record<string, { type: string; description: string }>;
		required: string[];
	};
	handler: (args: Record<string, unknown>) => Promise<unknown>;
}

function strArg(args: Record<string, unknown>, key: string): string {
	const v = args[key];
	if (typeof v !== 'string') throw new Error(`${key} must be a string`);
	return v;
}

function optStr(args: Record<string, unknown>, key: string): string | undefined {
	const v = args[key];
	return typeof v === 'string' ? v : undefined;
}

const tools: ToolSpec[] = [
	{
		name: 'mint_dreamball',
		description:
			'Create a new typed DreamBall. Writes <out> (CBOR envelope) and <out>.key (raw Ed25519 secret). Type must be one of: avatar, agent, tool, relic, field, guild.',
		inputSchema: {
			type: 'object',
			properties: {
				out: { type: 'string', description: 'Output file path' },
				type: { type: 'string', description: 'DreamBall type' },
				name: { type: 'string', description: 'Display name' }
			},
			required: ['out', 'type']
		},
		handler: async (a) => {
			const cliArgs = ['mint', '--out', strArg(a, 'out'), '--type', strArg(a, 'type')];
			const n = optStr(a, 'name');
			if (n) cliArgs.push('--name', n);
			return runJelly(cliArgs);
		}
	},
	{
		name: 'show_dreamball',
		description:
			'Pretty-print a .jelly file. Format can be "text" (default) or "json" for the canonical JSON export.',
		inputSchema: {
			type: 'object',
			properties: {
				path: { type: 'string', description: 'Path to the .jelly file' },
				format: { type: 'string', description: 'text or json' }
			},
			required: ['path']
		},
		handler: async (a) => {
			const cliArgs = ['show', strArg(a, 'path')];
			const f = optStr(a, 'format');
			if (f) cliArgs.push('--format=' + f);
			return runJelly(cliArgs);
		}
	},
	{
		name: 'verify_dreamball',
		description:
			'Verify the Ed25519 signature on a .jelly file. Exits 0 on success, non-zero on failure.',
		inputSchema: {
			type: 'object',
			properties: {
				path: { type: 'string', description: 'Path to the .jelly file' }
			},
			required: ['path']
		},
		handler: async (a) => runJelly(['verify', strArg(a, 'path')])
	},
	{
		name: 'join_guild',
		description:
			'Add a Guild membership to a DreamBall and re-sign. Requires the DreamBall\'s secret key.',
		inputSchema: {
			type: 'object',
			properties: {
				dreamball: { type: 'string', description: 'Path to the DreamBall file' },
				guild: { type: 'string', description: 'Path to the Guild file' },
				key: { type: 'string', description: 'Path to the DreamBall\'s Ed25519 secret' },
				out: { type: 'string', description: 'Output path (defaults to in-place)' }
			},
			required: ['dreamball', 'guild', 'key']
		},
		handler: async (a) => {
			const cliArgs = [
				'join-guild',
				strArg(a, 'dreamball'),
				'--guild',
				strArg(a, 'guild'),
				'--key',
				strArg(a, 'key')
			];
			const out = optStr(a, 'out');
			if (out) cliArgs.push('--out', out);
			return runJelly(cliArgs);
		}
	},
	{
		name: 'transmit_skill',
		description:
			'Transmit a Tool DreamBall to a target Agent via a Guild. Produces a signed transmission receipt. Crypto is MOCKED in v2 MVP — Ed25519 signature is real, proxy-recryption is stubbed.',
		inputSchema: {
			type: 'object',
			properties: {
				tool: { type: 'string', description: 'Path to the Tool .jelly file' },
				to: { type: 'string', description: 'Target Agent fingerprint (base58)' },
				viaGuild: { type: 'string', description: 'Guild fingerprint (base58)' },
				senderKey: { type: 'string', description: 'Sender\'s Ed25519 secret key path' },
				out: { type: 'string', description: 'Receipt output path' }
			},
			required: ['tool', 'to', 'viaGuild', 'senderKey', 'out']
		},
		handler: async (a) =>
			runJelly([
				'transmit',
				strArg(a, 'tool'),
				'--to',
				strArg(a, 'to'),
				'--via-guild',
				strArg(a, 'viaGuild'),
				'--sender-key',
				strArg(a, 'senderKey'),
				'--out',
				strArg(a, 'out')
			])
	},
	{
		name: 'seal_relic',
		description:
			'Wrap a DreamBall in a sealed Relic envelope (MOCKED crypto — inner bytes are stored plaintext in v2 MVP).',
		inputSchema: {
			type: 'object',
			properties: {
				inner: { type: 'string', description: 'Path to the inner .jelly file' },
				forGuild: { type: 'string', description: 'Guild fingerprint (base58) authorised to unlock' },
				out: { type: 'string', description: 'Output path for the sealed relic' },
				hint: { type: 'string', description: 'Reveal hint (optional)' }
			},
			required: ['inner', 'forGuild', 'out']
		},
		handler: async (a) => {
			const cliArgs = [
				'seal-relic',
				strArg(a, 'inner'),
				'--for-guild',
				strArg(a, 'forGuild'),
				'--out',
				strArg(a, 'out')
			];
			const hint = optStr(a, 'hint');
			if (hint) cliArgs.push('--hint', hint);
			return runJelly(cliArgs);
		}
	},
	{
		name: 'unlock_relic',
		description:
			'Unlock a sealed Relic and extract the inner DreamBall (MOCKED — v2 MVP pulls plaintext attachment).',
		inputSchema: {
			type: 'object',
			properties: {
				relic: { type: 'string', description: 'Path to the sealed relic' },
				out: { type: 'string', description: 'Output path for the inner DreamBall' }
			},
			required: ['relic', 'out']
		},
		handler: async (a) =>
			runJelly(['unlock', strArg(a, 'relic'), '--out', strArg(a, 'out')])
	},
	{
		name: 'list_dreamballs',
		description: 'Scan a directory for .jelly files and return a summary per file.',
		inputSchema: {
			type: 'object',
			properties: {
				dir: { type: 'string', description: 'Directory to scan' }
			},
			required: ['dir']
		},
		handler: async (a) => {
			const dir = strArg(a, 'dir');
			if (!existsSync(dir) || !statSync(dir).isDirectory()) {
				return { error: `not a directory: ${dir}` };
			}
			const entries = readdirSync(dir)
				.filter((f) => f.endsWith('.jelly'))
				.map((f) => {
					const full = resolve(dir, f);
					const show = runJelly(['show', full]);
					return { path: full, text: show.stdout.trim() };
				});
			return { count: entries.length, entries };
		}
	},
	{
		name: 'describe_protocol',
		description:
			'Return the v2 DreamBall protocol taxonomy + slot list so an LLM that hasn\'t read the spec has the schema at hand.',
		inputSchema: { type: 'object', properties: {}, required: [] },
		handler: async () => ({
			'format-version': 2,
			types: [
				{ tag: 'avatar', wire: 'jelly.dreamball.avatar', summary: 'look-heavy, worn, visible to observer' },
				{ tag: 'agent', wire: 'jelly.dreamball.agent', summary: 'act-heavy — model, memory, knowledge, emotion, skills' },
				{ tag: 'tool', wire: 'jelly.dreamball.tool', summary: 'single skill, transferable via transmission' },
				{ tag: 'relic', wire: 'jelly.dreamball.relic', summary: 'sealed payload, reveals on unlock' },
				{ tag: 'field', wire: 'jelly.dreamball.field', summary: 'omnispherical ambient layer' },
				{ tag: 'guild', wire: 'jelly.dreamball.guild', summary: 'group with a recrypt-style keyspace' }
			],
			shared_core_fields: ['type', 'format-version', 'stage', 'identity', 'genesis-hash', 'revision'],
			agent_slots: [
				'act',
				'memory',
				'knowledge-graph',
				'emotional-register',
				'interaction-set',
				'personality-master-prompt',
				'secret'
			],
			renderer_lenses: [
				'thumbnail',
				'avatar',
				'knowledge-graph',
				'emotional-state',
				'omnispherical',
				'flat',
				'phone'
			],
			mocked_crypto_notice:
				'v2 MVP mocks proxy-recryption. Every mocked call site is tagged TODO-CRYPTO in source and prints a stderr warning at runtime.'
		})
	}
];

// ---------------------------------------------------------------------------
// JSON-RPC 2.0 stdio transport
// ---------------------------------------------------------------------------

type JsonRpcId = string | number | null;

interface JsonRpcRequest {
	jsonrpc: '2.0';
	id?: JsonRpcId;
	method: string;
	params?: unknown;
}

interface JsonRpcResponse {
	jsonrpc: '2.0';
	id: JsonRpcId | undefined;
	result?: unknown;
	error?: { code: number; message: string; data?: unknown };
}

function respond(id: JsonRpcId | undefined, result: unknown): JsonRpcResponse {
	return { jsonrpc: '2.0', id, result };
}

function errorResponse(id: JsonRpcId | undefined, code: number, message: string, data?: unknown): JsonRpcResponse {
	return { jsonrpc: '2.0', id, error: { code, message, data } };
}

async function handle(req: JsonRpcRequest): Promise<JsonRpcResponse | null> {
	const method = req.method;

	if (method === 'initialize') {
		return respond(req.id, {
			protocolVersion: '2024-11-05',
			capabilities: { tools: { listChanged: false } },
			serverInfo: { name: 'jelly', version: '0.2.0' }
		});
	}

	if (method === 'notifications/initialized') {
		return null; // no response for notifications
	}

	if (method === 'tools/list') {
		return respond(req.id, {
			tools: tools.map((t) => ({
				name: t.name,
				description: t.description,
				inputSchema: t.inputSchema
			}))
		});
	}

	if (method === 'tools/call') {
		const params = (req.params ?? {}) as { name?: string; arguments?: Record<string, unknown> };
		const tool = tools.find((t) => t.name === params.name);
		if (!tool) return errorResponse(req.id, -32601, `unknown tool: ${params.name}`);
		try {
			const out = await tool.handler(params.arguments ?? {});
			return respond(req.id, {
				content: [{ type: 'text', text: JSON.stringify(out, null, 2) }],
				isError: false
			});
		} catch (e) {
			return errorResponse(req.id, -32000, `tool ${tool.name} failed: ${(e as Error).message}`);
		}
	}

	return errorResponse(req.id, -32601, `method not found: ${method}`);
}

// Minimal line-delimited JSON-RPC over stdio (LSP-style framing is NOT used
// for MCP stdio transport — MCP uses newline-delimited JSON per message).

async function main() {
	const decoder = new TextDecoder();
	let buffer = '';

	for await (const chunk of process.stdin as unknown as AsyncIterable<Uint8Array>) {
		buffer += decoder.decode(chunk);
		let idx: number;
		while ((idx = buffer.indexOf('\n')) >= 0) {
			const line = buffer.slice(0, idx).trim();
			buffer = buffer.slice(idx + 1);
			if (!line) continue;
			let req: JsonRpcRequest;
			try {
				req = JSON.parse(line) as JsonRpcRequest;
			} catch {
				process.stdout.write(
					JSON.stringify(errorResponse(null, -32700, 'parse error')) + '\n'
				);
				continue;
			}
			const res = await handle(req);
			if (res) process.stdout.write(JSON.stringify(res) + '\n');
		}
	}
}

main().catch((e) => {
	process.stderr.write(`fatal: ${(e as Error).message}\n`);
	process.exit(1);
});
