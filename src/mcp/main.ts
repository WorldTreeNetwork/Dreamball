/**
 * Story 4.3 — Memory Palace MCP Server entrypoint.
 *
 * Hosts the generated MCP tool spec (PALACE_TOOLS / PALACE_HANDLERS from
 * Story 4.2) via the pinned MCP SDK (TC7: @modelcontextprotocol/sdk@1.29.0).
 *
 * Transport: stdio (the SDK default; suitable for `bun run mcp` invocation by
 * an LLM agent host). Per Story 4.3 Technical Notes: use stdio transport by
 * default; no network listener required.
 *
 * Architecture (D-034): this file is a TRANSPORT SHIM only.
 *   MCP layer (here) → generated client (palace-client.ts) →
 *   store wrapper (D-007) → bridge (D-022) → CAS
 * No mutation primitives live here. All "intelligence" is in the manifest +
 * generated client + generated tool spec.
 *
 * Per 4.2 DAR: McpServer.registerTool() requires a ZodRawShape / AnySchema
 * for inputSchema; our generated PALACE_TOOLS use plain JSON Schema objects.
 * The low-level Server + setRequestHandler approach avoids the type cast issue
 * while keeping the architecture clean (one setRequestHandler per MCP method).
 *
 * Input validation (AC4): Ajv draft-07 validates args against the tool's
 * inputSchema before dispatching. Validation errors surface as a tool-call
 * error (isError: true) without invoking the underlying client.
 *
 * Elicitation (AC3): the server.elicitInput binding is passed as the ElicitFn
 * to each handler. The client must declare `capabilities.elicitation` in its
 * own constructor (per pinned SDK 1.29.0 elicitation negotiation).
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
  McpError,
  ErrorCode,
  type CallToolResult,
} from '@modelcontextprotocol/sdk/types.js';
import { Ajv2020 } from 'ajv/dist/2020.js';

import {
  PALACE_TOOLS,
  PALACE_HANDLERS,
} from '../lib/generated/palace-mcp-tools.js';

// ---------------------------------------------------------------------------
// Ajv instance for input validation (AC4).
// Use draft-07 (the default) — the manifest inputSchema fragments are simple
// JSON Schema objects without $schema declarations.
// ---------------------------------------------------------------------------
const ajv = new Ajv2020({ strict: false, allErrors: true });

// Pre-compile a validator for each tool's inputSchema.
const toolValidators = new Map<string, ReturnType<typeof ajv.compile>>();
for (const tool of PALACE_TOOLS) {
  toolValidators.set(tool.name, ajv.compile(tool.inputSchema));
}

// ---------------------------------------------------------------------------
// Server setup
// ---------------------------------------------------------------------------
const server = new Server(
  { name: 'dreamball-palace', version: '0.1.0' },
  {
    // Server declares tools capability so the SDK allows tools/list and
    // tools/call request handlers to be registered. Elicitation negotiation is
    // client-side: the client must declare capabilities.elicitation in its
    // constructor (per AC3 spike record in 4.2 DAR).
    capabilities: { tools: {} },
  },
);

// ---------------------------------------------------------------------------
// tools/list — advertise the generated tool spec
// ---------------------------------------------------------------------------
server.setRequestHandler(ListToolsRequestSchema, () => {
  return { tools: PALACE_TOOLS };
});

// ---------------------------------------------------------------------------
// tools/call — validate input, dispatch, translate result
// ---------------------------------------------------------------------------
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args = {} } = request.params;

  // Look up the handler.
  const handler = PALACE_HANDLERS[name];
  if (!handler) {
    throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${name}`);
  }

  // Validate input against the tool's JSON Schema (AC4).
  const validate = toolValidators.get(name);
  if (validate && !validate(args)) {
    const messages = (validate.errors ?? [])
      .map((e: { instancePath: string; message?: string }) => `${e.instancePath} ${e.message ?? ''}`.trim())
      .join('; ');
    const result: CallToolResult = {
      content: [{ type: 'text', text: `Validation error: ${messages}` }],
      isError: true,
    };
    return result;
  }

  // Dispatch through the handler with the server's elicitInput bound as the
  // ElicitFn (AC3 + AC4 — per 4.2 DAR section "Story 4.3 inheritance").
  let handlerResult;
  try {
    handlerResult = await handler(args, {
      elicit: server.elicitInput.bind(server),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    const result: CallToolResult = {
      content: [{ type: 'text', text: `Tool error: ${message}` }],
      isError: true,
    };
    return result;
  }

  // Translate HandlerResult → CallToolResult (AC2).
  const result: CallToolResult = {
    content: [{ type: 'text', text: JSON.stringify(handlerResult) }],
  };
  return result;
});

// ---------------------------------------------------------------------------
// Connect stdio transport and start listening (AC1)
// ---------------------------------------------------------------------------
const transport = new StdioServerTransport();
await server.connect(transport);
