#!/usr/bin/env bash
# =============================================================================
# install_aur.sh -- установщик AUR-пакетов для Arch Linux
#
# Что делает скрипт:
#   1. Читает список пакетов из packages/aur.txt рядом со скриптом.
#   2. Собирает yay из AUR если он ещё не установлен.
#   3. Проверяет существование каждого пакета в AUR.
#   4. Устанавливает AUR-пакеты через yay.
#
# Сборка AUR-пакетов всегда выполняется от непривилегированного пользователя --
# это требование makepkg и базовая мера безопасности.
#
# ИСПОЛЬЗОВАНИЕ:
#   sudo ./install_aur.sh [опции]
#
# ОПЦИИ:
#   --dry-run           Только анализ: показать что будет сделано, без изменений.
#   --pkgs FILE         Путь к файлу со списком AUR-пакетов
#                       (по умолч.: ../packages/aur.txt рядом со скриптом).
#   --jobs N            Число параллельных jobs для makepkg (по умолч.: nproc).
#   --aur-user USER     Пользователь для сборки AUR. Нужен только если скрипт
#                       запускается напрямую от root, а не через sudo.
#   --allow-temp-sudo   Выдать пользователю временный NOPASSWD на /usr/bin/pacman.
#                       Нужно только в unattended-режиме без интерактивного sudo.
#   -h, --help          Показать эту справку.
#
# ФОРМАТ packages/aur.txt:
#   Один пакет на строку. Строки начинающиеся с # — комментарии, пропускаются.
#   Пустые строки пропускаются.
#
# ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ:
#   BUILD_JOBS          Альтернатива --jobs (флаг имеет приоритет).
#
# ТРЕБОВАНИЯ:
#   - Arch Linux с pacman
#   - Запуск от root (через sudo)
#   - Доступ в интернет
#   - git и base-devel (устанавливаются автоматически если отсутствуют)
# =============================================================================

set -Eeuo pipefail

# =============================================================================
# Константы и значения по умолчанию
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/install_aur.log"
readonly TEMP_SUDOERS_FILE="/etc/sudoers.d/99-temp-aur-installer"

DRY_RUN=false
ALLOW_TEMP_SUDO=false
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
AUR_USER_CLI=""
PKGS_FILE="${SCRIPT_DIR}/../packages/aur.txt"

# =============================================================================
# Внутренние переменные состояния
# =============================================================================

AUR_PKGS=()     # заполняется из файла в load_packages()

TMP_DIR=""
AUR_USER=""
AUR_HOME=""
AUR_CACHE_DIR=""
YAY_AVAILABLE=false

AUR_INSTALLED=()
AUR_TO_INSTALL=()
AUR_NOT_FOUND=()
AUR_UNKNOWN=()

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
# Обработчики сигналов и очистка
# =============================================================================

on_error() {
  local exit_code=$?
  local line_no="${1:-unknown}"
  (( exit_code == 141 )) && return 0
  echo "[ERROR] Сбой на строке ${line_no}, код выхода: ${exit_code}" >&2
  exit "$exit_code"
}

cleanup() {
  [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]] && rm -rf -- "${TMP_DIR}"
  [[ -f "${TEMP_SUDOERS_FILE}" ]] && {
    log "Удаляю временный sudoers-файл: ${TEMP_SUDOERS_FILE}"
    rm -f -- "${TEMP_SUDOERS_FILE}"
  }
  return 0
}

trap cleanup EXIT
trap 'on_error $LINENO' ERR

