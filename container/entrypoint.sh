#!/bin/bash

# Quick function to generate a timestamp
timestamp () {
  date +"%Y-%m-%d %H:%M:%S,%3N"
}

# Shutdown function for trap
shutdown () {
    echo "$(timestamp) INFO: Received SIGTERM, shutting down gracefully"
    echo "$(timestamp) INFO: Saving world..."
    # Not clear if DoExit saves first so explicitly save then exit
    rcon -a 127.0.0.1:${RCON_PORT} -p "${SERVER_ADMIN_PASSWORD}" Saveworld
    rcon -a 127.0.0.1:${RCON_PORT} -p "${SERVER_ADMIN_PASSWORD}" DoExit

    # Server exit doesn't close pid for some reason, so lets check that the port is closed and then send SIGTERM to main pid
    while netstat -aln | grep -q $GAME_PORT; do
        sleep 1
    done

    echo "$(timestamp) INFO: Goodbye"
    kill -15 $asa_pid 
}

# Set our trap
trap 'shutdown' TERM

# Set vars established during image build
IMAGE_VERSION=$(cat /home/steam/image_version)
MAINTAINER=$(cat /home/steam/image_maintainer)
EXPECTED_FS_PERMS=$(cat /home/steam/expected_filesystem_permissions)

echo "$(timestamp) INFO: Launching Ark: Survival Ascended dedicated server image ${IMAGE_VERSION} by ${MAINTAINER}"

# Update timezone if TZ is changed at runtime
if [ -n "$TZ" ]; then
  sudo ln -snf /usr/share/zoneinfo/$TZ /etc/localtime 
  echo $TZ | sudo tee /etc/timezone > /dev/null
fi

# Make sure required arguments are set
if [ -z "$SERVER_MAP" ]; then
    SERVER_MAP="TheIsland_WP"
    echo "$(timestamp) WARN: SERVER_MAP not set, using default: $SERVER_MAP"
fi

if [ -z "$SESSION_NAME" ]; then
    echo "$(timestamp) ERROR: SESSION_NAME environment variable must be set"
    exit 1
fi

if [ -z "$GAME_PORT" ]; then
    GAME_PORT="7777"
    echo "$(timestamp) WARN: GAME_PORT not set, using default: $GAME_PORT UDP"
fi

if [ -z "$RCON_PORT" ]; then
    RCON_PORT="27020"
    echo "$(timestamp) WARN: RCON_PORT not set, using default: $RCON_PORT TCP"
fi

if [ -z "$SERVER_PASSWORD" ]; then
    echo "$(timestamp) WARN: SERVER_PASSWORD not set, the server will be open to the public"
fi

if [ -z "$SERVER_ADMIN_PASSWORD" ]; then
    echo "$(timestamp) ERROR: SERVER_ADMIN_PASSWORD environment variable must be set"
    exit 1
fi

# Check for correct ownership
if ! touch "${ARK_PATH}/ShooterGame/Saved/test"; then
    echo ""
    echo "$(timestamp) ERROR: The ownership of /home/steam/ark/ShooterGame/Saved is not correct and the server will not be able to save..."
    echo "the directory that you are mounting into the container needs to be owned by ${EXPECTED_FS_PERMS}"
    echo "from your container host attempt the following command 'chown -R ${EXPECTED_FS_PERMS} /your/ark/folder'"
    echo ""
    exit 1
fi

# Cleanup test write
rm "${ARK_PATH}/ShooterGame/Saved/test"

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
    fi

    steamcmd +@sSteamCmdForcePlatformType windows +force_install_dir "$ARK_PATH" +login anonymous +app_update 2430930 validate +quit

    if [ $? != 0 ]; then
        echo "$(timestamp) ERROR: steamcmd was unable to successfully initialize and update Ark Survival Ascended Dedicated Server"
        exit 1
    fi
}

# Call the update function
update_server

# Setup auto-update cron job if enabled
if [ "${AUTO_UPDATE_ENABLED}" = "true" ]; then
    /home/steam/update-scripts/setup-update-cron.sh
fi

# Check that log directory exists, if not create
if ! [ -d "${ARK_PATH}/ShooterGame/Saved/Logs/" ]; then
    mkdir -p "${ARK_PATH}/ShooterGame/Saved/Logs/"
