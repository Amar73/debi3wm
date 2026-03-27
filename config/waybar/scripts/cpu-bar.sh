#!/bin/bash
# ~/.config/waybar/scripts/cpu-bar.sh
load=$(awk '{print int($1*10)}' /proc/loadavg)
cores=$(nproc)
pct=$((load * 100 / (cores * 10)))
pct=$((pct > 100 ? 100 : pct))

# Блочный прогресс-бар из Unicode-символов
blocks=("░" "▏" "▎" "▍" "▌" "▋" "▊" "▉" "█")
bar=""
for i in $(seq 1 10); do
    threshold=$((i * 10))
    if [[ $pct -ge $threshold ]]; then bar+="█"
    else bar+="░"; fi
done

if   [[ $pct -lt 50 ]]; then cls="normal"
elif [[ $pct -lt 80 ]]; then cls="warning"
else cls="critical"; fi

echo "{\"text\":\" $bar $pct%\",\"tooltip\":\"CPU: $pct%\\nCores: $cores\",\"class\":\"$cls\"}"
