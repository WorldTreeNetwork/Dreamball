/**
 * MCP self-documentation assembler.
 *
 * Generates the /.well-known/mcp document at request time from:
 *   - The Elysia route table (paths, methods, descriptions)
 *   - Valibot schemas converted to JSON Schema via @valibot/to-json-schema
 *   - Manually maintained example registry
 *   - WASM export signatures
 *   - DreamBall type taxonomy
 *   - MCP tool descriptors matching tools/mcp-server/server.ts format
 *
 * Drift between the doc and the actual server is structurally impossible
 * because both are derived from the same schema/route sources.
 */

import { toJsonSchema } from '@valibot/to-json-schema';
import {
  DreamBallSchema,
  DreamBallAvatarSchema,
  DreamBallAgentSchema,
  DreamBallToolSchema,
  DreamBallRelicSchema,
  DreamBallFieldSchema,
  DreamBallGuildSchema,
  DreamBallUntypedSchema,
  Base58Schema,
  SignatureSchema
} from '../../src/lib/generated/schemas.js';

// ---------------------------------------------------------------------------
// Route table — mirrors the actual routes in index.ts
// ---------------------------------------------------------------------------

interface RouteDoc {
  method: string;
  path: string;
  summary: string;
  description: string;
  inputSchema?: object;
  outputSchema?: object;
  exampleRequest?: object;
  exampleResponse?: object;
  exampleError?: object;
}

