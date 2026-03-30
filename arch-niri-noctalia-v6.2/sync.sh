#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="${ROOT_DIR}/files"

backup_if_exists() {
  local path="$1"
  if [[ -e "$path" && ! -L "$path" ]]; then
    local stamp
    stamp="$(date +%F-%H%M%S)"
    cp -a "$path" "${path}.bak.${stamp}"
  fi
}

echo "[*] Sync /etc/greetd"
sudo install -d -m 755 /etc/greetd
sudo rsync -a --delete "${FILES_DIR}/etc/greetd/" /etc/greetd/

echo "[*] Sync ~/.config"
mkdir -p "${HOME}/.config"
rsync -a --delete "${FILES_DIR}/home/.config/" "${HOME}/.config/"

echo "[*] Sync ~/.bashrc and ~/.ssh/config"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
backup_if_exists "$HOME/.bashrc"
backup_if_exists "$HOME/.ssh/config"
install -m 644 "${FILES_DIR}/home/.bashrc" "$HOME/.bashrc"
install -m 600 "${FILES_DIR}/home/.ssh/config" "$HOME/.ssh/config"

echo "[*] Reload user units"
systemctl --user daemon-reload

echo "[*] Validate niri config"
niri validate || true

echo "[*] Validate bashrc"
bash -n "$HOME/.bashrc"

echo "[*] Validate ssh config"
ssh -G github.com >/dev/null

echo "[OK] Sync done"
