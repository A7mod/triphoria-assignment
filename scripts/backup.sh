#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$(dirname "$0")/../backups"
BACKUP_FILE="$BACKUP_DIR/triphoria_backup_$TIMESTAMP.sql"

mkdir -p "$BACKUP_DIR"

echo "Starting backup..."
docker exec -i triphoria-postgres pg_dump -U triphoria_admin -d triphoria > "$BACKUP_FILE"

echo "Backup completed: $BACKUP_FILE"
ls -lh "$BACKUP_FILE"