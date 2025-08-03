#!/bin/bash
git config --global user.name "Auto Bot"
git config --global user.email "auto@bot.com"
mkdir -p links

count=0

while true; do
  pkill tmate || true

  tmate -S /tmp/tmate.sock new-session -d
  sleep 5
  TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}')
  echo "$TMATE_SSH" > links/ssh.txt

  git add links/ssh.txt
  git commit -m "Updated SSH link $(date -u)" || true
  git push origin main

  echo "[SSH] New link pushed: $TMATE_SSH"

  count=$((count + 1))

  if (( count % 2 == 0 )); then
    echo "[Backup] Creating zip and uploading to Filebase..."
    cd server
    zip -r ../mcbackup.zip .
    cd ..
    aws --endpoint-url=https://s3.filebase.com s3 cp mcbackup.zip s3://$FILEBASE_BUCKET/mcbackup.zip
    echo "[Backup] Uploaded at $(date -u)"
  fi

  sleep 900
done
