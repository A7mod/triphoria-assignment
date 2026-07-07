#!/bin/bash
set -e

BACKUP_DIR="$(dirname "$0")/../backups"

if [ -z "$1" ]; then
    echo "No backup file specified. Using latest backup..."
    BACKUP_FILE=$(ls -t "$BACKUP_DIR"/*.sql | head -n 1)
else
    BACKUP_FILE="$1"
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "Restoring from: $BACKUP_FILE"

echo "Dropping and recreating database..."
docker exec -i triphoria-postgres psql -U triphoria_admin -d postgres -c "DROP DATABASE IF EXISTS triphoria;"
docker exec -i triphoria-postgres psql -U triphoria_admin -d postgres -c "CREATE DATABASE triphoria;"

echo "Restoring data..."
docker exec -i triphoria-postgres psql -U triphoria_admin -d triphoria < "$BACKUP_FILE"

echo "Restore completed."
echo "Verifying row counts..."
docker exec -it triphoria-postgres psql -U triphoria_admin -d triphoria -c "SELECT COUNT(*) FROM hotel_bookings; SELECT COUNT(*) FROM booking_events;"