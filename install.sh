#!/bin/bash

set -e

checkinstall() {
    command -v $@ 2>&1 >/dev/null
}

checkfolder() {
    test -d $@ 2>&1 >/dev/null
}

if ! checkfolder /content/drive/MyDrive; then
    echo "Google Drive not mounted. Please mount Google Drive in the Colab interface." >&2
    echo "from google.colab import drive" >&2
    echo "drive.mount('/content/drive')" >&2
    exit 1
fi

mkdir -p /content

# Install ComfyUI
if ! checkfolder /content/ComfyUI; then
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /content/ComfyUI
    cd /content/ComfyUI
    pip install -r requirements.txt 2>&1 >/dev/null
fi

# Install Cloudflared
if ! checkinstall cloudflared; then
    rm -f /tmp/cloudflared.deb
    wget -q -O /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb 2>&1 >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y /tmp/cloudflared.deb 2>&1 >/dev/null
    rm -f /tmp/cloudflared.deb
fi

# Install PM2
if ! checkinstall pm2; then
    npm i -g pm2 2>&1 >/dev/null
fi

USERDATA_DIR=/content/drive/MyDrive/ComfyUI
mkdir -p $USERDATA_DIR
cd $USERDATA_DIR

mkdir -p $USERDATA_DIR/user
rm -rf /content/ComfyUI/user
ln -sf $USERDATA_DIR/user /content/ComfyUI/user

mkdir -p $USERDATA_DIR/input
rm -rf /content/ComfyUI/input
ln -sf $USERDATA_DIR/input /content/ComfyUI/input

mkdir -p $USERDATA_DIR/output
rm -rf /content/ComfyUI/output
ln -sf $USERDATA_DIR/output /content/ComfyUI/output

mkdir -p $USERDATA_DIR/models
rm -rf /content/ComfyUI/models
ln -sf $USERDATA_DIR/models /content/ComfyUI/models

cd /content/ComfyUI
pm2 delete comfyui 2>&1 >/dev/null || true
pm2 delete cloudflared 2>&1 >/dev/null || true

pm2 start "python main.py --port 8188" --name comfyui --cwd /content/ComfyUI 2>&1 >/dev/null
echo "Waiting for ComfyUI to start..." >&2
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

pm2 start "cloudflared tunnel --url http://localhost:8188 --no-autoupdate" --name cloudflared --cwd /content/ComfyUI 2>&1 >/dev/null
echo "Waiting for cloudflared to start..." >&2
CLOUDFLARED_URL=""
for i in {1..60}; do
    sleep 1
    CLOUDFLARED_URL=$(pm2 logs cloudflared --lines 100 --nostream 2>/dev/null | grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' | head -1)
    if [ ! -z "$CLOUDFLARED_URL" ]; then
        echo "✓ cloudflared started successfully" >&2
        break
    fi
done

if [ -z "$CLOUDFLARED_URL" ]; then
    echo "" >&2
    echo "✗ Error: cloudflared failed to start after 60 seconds" >&2
    echo "Check logs with: pm2 logs cloudflared" >&2
    exit 1
fi

echo "" >&2
echo "========================= ComfyUI =========================" >&2
echo "ComfyUI is running and accessible via the following URL:" >&2
echo "" >&2
echo "    $CLOUDFLARED_URL" >&2
echo "" >&2
echo "Run 'pm2 list' to list the processes." >&2
echo "Run 'pm2 logs comfyui --lines 1000' to see the ComfyUI logs." >&2
echo "Run 'pm2 logs cloudflared --lines 1000' to see the cloudflared logs." >&2
echo "Run 'pm2 delete comfyui cloudflared' to stop all processes." >&2
