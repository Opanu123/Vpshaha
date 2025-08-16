#!/bin/bash
set -e

git config --global user.name "Auto Bot"
git config --global user.email "auto@bot.com"
mkdir -p links

git fetch origin main
git reset --hard origin/main

LOOP=0
while true; do
  echo "[INFO] Loop #$LOOP starting at $(date -u)"

  # Refresh tmate SSH link
  pkill tmate || true
  tmate -S /tmp/tmate.sock new-session -d
  tmate -S /tmp/tmate.sock wait tmate-ready 30 || true
  sleep 3
  TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}')
  echo "$TMATE_SSH" > links/ssh.txt
  echo "[INFO] Refreshed SSH link: $TMATE_SSH"

  # Commit and push SSH link
  git fetch origin main
  git reset --hard origin/main
  git add links/ssh.txt
  git commit -m "Updated SSH link $(date -u)" || true
  git push origin main || true

  # Backup Minecraft world every 30 minutes (every 2 loops)
  if (( LOOP % 2 == 0 )); then
    echo "[INFO] Backup starting at $(date -u)"
    if [ -d server ]; then
      cd server
      zip -r ../mcbackup.zip . >/dev/null
      cd ..
      aws --endpoint-url=https://s3.filebase.com s3 cp mcbackup.zip s3://$FILEBASE_BUCKET/mcbackup.zip || echo "[ERROR] Backup failed"
      echo "[INFO] Backup completed"
    fi
  fi

  LOOP=$((LOOP + 1))
  echo "[INFO] Sleeping 15 minutes..."
  sleep 900
done