const routes: RouteDoc[] = [
  {
    method: 'POST',
    path: '/dreamballs',
    summary: 'Mint a new DreamBall',
    description: 'Creates a new typed DreamBall. Returns the secret key ONCE in the creation response — store it securely, it cannot be recovered.',
    inputSchema: {
      type: 'object',
      properties: {
        type: { type: 'string', enum: ['avatar', 'agent', 'tool', 'relic', 'field', 'guild', 'untyped'] },
        name: { type: 'string', description: 'Optional display name' }
      },
      required: ['type']
    },
    outputSchema: {
      type: 'object',
      properties: {
        fingerprint: { type: 'string' },
        dreamball: { type: 'object' },
        secret_key_b58: { type: 'string', description: 'Returned ONCE only on creation' },
        created_at: { type: 'string', format: 'date-time' }
      },
      required: ['fingerprint', 'dreamball', 'secret_key_b58', 'created_at']
    },
    exampleRequest: { type: 'avatar', name: 'Alice' },
    exampleResponse: {
      fingerprint: 'AbC123...',
      dreamball: { type: 'jelly.dreamball.avatar', stage: 'dreamball', identity: 'b58:AbC123...' },
      secret_key_b58: 'b58:...',
      created_at: '2026-04-19T00:00:00Z'
    },
    exampleError: { error: 'validation failed' }
  },
  {
    method: 'GET',
    path: '/dreamballs',
    summary: 'List all DreamBalls',
    description: 'Returns an array of { fingerprint, summary } objects. Never includes secret_key_b58.',
    outputSchema: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          fingerprint: { type: 'string' },
          summary: { type: 'object' }
        }
      }
    },
    exampleResponse: [
      { fingerprint: 'AbC123...', summary: { type: 'jelly.dreamball.avatar', name: 'Alice', stage: 'dreamball' } }
    ]
  },
  {
    method: 'GET',
    path: '/dreamballs/:fp',
    summary: 'Get a DreamBall',
    description: 'Returns the stored DreamBall JSON by fingerprint. Never includes secret_key_b58. Returns 404 on miss.',
    outputSchema: toJsonSchema(DreamBallSchema) as object,
    exampleResponse: { type: 'jelly.dreamball.avatar', stage: 'dreamball', identity: 'b58:AbC123...' },
    exampleError: { error: 'not found', fingerprint: 'AbC123...' }
  },
  {
    method: 'GET',
    path: '/dreamballs/:fp/verify',
    summary: 'Verify DreamBall signature',
    description: 'Verifies Ed25519 signature(s) on the stored DreamBall. Returns { ok, hadEd25519, reason? }.',
    outputSchema: {
      type: 'object',
      properties: {
        ok: { type: 'boolean' },
        hadEd25519: { type: 'boolean' },
        reason: { type: 'string' }
      },
      required: ['ok', 'hadEd25519']
    },
    exampleResponse: { ok: true, hadEd25519: true },
    exampleError: { ok: false, hadEd25519: false, reason: 'signature mismatch' }
  },
  {
    method: 'POST',
    path: '/dreamballs/:fp/grow',
    summary: 'Grow (update) a DreamBall',
    description: 'Applies updates to a DreamBall, bumps revision, re-signs with Ed25519. Requires the secret key. Response never includes secret_key_b58.',
    inputSchema: {
      type: 'object',
      properties: {
        secret_key_b58: { type: 'string' },
        updates: {
          type: 'object',
          properties: {
            name: { type: 'string' },
            promote_to_dreamball: { type: 'boolean' }
          }
        }
      },
      required: ['secret_key_b58', 'updates']
    },
    outputSchema: toJsonSchema(DreamBallSchema) as object,
    exampleRequest: { secret_key_b58: 'b58:...', updates: { name: 'Alice v2' } },
    exampleResponse: { type: 'jelly.dreamball.avatar', revision: 2, name: 'Alice v2' },
    exampleError: { error: 'not found', fingerprint: 'AbC123...' }
  },
  {
    method: 'POST',
    path: '/dreamballs/:fp/join-guild',
    summary: 'Join a guild',
    description: 'Appends a guild membership assertion to a DreamBall and re-signs. Requires the secret key.',
    inputSchema: {
      type: 'object',
      properties: {
        guild_fp: { type: 'string' },
        secret_key_b58: { type: 'string' }
      },
      required: ['guild_fp', 'secret_key_b58']
    },
    exampleRequest: { guild_fp: 'GuildFp123...', secret_key_b58: 'b58:...' },
    exampleResponse: { type: 'jelly.dreamball.avatar', guild: ['b58:GuildFp123...'] }
  },
  {
    method: 'POST',
    path: '/dreamballs/:fp/transmit',
    summary: 'Transmit a Tool DreamBall',
    description: 'Produces a signed transmission receipt for sending a Tool to an Agent via a Guild. MVP: subprocesses to jelly CLI.',
    inputSchema: {
      type: 'object',
      properties: {
        to_fp: { type: 'string' },
        via_guild_fp: { type: 'string' },
        sender_key_b58: { type: 'string' }
      },
      required: ['to_fp', 'via_guild_fp', 'sender_key_b58']
    },
    exampleRequest: { to_fp: 'AgentFp...', via_guild_fp: 'GuildFp...', sender_key_b58: 'b58:...' }
  },
  {
    method: 'POST',
    path: '/relics',
    summary: 'Seal a relic',
    description: 'Wraps an inner DreamBall JSON into a sealed Relic envelope. MVP: subprocesses to jelly CLI.',
    inputSchema: {
      type: 'object',
      properties: {
        inner_dreamball_json: { type: 'string', description: 'JSON string of the inner DreamBall' },
        unlock_guild_fp: { type: 'string' },
        reveal_hint: { type: 'string' }
      },
      required: ['inner_dreamball_json', 'unlock_guild_fp']
    },
    exampleRequest: {
      inner_dreamball_json: '{"type":"jelly.dreamball.agent",...}',
      unlock_guild_fp: 'GuildFp...',
      reveal_hint: 'Contains the agent memory'
    }
  },
  {
    method: 'POST',
    path: '/relics/:id/unlock',
    summary: 'Unlock a relic',
    description: 'Extracts the inner DreamBall from a sealed relic. MVP: subprocesses to jelly CLI.',
    inputSchema: { type: 'object', properties: {} },
    exampleResponse: { type: 'jelly.dreamball.agent', stage: 'dreamball' }
  }
];

// ---------------------------------------------------------------------------
// WASM export signatures
// ---------------------------------------------------------------------------

