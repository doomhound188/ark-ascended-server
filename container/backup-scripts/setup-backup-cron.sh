#!/bin/bash
set -e

# Exit if backups are disabled
if [ "${BACKUP_ENABLED}" != "true" ]; then
    echo "Backups are disabled. Not setting up cron job."
    exit 0
fi

# Check if repository is configured
if [ -z "${BACKUP_REPOSITORY}" ]; then
    echo "Warning: BACKUP_REPOSITORY not set. Cron job will be created but backups will fail."
fi

# Create cron job for scheduled backups
CRON_FILE="/tmp/backup-cron"
echo "${BACKUP_SCHEDULE} /home/steam/backup-scripts/backup.sh >> /home/steam/backup.log 2>&1" > ${CRON_FILE}

# Install cron job
crontab ${CRON_FILE}
rm ${CRON_FILE}

echo "Backup cron job installed with schedule: ${BACKUP_SCHEDULE}"
