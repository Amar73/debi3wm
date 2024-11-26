#!/bin/sh

# run flameshot daemon
exec flameshot &

#for wallpaper
#if [[ $(pidof nitrogen) ]]; then
# echo "nitrogen is running"
#else
# echo "starting"
exec nitrogen --restore --set-scaled &
#exec nitrogen --restore &
#fi

#feh --bg-fill ~/Pictures/Wallpapers/wallpaper.jpg &

#notification daemon
exec dunst -config ~/.config/dunst/dunstrc &

exec birdtray &

numlockx &
sxhkd -c ~/.config/sxhkd/sxhkdrc &
exec /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
exec slstatus &
exec xautolock -time 10 -locker slock &
exec dwm
XDG_CONFIG_HOME=~/.config
export XDG_CONFIG_HOME

while type dwm >/dev/null; do dwm && continue || break; done
