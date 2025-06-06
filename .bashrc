#
# ~/.bashrc
#

# ====== История команд ======
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=5000
HISTFILESIZE=5000
export HISTTIMEFORMAT="%h %d %H:%M:%S "
PROMPT_COMMAND='history -a'
shopt -s checkwinsize

# ====== Полезные функции ======
mkcd () {
  mkdir -p "$1" && cd "$1"
}

# ====== Алиасы ======
alias .1="cd .."
alias .2="cd ../.."
alias .3="cd ../../.."
alias .4="cd ../../../.."

alias ld='eza -ll --icons --group-directories-first'
alias la='eza -al --header --icons --group-directories-first'

alias df='df -h'
alias free='free -h'
alias reload='source ~/.bashrc'

alias g.="cd /home/amar/.config/"
alias gd="cd /home/amar/Downloads/"
alias gG="cd /home/amar/Git/"
alias gA="cd /home/amar/Amar73/debi3wm/"
alias gdwm="cd /home/amar/.config/suckless/dwm/"
alias gdm="cd /home/amar/.config/suckless/dmenu/"
alias gsl="cd /home/amar/.config/suckless/slstatus/"
alias gy='cd /home/amar/Yandex.Disk'

alias gpull='git pull origin main'
alias gs='git status'
alias ga='git add .'
alias gc='git commit -m'
alias gpush='git push origin main'

alias v="vim"
alias sv="sudo vim"

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias search='pacman -Ss'
alias update='sudo pacman -Syu'
alias install='sudo pacman -S'

# ====== PATH ======
export PATH="~/bin:$PATH"
export PATH="~/.local/bin:$PATH"
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/go/bin:$PATH"

# ====== Редактор по умолчанию ======
export VISUAL=vim
export EDITOR=vim

# ====== Цветной PS1 ======
PS1='\[\e[96m\]\t\[\e[0m\] \[\e[38;5;208m\]\u\[\e[0m\]@\[\e[38;5;208m\]\h\[\e[93m\]\w\n\[\e[0m\]$? \[\e[93m\]\$\[\e[0m\]'

# ====== Автозапуск ssh-agent ======
if [ -z "$SSH_AUTH_SOCK" ]; then
   eval "$(ssh-agent -s)"
   ssh-add ~/.ssh/id_ed25519
fi

# ====== SSH Aliases ======
alias a03='ssh arch03'
alias a04='ssh arch04'
alias a05='ssh arch05'
alias m01='ssh archminio01'
alias m02='ssh archminio02'

alias a224='ssh amar224'

# ====== Универсальные функции для копирования ======

# Скачивание с любого сервера
scpto() {
    if [ $# -ne 3 ]; then
        echo "Usage: scpto <server> <remote_path> <local_path>"
        echo "Example: scpto arch05 /root/file.txt ~/Downloads/"
        return 1
    fi

    local server="$1"
    local remote_path="$2"
    local local_path="$3"

    scp "${server}:${remote_path}" "${local_path}"
}

# Загрузка на любой сервер
putto() {
    if [ $# -ne 3 ]; then
        echo "Usage: putto <server> <local_path> <remote_path>"
        echo "Example: putto archminio01 ~/file.txt /tmp/"
        return 1
    fi

    local server="$1"
    local local_path="$2"
    local remote_path="$3"

    scp "${local_path}" "${server}:${remote_path}"
}
#####Подключаться к серверам:
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

