#!/usr/bin/env bash
# 4DGS Research + Build — Clone Everything & Deploy Parallel Research
# Copy-paste this entire block into your terminal

echo "🌀 4DGS RESEARCH BOOTSTRAP — Cloning all repos..."

# === STEP 1: Clone ALL repos ===
mkdir -p ~/research/4dgs && cd ~/research/4dgs

# WebGPU rasterizer core
echo "🌐 Cloning Visionary (WebGPU radix sort + renderer)..."
git clone https://github.com/Visionary-Laboratory/visionary.git

# Temporal opacity tables
echo "📊 Cloning TOGS (temporal opacity tables)..."
git clone https://github.com/hustvl/TOGS.git

# Feed-forward 4D generator (NVIDIA)
echo "🎨 Cloning Lyra (image/video → 4DGS)..."
git clone https://github.com/nv-tlabs/lyra.git

# Editor UX reference
echo "✏️ Cloning SuperSplat (editor timeline layout)..."
git clone https://github.com/playcanvas/supersplat.git

# Baseline 4D-GS
echo "🧪 Cloning 4D-GS baseline..."
git clone https://github.com/hustvl/4DGaussians.git

# 4D-Rotor (NVIDIA)
echo "⚡ Cloning 4D-Rotor (583 FPS variant)..."
git clone https://github.com/weify627/4D-Rotor-Gaussians.git

# ST-4DGS (temporal consistency)
echo "🌊 Cloning ST-4DGS..."
git clone https://github.com/wanglids/ST-4DGS.git

# HDR-4DGS (ICLR 2026)
echo "💡 Cloning HDR-4DGS (dynamic illumination)..."
git clone https://github.com/Surrey-UP-Lab/HDR-4DGS.git

# Lumina-4DGS paper
echo "📄 Lumina-4DGS: https://www.preprints.org/manuscript/202601.2150/v1"
echo "   DOI: 10.3390/s26051650"

# Web viewers
echo "🌍 Cloning web viewers..."
git clone https://github.com/sparkjsdev/spark.git
git clone https://github.com/mkkellogg/GaussianSplats3D.git
git clone https://github.com/antimatter15/splat.git
git clone https://github.com/zappar-xr/three-gaussian-splat.git
git clone https://github.com/cs-util-com/SplatLabJs.git
git clone https://github.com/akbartus/Gaussian-Splatting-WebViewers.git

# Paper tracker
echo "📚 Cloning paper tracker..."
git clone https://github.com/Lee-JaeWon/2025-Arxiv-Paper-List-Gaussian-Splatting.git

# Our build destination
echo "🏗️ Cloning Dreamball repo..."
git clone https://github.com/WorldTreeNetwork/Dreamball.git

# === STEP 2: Install + Build Visionary (WebGPU core) ===
echo "🔧 Installing Visionary deps..."
cd visionary && npm install 2>&1 | tail -3
cd ..

# === STEP 3: Print summary ===
echo ""
echo "═══════════════════════════════════════════"
echo "  ✅ 4DGS RESEARCH ECOSYSTEM CLONED"
echo "═══════════════════════════════════════════"
echo ""
echo "  📁 ~/research/4dgs/ contains:"
ls -d */
echo ""
echo "  📄 OPEN RESEARCH VENUES:"
echo "    1. Claude Code:  cat references/4dgs-phd-research-prompt.md | claude"
echo "    2. DeepSeek:     paste prompt into chat"
echo "    3. Parallel:     one agent per stage"
echo ""

# === STEP 4: Launch parallel research prompts ===
echo "📢 PARALLEL RESEARCH COMMANDS (run in separate terminals):"
echo ""
echo "  Terminal 1 (Stage 1+2):"
echo "    echo 'Research 4D-GS baseline + 4D-Rotor' | claude"
echo ""
echo "  Terminal 2 (Stage 3+4):"
echo "    echo 'Research ST-4DGS + Lumina/HDR-4DGS' | claude"
echo ""
echo "  Terminal 3 (Stage 5 + Web Modules):"
echo "    echo 'Research 4DGS-1K compression algorithm + implement from pseudocode' | claude"
echo ""
echo "  Terminal 4 (Phase 1 Build):"
echo "    echo 'Analyze TOGS + Visionary for .4dgs file format design' | claude"
echo ""
echo "═══════════════════════════════════════════"
echo "🌀 4DGS-1K PROJECT PAGE: https://4dgs-1k.github.io/"
echo "🌀 FULL PROMPT: references/4dgs-phd-research-prompt.md"
echo "═══════════════════════════════════════════"
