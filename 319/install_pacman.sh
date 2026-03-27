#!/usr/bin/env bash
# =============================================================================
# install_software.sh — установщик пакетов и конфигураций для Arch Linux
#
# Что делает скрипт:
#   1. Определяет производителя видеокарты через lspci и устанавливает
#      соответствующие драйверы (Intel / AMD / NVIDIA nouveau / виртуалка).
#   2. Устанавливает пакеты из официальных репозиториев через pacman.
#   3. Разворачивает конфигурационные файлы из каталога-источника в ~/.config/.
#      Перед заменой каждого файла создаётся резервная копия (.bak.TIMESTAMP).
#
# ИСПОЛЬЗОВАНИЕ:
#   sudo ./install_software.sh [опции]
#
# БЫСТРЫЙ СТАРТ:
#   # Сухой прогон — ничего не меняет, только показывает план:
#   sudo ./install_software.sh --dry-run
#
#   # Полная установка (пакеты + конфиги):
#   sudo ./install_software.sh
#
#   # Только развернуть конфиги, пакеты не трогать:
#   sudo ./install_software.sh --configs-only
#
#   # Только установить пакеты, конфиги не трогать:
#   sudo ./install_software.sh --no-configs
#
# ОПЦИИ:
#   --dry-run           Только анализ: показать что будет сделано, без изменений.
#   --configs-only      Пропустить установку пакетов, только развернуть конфиги.
#   --no-configs        Пропустить развёртывание конфигов, только пакеты.
#   --configs-src DIR   Каталог с конфигами (по умолч.: ./configs рядом со скриптом).
#                       Структура каталога должна зеркалить ~/.config/:
#                         configs/
#                           alacritty/alacritty.toml
#                           dunst/dunstrc
#                           hypr/hyprland.conf
#                           hypr/hyprpaper.conf
#                           hypr/hyprlock.conf
#                           hypr/hypridle.conf
#                           waybar/config.jsonc
#                           waybar/style.css
#                           rofi/config.rasi
#                           rclone/rclone.conf
#   -h, --help          Показать эту справку.
#
# ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ:
#   CONFIGS_SRC         Альтернатива --configs-src (флаг имеет приоритет).
#
# ТРЕБОВАНИЯ:
#   - Arch Linux с pacman
#   - Запуск от root (через sudo)
#   - Доступ в интернет (для обновления баз)
#   - pciutils (устанавливается автоматически если отсутствует)
#
# ТОПОЛОГИЯ ДИСКОВ:
#   /dev/sda1 -> /        (корневой раздел, переустанавливается при смене ОС)
#   /dev/sda2 -> /boot    (загрузчик)
#   /dev/sdb1 -> /home    (домашние каталоги, данные сохраняются между переустановками)
#
#   Конфиги хранятся на /dev/sdb1 вместе с /home — при переустановке системы
#   на /dev/sda данные пользователя и конфиги остаются нетронутыми.
#   Скрипт копирует файлы (не создаёт симлинки), поэтому работает независимо
#   от того, смонтирован ли /home в момент запуска.
# =============================================================================

set -Eeuo pipefail

# =============================================================================
# Константы и значения по умолчанию
# =============================================================================

readonly LOG_FILE="/var/log/install_software.log"

DRY_RUN=false
DEPLOY_CONFIGS=true   # становится false при --no-configs
CONFIGS_ONLY=false    # становится true при --configs-only
# Источник конфигов: переменная окружения -> каталог ./configs рядом со скриптом.
# Флаг --configs-src перекрывает оба варианта.
CONFIGS_SRC="${CONFIGS_SRC:-$(dirname "$(realpath "$0")")/configs}"

# =============================================================================
# PACMAN_PKGS — базовые пакеты из официальных репозиториев
# =============================================================================
# Видеодрайверы в этот массив НЕ входят — они определяются автоматически
# функцией detect_gpu() и добавляются в GPU_PKGS.
# Все пакеты проверяются через `pacman -Si` перед установкой.

