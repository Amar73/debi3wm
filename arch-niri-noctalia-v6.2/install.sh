#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '
[%s] %s
' "$(date +'%F %T')" "$*"; }
die() { printf '
[ERROR] %s
' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "Запускай от обычного пользователя, не от root."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="${ROOT_DIR}/files"

need() {
  command -v "$1" >/dev/null 2>&1 || die "Не найдено: $1"
}

install_paru() {
  if command -v paru >/dev/null 2>&1; then
    log "paru уже установлен"
    return 0
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  log "Установка paru"
  git clone https://aur.archlinux.org/paru.git "$tmpdir/paru"
  (
    cd "$tmpdir/paru"
    makepkg -si --noconfirm
  )
}

remove_conflicts() {
  if pacman -Q quickshell >/dev/null 2>&1; then
    log "Удаляю quickshell"
    sudo pacman -Rns --noconfirm quickshell
  fi

  if pacman -Q quickshell-git >/dev/null 2>&1; then
    log "Удаляю quickshell-git"
    paru -Rns --noconfirm quickshell-git || true
  fi
}

install_official_packages() {
  log "Обновление системы"
  sudo pacman -Syu --noconfirm

  log "Установка официальных пакетов"
  sudo pacman -S --needed --noconfirm     base-devel git rsync curl wget unzip     niri     greetd greetd-tuigreet     networkmanager seatd     pipewire wireplumber     xdg-desktop-portal xdg-desktop-portal-wlr     foot fuzzel mako     swaybg swayidle swaylock     wl-clipboard cliphist     polkit-gnome     brightnessctl playerctl     grim slurp     mesa vulkan-icd-loader     qt6-wayland qt6-svg qt6-multimedia qt5-compat     qt6ct kvantum nwg-look     noto-fonts noto-fonts-cjk noto-fonts-emoji     ttf-jetbrains-mono-nerd     adw-gtk-theme papirus-icon-theme bibata-cursor-theme     xwayland-satellite     keychain openssh
}

enable_system_services() {
  log "Включение system services"
  sudo systemctl enable NetworkManager.service
  sudo systemctl enable seatd.service
  sudo systemctl enable greetd.service
}

add_groups() {
  log "Добавление пользователя в группы"
  sudo usermod -aG video,input,seat "$USER" || true
}

install_noctalia() {
  log "Установка Noctalia"
  paru -S --needed --noconfirm noctalia-shell
}

backup_if_exists() {
  local path="$1"
  if [[ -e "$path" && ! -L "$path" ]]; then
    local stamp
    stamp="$(date +%F-%H%M%S)"
    cp -a "$path" "${path}.bak.${stamp}"
  fi
}

deploy_dotfiles() {
  log "Копирование пользовательских bashrc и ssh config"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  backup_if_exists "$HOME/.bashrc"
  backup_if_exists "$HOME/.ssh/config"
  install -m 644 "${FILES_DIR}/home/.bashrc" "$HOME/.bashrc"
  install -m 600 "${FILES_DIR}/home/.ssh/config" "$HOME/.ssh/config"
}

deploy_files() {
  log "Копирование конфигов"

  sudo install -d -m 755 /etc/greetd
  sudo rsync -a "${FILES_DIR}/etc/greetd/" /etc/greetd/

  mkdir -p "${HOME}/.config"
  rsync -a "${FILES_DIR}/home/.config/" "${HOME}/.config/"

  mkdir -p "${HOME}/Pictures"
  deploy_dotfiles
}

enable_user_services() {
  log "Включение user services"
  systemctl --user daemon-reload
  systemctl --user enable noctalia.service
  systemctl --user enable swayidle.service
  systemctl --user enable cliphist.service
}

print_summary() {
  cat <<'EOF'

========================================
Готово
========================================

Дальше:
  sudo reboot

После входа:
  make check
  make logs
  bash -n ~/.bashrc
  ssh -G github.com >/dev/null

EOF
}

main() {
  need sudo
  need pacman
  need git
  need rsync

  install_official_packages
  enable_system_services
  add_groups
  install_paru
  remove_conflicts
  install_noctalia
  deploy_files
  enable_user_services
  print_summary
}

main "$@"
