#!/usr/bin/env bash
# Back up the Minecraft server's /data volume to the external volume.
#
# Finds the running itzg/minecraft-server container, pauses world saving
# over RCON so the copy is consistent, and writes a dated snapshot to DEST.
# Unchanged files are hard-linked to the previous snapshot, so each
# snapshot only uses space for what changed. Snapshots older than
# KEEP_DAYS are removed.
#
# Cron example (/etc/cron.d/mc-backup):
#   0 */6 * * * root /usr/local/bin/mc-backup.sh >> /var/log/mc-backup.log 2>&1

set -euo pipefail

# External volume mount point; the backup is skipped if it isn't mounted
MOUNT="${MOUNT:-/mnt/HC_Volume_100133373}"
DEST="${DEST:-$MOUNT/CreateChronicles-2.0.0/backups}"
KEEP_DAYS="${KEEP_DAYS:-7}"
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

name=$(date '+%F_%H%M')
snapshot="$DEST/$name"
partial="$DEST/.partial"
[[ -e $snapshot ]] && fail "Snapshot $snapshot already exists"

log "Backing up $container ($src) to $snapshot"

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
rm -rf "$partial"

# Copy into .partial and rename when done, so an interrupted run never
# looks like a finished snapshot
link_dest=()
[[ -d $DEST/latest ]] && link_dest=(--link-dest="$DEST/latest")
rsync -a "${link_dest[@]}" "$src"/ "$partial"/
mv "$partial" "$snapshot"
ln -sfn "$name" "$DEST/latest"

# Remove snapshots older than KEEP_DAYS (names sort by date)
cutoff=$(date -d "$KEEP_DAYS days ago" '+%F_%H%M')
for dir in "$DEST"/20??-??-??_????; do
  old=$(basename "$dir")
  if [[ $old < $cutoff && $old != "$name" ]]; then
    log "Removing old snapshot $old"
    rm -rf "$dir"
  fi
done

log "Backup complete: $snapshot ($(du -sh "$DEST" | cut -f1) total in $DEST)"
