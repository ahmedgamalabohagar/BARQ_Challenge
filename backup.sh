#! /usr/bin/env bash
set -euo pipefail

backup_dir="./backups"
timestamp=$(date +%Y%m%d_%H%M%S)
backup_file="${backup_dir}/postgres_backup_${timestamp}.sql"
POSTGRES_USER="${POSTGRES_USER:-barq_app}"
POSTGRES_DB="${POSTGRES_DB:-barq_tasks}"
CONTAINER_NAME="${CONTAINER_NAME:-postgres}"

mkdir -p "$backup_dir"

echo "[INFO] starting database backup process..."

#check postgres running
if ! docker compose ps --services --filter "status=running" | grep -q "^${CONTAINER_NAME}$"; then
    echo "[FAIL]: '${CONTAINER_NAME}' is not running"
    exit 1
fi

if docker compose exec -T "${CONTAINER_NAME}" pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > "${backup_file}"; then
    if [ -s "$backup_file" ]; then
        echo "[PASS]: database backup successfully created at : ${backup_file}"
        exit 0
    else
        echo "[FAIL]: backup created but is empty :("
        rm -f "${backup_file}"
        exit 1
    fi
else
    echo "[FAIL] faild to execute pg_dump on '${CONTAINER_NAME}'"
    rm -f "${backup_file}"
    exit 1
fi