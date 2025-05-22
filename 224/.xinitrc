#!/bin/sh

#exec flameshot &
#exec nitrogen --restore &
#exec dunst -config ~/.config/dunst/dunstrc &
#exec birdtray &
#exec yandex-disk start &
#numlockx &
#sxhkd -c ~/.config/sxhkd/sxhkdrc &
#exec /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
#exec slstatus &
#exec xautolock -time 20 -locker slock &
#exec dwm
#XDG_CONFIG_HOME=~/.config
#export XDG_CONFIG_HOME

XDG_CONFIG_HOME=~/.config
export XDG_CONFIG_HOME

# Фоновые службы
flameshot &
nitrogen --restore &
dunst -config ~/.config/dunst/dunstrc &
birdtray &
yandex-disk start &
numlockx &
sxhkd -c ~/.config/sxhkd/sxhkdrc &
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
slstatus &
xautolock -time 20 -locker slock &

# Запуск программ с задержками
#(sleep 2 && alacritty) &
#(sleep 3 && thunderbird) &
#(sleep 4 && yandex-browser) &
#(sleep 5 && code) &
#(sleep 6 && kate) &
#(sleep 7 && kate) &
#(sleep 8 && telegram-desktop) &
#(sleep 9 && FBReader) &
#sleep 1 && alacritty --class 'Alacritty,Alacritty-mon1' &
#sleep 1 && alacritty --class 'Alacritty,Alacritty-mon2' &
#sleep 1 && alacritty --class 'Alacritty,Alacritty-mon3' &
#~/.config/autostart/alacritty_autostart.sh &
exec dwm
