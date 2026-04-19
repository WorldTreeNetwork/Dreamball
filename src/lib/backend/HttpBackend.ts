/**
 * HttpBackend — typed HTTP client for the locally-running `jelly-server`.
 *
 * Uses Eden's `treaty` for type-safe calls. The server app type is imported
 * via a conditional path: when the jelly-server package is available in the
 * same workspace the full type flows through; otherwise it falls back to
 * `unknown` and the fetch calls remain functional but untyped.
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
		const items = await this.getJSON<Array<{ fingerprint: string; summary: unknown }>>('/dreamballs');
		return items.map((item) => ({
			fingerprint: item.fingerprint as Fingerprint,
			summary: item.summary as DreamBall
		}));
	}

	async unlockRelic(relic: DreamBall, _guildKey: Uint8Array): Promise<DreamBall> {
		const identity = (relic as unknown as Record<string, unknown>)['identity'];
		if (typeof identity !== 'string') throw new Error('relic missing identity field');
		const fp = identity.startsWith('b58:') ? identity.slice(4) : identity;
		return this.postJSON<DreamBall>(`/relics/${encodeURIComponent(fp)}/unlock`, {});
	}

	async resolvePermittedSlots(ball: DreamBall, viewer: Fingerprint | null): Promise<string[]> {
		const vfp = viewer ?? this.viewer;
		const policy = (ball as unknown as Record<string, unknown>)['policy'] as
			| { public: string[]; 'guild-only': string[]; 'admin-only': string[] }
			| undefined;
		if (!policy) return [...ALWAYS_PUBLIC_SLOTS, 'look', 'feel'];
		if (!vfp) return policy.public;
		const member = ((ball as unknown as Record<string, unknown>)['member'] ?? []) as string[];
		const admin = ((ball as unknown as Record<string, unknown>)['admin'] ?? []) as string[];
		const isMember = member.includes(vfp);
		const isAdmin = admin.includes(vfp);
		const slots = new Set(policy.public);
		if (isMember || isAdmin) for (const s of policy['guild-only']) slots.add(s);
		if (isAdmin) for (const s of policy['admin-only']) slots.add(s);
		return [...slots];
	}
}
