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
  exit 1
fi

mkdir -p /content

# Install ComfyUI
if ! checkfolder /content/ComfyUI; then
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /content/ComfyUI
  cd /content/ComfyUI
  pip install -r requirements.txt
fi

# Install PM2
if ! checkinstall pm2; then
  npm i -g pm2
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
pm2 start "python main.py --port 8188" --name comfyui

echo "" >&2
echo "================ ComfyUI ================" >&2
echo "Run 'pm2 list' to list the processes." >&2
echo "Run 'pm2 logs comfyui --lines 1000' to see the logs." >&2
echo "Run 'pm2 delete comfyui' to delete the process." >&2