const wasmExports = [
  { name: 'alloc', signature: '(size: u32) -> u32', description: 'Allocate bytes in the linear memory scratch arena. Returns 0 on OOM.' },
  { name: 'reset', signature: '() -> void', description: 'Reset the scratch arena. Must be called before each operation.' },
  { name: 'parseJelly', signature: '(ptr: u32, len: u32) -> u64', description: 'Parse a .jelly CBOR/JSON envelope. Returns packed (resultPtr << 32 | resultLen). Returns 0 on error.' },
  { name: 'verifyJelly', signature: '(ptr: u32, len: u32) -> i32', description: 'Verify Ed25519 signatures. Returns 2=ok+signed, 1=ok+unsigned, 0=fail, -1=parse error.' },
  { name: 'mintDreamBall', signature: '(typeId: u32, namePtr: u32, nameLen: u32, nowSecs: u64) -> u64', description: 'Mint a new DreamBall. Returns packed JSON result containing dreamball_json + secret_key_b58.' },
  { name: 'growDreamBall', signature: '(ptr: u32, len: u32) -> u64', description: 'Apply updates to a DreamBall and re-sign. Input: { dreamball_json, secret_key_b58, updates }.' },
  { name: 'joinGuildWasm', signature: '(ptr: u32, len: u32) -> u64', description: 'Add guild membership to a DreamBall. Input: { dreamball_json, guild_json, secret_key_b58 }.' },
  { name: 'lastSecretPtr', signature: '() -> u32', description: 'Pointer to the last secret key bytes in linear memory.' },
  { name: 'lastSecretLen', signature: '() -> u32', description: 'Length of the last secret key bytes.' },
  { name: 'resultErrPtr', signature: '() -> u32', description: 'Pointer to the last error message string.' },
  { name: 'resultErrLen', signature: '() -> u32', description: 'Length of the last error message string.' },
  { name: 'getRandomBytes', signature: '(ptr: u32, len: u32) -> void [import from env]', description: 'Host-provided randomness. Must be wired to crypto.getRandomValues by the host.' }
];

// ---------------------------------------------------------------------------
// DreamBall type taxonomy
// ---------------------------------------------------------------------------

const dreamballTypes = [
  {
    tag: 'avatar',
    wire: 'jelly.dreamball.avatar',
    summary: 'A worn identity — look-heavy, visible to the observer.',
    populatedSlots: ['look', 'feel'],
    schema: toJsonSchema(DreamBallAvatarSchema)
  },
  {
    tag: 'agent',
    wire: 'jelly.dreamball.agent',
    summary: 'An autonomous agent — act-heavy with memory, knowledge graph, emotional register, and skills.',
    populatedSlots: ['look', 'feel', 'act', 'memory', 'knowledge-graph', 'emotional-register', 'interaction-set', 'personality-master-prompt', 'secret'],
    schema: toJsonSchema(DreamBallAgentSchema)
  },
  {
    tag: 'tool',
    wire: 'jelly.dreamball.tool',
    summary: 'A single transferable skill, transmitted via guild.',
    populatedSlots: ['skill', 'applicable-to'],
    schema: toJsonSchema(DreamBallToolSchema)
  },
  {
    tag: 'relic',
    wire: 'jelly.dreamball.relic',
    summary: 'A sealed payload that reveals on unlock by an authorized guild member.',
    populatedSlots: ['sealed-payload-hash', 'unlock-guild', 'reveal-hint', 'sealed-until'],
    schema: toJsonSchema(DreamBallRelicSchema)
  },
  {
    tag: 'field',
    wire: 'jelly.dreamball.field',
    summary: 'An omnispherical ambient layer — the spatial context a DreamBall inhabits.',
    populatedSlots: ['omnispherical-grid', 'ambient-palette', 'dream-field-id'],
    schema: toJsonSchema(DreamBallFieldSchema)
  },
  {
    tag: 'guild',
    wire: 'jelly.dreamball.guild',
    summary: 'A group with a recrypt-style keyspace. Members can unlock relics and receive transmissions.',
    populatedSlots: ['guild-name', 'keyspace-root-hash', 'member', 'admin', 'policy'],
    schema: toJsonSchema(DreamBallGuildSchema)
  },
  {
    tag: 'untyped',
    wire: 'jelly.dreamball',
    summary: 'Legacy v1 DreamBall with no subtype suffix.',
    populatedSlots: ['look', 'feel', 'act'],
    schema: toJsonSchema(DreamBallUntypedSchema)
  }
];

// ---------------------------------------------------------------------------
// MCP tool descriptors (matching tools/mcp-server/server.ts format)
// ---------------------------------------------------------------------------

