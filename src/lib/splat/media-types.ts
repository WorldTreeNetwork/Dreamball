/**
 * Splat-asset media-type routing.
 *
 * A DreamBall's `look.asset[i]` carries a `media-type`. If that type
 * matches one of the splat formats below, the renderer routes it to
 * SplatLens (PlayCanvas) instead of AvatarLens (Threlte).
 *
 * The ordered format — `.sog` — is "ordered" in the sense that
 * PlayCanvas's SuperSplat Optimized Gaussian serialization sorts the
 * gaussian primitives by morton-order / spatial depth, which lets the
 * renderer stream + draw them progressively without a global sort.
 * That's why it gets first-class priority here. `compressed.ply` comes
 * second as the widely-shared community format.
 *
 * Future formats (`.splat`, `.spz`, `.ksplat`) land here as they're
 * plumbed through PlayCanvas or a dedicated handler.
 */

export const SPLAT_MEDIA_TYPES = [
	// SOG — SuperSplat Optimized Gaussian (ordered, streamable).
	'application/vnd.playcanvas.gsplat+sog',
	'model/gsplat-sog',
	// Compressed PLY — the community standard for gaussian splats on disk.
	'model/gsplat-ply',
	'application/vnd.playcanvas.gsplat+ply',
	// Plain PLY (non-compressed), also accepted by PlayCanvas GSplatHandler.
	'model/gsplat'
] as const;

export type SplatMediaType = (typeof SPLAT_MEDIA_TYPES)[number];

export function isSplatAsset(mediaType: string | undefined): boolean {
	if (!mediaType) return false;
	return SPLAT_MEDIA_TYPES.includes(mediaType as SplatMediaType);
}

/**
 * Infer a splat media-type from a URL extension. Not authoritative —
 * the envelope's declared `media-type` wins. Used only as a fallback
 * when `media-type` is missing or when we're deriving a type from a
 * dropped-in file.
 */
export function mediaTypeFromUrl(url: string): SplatMediaType | undefined {
	const lower = url.toLowerCase();
	if (lower.endsWith('.sog')) return 'application/vnd.playcanvas.gsplat+sog';
	if (lower.endsWith('.compressed.ply')) return 'model/gsplat-ply';
	if (lower.endsWith('.ply')) return 'model/gsplat';
	return undefined;
}
