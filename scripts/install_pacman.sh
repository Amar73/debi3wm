#!/usr/bin/env bash
# =============================================================================
# install_pacman.sh — установщик пакетов из официальных репозиториев Arch Linux
#
# Что делает скрипт:
#   1. Читает список пакетов из packages/base.txt рядом со скриптом.
#   2. Определяет производителя видеокарты через lspci и добавляет
#      соответствующие драйверы (Intel / AMD / NVIDIA nouveau / виртуалка).
#   3. Устанавливает пакеты через pacman.
#
# Деплой конфигов — в install.sh (не здесь).
#
# ИСПОЛЬЗОВАНИЕ:
#   sudo ./install_pacman.sh [опции]
#
# ОПЦИИ:
#   --dry-run      Только анализ: показать что будет сделано, без изменений.
#   --pkgs FILE    Путь к файлу со списком пакетов
#                  (по умолч.: ../packages/base.txt рядом со скриптом).
#   -h, --help     Показать эту справку.
#
# ФОРМАТ packages/base.txt:
#   Один пакет на строку. Строки начинающиеся с # — комментарии, пропускаются.
#   Пустые строки пропускаются.
#
# ТРЕБОВАНИЯ:
#   - Arch Linux с pacman
#   - Запуск от root (через sudo)
#   - Доступ в интернет
#   - pciutils (устанавливается автоматически если отсутствует)
#
# ТОПОЛОГИЯ ДИСКОВ:
#   /dev/sda1 -> /        (корневой раздел)
#   /dev/sda2 -> /boot    (загрузчик)
#   /dev/sdb1 -> /home    (данные сохраняются между переустановками)
# =============================================================================

set -Eeuo pipefail

# =============================================================================
# Константы и значения по умолчанию
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/install_pacman.log"

DRY_RUN=false
PKGS_FILE="${SCRIPT_DIR}/../packages/base.txt"

# =============================================================================
# Внутренние переменные состояния
# =============================================================================

PACMAN_PKGS=()    # заполняется из файла в load_packages()
GPU_PKGS=()       # заполняется в detect_gpu()

REPO_INSTALLED=()
REPO_TO_INSTALL=()
REPO_NOT_FOUND=()

# =============================================================================
# Вспомогательные функции вывода
# =============================================================================

log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

usage() {
  sed -n '/^# ={5}/,/^# ={5}/{ s/^# \?//; p }' "$0" | head -n -1
}

# =============================================================================
# Обработчики сигналов
# =============================================================================

on_error() {
  local exit_code=$?
  local line_no="${1:-unknown}"
  (( exit_code == 141 )) && return 0
  echo "[ERROR] Сбой на строке ${line_no}, код выхода: ${exit_code}" >&2
  exit "$exit_code"
}

trap 'on_error $LINENO' ERR

