/**
 * Public surface of the `@dreamball/svelte` library.
 *
 * Consumers:
 *   import { DreamBallViewer, MockBackend, mockBall } from '$lib';
 */

export { default as DreamBallViewer } from './components/DreamBallViewer.svelte';
export { default as DreamBallCard } from './components/DreamBallCard.svelte';
export { default as SealedRelic } from './components/SealedRelic.svelte';
export { default as Wearer } from './components/Wearer.svelte';

export { default as ThumbnailLens } from './lenses/ThumbnailLens.svelte';
export { default as AvatarLens } from './lenses/AvatarLens.svelte';
export { default as KnowledgeGraphLens } from './lenses/KnowledgeGraphLens.svelte';
export { default as EmotionalStateLens } from './lenses/EmotionalStateLens.svelte';
export { default as OmnisphericalLens } from './lenses/OmnisphericalLens.svelte';
export { default as FlatLens } from './lenses/FlatLens.svelte';
export { default as PhoneLens } from './lenses/PhoneLens.svelte';
export { default as SplatLens } from './lenses/SplatLens.svelte';

export {
	SPLAT_MEDIA_TYPES,
	isSplatAsset,
	mediaTypeFromUrl,
	type SplatMediaType
} from './splat/media-types.js';

export {
	parseJelly,
	parseJellyToJson,
	parseJellyUnvalidated,
	safeParseJelly,
	verifyJelly,
	VERIFY_OK,
	VERIFY_NO_ED25519,
	VERIFY_FAILED,
	VERIFY_PARSE_ERROR,
	type VerifyResult
} from './wasm/loader.js';

export {
	DreamBallSchema,
	DreamBallAvatarSchema,
	DreamBallAgentSchema,
	DreamBallToolSchema,
	DreamBallRelicSchema,
	DreamBallFieldSchema,
	DreamBallGuildSchema,
	DreamBallUntypedSchema,
	SignatureSchema,
	AssetSchema,
	LookSchema,
	FeelSchema,
	ActSchema,
	SkillSchema,
	MemorySchema,
	KnowledgeGraphSchema,
	EmotionalRegisterSchema,
	GuildPolicySchema,
	OmnisphericalGridSchema,
	parseDreamBall,
	safeParseDreamBall,
	type DreamBallValidated,
	type ParseResult
} from './generated/schemas.js';

export { ALL_LENSES, type LensName } from './lenses/lens-types.js';

export { MockBackend, mockBall } from './backend/MockBackend.js';
export { HttpBackend } from './backend/HttpBackend.js';
export type { JellyBackend } from './backend/JellyBackend.js';
export { ALWAYS_PUBLIC_SLOTS } from './backend/JellyBackend.js';

export * from './generated/types.js';
export {
	decodeEnvelope,
	base58Encode,
	base58Decode,
	fromBase58Tagged,
	toBase58Tagged
} from './generated/cbor.js';
