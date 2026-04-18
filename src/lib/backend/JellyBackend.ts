/**
 * JellyBackend — thin interface to the crypto/authoring layer.
 *
 * Every renderer call goes through this interface. Two default
 * implementations ship:
 *
 *   - `MockBackend`: generates fixture DreamBalls in-memory; good for
 *     Storybook + Vitest; does NOT do real crypto.
 *   - `HttpBackend`: proxies to a locally-running `jelly-server`
 *     HTTP daemon (A2 from the v2 PRD).
 *
 * The interface is minimal on purpose — callers should be able to
 * swap backends without the components noticing.
 *
 * ⚠ TODO-CRYPTO: replace before prod. The Mock backend lies about
 * signatures and guild-key decryption. The Http backend's current
 * wire protocol assumes the server is also mocked. Real recrypt
 * proxy-recryption + Ed25519/ML-DSA signing land post-v2.
 */

import type { DreamBall, Fingerprint } from '../generated/types.js';

export interface JellyBackend {
	/** Load a DreamBall by its file path or identity fingerprint. */
	load(reference: string | Fingerprint): Promise<DreamBall>;

	/** List all DreamBalls known to this backend (fingerprint + summary). */
	list(): Promise<Array<{ fingerprint: Fingerprint; summary: DreamBall }>>;

	/**
	 * Attempt to unlock a sealed relic. The resolved value is the inner
	 * DreamBall on success. Throws on missing-key, wrong-guild, or
	 * corrupt-payload.
	 *
	 * TODO-CRYPTO: replace before prod — real unlock requires Guild keyspace
	 * proxy-recryption.
	 */
	unlockRelic(relic: DreamBall, guildKey: Uint8Array): Promise<DreamBall>;

	/**
	 * Which slots of `ball` is `viewer` allowed to see? Resolves the guild
	 * policy and returns the set of slot names. Used by the renderer to
	 * filter lens props for the observer persona.
	 */
	resolvePermittedSlots(ball: DreamBall, viewer: Fingerprint | null): Promise<string[]>;
}

/** Minimum slot set that is always public regardless of guild policy. */
export const ALWAYS_PUBLIC_SLOTS: readonly string[] = [
	'type',
	'format-version',
	'stage',
	'identity',
	'genesis-hash',
	'revision',
	'name'
];