fi

# Check that log file exists, if not create
if ! [ -f "${ARK_PATH}/ShooterGame/Saved/Logs/ShooterGame.log" ]; then
    touch "${ARK_PATH}/ShooterGame/Saved/Logs/ShooterGame.log"
fi

# Link logfile to stdout of pid 1 so we can see logs
ln -sf /proc/1/fd/1 "${ARK_PATH}/ShooterGame/Saved/Logs/ShooterGame.log"

# Build Ark Ascended launch command
LAUNCH_COMMAND="${SERVER_MAP}?SessionName=${SESSION_NAME}?RCONEnabled=True?RCONPort=${RCON_PORT}"
if [ -n "${SERVER_PASSWORD}" ]; then
    LAUNCH_COMMAND="${LAUNCH_COMMAND}?ServerPassword=${SERVER_PASSWORD}"
fi

if [ -n "${EXTRA_SETTINGS}" ]; then
    LAUNCH_COMMAND="${LAUNCH_COMMAND}${EXTRA_SETTINGS}"
fi

# According to Wiki, ServerAdminPassword must be the last "?" deliniated Argument
LAUNCH_COMMAND="${LAUNCH_COMMAND}?ServerAdminPassword=${SERVER_ADMIN_PASSWORD}"

# According to Wiki, game port is not a ? deliniated command
LAUNCH_COMMAND="${LAUNCH_COMMAND} -port=${GAME_PORT}"

if [ -n "${EXTRA_FLAGS}" ]; then
    LAUNCH_COMMAND="${LAUNCH_COMMAND} ${EXTRA_FLAGS}"
fi

if [ -n "${MODS}" ]; then
    LAUNCH_COMMAND="${LAUNCH_COMMAND} -mods=${MODS}"
fi

# RCONEnabled in server start args doesn't seem to actually enabled RCON, so let's do it manually
if ! [ -f "${ARK_PATH}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini" ]; then
    mkdir -p ${ARK_PATH}/ShooterGame/Saved/Config/WindowsServer
    cat <<EOF > ${ARK_PATH}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini
[ServerSettings]
RCONEnabled=True
RCONPort=${RCON_PORT}
EOF
elif ! grep -q "RCONEnabled" ${ARK_PATH}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini; then
    echo "$(timestamp) INFO: Adding RCON settings to GameUserSettings.ini"
    sed -i "s/RCONPort=[0-9]*/RCONPort=${RCON_PORT}\nRCONEnabled=True/" ${ARK_PATH}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini
elif grep -q "RCONEnabled=False" ${ARK_PATH}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini; then
    echo "$(timestamp) INFO: Enabling RCON in GameUserSettings.ini"
    sed -i "s/RCONEnabled=False/RCONEnabled=True/" ${ARK_PATH}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini
fi

# Ensure RCON port is set correctly in configuration
if grep -q "RCONPort=" ${ARK_PATH}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini; then
    echo "$(timestamp) INFO: Setting RCON port to ${RCON_PORT} in GameUserSettings.ini"
    sed -i "s/RCONPort=[0-9]*/RCONPort=${RCON_PORT}/" ${ARK_PATH}/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini
fi

echo "$(timestamp) INFO: Launching ARK:SA"
echo "-----------------------------------------------------------"
echo "Server Name: ${SESSION_NAME}"
echo "Server Password: ${SERVER_PASSWORD}"
echo "Admin Password: ${SERVER_ADMIN_PASSWORD}"
echo "RCON Port: ${RCON_PORT}"
echo "Game Port: ${GAME_PORT}"
echo "Map: ${SERVER_MAP}"
echo "Extra Settings: ${EXTRA_SETTINGS}"
echo "Extra Flags: ${EXTRA_FLAGS}"
echo "Mods: ${MODS}"
echo "Server Container Image Version: ${IMAGE_VERSION}"
echo ""
echo ""

# Launch ASE Server in Proton
${STEAM_PATH}/compatibilitytools.d/GE-Proton${GE_PROTON_VERSION}/proton run ${ARK_PATH}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe ${LAUNCH_COMMAND} &

asa_pid=$!

wait $asa_pid
