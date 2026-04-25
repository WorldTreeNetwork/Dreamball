/**
 * jelly-server — Bun-native Elysia HTTP server wrapping jelly.wasm.
 *
 * Exposes DreamBall write+read operations over HTTP. Routes mirror the CLI.
 * Valibot schemas drive request/response validation.
 * Eden client provides strongly-typed access end-to-end via typeof app.
 *
 * Endpoints:
 *   POST   /dreamballs                  — mint
 *   GET    /dreamballs                  — list
 *   GET    /dreamballs/:fp              — show
 *   GET    /dreamballs/:fp/verify       — verify signature
 *   POST   /dreamballs/:fp/grow         — grow (update)
 *   POST   /dreamballs/:fp/join-guild   — join guild
 *   POST   /dreamballs/:fp/transmit     — transmit (CLI subprocess)
 *   POST   /relics                      — seal relic (CLI subprocess)
 *   POST   /relics/:id/unlock           — unlock relic (CLI subprocess)
 *   POST   /embed                       — compute 256d embedding (Qwen3, S6.1)
 *   GET    /.well-known/mcp             — MCP self-documentation
 *   GET    /.well-known/mcp/types       — JSON Schema bundle
 *   GET    /swagger                     — OpenAPI UI
 */

import { Elysia } from 'elysia';
import { swagger } from '@elysiajs/swagger';
import { cors } from '@elysiajs/cors';
import { randomUUID } from 'crypto';

import { mintRoute } from './routes/mint.js';
import { showRoute } from './routes/show.js';
import { listRoute } from './routes/list.js';
import { verifyRoute } from './routes/verify.js';
import { growRoute } from './routes/grow.js';
import { joinGuildRoute } from './routes/join-guild.js';
import { transmitRoute } from './routes/transmit.js';
import { sealRelicRoute } from './routes/seal-relic.js';
import { unlockRelicRoute } from './routes/unlock-relic.js';
import { embedRoute } from './routes/embed.js';
import { loadQwen3Model } from './embedding/qwen3.js';
import { buildMcpDoc, buildTypesDoc } from './mcp-doc.js';

const PORT = Number(process.env.JELLY_SERVER_PORT ?? 9808);

// ---------------------------------------------------------------------------
// Structured logging middleware
// One JSON line per request: { ts, method, path, status, duration_ms, request_id }
// ---------------------------------------------------------------------------

function logRequest(opts: {
  ts: string;
  method: string;
  path: string;
  status: number;
  duration_ms: number;
  request_id: string;
  error?: string;
}) {
  process.stdout.write(JSON.stringify(opts) + '\n');
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

export const app = new Elysia()
  .use(cors())
  .use(
    swagger({
      documentation: {
        info: {
          title: 'jelly-server',
          version: '0.0.1',
          description: 'DreamBall v2 protocol HTTP API'
        }
      }
    })
  )
  // Logging derive + afterHandle
  .derive(() => ({
    requestId: randomUUID(),
    startAt: Date.now()
  }))
  .onAfterHandle(({ request, set, requestId, startAt }) => {
    const status = typeof set.status === 'number' ? set.status : 200;
    logRequest({
      ts: new Date().toISOString(),
      method: request.method,
      path: new URL(request.url).pathname,
      status,
      duration_ms: Date.now() - startAt,
      request_id: requestId
    });
  })
  .onError(({ request, error, set, requestId, startAt }) => {
    const status = typeof set.status === 'number' ? set.status : 500;
    logRequest({
      ts: new Date().toISOString(),
      method: request.method,
      path: new URL(request.url).pathname,
      status,
      duration_ms: Date.now() - (startAt ?? Date.now()),
      request_id: requestId ?? 'unknown',
      error: error instanceof Error ? error.constructor.name + ': ' + error.message : String(error)
    });
  })
  // MCP self-documentation (before routes, no auth required)
  .get('/.well-known/mcp', () => buildMcpDoc(), {
    detail: { summary: 'MCP self-documentation', tags: ['meta'] }
  })
  .get('/.well-known/mcp/types', () => buildTypesDoc(), {
    detail: { summary: 'JSON Schema type bundle', tags: ['meta'] }
  })
  // Protocol routes
  .use(mintRoute)
  .use(listRoute)
  .use(showRoute)
  .use(verifyRoute)
  .use(growRoute)
  .use(joinGuildRoute)
  .use(transmitRoute)
  .use(sealRelicRoute)
  .use(unlockRelicRoute)
  .use(embedRoute);

// ---------------------------------------------------------------------------
// Start server (skipped when imported in tests)
// ---------------------------------------------------------------------------

// Listen guard: skip explicitly, OR when the runtime doesn't support
// `.listen()` (e.g. Vitest's worker uses Elysia's WebStandard adapter
// which only exposes `.fetch()`). We try/catch both to keep this file
// importable everywhere without an env-var contract that ESM hoisting
// can defeat.
if (process.env.JELLY_SERVER_NO_LISTEN !== '1') {
  try {
    // Load Qwen3-Embedding-0.6B once at boot — fail-fast if model absent (S6.1 AC10).
    // In mock mode (JELLY_EMBED_MOCK=1), loadQwen3Model() is a no-op.
    // This runs inside the listen guard so test imports (JELLY_SERVER_NO_LISTEN=1)
    // never trigger the model load or process.exit path.
    await loadQwen3Model().catch((err: unknown) => {
      process.stderr.write(
        JSON.stringify({
          ts: new Date().toISOString(),
          event: 'embedding_model_load_failed',
          error: err instanceof Error ? err.message : String(err),
        }) + '\n'
      );
      process.exit(1);
    });

    app.listen(PORT, () => {
      process.stdout.write(
        JSON.stringify({
          ts: new Date().toISOString(),
          event: 'server_start',
          port: PORT,
          swagger: `http://localhost:${PORT}/swagger`,
          mcp: `http://localhost:${PORT}/.well-known/mcp`
        }) + '\n'
      );
    });
  } catch {
    // WebStandard runtimes (Vitest worker, Cloudflare Workers, etc.) don't
    // support .listen — consumers of this module will use app.handle()
    // directly. Non-fatal.
  }
}