# =============================================================================
# Разбор аргументов
# =============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)         DRY_RUN=true; shift ;;
    --allow-temp-sudo) ALLOW_TEMP_SUDO=true; shift ;;
    --pkgs)
      [[ $# -ge 2 ]] || die "Для --pkgs нужно указать путь к файлу"
      PKGS_FILE="$2"; shift 2 ;;
    --jobs)
      [[ $# -ge 2 ]] || die "Для --jobs нужно указать число"
      [[ "$2" =~ ^[1-9][0-9]*$ ]] \
        || die "--jobs должен быть положительным числом, получено: '$2'"
      BUILD_JOBS="$2"; shift 2 ;;
    --aur-user)
      [[ $# -ge 2 ]] || die "Для --aur-user нужно указать имя пользователя"
      AUR_USER_CLI="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Неизвестный аргумент: '$1'. Запусти с --help для справки." ;;
  esac
done

# =============================================================================
# Загрузка списка пакетов из файла
# =============================================================================

load_packages() {
  local file="$1"
  local abs_path
  abs_path="$(realpath "$file" 2>/dev/null || echo "$file")"

  [[ -f "$file" ]] || die "Файл пакетов не найден: ${abs_path}"

  AUR_PKGS=()
  local line
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line// /}"
    line="${line//	/}"
    [[ -z "$line" ]] && continue
    AUR_PKGS+=("$line")
  done < "$file"

  [[ ${#AUR_PKGS[@]} -gt 0 ]] \
    || die "Файл пакетов пуст или содержит только комментарии: ${abs_path}"

  log "Загружено ${#AUR_PKGS[@]} AUR-пакетов из: ${abs_path}"
}

# =============================================================================
# Функции выполнения команд
# =============================================================================

run_cmd() {
  if $DRY_RUN; then
    printf '[DRY-RUN] '; printf '%q ' "$@"; printf '\n'
  else
    "$@"
  fi
}

run_as_user() {
  if command -v sudo >/dev/null 2>&1; then
    sudo -H -u "${AUR_USER}" -- "$@"
  else
    su - "${AUR_USER}" -s /bin/bash -c "$(printf '%q ' "$@")"
  fi
}

run_as_user_cmd() {
  if $DRY_RUN; then
    printf '[DRY-RUN as %s] ' "${AUR_USER}"; printf '%q ' "$@"; printf '\n'
  else
    run_as_user "$@"
  fi
}

# =============================================================================
# Вспомогательные функции
# =============================================================================

print_list() {
  local title="$1"; shift
  echo; echo "==> ${title}"
  if [[ $# -eq 0 ]]; then echo "  (пусто)"; return 0; fi
  local item
  for item in "$@"; do echo "  - $item"; done
}

is_installed() {
  pacman -Qq "$1" >/dev/null 2>&1
}

# =============================================================================
# Управление временными правами sudo
# =============================================================================

grant_temp_sudo() {
  $DRY_RUN && { log "DRY-RUN: создание временного sudoers-файла пропущено"; return 0; }

  [[ -f "${TEMP_SUDOERS_FILE}" ]] && {
    warn "Найден старый временный sudoers-файл, удаляю: ${TEMP_SUDOERS_FILE}"
    rm -f -- "${TEMP_SUDOERS_FILE}"
  }

  log "Создаю временные права NOPASSWD для пользователя '${AUR_USER}'"

  local tmp_sudoers
  tmp_sudoers="$(mktemp /tmp/sudoers-validate.XXXXXX)"
  cat > "${tmp_sudoers}" <<EOF
# Временный файл, создан install_aur.sh. Удаляется автоматически.
${AUR_USER} ALL=(root) NOPASSWD: /usr/bin/pacman
Defaults:${AUR_USER} !requiretty
EOF

  visudo -cf "${tmp_sudoers}" >/dev/null 2>&1 \
    || { rm -f -- "${tmp_sudoers}"; die "Синтаксическая ошибка во временном sudoers-файле."; }

  install -m 0440 -o root -g root "${tmp_sudoers}" "${TEMP_SUDOERS_FILE}"
  rm -f -- "${tmp_sudoers}"
  log "Временный sudoers-файл установлен: ${TEMP_SUDOERS_FILE}"
}

# =============================================================================
# Проверка существования пакета в AUR
# =============================================================================

# Коды возврата: 0 найден / 1 не существует / 2 неизвестно
aur_exists() {
  local pkg="$1" rc=0

  if $YAY_AVAILABLE; then
    run_as_user yay -Si "$pkg" >/dev/null 2>&1 || rc=$?
    return "$rc"
  fi

  if command -v git >/dev/null 2>&1; then
    run_as_user git ls-remote \
      "https://aur.archlinux.org/${pkg}.git" HEAD >/dev/null 2>&1 || rc=$?
    (( rc == 128 )) && return 1
    (( rc != 0 ))   && return 2
    return 0
  fi

  return 2
}

# =============================================================================
# Классификация AUR-пакетов
# =============================================================================

split_aur_packages() {
  AUR_INSTALLED=(); AUR_TO_INSTALL=(); AUR_NOT_FOUND=(); AUR_UNKNOWN=()

  local pkg rc
  for pkg in "${AUR_PKGS[@]}"; do
    rc=0; aur_exists "$pkg" || rc=$?
    case "$rc" in
      0) is_installed "$pkg" && AUR_INSTALLED+=("$pkg") || AUR_TO_INSTALL+=("$pkg") ;;
      1) AUR_NOT_FOUND+=("$pkg") ;;
      *) is_installed "$pkg" && AUR_INSTALLED+=("$pkg") || AUR_UNKNOWN+=("$pkg") ;;
    esac
  done
}

# =============================================================================
# Установка prereqs и yay
# =============================================================================

install_build_prereqs() {
  log "Синхронизирую базы пакетов (pacman -Sy)"
  pacman -Sy --noconfirm
  log "Устанавливаю git, base-devel (pacman -Su)"
  run_cmd pacman -Su --needed --noconfirm git base-devel
}

install_yay_if_needed() {
  if command -v yay >/dev/null 2>&1; then
    YAY_AVAILABLE=true
    log "yay уже установлен: $(yay --version 2>&1 | { read -r line; echo "$line"; })"
    return 0
  fi

  YAY_AVAILABLE=false
  log "yay не найден, выполняю сборку из AUR"

  if $DRY_RUN; then
    log "DRY-RUN: сборка yay пропущена."
    return 0
  fi

  TMP_DIR="$(mktemp -d "${AUR_HOME}/yay-build.XXXXXX")"
  chown "${AUR_USER}:" "${TMP_DIR}"

  log "Клонирую репозиторий yay от имени ${AUR_USER}"
  run_as_user git clone --depth=1 https://aur.archlinux.org/yay.git "${TMP_DIR}/yay"

  log "Собираю yay (jobs: ${BUILD_JOBS})"
  run_as_user env \
    MAKEFLAGS="-j${BUILD_JOBS}" \
    BUILDDIR="${AUR_CACHE_DIR}" \
    bash -c "cd $(printf '%q' "${TMP_DIR}/yay") && makepkg -s --noconfirm --needed"

  local pkg_file=""
  pkg_file="$(find "${TMP_DIR}/yay" -maxdepth 1 -type f \
    \( -name 'yay-*.pkg.tar.zst' -o -name 'yay-*.pkg.tar.xz' \) \
    -printf '%T@ %p\n' | sort -rn | head -n1 | cut -d' ' -f2-)"

  [[ -n "${pkg_file}" ]] || die "Не удалось найти собранный пакет yay в ${TMP_DIR}/yay"

  log "Устанавливаю yay: $(basename "${pkg_file}")"
  pacman -U --noconfirm "${pkg_file}"

  command -v yay >/dev/null 2>&1 || die "yay не обнаружен после установки"
  YAY_AVAILABLE=true
  log "yay успешно установлен: $(yay --version 2>&1 | { read -r line; echo "$line"; })"
}

# =============================================================================
# Установка AUR-пакетов
# =============================================================================

install_aur_packages() {
  local targets=()
  (( ${#AUR_TO_INSTALL[@]} > 0 )) && targets+=("${AUR_TO_INSTALL[@]}")

  if (( ${#AUR_UNKNOWN[@]} > 0 )); then
    warn "Следующие пакеты не удалось проверить заранее (передаю в yay напрямую):"
    printf '  - %s\n' "${AUR_UNKNOWN[@]}"
    targets+=("${AUR_UNKNOWN[@]}")
  fi

  if (( ${#targets[@]} == 0 )); then
    log "Все AUR-пакеты уже установлены, пропускаю"
    return 0
  fi

  log "Устанавливаю ${#targets[@]} AUR-пакет(ов) через yay"

  run_as_user_cmd mkdir -p "${AUR_CACHE_DIR}"
  run_as_user_cmd yay -S \
    --needed --noconfirm \
    --builddir "${AUR_CACHE_DIR}" \
    --norebuild \
    --mflags "-j${BUILD_JOBS}" \
    --answerclean None \
    --answerdiff None \
    --answeredit None \
    "${targets[@]}"
}

# =============================================================================
# Финальная верификация
# =============================================================================

verify_aur_packages() {
  local failed=() pkg
  for pkg in "${AUR_PKGS[@]}"; do
    is_installed "$pkg" || failed+=("$pkg")
  done
  if (( ${#failed[@]} > 0 )); then
    warn "Следующие пакеты не установлены после завершения:"
    printf '  - %s\n' "${failed[@]}"
    return 1
  fi
  log "Верификация: все AUR-пакеты на месте"
  return 0
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
  [[ $EUID -eq 0 ]] || die "Скрипт нужно запускать от root (через sudo или напрямую)"
  command -v pacman >/dev/null 2>&1 || die "pacman не найден. Только для Arch Linux."
  [[ ! -e /var/lib/pacman/db.lck ]] \
    || die "База pacman заблокирована (/var/lib/pacman/db.lck)."

  touch "${LOG_FILE}" 2>/dev/null \
    || die "Не могу создать лог-файл: ${LOG_FILE}."
  chmod 600 "${LOG_FILE}" 2>/dev/null || warn "Не удалось установить права 600 на ${LOG_FILE}"

  exec > >(tee -a "${LOG_FILE}") 2>&1

  log "======================================================="
  log "Запуск install_aur.sh -- $(date '+%Y-%m-%d %H:%M:%S')"
  log "======================================================="
  $DRY_RUN && log "Режим DRY-RUN: реальных изменений не будет"

  # --- Определение пользователя ---
  if [[ -n "${AUR_USER_CLI:-}" ]]; then
    AUR_USER="${AUR_USER_CLI}"
  elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    AUR_USER="${SUDO_USER}"
  else
    die "Запусти через sudo от обычного пользователя, или укажи --aur-user USERNAME."
  fi

  [[ "${AUR_USER}" != "root" ]] || die "Нельзя использовать root для AUR."
  id "${AUR_USER}" >/dev/null 2>&1 || die "Пользователь '${AUR_USER}' не существует."

  AUR_HOME="$(getent passwd "${AUR_USER}" | cut -d: -f6)"
  [[ -n "${AUR_HOME:-}" && -d "${AUR_HOME}" ]] \
    || die "Домашний каталог '${AUR_USER}' не найден: '${AUR_HOME}'"

  AUR_CACHE_DIR="${AUR_HOME}/.cache/yay-build"

  log "Пользователь:      ${AUR_USER}"
  log "Домашний каталог:  ${AUR_HOME}"
  log "Каталог кеша AUR:  ${AUR_CACHE_DIR}"
  log "Лог-файл:          ${LOG_FILE}"
  log "Число jobs:        ${BUILD_JOBS}"

  [[ -f "${TEMP_SUDOERS_FILE}" ]] && {
    warn "Найден sudoers-файл от предыдущего запуска, удаляю."
    rm -f -- "${TEMP_SUDOERS_FILE}"
  }

  # 1. Загружаем список пакетов из файла
  load_packages "${PKGS_FILE}"

  # 2. Временные права sudo (unattended-режим)
  $ALLOW_TEMP_SUDO && grant_temp_sudo

  # 3. Prereqs
  install_build_prereqs

  # 4. yay
  install_yay_if_needed

  # 5. Классификация
  split_aur_packages

  print_list "AUR: уже установлены"   "${AUR_INSTALLED[@]+"${AUR_INSTALLED[@]}"}"
  print_list "AUR: будут установлены" "${AUR_TO_INSTALL[@]+"${AUR_TO_INSTALL[@]}"}"
  print_list "AUR: НЕ НАЙДЕНЫ"        "${AUR_NOT_FOUND[@]+"${AUR_NOT_FOUND[@]}"}"
  print_list "AUR: статус неизвестен" "${AUR_UNKNOWN[@]+"${AUR_UNKNOWN[@]}"}"
  echo

  if (( ${#AUR_NOT_FOUND[@]} > 0 )); then
    die "Обнаружены несуществующие пакеты. Исправь packages/aur.txt и запусти снова."
  fi

  # 6. Установка
  install_aur_packages

  # 7. Верификация
  if ! $DRY_RUN; then
    verify_aur_packages \
      || die "Верификация не прошла. Проверь лог: ${LOG_FILE}"
    log "======================================================="
    log "Завершено успешно -- $(date '+%Y-%m-%d %H:%M:%S')"
    log "======================================================="
  else
    log "======================================================="
    log "DRY-RUN завершён. Для установки уберите флаг --dry-run."
    log "======================================================="
  fi
}

main "$@"
