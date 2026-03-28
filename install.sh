#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

log()  { echo "[+] $*"; }
die()  { echo "[!] $*" >&2; exit 1; }

install_packages() {
  local list="$1"
  [[ -f "$list" ]] || die "Not found: $list"
  sudo apt install -y $(grep -v '^#' "$list" | tr '\n' ' ')
}

log "Installing base packages..."
install_packages "$REPO_DIR/packages/base.txt"

log "Installing xorg..."
install_packages "$REPO_DIR/packages/xorg.txt"

log "Linking configs..."
# symlink или cp — на твой вкус
ln -sf "$REPO_DIR/config/bashrc" "$HOME/.bashrc"
ln -sf "$REPO_DIR/config/ssh/config" "$HOME/.ssh/config"

log "Running post-install scripts..."
for script in "$REPO_DIR/scripts"/*.sh; do
  bash "$script"
done

log "Done."
