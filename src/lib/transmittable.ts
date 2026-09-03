/**
 * Transmittable locator — object-store address for signed DreamBall bytes.
 *
 * This is an app-level adapter type, not a wire envelope. Bucket + filename
 * are store keys only. A DreamBall's identity remains its fingerprint.
 * Decode is always dreamball.wasm verifyBall then parseBall — never hand CBOR.
 *
 * Fetch lives in a later change (`add-transmittable-fetch`). This module
 * names the locator and the error vocabulary that fetch must use.
 */

export interface TransmittableLocator {
	bucket: string;
	filename: string;
}

/** Typed miss — the object does not exist. Do not invent an empty DreamBall. */
export class TransmittableNotFoundError extends Error {
	readonly code = 'transmittable-not-found' as const;
	constructor(readonly locator: TransmittableLocator) {
		super(`transmittable not found: ${locator.bucket}/${locator.filename}`);
		this.name = 'TransmittableNotFoundError';
	}
}

/** wasm verifyBall failed. `reason` is the wasm reason/code, not a second parser. */
export class TransmittableVerifyError extends Error {
	readonly code = 'transmittable-verify-failed' as const;
	constructor(
		readonly locator: TransmittableLocator,
		readonly reason: string
	) {
		super(`transmittable verify failed (${locator.bucket}/${locator.filename}): ${reason}`);
		this.name = 'TransmittableVerifyError';
	}
}

/** wasm parseBall failed. `reason` is the wasm reason/code. */
export class TransmittableParseError extends Error {
	readonly code = 'transmittable-parse-failed' as const;
	constructor(
		readonly locator: TransmittableLocator,
		readonly reason: string
	) {
		super(`transmittable parse failed (${locator.bucket}/${locator.filename}): ${reason}`);
		this.name = 'TransmittableParseError';
	}
}

export type TransmittableError =
	| TransmittableNotFoundError
	| TransmittableVerifyError
	| TransmittableParseError;

export function isTransmittableError(err: unknown): err is TransmittableError {
	return (
		err instanceof TransmittableNotFoundError ||
		err instanceof TransmittableVerifyError ||
		err instanceof TransmittableParseError
	);
}

/**
 * Build a locator. Empty/whitespace fields are invalid — they are not a
 * typed not-found (nothing was fetched yet).
 */
export function transmittableLocator(bucket: string, filename: string): TransmittableLocator {
	const b = bucket.trim();
	const f = filename.trim();
	if (!b || !f) {
		throw new TypeError('transmittable locator requires non-empty bucket and filename');
	}
	return { bucket: b, filename: f };
}

/**
 * Human-facing encoding used by the later viewer route (`?bucket=&filename=`).
 * Missing or blank params → null (empty locator), not a not-found error.
 */
export function locatorFromSearchParams(params: URLSearchParams): TransmittableLocator | null {
	const bucket = params.get('bucket') ?? '';
	const filename = params.get('filename') ?? '';
	if (!bucket.trim() || !filename.trim()) return null;
	return transmittableLocator(bucket, filename);
}