PACMAN_PKGS=(
  # --- Wayland — стек и интеграция ---
  wayland
  wayland-protocols
  xorg-xwayland                    # Совместимость с X11-приложениями
  xdg-desktop-portal-hyprland      # Обязателен: скриншоты, screen-share, разреш. окон
  xdg-desktop-portal-gtk           # Диалоги выбора файлов (file picker)
  qt5-wayland                      # Qt5-приложения нативно на Wayland
  qt6-wayland                      # Qt6-приложения нативно на Wayland

  # --- Hyprland и экосистема ---
  hyprland                         # Сам WM
  hyprpaper                        # Обои (статические)
  awww                             # Обои с анимацией (gif, плавные переходы); переименован из swww
  hyprlock                         # Экранный замок
  hypridle                         # Управление idle / DPMS
  waybar                           # Статусная панель
  wlr-randr                        # Аналог xrandr для wlroots
  kanshi                           # Автопрофили мониторов (как autorandr)

  # --- Библиотеки ---
  libxkbcommon                     # Раскладки клавиатуры (нужен Wayland)
  libnotify                        # D-Bus-уведомления
  freetype2
  fontconfig

  # --- Шрифты ---
  ttf-jetbrains-mono-nerd
  otf-font-awesome
  noto-fonts
  noto-fonts-cjk
  noto-fonts-emoji

  # --- Звук (PipeWire) ---
  pipewire
  pipewire-alsa
  pipewire-pulse
  pipewire-jack
  wireplumber
  alsa-utils
  pamixer
  playerctl                        # Управление медиаплеером (MPRIS)

  # --- Системные компоненты ---
  base-devel
  accountsservice
  polkit-gnome
  xdg-utils
  xdg-user-dirs
  openssh
  gvfs
  unzip
  tree
  dmidecode
  pciutils                         # Нужен для lspci (определение GPU)

  # --- Сеть ---
  iproute2
  bind
  networkmanager
  network-manager-applet           # nm-applet — трей NetworkManager
  nm-connection-editor             # GUI-редактор сетевых подключений

  # --- Терминалы ---
  alacritty                        # Поддерживает Wayland нативно
  kitty                            # Поддерживает Wayland нативно

  # --- Файловые менеджеры ---
  mc
  ranger
  nautilus
  gnome-disk-utility

  # --- Запуск приложений ---
  fuzzel                           # Wayland-нативный лаунчер (замена rofi)

  # --- Уведомления ---
  dunst                            # Работает на Wayland начиная с v1.9

  # --- Буфер обмена ---
  wl-clipboard                     # Wayland-буфер обмена
  cliphist                         # История буфера обмена

  # --- Скриншоты ---
  grim                             # Скриншот экрана (Wayland)
  slurp                            # Выбор области для grim
  swappy                           # Аннотации поверх скриншота

  # --- Wayland-отладка ---
  wev                              # Просмотр событий Wayland (аналог xev)

  # --- Яркость ---
  brightnessctl

  # --- Браузеры и связь ---
  firefox
  telegram-desktop
  thunderbird

  # --- Текстовые редакторы ---
  vim
  mousepad

  # --- Утилиты командной строки ---
  wget
  curl
  git
  eza
  duf
  ncdu
  rclone
  lazygit
  s-tui

  # --- Мониторинг системы ---
  btop
  htop
  atop
  bluetui
  wiremix
  dysk

  # --- Docker ---
  docker
)

# =============================================================================
# Таблица видеодрайверов
# =============================================================================
#
# detect_gpu() анализирует вывод lspci, определяет производителя и заполняет
# массив GPU_PKGS нужными пакетами из этой таблицы.
#
# Intel (встройка): требует mesa + vulkan-intel + VA-API драйверы.
#   intel-media-driver  — VA-API для Broadwell и новее (iHD)
#   libva-intel-driver  — VA-API для Ivy Bridge и старее (i965)
#   Ставим оба: система сама выберет нужный по железу.
#
# AMD (дискретная / встройка): mesa + vulkan-radeon + libva-mesa-driver.
#
# NVIDIA (nouveau, свободный драйвер): mesa + libva-mesa-driver + vulkan-nouveau.
#   Проприетарный nvidia в этом скрипте не ставится.
#   Если нужен — замени пакеты вручную или добавь отдельную ветку ниже.
#
# VMware / VirtualBox (виртуалка): mesa + гостевые утилиты.

GPU_PKGS=()   # заполняется в detect_gpu(), используется в main

