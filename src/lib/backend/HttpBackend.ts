/**
 * HttpBackend — proxies every call to a locally-running `jelly-server`
 * HTTP daemon (A2 path from the v2 PRD).
 *
 * For v2 MVP the server does not yet exist in proper form; it's intended
 * as a thin shim that shells out to the Zig `jelly` CLI per request. Both
 * the server and the proxy-recryption code paths are expected to mature
 * together post-v2.
 *
 * ⚠ TODO-CRYPTO: replace before prod. The HTTP path currently trusts the
 * server blindly; a real implementation needs at minimum a signature
 * check on every DreamBall returned + Guild keyspace ACL checks before
 * unlocking relics.
 */

import type { DreamBall, Fingerprint } from '../generated/types.js';
import { ALWAYS_PUBLIC_SLOTS, type JellyBackend } from './JellyBackend.js';

export interface HttpBackendOptions {
	/** Base URL for the jelly-server daemon. Defaults to http://127.0.0.1:9808. */
	baseUrl?: string;
	/** Current viewer identity (optional — used for slot permission resolution). */
	viewer?: Fingerprint | null;
}

export class HttpBackend implements JellyBackend {
	private readonly baseUrl: string;
	private readonly viewer: Fingerprint | null;

	constructor(opts: HttpBackendOptions = {}) {
		this.baseUrl = opts.baseUrl ?? 'http://127.0.0.1:9808';
		this.viewer = opts.viewer ?? null;
	}

	private async getJSON<T>(path: string): Promise<T> {
		const res = await fetch(new URL(path, this.baseUrl));
		if (!res.ok) throw new Error(`jelly-server ${path}: ${res.status} ${res.statusText}`);
		return (await res.json()) as T;
	}

	private async postJSON<T>(path: string, body: unknown): Promise<T> {
		const res = await fetch(new URL(path, this.baseUrl), {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify(body)
		});
		if (!res.ok) throw new Error(`jelly-server ${path}: ${res.status} ${res.statusText}`);
		return (await res.json()) as T;
	}

	async load(reference: string | Fingerprint): Promise<DreamBall> {
		return this.getJSON<DreamBall>(`/dreamballs/${encodeURIComponent(reference)}`);
	}

	async list(): Promise<Array<{ fingerprint: Fingerprint; summary: DreamBall }>> {
		return this.getJSON('/dreamballs');
	}

	async unlockRelic(relic: DreamBall, guildKey: Uint8Array): Promise<DreamBall> {
		return this.postJSON<DreamBall>('/unlock', {
			relic,
			// TODO-CRYPTO: base64 wrapping is just to get bytes across JSON; real
			// impl will never send the raw guild key over the wire.
			guildKey: Buffer.from(guildKey).toString('base64')
		});
	}

	async resolvePermittedSlots(ball: DreamBall, viewer: Fingerprint | null): Promise<string[]> {
		const vfp = viewer ?? this.viewer;
		const policy = ball.policy;
		if (!policy) return [...ALWAYS_PUBLIC_SLOTS, 'look', 'feel'];
		if (!vfp) return policy.public;
		const isMember = (ball.member ?? []).includes(vfp);
		const isAdmin = (ball.admin ?? []).includes(vfp);
		const slots = new Set(policy.public);
		if (isMember || isAdmin) for (const s of policy['guild-only']) slots.add(s);
		if (isAdmin) for (const s of policy['admin-only']) slots.add(s);
		return [...slots];
	}
}
