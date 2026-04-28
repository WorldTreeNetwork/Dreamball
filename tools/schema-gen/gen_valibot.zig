//! Story 1.3 — gen_valibot per-target generator.
//!
//! Emits Valibot runtime validators for the DreamBall root protocol
//! to `src/lib/generated/schemas.ts`. Per NFR8 (validate-on-publish,
//! not validate-on-decode) these validators are exported for callers
//! at publish boundaries (jelly-server ingest, mint-time authoring,
//! manual replay tools). The generated decoders in `cbor.ts` do NOT
//! call `Valibot.parse` / `safeParse`; that's the AC7 grep audit.
//!
//! During the D-030 Option A shadow phase the canonical body is the
//! same byte-text the legacy generator emits. Story 1.4 wires the
//! byte-equivalence diff that gates final cutover.

const std = @import("std");
const main_mod = @import("main.zig");

const OUT_PATH = "src/lib/generated/schemas.ts";

pub fn generate(ctx: *const main_mod.GeneratorCtx) !void {
    try ctx.writeOutput(OUT_PATH, BODY, .ts);
}

const BODY =
    \\// Valibot runtime validators for the DreamBall v2 protocol. Matches
    \\// one-to-one the interfaces in `./types.ts`. Use these to validate
    \\// JSON that came in from the wire (e.g., from the WASM parser or
    \\// an HTTP response) at publish boundaries — NOT in decode hot paths
    \\// (NFR8: validate-on-publish, not validate-on-decode).
    \\//
    \\// Two entry-points worth knowing:
    \\//   - DreamBallSchema      — top-level; discriminates on `type`
    \\//   - ParseResult<T>       — tagged { success: true, data } | {
    \\//                            success: false, issues }
    \\
    \\import * as v from 'valibot';
    \\import type { InferOutput } from 'valibot';
    \\
    \\// ========================================================================
    \\// Primitives
    \\// ========================================================================
    \\
    \\/** Base58-wrapped bytes — the protocol's canonical form for 32-byte
    \\ *  identity / hash / fingerprint fields in JSON. */
    \\export const Base58Schema = v.pipe(
    \\  v.string(),
    \\  v.regex(/^b58:[1-9A-HJ-NP-Za-km-z]*$/, 'expected "b58:..." prefix')
    \\);
    \\
    \\export const Rfc3339Schema = v.pipe(
    \\  v.string(),
    \\  v.regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/, 'expected RFC3339 UTC')
    \\);
    \\
    \\export const SignatureAlgSchema = v.picklist(['ed25519', 'ml-dsa-87']);
    \\
    \\export const SignatureSchema = v.object({
    \\  alg: SignatureAlgSchema,
    \\  value: Base58Schema
    \\});
    \\
    \\// ========================================================================
    \\// v1 nested — look / feel / act / asset / skill
    \\// ========================================================================
    \\
    \\export const AssetSchema = v.object({
    \\  'media-type': v.string(),
    \\  hash: Base58Schema,
    \\  url: v.optional(v.array(v.string())),
    \\  embedded: v.optional(Base58Schema),
    \\  size: v.optional(v.number()),
    \\  note: v.optional(v.string())
    \\});
    \\
    \\export const LookSchema = v.object({
    \\  asset: v.optional(v.array(AssetSchema)),
    \\  preview: v.optional(AssetSchema),
    \\  background: v.optional(v.string()),
    \\  note: v.optional(v.string())
    \\});
    \\
    \\export const FeelSchema = v.object({
    \\  personality: v.optional(v.string()),
    \\  voice: v.optional(v.string()),
    \\  values: v.optional(v.array(v.string())),
    \\  tempo: v.optional(v.string()),
    \\  note: v.optional(v.string())
    \\});
    \\
    \\export const SkillSchema = v.object({
    \\  name: v.string(),
    \\  trigger: v.optional(v.string()),
    \\  body: v.optional(v.string()),
    \\  asset: v.optional(AssetSchema),
    \\  requires: v.optional(v.array(v.string())),
    \\  note: v.optional(v.string())
    \\});
    \\
    \\export const ActSchema = v.object({
    \\  model: v.optional(v.string()),
    \\  'system-prompt': v.optional(v.string()),
    \\  skill: v.optional(v.array(SkillSchema)),
    \\  script: v.optional(v.array(AssetSchema)),
    \\  tool: v.optional(v.array(v.string())),
    \\  note: v.optional(v.string())
    \\});
    \\
    \\// ========================================================================
    \\// v2 agent slots — memory / knowledge-graph / emotional-register /
    \\//                  interaction-set
    \\// ========================================================================
    \\
    \\export const MemoryConnectionKindSchema = v.picklist(['semantic', 'emotional', 'temporal', 'other']);
    \\
    \\export const MemoryNodeSchema = v.object({
    \\  id: v.number(),
    \\  content: v.optional(v.string()),
    \\  lookups: v.optional(v.record(v.string(), v.number())),
    \\  created: v.optional(Rfc3339Schema),
    \\  'last-recalled': v.optional(Rfc3339Schema)
    \\});
    \\
    \\export const MemoryConnectionSchema = v.object({
    \\  from: v.number(),
    \\  to: v.number(),
    \\  kind: MemoryConnectionKindSchema,
    \\  strength: v.optional(v.number()),
    \\  label: v.optional(v.string())
    \\});
    \\
    \\export const MemorySchema = v.object({
    \\  nodes: v.array(MemoryNodeSchema),
    \\  connections: v.array(MemoryConnectionSchema),
    \\  'last-updated': v.optional(Rfc3339Schema)
    \\});
    \\
    \\export const TripleSchema = v.object({
    \\  from: v.string(),
    \\  label: v.string(),
    \\  to: v.string()
    \\});
    \\
    \\export const KnowledgeGraphSchema = v.object({
    \\  triples: v.array(TripleSchema),
    \\  source: v.optional(v.string())
    \\});
    \\
    \\export const EmotionalAxisSchema = v.object({
    \\  name: v.string(),
    \\  value: v.number(),
    \\  min: v.optional(v.number()),
    \\  max: v.optional(v.number())
    \\});
    \\
    \\export const EmotionalRegisterSchema = v.object({
    \\  axes: v.array(EmotionalAxisSchema),
    \\  'observed-at': v.optional(Rfc3339Schema)
    \\});
    \\
    \\export const InteractionKindSchema = v.picklist(['speak', 'listen', 'act', 'receive']);
    \\
    \\export const InteractionSchema = v.object({
    \\  turn: v.number(),
    \\  actor: Base58Schema,
    \\  kind: InteractionKindSchema,
    \\  content: v.optional(v.string()),
    \\  timestamp: v.optional(Rfc3339Schema),
    \\  outcome: v.optional(v.string())
    \\});
    \\
    \\export const InteractionSetSchema = v.object({
    \\  'set-id': Base58Schema,
    \\  interactions: v.array(InteractionSchema),
    \\  created: v.optional(Rfc3339Schema)
    \\});
    \\
    \\// ========================================================================
    \\// Guild / Relic / secrets / omnispherical grid
    \\// ========================================================================
    \\
    \\export const GuildPolicySchema = v.object({
    \\  public: v.array(v.string()),
    \\  'guild-only': v.array(v.string()),
    \\  'admin-only': v.array(v.string()),
    \\  note: v.optional(v.string())
    \\});
    \\
    \\export const GuildMembershipSchema = v.object({
    \\  member: Base58Schema,
    \\  'is-admin': v.optional(v.boolean())
    \\});
    \\
    \\export const Vec3Schema = v.object({
    \\  x: v.number(),
    \\  y: v.number(),
    \\  z: v.number()
    \\});
    \\
    \\export const CameraRingSchema = v.object({
    \\  radius: v.number(),
    \\  tilt: v.number(),
    \\  fov: v.number()
    \\});
    \\
    \\export const OmnisphericalGridSchema = v.object({
    \\  'pole-north': v.optional(Vec3Schema),
    \\  'pole-south': v.optional(Vec3Schema),
    \\  'camera-ring': v.optional(v.array(CameraRingSchema)),
    \\  'layer-depth': v.optional(v.number()),
    \\  resolution: v.optional(v.number()),
    \\  note: v.optional(v.string())
    \\});
    \\
    \\export const SecretRefSchema = v.object({
    \\  name: v.string(),
    \\  locator: v.string(),
    \\  'issued-by': v.optional(Base58Schema),
    \\  description: v.optional(v.string())
    \\});
    \\
    \\// ========================================================================
    \\// DreamBall — common core fields, then per-type variants
    \\// ========================================================================
    \\
    \\const commonCore = {
    \\  stage: v.picklist(['seed', 'dreamball', 'dragonball']),
    \\  identity: Base58Schema,
    \\  'genesis-hash': Base58Schema,
    \\  revision: v.number(),
    \\  'format-version': v.union([v.literal(1), v.literal(2)]),
    \\  name: v.optional(v.string()),
    \\  created: v.optional(Rfc3339Schema),
    \\  updated: v.optional(Rfc3339Schema),
    \\  note: v.optional(v.string()),
    \\  contains: v.optional(v.array(Base58Schema)),
    \\  'derived-from': v.optional(v.array(Base58Schema)),
    \\  guild: v.optional(v.array(Base58Schema)),
    \\  signatures: v.optional(v.array(SignatureSchema))
    \\};
    \\
    \\/** v1 legacy shape — `jelly.dreamball` with no subtype suffix. */
    \\export const DreamBallUntypedSchema = v.object({
    \\  ...commonCore,
    \\  type: v.literal('jelly.dreamball'),
    \\  look: v.optional(LookSchema),
    \\  feel: v.optional(FeelSchema),
    \\  act: v.optional(ActSchema)
    \\});
    \\
    \\export const DreamBallAvatarSchema = v.object({
    \\  ...commonCore,
    \\  type: v.literal('jelly.dreamball.avatar'),
    \\  look: v.optional(LookSchema),
    \\  feel: v.optional(FeelSchema)
    \\});
    \\
    \\export const DreamBallAgentSchema = v.object({
    \\  ...commonCore,
    \\  type: v.literal('jelly.dreamball.agent'),
    \\  look: v.optional(LookSchema),
    \\  feel: v.optional(FeelSchema),
    \\  act: v.optional(ActSchema),
    \\  memory: v.optional(MemorySchema),
    \\  'knowledge-graph': v.optional(KnowledgeGraphSchema),
    \\  'emotional-register': v.optional(EmotionalRegisterSchema),
    \\  'interaction-set': v.optional(v.array(InteractionSetSchema)),
    \\  'personality-master-prompt': v.optional(v.string()),
    \\  secret: v.optional(v.array(SecretRefSchema))
    \\});
    \\
    \\export const DreamBallToolSchema = v.object({
    \\  ...commonCore,
    \\  type: v.literal('jelly.dreamball.tool'),
    \\  skill: v.optional(SkillSchema),
    \\  'applicable-to': v.optional(v.array(v.string()))
    \\});
    \\
    \\export const DreamBallRelicSchema = v.object({
    \\  ...commonCore,
    \\  type: v.literal('jelly.dreamball.relic'),
    \\  'sealed-payload-hash': Base58Schema,
    \\  'unlock-guild': Base58Schema,
    \\  'reveal-hint': v.optional(v.string()),
    \\  'sealed-until': v.optional(Rfc3339Schema)
    \\});
    \\
    \\export const DreamBallFieldSchema = v.object({
    \\  ...commonCore,
    \\  type: v.literal('jelly.dreamball.field'),
    \\  'omnispherical-grid': v.optional(OmnisphericalGridSchema),
    \\  'ambient-palette': v.optional(v.array(v.string())),
    \\  'dream-field-id': v.optional(v.string())
    \\});
    \\
    \\export const DreamBallGuildSchema = v.object({
    \\  ...commonCore,
    \\  type: v.literal('jelly.dreamball.guild'),
    \\  'guild-name': v.optional(v.string()),
    \\  'keyspace-root-hash': v.optional(Base58Schema),
    \\  member: v.optional(v.array(Base58Schema)),
    \\  admin: v.optional(v.array(Base58Schema)),
    \\  policy: v.optional(GuildPolicySchema)
    \\});
    \\
    \\/** Top-level DreamBall — discriminated on `type`. Use this to
    \\ *  validate any incoming .jelly JSON. */
    \\export const DreamBallSchema = v.variant('type', [
    \\  DreamBallUntypedSchema,
    \\  DreamBallAvatarSchema,
    \\  DreamBallAgentSchema,
    \\  DreamBallToolSchema,
    \\  DreamBallRelicSchema,
    \\  DreamBallFieldSchema,
    \\  DreamBallGuildSchema
    \\]);
    \\
    \\export type DreamBallValidated = InferOutput<typeof DreamBallSchema>;
    \\
    \\/** Tagged-result type used by publish-boundary parse helpers in
    \\ *  `src/lib/parse.ts`. Lives in the generated module so callers
    \\ *  can re-export it without depending on the helpers themselves
    \\ *  (which would re-introduce a validator call site inside
    \\ *  `src/lib/generated/` and break NFR8 / Story 1.3 AC7). */
    \\export type ParseResult<T> =
    \\  | { success: true; data: T }
    \\  | { success: false; issues: v.BaseIssue<unknown>[] };
    \\
    \\// ========================================================================
    \\// §13 palace envelope Valibot schemas
    \\// ========================================================================
    \\
    \\export const PlacementSchema = v.object({
    \\  'child-fp': Base58Schema,
    \\  position: v.tuple([v.number(), v.number(), v.number()]),
    \\  facing: v.tuple([v.number(), v.number(), v.number(), v.number()])
    \\});
    \\
    \\export const LayoutSchema = v.object({
    \\  type: v.literal('jelly.layout'),
    \\  'format-version': v.literal(2),
    \\  placements: v.array(PlacementSchema),
    \\  note: v.optional(v.string())
    \\});
    \\
    \\export const ActionKindSchema = v.picklist([
    \\  'palace-minted',
    \\  'room-added',
    \\  'avatar-inscribed',
    \\  'aqueduct-created',
    \\  'move',
    \\  'true-naming',
    \\  'inscription-updated',
    \\  'inscription-orphaned',
    \\  'inscription-pending-embedding'
    \\]);
    \\
    \\export const TimelineSchema = v.object({
    \\  type: v.literal('jelly.timeline'),
    \\  'format-version': v.literal(3),
    \\  'palace-fp': Base58Schema,
    \\  'head-hashes': v.array(Base58Schema),
    \\  note: v.optional(v.string())
    \\});
    \\
    \\export const ActionSchema = v.object({
    \\  type: v.literal('jelly.action'),
    \\  'format-version': v.literal(3),
    \\  'action-kind': ActionKindSchema,
    \\  actor: Base58Schema,
    \\  'parent-hashes': v.array(Base58Schema),
    \\  'target-fp': v.optional(Base58Schema),
    \\  timestamp: v.optional(v.number()),
    \\  deps: v.optional(v.array(Base58Schema)),
    \\  nacks: v.optional(v.array(Base58Schema))
    \\});
    \\
    \\export const AqueductPhaseSchema = v.picklist(['in', 'out', 'standing', 'resonant']);
    \\
    \\export const AqueductSchema = v.object({
    \\  type: v.literal('jelly.aqueduct'),
    \\  'format-version': v.literal(2),
    \\  from: Base58Schema,
    \\  to: Base58Schema,
    \\  kind: v.string(),
    \\  capacity: v.number(),
    \\  strength: v.number(),
    \\  resistance: v.number(),
    \\  capacitance: v.number(),
    \\  conductance: v.optional(v.number()),
    \\  phase: v.optional(AqueductPhaseSchema),
    \\  'last-traversed': v.optional(v.number())
    \\});
    \\
    \\export const ElementTagSchema = v.object({
    \\  type: v.literal('jelly.element-tag'),
    \\  'format-version': v.literal(2),
    \\  element: v.string(),
    \\  phase: v.optional(v.string()),
    \\  note: v.optional(v.string())
    \\});
    \\
    \\export const TrustAxisSchema = v.object({
    \\  name: v.string(),
    \\  value: v.number(),
    \\  range: v.tuple([v.number(), v.number()])
    \\});
    \\
    \\export const TrustObservationSchema = v.object({
    \\  type: v.literal('jelly.trust-observation'),
    \\  'format-version': v.literal(2),
    \\  observer: Base58Schema,
    \\  about: Base58Schema,
    \\  axes: v.optional(v.array(TrustAxisSchema)),
    \\  'observed-at': v.optional(v.number()),
    \\  context: v.optional(v.string()),
    \\  signatures: v.optional(v.array(SignatureSchema))
    \\});
    \\
    \\export const InscriptionSchema = v.object({
    \\  type: v.literal('jelly.inscription'),
    \\  'format-version': v.literal(2),
    \\  surface: v.string(),
    \\  placement: v.string(),
    \\  note: v.optional(v.string())
    \\});
    \\
    \\export const MythosSchema = v.object({
    \\  type: v.literal('jelly.mythos'),
    \\  'format-version': v.literal(2),
    \\  'is-genesis': v.boolean(),
    \\  predecessor: v.optional(Base58Schema),
    \\  about: v.optional(Base58Schema),
    \\  form: v.optional(v.string()),
    \\  body: v.optional(v.string()),
    \\  'true-name': v.optional(v.string()),
    \\  'discovered-in': v.optional(Base58Schema),
    \\  synthesizes: v.optional(v.array(Base58Schema)),
    \\  'inspired-by': v.optional(v.array(Base58Schema)),
    \\  author: v.optional(Base58Schema),
    \\  'authored-at': v.optional(v.number())
    \\});
    \\
    \\export const ArchiformSchema = v.object({
    \\  type: v.literal('jelly.archiform'),
    \\  'format-version': v.literal(2),
    \\  form: v.string(),
    \\  tradition: v.optional(v.string()),
    \\  'parent-form': v.optional(v.string()),
    \\  note: v.optional(v.string())
    \\});
    \\
;
