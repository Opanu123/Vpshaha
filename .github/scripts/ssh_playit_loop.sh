#!/bin/bash
set -e

# ------------------------------
# Setup Git for SSH & links
# ------------------------------
git config --global user.name "Auto Bot"
git config --global user.email "auto@bot.com"
mkdir -p links

git pull --rebase origin main || true

LOOP=0
while true; do

  # ------------------------------
  # Start/Restart Playit agent safely
  # ------------------------------
  pkill -f playit-linux-amd64 || true
  mkdir -p ~/.playit
  if [ -f .playit.toml ]; then
      cp .playit.toml ~/.playit/.playit.toml
  fi

  # Download new binary to temporary file
  TMP_BINARY="playit-linux-amd64.new"
  wget -q https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-linux-amd64 -O "$TMP_BINARY"
  chmod +x "$TMP_BINARY"

  # Replace old binary safely
  mv "$TMP_BINARY" playit-linux-amd64

  # Start agent in background
  nohup ./playit-linux-amd64 > playit.log 2>&1 &

  # Capture claim link if exists (only first time)
  sleep 5
  grep -o 'https://playit.gg/claim/[A-Za-z0-9]*' playit.log > links/playit_claim.txt || echo "No claim link found"

  # ------------------------------
  # Start/Restart tmate SSH
  # ------------------------------
  pkill tmate || true
  tmate -S /tmp/tmate.sock new-session -d
  sleep 5
  TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}')
  echo "$TMATE_SSH" > links/ssh.txt

  # Push updated links to repo
  git pull --rebase origin main || true
  git add links/ssh.txt links/playit_claim.txt
  git commit -m "Updated SSH & Playit claim link $(date -u)" || true
  git push origin main || true

  # ------------------------------
  # Backup every 30 mins (every 2 loops)
  # ------------------------------
  if (( LOOP % 2 == 0 )); then
    echo "[Backup] Starting backup at $(date -u)"
    cd server || exit 1
    zip -r ../mcbackup.zip . >/dev/null
    cd ..

    n=0
    until [ $n -ge 3 ]; do
      aws --endpoint-url=https://s3.filebase.com s3 cp mcbackup.zip s3://$FILEBASE_BUCKET/mcbackup.zip && break
      echo "[Backup] Upload failed. Retry in 30s..."
      sleep 30
      n=$((n+1))
    done

    if [ $n -eq 3 ]; then
      echo "[Backup] Failed to upload after 3 attempts!"
    else
      echo "[Backup] Uploaded to Filebase at $(date -u)"
    fi
  fi

  LOOP=$((LOOP + 1))
  echo "[LOOP] Sleeping 15 minutes before next refresh..."
  sleep 900
done
