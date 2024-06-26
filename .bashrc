# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
#[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
#alias ll='ls -lA'
#alias la='ls -A'
#alias l='ls -CF'
alias .1="cd .."
alias .2="cd ../.."
alias .3="cd ../../.."
alias .4="cd ../../../.."
alias install='sudo nala install -y'
alias update='sudo nala update'
alias upgrade='sudo nala upgrade -y'
alias uplist='nala list --upgradable'
alias nls='nala search'
alias remove='sudo nala autoremove -y'
alias ld='exa -ll --icons --group-directories-first'
alias la='exa -al --header --icons --group-directories-first'
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
alias v="vim"
alias sv="sudo vim"
# Git aliases
alias ga="git add ."
alias gp="git push"
alias gs="git commit -m 'save'"
#alias gs="git status"
alias gc="git clone"
alias tr="tree"

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
#export PATH="$PATH:/opt/nvim-linux64/bin"
export PATH="~/bin:$PATH"
export PATH="~/.local/bin:$PATH"
export PATH="/usr/local/go/bin:$PATH"
export VISUAL=vim;
export EDITOR=vim;

# Colour codes
#RED="\\[\\e[1;31m\\]"
#GREEN="\\[\\e[1;32m\\]"
#YELLOW="\\[\\e[1;33m\\]"
#BLUE="\\[\\e[1;34m\\]"
#MAGENTA="\\[\\e[1;35m\\]"
#CYAN="\\[\\e[1;36m\\]"
#WHITE="\\[\\e[1;37m\\]"
#ENDC="\\[\\e[0m\\]"

# Set a two-line prompt. If accessing via ssh include 'ssh-session' message.
#if [[ -n "$SSH_CLIENT" ]]; then ssh_message="-ssh_session"; fi
#PS1="${MAGENTA}\t ${GREEN}\u ${WHITE}at ${YELLOW}\h${RED}${ssh_message} ${WHITE}in ${BLUE}\w \n${CYAN}\$${ENDC} "

PS1='\[\e[96m\]\t\[\e[0m\] \[\e[38;5;208m\]\u\[\e[0m\]@\[\e[38;5;208m\]\h\[\e[93m\]\w\n\[\e[0m\]$? \[\e[93m\]\$\[\e[0m\]'
