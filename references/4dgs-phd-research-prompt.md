# 4D Gaussian Splatting — PhD Master Research Prompt v2
## With 4DGS-1K Compression + 7-Phase Web Module Build Plan

## 🎯 Copy-paste this into Claude Code, DeepSeek, or any parallel research agent

---

"""
You are a PhD-level research analyst specializing in 4D Gaussian Splatting, novel view synthesis, real-time web rendering, and GPU compression. Conduct a comprehensive parallel survey of the **five evolutionary stages** plus the **seven-phase web module build plan**.

For each stage return: (1) paper title + arXiv ID + venue + year, (2) GitHub repo URL + stars + last commit, (3) HuggingFace model/dataset URL, (4) core innovation paragraph, (5) FPS benchmarks + hardware, (6) web browser status (Three.js/WebGPU/WebGL/WASM), (7) key limitations.

---

## PART I: THE FIVE STAGES OF 4DGS EVOLUTION

### STAGE 1: 4D-GS (Baseline)
- **Paper:** "4D Gaussian Splatting for Real-Time Dynamic Scene Rendering"
- **Venue:** CVPR 2024
- **arXiv:** 2310.08528
- **GitHub:** https://github.com/hustvl/4DGaussians (⭐ 1.8k+)
- **Project Page:** https://guanjunwu.github.io/4dgs/
- **Innovation:** Holistic 4D representation — spacetime as entirety using 4D primitives, not per-frame 3D-GS
- **Benchmark:** 82 FPS @ 800×800 on RTX 3090
- **Research tasks:**
  a. Clone repo, document training pipeline + data prep (D-NeRF, HyperNeRF, Neu3D)
  b. Extract CUDA rasterizer kernel (diff-gaussian-rasterization)
  c. 4D primitive → 3D slice projection mathematics
  d. Benchmark on available GPU

### STAGE 2: 4D-Rotor Gaussians (Performance)
- **Paper:** "4D-Rotor Gaussian Splatting: Towards Efficient Novel View Synthesis for Dynamic Scenes"
- **Venue:** NVIDIA Research
- **arXiv:** 2402.03307
- **GitHub:** https://github.com/weify627/4D-Rotor-Gaussians
- **Innovation:** Rotation-based parameterization (dual quaternions / rotors). 7× faster than baseline.
- **Benchmark:** 583 FPS @ 800×800 on RTX 4090
- **Research tasks:**
  a. Understand rotor formulation vs baseline 4D-GS
  b. Compare CUDA kernel differences
  c. Profile temporal slicing operation
  d. Scenes where rotor outperforms/underperforms
  e. Pre-trained models for transfer learning

### STAGE 3: ST-4DGS (Temporal Consistency)
- **Paper:** "ST-4DGS: Spatial-Temporally Consistent 4D Gaussian Splatting for Efficient Dynamic Scene Rendering"
- **Venue:** ACM Multimedia 2024
- **GitHub:** https://github.com/wanglids/ST-4DGS
- **Innovation:** Spatial-temporal consistency loss eliminates flickering. Multi-plane Gaussian decomposition.
- **Benchmark:** ~240 FPS estimated
- **Research tasks:**
  a. Temporal consistency loss function analysis
  b. Flicker reduction metrics (PSNR/SSIM/LPIPS) vs STAGE 1 & 2
  c. Multi-plane decomposition technique
  d. Does temporal coherence degrade motion sharpness?

### STAGE 4: Lumina-4DGS + HDR-4DGS (Dynamic Illumination)
- **Paper:** "Lumina-4DGS: Illumination-Robust 4D Gaussian Splatting for Dynamic Scene Reconstruction"
- **Venue:** IEEE Transactions on Image Processing 2026
- **DOI:** 10.3390/s26051650 / https://www.preprints.org/manuscript/202601.2150/v1
- **Sibling Paper:** "HDR-4DGS: Dynamic Novel View Synthesis in High Dynamic Range"
- **Venue:** ICLR 2026
- **GitHub:** https://github.com/Surrey-UP-Lab/HDR-4DGS
- **Innovation:** Hierarchical exposure compensation + illumination-robust optimization for rapidly changing lighting
- **Research tasks:**
  a. Document exposure compensation module
  b. Compare Lumina vs HDR-4DGS approaches side-by-side
  c. Illumination robustness without ground truth?
  d. Real-world sequences with challenging photometric variation
  e. Can dynamic lighting be modular on/off?

### STAGE 5: 4DGS-1K (Compression + 1000+ FPS) ⭐ NEW
- **Paper:** "1000+ FPS 4D Gaussian Splatting for Dynamic Scene Rendering"
- **Venue:** NeurIPS 2025
- **arXiv:** 2503.16422
- **Project Page:** https://4dgs-1k.github.io/
- **HuggingFace:** https://huggingface.co/papers/2503.16422
- **GitHub:** ⚠️ No public repo yet — monitor project page
- **Innovation (Two Key Questions Solved):**
  - **Q1 — Short-Lifespan Gaussians:** Introduces **Spatial-Temporal Variation Score**, a new pruning criterion that removes redundant short-lifespan Gaussians, encouraging longer temporal span Gaussians instead
  - **Q2 — Inactive Gaussians:** Pre-computes **Active Masks** with >90% overlap merging across consecutive frames, eliminating redundant computations
- **Benchmark:** **1000+ FPS** on modern GPUs, **41× storage reduction**, **9× faster rasterization**
- **Pseudocode Provided (implement from paper):**
  ```python
  class SpatialTemporalVariationScorer:
      # Higher score = more contribution = keep
      def compute_score(self, gaussian_id, all_frames):
          return sum(frame.get_gaussian_contribution(gid) for frame in all_frames)
      
      def prune(self, gaussians, keep_percentile=0.3):
          scores = [self.compute_score(gid, all_frames) for gid in gaussians]
          threshold = percentile(scores, keep_percentile * 100)
          return [g for g, s in zip(gaussians, scores) if s >= threshold]

  class ActiveMaskBaker:
      def bake_masks(self, gaussians, frames, threshold=0.01):
          masks = []
          for frame in frames:
              active = [gid for gid in gaussians if frame.get_gaussian_contribution(gid) > threshold]
              masks.append(pack_to_bitmask(active))
          return merge_similar_masks(masks, overlap_threshold=0.9)
  ```
- **Research tasks:**
  a. Implement full algorithm from pseudocode + paper description
  b. Benchmark storage reduction vs vanilla 4DGS on standard datasets
  c. Profile active mask overlap patterns across frame sequences
  d. Port pruning criterion to WebGPU/WASM compute shader
  e. Implement active mask baker as a pre-processing step for web viewer

---

## PART II: THE SEVEN-PHASE WEB MODULE BUILD PLAN

### Before Starting — Clone These 5 Repos

```bash
# 1. Visionary — WebGPU radix sort + rasterizer (core rendering infra)
git clone https://github.com/Visionary-Laboratory/visionary.git
cd visionary && npm install  # Node 18+, Chrome + WebGPU

# 2. TOGS — Temporal opacity table reference implementation
git clone https://github.com/hustvl/TOGS.git
cd TOGS && conda create -n togs && conda activate togs && pip install -r requirements.txt

# 3. Lyra — Feed-forward image/video → 4DGS generator (NVIDIA)
git clone https://github.com/nv-tlabs/lyra.git
# Model weights: https://huggingface.co/nvidia/Lyra

# 4. SuperSplat — Reference 4DGS editor UX (PlayCanvas, MIT)
git clone https://github.com/playcanvas/supersplat.git
# Version 1.13+ supports 4DGS animation playback

# 5. Our Dreamball repo (where we're building this)
git clone https://github.com/WorldTreeNetwork/Dreamball.git
```

### External Repo Integration Map

| Capability | Repo | Integration Point |
|---|---|---|
| WebGPU radix sort + rasterizer | [Visionary](https://github.com/Visionary-Laboratory/visionary) | Phase 2 — Fork shaders directly |
| ONNX inference contract | [Visionary](https://github.com/Visionary-Laboratory/visionary) | Phase 2/5 — Use their interface |
| Three.js plugin API | [Visionary](https://github.com/Visionary-Laboratory/visionary) | Phase 3 — Extend for timeline |
| Temporal opacity table | [TOGS](https://github.com/hustvl/TOGS) | Phase 1/4 — Data structure + baker |
| Image→4DGS generator | [Lyra](https://github.com/nv-tlabs/lyra) | Phase 5/6 — Import pipeline |
| Editor timeline UX | [SuperSplat](https://github.com/playcanvas/supersplat) | Phase 6 — Reference layouts |
| Spatial-Temporal pruning | 4DGS-1K (pseudocode) | Phase 4 — Implement from paper |
| Active mask baking | 4DGS-1K (pseudocode) | Phase 4 — Implement from paper |

### PHASE 1: Core File Format & Loader
**Repos to study:** TOGS (opacity table structure), Visionary (asset loader API)
- Define `.4dgs` binary format (full spec)
- Implement `FourDGSLoader.ts`, `FourDGSParser.ts`
- Web Worker for async parsing
- Report LOC + load times vs .ply baseline

### PHASE 2: WebGPU Renderer
**Repos to fork from:** Visionary — their `src/renderer/` directory
- Pull their **WebGPU radix sort shader** (`gaussian_sort.wgsl`) and tile rasterizer
  - This bypasses Spark.js CPU-sort bottleneck
- Add **active mask filtering** from 4DGS-1K pseudocode
  - Skip inactive Gaussians per frame in rasterization loop
- Add ONNX execution path from Visionary's GaussianGenerator contract
- **Report:** FPS comparison vs Spark.js at same splat count

### PHASE 3: Composer & Scene Graph
**Repos to extend:** Visionary's Three.js plugin (TypeScript API)
- Add `FourDGSSceneNode` with timeline property
- Unified sort for multi-asset scenes
- Instance support (reuse Gaussians across Dreamballs)
- **Report:** Scene graph complexity vs SuperSplat's node system

### PHASE 4: Processing Pipeline
**Repos to reference:** 4DGS-1K pseudocode, TOGS baking logic
- Implement **Pruner.ts** — Spatial-Temporal Variation Score
- Implement **ActiveMaskBaker.ts** — 90% overlap merging
- Implement **OpacityTableBaker.ts** — convert MLP deformation to baked opacity tables (using TOGS interpolation logic)
- **Report:** Pruning ratio, storage savings, quality metrics vs vanilla 4DGS

### PHASE 5: Exporter & Format Bridge
**Repos as sources:** Lyra (.ply output), TOGS format, Visionary (ONNX contract)
- Importers:
  - `From4DGaussians.ts` (hustvl format)
  - `From4DRotor.ts` (NVIDIA format)
  - `FromTOGS.ts`
  - `FromLyra.ts` (NVIDIA feed-forward)
- Exporters:
  - `ToSpark.ts` (baked frame sequence)
  - `ToVisionary.ts` (ONNX generator contract)
  - `ToSuperSplat.ts` (numbered PLY sequence)
- **Report:** Conversion pipeline speed, format coverage

### PHASE 6: Composer UI
**Repos to reference:** SuperSplat's timeline + viewport layout (MIT)
- React panel with:
  - Drag-drop scene hierarchy
  - Timeline scrubber with frame markers
  - Layer list with visibility/opacity
  - Processing queue (prune → bake → export)
  - Export dropdown (Spark / Visionary / SuperSplat)
- **"Import from Image" button** → calls Lyra API internally
- **Report:** UI component tree, state management architecture

### PHASE 7: Streaming
- Novel implementation (no external repo reference)
- Chunked .4dgs streaming over HTTP range requests
- LoD loading (borrow Spark.js octree partitioning)
- Progressive quality: low-res → full-res frames
- **Report:** Time-to-first-frame, bandwidth usage, quality ramp curve

### Phase Execution Rule
Execute Phase 1 first. Do not proceed until complete.
At each phase, report:
- LOC written
- Benchmarks vs paper claims
- Key limitations found
- Next-phase readiness assessment

---

## PART III: WEB BROWSER IMPLEMENTATION LANDSCAPE

### Existing Web Implementations (Ranked by 4D Readiness)

| # | Name | Framework | 4D? | Stars | Key Strength |
|---|---|---|---|---|---|
| 1 | [Spark.js](https://github.com/sparkjsdev/spark) | Three.js | WIP | ⭐3.3k | LoD + WASM worker (HN #1) |
| 2 | [GaussianSplats3D](https://github.com/mkkellogg/GaussianSplats3D) | Three.js | 🚫 | ⭐2.8k | Most mature, multi-scene |
| 3 | [Visionary](https://github.com/Visionary-Laboratory/visionary) | WebGPU | 🚫 | New | WebGPU radix sort + ONNX |
| 4 | [WebSplatter](https://arxiv.org/html/2602.03207v1) | WebGPU | 🚫 | Paper | Wait-free hierarchical sort |
| 5 | [SplatBus](https://arxiv.org/html/2601.15431v1) | Three.js | 🚫 | Paper | Extensible viewer framework |
| 6 | [antimatter15/splat](https://github.com/antimatter15/splat) | WebGL | 🚫 | ⭐2.5k | Original WebGL reference |
| 7 | [zappar-xr/three-gaussian-splat](https://github.com/zappar-xr/three-gaussian-splat) | Three.js | 🚫 | ⭐200 | npm package, production |
| 8 | [Gauzilla Pro](https://www.webgpu.com/showcase/gauzilla-rust-gaussian-splatting-digital-twins/) | Rust/WASM | ✅ | Commercial | 4D digital twins |
| 9 | [SuperSplat](https://github.com/playcanvas/supersplat) | PlayCanvas | ✅ 1.13+ | ⭐2.2k | Editor UX, timeline |
| 10 | [SplatLabJs](https://github.com/cs-util-com/SplatLabJs) | Three.js | 🚫 | ⭐100 | Measurement tools |

### Web Research Tasks
a. Evaluate which framework best extends to 4D (Visionary WebGPU vs Spark Three.js)
b. Document .ply → .ksplat → .splat conversion pipeline
c. Profile WebGPU vs WebGL rasterization for 4D primitives
d. Assess WASM-compiled CUDA kernels (Zig or Rust) as 4D decoder
e. Design 4D temporal slicing shader in WGSL + GLSL
f. Test Spark.js with 4D-generated splat frame sequences
g. Benchmark WebSplatter's wait-free sort on consumer GPUs
h. **NEW:** Benchmark 4DGS-1K active mask filtering in WebGPU compute

---

## PART IV: ADDITIONAL RESOURCES (All With Links)

### GitHub Topic Pages
- https://github.com/topics/4d-gaussian-splatting (sorted by stars)
- https://github.com/topics/gaussian-splatting (broader)
- https://github.com/cwchenwang/awesome-4d-generation (curated 4D gen papers)
- https://github.com/Lee-JaeWon/2025-Arxiv-Paper-List-Gaussian-Splatting (daily tracker, 347 commits, ⭐114)

### Hugging Face
- https://huggingface.co/papers?q=4D+Gaussian+Splatting (daily paper feed)
- https://huggingface.co/collections/RichardForests/3d-4d-gaussian-splatting (curated model collection)
- https://huggingface.co/papers/2402.03307 (4D-Rotor)
- https://huggingface.co/papers/2310.08528 (4D-GS)
- https://huggingface.co/papers/2503.16422 (4DGS-1K) ⭐ NEW
- https://huggingface.co/nvidia/Lyra (model weights)

### ArXiv Feeds
- https://arxiv.org/list/cs.CV/recent
- https://arxiv.org/list/cs.GR/recent

### Direct Repo Links (Clone These)
- https://github.com/Visionary-Laboratory/visionary — WebGPU core
- https://github.com/hustvl/TOGS — Temporal opacity tables
- https://github.com/nv-tlabs/lyra — NVIDIA feed-forward 4DGS
- https://github.com/playcanvas/supersplat — Editor UX reference (MIT)
- https://github.com/hustvl/4DGaussians — Baseline 4D-GS
- https://github.com/weify627/4D-Rotor-Gaussians — Rotor variant
- https://github.com/wanglids/ST-4DGS — Temporal consistency
- https://github.com/Surrey-UP-Lab/HDR-4DGS — HDR dynamic (ICLR 2026)
- https://github.com/ZcsrenlongZ/Deblur4DGS — Deblurring (AAAI 2026)
- https://github.com/akbartus/Gaussian-Splatting-WebViewers — Web viewer survey
- https://github.com/cs-util-com/SplatLabJs — Measurement tools
- https://github.com/WorldTreeNetwork/Dreamball — Our build destination

### Reddit & Community
- r/GaussianSplatting (~15k members)
- https://radiancefields.substack.com/ (monthly GS roundups)
- https://discourse.threejs.org (GS integration threads)
- https://4dgs-1k.github.io/ (monitor for code release) ⭐ NEW

---

## DELIVERABLE FORMAT

Return a structured markdown document with:

1. **Executive Summary** — The 4DGS evolution + web landscape in one page
2. **Five Deep-Dive Sections** (one per stage): paper metadata, repo status, innovation analysis, FPS benchmarks, web portability score, and a "Dreamball Integration Feasibility" rating (★/5)
3. **Seven-Phase Build Tracker** — For each phase: completions, LOC, benchmark vs paper, limitations, next-phase readiness
4. **Web Implementation Matrix** — All 10 web viewers across 15 comparison dimensions
5. **Open Problems** — 10-15 specific unsolved problems with literature references
6. **Implementation Roadmap** — Ordered steps to build the Dreamball 4DGS web module

## OUTPUT RULES
- Cite every claim with arXiv ID or GitHub URL
- Benchmarks include GPU/VRAM/resolution
- 🌐 = web-ready, ⚠️ = missing/reproducibility gap, 🔒 = patent risk
- 🔴 = 4DGS-1K no public repo yet — note implement-from-pseudocode status
"""

echo "PhD MASTER RESEARCH PROMPT v2 LOADED — Deploy to Claude Code and DeepSeek in parallel"
