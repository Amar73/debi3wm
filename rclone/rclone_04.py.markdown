# Описание скрипта rclone_backup_idream_single.py

Этот Python-скрипт выполняет резервное копирование данных из одной директории Ceph FS (`/ceph/data/exp/idream/`) на локальную файловую систему (`/backup/main/ceph/data/exp/idream/`) с использованием `rclone`. Он требует обязательный файл исключений, выполняет однопоточную обработку (хотя использует `ThreadPoolExecutor` для унификации), и включает логирование, блокировку, проверку Ceph и валидацию.

## 1. Назначение скрипта
- **Основная цель**: Синхронизация данных из `/ceph/data/exp/idream/` в `/backup/main/ceph/data/exp/idream/`.
- **Функциональность**:
  - Выполнение `rclone sync` с обязательным файлом исключений.
  - Перемещение удалённых файлов в `/backup/deleted/YYYY-MM-DD`.
  - Очистка данных старше 30 дней из `/backup/deleted`.
  - Проверка монтирования Ceph FS, прав доступа и состояния кластера.
  - Частичная валидация (сравнение количества файлов).
  - Логирование в `/var/log/backup/backup_YYYY-MM-DD_HH-MM.log`.
  - Блокировка для предотвращения одновременного запуска.

## 2. Конфигурация скрипта
- **BACKUP_USER**: `backup_user`.
- **LOGDIR**: `/var/log/backup`.
- **LOCKFILE**: `/var/lock/backup.lock`.
- **EXCLUDE_FILE**: `/usr/local/bin/scripts/exclude-file.txt` (обязательный).
- **DELETE_BACKUP**: `/backup/deleted`.
- **MAIN_BACKUP**: `/backup/main`.
- **SOURCEDIRS**: Список с одной директорией (`/ceph/data/exp/idream/`).
- **RCLONE_TRANSFERS**: 30.
- **RCLONE_CHECKERS**: 8.
- **RCLONE_RETRIES**: 5.

## 3. Инициализация и логирование
- **Лог-файл**: `/var/log/backup/backup_YYYY-MM-DD_HH-MM.log`.
- **Директория логов**: Создаётся, если отсутствует.
- **Ротация логов**:
  - Удаление логов старше 30 дней.
  - Проверка на превышение 100 файлов.
- **Формат логов**: Как в первом скрипте, с уровнями INFO, WARNING, ERROR, DEBUG.

## 4. Проверка конфигурации rclone
- **RCLONE_CONFIG**: Аналогично первому скрипту, с обработкой отсутствия файла.

## 5. Проверка файла исключений
- **EXCLUDE_FILE**:
  - Проверяется существование и читаемость.
  - Если файл отсутствует или не читаем, скрипт завершается.
  - Если пустой, выдаётся предупреждение.
  - Содержимое логируется.
- **Повторная проверка**: В `backup_dir` для согласованности.

## 6. Механизм блокировки
- **LOCKFILE**: `fcntl.flock`, как в первом скрипте.

## 7. Проверка Ceph FS
- **Функция `check_ceph_access`**: Аналогична первому скрипту, с проверкой `/ceph/data/exp/idream/`.

## 8. Очистка устаревших данных
- **Функция `cleanup_old_backups`**: Как в первом скрипте.

## 9. Резервное копирование директорий
- **Функция `backup_dir`**:
  - Обрабатывает `/ceph/data/exp/idream/`.
  - Требует файл исключений.
  - Параметры `rclone sync` включают `--exclude-from`.
- **Валидация**: Как в первом скрипте.

## 10. Параллельная обработка
- **Функция `perform_backup`**:
  - Использует `ThreadPoolExecutor`, хотя для одной директории это избыточно (для унификации с другими скриптами).
  - Выполняет `backup_dir` для `/ceph/data/exp/idream/`.

## 11. Основной поток выполнения
- **Функция `main`**: Аналогична первому скрипту, но требует файл исключений.

## 12. Обработка ошибок
- **Критичные ошибки**: Отсутствие файла исключений завершает скрипт.
- **Остальное**: Как в первом скрипте.

## 13. Логирование и отладка
- Аналогично первому скрипту.

## 14. Зависимости
- Те же, что в первом скрипте, плюс обязательный файл исключений.

## 15. Ограничения и особенности
- **Одна директория**: Ограничивает параллелизм.
- **Обязательный файл исключений**: Требует наличия `/usr/local/bin/scripts/exclude-file.txt`.
- **Валидация**: Только количество файлов.

## 16. Пример работы
1. Создайте `/usr/local/bin/scripts/exclude-file.txt`.
2. Запуск: `python3 /usr/local/bin/rclone_backup_idream_single.py`.
3. Лог: `/var/log/backup/backup_2025-05-23_17-46.log`.
4. Проверяется Ceph, синхронизируется `/ceph/data/exp/idream/`, валидируется.

## 17. Рекомендации по использованию
- **Файл исключений** (обязателен):
  ```bash
  echo -e "subdir1/**\nsubdir2/**" > /usr/local/bin/scripts/exclude-file.txt
  chmod 644 /usr/local/bin/scripts/exclude-file.txt
  ```
- **Права**:
  ```bash
  chmod 755 /usr/local/bin/rclone_backup_idream_single.py
  ```
- **Тестирование**:
  ```bash
  python3 /usr/local/bin/rclone_backup_idream_single.py
  ```
- **Остальное**: Как в первом скрипте.