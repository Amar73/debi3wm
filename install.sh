#!/usr/bin/env bash
# =============================================================================
# install.sh — точка входа для развёртывания системы
#
# ИСПОЛЬЗОВАНИЕ:
#   sudo ./install.sh              — полная установка
#   sudo ./install.sh --dry-run    — только показать план
#   sudo ./install.sh --configs-only
#   sudo ./install.sh --no-configs
# =============================================================================
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="$(cat /etc/hostname 2>/dev/null | tr -d '[:space:]' || echo "unknown")"
readonly LOG_FILE="/var/log/install.log"

DRY_RUN=false
CONFIGS_ONLY=false
NO_CONFIGS=false

log()  { echo "[+] $*"; }
warn() { echo "[!] $*" >&2; }
die()  { echo "[ERR] $*" >&2; exit 1; }
dryrun() { $DRY_RUN && echo "[DRY] $*" || "$@"; }

# --- Аргументы ---
for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=true ;;
    --configs-only) CONFIGS_ONLY=true ;;
    --no-configs)   NO_CONFIGS=true ;;
    -h|--help) grep '^#' "$0" | head -20 | sed 's/^# \?//'; exit 0 ;;
    *) die "Неизвестный аргумент: $arg" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "Запускай через sudo"

TARGET_USER="${SUDO_USER:-}"
[[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]] \
  || die "Запускай через sudo от обычного пользователя"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

# Пишем всё в лог
touch "${LOG_FILE}" 2>/dev/null || true
chmod 600 "${LOG_FILE}" 2>/dev/null || true
exec > >(tee -a "${LOG_FILE}") 2>&1

log "======================================================="
log "Запуск install.sh — $(date '+%Y-%m-%d %H:%M:%S')"
log "======================================================="
log "Хост:       $HOST"
log "Юзер:       $TARGET_USER"
log "Домашний:   $TARGET_HOME"
log "Лог-файл:   $LOG_FILE"
$DRY_RUN && log "Режим:      DRY-RUN"

# =============================================================================
# Установка пакетов
# =============================================================================
install_packages() {
  log "--- Установка пакетов (pacman) ---"
  bash "$REPO_DIR/scripts/install_pacman.sh" \
    $($DRY_RUN && echo "--dry-run" || true)

  log "--- Установка AUR-пакетов ---"
  bash "$REPO_DIR/scripts/install_aur.sh" \
    --aur-user "$TARGET_USER" \
    $($DRY_RUN && echo "--dry-run" || true)
}

# =============================================================================
# Deploy конфигов
# =============================================================================

deploy_file() {
  local src="$1" dst="$2" mode="${3:-644}"
  if $DRY_RUN; then
    echo "  [DRY] $src → $dst (${mode})"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  [[ -e "$dst" && ! -L "$dst" ]] && cp -a "$dst" "${dst}.bak.$(date +%s)"
  cp -a "$src" "$dst"
  chown "$TARGET_USER:" "$dst"
  chmod "$mode" "$dst"
}

deploy_dir() {
  local src="$1" dst="$2"
  if $DRY_RUN; then
    echo "  [DRY] $src/ → $dst/"
    return
  fi
  mkdir -p "$dst"
  cp -a "$src/." "$dst/"
  chown -R "$TARGET_USER:" "$dst"
}

