#!/usr/local/bin/bash

# Конфигурация
LOGDIR="/var/log/rclone-backup"
LOCKFILE="/var/lock/backup.lock"
RCLONE_CONFIG="/root/.config/rclone/rclone.conf"
DELETE_BACKUP="minio:backup-deleted"
RETENTION_DAYS=30
RCLONE_TRANSFERS=${RCLONE_TRANSFERS:-50}
RCLONE_CHECKERS=${RCLONE_CHECKERS:-50}
RCLONE_RETRIES=${RCLONE_RETRIES:-10}
RCLONE_PARALLEL=${RCLONE_PARALLEL:-4}
RCLONE_FLAGS=(
    "--progress"
    "--check-first"
    "--transfers=$RCLONE_TRANSFERS"
    "--checkers=$RCLONE_CHECKERS"
    "--stats=60s"
    "--fast-list"
    "--retries=$RCLONE_RETRIES"
    "--retries-sleep=10s"
    "--update"
    "--s3-upload-concurrency=20"
    "--checksum"
    "--s3-force-path-style"
    "--no-check-certificate"
    "--log-file=$LOGFILE"
    "--log-level=INFO"
    "--backup-dir=$DELETE_BACKUP/$(date +%F)"
)

# Список бакетов для бэкапа
buckets=(
    "test:nbgi-db-public"
    "test:nbgi-db-dev"
    "test:nbgi-db-private"
    "test:nbgi-tps"
    "test:nbgi-db-test"
    "test:db-arb-silva"
    "test:db-metagenomics"
    "test:3dparty-db-test"
    "nbgi-init-sequencing:nbgi-private-init-sequencing"
    "nbgi-init-sequencing:nbgi-public-init-sequencing"
    "nbgi-init-gd:nbgi-private-init-gd"
    "nbgi-init-gd:nbgi-public-init-gd"
    "registry:docker-registry"
    "backup:backup-psql"
    "backup:backup-vm"
    "test:db-meta"
    "test:db-pmc"
    "test:db-pdb"
    "test:db-ena"
    "test:db-ebi"
    "test:3rdparty-db-prod"
    "test:db-card-blast"
    "registry:pypi-registry"
    "default:k8s-logs"
)

# Инициализация логирования
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M')
LOGFILE="$LOGDIR/backup_$TIMESTAMP.log"
mkdir -p "$LOGDIR" || { echo "Не удалось создать $LOGDIR" >&2; exit 1; }

# Ротация логов
find "$LOGDIR" -type f -name 'backup_*' -mtime +30 -delete
if [[ $(find "$LOGDIR" -type f | wc -l) -gt 100 ]]; then
    log ERROR "Слишком много лог-файлов в $LOGDIR"
    exit 1
fi

# Проверка конфигурации rclone
if [[ ! -f "$RCLONE_CONFIG" ]]; then
    log ERROR "Конфиг rclone не найден: $RCLONE_CONFIG"
    exit 1
fi
if [[ "$(stat -f %Sp "$RCLONE_CONFIG")" != "-rw-------" ]]; then
    log WARNING "Небезопасные права доступа к $RCLONE_CONFIG. Рекомендуется: chmod 600 $RCLONE_CONFIG"
fi

# Блокировка с использованием flock
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    log ERROR "Скрипт уже запущен. Выход."
    exit 1
fi
trap 'flock -u 200; rm -f "$LOCKFILE"; exit $?' INT TERM EXIT

# Функция логирования
log() {
    local level=${1:-INFO}
    local msg="${2}"
    echo "$(date +'%Y-%m-%d %T') [$level] $msg" | tee -a "$LOGFILE"
}

# Функция повторных попыток
retry_command() {
    local cmd="$1"
    local retries=${2:-3}
    local delay=${3:-10}
    for attempt in $(seq 1 $retries); do
        log INFO "Попытка $attempt/$retries: $cmd"
        if eval "$cmd"; then
            return 0
        else
            log WARNING "Ошибка выполнения: $cmd (попытка $attempt/$retries)"
            sleep $delay
        fi
    done
    log ERROR "Не удалось выполнить команду после $retries попыток: $cmd"
    return 1
}

# Проверка доступности хранилищ
check_storage_access() {
    log INFO "Проверка доступности хранилищ..."

    # Список уникальных remote'ов
    local remotes=("test" "nbgi-init-sequencing" "nbgi-init-gd" "registry" "backup" "default" "minio")
    for remote in "${remotes[@]}"; do
        if ! rclone lsd "$remote:" --config="$RCLONE_CONFIG" >/dev/null 2>&1; then
            log ERROR "Хранилище $remote недоступно"
            return 1
        fi
        log INFO "Хранилище $remote доступно"
    done

    # Проверка состояния Ceph через SSH
    if command -v ssh >/dev/null; then
        if ! ssh cephsvc05 "podman exec ceph-mon-cephsvc05 ceph status" >/dev/null; then
            log WARNING "Проблемы с состоянием Ceph-кластера"
        else
            log INFO "Ceph-кластер в порядке"
        fi
    else
        log WARNING "Команда ssh недоступна, пропускаем проверку состояния Ceph"
    fi

    return 0
}

