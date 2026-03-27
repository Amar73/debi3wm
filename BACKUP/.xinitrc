exec flameshot &
exec nitrogen --restore &
exec dunst -config ~/.config/dunst/dunstrc &
exec yandex-disk start &
exec numlockx &
exec sxhkd -c ~/.config/sxhkd/sxhkdrc &
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
exec slstatus &
exec xrdb &
# Включаем DPMS
xset +dpms
# Устанавливаем время до перехода в режим ожидания
xset dpms 600 600 600  # 10 минут до выключения экрана

# Запуск автоблокировки: блокируем через 20 мин бездействия
exec xautolock -time 20 -locker "lock" &
exec dwm
