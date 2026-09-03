# Decision Graph

Maps architecture decisions to dependent stories. Updated by /sprint-plan, /refine, /replan.

---

## D-017: Archiform Registry — aspects.sh as the registry under a 3-layer model

- 2.1: Extract Memory Palace Types into `schemas/memory-palace-0.1.0.json` + Pin
- 2.3: Genesis Envelope `archiform_fp` Field with Implicit-Binding Back-Compat
- 8.1: Author `dreamball/guestbook@0.1.0` JSON Schema + Pin + Per-Archiform Codegen [STRETCH]

---

## D-018: JSON Schema as canonical source for field shapes

- 1.1: Codegen Inversion Spike — Round-Trip Three Complex Zig Types
- 1.2: Author `schemas/root-2.0.0.json` + Pin File Format
- 1.3: Build Per-Target Generators with Provenance + Logging
- 1.4: Shadow-Generator Phase + Byte-Equivalence CI Gate
- 2.1: Extract Memory Palace Types into `schemas/memory-palace-0.1.0.json` + Pin
- 2.2: Per-Archiform Codegen Pass + Cypher DDL Byte-Equivalence
- 7.1: Update `docs/PROTOCOL.md` — Schema Vendoring + Pin Format + Wasm Trust Model + JSON Schema Pointers
- 7.2: Update `docs/ARCHITECTURE.md` Cross-Runtime Invariant + Wasm Action Host + Codegen Flow Diagram + Cross-Doc Consistency Pass

---

## D-019: Action Manifest as universal action contract

- 3.1: Action Manifest Schema in Memory Palace JSON Schema + Closed-Set Validator + Pure-Transaction Lint
- 3.2: CLI Projection Spike — Project `mint` Verb End-to-End from Action Manifest
- 3.3: CLI Projection — `inscribe` and `add-room` Verbs
- 3.4: CLI Projection — `rename-mythos` and `move` Verbs
- 3.5: Remove Hand-Written `src/cli/palace_*.zig` Stubs + CLI Dispatch Cutover
- 4.1: Generate `@dreamball/palace-client` TypeScript Client + Migrate One Bridge Site
- 4.2: Generate MCP Tool Spec + Spike MCP Elicitation Against Pinned SDK
- 4.3: MCP Server Entrypoint (`bun run mcp`)
- 5.4: Author + Run Sample `mint.wasm` End-to-End Against Wasm Host
- 8.2: Author + Run Guestbook Wasm Action End-to-End Through Host [STRETCH]
- 8.3: Project Guestbook Action to CLI Verb + Smoke Verification [STRETCH]

---

## D-020: Wasm as runtime for all executable code in DreamBalls

- 5.1: Wasm Runtime Spike — Choose Runtime; Minimal Host Loads `hello.wasm` on darwin + linux
- 5.2: Implement 5 `dreamball.*` Imports + Per-Import Tests + Structured Event Emission
- 5.3: Wasm Host Failure Paths — Verify-Before-Instantiate, Import-Violation, Memory-Limit
- 5.4: Author + Run Sample `mint.wasm` End-to-End Against Wasm Host
- 7.2: Update `docs/ARCHITECTURE.md` Cross-Runtime Invariant + Wasm Action Host + Codegen Flow Diagram + Cross-Doc Consistency Pass
- 8.2: Author + Run Guestbook Wasm Action End-to-End Through Host [STRETCH]

---

## D-021: LadybugDB transactional model — logical-commit + replay-from-CAS