# =============================================================================
# Карта конфигурационных файлов
# =============================================================================
#
# Формат каждой записи:  "приложение:файл_или_подкаталог"
#
#   "приложение" — имя подкаталога внутри CONFIGS_SRC/ и внутри ~/.config/
#   "файл"       — конкретный файл или подкаталог внутри приложения
#
# Примеры записей:
#   "alacritty:alacritty.toml"
#       CONFIGS_SRC/alacritty/alacritty.toml  ->  ~/.config/alacritty/alacritty.toml
#
#   "rofi:themes"
#       CONFIGS_SRC/rofi/themes/  ->  ~/.config/rofi/themes/  (рекурсивно)
#
# Чтобы добавить конфиг — добавь строку. Чтобы временно отключить — закомментируй.

CONFIG_FILES=(
  # Терминал Alacritty
  "alacritty:alacritty.toml"

  # Демон уведомлений Dunst
  "dunst:dunstrc"

  # Hyprland — основные конфиги WM
  "hypr:hyprland.conf"
  "hypr:hyprpaper.conf"
  "hypr:hyprlock.conf"
  "hypr:hypridle.conf"

  # Статусная панель Waybar
  "waybar:config.jsonc"
  "waybar:style.css"

  # Запускалка приложений Fuzzel
  # (rofi:config.rasi оставлен для совместимости если rofi установлен отдельно)
  "rofi:config.rasi"

  # Синхронизация облака rclone
  # ВНИМАНИЕ: rclone.conf содержит токены доступа к облачным сервисам.
  # Файл копируется с правами 600. Не добавляй его в публичные репозитории!
  "rclone:rclone.conf"
)

# Конфиги с чувствительными данными — копируются с правами 600 вместо 644.
SENSITIVE_CONFIGS=(
  "rclone:rclone.conf"
)

# =============================================================================
# Внутренние переменные состояния (не трогать вручную)
# =============================================================================

TARGET_USER=""        # пользователь-владелец конфигов (определяется в main)
TARGET_HOME=""        # домашний каталог TARGET_USER

# Массивы результатов классификации пакетов (заполняются функцией split_packages)
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
# Обработчики сигналов и очистка
# =============================================================================

on_error() {
  local exit_code=$?
  local line_no="${1:-unknown}"
  # Код 141 = SIGPIPE: возникает когда tee в exec-редиректе получает сигнал
  # при завершении скрипта. Это ложное срабатывание — игнорируем.
  (( exit_code == 141 )) && return 0
  echo "[ERROR] Сбой на строке ${line_no}, код выхода: ${exit_code}" >&2
  exit "$exit_code"
}

cleanup() {
  return 0
}

trap cleanup EXIT
trap 'on_error $LINENO' ERR

