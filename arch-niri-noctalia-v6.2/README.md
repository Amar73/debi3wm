# Arch Linux + Niri + Noctalia v6.2

Bootstrap-репозиторий для чистого Arch Linux.

Добавлено в v6.2:
- интеграция пользовательского `~/.bashrc`
- интеграция пользовательского `~/.ssh/config`
- безопасный деплой с бэкапом старых файлов
- отдельная цель `make dots-local`
- smoke-check для bash и ssh config
- кастомный XKB keymap:
  - Alt_L -> English
  - Alt_R -> Russian

## Установка

```bash
git clone <YOUR_REPO_URL> arch-niri-noctalia
cd arch-niri-noctalia
chmod +x *.sh
make install
sudo reboot
```

## Развёртывание только dotfiles из репозитория

```bash
make dots-local
```

## Проверка

```bash
make check
```

## Логи

```bash
make logs
```

## Резервная копия конфигов

```bash
make backup
```

## Синхронизация файлов репозитория в систему

```bash
make sync
```
