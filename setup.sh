#!/usr/bin/env bash
# =============================================================================
# setup.sh — Post-install bootstrap для Arch Linux + Hyprland
# Репо: https://github.com/Amar73/debi3wm
#
# ИСПОЛЬЗОВАНИЕ:
#   git clone https://github.com/Amar73/debi3wm.git ~/debi3wm
#   cd ~/debi3wm && chmod +x setup.sh && ./setup.sh
# =============================================================================

set -euo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; BLUE=$'\033[0;34m'; RESET=$'\033[0m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_KEY="$HOME/.ssh/id_ed25519"
GIT_EMAIL="319_amar@grid.kiae.ru"
GIT_NAME="Amar73"
GITHUB_USER="Amar73"

log()  { echo "${GREEN}==>${RESET} $*"; }
warn() { echo "${YELLOW}[!]${RESET} $*"; }
die()  { echo "${RED}[ERR]${RESET} $*" >&2; exit 1; }
step() { echo; echo "${CYAN}━━━ $* ━━━${RESET}"; }

# =============================================================================
step "1/8  Git конфигурация"
git config --global user.email  "$GIT_EMAIL"
git config --global user.name   "$GIT_NAME"
git config --global init.defaultBranch main
git config --global core.editor vim
git config --global pull.rebase false
log "Git: $GIT_NAME <$GIT_EMAIL>"

# =============================================================================
step "2/8  SSH ключ"
mkdir -p ~/.ssh && chmod 700 ~/.ssh

if [[ -f "$SSH_KEY" ]]; then
    log "Ключ уже существует: $SSH_KEY"
else
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N ""
    log "Новый ключ создан"
fi

# =============================================================================
step "3/8  Загрузка SSH-ключа на GitHub"
echo
echo "${BLUE}Твой публичный ключ:${RESET}"
echo "──────────────────────────────────────────────────────────"
cat "${SSH_KEY}.pub"
echo "──────────────────────────────────────────────────────────"
echo

if command -v gh >/dev/null 2>&1; then
    log "Найден GitHub CLI — используем gh"
    if ! gh auth status >/dev/null 2>&1; then
        echo "Авторизация: выбери GitHub.com → SSH → Login with a web browser"
        echo "На телефоне открой github.com/login/device и введи код с экрана"
        gh auth login --hostname github.com --git-protocol ssh --web
    else
        log "gh уже авторизован"
    fi
    KEY_TITLE="arch-$(hostname)-$(date +%Y%m%d)"
    if gh ssh-key list 2>/dev/null | grep -q "$(cut -d' ' -f2 "${SSH_KEY}.pub")"; then
        log "Ключ уже есть на GitHub"
    else
        gh ssh-key add "${SSH_KEY}.pub" --title "$KEY_TITLE" && log "Ключ загружен: $KEY_TITLE"
    fi
