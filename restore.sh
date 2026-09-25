#! /usr/bin/env bash

set -euo pipefail

backup_dir="./backups"
POSTGRES_USER="${POSTGRES_USER:-barq_app}"
POSTGRES_DB="${POSTGRES_DB:-barq_tasks}"
CONTAINER_NAME="${CONTAINER_NAME:-postgres}"

# restore latest backup if user don't select specific backup
if [ $# -ge 1 ]; then
    backup_file="$1"
else
    backup_file=$(ls -t "${backup_dir}"/postgres_backup*.sql 2>/dev/null | head -n 1) || true
fi

echo "[INFO]: start restoring process ..."

if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
    echo "[FAIL]: no valid backup file in ${backup_dir}"
    exit 1
fi

# check postgress container running
if ! docker compose ps --services --filter "status=running" | grep -q "^${CONTAINER_NAME}$"; then
    echo "[FAIL] : container ${CONTAINER_NAME} is not running"
    exit 1
fi

echo "[INFO]: restoring database from : $backup_file"

# restore from dump
if docker compose exec -T "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1 && \
   docker compose exec -T "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$backup_file" >/dev/null 2>&1; then
   echo "[PASS] database restoration successfully from $backup_file"
   exit 0
else
    echo "[FAIL] faild to restore database from $backup_file"
    exit 1
fi