#!/bin/bash
set -e

# -------------------------
# Git Setup
# -------------------------
git config --global user.name "Auto Bot"
git config --global user.email "auto@bot.com"
mkdir -p links

# Initial pull to avoid push rejection
git pull --rebase origin main || true

# -------------------------
# Playit Setup
# -------------------------
mkdir -p ~/.config/playit
PLAYIT_FILE=~/.config/playit/.playit.toml

# Download latest Playit agent
curl -L -o playit https://github.com/playit-cloud/playit-agent/releases/latest/download/playit_linux_amd64
chmod +x playit

# Wait for .playit.toml to appear (up to 5 minutes)
TIMEOUT=300  # 5 minutes
INTERVAL=5
ELAPSED=0
echo "[Playit] Waiting for .playit.toml in Filebase..."
while [ ! -f "$PLAYIT_FILE" ] && [ $ELAPSED -lt $TIMEOUT ]; do
    aws --endpoint-url=https://s3.filebase.com s3 cp s3://$FILEBASE_BUCKET/.playit.toml $PLAYIT_FILE 2>/dev/null || true
    if [ -f "$PLAYIT_FILE" ]; then
        echo "[Playit] Found .playit.toml!"
        break
    fi
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

[ ! -f "$PLAYIT_FILE" ] && echo "[Playit] No .playit.toml found after 5 minutes. Agent will start without claimed tunnel."

# Start Playit agent in background
nohup ./playit &

echo "[Playit] Agent started with config $(cat $PLAYIT_FILE 2>/dev/null || echo 'not found')"

# -------------------------
# Loop: tmate + backup
# -------------------------
LOOP=0
while true; do
  echo "[Loop] Starting loop iteration $LOOP at $(date -u)"

  # Kill old tmate if exists
  pkill tmate || true

  # Start new tmate session
  tmate -S /tmp/tmate.sock new-session -d
  sleep 5
  TMATE_SSH=$(tmate -S /tmp/tmate.sock display -p '#{tmate_ssh}')
  echo "$TMATE_SSH" > links/ssh.txt

  # Git: pull → add → commit → push
  git pull --rebase origin main || true
  git add links/ssh.txt
  git commit -m "Updated SSH link $(date -u)" || true
  git push origin main || true

  echo "[SSH] New SSH link pushed: $TMATE_SSH"

  # -------------------------
  # Backup every 30 mins (every 2 loops)
  # -------------------------
  if (( LOOP % 2 == 0 )); then
    echo "[Backup] Starting backup at $(date -u)"

    # Server backup
    cd server || mkdir -p server && cd server
    zip -r ../mcbackup.zip . >/dev/null
    cd ..

    # Upload backup with retry
    n=0
    until [ $n -ge 3 ]; do
      aws --endpoint-url=https://s3.filebase.com s3 cp mcbackup.zip s3://$FILEBASE_BUCKET/mcbackup.zip && break
      echo "[Backup] Upload failed. Retry in 30s..."
      sleep 30
      n=$((n+1))
    done
    [ $n -eq 3 ] && echo "[Backup] Failed to upload after 3 attempts!" || echo "[Backup] Uploaded server backup."

    # Upload Playit config
    aws --endpoint-url=https://s3.filebase.com s3 cp $PLAYIT_FILE s3://$FILEBASE_BUCKET/.playit.toml || echo "[Playit] Backup failed!"
    echo "[Playit] Config backed up to Filebase"
  fi

  LOOP=$((LOOP + 1))
  echo "[Loop] Sleeping 15 minutes before next refresh..."
  sleep 900
done
