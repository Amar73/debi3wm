# ~/.bashrc - Подробная конфигурация для продвинутых пользователей

# =================== Общие настройки ===================

# Выход, если оболочка неинтерактивная (например, при запуске из скриптов)
[[ $- != *i* ]] && return

# =================== История команд ===================
# Настройки для более удобной и мощной истории команд
HISTCONTROL=ignoreboth:erasedups  # Пропуск дубликатов и команд, начинающихся с пробела
HISTSIZE=10000                    # Максимальное число команд в истории в оперативной памяти
HISTFILESIZE=20000                # Максимальное число команд в .bash_history
HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "  # Формат времени для истории
PROMPT_COMMAND='history -a'  # Сохраняем историю

# Расширенные настройки bash
shopt -s histappend      # Не перезаписывать, а добавлять в .bash_history
shopt -s checkwinsize    # Проверка размера терминала после каждой команды
shopt -s cdspell         # Исправление ошибок в названии директорий при cd
shopt -s dirspell        # Исправление ошибок в автодополнении директорий
shopt -s autocd          # cd по имени директории без ввода cd

# =================== Полезные функции ===================

# Создание директории и переход в неё
mkcd() {
    mkdir -p "$1" && cd "$1" || return
}

# Извлечение архивов разных форматов
extract() {
    if [ -f "$1" ]; then
        case $1 in
            *.tar.bz2)   tar xvjf "$1"     ;;
            *.tar.gz)    tar xvzf "$1"     ;;
            *.bz2)       bunzip2 "$1"      ;;
            *.rar)       unrar x "$1"      ;;
            *.gz)        gunzip "$1"       ;;
            *.tar)       tar xvf "$1"      ;;
            *.tbz2)      tar xvjf "$1"     ;;
            *.tgz)       tar xvzf "$1"     ;;
            *.zip)       unzip "$1"        ;;
            *.Z)         uncompress "$1"   ;;
            *.7z)        7z x "$1"         ;;
            *.xz)        unxz "$1"         ;;
            *.exe)       cabextract "$1"   ;;
            *)           echo "extract: '$1' - неизвестный архив" ;;
        esac
    else
        echo "$1 - файл не существует"
    fi
}

# Поиск по истории
hgrep() { history | grep "$@"; }

# Быстрый поиск файлов
ff() { find . -name "*$1*" 2>/dev/null; }

# =================== Навигационные алиасы ===================
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ~='cd ~'
alias -- -='cd -'

# =================== Цветной ls (через eza, если есть) ===================
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -l --icons --group-directories-first --header'
    alias la='eza -la --icons --group-directories-first --header'
    alias lt='eza --tree --level=2 --icons'
    alias lta='eza --tree --level=2 --icons -a'
else
    alias ls='ls --color=auto --group-directories-first'
    alias ll='ls -lh --color=auto --group-directories-first'
    alias la='ls -lah --color=auto --group-directories-first'
fi

# =================== Безопасные команды ===================
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'

# =================== Мониторинг ===================
alias df='df -h'
alias du='du -ch'
alias free='free -h'
alias ps='ps auxf'
alias psg='ps aux | grep -v grep | grep -i -e VSZ -e'
alias myip='curl -s ifconfig.me'
alias ports='netstat -tulanp'

# =================== Git-алиасы ===================
alias gs='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit -m'
alias gca='git commit -am'
alias gp='git push'
alias gpf='git push --force-with-lease -u origin $(git symbolic-ref --short HEAD)'
alias gl='git pull'
alias glo='git log --oneline --graph --decorate'
alias glog='git log --graph --pretty=format:"%Cred%h%Creset - %Cgreen(%cr)%Creset %s%C(yellow)%d%Creset %C(bold blue)<%an>%Creset" --abbrev-commit'
alias gd='git diff'
alias gb='git branch'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gm='git merge'
alias gr='git reset'
alias grh='git reset --hard'

# =================== Быстрая навигация ===================
alias cdconfig='cd ~/.config'
alias cddown='cd ~/Downloads'
alias cddoc='cd ~/Documents'
alias cdgit='cd ~/Git'
alias cddwm='cd ~/.config/suckless/dwm'
alias cddmenu='cd ~/.config/suckless/dmenu'
alias cdslstatus='cd ~/.config/suckless/slstatus'
alias cddeb='cd ~/Amar73/debi3wm'
alias cdrclone='cd ~/Amar73/rclone'

# =================== Пакетные менеджеры ===================
# Arch Linux
if command -v pacman >/dev/null 2>&1; then
    alias search='pacman -Ss'
    alias install='sudo pacman -S'
    alias update='sudo pacman -Syu'
    alias remove='sudo pacman -R'
    alias autoremove='sudo pacman -Rns $(pacman -Qtdq)'
    alias installed='pacman -Q'
    alias yaysearch='yay -Ss'
    alias yayinstall='yay -S'
    alias yayupdate='yay -Syu'
    alias yayshow='yay -Qi'
    alias yayremove='yay -Rns'
    alias aurorphans='yay -Yc'  # удаление осиротевших AUR пакетов