const mcpTools = [
  {
    name: 'mint_dreamball',
    description: 'Create a new typed DreamBall via jelly-server HTTP API.',
    transport: 'http',
    endpoint: 'POST /dreamballs',
    inputSchema: {
      type: 'object',
      properties: {
        type: { type: 'string', enum: ['avatar', 'agent', 'tool', 'relic', 'field', 'guild', 'untyped'] },
        name: { type: 'string' }
      },
      required: ['type']
    }
  },
  {
    name: 'show_dreamball',
    description: 'Get a DreamBall by fingerprint.',
    transport: 'http',
    endpoint: 'GET /dreamballs/:fp',
    inputSchema: {
      type: 'object',
      properties: { fp: { type: 'string' } },
      required: ['fp']
    }
  },
  {
    name: 'list_dreamballs',
    description: 'List all stored DreamBalls.',
    transport: 'http',
    endpoint: 'GET /dreamballs',
    inputSchema: { type: 'object', properties: {}, required: [] }
  },
  {
    name: 'verify_dreamball',
    description: 'Verify the Ed25519 signature on a stored DreamBall.',
    transport: 'http',
    endpoint: 'GET /dreamballs/:fp/verify',
    inputSchema: {
      type: 'object',
      properties: { fp: { type: 'string' } },
      required: ['fp']
    }
  },
  {
    name: 'grow_dreamball',
    description: 'Apply updates to a DreamBall and re-sign. Requires the secret key.',
    transport: 'http',
    endpoint: 'POST /dreamballs/:fp/grow',
    inputSchema: {
      type: 'object',
      properties: {
        fp: { type: 'string' },
        secret_key_b58: { type: 'string' },
        updates: { type: 'object' }
      },
      required: ['fp', 'secret_key_b58', 'updates']
    }
  },
  {
    name: 'join_guild',
    description: 'Add a guild membership to a DreamBall and re-sign.',
    transport: 'http',
    endpoint: 'POST /dreamballs/:fp/join-guild',
    inputSchema: {
      type: 'object',
      properties: {
        fp: { type: 'string' },
        guild_fp: { type: 'string' },
        secret_key_b58: { type: 'string' }
      },
      required: ['fp', 'guild_fp', 'secret_key_b58']
    }
  },
  {
    name: 'transmit_skill',
    description: 'Transmit a Tool DreamBall to an Agent via a Guild.',
    transport: 'http',
    endpoint: 'POST /dreamballs/:fp/transmit',
    inputSchema: {
      type: 'object',
      properties: {
        fp: { type: 'string' },
        to_fp: { type: 'string' },
        via_guild_fp: { type: 'string' },
        sender_key_b58: { type: 'string' }
      },
      required: ['fp', 'to_fp', 'via_guild_fp', 'sender_key_b58']
    }
  },
  {
    name: 'seal_relic',
    description: 'Wrap a DreamBall in a sealed Relic envelope.',
    transport: 'http',
    endpoint: 'POST /relics',
    inputSchema: {
      type: 'object',
      properties: {
        inner_dreamball_json: { type: 'string' },
        unlock_guild_fp: { type: 'string' },
        reveal_hint: { type: 'string' }
      },
      required: ['inner_dreamball_json', 'unlock_guild_fp']
    }
  },
  {
    name: 'unlock_relic',
    description: 'Unlock a sealed Relic and extract the inner DreamBall.',
    transport: 'http',
    endpoint: 'POST /relics/:id/unlock',
    inputSchema: {
      type: 'object',
      properties: { id: { type: 'string' } },
      required: ['id']
    }
  }
];

// ---------------------------------------------------------------------------
// Workflow recipes
// ---------------------------------------------------------------------------

