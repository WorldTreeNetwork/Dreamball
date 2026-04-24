-- schema.cypher — canonical DDL for the Memory Palace graph
--
-- Single source of truth per D-016. Executed identically on:
--   server: @ladybugdb/core napi (store.server.ts)
--   browser: kuzu-wasm@0.11.3 (store.browser.ts)
--
-- Idempotency: each CREATE statement is guarded in the adapter code via
-- CALL SHOW_TABLES() — tables that already exist are skipped.
--
-- Vector index: CREATE_VECTOR_INDEX is issued by the adapter after DDL,
-- gated by CALL SHOW_INDEXES() to skip if already present.
-- Server adapter: runs INSTALL VECTOR; LOAD EXTENSION VECTOR first.
-- Browser adapter: VECTOR extension is bundled — no install/load needed.
--
-- RC1: Inscription.orphaned BOOL DEFAULT false (S4.4 file-watcher writes here)
-- RC2: ActionLog.action_kind STRING accepts all 9 known action kinds
-- RC3: Inscription.source_blake3 STRING (not body_hash)
--
-- CONTAINS: single multi-pair rel table covering Palace→Room, Room→Inscription,
-- Palace→Inscription, Palace→Agent. kuzu-wasm@0.11.3 supports multi-pair rel tables
-- (confirmed by S2.1 spike — same engine version as @ladybugdb/core 0.15.3).
--
-- DISCOVERED_IN: NOT a relationship. Stored as Mythos.discovered_in_action_fp
-- STRING property per AC2 / D-016 decision.
--
-- TRIPLE node table + HAS_KNOWLEDGE REL:
-- The oracle Agent's knowledge graph is stored as native graph nodes (Triple)
-- with HAS_KNOWLEDGE edges from Agent to each Triple it owns. Previously the KG
-- was a JSON STRING column on Agent — that was (1) not CBOR-on-the-wire-native,
-- (2) re-parsed and re-serialised on every insert (O(n²) on replay), (3) an
-- on-disk format owned by TS outside the Zig-generated schema story. Native
-- nodes give us idempotent MERGE via fp = blake3(agent||s||p||o), indexable
-- subject lookups, and a versioning path that mirrors every other schema change.
-- See docs/decisions/2026-04-24-kg-triple-native-storage.md for the rationale.

-- ── Node tables (8) ────────────────────────────────────────────────────────────

CREATE NODE TABLE Palace(
  fp STRING PRIMARY KEY,
  created_at INT64,
  mythos_head_fp STRING,
  guild_fps STRING[] DEFAULT []
);

CREATE NODE TABLE Room(
  fp STRING PRIMARY KEY,
  created_at INT64
);

-- Inscription carries a policy + revision column so S4.2 getInscription can
-- actually read the gate (previously the code hardcoded 'any-admin' and no
-- column existed to read), and so S4.4 file-watcher revision-bumps persist
-- across the reembed delete/recreate round-trip instead of being silently
-- reset to zero. Default policy is 'public' to keep the MVP readable.
CREATE NODE TABLE Inscription(
  fp STRING PRIMARY KEY,
  source_blake3 STRING,
  orphaned BOOL DEFAULT false,
  embedding FLOAT[256],
  created_at INT64,
  policy STRING DEFAULT 'public',
  revision INT64 DEFAULT 0
);

-- S4.1: oracle Agent carries 4 slot columns (stored as JSON strings) plus
-- knowledge graph now stored as native Triple nodes via HAS_KNOWLEDGE (below).
-- personality_master_prompt: seed asset bytes (oracle-prompt.md)
-- memory: JSON array (empty at mint)
-- emotional_register: JSON object {curiosity,warmth,patience} at 0.5 each
-- interaction_set: JSON array (empty at mint)
CREATE NODE TABLE Agent(
  fp STRING PRIMARY KEY,
  created_at INT64,
  personality_master_prompt STRING DEFAULT '',
  memory STRING DEFAULT '[]',
  emotional_register STRING DEFAULT '{"curiosity":0.5,"warmth":0.5,"patience":0.5}',
  interaction_set STRING DEFAULT '[]'
);