# NixOS
elif command -v nixos-rebuild >/dev/null 2>&1; then
    alias rebuild='sudo nixos-rebuild switch'
    alias rebuild-test='sudo nixos-rebuild test'
    alias upgrade='sudo nixos-rebuild switch --upgrade'
    alias search='nix-env -qaP'
    alias nix-search='nix search'
# Nix
elif command -v nix-env >/dev/null 2>&1; then
    alias nix-search='nix-env -qaP'
    alias nix-install='nix-env -i'
    alias nix-remove='nix-env -e'
    alias nix-upgrade='nix-env -u'
fi

# =================== Предпочтительные редакторы ===================
alias v='vim'
alias sv='sudo vim'
alias e='$EDITOR'
alias se='sudo $EDITOR'

# =================== Расширение PATH ===================
add_to_path() {
    if [[ -d "$1" && ":$PATH:" != *":$1:"* ]]; then
        PATH="$1:$PATH"
    fi
}

add_to_path "$HOME/bin"
add_to_path "$HOME/.local/bin"
add_to_path "/usr/local/bin"
add_to_path "/usr/local/go/bin"

# Flutter SDK
if [[ -d "/usr/lib/flutter" ]]; then
    add_to_path "/usr/lib/flutter/bin"
    export CHROME_EXECUTABLE=/usr/bin/chromium
fi

# Android SDK
if [[ -d "$HOME/Android/Sdk" ]]; then
    export ANDROID_HOME="$HOME/Android/Sdk"
    export ANDROID_SDK_ROOT="$ANDROID_HOME"
    add_to_path "$ANDROID_HOME/cmdline-tools/latest/bin"
    add_to_path "$ANDROID_HOME/platform-tools"
fi

# =================== Переменные окружения ===================
export VISUAL=vim
export EDITOR=vim
export PAGER=less
export BROWSER=firefox

# =================== Цветовая схема для приглашения ===================
# Цвета — для встраивания в echo из функций
COLOR_GREEN=$'\033[0;32m'
COLOR_RED=$'\033[0;31m'
COLOR_YELLOW=$'\033[1;33m'
COLOR_RESET=$'\033[0m'
# Цвета — только для PS1 (обязательно экранируем!)
PS_COLOR_GREEN='\[\033[0;32m\]'
PS_COLOR_RED='\[\033[0;31m\]'
PS_COLOR_YELLOW='\[\033[1;33m\]'
PS_COLOR_PURPLE='\[\033[0;35m\]'
PS_COLOR_CYAN='\[\033[0;36m\]'
PS_COLOR_BLUE='\[\033[0;34m\]'
PS_COLOR_RESET='\[\033[0m\]'
# Цвета
PS_CYAN='\[\033[0;36m\]'
PS_GREEN='\[\033[0;32m\]'
PS_BLUE='\[\033[0;34m\]'
PS_YELLOW='\[\033[1;33m\]'
PS_RESET='\[\033[0m\]'
# =================== Git статус для PS1 ===================
git_status() {
    local branch
    if branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); then
        local changes=$(git status --porcelain 2>/dev/null)
        if [[ -n $changes ]]; then
            echo -n " ${COLOR_YELLOW}(${branch}*)${COLOR_RESET}"
        else
            echo -n " ${COLOR_GREEN}(${branch})${COLOR_RESET}"
        fi
    fi
}

# Код возврата последней команды для PS1
last_command_status() {
    local status=$?
    if [[ $status -eq 0 ]]; then
        echo -n "${COLOR_GREEN}✓${COLOR_RESET}"
    else
        echo -n "${COLOR_RED}✗ $status${COLOR_RESET}"
    fi
}

# Основной PS1: Время, пользователь, хост, путь, git, код возврата
# PS1="${PS_COLOR_CYAN}\t${PS_COLOR_RESET} ${PS_COLOR_PURPLE}\u${PS_COLOR_RESET}@${PS_COLOR_PURPLE}\h${PS_COLOR_RESET}:${PS_COLOR_BLUE}\w${PS_COLOR_RESET}\$(git_status)\n\$(last_command_status) ${PS_COLOR_YELLOW}\\\$${PS_COLOR_RESET} "
#PS1='\u@\h:\w\$ '
# Лаконичный, информативный PS1
PS1="${PS_CYAN}\t${PS_RESET} ${PS_GREEN}\u${PS_RESET}@${PS_BLUE}\h${PS_RESET}:${PS_YELLOW}\w${PS_RESET}\$ "
# =================== SSH Agent ===================
if [[ -z "$SSH_AUTH_SOCK" && -z "$SSH_AGENT_PID" ]]; then
    eval "$(ssh-agent -s)" >/dev/null 2>&1
    for key in ~/.ssh/id_rsa ~/.ssh/id_ed25519; do
        [[ -f "$key" ]] && ssh-add "$key" >/dev/null 2>&1
    done
