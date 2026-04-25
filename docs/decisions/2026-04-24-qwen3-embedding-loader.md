# ADR 2026-04-24: Qwen3-Embedding-0.6B loader — @huggingface/transformers via onnxruntime-node

**Date**: 2026-04-24
**Sprint**: sprint-001
**Story**: S6.1
**Status**: ACCEPTED

## Context

S6.1 requires jelly-server to host Qwen3-Embedding-0.6B with MRL truncation to 256d.
D-002 locks the model; D-012 locks the HTTP wire shape. The open question is:
**how does jelly-server load and run the ONNX model in the Bun runtime?**

Three options were considered:

1. **`@huggingface/transformers` (transformers.js) via `onnxruntime-node`** — JS-native,
   no Python sidecar, loads ONNX models from a local directory.
2. **`onnxruntime-node` directly** — lower-level, requires manual tokenizer wiring.
3. **Python sidecar** — separate process, inter-process communication overhead,
   non-Bun deployment complexity.

## Decision

**Option 1 — `@huggingface/transformers@4.2.0` with `onnxruntime-node@1.24.3`.**

The `onnx-community/Qwen3-Embedding-0.6B-ONNX` repository on HuggingFace Hub provides
a ready-made ONNX export of the model. `@huggingface/transformers` bundles
`onnxruntime-node` as a peer dependency, handling tokenization, padding, and pooling
in JS without a Python environment.

Concrete loader call:
```ts
const { pipeline, env } = await import('@huggingface/transformers');
env.allowRemoteModels = false;   // local-only: no network calls
env.localModelPath = modelPath;  // pinned to JELLY_EMBED_MODEL_PATH
const pipe = await pipeline('feature-extraction', modelPath, { dtype: 'fp32' });
```

MRL truncation takes the first 256 dims of the 1024d output (AC3 semantics).

## Why not option 2 (onnxruntime-node directly)

Requires hand-rolling the BPE tokenizer, attention mask logic, and mean-pooling
for Qwen3. `@huggingface/transformers` already does this correctly for the
`feature-extraction` pipeline. Reinventing it would be a `TODO-EMBEDDING` work item
with higher risk of subtle divergence from the reference tokenizer.

## Why not option 3 (Python sidecar)

Adds a Python runtime dependency to a Bun-native server. Deployment complexity
increases; the cross-process IPC boundary is another failure mode. The cross-runtime
invariant (ARCHITECTURE.md ADR-1) prefers Bun-native paths.

## Deferred

The model weights are NOT bundled in the repository. The server fails fast at boot
if `JELLY_EMBED_MODEL_PATH` is absent (`embedding model not found at <path>`).
Download procedure is a `TODO-EMBEDDING: bring-model-local-or-byo` follow-up:

```
# Download ONNX model (future script)
bun run scripts/download-embed-model.ts
# or: huggingface-cli download onnx-community/Qwen3-Embedding-0.6B-ONNX
```

In CI and tests, `JELLY_EMBED_MOCK=1` activates the deterministic blake3-seeded
mock in `jelly-server/src/routes/embed.mock.ts`, which produces the same 256d float
array for the same input without any model weights.

## Test seam

`JELLY_EMBED_MOCK=1` → `embed.mock.ts` path (deterministic, no ONNX).
`JELLY_EMBED_MOCK` unset + `JELLY_EMBED_MODEL_PATH` set → real Qwen3 ONNX path.
`JELLY_EMBED_MODEL_PATH` unset → fail-fast at boot with clear error message.

## Consequences

- `jelly-server/package.json` gains `@huggingface/transformers@^4.2.0`.
- Model weights (~600 MB for fp32 ONNX) must be provisioned before production boot.
- `onnxruntime-node` native addon runs on macOS/Linux/Windows (the three Bun targets).
- The `env.allowRemoteModels = false` guard prevents any network calls during
  inference — satisfying NFR11 (sanctioned exit) and NFR13 (no implicit exfiltration).
- Future: swap `onnx-community/Qwen3-Embedding-0.6B-ONNX` for a quantised variant
  (`electroglyph/Qwen3-Embedding-0.6B-onnx-uint8`) to halve memory; the MRL prefix
  property is preserved under quantisation.

## Addendum 2026-04-25 — Runpod Serverless backend

After S6.1 landed, a third backend was wired in: **Runpod Serverless** running
the same `qwen3-embedding:0.6b` Ollama tag the sibling Negotiated project uses.

`jelly-server/src/embedding/runpod.ts` posts the OpenAI-compatible `/v1/embeddings`
body wrapped in Runpod's `{ input: { openai_route, openai_input } }` envelope to
`https://api.runpod.ai/v2/{endpointId}/runsync`, falling back to async `/run` +
`/status/{id}` polling when the worker is cold.

Backend selection order in `qwen3.ts` is now:
1. `JELLY_EMBED_MOCK=1` → deterministic mock
2. `RUNPOD_SERVERLESS_ENDPOINT_ID` + `RUNPOD_API_KEY` → Runpod
3. `JELLY_EMBED_MODEL_PATH` (default `./models/Qwen3-Embedding-0.6B-ONNX`) → local ONNX
4. None → fail-fast

The Runpod path lets developers run real embeddings against shared GPU without
provisioning local weights. `JELLY_EMBED_RUNPOD_TIMEOUT_MS` controls poll budget
(default 5 min, since serverless cold-start can take minutes when the pool is
fully idle). Returned 1024d vectors flow through the same `truncateMrl(_, 256)`
path as the local backend, so the wire shape is identical for downstream callers.
