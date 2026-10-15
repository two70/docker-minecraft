#!/usr/bin/env bash
# Back up the Minecraft server's /data volume to the external volume.
#
# Finds the running itzg/minecraft-server container, pauses world saving
# over RCON so the copy is consistent, and rsyncs the volume to DEST.
#
# Cron example (/etc/cron.d/mc-backup):
#   0 */6 * * * root /usr/local/bin/mc-backup.sh >> /var/log/mc-backup.log 2>&1

set -euo pipefail

# External volume mount point; the backup is skipped if it isn't mounted
MOUNT="${MOUNT:-/mnt/HC_Volume_100133373}"
DEST="${DEST:-$MOUNT/CreateChronicles-2.0.0/backup}"
# docker ps filter used to find the server container
FILTER="${FILTER:-ancestor=itzg/minecraft-server}"
LOCK="${LOCK:-/var/lock/mc-backup.lock}"

log() { echo "[$(date '+%F %T')] $*"; }
fail() { log "ERROR: $*"; exit 1; }

# Skip if a previous run is still going
exec 9>"$LOCK"
flock -n 9 || { log "Backup already running, skipping"; exit 0; }

mountpoint -q "$MOUNT" || fail "$MOUNT is not mounted"

mapfile -t containers < <(docker ps --filter "$FILTER" --format '{{.Names}}')
case ${#containers[@]} in
  0) fail "No running container matches '$FILTER'" ;;
  1) container=${containers[0]} ;;
  *) fail "Several containers match '$FILTER' (${containers[*]}); set FILTER to pick one" ;;
esac

src=$(docker inspect "$container" \
  --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}')
[[ -d $src ]] || fail "No /data volume found for $container"

log "Backing up $container ($src) to $DEST"

rcon() { docker exec "$container" rcon-cli "$@" >/dev/null; }
resume_saving() { rcon save-on || log "WARNING: could not re-enable saving (run: rcon-cli save-on)"; }

# Flush and pause world saves; always turn them back on when the script exits
if rcon save-off; then
  trap resume_saving EXIT
  rcon save-all flush
else
  log "WARNING: RCON unavailable, copying the world while it is live"
fi

mkdir -p "$DEST"
rsync -a --delete "$src"/ "$DEST"/

log "Backup complete ($(du -sh "$DEST" | cut -f1))"