const recipes = [
  {
    name: 'mint-an-avatar',
    steps: [
      { call: 'POST /dreamballs', body: { type: 'avatar', name: 'Alice' }, note: 'Save fingerprint and secret_key_b58' },
      { call: 'GET /dreamballs/:fp', note: 'Confirm the DreamBall is stored' },
      { call: 'GET /dreamballs/:fp/verify', note: 'Confirm Ed25519 signature is valid' }
    ]
  },
  {
    name: 'mint-tool-join-guild-transmit',
    steps: [
      { call: 'POST /dreamballs', body: { type: 'guild', name: 'My Guild' }, note: 'Mint a guild; save guild fingerprint + secret' },
      { call: 'POST /dreamballs', body: { type: 'tool', name: 'My Tool' }, note: 'Mint a tool; save tool fingerprint + secret' },
      { call: 'POST /dreamballs', body: { type: 'agent', name: 'Target Agent' }, note: 'Mint target agent; save agent fingerprint' },
      { call: 'POST /dreamballs/:tool_fp/join-guild', body: { guild_fp: ':guild_fp', secret_key_b58: ':tool_secret' }, note: 'Tool joins the guild' },
      { call: 'POST /dreamballs/:tool_fp/transmit', body: { to_fp: ':agent_fp', via_guild_fp: ':guild_fp', sender_key_b58: ':tool_secret' }, note: 'Transmit tool to agent via guild' }
    ]
  },
  {
    name: 'seal-and-unlock-relic',
    steps: [
      { call: 'POST /dreamballs', body: { type: 'guild', name: 'Unlock Guild' }, note: 'Mint a guild for relic access control' },
      { call: 'POST /dreamballs', body: { type: 'agent', name: 'Secret Agent' }, note: 'Mint the inner DreamBall to seal' },
      { call: 'GET /dreamballs/:inner_fp', note: 'Get inner DreamBall JSON' },
      { call: 'POST /relics', body: { inner_dreamball_json: ':inner_json', unlock_guild_fp: ':guild_fp', reveal_hint: 'Contains secret agent' }, note: 'Seal the relic' },
      { call: 'POST /relics/:relic_id/unlock', body: {}, note: 'Unlock the relic to get the inner DreamBall back' }
    ]
  }
];

// ---------------------------------------------------------------------------
// Doc anchors
// ---------------------------------------------------------------------------

const docAnchors = {
  protocol: 'https://identikey.github.io/Dreamball/PROTOCOL.md',
  vision: 'https://identikey.github.io/Dreamball/VISION.md',
  architecture: 'https://identikey.github.io/Dreamball/ARCHITECTURE.md',
  protocolLocal: '../docs/PROTOCOL.md',
  visionLocal: '../docs/VISION.md'
};

// ---------------------------------------------------------------------------
// Assembled document
// ---------------------------------------------------------------------------

export function buildMcpDoc() {
  return {
    schema_version: '1.0',
    generated_at: new Date().toISOString(),
    server: {
      name: 'jelly-server',
      version: '0.0.1',
      description: 'Bun-native Elysia HTTP server wrapping jelly.wasm for DreamBall write+read operations.',
      base_url: `http://localhost:${process.env.JELLY_SERVER_PORT ?? 9808}`
    },
    docs: docAnchors,
    routes,
    wasm_exports: wasmExports,
    dreamball_types: dreamballTypes,
    mcp_tools: mcpTools,
    recipes,
    security_notes: [
      'secret_key_b58 is returned ONLY in the POST /dreamballs creation response.',
      'Every GET route and every subsequent POST response is guaranteed to omit secret_key_b58.',
      'Store the secret key client-side immediately and never transmit it except in authorized write operations.'
    ]
  };
}

export function buildTypesDoc() {
  return {
    schema_version: '1.0',
    generated_at: new Date().toISOString(),
    description: 'JSON Schema bundle for all DreamBall v2 protocol types. Equivalent to src/lib/generated/schemas.ts.',
    $defs: {
      DreamBall: toJsonSchema(DreamBallSchema),
      DreamBallAvatar: toJsonSchema(DreamBallAvatarSchema),
      DreamBallAgent: toJsonSchema(DreamBallAgentSchema),
      DreamBallTool: toJsonSchema(DreamBallToolSchema),
      DreamBallRelic: toJsonSchema(DreamBallRelicSchema),
      DreamBallField: toJsonSchema(DreamBallFieldSchema),
      DreamBallGuild: toJsonSchema(DreamBallGuildSchema),
      DreamBallUntyped: toJsonSchema(DreamBallUntypedSchema),
      Base58: toJsonSchema(Base58Schema),
      Signature: toJsonSchema(SignatureSchema)
    }
  };
}
