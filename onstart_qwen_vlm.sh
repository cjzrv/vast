#!/usr/bin/env bash
set -eo pipefail

# =========================
# Fix SSH authorized_keys permissions
# =========================
mkdir -p /root/.ssh
chown root:root /root /root/.ssh
chmod 700 /root
chmod 700 /root/.ssh

if [[ -f /root/.ssh/authorized_keys ]]; then
  chown root:root /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
fi

# Disable Vast/base-image auto tmux
touch /root/.no_auto_tmux

# =========================
# Common directories
# =========================
mkdir -p \
  /workspace/repos \
  /workspace/data \
  /workspace/models \
  /workspace/outputs \
  /workspace/logs \
  /workspace/wandb \
  /workspace/.cache/huggingface \
  /workspace/.config/rclone

# =========================
# Common environment
# =========================
export HF_HOME=/workspace/.cache/huggingface
export TRANSFORMERS_CACHE=/workspace/.cache/huggingface
export HF_HUB_ENABLE_HF_TRANSFER=1
export WANDB_DIR=/workspace/wandb
export FORCE_QWENVL_VIDEO_READER=torchcodec
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export TOKENIZERS_PARALLELISM=false
export RCLONE_CONFIG=/workspace/.config/rclone/rclone.conf

cat > /etc/profile.d/qwen-vlm-env.sh <<'EOF'
export HF_HOME=/workspace/.cache/huggingface
export TRANSFORMERS_CACHE=/workspace/.cache/huggingface
export HF_HUB_ENABLE_HF_TRANSFER=1
export WANDB_DIR=/workspace/wandb
export FORCE_QWENVL_VIDEO_READER=torchcodec
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export TOKENIZERS_PARALLELISM=false
export RCLONE_CONFIG=/workspace/.config/rclone/rclone.conf
export PATH=/venv/main/bin:$PATH

alias rlg='rclone lsf gdrive:'
alias rcp='rclone copy --progress --transfers 8 --checkers 16 --drive-chunk-size 128M'
alias rsyncg='rclone sync --progress --transfers 8 --checkers 16 --drive-chunk-size 128M'
EOF

# =========================
# rclone setup
# =========================
chmod 700 /workspace/.config
chmod 700 /workspace/.config/rclone

if [[ -n "${RCLONE_CONFIG_B64:-}" ]]; then
  echo "Restoring rclone config from RCLONE_CONFIG_B64..."
  echo "${RCLONE_CONFIG_B64}" | base64 -d > "${RCLONE_CONFIG}"
  chmod 600 "${RCLONE_CONFIG}"
else
  echo "RCLONE_CONFIG_B64 is not set. rclone config will not be restored automatically."
fi

mkdir -p /root/.config/rclone
ln -sf "${RCLONE_CONFIG}" /root/.config/rclone/rclone.conf

if [[ -s "${RCLONE_CONFIG}" ]]; then
  echo "rclone config restored at ${RCLONE_CONFIG}"
  rclone listremotes || true
else
  echo "rclone config file does not exist or is empty: ${RCLONE_CONFIG}"
fi

# =========================
# Python / GPU environment check
# =========================
if [[ -f /venv/main/bin/activate ]]; then
  source /venv/main/bin/activate
fi

python - <<'PY' || true
import torch

print("torch:", torch.__version__)
print("torch cuda:", torch.version.cuda)
print("cuda available:", torch.cuda.is_available())
print("gpu:", torch.cuda.get_device_name(0) if torch.cuda.is_available() else None)

try:
    import flash_attn
    print("flash_attn:", flash_attn.__version__)
except Exception as e:
    print("flash_attn import failed:", e)
PY

echo "Vast Qwen VLM container is ready."