fi

# =================== SSH Алиасы ===================
alias a03='ssh arch03'
alias a04='ssh arch04'
alias a05='ssh arch05'
alias m01='ssh archminio01'
alias m02='ssh archminio02'

# =================== Передача файлов по SSH ===================
download_from_server() {
    if [[ $# -ne 3 ]]; then
        echo "Использование: download_from_server <сервер> <удаленный_путь> <локальный_путь>"
        return 1
    fi
    scp "$1:$2" "$3" && echo "✓ Файл успешно скачан" || echo "✗ Ошибка при скачивании файла"
}

upload_to_server() {
    if [[ $# -ne 3 ]]; then
        echo "Использование: upload_to_server <сервер> <локальный_путь> <удаленный_путь>"
        return 1
    fi
    if [[ ! -f "$2" ]]; then
        echo "✗ Локальный файл $2 не существует"
        return 1
    fi
    scp "$2" "$1:$3" && echo "✓ Файл успешно загружен" || echo "✗ Ошибка при загрузке файла"
}

alias scpto='download_from_server'
alias putto='upload_to_server'

####Подключаться к серверам:
# a03
# m01
#
#####Скачивать файлы:
# scpto arch05 /root/file.txt ~/Downloads/
# scpto archminio01 /home/amar/data.txt ~/temp/
#
#####Отправлять файлы:
# putto arch05 ~/report.pdf /home/amar/
# putto archminio02 ~/backup.tar.gz /var/backups/
#

# =================== Git-проекты ===================
gitinit() {
    local repo_name="${1:-$(basename "$PWD")}"
    git init
    echo "# $repo_name" > README.md
    echo -e ".DS_Store\n*.log\n*.tmp\n*~" > .gitignore
    git add .
    git commit -m "Initial commit"
    echo "✓ Git репозиторий $repo_name инициализирован"
}

project() {
    if [[ -z "$1" ]]; then
        ls ~/Git/ 2>/dev/null || echo "~/Git/ не найдена"
        return 1
    fi
    local p="$HOME/Git/$1"
    if [[ -d "$p" ]]; then
        cd "$p" || return 1
        echo "Перешли в проект: $1"
        [[ -f README.md ]] && head -5 README.md
    else
        echo "Проект $1 не найден"
        return 1
    fi
}

# =================== Дополнительные конфиги ===================
[[ -f ~/.bashrc.local ]] && source ~/.bashrc.local
[[ -f ~/.bashrc.$(hostname) ]] && source ~/.bashrc.$(hostname)

# =================== Информация о системе ===================
if [[ "${SHOW_SYSTEM_INFO:-false}" == "true" ]]; then
    echo -e "${CYAN}=== Информация о системе ===${RESET}"
    echo -e "${GREEN}Система:${RESET} $(uname -sr)"
    echo -e "${GREEN}Время работы:${RESET} $(uptime -p 2>/dev/null || uptime)"
    echo -e "${GREEN}Загрузка:${RESET} $(cut -d' ' -f1-3 < /proc/loadavg)"
    echo -e "${GREEN}Память:${RESET} $(free -h | awk '/Mem:/ {print $3"/"$2}')"
    echo
fi

# =================== systemd утилиты ===================
if command -v systemctl >/dev/null 2>&1; then
    alias sc='systemctl'
    alias scu='systemctl --user'
    alias scr='sudo systemctl reload'
    alias scs='systemctl status'
    alias scus='systemctl --user status'

    logs() {
        [[ -z "$1" ]] && echo "Использование: logs <служба> [user]" && return 1
        [[ "$2" == "user" || "$2" == "u" ]] && journalctl --user -xeu "$1" || sudo journalctl -xeu "$1"
    }

    restart-dwm-services() {
        local services=(flameshot nitrogen dunst sxhkd slstatus)
        for s in "${services[@]}"; do
            echo "Перезапуск $s..."
            systemctl --user restart "$s" 2>/dev/null || echo "⚠ Не удалось перезапустить $s"
        done
        echo "✓ Перезапуск служб DWM завершен"
    }
fi

# =================== Отладка ===================
[[ "${BASH_DEBUG:-false}" == "true" ]] && echo "✓ .bashrc загружен полностью"

# =================== Перезагрузка bashrc ===================
# Функция reload — вручную перечитать .bashrc и сбросить функции
reload() {
    echo "🔄 Перезагрузка .bashrc..."
    unset -f git_status last_command_status reload 2>/dev/null
    source ~/.bashrc && echo "✅ .bashrc успешно перезагружен"
}
