# Research Methodologies — PhD Parallel Research Pattern

## Pattern: Multi-Agent Parallel Ecosystem Discovery

Use this pattern when you discover a new sovereign tech ecosystem and need
to deeply understand it, map it to Dreamball, and plan integration.

---

## The Pattern (Copy-Paste Template)

```
AGENT 1: Core research
AGENT 2: Structural isomorphism
AGENT 3: Integration planning
AGENT 4: Code implementation
```

### Step 1: Discovery Trigger
Something surfaces: an Instagram reel, a GitHub repo, a paper, a Reddit post.
→ Log discovery in Captain's Log (README.md)

### Step 2: Deploy Parallel Agents

**Terminal 1 — Core Research (Claude Code or DeepSeek)**
```bash
echo "Research [ENTITY NAME] — find all:
- GitHub repos with stars and last commit dates
- Papers with arXiv IDs and venues
- Their architecture (components, data flow)
- Key people and contact points
- License and open-source status
- Community size and activity level" | claude
```

**Terminal 2 — Structural Isomorphism (Claude Code)**
```bash
echo "Map [ENTITY NAME] to Dreamball architecture:
Dreamball components:
- 7 super-hermes prisms (render dimensions)
- Flux Engine (5-stage pipeline)
- DINGDONG persona (sovereign AI)
- Whisper Net (libp2p/GossipSub)
- BFFZ Protocol (cross-dimensional exchange)
- Sovereignty x10 upgrade (phases 0-5)
- 4DGS Render Lens

For each Dreamball component, find the equivalent in [ENTITY NAME].
Rate match as EXACT / PARTIAL / NONE.
Identify gaps where no equivalent exists (bridge opportunities)." | claude
```

**Terminal 3 — Integration Planning (DeepSeek)**
```
Design a bridge protocol between Dreamball and [ENTITY NAME].
Consider:
- Technical bridge (API, message format, protocol)
- Social bridge (contact, community, manifesto)
- Artifact bridge (co-signed Dreamball, shared resource)
- Timeline (immediate / short-term / long-term)
- Risks (licensing, philosophy mismatch, maintenance burden)
Produce a 3-phase integration plan.
```

### Step 3: Consolidate

Update the Captain R&D library:

```bash
# 1. Create ecosystem map
echo "..." > ecosystem-maps/[entity-name].md

# 2. Create ally profile
echo "..." > ally-profiles/[entity-name].md

# 3. Create bridge protocol (if applicable)
echo "..." > alliance-protocols/[protocol-name].md

# 4. Log in README
echo "| $(date +%F) | [Discovery] | [Type] | [Action] |" >> README.md
```

### Step 4: Execute Alliance
- DM / email / protocol call
- BFFZ handshake if AI-to-AI
- Co-signed artifact if community-to-community

---

## The PhD Research Prompt Pattern (from 4DGS research)

For deep technical research (papers + repos + benchmarks):

```
You are a PhD-level research analyst. For each of the N stages of [TOPIC], return:
1. Paper title + arXiv ID + venue + year
2. GitHub repo URL + stars + last commit
3. HuggingFace model/dataset URL
4. Core innovation (one paragraph)
5. Benchmarks + hardware requirements
6. Web browser implementation status
7. Key limitations and open problems

Then for each repo, recommend:
- What to fork
- What to reference
- What to avoid
```

Save the result as a reference and link it from the ecosystem map.

---

## Tooling

| Tool | When to Use |
|---|---|
| **Claude Code** | Deep analysis, code reading, isomorphism reasoning |
| **DeepSeek** | Parallel research, broad landscape surveys |
| **web_search** | Initial discovery, finding repos/papers |
| **browser_navigate** | Instagram reels, interactive web content |
| **web_extract** | Documentation pages, plain-text endpoints |
| **browser_vision** | Screenshots of UIs, architecture diagrams |