# =============================================================================
# Разбор аргументов командной строки
# =============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --configs-only)
      CONFIGS_ONLY=true
      shift
      ;;
    --no-configs)
      DEPLOY_CONFIGS=false
      shift
      ;;
    --configs-src)
      [[ $# -ge 2 ]] || die "Для --configs-src нужно указать путь к каталогу"
      CONFIGS_SRC="$2"
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

if $CONFIGS_ONLY && ! $DEPLOY_CONFIGS; then
  die "--configs-only и --no-configs нельзя использовать одновременно."
fi

# =============================================================================
# Функции выполнения команд
# =============================================================================

# Выполняет команду — или выводит её в dry-run режиме.
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
# Вспомогательные функции
# =============================================================================

# Выводит список пакетов с заголовком.
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

# Проверяет, установлен ли пакет через pacman.
is_installed() {
  pacman -Qq "$1" >/dev/null 2>&1
}

# Проверяет, существует ли пакет в официальных репозиториях.
repo_exists() {
  pacman -Si "$1" >/dev/null 2>&1
}

# Проверяет, что все пакеты из переданного списка реально установлены.
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

# Заполняет массив GPU_PKGS пакетами для найденных GPU.
# Поддерживаются: Intel, AMD, NVIDIA (nouveau), VMware, VirtualBox.
# Если GPU не распознан — предупреждение, скрипт продолжает работу.
#
# Логика: lspci фильтруется по классу VGA/3D/Display.
# Один компьютер может иметь несколько GPU (iGPU + dGPU) — обрабатываем все.
# Дублирующиеся пакеты (например mesa, если найдены Intel и AMD) дедуплицируются.
detect_gpu() {
  GPU_PKGS=()

  if ! command -v lspci >/dev/null 2>&1; then
    warn "lspci не найден — pciutils ещё не установлен."
    warn "Пропускаю автоопределение GPU. Драйверы не будут установлены."
    return 0
  fi

  # -mm: машиночитаемый формат (поля в кавычках через пробел).
  # Пример строки: 00:02.0 "VGA compatible controller" "Intel Corporation"
  #                         "UHD Graphics 620" -r07 "Apple Inc." "MacBook Air"
  local lspci_out
  lspci_out="$(lspci -mm | grep -iE '"(VGA compatible controller|3D controller|Display controller)"')" || true

  if [[ -z "${lspci_out}" ]]; then
    warn "GPU-устройства не обнаружены через lspci. Драйверы не будут установлены."
    return 0
  fi

  # Флаги найденных производителей — не дублируем пакеты.
  local found_intel=false
  local found_amd=false
  local found_nvidia=false
  local found_vmware=false
  local found_vbox=false

  local line vendor
  while IFS= read -r line; do
    # В формате -mm поле Vendor — это 3-я пара кавычек (индекс 6 при разбивке по '"').
    # Пример: 0 "" 1 "VGA..." 2 "" 3 "Intel..." -> cut -d'"' -f6
    vendor="$(echo "${line}" | cut -d'"' -f6)"

    case "${vendor}" in
      *Intel*)
        found_intel=true
        log "  GPU: Intel — ${vendor}"
        ;;
      *AMD*|*ATI*|*"Advanced Micro"*)
        found_amd=true
        log "  GPU: AMD — ${vendor}"
        ;;
      *NVIDIA*)
        found_nvidia=true
        log "  GPU: NVIDIA — ${vendor}"
        ;;
      *VMware*)
        found_vmware=true
        log "  GPU: VMware (виртуалка) — ${vendor}"
        ;;
      *VirtualBox*|*InnoTek*)
        found_vbox=true
        log "  GPU: VirtualBox (виртуалка) — ${vendor}"
        ;;
      *)
        warn "  GPU: нераспознанный производитель: '${vendor}'"
        warn "       Полная строка lspci: ${line}"
        warn "       Добавь обработку в detect_gpu() или установи драйверы вручную."
        ;;
    esac
  done <<< "${lspci_out}"

  # --- Intel ---
  # mesa               — DRI через i965/iris/crocus
  # vulkan-intel       — Vulkan через ANV (Broadwell+)
  # intel-media-driver — VA-API для Broadwell и новее (iHD драйвер)
  # libva-intel-driver — VA-API для Ivy Bridge и старее (i965 драйвер)
  # Оба VA-API ставим вместе: система выберет нужный по железу через LIBVA_DRIVER_NAME.
  if $found_intel; then
    GPU_PKGS+=(
      mesa
      libva-mesa-driver
      vulkan-intel
      intel-media-driver
      libva-intel-driver
    )
  fi

  # --- AMD ---
  # mesa              — DRI через radeonsi
  # vulkan-radeon     — Vulkan через RADV
  # libva-mesa-driver — VA-API через Gallium/radeonsi
  if $found_amd; then
    GPU_PKGS+=(
      mesa
      libva-mesa-driver
      vulkan-radeon
    )
  fi

  # --- NVIDIA (nouveau, свободный драйвер) ---
  # mesa              — DRI через nouveau
  # libva-mesa-driver — VA-API через Gallium/nouveau
  # vulkan-nouveau    — Vulkan через NVK (требует mesa 24+)
  # Если нужен проприетарный nvidia — замени эти пакеты на:
  #   nvidia nvidia-utils libva-nvidia-driver
  if $found_nvidia; then
    GPU_PKGS+=(
      mesa
      libva-mesa-driver
      vulkan-nouveau
    )
  fi

  # --- VMware ---
  # open-vm-tools      — интеграция с гипервизором (буфер обмена, resize)
  # xf86-video-vmware  — 2D-ускорение для Xwayland
  if $found_vmware; then
    GPU_PKGS+=(
      mesa
      open-vm-tools
      xf86-video-vmware
    )
  fi

  # --- VirtualBox ---
  # virtualbox-guest-utils — shared folders, clipboard, resize
  if $found_vbox; then
    GPU_PKGS+=(
      mesa
      virtualbox-guest-utils
    )
  fi

  # Дедупликация: iGPU + dGPU дают дублирующиеся mesa и libva-mesa-driver.
  # pacman --needed справится, но лог и вывод плана будут чище без дублей.
  local dedup=()
  local seen=""
  local pkg
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

