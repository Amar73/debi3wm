#!/bin/bash
# ~/.config/waybar/scripts/updates.sh
count=$(checkupdates 2>/dev/null | wc -l)

if [[ $count -eq 0 ]]; then
    echo '{"text": "0", "tooltip": "Система актуальна", "class": "updated"}'
elif [[ $count -lt 10 ]]; then
    echo "{\"text\": \"$count\", \"tooltip\": \"$count обновлений\", \"class\": \"pending\"}"
else
    echo "{\"text\": \"$count\", \"tooltip\": \"$count обновлений!\", \"class\": \"critical\"}"
fi
