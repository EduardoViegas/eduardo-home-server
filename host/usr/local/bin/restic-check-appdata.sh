#!/bin/bash
set -uo pipefail

export RESTIC_REPOSITORY=/mnt/storage/backups/restic-appdata
export RESTIC_PASSWORD_FILE=/mnt/storage/backups/.restic-password

KUMA_DB=/docker/appdata/uptime-kuma/kuma.db

send_telegram() {
  local msg="$1"
  local creds token chat_id
  creds=$(sqlite3 "$KUMA_DB" \
    "SELECT json_extract(config,'\$.telegramBotToken')||'|'||json_extract(config,'\$.telegramChatID') FROM notification WHERE name='Telegram' LIMIT 1;" 2>/dev/null) || return 1
  token="${creds%|*}"
  chat_id="${creds#*|}"
  [[ -z "$token" || -z "$chat_id" ]] && return 1
  curl -sS -m 15 \
    --data-urlencode "chat_id=${chat_id}" \
    --data-urlencode "text=${msg}" \
    "https://api.telegram.org/bot${token}/sendMessage" >/dev/null
}

out=$(restic check --read-data-subset=5% 2>&1)
rc=$?

if [[ $rc -ne 0 ]]; then
  tail=$(echo "$out" | tail -20)
  send_telegram "Restic check FAILED on $(hostname) (rc=${rc})
${tail}" || true
  echo "$out" >&2
  exit "$rc"
fi

echo "$out"
exit 0
