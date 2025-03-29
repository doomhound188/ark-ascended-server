#!/bin/bash
set -e

# Exit if auto-updates are disabled
if [ "${AUTO_UPDATE_ENABLED}" != "true" ]; then
    echo "Auto-updates are disabled. Not setting up cron job."
    exit 0
fi

# Create cron job for scheduled updates
CRON_FILE="/tmp/update-cron"
echo "${AUTO_UPDATE_SCHEDULE} /home/steam/update-scripts/check-update.sh >> /home/steam/update.log 2>&1" > ${CRON_FILE}

# Install cron job
crontab -l > /tmp/current-crontab 2>/dev/null || true
cat ${CRON_FILE} >> /tmp/current-crontab
crontab /tmp/current-crontab
rm ${CRON_FILE} /tmp/current-crontab

echo "Update check cron job installed with schedule: ${AUTO_UPDATE_SCHEDULE}"
