#!/bin/bash
set -e

# Exit if backups are disabled
if [ "${BACKUP_ENABLED}" != "true" ]; then
    echo "Backups are disabled. Skipping backup."
    exit 0
fi

# Check if repository is configured
if [ -z "${BACKUP_REPOSITORY}" ]; then
    echo "Error: BACKUP_REPOSITORY not set. Cannot perform backup."
    exit 1
fi

# Export password for restic
export RESTIC_PASSWORD="${BACKUP_PASSWORD}"

# Initialize repository if it doesn't exist yet
echo "Checking if repository needs initialization..."
if ! restic -r "${BACKUP_REPOSITORY}" snapshots &>/dev/null; then
    echo "Initializing repository ${BACKUP_REPOSITORY}..."
    restic -r "${BACKUP_REPOSITORY}" init
fi

# Build backup command
BACKUP_CMD="restic -r ${BACKUP_REPOSITORY} backup ${BACKUP_PATHS}"

# Add exclude patterns if specified
if [ -n "${BACKUP_EXCLUDE}" ]; then
    for pattern in ${BACKUP_EXCLUDE}; do
        BACKUP_CMD="${BACKUP_CMD} --exclude=${pattern}"
    done
fi

# Run backup
echo "Starting backup at $(date)..."
eval "${BACKUP_CMD}"
echo "Backup completed at $(date)"

# Prune old backups if retention is set
if [ -n "${BACKUP_RETENTION_DAYS}" ] && [ "${BACKUP_RETENTION_DAYS}" -gt 0 ]; then
    echo "Pruning backups older than ${BACKUP_RETENTION_DAYS} days..."
    restic -r "${BACKUP_REPOSITORY}" forget --keep-within "${BACKUP_RETENTION_DAYS}d" --prune
fi
