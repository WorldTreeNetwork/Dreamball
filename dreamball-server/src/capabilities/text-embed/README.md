# `text-embed/1` — capability/provider prototype

This directory is a **working prototype** of the capability/provider model
proposed in
[`docs/decisions/2026-05-31-capability-provider-model.md`](../../../../docs/decisions/2026-05-31-capability-provider-model.md)
(§9, step 2 — "formalize the embedding capability first").

## Why this capability was chosen as the proof

The embedding capability already had **three providers** (`qwen3` local ONNX,
`runpod` remote GPU, deterministic `mock`) selected by an env-var `if/else`
smeared across `routes/embed.ts` *and* `embedding/qwen3.ts`'s `loadQwen3Model`.
The pattern was already present; it was missing only a **declared interface**
and a **single binding point**. So extracting it demonstrates the model with
the least invention and zero wire-format change.

## Shape

| File | Role | Maps to decision doc |
|---|---|---|
| `interface.ts` | The `text-embed/1` contract: 256d / `mrl-256` output, the `TextEmbedProvider` shape. A DreamBall depends on *this*, never a provider. | §3 (interface vs. provider), §4 (Category B service) |
| `providers.ts` | Registry of conforming providers. Registry order = binding priority (mock → runpod). | §3.1, §9 |
| `resolver.ts` | The single binding point (the `ld.so`). Idempotent; boot binds eagerly, the route binds lazily. Normalizes any provider's raw vector to the interface's `OUTPUT_DIM`. | §3 (resolver) |
| `truncate.ts` | MRL prefix truncation — a property of the capability, not of any provider. | §3 |
| `runpod.ts` | The remote-GPU provider's HTTP adapter (dependency-free). | §4 |

## 2026-08-07 — the in-process provider is gone

The seam did its job. `onnx-local` — which wrapped `embedding/qwen3.ts` and
dragged `@huggingface/transformers` (onnxruntime-node + sharp, ~600 MB
installed) into an otherwise generic protocol server — was **deleted**, along
with `src/embedding/`. Two providers remain: `mock` and `runpod`.

This is the point of the model. Hosting a model runtime is an application
concern; the substrate declares the interface and binds whatever satisfies it.
A consumer that wants local weights implements `text-embed/1` in its own
process. It does not get to make every `bun install` of the protocol server pay
for ONNX. See
[`docs/decisions/2026-08-07-substrate-palace-boundary.md`](../../../../docs/decisions/2026-08-07-substrate-palace-boundary.md).

`routes/embed.ts` and `index.ts` are now **provider-agnostic** — they call
`resolveTextEmbed()` and never name a provider.

## What this prototype is *not*

- It does **not** declare `text-embed/1` in the archiform JSON Schema's
  `capabilities` block yet (decision doc §3.1). It proves the runtime *seam*
  inside dreamball-server, in TS, not the wire-format declaration.
- Providers are **not** content-addressed / acquirable here (decision doc §6).
  They wrap in-tree implementations. Content-addressing + signature-verified
  acquisition is the next step once the seam is agreed.
- The model identity (`qwen3-embedding-0.6b`) is **contract-declared**, not
  provider-reported — a known open question (decision doc §10). It is kept
  constant here so the mock and real providers present one response identity,
  matching the existing D-012 tests.

## Verification

`bunx vitest run dreamball-server` → 30/30 pass (unchanged behavior).
`bunx tsc --noEmit -p dreamball-server/tsconfig.json` → clean.
`scripts/server-smoke.sh` boots with `DREAMBALL_EMBED_MOCK=1`, which binds the mock
provider; its `/embed` assertions (dim 256, model, `mrl-256`) are unchanged.
