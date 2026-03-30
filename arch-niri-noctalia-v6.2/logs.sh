#!/usr/bin/env bash
set -Eeuo pipefail

echo "===== greetd ====="
journalctl -b -u greetd -n 80 --no-pager || true
echo

echo "===== noctalia.service ====="
journalctl --user -b -u noctalia.service -n 80 --no-pager || true
echo

echo "===== swayidle.service ====="
journalctl --user -b -u swayidle.service -n 80 --no-pager || true
echo

echo "===== cliphist.service ====="
journalctl --user -b -u cliphist.service -n 80 --no-pager || true
echo

echo "===== failed units ====="
systemctl --failed || true
systemctl --user --failed || true
