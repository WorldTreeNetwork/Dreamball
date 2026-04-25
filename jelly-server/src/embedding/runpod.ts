/**
 * runpod.ts — RunPod Serverless adapter for Qwen3-Embedding-0.6B.
 *
 * When `RUNPOD_SERVERLESS_ENDPOINT_ID` + `RUNPOD_API_KEY` are set, jelly-server
 * proxies its `/embed` endpoint to a remote RunPod worker that hosts Ollama
 * with `qwen3-embedding:0.6b`. The worker exposes an OpenAI-compatible
 * `/v1/embeddings` route; RunPod wraps requests in `{ input: { openai_route,
 * openai_input } }` and returns `{ status, output: { data: [{embedding,...}]} }`.
 *
 * Mirrors the runpod-serverless module from the sibling Negotiated project
 * (same Ollama worker image, same model tag).
 *
 * TODO-EMBEDDING: bring-model-local-or-byo
 *   This is the "bring-your-own-GPU" exit. The local ONNX path in qwen3.ts is
 *   the "bring-model-local" exit. Either is valid; both go through the same
 *   D-012 wire shape on the wire to the client.
 */

const RUNPOD_BASE = 'https://api.runpod.ai/v2';
const POLL_INTERVAL_MS = 5_000;

// Cold-start on Runpod Serverless can take several minutes when the worker
// pool is idle. Default budget is 5 min; override with JELLY_EMBED_RUNPOD_TIMEOUT_MS.
const POLL_TIMEOUT_MS = Number(process.env.JELLY_EMBED_RUNPOD_TIMEOUT_MS ?? 300_000);
const MAX_POLL_ATTEMPTS = Math.max(1, Math.ceil(POLL_TIMEOUT_MS / POLL_INTERVAL_MS));

const EMBEDDING_MODEL = process.env.JELLY_EMBED_RUNPOD_MODEL ?? 'qwen3-embedding:0.6b';

interface OpenAIEmbeddingRequest {
  model: string;
  input: string;
  encoding_format: 'float';
}

interface OpenAIEmbeddingResponse {
  data: Array<{ embedding: number[]; index: number }>;
}

interface RunpodEnvelope {
  id?: string;
  status?: 'COMPLETED' | 'IN_QUEUE' | 'IN_PROGRESS' | 'FAILED' | string;
  output?: unknown;
  error?: string;
}

export interface RunpodConfig {
  endpointId: string;
  apiKey: string;
}

/** Returns config when both Runpod env vars are set, otherwise null. */
export function readRunpodConfig(): RunpodConfig | null {
  const endpointId = process.env.RUNPOD_SERVERLESS_ENDPOINT_ID;
  const apiKey = process.env.RUNPOD_API_KEY;
  if (endpointId && apiKey) return { endpointId, apiKey };
  return null;
}

/**
 * Embed a single string against the configured Runpod endpoint.
 * Returns the raw vector at whatever dimension Ollama emits (caller MRL-truncates).
 */
export async function embedViaRunpod(content: string, cfg: RunpodConfig): Promise<Float32Array> {
  const body: OpenAIEmbeddingRequest = {
    model: EMBEDDING_MODEL,
    input: content,
    encoding_format: 'float',
  };
  const wrapped = { input: { openai_route: '/v1/embeddings', openai_input: body } };

  const res = await fetch(`${RUNPOD_BASE}/${cfg.endpointId}/runsync`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${cfg.apiKey}`,
    },
    body: JSON.stringify(wrapped),
  });
  if (!res.ok) {
    throw new Error(`runpod runsync ${res.status}: ${await res.text()}`);
  }

  const env = (await res.json()) as RunpodEnvelope;
  const output = await resolveEnvelope(env, cfg);
  return extractEmbedding(output);
}

async function resolveEnvelope(env: RunpodEnvelope, cfg: RunpodConfig): Promise<unknown> {
  if (env.status === 'COMPLETED') return env.output;
  if (env.status === 'FAILED') throw new Error(`runpod failed: ${env.error ?? 'unknown'}`);
  if ((env.status === 'IN_QUEUE' || env.status === 'IN_PROGRESS') && env.id) {
    return pollUntilDone(env.id, cfg);
  }
  if (env.output !== undefined) return env.output;
  throw new Error(`runpod unexpected status: ${env.status}`);
}

async function pollUntilDone(jobId: string, cfg: RunpodConfig): Promise<unknown> {
  for (let attempt = 0; attempt < MAX_POLL_ATTEMPTS; attempt++) {
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
    const res = await fetch(`${RUNPOD_BASE}/${cfg.endpointId}/status/${jobId}`, {
      headers: { Authorization: `Bearer ${cfg.apiKey}` },
    });
    if (!res.ok) continue;
    const env = (await res.json()) as RunpodEnvelope;
    if (env.status === 'COMPLETED') return env.output;
    if (env.status === 'FAILED') throw new Error(`runpod job ${jobId}: ${env.error ?? 'unknown'}`);
  }
  throw new Error(`runpod job ${jobId} timed out`);
}

function extractEmbedding(output: unknown): Float32Array {
  // Runpod sometimes wraps the OpenAI response in a single-element array.
  const unwrapped =
    Array.isArray(output) && output.length === 1 ? output[0] : output;
  const openai = unwrapped as OpenAIEmbeddingResponse;
  if (!openai?.data?.[0]?.embedding) {
    throw new Error('runpod: missing data[0].embedding in response');
  }
  return new Float32Array(openai.data[0].embedding);
}