- 2.1: Extract Memory Palace Types into `schemas/memory-palace-0.1.0.json` + Pin
  (Technical Notes cite D-021/D-022 as inherited mutation pattern; no further story in Epic 2+ is expected to re-litigate this pattern per D-021's intent)

---

## D-022: Bridge pattern — Zig staging → Bun bridge → promote-on-success

- 3.2: CLI Projection Spike — Project `mint` Verb End-to-End from Action Manifest
- 3.3: CLI Projection — `inscribe` and `add-room` Verbs
- 3.4: CLI Projection — `rename-mythos` and `move` Verbs
- 3.5: Remove Hand-Written `src/cli/palace_*.zig` Stubs + CLI Dispatch Cutover
- 4.1: Generate `@dreamball/palace-client` TypeScript Client + Migrate One Bridge Site
- 5.2: Implement 5 `dreamball.*` Imports + Per-Import Tests + Structured Event Emission
- 5.4: Author + Run Sample `mint.wasm` End-to-End Against Wasm Host
- 6.2: Migrate `oracle.ts oracleSignAction` + `store.recordTraversal` to Real Ed25519 Signatures
- 8.2: Author + Run Guestbook Wasm Action End-to-End Through Host [STRETCH]
- 8.3: Project Guestbook Action to CLI Verb + Smoke Verification [STRETCH]

---

## D-023: Dual-sig parameterisation through `jelly.wasm` `signActionEnvelope` export

- 5.2: Implement 5 `dreamball.*` Imports + Per-Import Tests + Structured Event Emission
- 5.4: Author + Run Sample `mint.wasm` End-to-End Against Wasm Host
- 6.1: Add `signActionEnvelope` Export to `jelly.wasm`
- 6.2: Migrate `oracle.ts oracleSignAction` + `store.recordTraversal` to Real Ed25519 Signatures

---

## D-024: Spike-before-promote default for new shaders/materials/lenses

- 1.1: Codegen Inversion Spike — Round-Trip Three Complex Zig Types
- 3.1: Action Manifest Schema in Memory Palace JSON Schema + Closed-Set Validator + Pure-Transaction Lint
- 3.2: CLI Projection Spike — Project `mint` Verb End-to-End from Action Manifest
- 4.2: Generate MCP Tool Spec + Spike MCP Elicitation Against Pinned SDK
- 5.1: Wasm Runtime Spike — Choose Runtime; Minimal Host Loads `hello.wasm` on darwin + linux
- 5.4: Author + Run Sample `mint.wasm` End-to-End Against Wasm Host
- 8.1: Author `dreamball/guestbook@0.1.0` JSON Schema + Pin + Per-Archiform Codegen [STRETCH]

---

## D-025: Forward-declare consumer seam contracts in `architecture-decisions.md`

- 3.1: Action Manifest Schema in Memory Palace JSON Schema + Closed-Set Validator + Pure-Transaction Lint
- 5.5: Author `docs/dreamball-imports.md` Enumerating the 5-Import Surface
- 6.1: Add `signActionEnvelope` Export to `jelly.wasm`
- 6.2: Migrate `oracle.ts oracleSignAction` + `store.recordTraversal` to Real Ed25519 Signatures
- 7.2: Update `docs/ARCHITECTURE.md` Cross-Runtime Invariant + Wasm Action Host + Codegen Flow Diagram + Cross-Doc Consistency Pass

---

## D-026: Surface registry + fallback chain

- 3.3: CLI Projection — `inscribe` and `add-room` Verbs
  (Technical Notes: `inscribe` exercises the surface registry per PROTOCOL.md §13.7 + D-026)
- 7.1: Update `docs/PROTOCOL.md` — Schema Vendoring + Pin Format + Wasm Trust Model + JSON Schema Pointers

---

## D-027: Coord-frames composition — polar field, cartesian placements, nested reference frames

- 7.1: Update `docs/PROTOCOL.md` — Schema Vendoring + Pin Format + Wasm Trust Model + JSON Schema Pointers
  (AC5: §13.2 cites D-027; doc-only impact for sprint-002)

---

## D-028: Triple-native KG storage

- 2.1: Extract Memory Palace Types into `schemas/memory-palace-0.1.0.json` + Pin
- 2.2: Per-Archiform Codegen Pass + Cypher DDL Byte-Equivalence

---

## D-029: aspects.sh contract — vendor-first with deterministic local pin file format

- 1.2: Author `schemas/root-2.0.0.json` + Pin File Format
- 1.3: Build Per-Target Generators with Provenance + Logging
- 2.1: Extract Memory Palace Types into `schemas/memory-palace-0.1.0.json` + Pin
- 2.2: Per-Archiform Codegen Pass + Cypher DDL Byte-Equivalence
- 7.1: Update `docs/PROTOCOL.md` — Schema Vendoring + Pin Format + Wasm Trust Model + JSON Schema Pointers
- 7.2: Update `docs/ARCHITECTURE.md` Cross-Runtime Invariant + Wasm Action Host + Codegen Flow Diagram + Cross-Doc Consistency Pass
- 8.1: Author `dreamball/guestbook@0.1.0` JSON Schema + Pin + Per-Archiform Codegen [STRETCH]

---

## D-030: `tools/schema-gen/main.zig` disposition — repurpose as JSON-Schema consumer entry point

- 1.1: Codegen Inversion Spike — Round-Trip Three Complex Zig Types
- 1.2: Author `schemas/root-2.0.0.json` + Pin File Format
- 1.3: Build Per-Target Generators with Provenance + Logging
- 1.4: Shadow-Generator Phase + Byte-Equivalence CI Gate
- 1.5: Cutover Commit — Delete `tools/schema-gen/legacy/` and `src/lib/generated.legacy/`
- 2.2: Per-Archiform Codegen Pass + Cypher DDL Byte-Equivalence

---

## D-031: Wasm module signing — signed schema body + content-addressed wasm

- 5.3: Wasm Host Failure Paths — Verify-Before-Instantiate, Import-Violation, Memory-Limit
- 5.4: Author + Run Sample `mint.wasm` End-to-End Against Wasm Host
- 7.1: Update `docs/PROTOCOL.md` — Schema Vendoring + Pin Format + Wasm Trust Model + JSON Schema Pointers
- 7.2: Update `docs/ARCHITECTURE.md` Cross-Runtime Invariant + Wasm Action Host + Codegen Flow Diagram + Cross-Doc Consistency Pass
- 8.1: Author `dreamball/guestbook@0.1.0` JSON Schema + Pin + Per-Archiform Codegen [STRETCH]
- 8.2: Author + Run Guestbook Wasm Action End-to-End Through Host [STRETCH]

---

## D-032: Wasm host architecture — single shared host code targeting CLI and browser

- 5.1: Wasm Runtime Spike — Choose Runtime; Minimal Host Loads `hello.wasm` on darwin + linux
- 5.2: Implement 5 `dreamball.*` Imports + Per-Import Tests + Structured Event Emission
- 5.3: Wasm Host Failure Paths — Verify-Before-Instantiate, Import-Violation, Memory-Limit
- 7.2: Update `docs/ARCHITECTURE.md` Cross-Runtime Invariant + Wasm Action Host + Codegen Flow Diagram + Cross-Doc Consistency Pass

---

## D-033: `dreamball.*` import surface locked to 5 imports for sprint-002; any addition is a new ADR

- 5.2: Implement 5 `dreamball.*` Imports + Per-Import Tests + Structured Event Emission
- 5.3: Wasm Host Failure Paths — Verify-Before-Instantiate, Import-Violation, Memory-Limit
- 5.5: Author `docs/dreamball-imports.md` Enumerating the 5-Import Surface
- 8.2: Author + Run Guestbook Wasm Action End-to-End Through Host [STRETCH]
- 8.3: Project Guestbook Action to CLI Verb + Smoke Verification [STRETCH]

---

## D-034: Generated TS client integration — generated client wraps existing D-007 store wrapper

- 4.1: Generate `@dreamball/palace-client` TypeScript Client + Migrate One Bridge Site
- 4.2: Generate MCP Tool Spec + Spike MCP Elicitation Against Pinned SDK

---

## D-035: Action manifest `attributes` is a closed set; `effects.kind` is a closed enum; validator rejects unknown

- 1.1: Codegen Inversion Spike — Round-Trip Three Complex Zig Types
- 1.2: Author `schemas/root-2.0.0.json` + Pin File Format
- 3.1: Action Manifest Schema in Memory Palace JSON Schema + Closed-Set Validator + Pure-Transaction Lint
- 3.2: CLI Projection Spike — Project `mint` Verb End-to-End from Action Manifest
- 3.3: CLI Projection — `inscribe` and `add-room` Verbs
- 3.4: CLI Projection — `rename-mythos` and `move` Verbs
- 4.1: Generate `@dreamball/palace-client` TypeScript Client + Migrate One Bridge Site
- 4.2: Generate MCP Tool Spec + Spike MCP Elicitation Against Pinned SDK
- 4.3: MCP Server Entrypoint (`bun run mcp`)
- 8.3: Project Guestbook Action to CLI Verb + Smoke Verification [STRETCH]

---

## D-036: Test-tier defaults per cluster — Cluster A/E thorough; Cluster B/C/D/G/H smoke; nothing yolo

(no stories reference this decision — it is a process/planning artifact; story test tiers are assigned per cluster default; no story-level citation is expected or required)