deploy_configs() {
  log "--- Развёртывание конфигов ---"
  local cfg="$REPO_DIR/config"

  # bashrc
  deploy_file "$cfg/bashrc" "$TARGET_HOME/.bashrc"
  log "  bashrc → ~/.bashrc"

  # SSH config — по hostname
  local ssh_src=""
  if [[ -f "$cfg/ssh/config.${HOST}" ]]; then
    ssh_src="$cfg/ssh/config.${HOST}"
  elif [[ "$HOST" == amar319* && -f "$cfg/ssh/config.amar319" ]]; then
    ssh_src="$cfg/ssh/config.amar319"
  elif [[ "$HOST" == amar224* && -f "$cfg/ssh/config.amar224" ]]; then
    ssh_src="$cfg/ssh/config.amar224"
  else
    warn "ssh/config для хоста '$HOST' не найден, пропускаю"
  fi
  if [[ -n "$ssh_src" ]]; then
    mkdir -p "$TARGET_HOME/.ssh"
    chmod 700 "$TARGET_HOME/.ssh"
    deploy_file "$ssh_src" "$TARGET_HOME/.ssh/config" "600"
    log "  $ssh_src → ~/.ssh/config"
  fi

  # Hyprland monitors — по hostname
  local mon_src=""
  if [[ -f "$cfg/hypr/monitors/${HOST}.conf" ]]; then
    mon_src="$cfg/hypr/monitors/${HOST}.conf"
  elif [[ "$HOST" == amar319* && -f "$cfg/hypr/monitors/amar319.conf" ]]; then
    mon_src="$cfg/hypr/monitors/amar319.conf"
  elif [[ "$HOST" == amar224* && -f "$cfg/hypr/monitors/amar224.conf" ]]; then
    mon_src="$cfg/hypr/monitors/amar224.conf"
  else
    mon_src="$cfg/hypr/monitors/default.conf"
    warn "Монитор-конфиг для '$HOST' не найден, использую default.conf"
  fi
  deploy_file "$mon_src" "$TARGET_HOME/.config/hypr/monitors.conf" "644"
  log "  $mon_src → ~/.config/hypr/monitors.conf"

  # Hyprland общий конфиг
  deploy_file "$cfg/hypr/hyprland.conf" "$TARGET_HOME/.config/hypr/hyprland.conf"
  log "  hyprland.conf → ~/.config/hypr/"

  # Остальные конфиги
  local -A app_configs=(
    [alacritty]="$TARGET_HOME/.config/alacritty"
    [dunst]="$TARGET_HOME/.config/dunst"
    [waybar]="$TARGET_HOME/.config/waybar"
    [ranger]="$TARGET_HOME/.config/ranger"
    [flameshot]="$TARGET_HOME/.config/flameshot"
    [picom]="$TARGET_HOME/.config/picom"
    [polybar]="$TARGET_HOME/.config/polybar"
    [nitrogen]="$TARGET_HOME/.config/nitrogen"
  )

  for app in "${!app_configs[@]}"; do
    local src_dir="$cfg/$app"
    local dst_dir="${app_configs[$app]}"
    if [[ -d "$src_dir" ]]; then
      deploy_dir "$src_dir" "$dst_dir"
      log "  $app/ → $dst_dir/"
    fi
  done
}

# =============================================================================
# Post-install скрипты
# =============================================================================
run_post_install() {
  log "--- Post-install ---"
  local found=false
  for s in "$REPO_DIR/post-install"/*.sh; do
    [[ -f "$s" ]] || continue
    found=true
    log "  post-install: $(basename "$s")"
    dryrun bash "$s"
  done
  $found || log "  post-install: ничего нет"
}

# =============================================================================
# Сводка ошибок и предупреждений
# =============================================================================
summary() {
  local logs=(
    /var/log/install.log
    /var/log/install_pacman.log
    /var/log/install_aur.log
  )
  echo ""
  log "--- Сводка проблем ---"
  local found=false
  for f in "${logs[@]}"; do
    [[ -f "$f" ]] || continue
    local hits
    hits="$(grep -E '\[(ERROR|WARN)\]' "$f" 2>/dev/null || true)"
    if [[ -n "$hits" ]]; then
      found=true
      echo "  >>> $f"
      echo "$hits" | sed 's/^/    /'
    fi
  done
  if $found; then
    warn "Есть предупреждения/ошибки — полные логи в /var/log/install*.log"
  else
    log "Проблем не обнаружено"
  fi
}

# =============================================================================
# Main
# =============================================================================
$CONFIGS_ONLY || install_packages
$NO_CONFIGS   || deploy_configs

run_post_install
summary

log "======================================================="
log "Готово. Хост: $HOST — $(date '+%Y-%m-%d %H:%M:%S')"
log "======================================================="
