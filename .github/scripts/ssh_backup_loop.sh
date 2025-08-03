#!/bin/bash
set -e

# Setup Git
git config --global user.name "Auto Bot"
git config --global user.email "auto@bot.com"
mkdir -p links

# Loop forever
LOOP=0
while true; do
  # Kill old tmate
  pkill tmate || true

  # Start fresh tmate session
  tmate -S /tmp/tmate.sock new-session -d
  sleep 5
  TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}')
  
  echo "$TMATE_SSH" > links/ssh.txt

  git add links/ssh.txt
  git commit -m "Updated SSH link $(date -u)"
  git push origin main
  echo "[SSH] New SSH link pushed at $(date -u): $TMATE_SSH"

  # Every 2 loops = every 30 minutes (15 min * 2)
  if (( LOOP % 2 == 0 )); then
    echo "[Backup] Starting backup at $(date -u)"
    cd server
    zip -r ../mcbackup.zip . >/dev/null
    aws --endpoint-url=https://s3.filebase.com s3 cp ../mcbackup.zip s3://$FILEBASE_BUCKET/mcbackup.zip
    echo "[Backup] Uploaded to Filebase at $(date -u)"
    cd ..
  fi

  LOOP=$((LOOP + 1))
  echo "[Loop] Waiting 15 minutes before next SSH refresh..."
  sleep 900  # 15 minutes
done
