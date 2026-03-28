#!/usr/bin/env bash
# =============================================================================
# install.sh — точка входа для развёртывания системы
#
# ИСПОЛЬЗОВАНИЕ:
#   sudo ./install.sh              — пакеты pacman + конфиги
#   sudo ./install.sh --dry-run    — только показать план
#   sudo ./install.sh --configs-only
#   sudo ./install.sh --no-configs
#   sudo ./install.sh --with-aur   — включить установку AUR (долго!)
#
# AUR-пакеты по умолчанию НЕ устанавливаются автоматически.
# Для ручной установки AUR после основной установки:
#   sudo ./scripts/install_aur.sh
# =============================================================================
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST="$(cat /etc/hostname 2>/dev/null | tr -d '[:space:]' || echo "unknown")"
readonly LOG_FILE="/var/log/install.log"

DRY_RUN=false
CONFIGS_ONLY=false
NO_CONFIGS=false
WITH_AUR=false

log()  { echo "[+] $*"; }
warn() { echo "[!] $*" >&2; }
die()  { echo "[ERR] $*" >&2; exit 1; }

# --- Аргументы ---
for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=true ;;
    --configs-only) CONFIGS_ONLY=true ;;
    --no-configs)   NO_CONFIGS=true ;;
    --with-aur)     WITH_AUR=true ;;
    -h|--help) grep '^#' "$0" | head -25 | sed 's/^# \?//'; exit 0 ;;
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
$DRY_RUN  && log "Режим:      DRY-RUN"
$WITH_AUR && log "AUR:        включён"

# =============================================================================
# Установка пакетов pacman
# =============================================================================
install_pacman_packages() {
  log "--- Установка пакетов (pacman) ---"
  bash "$REPO_DIR/scripts/install_pacman.sh" \
    $($DRY_RUN && echo "--dry-run" || true)
}

# =============================================================================
# Установка AUR-пакетов (только если --with-aur)
# =============================================================================
install_aur_packages() {
  log "--- Установка AUR-пакетов ---"
  log "    Это может занять несколько часов."
  log "    Для ручной установки позже: sudo ./scripts/install_aur.sh"
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
  if [[ -f "$cfg/bashrc" ]]; then
    deploy_file "$cfg/bashrc" "$TARGET_HOME/.bashrc"
    log "  bashrc → ~/.bashrc"
  else
    warn "config/bashrc не найден, пропускаю"
  fi

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
    if $DRY_RUN; then
      echo "  [DRY] mkdir ~/.ssh && $ssh_src → ~/.ssh/config (600)"
    else
      mkdir -p "$TARGET_HOME/.ssh"
      chmod 700 "$TARGET_HOME/.ssh"
      chown "$TARGET_USER:" "$TARGET_HOME/.ssh"
    fi
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
  if [[ -f "$cfg/hypr/hyprland.conf" ]]; then
    deploy_file "$cfg/hypr/hyprland.conf" "$TARGET_HOME/.config/hypr/hyprland.conf"
    log "  hyprland.conf → ~/.config/hypr/"
  fi

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
# SSH agent — systemd user service
# =============================================================================
setup_ssh_agent() {
  log "--- Настройка ssh-agent (systemd user service) ---"

  local service_dir="$TARGET_HOME/.config/systemd/user"
  local service_file="$service_dir/ssh-agent.service"

  if $DRY_RUN; then
    echo "  [DRY] создать $service_file"
    echo "  [DRY] systemctl --user enable ssh-agent"
    return
  fi

  mkdir -p "$service_dir"
  chown -R "$TARGET_USER:" "$service_dir"

  cat > "$service_file" << 'EOF'
[Unit]
Description=SSH key agent
Before=graphical-session.target
After=default.target

[Service]
Type=simple
Environment=SSH_AUTH_SOCK=%t/ssh-agent.socket
ExecStart=/usr/bin/ssh-agent -D -a $SSH_AUTH_SOCK
ExecStartPost=/usr/bin/bash -c 'systemctl --user set-environment SSH_AUTH_SOCK=$SSH_AUTH_SOCK'

[Install]
WantedBy=default.target
EOF

  chown "$TARGET_USER:" "$service_file"
  chmod 644 "$service_file"

  # Включаем сервис от имени пользователя
  sudo -u "$TARGET_USER" systemctl --user daemon-reload 2>/dev/null || \
    warn "daemon-reload не выполнен (возможно, dbus не запущен — выполни вручную после входа)"
  sudo -u "$TARGET_USER" systemctl --user enable ssh-agent 2>/dev/null || \
    warn "enable ssh-agent не выполнен — выполни вручную: systemctl --user enable ssh-agent"

  log "  ssh-agent.service → $service_file"
  log "  После входа в систему: SSH_AUTH_SOCK будет установлен автоматически"

  # Добавляем SSH_AUTH_SOCK в .bashrc.local если не задан
  local bashrc_local="$TARGET_HOME/.bashrc.local"
  if ! grep -q 'SSH_AUTH_SOCK' "$bashrc_local" 2>/dev/null; then
    cat >> "$bashrc_local" << 'EOF'

# SSH agent socket (systemd user service)
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
EOF
    chown "$TARGET_USER:" "$bashrc_local"
    log "  SSH_AUTH_SOCK добавлен в ~/.bashrc.local"
  fi
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
    log "  $(basename "$s")"
    $DRY_RUN && echo "  [DRY] bash $s" || bash "$s"
  done
  $found || log "  ничего нет"
}

# =============================================================================
# Сводка ошибок
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
    hits="$(grep -E '\[(ERROR|WARN)\]|\[!\]' "$f" 2>/dev/null || true)"
    if [[ -n "$hits" ]]; then
      found=true
      echo "  >>> $f"
      echo "$hits" | sed 's/^/    /'
    fi
  done
  $found \
    && warn "Есть предупреждения/ошибки — полные логи: /var/log/install*.log" \
    || log "Проблем не обнаружено"
}

# =============================================================================
# Main
# =============================================================================

# Пакеты — если не --configs-only
if ! $CONFIGS_ONLY; then
  # pacman всегда
  install_pacman_packages || warn "install_pacman.sh завершился с ошибкой, продолжаю..."

  # AUR только если явно попросили
  if $WITH_AUR; then
    install_aur_packages || warn "install_aur.sh завершился с ошибкой, продолжаю..."
  else
    log "--- AUR пропущен (используй --with-aur для установки) ---"
    log "    Ручная установка: sudo ./scripts/install_aur.sh"
  fi
fi

# Конфиги — если не --no-configs (выполняется ВСЕГДА, даже если пакеты упали)
if ! $NO_CONFIGS; then
  deploy_configs || warn "deploy_configs завершился с ошибкой"
  setup_ssh_agent || warn "setup_ssh_agent завершился с ошибкой"
fi

run_post_install
summary

log "======================================================="
log "Готово. Хост: $HOST — $(date '+%Y-%m-%d %H:%M:%S')"
log "======================================================="
log ""
log "Следующие шаги:"
log "  1. Перезайди в систему (или: source ~/.bashrc)"
log "  2. Запусти ssh-agent: systemctl --user start ssh-agent"
log "  3. Добавь ключ: ssh-add ~/.ssh/id_ed25519"
$WITH_AUR || \
log "  4. AUR-пакеты: sudo ./scripts/install_aur.sh"
