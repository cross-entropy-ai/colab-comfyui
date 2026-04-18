#!/bin/bash
# ============================================================
# ComfyUI + Claude Code Setup on Google Colab
# With Google Drive persistence for both ComfyUI and Claude Code
# ============================================================

set -e

checkinstall() {
    command -v $@ 2>&1 >/dev/null
}

checkfolder() {
    test -d $@ 2>&1 >/dev/null
}

safe_symlink() {
    local src=$1
    local dst=$2

    mkdir -p "$src"

    if [ -L "$dst" ]; then
        if [ "$(readlink "$dst")" = "$src" ]; then
            return 0
        fi
        rm "$dst"
    elif [ -e "$dst" ]; then
        rm -rf "$dst"
    fi

    ln -s "$src" "$dst"
}

# ---------- Check CUDA GPU is available ----------
if ! checkinstall nvidia-smi; then
    echo "✗ Error: nvidia-smi not found. No NVIDIA GPU detected." >&2
    echo "  In Colab: Runtime → Change runtime type → select a GPU (T4/L4/A100)" >&2
    exit 1
fi

if ! nvidia-smi >/dev/null 2>&1; then
    echo "✗ Error: nvidia-smi failed. GPU not accessible." >&2
    echo "  In Colab: Runtime → Change runtime type → select a GPU (T4/L4/A100)" >&2
    exit 1
fi

GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
echo "✓ GPU detected: $GPU_NAME" >&2

# ---------- Check Drive is mounted ----------
if ! checkfolder /content/drive/MyDrive; then
    echo "✗ Error: Google Drive not mounted." >&2
    echo "  Run this in a Python cell first:" >&2
    echo "    from google.colab import drive" >&2
    echo "    drive.mount('/content/drive')" >&2
    exit 1
fi

mkdir -p /content

# ---------- Install ComfyUI ----------
if ! checkfolder /content/ComfyUI; then
    echo "Installing ComfyUI..." >&2
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /content/ComfyUI
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager /content/ComfyUI/custom_nodes/comfyui-manager
    cd /content/ComfyUI
    pip install -r requirements.txt 2>&1 >/dev/null
    pip install -r custom_nodes/comfyui-manager/requirements.txt 2>&1 >/dev/null
    # Reinstall PyTorch CUDA if pip downgraded it to CPU-only
    if ! python -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
        echo "- PyTorch CUDA lost, reinstalling..." >&2
        pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121 2>&1 >/dev/null
    fi
fi

# ---------- Verify PyTorch CUDA works ----------
if ! python -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
    echo "✗ Error: PyTorch cannot access CUDA." >&2
    PYTORCH_VERSION=$(python -c "import torch; print(torch.__version__)" 2>/dev/null || echo "unknown")
    echo "  PyTorch version: $PYTORCH_VERSION" >&2
    echo "  Fix:" >&2
    echo "    pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121" >&2
    exit 1
fi
echo "✓ PyTorch CUDA verified" >&2

# ---------- Install Cloudflared ----------
if ! checkinstall cloudflared; then
    rm -f /tmp/cloudflared.deb
    wget -q -O /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb 2>&1 >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y /tmp/cloudflared.deb 2>&1 >/dev/null
    rm -f /tmp/cloudflared.deb
fi

# ---------- Install Claude Code ----------
if ! checkinstall claude; then
    npm i -g @anthropic-ai/claude-code 2>&1 >/dev/null
fi

# ---------- Install PM2 ----------
if ! checkinstall pm2; then
    npm i -g pm2 2>&1 >/dev/null
fi

# ---------- Drive persistence setup ----------
USERDATA_DIR=/content/drive/MyDrive/ComfyUI
mkdir -p $USERDATA_DIR
cd $USERDATA_DIR

