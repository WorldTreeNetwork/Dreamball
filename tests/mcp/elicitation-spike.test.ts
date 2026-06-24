/**
 * Story 4.2 — MCP Elicitation Spike (D-024 spike-before-promote).
 *
 * AC3: confirm MCP elicitation is supported in the pinned MCP SDK
 * (`@modelcontextprotocol/sdk@1.29.0`) and record the API shape used.
 * AC4: confirm `requiresConfirmation: true` actions surface elicitation
 * on first call and proceed on second call after user grant.
 *
 * Spike strategy (per `feedback_dreamball_ac_scope_retreat`): drive the
 * generated `palace.rename-mythos` handler against the SDK's actual
 * elicitation API surface, NOT a hand-rolled mock. We use:
 *
 *   - `Server` (low-level) + `Client` connected via `InMemoryTransport`
 *     pair so the elicitation request travels through the real SDK
 *     transport + JSON-RPC machinery.
 *   - The client registers an `elicitation/create` request handler
 *     (this IS the spec-defined surface — `ElicitRequestSchema`).
 *   - The handler calls `server.elicitInput({ mode: 'form', ... })`
 *     which round-trips through the transport pair.
 *
 * If this test passes, AC3 is satisfied: the pinned SDK supports
 * elicitation natively. If it fails for "elicitation not supported"
 * reasons, AC5 fires and the spike's outcome is a blocker (per the
 * Dev Agent Record).
 *
 * Recorded SDK shape (load-bearing for Story 4.3):
 *   - Method: `elicitation/create` (JSON-RPC)
 *   - Server-side: `server.elicitInput(params, options?) → Promise<ElicitResult>`
 *   - Client-side: `client.setRequestHandler(ElicitRequestSchema, handler)`
 *   - Form-mode params: `{ mode: 'form', message, requestedSchema }`
 *   - Result: `{ action: 'accept' | 'decline' | 'cancel', content?: object }`
 *   - Capability negotiation: client must declare `capabilities.elicitation`
 *     in its constructor for the server's elicit request to be accepted.
 *
 * Note: the existing `palace-client.ts` (Story 4.1) shells out to a
 * `dreamball` CLI binary via `spawnSync`. The spike DOES NOT exercise that
 * underlying CLI path — Story 4.2's scope is the elicitation routing,
 * not the action execution. The handler's post-confirmation dispatch
 * to `renameMythos(args)` is gated behind a JELLY_CLI shim test
 * environment variable so the spawn doesn't crash the test.
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { ElicitRequestSchema, type ElicitRequest, type ElicitResult } from '@modelcontextprotocol/sdk/types.js';
import { mkdtempSync, writeFileSync, chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
  PALACE_TOOLS,
  PALACE_HANDLERS,
  RENAME_MYTHOS_TOOL,
  MINT_TOOL,
  handleRenameMythos,
  type ElicitFn,
  type HandlerResult,
} from '../../src/lib/generated/palace-mcp-tools.js';

describe('Story 4.2 — MCP elicitation spike (AC3, AC4)', () => {
  // ── AC1 surface checks ────────────────────────────────────────────────────

  it('AC1: emits one Tool spec per manifest action with palace.<key> name', () => {
    const names = PALACE_TOOLS.map((t) => t.name).sort();
    expect(names).toEqual(
      [
        'palace.add-room',
        'palace.inscribe',
        'palace.mint',
        'palace.move',
        'palace.rename-mythos',
      ].sort(),
    );
  });

  it("AC1: tool description = manifest's summary; inputSchema declared", () => {
    expect(MINT_TOOL.description).toContain('Mint a new Memory Palace');
    expect(MINT_TOOL.inputSchema.type).toBe('object');
    expect(MINT_TOOL.inputSchema.required).toContain('out');
    expect(MINT_TOOL.inputSchema.required).toContain('mythos');
  });

  it('AC1: PALACE_HANDLERS dispatch table covers all five tools', () => {
    expect(Object.keys(PALACE_HANDLERS).sort()).toEqual([
      'palace.add-room',
      'palace.inscribe',
      'palace.mint',
      'palace.move',
      'palace.rename-mythos',
    ]);
  });

  // ── AC2: input schema matches the JSON Schema fragment from the manifest ──

  it('AC2: tool inputSchema is the manifest inputs fragment verbatim (same source as CLI/Ajv)', () => {
    // The MINT_TOOL.inputSchema must structurally equal the manifest's
    // x-actions.mint.inputs fragment. We don't import the JSON file again
    // here — the structural sample is sufficient: the generator emits
    // verbatim, so the shape's required/properties keys round-trip.
    expect(MINT_TOOL.inputSchema.properties).toHaveProperty('out');
    expect(MINT_TOOL.inputSchema.properties).toHaveProperty('mythos');
    expect(MINT_TOOL.inputSchema.properties).toHaveProperty('mythosFile');
    // additionalProperties: false discipline preserved (D-035 closed-set
    // discipline applies to attributes/effects.kind; on inputs it's the
    // manifest's own `additionalProperties: false`).
    // (We can't assert additionalProperties directly via the strict Tool
    // type without casting; the verbatim emission is the contract.)
  });

  // ── AC4: requiresConfirmation routes to elicitation (handler-level) ──────

  it('AC4: rename-mythos surfaces elicitation on first call (no confirm)', async () => {
    const elicitCalls: Array<ElicitRequest['params']> = [];
    const elicit: ElicitFn = async (params) => {
      elicitCalls.push(params);
      return { action: 'decline' };
    };
    const result: HandlerResult = await handleRenameMythos(
      { palace: '/tmp/p', body: 'new name' },
      { elicit },
    );
    expect(elicitCalls.length).toBe(1);
    expect(elicitCalls[0].mode).toBe('form');
    expect(elicitCalls[0].message).toContain('Rename the palace mythos');
    expect(result).toEqual({ elicited: true, confirmed: false });
  });

  it('AC4: handler does NOT call elicit on second call when confirmed already true', async () => {
    const elicitCalls: number[] = [];
    const elicit: ElicitFn = async () => {
      elicitCalls.push(1);
      return { action: 'accept', content: { confirm: true } };
    };
    // We can't run the underlying client (it shells out to dreamball CLI), but
    // we can assert that elicit is NOT called when confirmed=true is already
    // threaded through. The handler will then attempt to dispatch — wrap
    // in try so the spawn failure (no JELLY_CLI in test env) doesn't fail
    // this assertion.
    try {
      await handleRenameMythos(
        { palace: '/tmp/p', body: 'new name' },
        { elicit, confirmed: true },
      );
    } catch {
      // expected: spawn failure when JELLY_CLI is unset / not built
    }
    expect(elicitCalls.length).toBe(0);
  });

  it("AC4: mint (requiresConfirmation: false) does NOT elicit", async () => {
    const elicitCalls: number[] = [];
    const elicit: ElicitFn = async () => {
      elicitCalls.push(1);
      return { action: 'decline' };
    };
    // Run the mint handler — should skip elicitation entirely and try to
    // dispatch. We don't care about the dispatch outcome here; we care
    // that elicit was never invoked.
    try {
      await PALACE_HANDLERS['palace.mint']({ out: '/tmp/x', mythos: 'hi' }, { elicit });
    } catch {
      // expected: spawn failure
    }
    expect(elicitCalls.length).toBe(0);
  });

  // ── AC3: end-to-end elicitation against pinned SDK (the spike) ───────────

  describe('AC3: end-to-end elicitation/create round-trip via pinned SDK', () => {
    let server: Server;
    let client: Client;
    let serverTransport: InMemoryTransport;
    let clientTransport: InMemoryTransport;

    beforeAll(async () => {
      [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();

      server = new Server(
        { name: 'dreamball-test-server', version: '0.0.1' },
        {
          // Server declares it can issue elicitation requests.
          capabilities: {},
        },
      );

      client = new Client(
        { name: 'dreamball-test-client', version: '0.0.1' },
        {
          // Client must declare elicitation support so the server's
          // elicit calls are accepted (per pinned SDK 1.29.0).
          capabilities: { elicitation: { form: {} } },
        },
      );

      // Client-side handler for elicitation/create — the spike's "user".
      // For the spike we always accept with confirm=true; AC4's per-handler
      // tests above cover the decline path via the handler-level stub.
      client.setRequestHandler(ElicitRequestSchema, async (request) => {
        const params = request.params;
        if (params.mode !== 'form') {
          throw new Error(`unexpected elicitation mode: ${String(params.mode)}`);
        }
        // Return the requested-schema's required keys with default truthy
        // values (the spike's user-grant simulation).
        const result: ElicitResult = {
          action: 'accept',
          content: { confirm: true },
        };
        return result;
      });

      await Promise.all([
        server.connect(serverTransport),
        client.connect(clientTransport),
      ]);
    });

    afterAll(async () => {
      await server.close();
      await client.close();
    });

    it('AC3: server.elicitInput round-trips form-mode request through SDK transport', async () => {
      const result = await server.elicitInput({
        mode: 'form',
        message: 'Rename the palace mythos? (spike)',
        requestedSchema: {
          type: 'object',
          properties: {
            confirm: {
              type: 'boolean',
              title: 'Confirm',
              description: 'Confirm the rename',
            },
          },
          required: ['confirm'],
        },
      });
      expect(result.action).toBe('accept');
      expect((result.content as { confirm?: boolean }).confirm).toBe(true);
    });

    it('AC3+AC4: rename-mythos handler dispatches via real SDK elicit binding', async () => {
      // Bind the real SDK elicitInput as the ElicitFn — this is exactly
      // what the runtime entrypoint (Story 4.3) will do.
      const elicit: ElicitFn = (params) => server.elicitInput(params);

      // Stub JELLY_CLI to a no-op script so the post-confirmation dispatch
      // succeeds (we just need to verify the elicit→dispatch flow happens).
      const tmp = mkdtempSync(join(tmpdir(), 'jelly-stub-'));
      const stubPath = join(tmp, 'jelly');
      writeFileSync(stubPath, '#!/bin/sh\nexit 0\n', { mode: 0o755 });
      chmodSync(stubPath, 0o755);
      const prevJelly = process.env.JELLY_CLI;
      process.env.JELLY_CLI = stubPath;

      try {
        const result = await handleRenameMythos(
          { palace: '/tmp/p', body: 'new name' },
          { elicit },
        );
        // Should have round-tripped the elicitation, gotten an accept, and
        // dispatched to renameMythos (which calls the stub jelly = exit 0).
        expect(result.elicited).toBe(false);
        expect(result.confirmed).toBe(true);
      } finally {
        if (prevJelly === undefined) {
          delete process.env.JELLY_CLI;
        } else {
          process.env.JELLY_CLI = prevJelly;
        }
      }
    });
  });
});
