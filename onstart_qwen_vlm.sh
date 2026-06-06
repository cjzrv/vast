#!/usr/bin/env bash
set -eo pipefail

LOG_FILE=/var/log/onstart_qwen_vlm.log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== onstart_qwen_vlm.sh started: $(date) ====="

# Load Docker env vars from PID 1.
# SSH login shell may not inherit Docker -e variables, so read them manually.
if [[ -r /proc/1/environ ]]; then
  while IFS= read -r -d '' item; do
    case "$item" in
      RCLONE_CONFIG=*|RCLONE_CONFIG_B64=*|HF_HOME=*|TRANSFORMERS_CACHE=*|WANDB_DIR=*)
        export "$item"
        ;;
    esac
  done < /proc/1/environ
fi

# Do not print RCLONE_CONFIG_B64 itself.
echo "RCLONE_CONFIG=${RCLONE_CONFIG:-<unset>}"
echo "RCLONE_CONFIG_B64 length=${#RCLONE_CONFIG_B64}"

# =========================
# Fix SSH permissions
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
# Common env
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
  echo "Restoring rclone config to ${RCLONE_CONFIG}"

  tmp_conf="${RCLONE_CONFIG}.tmp"
  printf '%s' "${RCLONE_CONFIG_B64}" | base64 -d > "${tmp_conf}"
  chmod 600 "${tmp_conf}"

  if rclone --config "${tmp_conf}" listremotes >/tmp/rclone-remotes.txt 2>/tmp/rclone-error.txt; then
    mv "${tmp_conf}" "${RCLONE_CONFIG}"
    chmod 600 "${RCLONE_CONFIG}"
    echo "rclone config restored successfully."
    echo "Available remotes:"
    cat /tmp/rclone-remotes.txt
  else
    echo "ERROR: decoded rclone config is invalid."
    cat /tmp/rclone-error.txt || true
    rm -f "${tmp_conf}"
  fi
else
  echo "WARNING: RCLONE_CONFIG_B64 is empty or unset."
fi

mkdir -p /root/.config/rclone
ln -sf "${RCLONE_CONFIG}" /root/.config/rclone/rclone.conf

# =========================
# Python / GPU check
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

echo "===== onstart_qwen_vlm.sh finished: $(date) ====="