# Распределяет объединённый список PACMAN_PKGS + GPU_PKGS по трём группам:
#   REPO_INSTALLED  — уже установлены
#   REPO_TO_INSTALL — есть в репо, нужно установить
#   REPO_NOT_FOUND  — не найдены в репозиториях (скрипт завершится с ошибкой)
split_packages() {
  REPO_INSTALLED=()
  REPO_TO_INSTALL=()
  REPO_NOT_FOUND=()

  local all_pkgs=("${PACMAN_PKGS[@]}")
  if (( ${#GPU_PKGS[@]} > 0 )); then
    all_pkgs+=("${GPU_PKGS[@]}")
  fi

  local pkg
  for pkg in "${all_pkgs[@]}"; do
    if repo_exists "$pkg"; then
      if is_installed "$pkg"; then
        REPO_INSTALLED+=("$pkg")
      else
        REPO_TO_INSTALL+=("$pkg")
      fi
    else
      REPO_NOT_FOUND+=("$pkg")
    fi
  done
}

# =============================================================================
# Синхронизация баз и установка prereqs
# =============================================================================

# Синхронизирует базы пакетов (pacman -Sy).
# Выполняется всегда, в том числе в dry-run — это read-only операция,
# необходимая для корректной работы repo_exists() / pacman -Si.
sync_package_databases() {
  log "Синхронизирую базы пакетов (pacman -Sy)"
  pacman -Sy --noconfirm
}

# Устанавливает базовые prereqs и обновляет систему.
# Базы уже синхронизированы в sync_package_databases(), поэтому -Su (без повторного -y).
# pciutils устанавливается здесь, чтобы detect_gpu() мог вызвать lspci.
install_build_prereqs() {
  log "Устанавливаю pciutils, base-devel и обновляю систему (pacman -Su)"
  log "Это выполнит полное обновление системы — штатное поведение Arch Linux"
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
# Развёртывание конфигурационных файлов
# =============================================================================

# Проверяет, входит ли запись "app:file" в список SENSITIVE_CONFIGS.
is_sensitive_config() {
  local entry="$1"
  local s
  for s in "${SENSITIVE_CONFIGS[@]+"${SENSITIVE_CONFIGS[@]}"}"; do
    [[ "${s}" == "${entry}" ]] && return 0
  done
  return 1
}

# Создаёт резервную копию файла или каталога с суффиксом .bak.YYYYMMDD_HHMMSS.
backup_if_exists() {
  local target="$1"
  [[ -e "${target}" || -L "${target}" ]] || return 0
  local backup="${target}.bak.$(date '+%Y%m%d_%H%M%S')"
  if $DRY_RUN; then
    log "    DRY-RUN: резервная копия  ${target}  ->  $(basename "${backup}")"
  else
    cp -a --remove-destination "${target}" "${backup}"
    log "    Резервная копия: $(basename "${backup}")"
  fi
}

# Копирует один файл или каталог из src в dst.
# mode="sensitive" -> chmod 600; иначе -> chmod 644.
deploy_item() {
  local src="$1"
  local dst="$2"
  local mode="${3:-normal}"

  if [[ -d "${src}" ]]; then
    if $DRY_RUN; then
      log "    DRY-RUN: cp -a  ${src}/  ->  ${dst}/"
    else
      mkdir -p "${dst}"
      cp -a "${src}/." "${dst}/"
      chown -R "${TARGET_USER}:" "${dst}"
      log "    Каталог: ${dst}/"
    fi
  else
    if $DRY_RUN; then
      local perm; [[ "${mode}" == "sensitive" ]] && perm="600" || perm="644"
      log "    DRY-RUN: cp  ${src}  ->  ${dst}  (${perm})"
    else
      mkdir -p "$(dirname "${dst}")"
      cp -a "${src}" "${dst}"
      chown "${TARGET_USER}:" "${dst}"
      if [[ "${mode}" == "sensitive" ]]; then
        chmod 600 "${dst}"
        log "    Файл (600): ${dst}"
      else
        chmod 644 "${dst}"
        log "    Файл (644): ${dst}"
      fi
    fi
  fi
}

# Главная функция развёртывания конфигов.
# Для каждой записи в CONFIG_FILES:
#   1. Проверяет наличие источника в CONFIGS_SRC.
#   2. Создаёт резервную копию существующего файла в ~/.config/.
#   3. Копирует новый файл с нужными правами.
deploy_configs() {
  log "-------------------------------------------------------"
  log "Развёртывание конфигурационных файлов"
  log "  Источник:    ${CONFIGS_SRC}"
  log "  Назначение:  ${TARGET_HOME}/.config/"
  log "-------------------------------------------------------"

  if [[ ! -d "${CONFIGS_SRC}" ]]; then
    warn "Каталог конфигов не найден: ${CONFIGS_SRC}"
    warn "Ожидаемая структура:"
    warn "  ${CONFIGS_SRC}/"
    warn "    alacritty/alacritty.toml"
    warn "    dunst/dunstrc"
    warn "    hypr/hyprland.conf"
    warn "    hypr/hyprpaper.conf"
    warn "    hypr/hyprlock.conf"
    warn "    hypr/hypridle.conf"
    warn "    waybar/config.jsonc"
    warn "    waybar/style.css"
    warn "    rofi/config.rasi"
    warn "    rclone/rclone.conf"
    warn "Создай каталог рядом со скриптом или укажи путь через --configs-src DIR."
    warn "Развёртывание конфигов пропущено."
    return 0
  fi

  local deployed=0 skipped=0
  local entry app item src dst

  for entry in "${CONFIG_FILES[@]}"; do
    app="${entry%%:*}"
    item="${entry##*:}"
    src="${CONFIGS_SRC}/${app}/${item}"
    dst="${TARGET_HOME}/.config/${app}/${item}"

    if [[ ! -e "${src}" ]]; then
      warn "Источник не найден, пропускаю: ${src}"
      (( skipped++ )) || true
      continue
    fi

    log "  ${app}/${item}"
    backup_if_exists "${dst}"

    local mode="normal"
    is_sensitive_config "${entry}" && mode="sensitive"

    deploy_item "${src}" "${dst}" "${mode}"
    (( deployed++ )) || true
  done

  echo
  log "Конфиги: развёрнуто — ${deployed}, пропущено (нет источника) — ${skipped}"

  if ! $DRY_RUN; then
    local e
    for e in "${CONFIG_FILES[@]}"; do
      if [[ "${e}" == rclone:* ]]; then
        log ""
        log "  ! rclone.conf содержит токены доступа к облачным сервисам."
        log "    Скопирован с правами 600. Не добавляй в публичные репозитории."
        break
      fi
    done
  fi
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
  # -------------------------------------------------------------------------
  # Предварительные проверки
  # -------------------------------------------------------------------------

  [[ $EUID -eq 0 ]] || die "Скрипт нужно запускать от root (через sudo или напрямую)"

  command -v pacman >/dev/null 2>&1 \
    || die "pacman не найден. Скрипт предназначен только для Arch Linux."

  [[ ! -e /var/lib/pacman/db.lck ]] \
    || die "База pacman заблокирована (/var/lib/pacman/db.lck). \
Убедись, что pacman не запущен, и удали файл блокировки вручную."

  touch "${LOG_FILE}" 2>/dev/null \
    || die "Не могу создать лог-файл: ${LOG_FILE}. Проверь права на /var/log/."

  if ! chmod 600 "${LOG_FILE}" 2>/dev/null; then
    warn "Не удалось установить права 600 на ${LOG_FILE}"
  fi

  exec > >(tee -a "${LOG_FILE}") 2>&1

  log "======================================================="
  log "Запуск install_software.sh — $(date '+%Y-%m-%d %H:%M:%S')"
  log "======================================================="

  $DRY_RUN        && log "Режим DRY-RUN: реальных изменений не будет"
  $CONFIGS_ONLY   && log "Режим --configs-only: установка пакетов пропущена"
  $DEPLOY_CONFIGS || log "Флаг --no-configs: развёртывание конфигов пропущено"

  # -------------------------------------------------------------------------
  # Определение пользователя для конфигов
  # -------------------------------------------------------------------------

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="${SUDO_USER}"
  else
    die "Не удалось определить пользователя. \
Запусти через sudo от обычного пользователя: sudo ./install_software.sh"
  fi

  [[ "${TARGET_USER}" != "root" ]] \
    || die "Нельзя использовать root. Запусти через sudo от обычного пользователя."

  id "${TARGET_USER}" >/dev/null 2>&1 \
    || die "Пользователь '${TARGET_USER}' не существует в системе."

  # getent надёжнее $HOME при sudo — читает /etc/passwd напрямую.
  TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  [[ -n "${TARGET_HOME:-}" && -d "${TARGET_HOME}" ]] \
    || die "Домашний каталог пользователя '${TARGET_USER}' не найден: '${TARGET_HOME}'"

  log "Пользователь:        ${TARGET_USER}"
  log "Домашний каталог:    ${TARGET_HOME}"
  log "Каталог конфигов:    ${CONFIGS_SRC}"
  log "Лог-файл:            ${LOG_FILE}"

  # -------------------------------------------------------------------------
  # Установка пакетов (пропускается при --configs-only)
  # -------------------------------------------------------------------------

  if ! $CONFIGS_ONLY; then

    # 1. Синхронизируем базы (выполняется всегда, включая dry-run).
    sync_package_databases

    # 2. Устанавливаем prereqs и обновляем систему (пропускается в dry-run).
    #    После этого шага lspci гарантированно доступен.
    install_build_prereqs

    # 3. Определяем GPU и формируем GPU_PKGS.
    log "Определяю видеокарту..."
    detect_gpu

    # 4. Классифицируем все пакеты: базовые (PACMAN_PKGS) + GPU (GPU_PKGS).
    split_packages

    # Вывод плана установки.
    print_list "GPU-пакеты (определены автоматически)" \
      "${GPU_PKGS[@]+"${GPU_PKGS[@]}"}"
    print_list "Уже установлены"   "${REPO_INSTALLED[@]+"${REPO_INSTALLED[@]}"}"
    print_list "Будут установлены" "${REPO_TO_INSTALL[@]+"${REPO_TO_INSTALL[@]}"}"
    print_list "НЕ НАЙДЕНЫ в репо" "${REPO_NOT_FOUND[@]+"${REPO_NOT_FOUND[@]}"}"
    echo

    if (( ${#REPO_NOT_FOUND[@]} > 0 )); then
      die "Обнаружены несуществующие пакеты (см. выше). \
Исправь PACMAN_PKGS или таблицу GPU-пакетов в detect_gpu() и запусти снова."
    fi

    # 5. Устанавливаем.
    install_packages
  fi

  # -------------------------------------------------------------------------
  # Развёртывание конфигов (пропускается при --no-configs)
  # -------------------------------------------------------------------------

  $DEPLOY_CONFIGS && deploy_configs

  # -------------------------------------------------------------------------
  # Финальная верификация (только в реальном режиме)
  # -------------------------------------------------------------------------

  if ! $DRY_RUN && ! $CONFIGS_ONLY; then
    local all_pkgs=("${PACMAN_PKGS[@]}")
    if (( ${#GPU_PKGS[@]} > 0 )); then
      all_pkgs+=("${GPU_PKGS[@]}")
    fi

    local verification_failed=false
    verify_installed_group "все пакеты" "${all_pkgs[@]}" || verification_failed=true

    if $verification_failed; then
      die "Верификация не прошла: часть пакетов не установлена. \
Проверь лог: ${LOG_FILE}"
    fi
  fi

  if $DRY_RUN; then
    log "======================================================="
    log "DRY-RUN завершён. Реальных изменений не было."
    log "Для запуска установки уберите флаг --dry-run."
    log "======================================================="
  else
    log "======================================================="
    log "Завершено успешно — $(date '+%Y-%m-%d %H:%M:%S')"
    log "======================================================="
  fi
}

main "$@"