-- Native KG triple row, one per (agent, subject, predicate, object) tuple.
-- fp is deterministic: blake3(agent_fp || '\0' || subject || '\0' || predicate || '\0' || object).
-- Replaces the prior Agent.knowledge_graph STRING DEFAULT '[]' JSON blob.
CREATE NODE TABLE Triple(
  fp STRING PRIMARY KEY,
  agent_fp STRING,
  subject STRING,
  predicate STRING,
  object STRING,
  created_at INT64
);

CREATE NODE TABLE Mythos(
  fp STRING PRIMARY KEY,
  body STRING,
  canonicality STRING,
  discovered_in_action_fp STRING,
  created_at INT64
);

CREATE NODE TABLE Aqueduct(
  fp STRING PRIMARY KEY,
  from_fp STRING,
  to_fp STRING,
  resistance DOUBLE DEFAULT 0.3,
  capacitance DOUBLE DEFAULT 0.5,
  strength DOUBLE DEFAULT 0.0,
  conductance DOUBLE DEFAULT 0.0,
  phase STRING DEFAULT 'standing',
  revision INT64 DEFAULT 0,
  last_traversal_ts INT64 DEFAULT 0
);

CREATE NODE TABLE ActionLog(
  fp STRING PRIMARY KEY,
  palace_fp STRING,
  action_kind STRING,
  actor_fp STRING,
  target_fp STRING,
  parent_hashes STRING[],
  timestamp INT64,
  cbor_bytes_blake3 STRING
);

-- ── Relationship tables (8) ────────────────────────────────────────────────────

-- CONTAINS: multi-pair covering all containment edges in one table.
-- Pairs: Palace→Room, Room→Inscription, Palace→Inscription, Palace→Agent (S3.2 oracle child)
CREATE REL TABLE CONTAINS(
  FROM Palace TO Room,
  FROM Room TO Inscription,
  FROM Palace TO Inscription,
  FROM Palace TO Agent
);

-- MYTHOS_HEAD: unique 1-edge pointer from Palace to its current head Mythos.
CREATE REL TABLE MYTHOS_HEAD(
  FROM Palace TO Mythos
);

-- PREDECESSOR: mythos chain — each Mythos points to its predecessor.
CREATE REL TABLE PREDECESSOR(
  FROM Mythos TO Mythos
);

-- LIVES_IN: Inscription lives in a Room (complement to CONTAINS Room→Inscription).
CREATE REL TABLE LIVES_IN(
  FROM Inscription TO Room
);

-- AQUEDUCT_FROM: Aqueduct originates from a Room.
CREATE REL TABLE AQUEDUCT_FROM(
  FROM Aqueduct TO Room
);

-- AQUEDUCT_TO: Aqueduct terminates at a Room.
CREATE REL TABLE AQUEDUCT_TO(
  FROM Aqueduct TO Room
);

-- KNOWS: reserved for oracle/quorum graph — Agent→Agent knowledge edges.
-- Defined upfront even if unused in Epic 2.
CREATE REL TABLE KNOWS(
  FROM Agent TO Agent
);

-- HAS_KNOWLEDGE: Agent owns a set of Triple nodes in its knowledge graph.
-- Replaces the prior Agent.knowledge_graph JSON STRING column.
CREATE REL TABLE HAS_KNOWLEDGE(
  FROM Agent TO Triple
);

-- ── Vector index ───────────────────────────────────────────────────────────────
-- NOTE: CREATE_VECTOR_INDEX is NOT in this file.
-- It is issued by each adapter after DDL execution, gated by SHOW_INDEXES().
-- Server: requires INSTALL VECTOR + LOAD EXTENSION VECTOR first.
-- Browser: VECTOR extension bundled — no install/load step.
-- See store.server.ts and store.browser.ts open() for the actual call.
