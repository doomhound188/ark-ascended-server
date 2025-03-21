# ark-ascended-server
[![Static Badge](https://img.shields.io/badge/DockerHub-blue)](https://hub.docker.com/r/sknnr/ark-ascended-server) ![Docker Pulls](https://img.shields.io/docker/pulls/sknnr/ark-ascended-server)

Containerized Ark: Survival Ascended server

This project runs the Windows Ark: SA binaries in Debian 12 Linux headless with GE Proton.

**Disclaimer:** This is not an official image. No support, implied or otherwise is offered to any end user by the author or anyone else. Feel free to do what you please with the contents of this repository.

## Usage

The processes within the container do **NOT** run as root. Everything runs as the user steam (gid:10000/uid:10000). There is no interface at all, everything runs headless. If you exec into the container, you will be operating as the steam user.

### Ports

| Port | Protocol | Default |
| ---- | -------- | ------- |
| Game Port | UDP | 7777 |
| RCON Port | TCP | 27020 |

This is the port required by Ark: SA. If you have read elsewhere about the query port, that is deprecated and not used in the Survival Ascended version of Ark. If you are not able to see your server, make sure you have enabled the correct port forwarding on your router.

If you are still running into issues, there is one potential cause that may be out of your control that I feel I must mention. Some ISPs (internet service providers) utilize a technology called CGNAT (Carrier Grade Network Address Translation). CGNAT can cause issues with port forwarding. If you suspect this may be the case, you will need to contact your ISP for assistance.

### Environment Variables

| Name | Description | Default | Required |
| ---- | ----------- | ------- | -------- |
| SERVER_MAP | The map that the server runs | TheIsland_WP | True |
| SESSION_NAME | The name for your server/session | None | True |
| SERVER_PASSWORD | The password to join your server | None | False |
| SERVER_ADMIN_PASSWORD | The password for utilizing admin functions | None | True |
| GAME_PORT | This is the port that the server accepts incoming traffic on | 7777 | True |
| RCON_PORT | The port for the RCON service to listen on | 27020 | False |
| MODS | Comma separated list of CurseForge project IDs. Example: ModId1,ModId2,etc | None | False |
| EXTRA_FLAGS | Space separated list of additional server start flags. Example: -NoBattlEye -ForceAllowCaveFlyers | None | False |
| EXTRA_SETTINGS | ? Separated list of additional server settings. Example: ?serverPVE=True?ServerHardcore=True | None | False |
| TZ | Set timezone for the container | America/Toronto | False |

#### Backup Environment Variables

| Name | Description | Default | Required |
| ---- | ----------- | ------- | -------- |
| BACKUP_ENABLED | Enable automated backups | false | False |
| BACKUP_REPOSITORY | Restic repository URL/path | None | True if backups enabled |
| BACKUP_PASSWORD | Password for the Restic repository | None | True if backups enabled |
| BACKUP_SCHEDULE | Cron schedule for backups | 0 0 * * * (daily at midnight) | False |
| BACKUP_RETENTION_DAYS | Number of days to keep backups | 7 | False |
| BACKUP_PATHS | Paths to backup | /home/steam/ark/ShooterGame/Saved | False |
| BACKUP_EXCLUDE | Space separated list of exclude patterns | None | False |
| BACKUP_BEFORE_UPDATE | Whether to backup before updating | true | False |

### Docker

To run the container in Docker, run the following command:

```bash
docker volume create ark-persistent-data
docker run \
  --detach \
  --name Ark-Ascended-Server \
  --mount type=volume,source=ark-persistent-data,target=/home/steam/ark/ShooterGame/Saved \
  --publish 7777:7777/udp \
  --publish 27020:27020/tcp \
  --env=SERVER_MAP=TheIsland_WP \
  --env=SESSION_NAME="Ark Ascended Containerized" \
  --env=SERVER_PASSWORD="PleaseChangeMe" \
  --env=SERVER_ADMIN_PASSWORD="AlsoChangeMe" \
  --env=GAME_PORT=7777 \
  --env=RCON_PORT=27020 \
  sknnr/ark-ascended-server:latest
```

### Docker Compose

To use Docker Compose, either clone this repo or copy the `compose.yaml` file out of the `container` directory to your local machine. Edit the compose file to change the environment variables to the desired values.

compose.yaml:
```yaml
services:
  ark-ascended:
    image: sknnr/ark-ascended-server:latest
    ports:
      - "7777:7777/udp"
      - "27020:27020/tcp"
    environment:
      - SESSION_NAME=Ark Ascended Containerized
      - SERVER_PASSWORD=PleaseChangeMe
      - SERVER_MAP=TheIsland_WP
      - SERVER_ADMIN_PASSWORD=AlsoChangeMe
      - GAME_PORT=7777
      - RCON_PORT=27020
    volumes:
      - ark-persistent-data:/home/steam/ark/ShooterGame/Saved

volumes:
  ark-persistent-data:
```

To bring the container up:

```bash
docker compose up -d
```

To bring the container down:

```bash
docker compose down
```

### Podman

To run the container in Podman, run the following command:

```bash
podman volume create ark-persistent-data
podman run \
  --detach \
  --name Ark-Ascended-Server \
  --mount type=volume,source=ark-persistent-data,target=/home/steam/ark/ShooterGame/Saved \
  --publish 7777:7777/udp \
  --publish 27020:27020/tcp \
  --env=SERVER_MAP=TheIsland_WP \
  --env=SESSION_NAME="Ark Ascended Containerized" \
  --env=SERVER_PASSWORD="PleaseChangeMe" \
  --env=SERVER_ADMIN_PASSWORD="AlsoChangeMe" \
  --env=GAME_PORT=7777 \
  --env=RCON_PORT=27020 \
  --restart always \
  --label io.containers.autoupdate=registry \
  docker.io/sknnr/ark-ascended-server:latest
```

### Kubernetes

I've built a Helm chart and have included it in the `helm` directory within this repo. Modify the `values.yaml` file to your liking and install the chart into your cluster. Be sure to create and use a `PersistentVolume` and `PersistentVolumeClaim` for the data storage.

## Backups

The container includes a built-in backup system using [Restic](https://restic.net/) which can automatically back up your server data on a schedule. To enable backups, you need to set the appropriate environment variables.

### Basic Backup Configuration

```bash
docker run \
  --detach \
  --name Ark-Ascended-Server \
  --mount type=volume,source=ark-persistent-data,target=/home/steam/ark/ShooterGame/Saved \
  --publish 7777:7777/udp \
  --publish 27020:27020/tcp \
  --env=SESSION_NAME="Ark Ascended Containerized" \
  --env=SERVER_ADMIN_PASSWORD="YourAdminPassword" \
  --env=BACKUP_ENABLED=true \
  --env=BACKUP_REPOSITORY="s3:https://s3.amazonaws.com/your-bucket-name" \
  --env=BACKUP_PASSWORD="YourSecureBackupPassword" \
  sknnr/ark-ascended-server:latest
```

### Backup Repository Types

Restic supports various repository types including:

- Local: `/path/to/repository`
- S3: `s3:https://s3.amazonaws.com/bucket_name`
- SFTP: `sftp:user@host:/path`
- Rest Server: `rest:https://user:pass@host:8000/`

For complete details on repository types, see the [Restic documentation](https://restic.readthedocs.io/en/latest/030_preparing_a_new_repo.html).

## Automatic Updates

### Using Watchtower with Docker

Watchtower can automatically update your running Docker containers. To use Watchtower:

1. Run Watchtower:

   ```bash
   docker run -d \
     --name watchtower \
     -v /var/run/docker.sock:/var/run/docker.sock \
     containrrr/watchtower
   ```

2. Configure Watchtower (optional):

   ```bash
   docker run -d \
     --name watchtower \
     -v /var/run/docker.sock:/var/run/docker.sock \
     containrrr/watchtower \
     --interval 300 \
     --notifications email \
     --notification-email-from watchtower@example.com \
     --notification-email-to you@example.com \
     --notification-email-server smtp.example.com \
     --notification-email-server-port 587 \
     --notification-email-server-user user@example.com \
     --notification-email-server-password password
   ```

### Using Built-in Update Functions in Podman

Podman supports automatic updates with the `io.containers.autoupdate` label.

1. Ensure your Podman run command includes the `--label io.containers.autoupdate=registry` option as shown in the Podman example above.

2. Create a systemd unit file for auto-update:

   ```ini
   [Unit]
   Description=Podman auto-update service
   Wants=network-online.target
   After=network-online.target

   [Service]
   Type=oneshot
   ExecStart=/usr/bin/podman auto-update --authfile /path/to/auth.json
   ```

3. Create a systemd timer to run the update service daily:

   ```ini
   [Unit]
   Description=Run Podman auto-update daily

   [Timer]
   OnCalendar=daily
   Persistent=true

   [Install]
   WantedBy=timers.target
   ```

4. Enable and start the timer:

   ```bash
   sudo systemctl enable podman-auto-update.timer
   sudo systemctl start podman-auto-update.timer
   ```

The chart in this repo is also hosted in my helm-charts repository [here](https://jsknnr.github.io/helm-charts)

To install this chart from my helm-charts repository:

```bash
helm repo add jsknnr https://jsknnr.github.io/helm-charts
helm repo update
```

To install the chart from the repo:

```bash
helm install ark-survival-ascended jsknnr/ark-survival-ascended --values myvalues.yaml
# Where myvalues.yaml is your copy of the Values.yaml file with the settings that you want
```

## Troubleshooting

### Connectivity

If you are having issues connecting to the server once the container is deployed, I promise the issue is not with this image. You need to make sure that the ports 7777/udp and 27020/tcp (or whichever ports you have configured) are open and forwarded correctly on your router.

### Storage

I recommend having Docker or Podman manage the volume that gets mounted into the container. However, if you absolutely must bind mount a directory into the container you need to make sure that ownership and permissions are set correctly. Use `chown -R 10000:10000 /your/mount/path` to set the correct ownership.

### Backups

If backups aren't working:
1. Check that `BACKUP_ENABLED` is set to `true`
2. Verify that `BACKUP_REPOSITORY` and `BACKUP_PASSWORD` are set correctly
3. Check the backup logs with `docker exec Ark-Ascended-Server cat /home/steam/backup.log`
```
