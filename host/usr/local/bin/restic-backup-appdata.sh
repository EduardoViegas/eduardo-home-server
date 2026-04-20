#!/bin/bash
set -euo pipefail

export RESTIC_REPOSITORY=/mnt/storage/backups/restic-appdata
export RESTIC_PASSWORD_FILE=/mnt/storage/backups/.restic-password

restic backup \
  --exclude '/docker/appdata/plex/Library/Application Support/Plex Media Server/Cache' \
  --exclude '/docker/appdata/plex/Library/Application Support/Plex Media Server/Logs' \
  --exclude '/docker/appdata/plex/Library/Application Support/Plex Media Server/Crash Reports' \
  --exclude '/docker/appdata/plex/Library/Application Support/Plex Media Server/Diagnostics' \
  --tag appdata \
  /docker/appdata

restic forget \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 12 \
  --tag appdata \
  --prune