# Создание бакета при отсутствии
create_bucket_if_not_exists() {
    local remote="$1"
    local bucket="$2"
    if ! rclone lsd "$remote:$bucket" --config="$RCLONE_CONFIG" >/dev/null 2>&1; then
        log INFO "Бакет $bucket не существует. Создание..."
        if ! retry_command "rclone mkdir '$remote:$bucket' --config='$RCLONE_CONFIG'" 3 10; then
            log ERROR "Не удалось создать бакет $bucket"
            return 1
        fi
        log INFO "Бакет $bucket успешно создан"
    else
        log INFO "Бакет $bucket уже существует"
    fi
    return 0
}

# Частичная валидация
validate_backup() {
    local src="$1"
    local dst="$2"
    log INFO "Начата частичная валидация: $src -> $dst"

    local src_count=$(rclone lsf "$src" --files-only --config="$RCLONE_CONFIG" | wc -l)
    local dst_count=$(rclone lsf "$dst" --files-only --config="$RCLONE_CONFIG" | wc -l)

    if [[ "$src_count" -eq "$dst_count" ]]; then
        log INFO "Валидация успешна: количество файлов совпадает ($src_count)"
        return 0
    else
        log ERROR "Валидация не пройдена: $src_count файлов в источнике, $dst_count в бэкапе"
        return 1
    fi
}

# Удаление устаревших данных
cleanup_old_backups() {
    log INFO "Начата очистка устаревших данных из $DELETE_BACKUP"
    if ! retry_command "rclone purge --min-age ${RETENTION_DAYS}d '$DELETE_BACKUP' \
        --config='$RCLONE_CONFIG' \
        --s3-force-path-style \
        --no-check-certificate \
        --log-level=INFO \
        --log-file='$LOGFILE'" 3 15; then
        log ERROR "Ошибка при очистке устаревших данных"
        return 1
    fi
    log INFO "Очистка завершена успешно"
}

# Обработка бакета
process_bucket() {
    local bucket="$1"
    local source_remote="${bucket%%:*}"
    local source_bucket="${bucket#*:}"
    local target_bucket="${source_remote}"
    local target_path="minio:${target_bucket}/${source_bucket}"

    log INFO "Проверка существования бакета: $target_bucket"
    if ! create_bucket_if_not_exists "minio" "$target_bucket"; then
        return 1
    fi

    log INFO "Синхронизация бакета: $bucket -> $target_path"
    if ! retry_command "rclone copy '$bucket' '$target_path' \
        --config='$RCLONE_CONFIG' ${RCLONE_FLAGS[*]}" 3 15; then
        log ERROR "Ошибка при синхронизации бакета: $bucket"
        return 1
    fi

    if ! validate_backup "$bucket" "$target_path"; then
        return 1
    fi
    log INFO "Синхронизация бакета $bucket успешно завершена"
}
export -f process_bucket log retry_command create_bucket_if_not_exists validate_backup
export RCLONE_CONFIG RCLONE_TRANSFERS RCLONE_CHECKERS RCLONE_RETRIES LOGFILE DELETE_BACKUP

# Основная функция
perform_backup() {
    # Проверка хранилищ
    if ! check_storage_access; then
        log ERROR "Ошибка проверки доступности хранилищ"
        return 1
    fi

    # Проверка backup-deleted
    create_bucket_if_not_exists "minio" "backup-deleted" || return 1

    # Параллельная обработка бакетов
    log INFO "Начата синхронизация бакетов (параллельно: $RCLONE_PARALLEL потоков)"
    if ! printf "%s\0" "${buckets[@]}" | xargs -0 -n1 -P"$RCLONE_PARALLEL" -I{} bash -c 'process_bucket "$@"' _ {}; then
        log ERROR "Ошибки при синхронизации бакетов"
        return 1
    fi

    # Очистка устаревших данных
    cleanup_old_backups || log WARNING "Проблемы с очисткой, проверьте логи"

    return 0
}

# Основной поток
log INFO "***** Начат процесс резервного копирования *****"
log INFO "Запуск от пользователя: $(whoami)"
log INFO "Версия rclone: $(rclone --version | head -n1)"
log INFO "Конфиг rclone: $RCLONE_CONFIG"
log INFO "Параметры: transfers=$RCLONE_TRANSFERS checkers=$RCLONE_CHECKERS retries=$RCLONE_RETRIES parallel=$RCLONE_PARALLEL"

if perform_backup; then
    log INFO "Процесс бэкапа завершен успешно"
else
    log ERROR "Бэкап завершился с ошибками"
    exit 1
fi