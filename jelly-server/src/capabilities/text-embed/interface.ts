/**
 * text-embed/1 — capability interface (PROTOTYPE).
 *
 * Demonstrates docs/decisions/2026-05-31-capability-provider-model.md §9 step 2:
 * the embedding capability already had three providers behind one route, selected
 * by a scattered env-var if/else. This file declares the *interface* those
 * providers satisfy; `resolver.ts` is the single binding point; `providers.ts`
 * holds the conforming implementations.
 *
 * The interface is the contract a DreamBall/archiform depends on — never a
 * specific provider. It is a Category-B (stateful host service) capability:
 * the host binds a provider; the ball declares the need. See the decision doc §4.
 *
 * NOTE (prototype scope): this is a TS-level interface inside jelly-server. The
 * production shape would declare `text-embed/1` in the archiform JSON Schema's
 * `capabilities` block (decision doc §3.1) and resolve content-addressed
 * providers. Here we prove the *seam*, not the wire format.
 */

/** Capability interface identifier (name/major). Providers advertise this. */
export const INTERFACE = 'text-embed/1' as const;

/**
 * The capability's declared *response contract* (D-012). These describe what
 * the capability emits, independent of which provider is bound:
 *   - every bound provider's raw vector is MRL-truncated to OUTPUT_DIM
 *   - the response model identity is the capability's declared model
 *
 * Provider-reported vs. contract-declared model identity is an open question
 * (decision doc §10); for the palace binding all real providers run
 * qwen3-embedding-0.6b and the mock stands in for it, so one constant holds.
 */
export const OUTPUT_DIM = 256 as const;
export const TRUNCATION = 'mrl-256' as const;
export const MODEL_IDENTITY = 'qwen3-embedding-0.6b' as const;

/**
 * A provider satisfies `text-embed/1` by producing a raw embedding vector for a
 * content string. The resolver normalizes (MRL-truncates) it to the interface's
 * OUTPUT_DIM, so providers may emit any nativeDim >= OUTPUT_DIM.
 */
export interface TextEmbedProvider {
  /** Stable provider id (the content-addressed identity, in the full model). */
  readonly id: string;
  /** Category B = stateful host service (decision doc §4). */
  readonly category: 'service';
  /** The `service/text-embed` interface version this provider implements
   *  (enforced-semver §10.1; matched against a requirement's range). */
  readonly implementsVersion: string;
  /** Raw output dimension before MRL truncation (e.g. 1024 for qwen3, 256 mock). */
  readonly nativeDim: number;
  /** Cheap, synchronous, non-throwing precondition check used for binding. */
  available(): boolean;
  /** Acquire/warm the provider (load weights, read config). Idempotent. */
  load(): Promise<void>;
  /** Produce the raw (nativeDim) embedding for one content string. */
  embedRaw(content: string): Promise<Float32Array>;
}

/** A provider that has been selected, loaded, and normalized to the interface. */
export interface BoundTextEmbedder {
  readonly providerId: string;
  readonly modelIdentity: string;
  readonly outputDim: number;
  readonly truncation: string;
  /** Content -> OUTPUT_DIM vector (MRL-truncated). The provider-agnostic call. */
  embed(content: string): Promise<Float32Array>;
}