# =============================================================================
# Разбор аргументов
# =============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --pkgs)
      [[ $# -ge 2 ]] || die "Для --pkgs нужно указать путь к файлу"
      PKGS_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Неизвестный аргумент: '$1'. Запусти с --help для справки."
      ;;
  esac
done

# =============================================================================
# Функции выполнения команд
# =============================================================================

run_cmd() {
  if $DRY_RUN; then
    printf '[DRY-RUN] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

# =============================================================================
# Загрузка списка пакетов из файла
# =============================================================================

load_packages() {
  local file="$1"
  # realpath для красивого вывода в логе
  local abs_path
  abs_path="$(realpath "$file" 2>/dev/null || echo "$file")"

  [[ -f "$file" ]] || die "Файл пакетов не найден: ${abs_path}"

  PACMAN_PKGS=()
  local line
  while IFS= read -r line; do
    # Убираем inline-комментарии и пробелы, пропускаем пустые и #-строки
    line="${line%%#*}"
    line="${line// /}"
    line="${line//	/}"
    [[ -z "$line" ]] && continue
    PACMAN_PKGS+=("$line")
  done < "$file"

  [[ ${#PACMAN_PKGS[@]} -gt 0 ]] \
    || die "Файл пакетов пуст или содержит только комментарии: ${abs_path}"

  log "Загружено ${#PACMAN_PKGS[@]} пакетов из: ${abs_path}"
}

# =============================================================================
# Вспомогательные функции
# =============================================================================

print_list() {
  local title="$1"
  shift
  echo
  echo "==> ${title}"
  if [[ $# -eq 0 ]]; then
    echo "  (пусто)"
    return 0
  fi
  local item
  for item in "$@"; do
    echo "  - $item"
  done
}

is_installed() {
  pacman -Qq "$1" >/dev/null 2>&1
}

repo_exists() {
  pacman -Si "$1" >/dev/null 2>&1
}

verify_installed_group() {
  local label="$1"
  shift
  local failed=()
  local pkg
  for pkg in "$@"; do
    is_installed "$pkg" || failed+=("$pkg")
  done
  if (( ${#failed[@]} > 0 )); then
    warn "Следующие пакеты (${label}) не установлены после завершения:"
    printf '  - %s\n' "${failed[@]}"
    return 1
  fi
  log "Верификация (${label}): все пакеты на месте"
  return 0
}

# =============================================================================
# Определение видеокарты и выбор драйверов
# =============================================================================

detect_gpu() {
  GPU_PKGS=()

  if ! command -v lspci >/dev/null 2>&1; then
    warn "lspci не найден — pciutils ещё не установлен."
    warn "Пропускаю автоопределение GPU. Драйверы не будут установлены."
    return 0
  fi

  local lspci_out
  lspci_out="$(lspci -mm | grep -iE '"(VGA compatible controller|3D controller|Display controller)"')" || true

  if [[ -z "${lspci_out}" ]]; then
    warn "GPU-устройства не обнаружены через lspci. Драйверы не будут установлены."
    return 0
  fi

  local found_intel=false found_amd=false found_nvidia=false
  local found_vmware=false found_vbox=false

  local line vendor
  while IFS= read -r line; do
    vendor="$(echo "${line}" | cut -d'"' -f6)"
    case "${vendor}" in
      *Intel*)              found_intel=true;  log "  GPU: Intel — ${vendor}" ;;
      *AMD*|*ATI*|*"Advanced Micro"*)
                            found_amd=true;    log "  GPU: AMD — ${vendor}" ;;
      *NVIDIA*)             found_nvidia=true; log "  GPU: NVIDIA — ${vendor}" ;;
      *VMware*)             found_vmware=true; log "  GPU: VMware — ${vendor}" ;;
      *VirtualBox*|*InnoTek*)
                            found_vbox=true;   log "  GPU: VirtualBox — ${vendor}" ;;
      *)
        warn "  GPU: нераспознанный производитель: '${vendor}'"
        warn "       Добавь обработку в detect_gpu() или установи драйверы вручную."
        ;;
    esac
  done <<< "${lspci_out}"

  $found_intel  && GPU_PKGS+=(mesa libva-mesa-driver vulkan-intel intel-media-driver libva-intel-driver)
  $found_amd    && GPU_PKGS+=(mesa libva-mesa-driver vulkan-radeon)
  $found_nvidia && GPU_PKGS+=(mesa libva-mesa-driver vulkan-nouveau)
  $found_vmware && GPU_PKGS+=(mesa open-vm-tools xf86-video-vmware)
  $found_vbox   && GPU_PKGS+=(mesa virtualbox-guest-utils)

  # Дедупликация
  local dedup=() seen="" pkg
  for pkg in "${GPU_PKGS[@]+"${GPU_PKGS[@]}"}"; do
    if [[ ! " ${seen} " =~ " ${pkg} " ]]; then
      dedup+=("${pkg}")
      seen+=" ${pkg}"
    fi
  done
  GPU_PKGS=("${dedup[@]+"${dedup[@]}"}")

  if (( ${#GPU_PKGS[@]} > 0 )); then
    log "Итоговые GPU-пакеты: ${GPU_PKGS[*]}"
  else
    warn "GPU-пакеты не определены. Проверь вывод lspci вручную."
  fi
}

# =============================================================================
# Классификация пакетов
# =============================================================================

split_packages() {
  REPO_INSTALLED=()
  REPO_TO_INSTALL=()
  REPO_NOT_FOUND=()

  local all_pkgs=("${PACMAN_PKGS[@]}")
  (( ${#GPU_PKGS[@]} > 0 )) && all_pkgs+=("${GPU_PKGS[@]}")

  local pkg
  for pkg in "${all_pkgs[@]}"; do
    if repo_exists "$pkg"; then
      is_installed "$pkg" \
        && REPO_INSTALLED+=("$pkg") \
        || REPO_TO_INSTALL+=("$pkg")
    else
      REPO_NOT_FOUND+=("$pkg")
    fi
  done
}

# =============================================================================
# Синхронизация баз и prereqs
# =============================================================================

sync_package_databases() {
  log "Синхронизирую базы пакетов (pacman -Sy)"
  pacman -Sy --noconfirm
}

install_build_prereqs() {
  log "Устанавливаю pciutils, base-devel и обновляю систему (pacman -Su)"
  run_cmd pacman -Su --needed --noconfirm pciutils base-devel
}

# =============================================================================
# Установка пакетов
# =============================================================================

install_packages() {
  if (( ${#REPO_TO_INSTALL[@]} == 0 )); then
    log "Все пакеты уже установлены, пропускаю"
    return 0
  fi
  log "Устанавливаю ${#REPO_TO_INSTALL[@]} пакет(ов) через pacman"
  run_cmd pacman -S --needed --noconfirm "${REPO_TO_INSTALL[@]}"
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
  [[ $EUID -eq 0 ]] \
    || die "Скрипт нужно запускать от root (через sudo или напрямую)"

  command -v pacman >/dev/null 2>&1 \
    || die "pacman не найден. Скрипт предназначен только для Arch Linux."

  [[ ! -e /var/lib/pacman/db.lck ]] \
    || die "База pacman заблокирована (/var/lib/pacman/db.lck). \
Убедись, что pacman не запущен, и удали файл блокировки вручную."

  touch "${LOG_FILE}" 2>/dev/null \
    || die "Не могу создать лог-файл: ${LOG_FILE}. Проверь права на /var/log/."
  chmod 600 "${LOG_FILE}" 2>/dev/null || warn "Не удалось установить права 600 на ${LOG_FILE}"

  exec > >(tee -a "${LOG_FILE}") 2>&1

  log "======================================================="
  log "Запуск install_pacman.sh — $(date '+%Y-%m-%d %H:%M:%S')"
  log "======================================================="
  $DRY_RUN && log "Режим DRY-RUN: реальных изменений не будет"

  # 1. Загружаем список пакетов из файла
  load_packages "${PKGS_FILE}"

  # 2. Синхронизируем базы
  sync_package_databases

  # 3. Prereqs (нужен lspci для detect_gpu)
  install_build_prereqs

  # 4. Определяем GPU
  log "Определяю видеокарту..."
  detect_gpu

  # 5. Классифицируем пакеты
  split_packages

  print_list "GPU-пакеты (авто)"   "${GPU_PKGS[@]+"${GPU_PKGS[@]}"}"
  print_list "Уже установлены"     "${REPO_INSTALLED[@]+"${REPO_INSTALLED[@]}"}"
  print_list "Будут установлены"   "${REPO_TO_INSTALL[@]+"${REPO_TO_INSTALL[@]}"}"
  print_list "НЕ НАЙДЕНЫ в репо"   "${REPO_NOT_FOUND[@]+"${REPO_NOT_FOUND[@]}"}"
  echo

  if (( ${#REPO_NOT_FOUND[@]} > 0 )); then
    die "Обнаружены несуществующие пакеты (см. выше). \
Исправь packages/base.txt и запусти снова."
  fi

  # 6. Устанавливаем
  install_packages

  # 7. Верификация
  if ! $DRY_RUN; then
    local all_pkgs=("${PACMAN_PKGS[@]}")
    (( ${#GPU_PKGS[@]} > 0 )) && all_pkgs+=("${GPU_PKGS[@]}")
    verify_installed_group "все пакеты" "${all_pkgs[@]}" \
      || die "Верификация не прошла. Проверь лог: ${LOG_FILE}"

    log "======================================================="
    log "Завершено успешно — $(date '+%Y-%m-%d %H:%M:%S')"
    log "======================================================="
  else
    log "======================================================="
    log "DRY-RUN завершён. Для установки уберите флаг --dry-run."
    log "======================================================="
  fi
}

main "$@"