# Claude Code: ~/.claude/ directory (credentials, projects, todos)
# Migrate pre-existing local dir into Drive on first run
if [ -d "$HOME/.claude" ] && [ ! -L "$HOME/.claude" ]; then
    if [ -z "$(ls -A $USERDATA_DIR/claude 2>/dev/null)" ]; then
        mv $HOME/.claude/* $USERDATA_DIR/claude/ 2>/dev/null || true
        mv $HOME/.claude/.* $USERDATA_DIR/claude/ 2>/dev/null || true
    fi
    rm -rf $HOME/.claude
fi
safe_symlink $USERDATA_DIR/claude $HOME/.claude

# Claude Code: ~/.claude.json file (MCP servers, project trust, onboarding state)
# Migrate pre-existing local file into Drive on first run
if [ -f "$HOME/.claude.json" ] && [ ! -L "$HOME/.claude.json" ]; then
    if [ ! -f "$USERDATA_DIR/claude.json" ]; then
        mv "$HOME/.claude.json" "$USERDATA_DIR/claude.json"
    else
        rm -f "$HOME/.claude.json"
    fi
fi
touch "$USERDATA_DIR/claude.json"
ln -sf "$USERDATA_DIR/claude.json" "$HOME/.claude.json"

# ComfyUI user data (settings, saved workflows live under user/default/workflows)
safe_symlink $USERDATA_DIR/user /content/ComfyUI/user

# ComfyUI input/output folders
safe_symlink $USERDATA_DIR/input /content/ComfyUI/input
safe_symlink $USERDATA_DIR/output /content/ComfyUI/output

# Models: use extra_model_paths.yaml instead of full symlink
mkdir -p $USERDATA_DIR/models/{checkpoints,loras,vae,clip,controlnet,upscale_models,embeddings}

cat > /content/ComfyUI/extra_model_paths.yaml <<EOF
drive:
    base_path: $USERDATA_DIR/models
    checkpoints: checkpoints/
    loras: loras/
    vae: vae/
    clip: clip/
    controlnet: controlnet/
    upscale_models: upscale_models/
    embeddings: embeddings/
EOF

# ---------- Start ComfyUI ----------
cd /content/ComfyUI
pm2 delete comfyui >/dev/null 2>&1 || true

pm2 start "python main.py --port 8188 --listen 0.0.0.0" \
    --name comfyui \
    --cwd /content/ComfyUI \
    >/dev/null 2>&1

echo "- Waiting for ComfyUI to start..." >&2
COMFYUI_STARTED=false
for i in {1..60}; do
    sleep 1
    if curl -s http://localhost:8188 >/dev/null 2>&1; then
        echo "✓ ComfyUI started successfully" >&2
        COMFYUI_STARTED=true
        break
    fi
done

if [ "$COMFYUI_STARTED" = false ]; then
    echo "" >&2
    echo "✗ Error: ComfyUI failed to start after 60 seconds" >&2
    echo "Check logs with: pm2 logs comfyui" >&2
    exit 1
fi

# ---------- Summary ----------
echo "" >&2
echo "========================= ComfyUI =========================" >&2
echo "ComfyUI is running at http://localhost:8188" >&2
echo "" >&2
echo "To access from Colab, run in a Python cell:" >&2
echo "  from google.colab import output" >&2
echo "  output.serve_kernel_port_as_iframe(8188, height=1200)" >&2
echo "" >&2
echo "Drive persistence:" >&2
echo "  $USERDATA_DIR/claude/       — Claude Code credentials, history" >&2
echo "  $USERDATA_DIR/claude.json   — Claude Code MCP & settings" >&2
echo "  $USERDATA_DIR/user/         — ComfyUI settings & workflows" >&2
echo "  $USERDATA_DIR/input/        — Input images" >&2
echo "  $USERDATA_DIR/output/       — Generated images" >&2
echo "  $USERDATA_DIR/models/       — Checkpoints, LoRAs, VAE, etc" >&2
echo "" >&2
echo "========================= Claude Code =========================" >&2
if [ -f "$HOME/.claude/.credentials.json" ]; then
    echo "✓ Already logged in (restored from Drive)" >&2
    echo "  Run: claude" >&2
else
    echo "🔑 First-time setup — log in once:" >&2
    echo "  claude login" >&2
    echo "  After login, all future Colab runners will auto-restore the session." >&2
fi
echo "" >&2
echo "Process management:" >&2
echo "  pm2 list                     — List processes" >&2
echo "  pm2 logs comfyui --lines 100 — ComfyUI logs" >&2
echo "  pm2 restart comfyui          — Restart ComfyUI" >&2