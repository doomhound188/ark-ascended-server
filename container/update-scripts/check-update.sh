#!/bin/bash
set -e

# Exit if auto-updates are disabled
if [ "${AUTO_UPDATE_ENABLED}" != "true" ]; then
    echo "$(timestamp) INFO: Auto-updates are disabled. Skipping update check."
    exit 0
fi

# Quick function to generate a timestamp
timestamp() {
  date +"%Y-%m-%d %H:%M:%S,%3N"
}

# Function to get the installed version
get_installed_version() {
    grep '"buildid"' ${ARK_PATH}/steamapps/appmanifest_2430930.acf | awk -F'"' '{print $4}'
}

# Function to get the latest version from Steam - targeting public branch specifically
get_latest_version() {
    steamcmd +login anonymous +app_info_print 2430930 +quit | grep -A 2 '^\s*"public"\s*$' | grep -m 1 '"buildid"' | awk '{print $2}' | tr -d '",'
}

# Update Ark Ascended if needed
update_server() {
    local installed_version latest_version
    installed_version=$(get_installed_version)
    latest_version=$(get_latest_version)

    if [ -z "$installed_version" ]; then
        echo "$(timestamp) INFO: No installed version found, updating Ark Survival Ascended Dedicated Server"
    elif [ "$installed_version" == "$latest_version" ]; then
        echo "$(timestamp) INFO: Ark Survival Ascended Dedicated Server is already up to date (version $installed_version)"
        return
    else
        echo "$(timestamp) INFO: Updating Ark Survival Ascended Dedicated Server from version $installed_version to $latest_version"
        
        # Perform server save before update if server is running
        if netstat -aln | grep -q $GAME_PORT; then
            echo "$(timestamp) INFO: Server is running, saving world before update..."
            rcon -a 127.0.0.1:${RCON_PORT} -p "${SERVER_ADMIN_PASSWORD}" Saveworld
            echo "$(timestamp) INFO: World saved, proceeding with update..."
        fi
    fi

    steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir "$ARK_PATH" +login anonymous +app_update 2430930 validate +quit

    if [ $? != 0 ]; then
        echo "$(timestamp) ERROR: steamcmd was unable to successfully update Ark Survival Ascended Dedicated Server"
        exit 1
    fi
    
    # If server was already running, restart it after update
    if netstat -aln | grep -q $GAME_PORT; then
        echo "$(timestamp) INFO: Update complete, restarting server..."
        rcon -a 127.0.0.1:${RCON_PORT} -p "${SERVER_ADMIN_PASSWORD}" DoExit
    fi
}

echo "$(timestamp) INFO: Running scheduled update check..."
update_server
echo "$(timestamp) INFO: Update check completed"
