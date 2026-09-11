/**
 * Coverage data-input — load a signed coverage snapshot for a /mesh consumer.
 *
 * Coverage is a labeled assertion on a ball/1 node, not a look/feel/act axis
 * and not the D-035 closed action-attribute object. Decode is always
 * dreamball.wasm verifyBall then parseBall. TypeScript does not read CBOR.
 *
 * Address by Ed25519 fingerprint or transmittable {bucket, filename}. Identity
 * after parse is still the envelope identity, not the store locator.
 */

import type { Coverage } from './generated/types.js';
import type { DreamBallValidated } from './generated/schemas.js';
import {
	type TransmittableLocator,
	TransmittableNotFoundError,
	TransmittableParseError,
	TransmittableVerifyError
} from './transmittable.js';
import { parseBall, verifyBall } from './wasm/loader.js';

export type CoverageAddress = { fingerprint: string } | TransmittableLocator;

export type CoverageBytesSource = {
	/** Return signed .ball bytes, or null if the object is missing. */
	fetch(address: CoverageAddress): Promise<Uint8Array | null>;
};

export type CoverageLoadOk = {
	ok: true;
	coverage: Coverage;
	identity: string;
	ball: DreamBallValidated;
};

export type CoverageLoadErr = {
	ok: false;
	code: 'not-found' | 'verify-failed' | 'parse-failed' | 'no-coverage';
	reason: string;
};

export type CoverageLoadResult = CoverageLoadOk | CoverageLoadErr;

export function isTransmittableAddress(address: CoverageAddress): address is TransmittableLocator {
	return 'bucket' in address && 'filename' in address;
}

export function addressKey(address: CoverageAddress): string {
	if (isTransmittableAddress(address)) return `tx:${address.bucket}/${address.filename}`;
	return `fp:${address.fingerprint}`;
}

/** In-memory source for tests and static fixtures. */
export function memoryCoverageSource(objects: Map<string, Uint8Array>): CoverageBytesSource {
	return {
		async fetch(address) {
			return objects.get(addressKey(address)) ?? null;
		}
	};
}

function locatorFor(address: CoverageAddress): TransmittableLocator {
	if (isTransmittableAddress(address)) return address;
	return { bucket: 'fingerprint', filename: address.fingerprint };
}

/**
 * Verify+parse signed envelope bytes through wasm. No invented ball on failure.
 */
export async function loadCoverageFromBytes(bytes: Uint8Array): Promise<CoverageLoadResult> {
	const verified = await verifyBall(bytes);
	if (!verified.ok) {
		return { ok: false, code: 'verify-failed', reason: verified.reason };
	}
	try {
		const ball = await parseBall(bytes);
		const coverage = ball.coverage;
		if (!coverage) {
			return { ok: false, code: 'no-coverage', reason: 'coverage attribute missing' };
		}
		return { ok: true, coverage, identity: ball.identity, ball };
	} catch (e) {
		const reason = e instanceof Error ? e.message : String(e);
		return { ok: false, code: 'parse-failed', reason };
	}
}

/**
 * Load coverage by fingerprint or transmittable locator.
 *
 * A /mesh consumer supplies a fetch that returns signed .ball bytes:
 *
 *   loadCoverage({ bucket: 'mesh', filename: 'lightning-fleet.ball' }, {
 *     fetch: async (addr) => {
 *       const url = isTransmittableAddress(addr)
 *         ? `/coverage/${addr.filename}`
 *         : `/dreamballs/${addr.fingerprint}.ball`;
 *       const res = await fetch(url);
 *       if (res.status === 404) return null;
 *       if (!res.ok) throw new Error(`${res.status}`);
 *       return new Uint8Array(await res.arrayBuffer());
 *     }
 *   })
 */
export async function loadCoverage(
	address: CoverageAddress,
	source: CoverageBytesSource
): Promise<CoverageLoadResult> {
	let bytes: Uint8Array | null;
	try {
		bytes = await source.fetch(address);
	} catch (e) {
		const reason = e instanceof Error ? e.message : String(e);
		return { ok: false, code: 'not-found', reason };
	}
	if (bytes === null) {
		const loc = locatorFor(address);
		return {
			ok: false,
			code: 'not-found',
			reason: new TransmittableNotFoundError(loc).message
		};
	}
	const result = await loadCoverageFromBytes(bytes);
	if (result.ok) return result;
	const loc = locatorFor(address);
	if (result.code === 'verify-failed') {
		return {
			ok: false,
			code: 'verify-failed',
			reason: new TransmittableVerifyError(loc, result.reason).reason
		};
	}
	if (result.code === 'parse-failed') {
		return {
			ok: false,
			code: 'parse-failed',
			reason: new TransmittableParseError(loc, result.reason).reason
		};
	}
	return result;
}
