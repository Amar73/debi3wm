#
# ~/.bashrc

HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=5000
HISTFILESIZE=5000
export HISTTIMEFORMAT="%h %d %H:%M:%S "
PROMPT_COMMAND='history -a'
shopt -s checkwinsize
mkcd () {
  mkdir -p "$1" && cd "$1"
}
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
export PATH="~/bin:$PATH"
export PATH="~/.local/bin:$PATH"
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/go/bin:$PATH"
export VISUAL=vim;
export EDITOR=vim;
PS1='\[\e[96m\]\t\[\e[0m\] \[\e[38;5;208m\]\u\[\e[0m\]@\[\e[38;5;208m\]\h\[\e[93m\]\w\n\[\e[0m\]$? \[\e[93m\]\$\[\e[0m\]'
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