else
    warn "github-cli не установлен. Варианты добавления ключа:"
    echo
    echo "  А) Через curl + Personal Access Token (на телефоне):"
    echo "     github.com → Settings → Developer settings → Tokens (classic)"
    echo "     → New → поставить галку admin:public_key → Generate"
    echo
    read -rp "  Вставь токен (или Enter чтобы добавить вручную): " GH_TOKEN
    if [[ -n "${GH_TOKEN:-}" ]]; then
        PUB_KEY=$(cat "${SSH_KEY}.pub")
        HTTP_CODE=$(curl -s -o /tmp/gh_resp.json -w "%{http_code}" \
            -X POST \
            -H "Authorization: token $GH_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            https://api.github.com/user/keys \
            -d "{\"title\":\"arch-$(hostname)\",\"key\":\"$PUB_KEY\"}")
        [[ "$HTTP_CODE" == "201" ]] \
            && log "Ключ загружен на GitHub (HTTP 201)" \
            || { warn "Ошибка HTTP $HTTP_CODE"; cat /tmp/gh_resp.json; echo; \
                 warn "Добавь ключ вручную на github.com"; \
                 read -rp "  Нажми Enter после добавления... "; }
    else
        echo "  Б) Вручную: github.com → Settings → SSH and GPG keys → New SSH key"
        echo "     Вставь содержимое файла выше"
        read -rp "  Нажми Enter после добавления ключа... "
    fi
fi

# =============================================================================
step "4/8  Проверка SSH-соединения с GitHub"
eval "$(ssh-agent -s)" > /dev/null 2>&1 || true
ssh-add "$SSH_KEY" 2>/dev/null || true

ssh -T git@github.com -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new 2>&1 \
    | grep -q "successfully" \
    && log "GitHub SSH: OK" \
    || warn "GitHub SSH: не подтверждено (это нормально если ключ только что добавлен)"

# =============================================================================
step "5/8  SSH config из репо"
SSH_CONFIG_SRC="$REPO_DIR/319/ssh/config"

if [[ -f ~/.ssh/config ]]; then
    cp ~/.ssh/config ~/.ssh/config.bak.$(date '+%Y%m%d_%H%M%S')
fi

if [[ -f "$SSH_CONFIG_SRC" ]]; then
    # Исправляем баг: IdentityAgent с путём к ключу → IdentityFile
    sed 's|IdentityAgent ~/.ssh/id_ed25519|IdentityFile ~/.ssh/id_ed25519|g' \
        "$SSH_CONFIG_SRC" > ~/.ssh/config
    log "SSH config из репо (исправлен IdentityAgent)"
else
    cat > ~/.ssh/config << 'EOF'
Host github.com
    HostName github.com
    User git
    IdentityAgent none
    IdentityFile ~/.ssh/id_ed25519

Host amar224
    HostName amar
    User amar
    IdentityFile ~/.ssh/id_ed25519
    AddKeysToAgent yes

Host wn75
    HostName wn75
    User root
    ProxyJump amar224

Host arch03 arch04 arch05
    HostName %h
    User root
    ProxyJump wn75

Host ui
    HostName ui
    User amar
    Port 7890
    ProxyJump amar224

Host archminio01 archminio02
    HostName %h
    User amar
    ProxyJump ui

Host *
    AddKeysToAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ConnectTimeout 15
    Compression yes
    ControlMaster auto
    ControlPath ~/.ssh/ctrl-%r@%h:%p
    ControlPersist 10m
EOF
    log "SSH config создан из шаблона"
fi
chmod 600 ~/.ssh/config

# =============================================================================
step "6/8  Переключение git remote на SSH"
cd "$REPO_DIR"
CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$CURRENT_REMOTE" == https* ]]; then
    git remote set-url origin "git@github.com:${GITHUB_USER}/debi3wm.git"
    log "Remote: $(git remote get-url origin)"
else
    log "Remote уже SSH: $CURRENT_REMOTE"
fi

# =============================================================================
step "7/8  Развёртывание конфигов"

CONFIG_SRC="$REPO_DIR/config"
CONFIG_DST="$HOME/.config"

deploy() {
    local src="$1" dst="$2"
    [[ -e "$src" ]] || { warn "Нет источника: $src"; return 0; }
    mkdir -p "$(dirname "$dst")"
    [[ -e "$dst" ]] && cp -a "$dst" "${dst}.bak.$(date '+%Y%m%d_%H%M%S')" 2>/dev/null || true
    cp -a "$src" "$dst"
    log "  ✓ $(realpath --relative-to="$CONFIG_DST" "$dst" 2>/dev/null || basename "$dst")"
}

# Alacritty
deploy "$CONFIG_SRC/alacritty/alacritty.toml" "$CONFIG_DST/alacritty/alacritty.toml"

# Dunst — исправляем #1121DCC (7 hex символов) → #11121D
mkdir -p "$CONFIG_DST/dunst"
[[ -f "$CONFIG_SRC/dunst/dunstrc" ]] && \
    sed 's|background = "#1121DCC"|background = "#11121D"|g' \
        "$CONFIG_SRC/dunst/dunstrc" > "$CONFIG_DST/dunst/dunstrc" && \
    log "  ✓ dunst/dunstrc (исправлен невалидный hex-цвет)"

# Hyprland
mkdir -p "$CONFIG_DST/hypr"
for f in hyprland.conf hyprpaper.conf hyprlock.conf hypridle.conf; do
    [[ -f "$CONFIG_SRC/hypr/$f" ]] && deploy "$CONFIG_SRC/hypr/$f" "$CONFIG_DST/hypr/$f"
done

# Waybar
for f in config.jsonc style.css; do
    [[ -f "$CONFIG_SRC/waybar/$f" ]] && deploy "$CONFIG_SRC/waybar/$f" "$CONFIG_DST/waybar/$f"
done
if [[ -d "$CONFIG_SRC/waybar/scripts" ]]; then
    mkdir -p "$CONFIG_DST/waybar/scripts"
    cp -a "$CONFIG_SRC/waybar/scripts/." "$CONFIG_DST/waybar/scripts/"
    chmod +x "$CONFIG_DST/waybar/scripts/"*.sh 2>/dev/null || true
    log "  ✓ waybar/scripts/ (chmod +x)"
fi

# Picom
deploy "$CONFIG_SRC/picom/picom.conf" "$CONFIG_DST/picom/picom.conf"

# Rofi
deploy "$CONFIG_SRC/rofi/config.rasi" "$CONFIG_DST/rofi/config.rasi"

# Ranger
mkdir -p "$CONFIG_DST/ranger"
for f in rc.conf rifle.conf commands.py scope.sh; do
    [[ -f "$CONFIG_SRC/ranger/$f" ]] && deploy "$CONFIG_SRC/ranger/$f" "$CONFIG_DST/ranger/$f"
done
if [[ -d "$CONFIG_SRC/ranger/colorschemes" ]]; then
    mkdir -p "$CONFIG_DST/ranger/colorschemes"
    cp -a "$CONFIG_SRC/ranger/colorschemes/." "$CONFIG_DST/ranger/colorschemes/"
    log "  ✓ ranger/colorschemes/"
fi
chmod +x "$CONFIG_DST/ranger/scope.sh" 2>/dev/null || true

# Flameshot — исправляем хардкод /home/amar/
mkdir -p "$CONFIG_DST/flameshot"
[[ -f "$CONFIG_SRC/flameshot/flameshot.ini" ]] && \
    sed "s|/home/amar/|$HOME/|g" \
        "$CONFIG_SRC/flameshot/flameshot.ini" > "$CONFIG_DST/flameshot/flameshot.ini" && \
    log "  ✓ flameshot.ini (путь: $HOME)"

# Nitrogen — исправляем хардкод /home/amar/
mkdir -p "$CONFIG_DST/nitrogen"
for f in bg-saved.cfg nitrogen.cfg; do
    [[ -f "$CONFIG_SRC/nitrogen/$f" ]] && \
        sed "s|/home/amar/|$HOME/|g" \
            "$CONFIG_SRC/nitrogen/$f" > "$CONFIG_DST/nitrogen/$f" && \
        log "  ✓ nitrogen/$f (путь: $HOME)"
done

# Polybar
[[ -f "$CONFIG_SRC/polybar/config.ini" ]] && \
    deploy "$CONFIG_SRC/polybar/config.ini" "$CONFIG_DST/polybar/config.ini"
if [[ -f "$CONFIG_SRC/polybar/launch.sh" ]]; then
    deploy "$CONFIG_SRC/polybar/launch.sh" "$CONFIG_DST/polybar/launch.sh"
    chmod +x "$CONFIG_DST/polybar/launch.sh"
fi

# .xinitrc
if [[ -f "$REPO_DIR/319/.xinitrc" ]]; then
    [[ -f ~/.xinitrc ]] && cp ~/.xinitrc ~/.xinitrc.bak.$(date '+%Y%m%d_%H%M%S')
    cp "$REPO_DIR/319/.xinitrc" ~/.xinitrc
    log "  ✓ ~/.xinitrc"
fi

# =============================================================================
step "8/8  .bashrc и системные директории"

if [[ -f "$REPO_DIR/319/bashrc_amar319" ]]; then
    [[ -f ~/.bashrc ]] && cp ~/.bashrc ~/.bashrc.bak.$(date '+%Y%m%d_%H%M%S')
    cp "$REPO_DIR/319/bashrc_amar319" ~/.bashrc
    log "~/.bashrc установлен"
fi

[[ ! -f ~/.bashrc.local ]] && cat > ~/.bashrc.local << 'EOF'
# ~/.bashrc.local — машино-специфичные настройки (не в git)
export SHOW_SYSTEM_INFO=true
EOF
log "~/.bashrc.local создан"

mkdir -p ~/Pictures/Wallpapers ~/Screenshots ~/Amar73
log "Директории ~/Pictures/Wallpapers ~/Screenshots ~/Amar73 готовы"

# =============================================================================
echo
echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${GREEN}  Готово! Следующие шаги:${RESET}"
echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo
echo "  ${CYAN}exec bash${RESET}                                   # применить .bashrc"
echo "  ${CYAN}sudo ./319/install_software_wayland.sh --dry-run${RESET}  # план"
echo "  ${CYAN}sudo ./319/install_software_wayland.sh${RESET}            # установка"
echo "  ${CYAN}Hyprland${RESET}                                    # запустить WM"
echo
git remote -v
echo
