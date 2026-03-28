#!/bin/bash
layout=$(hyprctl devices -j | python3 -c "
import sys, json
devices = json.load(sys.stdin)
keyboards = devices.get('keyboards', [])
for kb in keyboards:
    if kb.get('main', False):
        print(kb['active_keymap'])
        break
" 2>/dev/null)

case "$layout" in
    *"Russian"*) echo '{"text":"RU","class":"ru"}' ;;
    *)           echo '{"text":"US","class":"us"}' ;;
esac
