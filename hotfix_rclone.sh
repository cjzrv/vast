#!/usr/bin/env bash
set -eo pipefail

LOG_FILE=/var/log/vast-hotfix-rclone.log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== hotfix_rclone.sh started: $(date) ====="

# Load selected Docker env vars from PID 1 if current shell does not have them.
# This is useful because SSH login shells may not inherit Docker env vars.
if [[ -r /proc/1/environ ]]; then
  while IFS= read -r -d '' item; do
    case "$item" in
      RCLONE_CONFIG=*|RCLONE_CONFIG_B64=*|PROVISIONING_SCRIPT=*)
        export "$item"
        ;;
    esac
  done < /proc/1/environ
fi

# Do not print RCLONE_CONFIG_B64. Only print its length for debugging.
echo "RCLONE_CONFIG=${RCLONE_CONFIG:-<unset>}"
echo "RCLONE_CONFIG_B64 length=${#RCLONE_CONFIG_B64}"

# Fix SSH authorized_keys permissions for OpenSSH StrictModes
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

# rclone config path
export RCLONE_CONFIG="${RCLONE_CONFIG:-/workspace/.config/rclone/rclone.conf}"

mkdir -p /workspace/.config/rclone
chmod 700 /workspace/.config || true
chmod 700 /workspace/.config/rclone

if [[ -n "${RCLONE_CONFIG_B64:-}" ]]; then
  echo "Restoring rclone config to ${RCLONE_CONFIG}"

  tmp_conf="${RCLONE_CONFIG}.tmp"
  printf '%s' "${RCLONE_CONFIG_B64}" | base64 -d > "${tmp_conf}"
  chmod 600 "${tmp_conf}"

  # Basic validation before replacing config
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

# Compatibility path for rclone default config location
mkdir -p /root/.config/rclone
ln -sf "${RCLONE_CONFIG}" /root/.config/rclone/rclone.conf

# Make rclone config path and aliases available in future interactive shells
cat > /etc/profile.d/rclone-env.sh <<'EOF'
export RCLONE_CONFIG=/workspace/.config/rclone/rclone.conf
alias rlg='rclone lsf gdrive:'
alias rcp='rclone copy --progress --transfers 8 --checkers 16 --drive-chunk-size 128M'
alias rsyncg='rclone sync --progress --transfers 8 --checkers 16 --drive-chunk-size 128M'
EOF

echo "Final check:"
ls -l "${RCLONE_CONFIG}" || true
ls -l /root/.config/rclone/rclone.conf || true

echo "===== hotfix_rclone.sh finished: $(date) ====="
