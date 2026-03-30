#!/usr/bin/env bash
set -Eeuo pipefail

STAMP="$(date +%F-%H%M%S)"
BACKUP_DIR="${HOME}/backup/niri-noctalia-${STAMP}"

mkdir -p "${BACKUP_DIR}/etc/greetd"
mkdir -p "${BACKUP_DIR}/home/.ssh"

echo "[*] Backup /etc/greetd"
sudo rsync -a /etc/greetd/ "${BACKUP_DIR}/etc/greetd/"

echo "[*] Backup ~/.config"
rsync -a "${HOME}/.config/" "${BACKUP_DIR}/home/.config/"

if [[ -f "$HOME/.bashrc" ]]; then
  echo "[*] Backup ~/.bashrc"
  cp -a "$HOME/.bashrc" "${BACKUP_DIR}/home/.bashrc"
fi

if [[ -f "$HOME/.ssh/config" ]]; then
  echo "[*] Backup ~/.ssh/config"
  cp -a "$HOME/.ssh/config" "${BACKUP_DIR}/home/.ssh/config"
fi

echo "[OK] Backup saved to: ${BACKUP_DIR}"
